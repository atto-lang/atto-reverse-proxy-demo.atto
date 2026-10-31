#!/usr/bin/env bash
# Synthetic Git fixtures: checkout/inventory only, not native Oreslang tests.
set -euo pipefail
export LC_ALL=C
SCRIPT="$(cd "$(dirname "$0")" && pwd -P)/source_checkout_integrity.sh"
[[ -f "$SCRIPT" ]] || exit 1
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
checks=0
repo="$work/repo"
mkdir -p "$repo/ci"
cp "$SCRIPT" "$repo/ci/source_checkout_integrity.sh"
cd "$repo"
git init -q
git config user.name 'Synthetic CI'
git config user.email 'synthetic@example.invalid'
printf 'ignored.txt\n' > .gitignore
printf 'fixture\n' > source.ores
git add .
git commit -qm 'synthetic exact-head fixture'
head="$(git rev-parse HEAD)"
expect_pass() {
  local label="$1"; shift
  if ! EXPECTED_SHA="$head" "$@" >"$work/out" 2>"$work/err"; then
    echo "FAIL expected pass: $label" >&2; cat "$work/err" >&2; exit 1
  fi
  checks=$((checks+1))
  echo "PASS synthetic: $label"
}
expect_deny() {
  local label="$1"; shift
  if EXPECTED_SHA="$head" "$@" >"$work/out" 2>"$work/err"; then
    echo "FAIL unsafe pass: $label" >&2; exit 1
  fi
  checks=$((checks+1))
  echo "PASS synthetic rejection: $label"
}
expect_pass clean bash ci/source_checkout_integrity.sh
GIT_DIR='' GIT_INDEX_FILE='' expect_pass clean-empty-git-env bash ci/source_checkout_integrity.sh
printf 'new\n' > extra.txt
expect_deny nonignored-untracked bash ci/source_checkout_integrity.sh
rm extra.txt
printf 'ignored\n' > ignored.txt
expect_deny gitignored-untracked bash ci/source_checkout_integrity.sh
rm ignored.txt
printf 'changed\n' > source.ores
expect_deny dirty-tracked-bytes bash ci/source_checkout_integrity.sh
git restore -- source.ores
printf 'staged\n' > source.ores
git add source.ores
expect_deny staged-modification bash ci/source_checkout_integrity.sh
git reset -q HEAD -- source.ores
git restore -- source.ores
git config core.filemode false
chmod +x source.ores
expect_deny chmod-drift-with-filemode-disabled bash ci/source_checkout_integrity.sh
chmod -x source.ores
git config --unset core.filemode
expect_deny wrong-expected-head env EXPECTED_SHA=0000000000000000000000000000000000000000 bash ci/source_checkout_integrity.sh
GIT_DIR="$work" expect_deny poisoned-git-dir bash ci/source_checkout_integrity.sh
printf 'print(1)\n' > source.py
git add source.py
git commit -qm 'deliberate prohibited python fixture'
head="$(git rev-parse HEAD)"
expect_deny tracked-python-file bash ci/source_checkout_integrity.sh
printf 'CHECKOUT_INTEGRITY_NEGATIVE_PASS cases=%d host_only=true\n' "$checks"
