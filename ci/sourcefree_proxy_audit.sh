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
[[ -d .git && ! -L .git ]] || die 'expected real checkout'
for key in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE; do
  [[ -z "$(/usr/bin/printenv "$key" 2>/dev/null || true)" ]] || die "Git redirect: $key"
done
git_exact() {
  /usr/bin/git --no-replace-objects -c core.fsmonitor=false -c core.filemode=true \
    --git-dir="$ROOT/.git" --work-tree="$ROOT" "$@"
}
[[ "$(git_exact rev-parse --show-toplevel)" == "$ROOT" ]] || die 'Git root mismatch'
head="$(git_exact rev-parse --verify HEAD)"
[[ "$head" =~ ^[0-9a-f]{40}$ ]] || die 'invalid HEAD'
if [[ -n "$(/usr/bin/printenv EXPECTED_SHA 2>/dev/null || true)" ]]; then
  [[ "$head" == "$EXPECTED_SHA" ]] || die 'wrong exact head'
fi
git_exact diff --no-ext-diff --quiet HEAD -- || die 'modified tracked worktree'
git_exact diff --no-ext-diff --cached --quiet HEAD -- || die 'staged modifications'
[[ "$(git_exact ls-files --others -z | /usr/bin/wc -c)" -eq 0 ]] || die 'untracked/ignored files'
while IFS= read -r -d '' path; do
  case "$path" in
    *.[Pp][Yy]|*.[Pp][Yy][Ii]|*.[Ii][Pp][Yy][Nn][Bb])
      die "tracked Python forbidden: $path" ;;
  esac
done < <(git_exact ls-files -z)
pass 'no tracked Python source'
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
printf 'SOURCEFREE_PROXY_AUDIT_PASS checks=%s host_only=true; NATIVE_NOT_EXECUTED\n' "$count"
