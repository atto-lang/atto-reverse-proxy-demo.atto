#!/usr/bin/env bash
# Starts only local fixture/baselines. Never starts or enables Oreslang egress.
set -euo pipefail
bench=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
for cmd in cargo nginx haproxy sha256sum timeout ps jq tr awk getconf; do
  command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 2; }
done
[[ -x /usr/bin/time ]] || { echo "Missing dependency: /usr/bin/time" >&2; exit 2; }
clk_tck=$(getconf CLK_TCK)
[[ "$clk_tck" =~ ^[0-9]+$ && "$clk_tck" -gt 0 ]] || { echo "Invalid CLK_TCK" >&2; exit 2; }
proc_ticks() {
  local pid=$1
  [[ -r "/proc/$pid/stat" ]] || return 1
  awk '{print $14 + $15}' "/proc/$pid/stat"
}
out=$(mktemp -d "${TMPDIR:-/tmp}/ores-proxy-bench.XXXXXXXX")
chmod 700 "$out"
mkdir "$out/config"
cp "$bench/nginx.conf" "$bench/haproxy.cfg" "$bench/oreslang.yaml" "$bench/rust-toolchain.toml" "$out/config/"
printf 'Results: %s\n' "$out"
if [[ -n "${ORESLANG_ADDR:-}" ]]; then
  [[ "${ORESLANG_RUNTIME_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || { echo 'Oreslang measurements require a 40-hex runtime source SHA' >&2; exit 2; }
  case "${ORESLANG_BACKEND:-}" in java-jit|java-native|llvm) ;; *) echo 'Set ORESLANG_BACKEND=java-jit, java-native or llvm' >&2; exit 2 ;; esac
fi
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT
mode=${BENCH_MODE:-smoke}
case "$mode" in
  smoke) requests=128; warmup=8; repeats=1; levels='1 8'; sizes='0 1024' ;;
  full) requests=10000; warmup=200; repeats=5; levels='1 16 64 256'; sizes='0 1024 65536' ;;
  *) echo 'BENCH_MODE must be smoke or full' >&2; exit 2 ;;
esac
# Restricted UID namespaces can exercise config/wire smoke without a worker UID
# transition. This is recorded and forbidden for full benchmark runs.
nginx_global='daemon off;'
if [[ "${BENCH_SANDBOX_SMOKE:-0}" == 1 ]]; then
  [[ "$mode" == smoke ]] || { echo 'Sandbox mode is smoke-only' >&2; exit 2; }
  nginx_global="daemon off; master_process off; user $(id -un) $(id -gn);"
fi
# Optional explicit, distinct CPU placement. Unpinned runs are exploratory.
proxy_cpu=${BENCH_PROXY_CPU:-}
load_cpu=${BENCH_LOAD_CPU:-}
origin_cpu=${BENCH_ORIGIN_CPU:-}
proxy_affinity=(); load_affinity=(); origin_affinity=()
if [[ -n "$proxy_cpu$load_cpu$origin_cpu" ]]; then
  command -v taskset >/dev/null
  for cpu in "$proxy_cpu" "$load_cpu" "$origin_cpu"; do
    [[ "$cpu" =~ ^[0-9]+$ ]] || { echo 'Supply all three numeric CPU IDs' >&2; exit 2; }
  done
  [[ "$proxy_cpu" != "$load_cpu" && "$proxy_cpu" != "$origin_cpu" && "$load_cpu" != "$origin_cpu" ]] || { echo 'CPU IDs must be distinct' >&2; exit 2; }
  proxy_affinity=(taskset -c "$proxy_cpu"); load_affinity=(taskset -c "$load_cpu"); origin_affinity=(taskset -c "$origin_cpu")
fi
if [[ "$mode" == full && -z "$proxy_cpu$load_cpu$origin_cpu" ]]; then
  echo 'Full benchmark mode requires distinct BENCH_PROXY_CPU, BENCH_LOAD_CPU and BENCH_ORIGIN_CPU values' >&2
  exit 2
fi
if [[ "$mode" == full && -r /sys/fs/cgroup/cpu.max ]]; then
  read -r quota period < /sys/fs/cgroup/cpu.max
  if [[ "$quota" != max ]]; then
    quota_cpus=$(awk -v q="$quota" -v p="$period" 'BEGIN { if (p <= 0) exit 2; printf "%.3f", q / p }')
    awk -v c="$quota_cpus" 'BEGIN { exit !(c >= 3.0) }' || {
      echo "Full benchmark mode requires at least 3 cgroup CPUs; quota is $quota_cpus" >&2
      exit 2
    }
  fi
fi
cargo build --manifest-path "$bench/driver/Cargo.toml" --release --locked
bin="$bench/driver/target/release/ores-proxy-bench"
source_sha=${BENCH_SOURCE_SHA:-$(git -C "$bench" rev-parse HEAD 2>/dev/null || true)}
[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'BENCH_SOURCE_SHA/source tree must be exactly 40 lowercase hex characters' >&2; exit 2; }
origin_nonce=$(tr -d '-' < /proc/sys/kernel/random/uuid)
[[ "$origin_nonce" =~ ^[0-9a-f]{32}$ ]] || { echo 'failed to generate origin nonce' >&2; exit 2; }
origin_nonce_hash=$(printf '%s' "$origin_nonce" | sha256sum)
origin_nonce_hash=${origin_nonce_hash%% *}
{
  printf 'source_sha=%s\n' "$source_sha"
  printf 'mode=%s\nconnection=close\nload=closed-loop\nproxy_cpu=%s\nload_cpu=%s\norigin_cpu=%s\n' "$mode" "${proxy_cpu:-UNPINNED}" "${load_cpu:-UNPINNED}" "${origin_cpu:-UNPINNED}"
  printf 'nginx_global=%s\n' "$nginx_global"
  printf 'origin_nonce_sha256=%s\n' "$origin_nonce_hash"
  printf 'cpu_max='
  cat /sys/fs/cgroup/cpu.max 2>/dev/null || printf 'UNAVAILABLE\n'
  printf 'cpu_governors='
  if compgen -G '/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor' >/dev/null; then
    cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u | tr '\n' ',' || true
    printf '\n'
  else
    printf 'UNAVAILABLE\n'
  fi
  printf 'cpu_boost='
  if [[ -r /sys/devices/system/cpu/cpufreq/boost ]]; then cat /sys/devices/system/cpu/cpufreq/boost
  elif [[ -r /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then cat /sys/devices/system/cpu/intel_pstate/no_turbo
  else printf 'UNAVAILABLE\n'; fi
  date -u; uname -a
  command -v lscpu >/dev/null && lscpu
  cargo --version; rustc --version
  nginx -V 2>&1; haproxy -vv
  sha256sum "$bench/summarize.jq" "$bench/driver/Cargo.lock" "$bin" "$(command -v nginx)" "$(command -v haproxy)" "$bench/nginx.conf" "$bench/haproxy.cfg" "$bench/run.sh"
  if command -v oreslang >/dev/null; then sha256sum "$(command -v oreslang)"; fi
  printf 'oreslang_backend=%s\n' "${ORESLANG_BACKEND:-NOT_PROVIDED}"
  printf 'oreslang_runtime_source_sha=%s\n' "${ORESLANG_RUNTIME_SHA:-NOT_PROVIDED}"
} > "$out/provenance.txt"
nginx -t -p "$out/" -c "$bench/nginx.conf" -g "$nginx_global" > "$out/nginx-check.log" 2>&1
haproxy -c -f "$bench/haproxy.cfg" > "$out/haproxy-check.log" 2>&1
"${origin_affinity[@]}" "$bin" origin 127.0.0.1:9090 "$origin_nonce" > "$out/origin.log" 2>&1 &
origin_pid=$!; pids+=("$origin_pid")
"${proxy_affinity[@]}" nginx -p "$out/" -c "$bench/nginx.conf" -g "$nginx_global" > "$out/nginx.log" 2>&1 &
nginx_pid=$!; pids+=("$nginx_pid")
"${proxy_affinity[@]}" haproxy -db -f "$bench/haproxy.cfg" > "$out/haproxy.log" 2>&1 &
haproxy_pid=$!; pids+=("$haproxy_pid")
# Readiness is a correctness request, not a fixed startup sleep.
for addr in 127.0.0.1:9090 127.0.0.1:9081 127.0.0.1:9082; do
  ready=0
  for attempt in {1..30}; do
    for pid in "${pids[@]}"; do kill -0 "$pid" || { echo "Fixture exited; inspect $out" >&2; exit 1; }; done
    if "$bin" run "$addr" forward 0 1 1 0 "$origin_nonce" > /dev/null 2>&1; then ready=1; break; fi
    sleep 0.1
  done
  [[ "$ready" == 1 ]] || { echo "Fixture failed readiness: $addr" >&2; exit 1; }
done
# Process snapshots are diagnostic RSS/current CPU, not peak or per-request CPU.
ps -p "$origin_pid,$nginx_pid,$haproxy_pid" --ppid "$nginx_pid" -o pid,ppid,rss,pcpu,comm > "$out/processes-before.txt" 2>&1 || echo "Process telemetry unavailable" > "$out/processes-before.txt"
failures=0
measure() {
  local label=$1 addr=$2 profile=$3 size=$4 c=$5 repeat=$6
  local name="$label-$profile-b$size-c$c-r$repeat"
  local origin_before origin_after
  origin_before=$(proc_ticks "$origin_pid") || { echo "Origin telemetry unavailable" >&2; exit 2; }
  if ! /usr/bin/time -f 'load_user_s=%U load_sys_s=%S load_maxrss_kb=%M' -o "$out/$name.time" \
      "${load_affinity[@]}" timeout 180 "$bin" run "$addr" "$profile" "$size" "$requests" "$c" "$warmup" "$origin_nonce" > "$out/$name.raw" 2> "$out/$name.log"; then
    jq -n --arg target "$label" --arg profile "$profile" --argjson bytes "$size" --argjson concurrency "$c" --argjson repeat "$repeat" \
      '{schema:1,status:"BLOCKED_OR_INVALID",metrics_comparable:false,target:$target,profile:$profile,bytes:$bytes,concurrency:$concurrency,repeat:$repeat}' > "$out/$name.json"
    failures=$((failures + 1))
  else
    origin_after=$(proc_ticks "$origin_pid") || { echo "Origin telemetry unavailable" >&2; exit 2; }
    local seconds load_user load_sys load_rss load_cpu_pct origin_cpu_pct
    seconds=$(jq -er '.seconds | select(. > 0)' "$out/$name.raw")
    load_user=$(awk -F= '$1=="load_user_s"{print $2}' "$out/$name.time")
    load_sys=$(awk -F= '$1=="load_sys_s"{print $2}' "$out/$name.time")
    load_rss=$(awk -F= '$1=="load_maxrss_kb"{print $2}' "$out/$name.time")
    [[ "$load_user" =~ ^[0-9]+([.][0-9]+)?$ && "$load_sys" =~ ^[0-9]+([.][0-9]+)?$ && "$load_rss" =~ ^[0-9]+$ ]] || {
      echo "Invalid load-generator telemetry for $name" >&2
      exit 2
    }
    load_cpu_pct=$(awk -v u="$load_user" -v y="$load_sys" -v s="$seconds" 'BEGIN { printf "%.3f", ((u + y) / s) * 100.0 }')
    origin_cpu_pct=$(awk -v a="$origin_before" -v b="$origin_after" -v hz="$clk_tck" -v s="$seconds" 'BEGIN { printf "%.3f", (((b - a) / hz) / s) * 100.0 }')
    jq --arg target "$label" --argjson repeat "$repeat" --argjson load_cpu_pct "$load_cpu_pct" \
      --argjson load_maxrss_kb "$load_rss" --argjson origin_cpu_pct "$origin_cpu_pct" \
      '. + {target:$target,repeat:$repeat,load_cpu_pct:$load_cpu_pct,load_maxrss_kb:$load_maxrss_kb,origin_cpu_pct:$origin_cpu_pct}' \
      "$out/$name.raw" > "$out/$name.json"
  fi
}
# Rotate target order per repeat to reduce systematic order/thermal bias.
for ((repeat=1; repeat<=repeats; repeat++)); do
  if (( repeat % 2 )); then targets='direct nginx haproxy'; else targets='haproxy nginx direct'; fi
  for c in $levels; do
    for label in $targets; do
      case "$label" in direct) addr=127.0.0.1:9090 ;; nginx) addr=127.0.0.1:9081 ;; haproxy) addr=127.0.0.1:9082 ;; esac
      for size in $sizes; do measure "$label" "$addr" forward "$size" "$c" "$repeat"; done
      if [[ "$label" != direct ]]; then measure "$label" "$addr" ingress 0 "$c" "$repeat"; fi
    done
    if [[ -n "${ORESLANG_ADDR:-}" ]]; then
      measure oreslang "$ORESLANG_ADDR" ingress 0 "$c" "$repeat"
      for size in $sizes; do measure oreslang "$ORESLANG_ADDR" forward "$size" "$c" "$repeat"; done
    fi
  done
done
if [[ -z "${ORESLANG_ADDR:-}" ]]; then
  printf '{"schema":1,"status":"NOT_EXECUTED","reason":"no_oreslang_listener_supplied"}\n' > "$out/oreslang-status.json"
  if [[ "${REQUIRE_ORESLANG:-0}" == 1 ]]; then failures=$((failures+1)); fi
fi
printf '{"schema":1,"status":"NOT_IMPLEMENTED","reason":"no_authenticated_CONNECT_relay_in_oreslang_demo","metrics_comparable":false}\n' > "$out/connect-status.json"
ps -p "$origin_pid,$nginx_pid,$haproxy_pid" --ppid "$nginx_pid" -o pid,ppid,rss,pcpu,comm > "$out/processes-after.txt" 2>&1 || echo "Process telemetry unavailable" > "$out/processes-after.txt"
jq -s -f "$bench/summarize.jq" "$out"/*-r*.json > "$out/summary.json"
if [[ "$mode" == full ]] && ! jq -e '.capacity_gate_passed == true' "$out/summary.json" >/dev/null; then
  echo 'Direct-origin capacity gate failed; full-run proxy metrics are not publishable' >&2
  failures=$((failures + 1))
fi
printf 'Failures/blocked cases: %s\nResults: %s\n' "$failures" "$out"
(( failures == 0 ))
