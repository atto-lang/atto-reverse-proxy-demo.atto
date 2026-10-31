#!/usr/bin/env bash
# Host-only structural regressions. Not an Oreslang compiler or network test.
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
count=0
die() { echo "SOURCE_AUDIT_FAILURE: $*" >&2; exit 1; }
pass() { count=$((count + 1)); printf 'PASS source-only: %s\n' "$1"; }
regular() {
  [[ -f "$1" && ! -L "$1" ]] || die "missing/nonregular/linked $1"
  [[ "$(/usr/bin/realpath -e -- "$1")" == "$ROOT/$1" ]] || die "symlink ancestor $1"
}
has() {
  regular "$1"
  /usr/bin/grep -Fq -- "$2" "$1" || die "missing $3"
  pass "$3"
}
absent() {
  regular "$1"
  if /usr/bin/grep -Fq -- "$2" "$1"; then die "forbidden $3"; fi
  pass "$3"
}
ordered() {
  regular "$1"
  local first second
  first="$(/usr/bin/grep -nF -m 1 -- "$2" "$1" | /usr/bin/cut -d : -f 1)" || die "missing guard $4"
  second="$(/usr/bin/grep -nF -m 1 -- "$3" "$1" | /usr/bin/cut -d : -f 1)" || die "missing disposition $4"
  [[ "$first" -lt "$second" ]] || die "bad guard ordering $4"
  pass "$4"
}
selftest() {
  local file
  file="$(/usr/bin/mktemp)"
  trap 'rm -f -- "$file"' EXIT
  /usr/bin/printf 'first\nsecond\n' > "$file"
  /usr/bin/grep -Fq first "$file" || die 'positive grep'
  if /usr/bin/grep -Fq missing "$file"; then die 'negative grep'; fi
  [[ "$(/usr/bin/grep -nF -m 1 first "$file" | /usr/bin/cut -d : -f 1)" -lt "$(/usr/bin/grep -nF -m 1 second "$file" | /usr/bin/cut -d : -f 1)" ]] || die 'ordering'
  /usr/bin/ln -s "$file" "$file.link"
  [[ -L "$file.link" ]] || die 'symlink'
  /usr/bin/rm -f -- "$file.link"
  echo 'SOURCEFREE_BASH_SELFTEST_PASS cases=4 host_only=true'
}
if [[ "$#" -eq 1 && "$1" == --self-test ]]; then selftest; exit 0; fi
[[ "$#" -eq 0 ]] || die 'usage: sourcefree_proxy_audit.sh [--self-test]'
# Centralized Git identity and ignored-file authority checks are exercised
# independently by ci/test_source_checkout_integrity.sh.
regular ci/source_checkout_integrity.sh
bash ci/source_checkout_integrity.sh
pass 'checkout integrity including ignored and nonignored paths'
regular ci/oreslang-files.txt
regular ci/pure-contracts.txt
for dir in src tests; do
  [[ -d "$dir" && ! -L "$dir" ]] || die "linked/missing directory $dir"
  special="$(/usr/bin/find "$dir" ! -type d ! -type f -print -quit)" || die 'find object scan failed'
  [[ -z "$special" ]] || die "symlink or special Oreslang source object: $special"
done
pass 'source dirs have no special or symlink objects'
tmp="$(/usr/bin/mktemp)"
trap 'rm -f -- "$tmp"' EXIT
/usr/bin/find src tests -type f -name '*.ores' -print | /usr/bin/sort > "$tmp"
/usr/bin/diff -u ci/oreslang-files.txt "$tmp" >/dev/null || die 'source manifest differs'
pass 'complete sorted source manifest'
/usr/bin/find tests -maxdepth 1 -type f -name '*_contract.ores' -print | /usr/bin/sort > "$tmp"
/usr/bin/diff -u ci/pure-contracts.txt "$tmp" >/dev/null || die 'standalone manifest differs'
pass 'complete standalone manifest'
has ci/pure-contracts.txt tests/lexical_admission_contract.ores 'lexical negative retained'
has ci/pure-contracts.txt tests/network_admission_contract.ores 'predial negative retained'
absent ci/pure-contracts.txt tests/actor_ingress_tcp_smoke.ores 'TCP test not misclassified pure'
has src/proxy_yaml.ores 'import module admission_text from "./admission_text";' 'YAML lexical import'
has src/proxy_yaml.ores 'import module header_policy from "./header_policy";' 'header policy import'
ordered src/proxy_yaml.ores '!admission_text.control_free(original)' 'if line == "" || line.starts_with("#")' 'control check before comments'
has src/proxy_yaml.ores 'without_spaces.trim() != without_spaces' 'nonascii whitespace guard'
has src/proxy_yaml.ores 'final_label_has_letter = letters != ""' 'DNS final-letter requirement'
has src/proxy_yaml.ores '!header_policy.request_copy(header, "", "")' 'middleware header restriction'
has src/service_bindings.ores 'network-capable actor image forbidden on public ingress route' 'no-net actor registration'
has src/service_bindings.ores 'pub fnc local_dispatch_allowed' 'actor service authorization'
has src/service_bindings.ores 'binding.epoch == snapshot.epoch' 'actor generation receipt'
has src/service_bindings.ores 'binding.name == expected_name' 'actor service-name fence'
has src/service_bindings.ores 'binding.target == expected_target' 'actor code-image fence'
has src/service_bindings.ores 'binding.abi == expected_abi' 'actor ABI fence'
has src/serve_reverse.ores 'dispatch_receipt_valid(' 'actor validates its own receipt'
has src/serve_reverse.ores 'service_bindings.local_dispatch_allowed' 'caller checks receipt'
has src/serve_reverse.ores 'if request.method != "GET"; then' 'HEAD refused'
has src/serve_reverse.ores 'http.listen("127.0.0.1", 8080, 1024, 65536, 30000)' 'bounded loopback ingress'
absent src/serve_reverse.ores network.connect_async 'no outbound socket in guest listener'
absent src/serve_reverse.ores http.request 'no outbound HTTP in guest listener'
has src/network_admission.ores 'middleware admission receipt required before upstream egress' 'predial middleware receipt gate'
ordered src/network_admission.ores 'if route.middleware != ""; then' 'if route.upstream != endpoint.origin' 'middleware before network authorization'
absent src/network_admission.ores network.connect 'predial module does not connect'
has src/backend_pools.ores 'return plan.epoch == snapshot.epoch;' 'pool generation fence'
has src/backend_pools.ores 'middleware receipt required before reverse pool planning' 'pool middleware fence'
absent src/backend_pools.ores http.request 'pool cannot request network'
has tests/service_bindings_contract.ores 'same-image service alias escaped identity fence' 'alias identity regression'
has tests/backend_pools_contract.ores 'FAIL stale pool plan generation fence' 'stale pool regression'
has tests/network_admission_contract.ores 'FAIL route middleware was bypassed' 'predial middleware regression'
has tests/actor_ingress_tcp_smoke.ores 'X-Oreslang-Dispatch-Receipt: verified' 'TCP actor receipt'
has tests/actor_ingress_tcp_smoke.ores 'FAIL streaming actor HTTP chunked headers' 'TCP chunked header denial'
has tests/actor_ingress_tcp_smoke.ores 'FAIL streaming body order or terminating chunk' 'TCP chunk order'
has tests/actor_ingress_tcp_smoke.ores 'FAIL encoded noncanonical path not refused' 'TCP encoded traversal'
has tests/actor_ingress_tcp_smoke.ores 'FAIL actor service did not recover after disconnected streams' 'TCP disconnect recovery'
has config/worker-example.yaml 'streaming-route' 'streaming configuration'
has .github/workflows/native-contracts.yml 'Refuse legacy native admission' 'retired native CI denies'
absent .github/workflows/native-contracts.yml 'runs-on: [self-hosted' 'no PR native runner'
has .github/workflows/actor-ingress-wire.yml 'needs: hosted-preflight' 'governance job dependency'
has .github/workflows/actor-ingress-wire.yml 'group: oreslang-trusted-native' 'restricted runner group'
has .github/workflows/actor-ingress-wire.yml 'Recheck protected private main before source checkout' 'authorization before checkout'
has .github/workflows/actor-ingress-wire.yml 'APPROVED_ORESLANG_RUNTIME_MANIFEST_SHA256' 'approved native runtime manifest'
has .github/workflows/actor-ingress-wire.yml '--allow-net=127.0.0.1:8080' 'loopback-only native client'
absent .github/workflows/actor-ingress-wire.yml 'runs-on: [self-hosted' 'no unrestricted native runner'
# Retain high-value lexical/header/pool/middleware assertions from the
# retired Python checker. These are structural, not native guest evidence.
for n in $(/usr/bin/seq 0 31) 127; do
  printf -v token '\\u%04x' "$n"
  /usr/bin/grep -Fq -- "$token" src/admission_text.ores ||
    die "C0/DEL literal missing in lexical guard: $n"
done
pass 'all 32 C0 plus DEL literals are in shared lexical guard'
has src/header_policy.ores 'return admission_text.control_free(value)' 'complete header-value control filter'
has src/header_policy.ores 'for (const original of connection_tokens.split_literal' 'connection nomination full token list'
has src/header_policy.ores 'Only ASCII SP' 'connection token ASCII normalization'
has src/header_policy.ores 'return !matched' 'connection nomination deny on match'
has tests/backend_pools_contract.ores 'weighted-round-robin' 'weighted pool fixture'
has tests/backend_pools_contract.ores 'FAIL deterministic backend rotation' 'backend deterministic rotation negative'
has tests/backend_pools_contract.ores 'FAIL unknown backend pool' 'unknown pool rejected'
has tests/service_bindings_contract.ores 'gated_documents.add(gated_deny)' 'actor middleware deny fixture'
has tests/service_bindings_contract.ores 'kind: require_header' 'actor required-header fixture'
has tests/service_bindings_contract.ores 'kind: trace' 'actor trace fixture'
has tests/service_bindings_contract.ores 'FAIL middleware-gated service route escaped admission' 'actor middleware regression oracle'
has tests/network_admission_contract.ores 'middleware: denied' 'predial deny route fixture'
has tests/network_admission_contract.ores 'middleware: token' 'predial required-header route fixture'
has tests/network_admission_contract.ores '/deny/request' 'predial denial path'
has tests/network_admission_contract.ores '/required/request' 'predial header requirement path'
for entry in 'workers|streaming-route' 'streaming-route|unregistered-route' 'unregistered-route|origin'; do
  IFS='|' read -r start stop <<< "$entry"
  /usr/bin/awk -v start="$start" -v stop="$stop" '
    $0 == "  - name: " start {within=1; found=1; next}
    $0 == "  - name: " stop {if(within) exit 0}
    within && /middleware:/ {exit 2}
    END {if(!found) exit 3}
  ' config/worker-example.yaml || die "actor route middleware must remain unavailable: $start"
done
pass 'all three actor service routes are middleware-free'
has tests/actor_ingress_tcp_smoke.ores 'HEAD /actor HTTP/1.1' 'actor HEAD refusal fixture'
has tests/actor_ingress_tcp_smoke.ores 'HEAD /stream HTTP/1.1' 'stream HEAD refusal fixture'
has tests/actor_ingress_tcp_smoke.ores 'starts_with("HTTP/1.1 405")' 'actor HEAD 405 verdict'
printf 'SOURCEFREE_PROXY_AUDIT_PASS checks=%s host_only=true; NATIVE_NOT_EXECUTED\n' "$count"
