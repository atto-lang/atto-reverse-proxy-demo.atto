#!/usr/bin/env bash
# Host-only, source-local, canonical config contract. NOT an Oreslang guest test.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source_script="$root/ci/verify-safe-defaults.sh"
safe_defaults_tmp_dir=''

# The expected configuration is embedded in this independently reviewed gate.
# Do not learn expected values from the mutable source checkout being audited.
write_oracles() {
  local dir="$1"
  cat > "$dir/flags" <<'EXPECTED_FLAGS'
# Native Oreslang proxy flags-2-env contract.
[flags.config-yaml]
env = "ores_proxy_conf_yaml"
aliases = ["config-yaml", "conf"]
type = "string"
help = "Absolute trusted path to a proxy YAML configuration file."
EXPECTED_FLAGS
  cat > "$dir/config" <<'EXPECTED_CONFIG'
version: ores.proxy/v1
mode: reverse
listen:
  host: 127.0.0.1
  port: 8080
runtime:
  carriers: 20
  actors: 100
  max_inflight: 1024
middleware:
  - name: trace
    kind: trace
  - name: protected
    kind: require_header
    header: x-internal-token
routes:
  - name: api
    host: api.example.test
    path_prefix: /api
    upstream: http://127.0.0.1:9000
    middleware: trace,protected
EXPECTED_CONFIG
}

# Reject linked/absent/irregular files, symlinked parents and permission drift.
canonical_file() {
  local candidate="$1" oracle="$2" expected_absolute="$3" resolved perms
  [[ -f "$candidate" && ! -L "$candidate" ]] || return 1
  resolved="$(/usr/bin/realpath -e -- "$candidate")" || return 1
  [[ "$resolved" == "$expected_absolute" ]] || return 1
  perms="$(/usr/bin/stat -c %a -- "$candidate")" || return 1
  [[ "$perms" =~ ^[0-7]{3,4}$ ]] || return 1
  # Reject all executable, group/world write and special permission bits.
  (( (8#$perms & 8#7133) == 0 )) || return 1
  /usr/bin/cmp -s -- "$candidate" "$oracle"
}

# All Git reads are bound to this checkout. Never let inherited index/object/config
# routing select a different repository or object database on a reused runner.
git_safe() {
  /usr/bin/env \
    -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE \
    -u GIT_SHALLOW_FILE -u GIT_CEILING_DIRECTORIES -u GIT_DISCOVERY_ACROSS_FILESYSTEM \
    -u GIT_GRAFT_FILE -u GIT_REPLACE_REF_BASE -u GIT_EXEC_PATH -u GIT_CONFIG \
    GIT_CONFIG_COUNT=0 GIT_CONFIG_PARAMETERS='' \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    /usr/bin/git -c core.fsmonitor=false -c core.filemode=true --no-replace-objects \
      --git-dir="$root/.git" --work-tree="$root" "$@"
}

# Bind the exact files to regular, stage-0 index blobs and raw worktree bytes.
verify_index() {
  local path="$1" entry object mode stage recorded
  entry="$(git_safe ls-files --stage -- "$path")" || return 1
  [[ "$entry" != *$'\n'* && "$entry" == *$'\t'"$path" ]] || return 1
  recorded="${entry%%$'\t'*}"
  read -r mode object stage <<< "$recorded"
  [[ "$mode" == 100644 && "$stage" == 0 && "$object" =~ ^[0-9a-f]{40}$ ]] || return 1
  # Staged index must be byte-for-byte the pinned HEAD path, not a replacement.
  git_safe diff --no-ext-diff --cached --quiet HEAD -- "$path" || return 1
  [[ "$(git_safe hash-object --no-filters -- "$path")" == "$object" ]]
}

self_test() {
  local fixtures="$1" test_dir="$fixtures/adversarial" outside="$fixtures/outside"
  mkdir -p "$test_dir/config" "$outside"
  cp "$fixtures/flags" "$test_dir/flags"
  cp "$fixtures/config" "$test_dir/config/example.yaml"
  canonical_file "$test_dir/flags" "$fixtures/flags" "$test_dir/flags" || return 1
  canonical_file "$test_dir/config/example.yaml" "$fixtures/config" "$test_dir/config/example.yaml" || return 1
  printf '\n  host: 0.0.0.0\n' >> "$test_dir/config/example.yaml"
  if canonical_file "$test_dir/config/example.yaml" "$fixtures/config" "$test_dir/config/example.yaml"; then return 1; fi
  cp "$fixtures/config" "$test_dir/config/example.yaml"
  printf '\nmode: reverse\n' >> "$test_dir/config/example.yaml"
  if canonical_file "$test_dir/config/example.yaml" "$fixtures/config" "$test_dir/config/example.yaml"; then return 1; fi
  cp "$fixtures/config" "$test_dir/config/example.yaml"
  sed -i 's/ores_proxy_conf_yaml/unsafe_override/g' "$test_dir/flags"
  if canonical_file "$test_dir/flags" "$fixtures/flags" "$test_dir/flags"; then return 1; fi
  cp "$fixtures/flags" "$test_dir/flags"
  rm "$test_dir/config/example.yaml"
  ln -s "$fixtures/config" "$test_dir/config/example.yaml"
  if canonical_file "$test_dir/config/example.yaml" "$fixtures/config" "$test_dir/config/example.yaml"; then return 1; fi
  rm "$test_dir/config/example.yaml"
  cp "$fixtures/config" "$outside/example.yaml"
  rmdir "$test_dir/config"
  ln -s "$outside" "$test_dir/config"
  if canonical_file "$test_dir/config/example.yaml" "$fixtures/config" "$test_dir/config/example.yaml"; then return 1; fi
  rm "$test_dir/config"
  mkdir -p "$test_dir/config"
  cp "$fixtures/config" "$test_dir/config/example.yaml"
  canonical_file "$test_dir/config/example.yaml" "$fixtures/config" "$test_dir/config/example.yaml" || return 1
  chmod +x "$test_dir/config/example.yaml"
  if canonical_file "$test_dir/config/example.yaml" "$fixtures/config" "$test_dir/config/example.yaml"; then return 1; fi
  chmod -x "$test_dir/config/example.yaml"
  # A staged canonical file must not override a noncanonical pinned HEAD.
  local root="$fixtures/pinned-repo"
  mkdir -p "$root/config"
  cp "$fixtures/config" "$root/config/example.yaml"
  /usr/bin/git -C "$root" init -q
  /usr/bin/git -C "$root" config user.name 'Source policy test'
  /usr/bin/git -C "$root" config user.email 'policy@example.invalid'
  /usr/bin/git -C "$root" add .
  /usr/bin/git -C "$root" commit -qm 'clean'
  verify_index config/example.yaml || return 1
  # Ambient Git object routing must not influence exact-index verification.
  # This path is intentionally not a Git object database; unsanitized Git
  # would fail or inspect the wrong object store.
  GIT_OBJECT_DIRECTORY="$outside/not-an-object-db" verify_index config/example.yaml || return 1
  printf '\nmode: forward\n' >> "$root/config/example.yaml"
  /usr/bin/git -C "$root" add config/example.yaml
  /usr/bin/git -C "$root" commit -qm 'dirty pinned HEAD'
  cp "$fixtures/config" "$root/config/example.yaml"
  /usr/bin/git -C "$root" add config/example.yaml
  if verify_index config/example.yaml; then return 1; fi
  /usr/bin/git -C "$root" reset --hard -q HEAD
  /usr/bin/git -C "$root" update-index --chmod=+x config/example.yaml
  if verify_index config/example.yaml; then return 1; fi
  # Regression: a hostile TMPDIR containing quotes and shell metacharacters
  # must not execute a command through the EXIT cleanup trap.
  local poisoned_tmp="$outside/poison\";touch INJECTED;#"
  /usr/bin/mkdir -p -- "$poisoned_tmp"
  if (
    cd "$fixtures" &&
    TMPDIR="$poisoned_tmp" EXPECTED_DEMO_SHA=invalid \
      /bin/bash "$source_script" --verify >/dev/null 2>&1
  ); then
    return 1
  fi
  [[ ! -e "$fixtures/INJECTED" ]] || return 1
  [[ -z "$(/usr/bin/find "$poisoned_tmp" -mindepth 1 -print -quit)" ]] || return 1
  echo 'REVERSE_SAFE_DEFAULTS_ADVERSARIAL_PASS cases=11 host_only=true'
}

main() {
  local mode="${1:-}" fixtures expected path oracle
  case "$mode" in --verify|--self-test) ;; *) echo 'usage: verify-safe-defaults.sh --verify|--self-test' >&2; exit 2;; esac
  safe_defaults_tmp_dir="$(/usr/bin/mktemp -d)"
  fixtures="$safe_defaults_tmp_dir"
  # TMPDIR can contain shell metacharacters. Never interpolate it into trap code.
  # This must be global: main's local variables disappear before EXIT cleanup.
  trap '/usr/bin/rm -rf -- "$safe_defaults_tmp_dir"' EXIT
  write_oracles "$fixtures"
  if [[ "$mode" == --self-test ]]; then
    self_test "$fixtures" || { echo 'SAFE_DEFAULTS_SELF_TEST_FAILURE' >&2; exit 2; }
    return 0
  fi
  [[ -d "$root/.git" && ! -L "$root/.git" ]] || {
    echo 'SAFE_DEFAULTS_FAILURE: expected real checkout Git directory' >&2; exit 2;
  }
  for git_env_name in \
    GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE \
    GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM GIT_GRAFT_FILE \
    GIT_REPLACE_REF_BASE GIT_EXEC_PATH GIT_CONFIG GIT_CONFIG_COUNT \
    GIT_CONFIG_PARAMETERS GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
  do
    [[ -z "${!git_env_name:-}" ]] || {
      echo "SAFE_DEFAULTS_FAILURE: inherited Git control variable: $git_env_name" >&2
      exit 2
    }
  done
  [[ "$(git_safe rev-parse --show-toplevel)" == "$root" ]] || {
    echo 'SAFE_DEFAULTS_FAILURE: Git repository root mismatch' >&2; exit 2;
  }
  expected="${EXPECTED_DEMO_SHA:-}"
  [[ "$expected" =~ ^[0-9a-f]{40}$ ]] &&
    [[ "$(git_safe rev-parse HEAD)" == "$expected" ]] || {
    echo 'SAFE_DEFAULTS_FAILURE: invalid or mismatched pinned head' >&2; exit 2;
  }
  for path in .cli-flags.toml config/example.yaml; do
    case "$path" in .cli-flags.toml) oracle=flags ;; *) oracle=config ;; esac
    verify_index "$path" && canonical_file "$root/$path" "$fixtures/$oracle" "$root/$path" || {
      echo "SAFE_DEFAULTS_FAILURE: noncanonical tracked file $path" >&2; exit 2;
    }
  done
  echo 'REVERSE_SAFE_DEFAULTS_STRUCTURAL_PASS; ORESLANG_COMPILER_AND_WIRE_NOT_EXECUTED'
}
main "$@"
