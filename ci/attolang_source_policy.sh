#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
FIND=/usr/bin/find
STAT=/usr/bin/stat
CMP=/usr/bin/cmp
MKTEMP=/usr/bin/mktemp
RM=/usr/bin/rm
git_clean() { /usr/bin/env -i PATH=/usr/bin:/bin LC_ALL=C HOME=/nonexistent /usr/bin/git "$@"; }
root="$(git_clean rev-parse --show-toplevel)"
cd "$root"
scan_dir="$($MKTEMP -d)"
trap '$RM -rf "$scan_dir"' EXIT
legacy_index="$scan_dir/tracked-legacy"
atto_index="$scan_dir/tracked-atto"
legacy_fs="$scan_dir/legacy-fs"
blob_tmp="$scan_dir/blob"
if ! git_clean ls-files -z -- '*.ores' > "$legacy_index"; then
  echo 'failed to enumerate tracked legacy source' >&2; exit 1
fi
if [[ -s "$legacy_index" ]]; then
  IFS= read -r -d '' first < "$legacy_index" || true
  printf 'legacy .ores path is forbidden on AttoLang migration branch: %s\n' "$first" >&2; exit 1
fi
if ! git_clean ls-files -z -- '*.atto' > "$atto_index"; then
  echo 'failed to enumerate tracked AttoLang source' >&2; exit 1
fi
if [[ ! -s "$atto_index" ]]; then echo 'no tracked .atto guest files found' >&2; exit 1; fi
if ! $FIND . \( -type f -o -type l \) -name '*.ores' -not -path './.git/*' -print0 > "$legacy_fs"; then
  echo 'legacy .ores filesystem scan failed' >&2; exit 1
fi
if [[ -s "$legacy_fs" ]]; then
  IFS= read -r -d '' first < "$legacy_fs" || true
  printf 'untracked or symlink legacy .ores path is forbidden: %s\n' "$first" >&2; exit 1
fi
atto_count=0
while IFS= read -r -d '' file; do
  ((atto_count+=1))
  [[ "$file" == src/* || "$file" == tests/* || "$file" == bench/* ]] || { echo "unexpected .atto location: $file" >&2; exit 1; }
  test -f "$file" && test ! -L "$file" && test -s "$file" || { echo "invalid .atto regular file: $file" >&2; exit 1; }
  entry="$(git_clean ls-files --stage -- "$file")"
  mode="${entry%% *}"
  test "$mode" = 100644 || { echo "unapproved .atto Git mode $mode: $file" >&2; exit 1; }
  actual_mode="$($STAT -c %a -- "$file")"
  [[ "$actual_mode" =~ ^[0-7]{3,4}$ ]] || { echo "invalid filesystem mode: $file" >&2; exit 1; }
  (( (8#$actual_mode & 8#111) == 0 )) || { echo "unreviewed executable bit on .atto file: $file" >&2; exit 1; }
  (( (8#$actual_mode & 8#022) == 0 )) || { echo "group/world-writable .atto file: $file" >&2; exit 1; }
  links="$($STAT -c %h -- "$file")"
  [[ "$links" =~ ^[0-9]+$ ]] && (( links == 1 )) || { echo "hardlinked .atto file is forbidden: $file" >&2; exit 1; }
  if ! git_clean show "HEAD:$file" > "$blob_tmp"; then echo "failed to read committed .atto blob: $file" >&2; exit 1; fi
  $CMP -s "$file" "$blob_tmp" || { echo "working bytes differ from committed .atto blob: $file" >&2; exit 1; }
done < "$atto_index"
printf 'ATTOLANG_SOURCE_POLICY_PASS atto_files=%d legacy_ores=0\n' "$atto_count"
