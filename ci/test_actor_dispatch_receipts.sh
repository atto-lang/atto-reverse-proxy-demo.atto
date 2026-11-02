#!/usr/bin/env bash
# Host-only synthetic receipt-verifier checks. No Oreslang guest is executed.
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
hd=ORES_PROXY_TEST_DISPATCH_HELLO
hc=ORES_PROXY_TEST_CLAIM_HELLO
sd=ORES_PROXY_TEST_DISPATCH_STREAM
sc=ORES_PROXY_TEST_CLAIM_STREAM
fd=ORES_PROXY_TEST_DISPATCH_FALLBACK
fc=ORES_PROXY_TEST_CLAIM_FALLBACK
emit_valid() {
  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
    "$hd" "$hc" "$hd" "$hc" "$hd" "$hc" "$fd" "$fc" "$sd" "$sc" > "$log"
}
expect_pass() {
  if ! /bin/bash --noprofile --norc "$verifier" "$log" > "$scratch/out" 2>&1; then
    printf 'FAIL expected receipt pass: %s\n' "$1" >&2
    /bin/cat "$scratch/out" >&2
    exit 1
  fi
  printf 'PASS synthetic actor receipts: %s\n' "$1"
}
expect_fail() {
  if /bin/bash --noprofile --norc "$verifier" "$log" > "$scratch/out" 2>&1; then
    printf 'FAIL accepted invalid actor receipt: %s\n' "$1" >&2
    exit 1
  fi
  printf 'PASS rejected synthetic actor receipts: %s\n' "$1"
}
remove_first() {
  /usr/bin/sed -i "0,/^$1$/s/^$1$//" "$log"
}
emit_valid; expect_pass exact_counts
emit_valid; printf '%s\n' "$sd" >> "$log"; expect_pass abandoned_stream_dispatch
emit_valid; printf '%s\n%s\n' "$sd" "$sc" >> "$log"; expect_pass second_stream_claim
emit_valid; for _ in 1 2 3 4; do printf '%s\n' "$sd" >> "$log"; done; expect_pass five_stream_dispatches
emit_valid; for _ in 1 2 3 4; do printf '%s\n%s\n' "$sd" "$sc" >> "$log"; done; expect_pass five_stream_claims
# Equal final counts cannot excuse a claim preceding its own dispatch.
# Swap the first pair for each actor type without changing any totals.
emit_valid; /usr/bin/sed -i '1s/DISPATCH/CLAIM/;2s/CLAIM/DISPATCH/' "$log"; expect_fail claim_precedes_hello_dispatch
emit_valid; /usr/bin/sed -i '7s/DISPATCH/CLAIM/;8s/CLAIM/DISPATCH/' "$log"; expect_fail claim_precedes_fallback_dispatch
emit_valid; /usr/bin/sed -i '9s/DISPATCH/CLAIM/;10s/CLAIM/DISPATCH/' "$log"; expect_fail claim_precedes_stream_dispatch
emit_valid; printf '%s\n' "$hd" >> "$log"; expect_fail unexpected_hello_dispatch
emit_valid; remove_first "$hd"; expect_fail missing_hello_dispatch
emit_valid; printf '%s\n' "$hc" >> "$log"; expect_fail unexpected_hello_claim
emit_valid; remove_first "$hc"; expect_fail missing_hello_claim
emit_valid; printf '%s\n' "$fd" >> "$log"; expect_fail unexpected_fallback_dispatch
emit_valid; remove_first "$fd"; expect_fail missing_fallback_dispatch
emit_valid; printf '%s\n' "$fc" >> "$log"; expect_fail unexpected_fallback_claim
emit_valid; remove_first "$fc"; expect_fail missing_fallback_claim
emit_valid; remove_first "$sd"; expect_fail missing_stream_dispatch
emit_valid; remove_first "$sc"; expect_fail missing_stream_claim
emit_valid; printf '%s\n' "$sc" >> "$log"; expect_fail stream_claim_exceeds_dispatch
emit_valid; printf '%s\n' 'ORES_PROXY_TEST_DISPATCH_UNKNOWN' >> "$log"; expect_fail unknown_dispatch_marker
emit_valid; printf '%s\n' 'ORES_PROXY_TEST_CLAIM_UNKNOWN' >> "$log"; expect_fail unknown_claim_marker
emit_valid; /usr/bin/ln -s "$log" "$scratch/symlink"
if /bin/bash --noprofile --norc "$verifier" "$scratch/symlink" > /dev/null 2>&1; then
  echo 'FAIL accepted symlinked receipt log' >&2; exit 1
fi
echo 'PASS rejected synthetic actor receipts: symlink_log'
/usr/bin/head -c 1048577 /dev/zero > "$log"; expect_fail oversized_log
if /bin/bash --noprofile --norc "$verifier" "$scratch/missing" > /dev/null 2>&1; then
  echo 'FAIL accepted missing receipt log' >&2; exit 1
fi
echo 'PASS rejected synthetic actor receipts: missing_log'
echo 'SOURCE_FREE_ACTOR_CLAIM_RECEIPT_TESTS_PASS=24/24; NATIVE_ORESLANG_NOT_EXECUTED'
