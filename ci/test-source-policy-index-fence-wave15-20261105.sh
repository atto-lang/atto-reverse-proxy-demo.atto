#!/usr/bin/env bash
# Source-only index/HEAD admission tests; no native reverse proxy execution.
set -euo pipefail
source_root="$(cd "$(dirname "$0")/.." && pwd -P)"
test_repo="$(mktemp -d)"
trap 'rm -rf -- "$test_repo"' EXIT
git init -q "$test_repo"
git -C "$test_repo" config user.name 'Source policy fixture'
git -C "$test_repo" config user.email 'fixture@example.invalid'
mkdir -p "$test_repo/src"
printf 'owned actor\n' > "$test_repo/src/worker.ores"
printf 'a%.0s' {1..40} > "$test_repo/SOURCE_REF"
printf '\n' >> "$test_repo/SOURCE_REF"
git -C "$test_repo" add .
git -C "$test_repo" commit -qm 'baseline'
head="$(git -C "$test_repo" rev-parse HEAD)"
admit() {
  SOURCE_POLICY_ROOT="$test_repo" EXPECTED_DEMO_SHA="$head" \
    bash "$source_root/ci/source-policy.sh" >/dev/null
}
deny() {
  if SOURCE_POLICY_ROOT="$test_repo" EXPECTED_DEMO_SHA="$head" \
      bash "$source_root/ci/source-policy.sh" >/dev/null 2>&1; then
    echo 'POLICY_INDEX_FENCE_UNEXPECTED_ADMISSION' >&2
    exit 1
  fi
}
admit
# Ambient Git routing must not redirect the authoritative tracked inventory.
GIT_INDEX_FILE="$test_repo/.git/forged-empty-index" \
  GIT_DIR="/tmp" GIT_WORK_TREE="/" admit
# The expected commit HEAD must be exact, lowercase and current.
if SOURCE_POLICY_ROOT="$test_repo" EXPECTED_DEMO_SHA="$(printf '0%.0s' {1..40})" \
    bash "$source_root/ci/source-policy.sh" >/dev/null 2>&1; then exit 1; fi
if SOURCE_POLICY_ROOT="$test_repo" EXPECTED_DEMO_SHA="$(printf 'A%.0s' {1..40})" \
    bash "$source_root/ci/source-policy.sh" >/dev/null 2>&1; then exit 1; fi
# A changed worktree with an old index must fail.
printf 'worktree mutation\n' > "$test_repo/src/worker.ores"
deny
# Once the index is updated to the bytes, the policy can verify that state.
git -C "$test_repo" add src/worker.ores
admit
# Mutating the worktree again creates a staged/worktree mismatch.
printf 'second mutation\n' > "$test_repo/src/worker.ores"
deny
git -C "$test_repo" checkout -- src/worker.ores
admit
# A tracked file deleted from disk cannot be silently skipped.
rm "$test_repo/src/worker.ores"
deny
git -C "$test_repo" checkout -- src/worker.ores
admit
# A newly tracked symlink is never a safe regular source.
ln -s worker.ores "$test_repo/src/alias.ores"
git -C "$test_repo" add src/alias.ores
deny
git -C "$test_repo" rm -q -f src/alias.ores
admit
echo 'REVERSE_SOURCE_POLICY_INDEX_FENCE_HOST_PASS guest=NOT_EXECUTED'
