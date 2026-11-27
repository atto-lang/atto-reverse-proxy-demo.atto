#!/usr/bin/env bash
# TRUSTED LOCAL DEVELOPMENT ONLY: this file must NEVER execute from a PR checkout.
# The hosted workflow runs its own reviewed inline probe BEFORE checkout.
# Keep this helper for manual, trusted source-free regression checks.
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
workflow="$root/.github/workflows/safe-defaults.yml"
test -f "$workflow" && test ! -L "$workflow"
grep -Fq "python3 -I - <<'PY'" "$workflow" || {
  echo 'SECURITY_FAILURE: hosted Python policy lacks isolated import mode' >&2
  exit 1
}
if grep -Fq "python3 - <<'PY'" "$workflow"; then
  echo 'SECURITY_FAILURE: unisolated Python policy entrypoint remains' >&2
  exit 1
fi
python_bin="$(command -v python3)"
test -n "$python_bin"
umask 077
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
printf '%s\n' 'open("shadowed-tomllib", "w").close()' 'raise RuntimeError("untrusted tomllib imported")' > "$tmp/tomllib.py"
printf '%s\n' 'open("shadowed-pathlib", "w").close()' 'raise RuntimeError("untrusted pathlib imported")' > "$tmp/pathlib.py"
printf '%s\n' 'open("shadowed-sitecustomize", "w").close()' 'raise RuntimeError("untrusted startup hook")' > "$tmp/sitecustomize.py"
(
  cd "$tmp"
  PYTHONPATH="$tmp" PYTHONHOME="$tmp" "$python_bin" -I - <<'PY'
import pathlib
import tomllib
assert callable(tomllib.loads)
assert pathlib.Path(".").is_dir()
PY
)
for marker in shadowed-tomllib shadowed-pathlib shadowed-sitecustomize; do
  test ! -e "$tmp/$marker" || { echo "SECURITY_FAILURE: imported $marker" >&2; exit 1; }
done
printf '%s\n' 'SAFE_DEFAULTS_IMPORT_ISOLATION_PASS negative_vectors=3 source_free=1 native_guest=NOT_EXECUTED'
