#!/usr/bin/env bash
set -euo pipefail
policy="${1:-./ci/attolang_source_policy.sh}"
policy="$(realpath "$policy")"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
new_repo(){ rm -rf "$scratch/repo"; mkdir -p "$scratch/repo/src" "$scratch/repo/tests" "$scratch/repo/bench"; cd "$scratch/repo"; git init -q; git config user.name test; git config user.email test@example.invalid; printf 'fnc main() {}\n' > src/main.atto; printf 'fnc contract() {}\n' > tests/basic_contract.atto; git add .; git commit -qm base; }
pass(){ "$policy" >/dev/null; printf 'PASS %s\n' "$1"; }
fail(){ if "$policy" >/dev/null 2>&1; then printf 'FAIL accepted %s\n' "$1" >&2; exit 1; fi; printf 'PASS rejected %s\n' "$1"; }
new_repo; pass canonical_atto_tree
new_repo; printf 'x\n' > src/legacy.ores; git add .; git commit -qm legacy; fail tracked_legacy_ores
new_repo; printf 'x\n' > tests/untracked.ores; fail untracked_legacy_ores
new_repo; ln -s main.atto src/legacy.ores; fail legacy_ores_symlink
new_repo; rm src/main.atto; ln -s ../tests/basic_contract.atto src/main.atto; fail symlinked_atto
new_repo; chmod +x src/main.atto; fail executable_mode_drift
new_repo; chmod g+w src/main.atto; fail writable_mode_drift
new_repo; printf '// mutated\n' >> src/main.atto; fail working_byte_drift
new_repo; ln src/main.atto src/alias.atto; git add src/alias.atto; git commit -qm hardlink; fail hardlinked_atto
new_repo; mkdir -p misc; printf 'x\n' > misc/misplaced.atto; git add .; git commit -qm misplaced; fail unexpected_atto_location
new_repo; rm src/main.atto; fail missing_tracked_atto
printf 'ATTOLANG_SOURCE_POLICY_TESTS_PASS=11/11\n'
