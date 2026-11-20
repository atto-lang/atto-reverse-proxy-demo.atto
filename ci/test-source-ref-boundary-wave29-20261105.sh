#!/usr/bin/env bash
# Source-policy negative controls only; no guest execution or proxy certification.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

git init -q "$fixture"
git -C "$fixture" config user.name "Host test"
git -C "$fixture" config user.email "host@example.invalid"
mkdir -p "$fixture/src"
printf 'pub routine main(): void { return; }\n' > "$fixture/src/main.ores"
printf 'a%.0s' {1..40} > "$fixture/SOURCE_REF"
printf '\n' >> "$fixture/SOURCE_REF"
git -C "$fixture" add .
git -C "$fixture" commit -qm "pinned host fixture"
head_sha="$(git -C "$fixture" rev-parse HEAD)"

check_ok() {
  SOURCE_POLICY_ROOT="$fixture" EXPECTED_DEMO_SHA="$head_sha" \
    bash "$repo/ci/source-policy.sh" > "$fixture/out" 2>&1
  grep -Fq SOURCE_POLICY_STRUCTURAL_PASS "$fixture/out"
  grep -Fq NOT_EXECUTED "$fixture/out"
}
check_bad() {
  if SOURCE_POLICY_ROOT="$fixture" EXPECTED_DEMO_SHA="$head_sha" \
    bash "$repo/ci/source-policy.sh" > "$fixture/out" 2>&1; then
    printf 'HOST_POLICY_MUTATION_MISSED: %s\n' "$1" >&2
    exit 1
  fi
  grep -Fq POLICY_FAILURE "$fixture/out"
}
restore_ref() {
  rm -f -- "$fixture/SOURCE_REF"
  printf 'a%.0s' {1..40} > "$fixture/SOURCE_REF"
  printf '\n' >> "$fixture/SOURCE_REF"
  chmod 644 "$fixture/SOURCE_REF"
  git -C "$fixture" add SOURCE_REF
}

check_ok
printf 'A%.0s' {1..40} > "$fixture/SOURCE_REF"
printf '\n' >> "$fixture/SOURCE_REF"
git -C "$fixture" add SOURCE_REF
check_bad uppercase_source_ref
restore_ref
check_ok

printf 'a%.0s' {1..40} > "$fixture/SOURCE_REF"
git -C "$fixture" add SOURCE_REF
check_bad missing_final_newline
restore_ref
check_ok

printf 'a%.0s' {1..40} > "$fixture/SOURCE_REF"
printf '\n\n' >> "$fixture/SOURCE_REF"
git -C "$fixture" add SOURCE_REF
check_bad extra_line
restore_ref
check_ok

chmod 755 "$fixture/SOURCE_REF"
git -C "$fixture" add SOURCE_REF
check_bad executable_ref
restore_ref
check_ok

rm -- "$fixture/SOURCE_REF"
ln -s src/main.ores "$fixture/SOURCE_REF"
git -C "$fixture" add SOURCE_REF
check_bad symlink_ref
restore_ref
check_ok

if SOURCE_POLICY_ROOT="$fixture" EXPECTED_DEMO_SHA="$(printf '0%.0s' {1..40})" \
  bash "$repo/ci/source-policy.sh" > "$fixture/out" 2>&1; then
  echo "HOST_POLICY_MUTATION_MISSED: mismatched expected head" >&2
  exit 1
fi
check_ok
printf 'HOST_ONLY_SOURCE_REF_BOUNDARY_PASS negatives=6; NOT_COMPILER_EXECUTION\n'
