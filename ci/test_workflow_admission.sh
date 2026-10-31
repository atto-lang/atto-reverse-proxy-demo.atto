#!/usr/bin/env bash
# Source-only negative tests for trusted actor-wire admission. No guest launch.
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
validate() {
  local file="$1" clean a b c
  [[ -f "$file" && ! -L "$file" ]] || return 1
  clean="$(/usr/bin/grep -Ev '^[[:space:]]*#' "$file")" || return 1
  /usr/bin/grep -Fq '  workflow_dispatch:' <<< "$clean" || return 1
  if /usr/bin/grep -Eq '^[[:space:]]+pull_request(_target)?:' <<< "$clean"; then return 1; fi
  /usr/bin/grep -Fq 'needs: hosted-preflight' <<< "$clean" || return 1
  /usr/bin/grep -Fq 'github.ref_protected == true' <<< "$clean" || return 1
  /usr/bin/grep -Fq 'group: oreslang-trusted-native' <<< "$clean" || return 1
  /usr/bin/grep -Fq 'APPROVED_ORESLANG_RUNTIME_MANIFEST_SHA256' <<< "$clean" || return 1
  /usr/bin/grep -Fq 'set-safe-directory: false' <<< "$clean" || return 1
  /usr/bin/grep -Fq -- '--allow-net=127.0.0.1:8080' <<< "$clean" || return 1
  if /usr/bin/grep -Fq -- '--allow-all' <<< "$clean"; then return 1; fi
  a="$(/usr/bin/grep -nF -m1 -- 'Recheck protected private main before source checkout' "$file" | /usr/bin/cut -d : -f 1)" || return 1
  b="$(/usr/bin/grep -nF -m1 -- 'Checkout exact protected-main commit' "$file" | /usr/bin/cut -d : -f 1)" || return 1
  c="$(/usr/bin/grep -nF -m1 -- 'Verify trusted exact source and approved native runtime' "$file" | /usr/bin/cut -d : -f 1)" || return 1
  [[ "$a" -lt "$b" && "$b" -lt "$c" ]] || return 1
  return 0
}
candidate='.github/workflows/actor-ingress-wire.yml'
validate "$candidate" || { echo 'SOURCEFREE_FAIL: current actor wire gate is unsafe' >&2; exit 1; }
echo 'SOURCEFREE_WORKFLOW_BASELINE_PASS'
tmp="$(/usr/bin/mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cp "$candidate" "$tmp/clean"
cases=0
deny_mutation() {
  local label="$1" prior="$2" replacement="$3"
  cp "$tmp/clean" "$tmp/mutated"
  /usr/bin/sed -i "s|$prior|$replacement|" "$tmp/mutated"
  if /usr/bin/cmp -s "$tmp/clean" "$tmp/mutated"; then
    echo "SOURCEFREE_FAIL: mutation did not apply ($label)" >&2; exit 1
  fi
  if validate "$tmp/mutated"; then
    echo "SOURCEFREE_FAIL: unsafe mutation accepted ($label)" >&2; exit 1
  fi
  cases=$((cases+1))
  echo "PASS negative workflow mutation: $label"
}
deny_mutation 'remove dispatch trigger' 'workflow_dispatch:' 'untrusted_event:'
deny_mutation 'remove protected ref check' 'github.ref_protected == true' 'github.ref_protected == false'
deny_mutation 'remove hosted dependency' 'needs: hosted-preflight' 'needs: disabled-preflight'
deny_mutation 'broaden runner group' 'group: oreslang-trusted-native' 'group: unrestricted'
deny_mutation 'drop manifest requirement' 'APPROVED_ORESLANG_RUNTIME_MANIFEST_SHA256' 'UNAPPROVED_MANIFEST'
deny_mutation 'disable checkout safety' 'set-safe-directory: false' 'set-safe-directory: true'
deny_mutation 'unrestrict client network' '--allow-net=127.0.0.1:8080' '--allow-all'
deny_mutation 'remove pre-checkout authorization' 'Recheck protected private main before source checkout' 'Skip authentication'
# Test an added PR trigger, rather than merely replacing an existing field.
cp "$tmp/clean" "$tmp/mutated"
/usr/bin/sed -i '/^on:$/a\  pull_request:' "$tmp/mutated"
if validate "$tmp/mutated"; then
  echo 'SOURCEFREE_FAIL: PR trigger accepted' >&2; exit 1
fi
cases=$((cases+1))
echo 'PASS negative workflow mutation: PR trigger'
printf 'SOURCEFREE_WORKFLOW_NEGATIVE_PASS cases=%d host_only=true\n' "$cases"
