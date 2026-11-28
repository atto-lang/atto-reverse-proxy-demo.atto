#!/usr/bin/env bash
# Negative source-only tests for the privileged frozen-source workflow contract.
# This checks reviewed text invariants, not GitHub's live protection or runner.
set -euo pipefail
if (( $# != 1 )); then echo 'usage: test-trusted-workflow-static-admission.sh forward|reverse' >&2; exit 2; fi
side="$1"
case "$side" in
  forward)
    repository_id=1429955596
    frozen_sha=fe46a4cac8c3cbedfaa5d872bc0e6348974141b5 ;;
  reverse)
    repository_id=1429954649
    frozen_sha=1a667fcd4481e3511e0cfa1008e855d96540c200 ;;
  *) echo 'invalid side' >&2; exit 2 ;;
esac
root="$(cd "$(dirname "$0")/.." && pwd -P)"
workflow="$root/.github/workflows/trusted-frozen-$side-native.yml"
test -f "$workflow" && test ! -L "$workflow"
tmp="$(/usr/bin/mktemp -d)"
trap '/usr/bin/rm -rf -- "$tmp"' EXIT
count_is() {
  local remaining="$1" literal="$2" expected="$3" count=0
  while [[ "$remaining" == *"$literal"* ]]; do
    remaining="${remaining#*"$literal"}"
    count=$((count+1))
  done
  [[ "$count" -eq "$expected" ]]
}
check_policy() {
  local file="$1" content trigger permissions_block job_names preflight native
  # Ignore comments: missing/disabled policy gates cannot be spoofed by comments.
  content="$(/usr/bin/awk '!/^[[:space:]]*#/ {print}' "$file")"
  # Stop at the next top-level section, not only permissions: the reverse
  # workflow legitimately puts defaults: between on: and permissions:.
  trigger="$(/usr/bin/awk '
    /^on:$/ {inside=1; next}
    inside && /^[^[:space:]#][^:]*:/ {exit}
    inside && /[^[:space:]]/ && !/^[[:space:]]*#/ {print}
  ' "$file")"
  [[ "$trigger" == '  workflow_dispatch:' ]] || return 1
  for section in on permissions jobs; do
    /usr/bin/awk -v key="$section:" '$0 == key {n++} END {exit(n == 1 ? 0 : 1)}' "$file" || return 1
  done
  permissions_block="$(/usr/bin/awk '
    /^permissions:$/ {inside=1; next}
    inside && /^[^[:space:]#][^:]*:/ {exit}
    inside && /[^[:space:]]/ && !/^[[:space:]]*#/ {print}
  ' "$file")"
  [[ "$permissions_block" == '  contents: read' ]] || return 1
  # A job-level permissions: block would override this restricted grant.
  ! /usr/bin/grep -Eq '^    permissions:' "$file" || return 1
  job_names="$(/usr/bin/awk '
    /^jobs:$/ {inside=1; next}
    inside && /^[^[:space:]#][^:]*:/ {exit}
    inside && /^  [[:alnum:]_-]+:[[:space:]]*$/ {print $1}
  ' "$file")"
  [[ "$job_names" == $'protected-main-preflight:\nnative-contracts:' ]] || return 1
  [[ "$(/usr/bin/grep -Ec '^    runs-on:' "$file" || true)" == 2 ]] || return 1
  [[ "$(/usr/bin/grep -Ec '^    runs-on: ubuntu-24[.]04$' "$file" || true)" == 1 ]] || return 1
  [[ "$(/usr/bin/grep -Ec '^    steps:' "$file" || true)" == 2 ]] || return 1
  [[ "$(/usr/bin/grep -Ec '^        uses:' "$file" || true)" == 1 ]] || return 1
  # Each independently admitted job must carry its own repo/ref/protection gate.
  preflight="$(/usr/bin/awk '/^  protected-main-preflight:$/ {inside=1} /^  native-contracts:$/ {exit} inside {print}' <<< "$content")"
  native="$(/usr/bin/awk '/^  native-contracts:$/ {inside=1} inside {print}' <<< "$content")"
  for guard in "github.repository_id == '$repository_id'" "github.ref == 'refs/heads/main'" 'github.ref_protected == true'; do
    count_is "$preflight" "$guard" 1 || return 1
    count_is "$native" "$guard" 1 || return 1
  done
  for var in LD_PRELOAD NODE_OPTIONS NODE_EXTRA_CA_CERTS GIT_CONFIG_GLOBAL; do
    count_is "$content" "$var:" 1 || return 1
  done
  count_is "$content" "  LD_PRELOAD: ''" 1 || return 1
  count_is "$content" "  NODE_OPTIONS: ''" 1 || return 1
  count_is "$content" "  NODE_EXTRA_CA_CERTS: ''" 1 || return 1
  count_is "$content" '  GIT_CONFIG_GLOBAL: /dev/null' 1 || return 1
  count_is "$content" '  contents: read' 1 || return 1
  count_is "$content" "github.repository_id == '$repository_id'" 2 || return 1
  count_is "$content" "github.ref == 'refs/heads/main'" 2 || return 1
  count_is "$content" 'github.ref_protected == true' 2 || return 1
  count_is "$content" 'needs: protected-main-preflight' 1 || return 1
  count_is "$content" 'group: oreslang-trusted-native' 1 || return 1
  count_is "$content" 'labels: [self-hosted, linux, x64, oreslang-jdk25]' 1 || return 1
  count_is "$content" "EXPECTED_SHA: '$frozen_sha'" 1 || return 1
  count_is "$content" 'APPROVED_ORESLANG_RUNTIME_MANIFEST_SHA256' 3 || return 1
  count_is "$content" 'actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09' 1 || return 1
  count_is "$content" '/opt/oreslang-approved/oreslang-runtime.manifest.sha256' 1 || return 1
  return 0
}
check_policy "$workflow" || { echo 'STATIC_ADMISSION_FAILURE: original workflow violates pinned text contract' >&2; exit 1; }
original="$(/usr/bin/cat -- "$workflow")"
rejected=0
mutate() {
  local label="$1" needle="$2" replacement="$3" remainder changed
  local expected=1
  case "$label" in
    repository-identity|unprotected-main|default-ref|comment-spoof-protection) expected=2 ;;
    missing-manifest-approval) expected=3 ;;
  esac
  count_is "$original" "$needle" "$expected" || {
    echo "MISSING_OR_AMBIGUOUS_SOURCE_ANCHOR: $label (expected $expected)" >&2
    exit 1
  }
  changed="${original/"$needle"/"$replacement"}"
  test "$original" != "$changed" || exit 1
  /usr/bin/printf '%s\n' "$changed" > "$tmp/mutant.yml"
  if check_policy "$tmp/mutant.yml"; then
    echo "STATIC_ADMISSION_FAILURE: unsafe mutation accepted: $label" >&2
    exit 1
  fi
  rejected=$((rejected+1))
  echo "STATIC_ADMISSION_MUTATION_REJECTED name=$label"
}
mutate pull-request-trigger $'on:\n  workflow_dispatch:' $'on:\n  pull_request:'
mutate pr-target-trigger $'on:\n  workflow_dispatch:' $'on:\n  pull_request_target:'
mutate permission-escalation '  contents: read' '  contents: write'
mutate repository-identity "github.repository_id == '$repository_id'" "github.repository_id == '0'"
mutate unprotected-main 'github.ref_protected == true' 'github.ref_protected == false'
mutate default-ref "github.ref == 'refs/heads/main'" "github.ref == 'refs/heads/feature'"
mutate omit-preflight 'needs: protected-main-preflight' 'needs: unrelated-job'
mutate unrestricted-runner 'group: oreslang-trusted-native' 'group: default'
mutate wrong-native-label 'labels: [self-hosted, linux, x64, oreslang-jdk25]' 'labels: [self-hosted, linux, x64]'
mutate frozen-commit-drift "EXPECTED_SHA: '$frozen_sha'" "EXPECTED_SHA: '0000000000000000000000000000000000000000'"
mutate missing-manifest-approval 'APPROVED_ORESLANG_RUNTIME_MANIFEST_SHA256' 'UNREVIEWED_ORESLANG_RUNTIME_MANIFEST'
mutate unpinned-checkout 'actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09' 'actions/checkout@v5'
mutate manifest-pin-drift '/opt/oreslang-approved/oreslang-runtime.manifest.sha256' '/tmp/oreslang-runtime.manifest.sha256'
# These mutations preserve the original guard *text* while introducing a
# second authorization path, privilege grant or comment-only spoof. A simple
# substring counter is insufficient to detect them.
mutate workflow-id-token '  contents: read' $'  contents: read\n  id-token: write'
mutate job-token-override '  native-contracts:' $'  native-contracts:\n    permissions:\n      id-token: write'
mutate third-job $'jobs:\n  protected-main-preflight:' $'jobs:\n  unreviewed-job:\n    runs-on: ubuntu-24.04\n    steps: []\n  protected-main-preflight:'
mutate hosted-runner-swap '    runs-on: ubuntu-24.04' '    runs-on: self-hosted'
mutate checkout-step-injection '        uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09' $'        uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09\n        uses: unreviewed/action@v1'
mutate loader-preload "  LD_PRELOAD: ''" '  LD_PRELOAD: /tmp/inject.so'
mutate loader-node-options "  NODE_OPTIONS: ''" '  NODE_OPTIONS: --require=/tmp/inject.js'
mutate job-env-loader '  native-contracts:' $'  native-contracts:\n    env:\n      LD_PRELOAD: /tmp/inject.so'
mutate comment-spoof-protection 'github.ref_protected == true' '# github.ref_protected == true'
mutate duplicate-permissions-mapping $'permissions:\n  contents: read' $'permissions:\n  contents: read\npermissions:\n  contents: read'
test "$rejected" -eq 23
echo "SOURCE_FREE_TRUSTED_WORKFLOW_STATIC_MUTATIONS_PASS rejected=$rejected native_guest=NOT_EXECUTED live_protection=NOT_VERIFIED"
