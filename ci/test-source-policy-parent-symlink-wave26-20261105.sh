#!/usr/bin/env bash
# Disposable indexed Git checkout; no reverse proxy or guest execution.
set -euo pipefail
source_root="$(cd "$(dirname -- "$0")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
git init -q "$fixture"
git -C "$fixture" config user.name 'Reverse policy regression'
git -C "$fixture" config user.email 'reverse@example.invalid'
mkdir -p "$fixture/src"
printf 'define module Worker as\nend\n' > "$fixture/src/worker.ores"
printf 'a%.0s' {1..40} > "$fixture/SOURCE_REF"
printf '\n' >> "$fixture/SOURCE_REF"
git -C "$fixture" add .
git -C "$fixture" commit -qm 'indexed source baseline'
head="$(git -C "$fixture" rev-parse HEAD)"
check_ok() {
  SOURCE_POLICY_ROOT="$fixture" SOURCE_POLICY_MODE=strict EXPECTED_DEMO_SHA="$head" \
    bash "$source_root/ci/source-policy.sh" >/dev/null
}
check_bad() {
  local expected="$1" output
  if output="$(SOURCE_POLICY_ROOT="$fixture" SOURCE_POLICY_MODE=strict EXPECTED_DEMO_SHA="$head" \
    bash "$source_root/ci/source-policy.sh" 2>&1)"; then
    echo "unexpected source-policy admission: $expected" >&2
    exit 1
  fi
  [[ "$output" == *"$expected"* ]] || {
    printf 'missing expected denial (%s): %s\n' "$expected" "$output" >&2
    exit 1
  }
}
check_ok
# Matching content through an aliased directory is NOT the indexed path.
mv "$fixture/src" "$fixture/real-src"
ln -s real-src "$fixture/src"
check_bad 'tracked file escapes checkout through parent path'
rm "$fixture/src"
mv "$fixture/real-src" "$fixture/src"
check_ok
# Unstaged modification must not be conflated with the index authority.
printf 'mutated worktree\n' > "$fixture/src/worker.ores"
check_bad 'staged blob differs from audited worktree'
git -C "$fixture" add src/worker.ores
check_ok
printf 'new untracked bytes\n' > "$fixture/src/worker.ores"
check_bad 'staged blob differs from audited worktree'
git -C "$fixture" checkout -- src/worker.ores
check_ok
# Inherited routing must not substitute attacker-controlled Git metadata.
GIT_DIR=/tmp GIT_WORK_TREE=/ GIT_INDEX_FILE="$fixture/.git/alien-index" \
  GIT_CONFIG_COUNT=0 check_ok
echo 'REVERSE_PARENT_INDEX_HOST_PASS; GUEST_NOT_EXECUTED'
