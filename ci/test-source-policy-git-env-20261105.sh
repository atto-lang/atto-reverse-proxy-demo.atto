#!/usr/bin/env bash
# Index/worktree and inherited Git redirection isolation contract, host-only.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp"
git -C "$tmp" config user.name 'Policy fixture'
git -C "$tmp" config user.email 'fixture@example.invalid'
mkdir -p "$tmp/src"
printf 'owned actor source\n' > "$tmp/src/worker.ores"
printf 'a%.0s' {1..40} > "$tmp/SOURCE_REF"
printf '\n' >> "$tmp/SOURCE_REF"
git -C "$tmp" add .
git -C "$tmp" commit -qm baseline
pass() { SOURCE_POLICY_ROOT="$tmp" GIT_INDEX_FILE="$tmp/.git/forged-empty-index" GIT_WORK_TREE=/ GIT_DIR=/tmp GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false bash "$root/ci/source-policy.sh" >/dev/null; }
deny() { if SOURCE_POLICY_ROOT="$tmp" GIT_INDEX_FILE="$tmp/.git/forged-empty-index" GIT_WORK_TREE=/ GIT_DIR=/tmp bash "$root/ci/source-policy.sh" >/dev/null 2>&1; then echo 'POLICY_STAGED_WORKTREE_BYPASS' >&2; exit 1; fi; }
pass
# A staged original paired with different worktree bytes must be denied.
printf 'tampered actor source\n' > "$tmp/src/worker.ores"
deny
git -C "$tmp" add src/worker.ores
pass
# Missing tracked files may not be treated as a permitted empty inventory.
rm "$tmp/src/worker.ores"
deny
printf 'tampered actor source\n' > "$tmp/src/worker.ores"
pass
echo 'SOURCE_POLICY_INDEX_ENV_HOST_PASS cases=5 guest=NOT_EXECUTED'
