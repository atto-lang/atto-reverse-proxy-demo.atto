#!/usr/bin/env bash
set -euo pipefail
policy="${1:-./ci/attolang_source_policy.sh}"
policy="$(realpath "$policy")"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

new_repo() {
  rm -rf "$scratch/repo"
  mkdir -p "$scratch/repo/src" "$scratch/repo/tests" "$scratch/repo/bench"
  cd "$scratch/repo"
  git init -q
  git config user.name test
  git config user.email test@example.invalid
  printf 'fnc main() {}\n' > src/main.atto
  printf 'fnc contract() {}\n' > tests/basic_contract.atto
  git add .
  git commit -qm base
}
expect_pass() { "$policy" >/dev/null; printf 'PASS %s\n' "$1"; }
expect_fail() { if "$policy" >/dev/null 2>&1; then echo "FAIL accepted $1" >&2; exit 1; fi; printf 'PASS rejected %s\n' "$1"; }

new_repo; expect_pass canonical_atto_tree
new_repo; printf 'fnc legacy() {}\n' > src/legacy.ores; git add src/legacy.ores; git commit -qm legacy; expect_fail tracked_legacy_ores
new_repo; printf 'fnc legacy() {}\n' > tests/untracked.ores; expect_fail untracked_legacy_ores
new_repo; rm src/main.atto; ln -s ../tests/basic_contract.atto src/main.atto; expect_fail symlinked_atto
new_repo; chmod +x src/main.atto; expect_fail executable_mode_drift
new_repo; printf '// mutated\n' >> src/main.atto; expect_fail working_byte_drift
new_repo; mkdir -p misc; printf 'fnc misplaced() {}\n' > misc/misplaced.atto; git add misc/misplaced.atto; git commit -qm misplaced; expect_fail unexpected_atto_location
printf 'ATTOLANG_SOURCE_POLICY_TESTS_PASS=7/7\n'
