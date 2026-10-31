#!/usr/bin/env bash
# Host-only exact source checkout admission, never compiler or wire evidence.
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
[[ -d "$ROOT/.git" && ! -L "$ROOT/.git" ]] || {
  echo 'CHECKOUT_FAIL: expected real .git directory' >&2; exit 1;
}
for key in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_REPLACE_REF_BASE GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT; do
  [[ -z "$(/usr/bin/printenv "$key" 2>/dev/null || true)" ]] || {
    echo "CHECKOUT_FAIL: inherited Git routing/config variable: $key" >&2; exit 1;
  }
done
git_exact() {
  /usr/bin/env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR \
    -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
    -u GIT_NAMESPACE -u GIT_REPLACE_REF_BASE -u GIT_CONFIG_PARAMETERS \
    -u GIT_CONFIG_COUNT -u GIT_EXEC_PATH -u GIT_CONFIG \
    /usr/bin/git --no-replace-objects -c core.fsmonitor=false \
      -c core.filemode=true -c core.sparseCheckout=false \
      --git-dir="$ROOT/.git" --work-tree="$ROOT" "$@"
}
[[ "$(git_exact rev-parse --show-toplevel)" == "$ROOT" ]] || {
  echo 'CHECKOUT_FAIL: repository root mismatch' >&2; exit 1;
}
actual_head="$(git_exact rev-parse --verify HEAD)"
[[ "$actual_head" =~ ^[0-9a-f]{40}$ ]] || {
  echo 'CHECKOUT_FAIL: invalid HEAD' >&2; exit 1;
}
if [[ -n "$(/usr/bin/printenv EXPECTED_SHA 2>/dev/null || true)" && "$actual_head" != "$EXPECTED_SHA" ]]; then
  echo 'CHECKOUT_FAIL: checkout HEAD differs from pinned event' >&2; exit 1
fi
actual_tree="$(git_exact rev-parse --verify 'HEAD^{tree}')"
[[ "$actual_tree" =~ ^[0-9a-f]{40}$ ]] || {
  echo 'CHECKOUT_FAIL: invalid Git tree' >&2; exit 1;
}
git_exact diff --no-ext-diff --quiet HEAD -- || {
  echo 'CHECKOUT_FAIL: modified tracked working tree' >&2; exit 1;
}
git_exact diff --no-ext-diff --cached --quiet HEAD -- || {
  echo 'CHECKOUT_FAIL: modified staged index' >&2; exit 1;
}
# Keep both categories explicit: --others alone currently includes ignored
# files, but --exclude-standard without the separate ignored scan would not.
nonignored="$(git_exact ls-files --others --exclude-standard -z | /usr/bin/wc -c)" || {
  echo 'CHECKOUT_FAIL: nonignored file inventory failed' >&2; exit 1;
}
ignored="$(git_exact ls-files --others --ignored --exclude-standard -z | /usr/bin/wc -c)" || {
  echo 'CHECKOUT_FAIL: ignored file inventory failed' >&2; exit 1;
}
[[ "$nonignored" -eq 0 && "$ignored" -eq 0 ]] || {
  echo "CHECKOUT_FAIL: extra files (nonignored_bytes=$nonignored ignored_bytes=$ignored)" >&2; exit 1;
}
# Process substitution can hide git failures, so materialize tracked names
# before iterating to guarantee an error becomes a failed audit.
tracked="$(/usr/bin/mktemp)"
trap '/usr/bin/rm -f -- "$tracked"' EXIT
git_exact ls-files -z > "$tracked" || {
  echo 'CHECKOUT_FAIL: tracked file listing failed' >&2; exit 1;
}
# A reused checkout can hide modified tracked bytes with assume-unchanged
# or skip-worktree index flags. Require ordinary, non-sparse index entries.
index_flags="$(/usr/bin/mktemp)"
trap '/usr/bin/rm -f -- "$tracked" "$index_flags"' EXIT
git_exact ls-files -v -z > "$index_flags" || {
  echo 'CHECKOUT_FAIL: index flag listing failed' >&2; exit 1;
}
while IFS= read -r -d '' entry; do
  [[ "${entry:0:1}" == H ]] || {
    echo 'CHECKOUT_FAIL: skip-worktree or assume-unchanged index entry' >&2; exit 1;
  }
done < "$index_flags"
while IFS= read -r -d '' path; do
  case "$path" in
    *.[Pp][Yy]|*.[Pp][Yy][Ii]|*.[Ii][Pp][Yy][Nn][Bb])
      echo "CHECKOUT_FAIL: tracked Python forbidden: $path" >&2; exit 1 ;;
  esac
done < "$tracked"
printf 'SOURCE_CHECKOUT_PASS head=%s tree=%s ignored=0 nonignored=0 python=0 host_only=true\n' "$actual_head" "$actual_tree"
