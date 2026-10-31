#!/usr/bin/env bash
# Host-only, source-local, canonical config contract. NOT an Oreslang guest test.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

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

# Bind the exact files to regular, stage-0 index blobs and raw worktree bytes.
verify_index() {
  local path="$1" entry object mode stage recorded
  entry="$(/usr/bin/git -C "$root" -c core.fsmonitor=false -c core.filemode=true ls-files --stage -- "$path")" || return 1
  [[ "$entry" != *$'\n'* && "$entry" == *$'\t'"$path" ]] || return 1
  recorded="${entry%%$'\t'*}"
  read -r mode object stage <<< "$recorded"
  [[ "$mode" == 100644 && "$stage" == 0 && "$object" =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ "$(/usr/bin/git -C "$root" -c core.fsmonitor=false -c core.filemode=true hash-object --no-filters -- "$path")" == "$object" ]]
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
  echo 'REVERSE_SAFE_DEFAULTS_ADVERSARIAL_PASS cases=7 host_only=true'
}

main() {
  local mode="${1:-}" fixtures expected path oracle
  case "$mode" in --verify|--self-test) ;; *) echo 'usage: verify-safe-defaults.sh --verify|--self-test' >&2; exit 2;; esac
  fixtures="$(/usr/bin/mktemp -d)"
  trap "/usr/bin/rm -rf -- \"$fixtures\"" EXIT
  write_oracles "$fixtures"
  if [[ "$mode" == --self-test ]]; then
    self_test "$fixtures" || { echo 'SAFE_DEFAULTS_SELF_TEST_FAILURE' >&2; exit 2; }
    return 0
  fi
  [[ -z "${GIT_INDEX_FILE:-}" && -z "${GIT_DIR:-}" && -z "${GIT_WORK_TREE:-}" ]] || {
    echo 'SAFE_DEFAULTS_FAILURE: inherited Git redirection' >&2; exit 2;
  }
  expected="${EXPECTED_DEMO_SHA:-}"
  [[ "$expected" =~ ^[0-9a-f]{40}$ ]] &&
    [[ "$(/usr/bin/git -C "$root" rev-parse HEAD)" == "$expected" ]] || {
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
