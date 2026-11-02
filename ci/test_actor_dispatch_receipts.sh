#!/usr/bin/env bash
# Synthetic host verifier tests only, not native Oreslang runtime evidence.
set -euo pipefail
export LC_ALL=C
if (( $# != 1 )); then
  echo 'usage: test_actor_dispatch_receipts.sh <verifier>' >&2
  exit 64
fi
verifier=$1
if [[ ! -f "$verifier" || -L "$verifier" ]]; then
  echo 'missing or symlinked verifier' >&2
  exit 65
fi
scratch=$(/usr/bin/mktemp -d)
trap '/usr/bin/rm -rf -- "$scratch"' EXIT
log="$scratch/server.log"
hello=ORES_PROXY_TEST_DISPATCH_HELLO
stream=ORES_PROXY_TEST_DISPATCH_STREAM
fallback=ORES_PROXY_TEST_DISPATCH_FALLBACK
emit_valid() {
  printf '%s\n%s\n%s\n%s\n%s\n' "$hello" "$hello" "$hello" "$fallback" "$stream" > "$log"
}
expect_pass() {
  if ! /bin/bash --noprofile --norc "$verifier" "$log" > "$scratch/out" 2>&1; then
    echo "FAIL expected receipt pass: $1" >&2
    /bin/cat "$scratch/out" >&2
    exit 1
  fi
  echo "PASS synthetic dispatch verifier: $1"
}
expect_fail() {
  if /bin/bash --noprofile --norc "$verifier" "$log" > "$scratch/out" 2>&1; then
    echo "FAIL accepted invalid dispatch receipt: $1" >&2
    exit 1
  fi
  echo "PASS synthetic dispatch rejection: $1"
}
emit_valid; expect_pass exact_counts
printf '%s\n' "$stream" >> "$log"; expect_pass extra_abandoned_stream
emit_valid; printf '%s\n' "$hello" >> "$log"; expect_fail unexpected_hello_dispatch
emit_valid; /usr/bin/sed -i '1d' "$log"; expect_fail missing_hello_dispatch
emit_valid; printf '%s\n' "$fallback" >> "$log"; expect_fail unexpected_fallback
emit_valid; /usr/bin/sed -i "/$fallback/d" "$log"; expect_fail missing_fallback
emit_valid; /usr/bin/sed -i "/$stream/d" "$log"; expect_fail missing_stream
emit_valid; printf '%s\n' 'ORES_PROXY_TEST_DISPATCH_UNEXPECTED' >> "$log"; expect_fail unknown_dispatch_marker
emit_valid; /usr/bin/ln -s "$log" "$scratch/symlink"
if /bin/bash --noprofile --norc "$verifier" "$scratch/symlink" >/dev/null 2>&1; then
  echo 'FAIL accepted symlinked dispatch log' >&2; exit 1
fi
echo 'PASS synthetic dispatch rejection: symlink_log'
/usr/bin/head -c 1048577 /dev/zero > "$log"
expect_fail oversized_log
printf 'SOURCE_FREE_DISPATCH_RECEIPT_TESTS_PASS=10/10; NATIVE_ORESLANG_NOT_EXECUTED\n'
