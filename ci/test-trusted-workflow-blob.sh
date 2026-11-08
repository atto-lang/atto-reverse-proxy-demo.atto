#!/usr/bin/env bash
# Source-only workflow identity check. This is NOT live Github branch/runner
# authorization and does not prove compiler/guest execution.
# Reviewed SHA-1 Git blob pins are intentionally literal and require independent
# re-review whenever privileged workflow bytes change.
set -euo pipefail
if (( $# != 1 )); then
  echo 'usage: test-trusted-workflow-blob.sh forward|reverse' >&2
  exit 2
fi
root="$(cd "$(dirname "$0")/.." && pwd -P)"
case "$1" in
  forward)
    workflow="$root/.github/workflows/trusted-frozen-forward-native.yml"
    expected_blob='a1d1af6bd6786b2abc456ae9fd30ee892775f969' ;;
  reverse)
    workflow="$root/.github/workflows/trusted-frozen-reverse-native.yml"
    expected_blob='46b07f2ca60b742e03b0a28ac5736a5be1df68ff' ;;
  *) echo 'invalid workflow side' >&2; exit 2 ;;
esac
test -f "$workflow" && test ! -L "$workflow" && test -x /usr/bin/git
tmp="$(/usr/bin/mktemp -d)" || exit 2
trap '/usr/bin/rm -rf -- "$tmp"' EXIT
blob() {
  # Hash the actual file bytes, not the Git index or a working-tree cache.
  /usr/bin/git hash-object --no-filters --stdin < "$1"
}
admit_blob() {
  [[ "$(blob "$1")" == "$expected_blob" ]]
}
admit_blob "$workflow" || {
  echo 'TRUSTED_WORKFLOW_BLOB_MISMATCH: privileged workflow changed; independent review required' >&2
  exit 1
}
original="$(/usr/bin/cat -- "$workflow")"
# Prevent vacuous negative results caused by changing terminal newlines when
# reconstructing mutant files with Bash command substitution.
printf '%s\n' "$original" > "$tmp/reconstructed.yml"
admit_blob "$tmp/reconstructed.yml" || {
  echo 'TEST_FAILURE: baseline workflow bytes could not be reconstructed exactly' >&2
  exit 1
}
rejected=0
mutate() {
  local name="$1" needle="$2" replacement="$3" suffix changed
  [[ "$original" == *"$needle"* ]] || {
    echo "TEST_FAILURE: mutation anchor missing: $name" >&2; exit 1
  }
  suffix="${original#*"$needle"}"
  [[ "$suffix" != *"$needle"* ]] || {
    echo "TEST_FAILURE: mutation anchor not unique: $name" >&2; exit 1
  }
  changed="${original/"$needle"/"$replacement"}"
  [[ "$changed" != "$original" ]] || exit 1
  # Each mutant retains the original trusted-ref and runner-group sentinels.
  # These are integrity-drift tests rather than alternate workflow semantics.
  [[ "$changed" == *"github.ref_protected == true"* ]] || exit 1
  [[ "$changed" == *"group: oreslang-trusted-native"* ]] || exit 1
  printf '%s\n' "$changed" > "$tmp/mutant.yml"
  if admit_blob "$tmp/mutant.yml"; then
    echo "TEST_FAILURE: modified trusted workflow passed identity pin: $name" >&2
    exit 1
  fi
  rejected=$((rejected + 1))
  echo "TRUSTED_WORKFLOW_BYTE_DRIFT_REJECTED name=$name"
}
mutate disable-tls-verification "  NODE_TLS_REJECT_UNAUTHORIZED: '1'" "  NODE_TLS_REJECT_UNAUTHORIZED: '0'"
mutate mutable-git-system-config '  GIT_CONFIG_SYSTEM: /dev/null' '  GIT_CONFIG_SYSTEM: /tmp/unsafe-gitconfig'
mutate injected-java-tool-options "  JAVA_TOOL_OPTIONS: ''" "  JAVA_TOOL_OPTIONS: '-javaagent:/tmp/unsafe.jar'"
mutate injected-git-config-parameters "  GIT_CONFIG_PARAMETERS: ''" "  GIT_CONFIG_PARAMETERS: 'core.hooksPath=/tmp/hooks'"
mutate remove-native-timeout '    timeout-minutes: 20' '    timeout-minutes: 999'
mutate persist-checkout-credentials '          persist-credentials: false' '          persist-credentials: true'
mutate insert-preflight-command "          echo 'effective_main_review_rules=true'" $'          echo '\''effective_main_review_rules=true'\''\n          echo UNREVIEWED_PREFLIGHT_COMMAND'
mutate inject-native-shell-step '      - name: Compile complete frozen Oreslang source inventory' $'      - name: Unreviewed native command\n        run: echo UNREVIEWED_NATIVE_COMMAND\n      - name: Compile complete frozen Oreslang source inventory'
test "$rejected" -eq 8 || exit 1
echo "SOURCE_FREE_TRUSTED_WORKFLOW_BLOB_TESTS_PASS rejected=$rejected native_guest=NOT_EXECUTED live_protection=NOT_VERIFIED"
