#!/usr/bin/env bash
# Adversarial hermetic tests of the exact policy gate used in CI.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_repo="$(mktemp -d)"
trap 'rm -rf "$test_repo"' EXIT
git init -q "$test_repo"
git -C "$test_repo" config user.name "Policy test"
git -C "$test_repo" config user.email "policy@example.invalid"
mkdir -p "$test_repo/docs" "$test_repo/src"
printf '00_abc\n' > "$test_repo/src/hello.ores"
printf 'a%.0s' {1..40} > "$test_repo/SOURCE_REF"
printf '\n' >> "$test_repo/SOURCE_REF"
git -C "$test_repo" add .
check_ok() {
  SOURCE_POLICY_ROOT="$test_repo" SOURCE_POLICY_MODE="${1:-strict}" bash "$root/ci/source-policy.sh" > /dev/null
}
check_bad() {
  if SOURCE_POLICY_ROOT="$test_repo" SOURCE_POLICY_MODE="${1:-strict}" bash "$root/ci/source-policy.sh" > /dev/null 2>&1; then
    echo "TEST_FAILURE: expected source policy rejection" >&2; exit 1
  fi
}
check_ok
# SOURCE_REF provenance must be inert (100644), not executable even if
# its 40-hex contents and the worktree are otherwise valid.
git -C "$test_repo" update-index --chmod=+x -- SOURCE_REF
check_bad
git -C "$test_repo" update-index --chmod=-x -- SOURCE_REF
check_ok
mkdir -p "$test_repo/nested space"
printf 'placeholder\n' > "$test_repo/nested space/unsafe.PY"
git -C "$test_repo" add .
check_bad
git -C "$test_repo" rm -q -f -- "nested space/unsafe.PY"
printf 'placeholder\n' > "$test_repo/src/escape.ipynb"
git -C "$test_repo" add .
check_bad
git -C "$test_repo" rm -q -f -- src/escape.ipynb
printf '#!/usr/bin/env python3\n' > "$test_repo/runner"
git -C "$test_repo" add .
check_bad
git -C "$test_repo" rm -q -f -- runner
# GNU env -S strips quotes and concatenates quoted interpreter fragments.
# All of these execute Python on Linux, despite the original shebang regex.
for interpreter in "'python3'" '"python3"' "'py''thon3'"; do
  printf '#!/usr/bin/env -S %s\n' "$interpreter" > "$test_repo/quoted-interpreter"
  git -C "$test_repo" add quoted-interpreter
  check_bad
  git -C "$test_repo" rm -q -f -- quoted-interpreter
done
# Python executable ABI/debug variants bypassed the previous digits-and-dots
# regex, despite being valid executable names for Python interpreters.
for interpreter in python3.7m python3.11-dbg python3.11d; do
  printf '#!/usr/bin/env -S %s\n' "$interpreter" > "$test_repo/abi-interpreter"
  git -C "$test_repo" add abi-interpreter
  check_bad
  git -C "$test_repo" rm -q -f -- abi-interpreter
done
printf '#!/usr/bin/python3.7m\n' > "$test_repo/direct-abi-interpreter"
git -C "$test_repo" add direct-abi-interpreter
check_bad
git -C "$test_repo" rm -q -f -- direct-abi-interpreter
# GNU env -S also expands environment variables before interpreter lookup.
# Reject both unquoted and quoted variable-based executable selection.
for interpreter in '${ORES_POLICY_INTERPRETER}' '"${ORES_POLICY_INTERPRETER}"'; do
  printf '#!/usr/bin/env -S %s\n' "$interpreter" > "$test_repo/dynamic-interpreter"
  git -C "$test_repo" add dynamic-interpreter
  check_bad
  git -C "$test_repo" rm -q -f -- dynamic-interpreter
done
# GNU env -S interprets \_ as a word separator before selecting Python.
# The original backslash-removal regex sees _python3 and incorrectly permits it.
for interpreter in '\_python3' '\_ python3'; do
  printf '#!/usr/bin/env -S %s\n' "$interpreter" > "$test_repo/escaped-separator"
  git -C "$test_repo" add escaped-separator
  check_bad
  git -C "$test_repo" rm -q -f -- escaped-separator
done
# The stricter guard must not reject unrelated interpreters.
printf '#!/usr/bin/env node\n' > "$test_repo/node-interpreter"
git -C "$test_repo" add node-interpreter
check_ok
git -C "$test_repo" rm -q -f -- node-interpreter
ln -s hello.ores "$test_repo/src/alias.ores"
git -C "$test_repo" add .
check_bad
git -C "$test_repo" rm -q -f -- src/alias.ores
printf 'bad\n' > "$test_repo/SOURCE_REF"
git -C "$test_repo" add .
check_bad
printf 'a%.0s' {1..40} > "$test_repo/SOURCE_REF"
printf '\n' >> "$test_repo/SOURCE_REF"
git -C "$test_repo" add .
check_ok
mkdir -p "$test_repo/scripts"
printf 'legacy\n' > "$test_repo/scripts/benchmark.py"
git -C "$test_repo" add .
check_bad
check_ok rest-legacy
printf 'new\n' > "$test_repo/scripts/new_tool.py"
git -C "$test_repo" add .
check_bad rest-legacy
# Reset the earlier negative fixtures before testing valid-source baselines.
git -C "$test_repo" rm -q -f -- scripts/new_tool.py scripts/benchmark.py
check_ok
# A valid-looking but untracked SOURCE_REF cannot establish provenance.
git -C "$test_repo" rm -q --cached -- SOURCE_REF
check_bad
git -C "$test_repo" add SOURCE_REF
check_ok
# Optional SOURCE_REF cannot be replaced by a tracked symlink, even if its target is valid.
mv "$test_repo/SOURCE_REF" "$test_repo/saved_ref"
ln -s saved_ref "$test_repo/SOURCE_REF"
git -C "$test_repo" add -A
check_bad
rm "$test_repo/SOURCE_REF"
mv "$test_repo/saved_ref" "$test_repo/SOURCE_REF"
git -C "$test_repo" add -A
check_ok
# Symlinks are rejected regardless of file extension.
ln -s hello.ores "$test_repo/src/alias.txt"
git -C "$test_repo" add .
check_bad
git -C "$test_repo" rm -q -f -- src/alias.txt
check_ok
# A tracked SOURCE_REF deleted only from the working tree must fail closed.
rm "$test_repo/SOURCE_REF"
check_bad
printf 'a%.0s' {1..40} > "$test_repo/SOURCE_REF"
printf '\n' >> "$test_repo/SOURCE_REF"
git -C "$test_repo" add SOURCE_REF
check_ok
# A different tracked source deleted only from the working tree must also fail.
rm "$test_repo/src/hello.ores"
check_bad
printf '00_abc\n' > "$test_repo/src/hello.ores"
git -C "$test_repo" add src/hello.ores
check_ok
# An inherited empty index must not hide a tracked forbidden source. This
# reproduces the prior zero-file policy bypass when SOURCE_REF is optional.
git -C "$test_repo" rm -q -f -- SOURCE_REF
printf 'print(1)\n' > "$test_repo/src/hidden.py"
git -C "$test_repo" add src/hidden.py
GIT_INDEX_FILE="$test_repo/.git/nonexistent-index" check_bad
git -C "$test_repo" rm -q -f -- src/hidden.py
check_ok
# A corrupted real index must fail instead of being masked by process substitution.
cp "$test_repo/.git/index" "$test_repo/index-backup"
printf 'corrupt-index\n' > "$test_repo/.git/index"
check_bad
mv "$test_repo/index-backup" "$test_repo/.git/index"
check_ok
# A symlinked parent to identical external bytes bypassed leaf -L checks.
external_dir="$test_repo.external"
mkdir -p "$external_dir"
cp "$test_repo/src/hello.ores" "$external_dir/hello.ores"
mv "$test_repo/src" "$test_repo/src-original"
ln -s "$external_dir" "$test_repo/src"
check_bad
rm "$test_repo/src"
mv "$test_repo/src-original" "$test_repo/src"
rm -rf "$external_dir"
check_ok
# Hardlinks retain exact Git blob bytes and ordinary permissions but allow
# writes via an external alias after source admission: reject before execution.
external_hardlink="$test_repo.external-hardlink"
ln -- "$test_repo/src/hello.ores" "$external_hardlink"
check_bad
rm -- "$external_hardlink"
check_ok
# A staged Python interpreter cannot be hidden by a benign worktree file.
printf 'safe\n' > "$test_repo/src/disguised.txt"
git -C "$test_repo" add src/disguised.txt
check_ok
forged_blob="$(printf '#!/usr/bin/env python3\nprint(1)\n' | git -C "$test_repo" hash-object -w --stdin)"
git -C "$test_repo" update-index --cacheinfo "100644,$forged_blob,src/disguised.txt"
check_bad
git -C "$test_repo" add src/disguised.txt
check_ok
git -C "$test_repo" rm -q -f -- src/disguised.txt
check_ok
# A SHA-pinned production audit must not be redirected to a clean sibling
# checkout. Both clones have identical HEAD but the invoking tree is dirty.
redirect_case="$test_repo/sha-override"
git init -q "$redirect_case/clean"
git -C "$redirect_case/clean" config user.name "Policy test"
git -C "$redirect_case/clean" config user.email "policy@example.invalid"
mkdir -p "$redirect_case/clean/src"
printf 'safe\n' > "$redirect_case/clean/src/hello.ores"
git -C "$redirect_case/clean" add .
git -C "$redirect_case/clean" commit -q -m 'clean baseline'
git clone -q "$redirect_case/clean" "$redirect_case/dirty"
mkdir -p "$redirect_case/dirty/ci"
cp "$root/ci/source-policy.sh" "$redirect_case/dirty/ci/source-policy.sh"
printf '#!/usr/bin/env python3\n' > "$redirect_case/dirty/src/hello.ores"
redirect_sha="$(git -C "$redirect_case/dirty" rev-parse HEAD)"
if SOURCE_POLICY_ROOT="$redirect_case/clean" EXPECTED_DEMO_SHA="$redirect_sha" \
  bash "$redirect_case/dirty/ci/source-policy.sh" > "$redirect_case/result.log" 2>&1; then
  echo "TEST_FAILURE: SHA-pinned policy accepted redirected clean checkout" >&2
  exit 1
fi
grep -Fq 'POLICY_FAILURE: SHA-pinned audit cannot redirect SOURCE_POLICY_ROOT' "$redirect_case/result.log" || {
  echo "TEST_FAILURE: redirected SHA-pinned audit did not fail at root binding" >&2
  exit 1
}
# The pinned commit must bind the INDEX and worktree, not merely HEAD.
# Before this fix, deleting a tracked file from both the index and worktree
# left the old index-only policy blind to its presence in the pinned commit.
pinned_repo="$test_repo/pinned-audit"
mkdir -p "$pinned_repo/ci" "$pinned_repo/docs"
cp "$root/ci/source-policy.sh" "$pinned_repo/ci/source-policy.sh"
printf 'safe tracked bytes\n' > "$pinned_repo/docs/allowed.txt"
git init -q "$pinned_repo"
git -C "$pinned_repo" config user.name 'Policy pinned test'
git -C "$pinned_repo" config user.email 'policy@example.invalid'
git -C "$pinned_repo" add .
git -C "$pinned_repo" commit -q -m 'exact pinned source'
pinned_sha="$(git -C "$pinned_repo" rev-parse HEAD)"
EXPECTED_DEMO_SHA="$pinned_sha" bash "$pinned_repo/ci/source-policy.sh" > /dev/null || {
  echo 'TEST_FAILURE: clean SHA-pinned checkout was rejected' >&2; exit 1;
}
git -C "$pinned_repo" rm -q -- docs/allowed.txt
if EXPECTED_DEMO_SHA="$pinned_sha" bash "$pinned_repo/ci/source-policy.sh" >/dev/null 2>&1; then
  echo 'TEST_FAILURE: removed tracked HEAD blob escaped exact-source audit' >&2; exit 1
fi
git -C "$pinned_repo" reset --hard -q HEAD
printf 'unreviewed safe file\n' > "$pinned_repo/docs/addition.txt"
git -C "$pinned_repo" add docs/addition.txt
if EXPECTED_DEMO_SHA="$pinned_sha" bash "$pinned_repo/ci/source-policy.sh" >/dev/null 2>&1; then
  echo 'TEST_FAILURE: newly staged file escaped exact-source audit' >&2; exit 1
fi
git -C "$pinned_repo" reset --hard -q HEAD
# An ignored file is still an unexpected input to the pinned checkout.
printf 'ignored\n' > "$pinned_repo/docs/ignored.txt"
printf 'docs/ignored.txt\n' > "$pinned_repo/.git/info/exclude"
if EXPECTED_DEMO_SHA="$pinned_sha" bash "$pinned_repo/ci/source-policy.sh" >/dev/null 2>&1; then
  echo 'TEST_FAILURE: ignored untracked file escaped exact-source audit' >&2; exit 1
fi
rm "$pinned_repo/docs/ignored.txt"
EXPECTED_DEMO_SHA="$pinned_sha" bash "$pinned_repo/ci/source-policy.sh" > /dev/null || {
  echo 'TEST_FAILURE: pinned checkout failed after fixture recovery' >&2; exit 1;
}
# Exact-head audit must also reject the same cross-checkout hardlink alias.
external_pinned_hardlink="$test_repo.pinned-external-hardlink"
ln -- "$pinned_repo/docs/allowed.txt" "$external_pinned_hardlink"
if EXPECTED_DEMO_SHA="$pinned_sha" bash "$pinned_repo/ci/source-policy.sh" >/dev/null 2>&1; then
  echo 'TEST_FAILURE: pinned source admitted externally aliased tracked inode' >&2; exit 1
fi
rm -- "$external_pinned_hardlink"
EXPECTED_DEMO_SHA="$pinned_sha" bash "$pinned_repo/ci/source-policy.sh" >/dev/null || {
  echo 'TEST_FAILURE: pinned source did not recover after hardlink removal' >&2; exit 1
}
# A checkout with core.filemode=false must not hide executable-bit drift.
# The policy explicitly forces core.filemode=true for its HEAD comparisons.
git -C "$pinned_repo" config core.filemode false
chmod +x "$pinned_repo/docs/allowed.txt"
if EXPECTED_DEMO_SHA="$pinned_sha" bash "$pinned_repo/ci/source-policy.sh" >/dev/null 2>&1; then
  echo 'TEST_FAILURE: executable-bit drift escaped SHA-pinned audit with core.filemode=false' >&2
  exit 1
fi
chmod -x "$pinned_repo/docs/allowed.txt"
git -C "$pinned_repo" config --unset core.filemode
EXPECTED_DEMO_SHA="$pinned_sha" bash "$pinned_repo/ci/source-policy.sh" > /dev/null || {
  echo 'TEST_FAILURE: pinned checkout rejected after chmod fixture recovery' >&2; exit 1;
}
# Git index hints can suppress the diff that normally catches chmod drift.
# The policy must compare actual filesystem mode to the committed Git mode.
for hint in assume-unchanged skip-worktree; do
  git -C "$pinned_repo" update-index "--$hint" -- docs/allowed.txt
  chmod +x "$pinned_repo/docs/allowed.txt"
  if EXPECTED_DEMO_SHA="$pinned_sha" bash "$pinned_repo/ci/source-policy.sh" >/dev/null 2>&1; then
    echo "TEST_FAILURE: $hint concealed executable-bit drift" >&2; exit 1
  fi
  chmod -x "$pinned_repo/docs/allowed.txt"
  git -C "$pinned_repo" update-index "--no-$hint" -- docs/allowed.txt
  EXPECTED_DEMO_SHA="$pinned_sha" bash "$pinned_repo/ci/source-policy.sh" > /dev/null || {
    echo "TEST_FAILURE: pinned checkout rejected after $hint recovery" >&2; exit 1
  }
done
# A migration-only Python exception must never be accepted by SHA-pinned
# production admission, even with a clean tracked Git tree and matching HEAD.
legacy_repo="$test_repo/legacy-pinned-mode"
mkdir -p "$legacy_repo/ci" "$legacy_repo/scripts"
cp "$root/ci/source-policy.sh" "$legacy_repo/ci/source-policy.sh"
printf 'print(1)\n' > "$legacy_repo/scripts/benchmark.py"
git init -q "$legacy_repo"
git -C "$legacy_repo" config user.name 'Legacy policy test'
git -C "$legacy_repo" config user.email 'policy@example.invalid'
git -C "$legacy_repo" add .
git -C "$legacy_repo" commit -q -m 'legacy allowlisted source'
legacy_sha="$(git -C "$legacy_repo" rev-parse HEAD)"
SOURCE_POLICY_MODE=rest-legacy bash "$legacy_repo/ci/source-policy.sh" >/dev/null || {
  echo 'TEST_FAILURE: unpinned legacy fixture compatibility regressed' >&2; exit 1
}
if SOURCE_POLICY_MODE=rest-legacy EXPECTED_DEMO_SHA="$legacy_sha" \
  bash "$legacy_repo/ci/source-policy.sh" > "$test_repo/legacy-rejection.log" 2>&1; then
  echo 'TEST_FAILURE: SHA-pinned audit accepted migration-only Python exemption' >&2
  exit 1
fi
grep -Fq 'POLICY_FAILURE: SHA-pinned source policy requires strict mode' "$test_repo/legacy-rejection.log" || {
  echo 'TEST_FAILURE: pinned legacy exemption failed for wrong reason' >&2; exit 1
}
# A harmless extension cannot make mutated worktree bytes match the pinned index.
printf 'changed after staging\n' > "$test_repo/src/hello.ores"
check_bad
printf '00_abc\n' > "$test_repo/src/hello.ores"
check_ok
# Neither a foreign Git repository nor caller-supplied Git config may redirect
# the audit away from the pinned checkout's own index and object database.
poison_repo="$(mktemp -d)"
git init -q "$poison_repo"
GIT_DIR="$poison_repo/.git" GIT_WORK_TREE="$poison_repo" check_ok
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.bare GIT_CONFIG_VALUE_0=true check_ok
rm -rf -- "$poison_repo"
# Inherited Git identity, replacement-object and index controls must not
# redirect the audit to caller-provided metadata or an empty index.
GIT_INDEX_FILE="$test_repo/.git/empty-index-from-caller" check_ok
GIT_OBJECT_DIRECTORY="$test_repo/.git/nonexistent-object-store" check_ok
GIT_ALTERNATE_OBJECT_DIRECTORIES="$test_repo/nonexistent-alternate" check_ok
GIT_REPLACE_REF_BASE="refs/replace/foreign" check_ok
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.bare GIT_CONFIG_VALUE_0=true check_ok
# A stale expected-HEAD pin remains a refusal even with malicious Git controls.
GIT_INDEX_FILE="$test_repo/.git/empty-index-from-caller" \
  EXPECTED_DEMO_SHA="$(printf '0%.0s' {1..40})" check_bad
# A well-formed but stale external expected-HEAD claim must be rejected.
EXPECTED_DEMO_SHA="$(printf '0%.0s' {1..40})" check_bad
check_ok
printf 'SOURCE_POLICY_NEGATIVE_TESTS_PASS scenarios=37\n'
