#!/bin/bash -p
# Administrator-installed, root-owned verifier; do not execute the checkout copy.
# Install as /opt/oreslang-approved/oreslang-runtime/bin/verified-reverse-oreslang
# and include it in the independently approved full-runtime SHA-256 manifest.
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
hash -r
runtime_root='/opt/oreslang-approved/oreslang-runtime'
manifest_pin='/opt/oreslang-approved/oreslang-runtime.manifest.sha256'
java_root="$runtime_root/jdk"
java_exe="$java_root/bin/java"
launcher="$runtime_root/bin/oreslang"
verifier="$runtime_root/bin/verified-reverse-oreslang"
expected_source_sha='1a667fcd4481e3511e0cfa1008e855d96540c200'
expected_source_tree='5937599df00b6122dccaf22bcdebdaf836f6d3ee'
test "${GITHUB_REPOSITORY_ID:-}" = '1429954649' || { echo 'wrong source repository ID' >&2; exit 1; }
test "${GITHUB_REF:-}" = 'refs/heads/main' && test "${GITHUB_REF_PROTECTED:-}" = true || { echo 'unprotected control-plane ref' >&2; exit 1; }
test -n "${GITHUB_WORKSPACE:-}" && test -n "${RUNNER_TEMP:-}" || exit 1
test -f "$verifier" && test -x "$verifier" && test -f "$manifest_pin" || exit 1
for pinned_path in /opt /opt/oreslang-approved "$runtime_root" "$verifier" "$manifest_pin"; do
  test ! -L "$pinned_path" && test "$(/usr/bin/stat -c %u -- "$pinned_path")" = 0 || exit 1
  pinned_mode="$(/usr/bin/stat -c %a -- "$pinned_path")"
  [[ "$pinned_mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$pinned_mode & 8#22) == 0 )) || exit 1
done
expected_manifest_sha="$(/usr/bin/cat -- "$manifest_pin")"
[[ "$expected_manifest_sha" =~ ^[0-9a-f]{64}$ ]] || exit 1

test "$(/usr/bin/id -u)" != 0 || exit 1
test -d "$runtime_root" && test -f "$launcher" && test -x "$launcher" || exit 1
test -d "$java_root" && test -f "$java_exe" && test -x "$java_exe" || exit 1
test -r /proc/self/mountinfo && test -x /usr/bin/awk || exit 1
mount_report="$(/usr/bin/awk -v root="$runtime_root" -v prefix="$runtime_root/" "\$5==root || index(\$5,prefix)==1 {print \$5; exit}" /proc/self/mountinfo)" || { echo "failed to read approved runtime mount table" >&2; exit 1; }
test -z "$mount_report" || { echo "approved Oreslang runtime is a mount or contains nested mount" >&2; exit 1; }
bad_symlink="$(/usr/bin/find "$runtime_root" -xdev -type l -print -quit)" || exit 1
test -z "$bad_symlink" || exit 1
bad_special="$(/usr/bin/find "$runtime_root" -xdev ! -type d ! -type f -print -quit)" || exit 1
test -z "$bad_special" || exit 1
bad_owner="$(/usr/bin/find "$runtime_root" -xdev \( ! -uid 0 -o -perm /022 \) -print -quit)" || exit 1
test -z "$bad_owner" || exit 1
privileged_modes="$(/usr/bin/find "$runtime_root" -xdev -perm /6000 -print -quit)" || exit 1
test -z "$privileged_modes" || { echo "approved runtime contains setuid/setgid entries" >&2; exit 1; }
test -x /usr/sbin/getcap || exit 1
capability_report="$(/usr/sbin/getcap -r "$runtime_root" 2>&1)" || exit 1
test -z "$capability_report" || { echo "approved runtime has file capabilities or unreadable entries" >&2; exit 1; }
actual_manifest_sha="$(cd "$runtime_root" && /usr/bin/find . -xdev -type f -print0 | LC_ALL=C /usr/bin/sort -z | /usr/bin/xargs -0 -r /usr/bin/sha256sum | /usr/bin/sha256sum | /usr/bin/cut -d " " -f 1)"
test "$actual_manifest_sha" = "$expected_manifest_sha" || { echo "approved Oreslang runtime file set changed" >&2; exit 1; }
export JAVA_HOME="$java_root"
export PATH="$java_root/bin:/usr/bin:/bin"
spec="$("$java_exe" -XshowSettings:properties -version 2>&1 | /usr/bin/sed -nE "s/^[[:space:]]*java\\.specification\\.version[[:space:]]*=[[:space:]]*([^[:space:]]+).*$/\\1/p" | /usr/bin/head -n 1)"
test "$spec" = 25 || { echo "approved embedded JDK changed or is not JDK25" >&2; exit 1; }
cd "$GITHUB_WORKSPACE"
source_git=(/usr/bin/env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_NAMESPACE -u GIT_SHALLOW_FILE -u GIT_CEILING_DIRECTORIES -u GIT_DISCOVERY_ACROSS_FILESYSTEM -u GIT_GRAFT_FILE -u GIT_REPLACE_REF_BASE -u GIT_EXEC_PATH -u GIT_CONFIG -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null /usr/bin/git -c core.fsmonitor=false -c core.filemode=true --no-replace-objects --git-dir="$GITHUB_WORKSPACE/.git" --work-tree="$GITHUB_WORKSPACE")
actual_source_head="$("${source_git[@]}" rev-parse --verify HEAD)"
test "$actual_source_head" = "$expected_source_sha" || { echo "frozen source changed between native invocations" >&2; exit 1; }
actual_source_tree="$("${source_git[@]}" rev-parse --verify "HEAD^{tree}")"
test "$actual_source_tree" = "$expected_source_tree" || { echo "frozen tree changed between native invocations" >&2; exit 1; }
"${source_git[@]}" diff --no-ext-diff --quiet HEAD -- || { echo "frozen tracked worktree changed" >&2; exit 1; }
untracked_bytes="$("${source_git[@]}" ls-files --others -z -- | /usr/bin/wc -c)"
test "$untracked_bytes" -eq 0 || { echo "untracked or ignored source introduced" >&2; exit 1; }
checkout_root="$(/usr/bin/realpath -e -- "$GITHUB_WORKSPACE")"
"${source_git[@]}" ls-files -z -- | while IFS= read -r -d "" tracked_file; do
  test -f "$tracked_file" && test ! -L "$tracked_file" || exit 1
  test "$(/usr/bin/realpath -e -- "$tracked_file")" = "$checkout_root/$tracked_file" || { echo "frozen tracked file escapes checkout through parent symlink" >&2; exit 1; }
  "${source_git[@]}" show "HEAD:$tracked_file" | /usr/bin/cmp -s -- "$tracked_file" - || { echo "frozen source bytes changed" >&2; exit 1; }
  # Check committed executable mode even if index marks file assume-unchanged.
  head_entry=""
  IFS= read -r -d "" head_entry < <("${source_git[@]}" ls-tree -z HEAD -- ":(literal)$tracked_file") || exit 1
  expected_mode="${head_entry%% *}"
  current_mode="$(/usr/bin/stat -c %a -- "$tracked_file")"
  [[ "$current_mode" =~ ^[0-7]{3,4}$ ]] || exit 1
  (( (8#$current_mode & 8#6022) == 0 )) || exit 1
  case "$expected_mode" in 100644) (( (8#$current_mode & 8#111) == 0 )) || exit 1 ;; 100755) (( (8#$current_mode & 8#100) != 0 )) || exit 1 ;; *) exit 1 ;; esac
done
# Pass a minimal explicit guest environment. Runner/provider credentials,
# dynamic-loader hooks, Git configuration and unexpected variables stay outside
# the untrusted Oreslang process, including previously unknown secret names.
# Give each guest invocation a private job-local temporary directory rather
# than shared /tmp. This narrows cross-process interference on persistent
# self-hosted runners; runner-group isolation remains an independent admin gate.
umask 077
guest_tmp="$(/usr/bin/mktemp -d -- "$RUNNER_TEMP/oreslang-guest.XXXXXX")" || {
  echo "unable to create private guest temp directory" >&2
  exit 1
}
test -d "$guest_tmp" && test ! -L "$guest_tmp" || exit 1
test "$( /usr/bin/stat -c %u -- "$guest_tmp" )" = "$( /usr/bin/id -u )" || exit 1
guest_tmp_mode="$(/usr/bin/stat -c %a -- "$guest_tmp")"
[[ "$guest_tmp_mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$guest_tmp_mode & 8#077) == 0 )) || {
  echo "guest temp directory is accessible outside the runner account" >&2
  exit 1
}
guest_env=(
  "JAVA_HOME=$java_root"
  "PATH=$java_root/bin:/usr/bin:/bin"
  "LANG=C.UTF-8"
  "HOME=/nonexistent"
  "TMPDIR=$guest_tmp"
)
# Preserve only the two reviewed reverse ingress configuration cases:
# tracked example.yaml and a sentinel that the verifier maps to a private,
# per-invocation missing path inside guest_tmp. Never authorize a predictable
# missing-config pathname in shared RUNNER_TEMP.
guest_args=("$@")
if [[ "${ores_proxy_conf_yaml+x}" == x ]]; then
  example_cfg="$(/usr/bin/realpath -e -- "$GITHUB_WORKSPACE/config/example.yaml")" || exit 1
  missing_sentinel='@ORESLANG_MISSING_CONFIG@'
  if [[ "$ores_proxy_conf_yaml" == "$example_cfg" ]]; then
    guest_env+=("ores_proxy_conf_yaml=$example_cfg")
  elif [[ "$ores_proxy_conf_yaml" == "$missing_sentinel" ]]; then
    missing_cfg="$guest_tmp/ores-proxy-missing-config.yaml"
    test ! -e "$missing_cfg" && test ! -L "$missing_cfg" || {
      echo "private missing-config fixture unexpectedly exists" >&2
      exit 1
    }
    missing_allow_read_seen=0
    for i in "${!guest_args[@]}"; do
      if [[ "${guest_args[$i]}" == "--allow-read=$missing_sentinel" ]]; then
        guest_args[$i]="--allow-read=$missing_cfg"
        (( missing_allow_read_seen += 1 ))
      fi
    done
    test "$missing_allow_read_seen" -eq 1 || {
      echo "missing-config sentinel requires exactly one scoped --allow-read" >&2
      exit 1
    }
    guest_env+=("ores_proxy_conf_yaml=$missing_cfg")
  else
    echo "unapproved reverse ingress configuration environment path" >&2
    exit 1
  fi
fi

cleanup_guest_tmp() {
  /usr/bin/rm -rf -- "$guest_tmp"
}
trap cleanup_guest_tmp EXIT
set +e
/usr/bin/env -i "${guest_env[@]}" /usr/bin/timeout --signal=TERM --kill-after=2s 120s "$launcher" "${guest_args[@]}"
guest_status=$?
set -e
exit "$guest_status"
