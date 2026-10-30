#!/usr/bin/env bash
# Adversarial hermetic tests of the exact policy gate used in CI.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_repo="$(mktemp -d)"
trap 'rm -rf "$test_repo"' EXIT
git init -q "$test_repo"
git -C "$test_repo" config user.name "Policy test"
git -C "$test_repo" config user.email "policy@example.invalid"
mkdir -p "$test_repo/docs" "$test_repo/src"
printf '00_abc\n' > "$test_repo/src/hello.ores"
printf 'a%.0s' {1..40} > "$test_repo/SOURCE_REF"
printf '\n' >> "$test_repo/SOURCE_REF"
git -C "$test_repo" add .
check_ok() {
  SOURCE_POLICY_ROOT="$test_repo" SOURCE_POLICY_MODE="${1:-strict}" bash "$root/ci/source-policy.sh" > /dev/null
}
check_bad() {
  if SOURCE_POLICY_ROOT="$test_repo" SOURCE_POLICY_MODE="${1:-strict}" bash "$root/ci/source-policy.sh" > /dev/null 2>&1; then
    echo "TEST_FAILURE: expected source policy rejection" >&2; exit 1
  fi
}
check_ok
mkdir -p "$test_repo/nested space"
printf 'placeholder\n' > "$test_repo/nested space/unsafe.PY"
git -C "$test_repo" add .
check_bad
git -C "$test_repo" rm -q -f -- "nested space/unsafe.PY"
printf 'placeholder\n' > "$test_repo/src/escape.ipynb"
git -C "$test_repo" add .
check_bad
git -C "$test_repo" rm -q -f -- src/escape.ipynb
printf '#!/usr/bin/env python3\n' > "$test_repo/runner"
git -C "$test_repo" add .
check_bad
git -C "$test_repo" rm -q -f -- runner
ln -s hello.ores "$test_repo/src/alias.ores"
git -C "$test_repo" add .
check_bad
git -C "$test_repo" rm -q -f -- src/alias.ores
printf 'bad\n' > "$test_repo/SOURCE_REF"
git -C "$test_repo" add .
check_bad
printf 'a%.0s' {1..40} > "$test_repo/SOURCE_REF"
printf '\n' >> "$test_repo/SOURCE_REF"
git -C "$test_repo" add .
check_ok
mkdir -p "$test_repo/scripts"
printf 'legacy\n' > "$test_repo/scripts/benchmark.py"
git -C "$test_repo" add .
check_bad
check_ok rest-legacy
printf 'new\n' > "$test_repo/scripts/new_tool.py"
git -C "$test_repo" add .
check_bad rest-legacy
# Reset the earlier negative fixtures before testing valid-source baselines.
git -C "$test_repo" rm -q -f -- scripts/new_tool.py scripts/benchmark.py
check_ok
# A valid-looking but untracked SOURCE_REF cannot establish provenance.
git -C "$test_repo" rm -q --cached -- SOURCE_REF
check_bad
git -C "$test_repo" add SOURCE_REF
check_ok
# Optional SOURCE_REF cannot be replaced by a tracked symlink, even if its target is valid.
mv "$test_repo/SOURCE_REF" "$test_repo/saved_ref"
ln -s saved_ref "$test_repo/SOURCE_REF"
git -C "$test_repo" add -A
check_bad
rm "$test_repo/SOURCE_REF"
mv "$test_repo/saved_ref" "$test_repo/SOURCE_REF"
git -C "$test_repo" add -A
check_ok
# Symlinks are rejected regardless of file extension.
ln -s hello.ores "$test_repo/src/alias.txt"
git -C "$test_repo" add .
check_bad
git -C "$test_repo" rm -q -f -- src/alias.txt
check_ok
printf 'SOURCE_POLICY_NEGATIVE_TESTS_PASS scenarios=10\n'
