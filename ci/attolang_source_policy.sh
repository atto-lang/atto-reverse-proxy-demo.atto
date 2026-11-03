#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
root="$(git rev-parse --show-toplevel)"
cd "$root"

mapfile -d '' tracked_legacy < <(git ls-files -z -- '*.ores')
if ((${#tracked_legacy[@]} != 0)); then
  printf 'legacy .ores path is forbidden on AttoLang migration branch: %s\n' "${tracked_legacy[0]}" >&2
  exit 1
fi

mapfile -d '' atto_files < <(git ls-files -z -- '*.atto')
if ((${#atto_files[@]} == 0)); then
  echo 'no tracked .atto guest files found' >&2
  exit 1
fi

while IFS= read -r -d '' path; do
  echo "untracked legacy .ores path is forbidden: $path" >&2
  exit 1
done < <(find . -type f -name '*.ores' -not -path './.git/*' -print0)

for file in "${atto_files[@]}"; do
  [[ "$file" == src/* || "$file" == tests/* || "$file" == bench/* ]] || {
    echo "unexpected .atto location: $file" >&2
    exit 1
  }
  test -f "$file" && test ! -L "$file" && test -s "$file" || {
    echo "invalid .atto regular file: $file" >&2
    exit 1
  }
  entry="$(git ls-files --stage -- "$file")"
  mode="${entry%% *}"
  test "$mode" = 100644 || {
    echo "unapproved .atto Git mode $mode: $file" >&2
    exit 1
  }
  actual_mode="$(stat -c %a -- "$file")"
  [[ "$actual_mode" =~ ^[0-7]{3,4}$ ]] || exit 1
  (( (8#$actual_mode & 8#111) == 0 )) || {
    echo "unreviewed executable bit on .atto file: $file" >&2
    exit 1
  }
  (( (8#$actual_mode & 8#022) == 0 )) || {
    echo "group/world-writable .atto file: $file" >&2
    exit 1
  }
  cmp -s "$file" <(git show "HEAD:$file") || {
    echo "working bytes differ from committed .atto blob: $file" >&2
    exit 1
  }
done

printf 'ATTOLANG_SOURCE_POLICY_PASS atto_files=%d legacy_ores=0\n' "${#atto_files[@]}"
