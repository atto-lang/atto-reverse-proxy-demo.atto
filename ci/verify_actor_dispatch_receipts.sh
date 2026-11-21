#!/usr/bin/env bash
# Fixed host-side counts for opt-in supervisor dispatch and actor claim markers.
# Only native TCP execution against the same listener produces runtime evidence.
set -euo pipefail
export LC_ALL=C
if (( $# != 1 )); then
  echo 'usage: verify_actor_dispatch_receipts.sh <server-log>' >&2
  exit 64
fi
log=$1
if [[ ! -f "$log" || -L "$log" ]]; then
  echo 'missing or symlinked actor receipt log' >&2
  exit 65
fi
size=$(/usr/bin/stat -c %s -- "$log")
if (( size > 1048576 )); then
  echo 'actor receipt log exceeds 1 MiB bound' >&2
  exit 65
fi
# Fixed markers come from stdio.println, so the final record must end
# in a newline. GNU grep -x and Bash read also count an unterminated
# final marker, allowing a truncated log to look like a complete receipt.
# Reject that ambiguous boundary before performing independent count reads.
if (( size == 0 )) ||
  [[ "$(/usr/bin/tail -c 1 -- "$log" | /usr/bin/od -An -tu1 | /usr/bin/tr -d '[:space:]')" != 10 ]]; then
  echo 'actor receipt log ends with an incomplete record' >&2
  exit 65
fi
# Full-line markers only; the guest never includes request-controlled bytes.
hello=$(/usr/bin/grep -Fxc 'ORES_PROXY_TEST_DISPATCH_HELLO' -- "$log" || true)
hello_claim=$(/usr/bin/grep -Fxc 'ORES_PROXY_TEST_CLAIM_HELLO' -- "$log" || true)
stream=$(/usr/bin/grep -Fxc 'ORES_PROXY_TEST_DISPATCH_STREAM' -- "$log" || true)
stream_claim=$(/usr/bin/grep -Fxc 'ORES_PROXY_TEST_CLAIM_STREAM' -- "$log" || true)
fallback=$(/usr/bin/grep -Fxc 'ORES_PROXY_TEST_DISPATCH_FALLBACK' -- "$log" || true)
fallback_claim=$(/usr/bin/grep -Fxc 'ORES_PROXY_TEST_CLAIM_FALLBACK' -- "$log" || true)
all=$(/usr/bin/grep -Ec '^ORES_PROXY_TEST_(DISPATCH|CLAIM)_' -- "$log" || true)
for count in "$hello" "$hello_claim" "$stream" "$stream_claim" "$fallback" "$fallback_claim" "$all"; do
  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    echo 'malformed actor receipt count' >&2
    exit 1
  fi
done
# Three valid Hello responses and one admitted fallback must have matching
# actor-side claims. Four disconnected stream requests may be dropped before
# claim; require at least the one complete streaming response to be claimed.
# These counts do not prove quiescence or physical resource retirement.
if (( hello != 3 || hello_claim != 3 || fallback != 1 || fallback_claim != 1 ||
      stream < 1 || stream > 5 || stream_claim < 1 || stream_claim > stream ||
      all != hello + hello_claim + fallback + fallback_claim + stream + stream_claim )); then
  printf 'FAIL actor receipts hello=%s/%s fallback=%s/%s stream=%s/%s total=%s\n' \
    "$hello_claim" "$hello" "$fallback_claim" "$fallback" "$stream_claim" "$stream" "$all" >&2
  exit 1
fi
# A matching aggregate count alone can conceal claims logged before any
# supervisor dispatch. Each actor's observed claim prefix must be bounded by
# its dispatch prefix. This is a log-order check, not a proof of task retirement.
hello_seen=0
hello_claim_seen=0
stream_seen=0
stream_claim_seen=0
fallback_seen=0
fallback_claim_seen=0
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    ORES_PROXY_TEST_DISPATCH_HELLO) ((hello_seen+=1)) ;;
    ORES_PROXY_TEST_CLAIM_HELLO) ((hello_claim_seen+=1)) ;;
    ORES_PROXY_TEST_DISPATCH_STREAM) ((stream_seen+=1)) ;;
    ORES_PROXY_TEST_CLAIM_STREAM) ((stream_claim_seen+=1)) ;;
    ORES_PROXY_TEST_DISPATCH_FALLBACK) ((fallback_seen+=1)) ;;
    ORES_PROXY_TEST_CLAIM_FALLBACK) ((fallback_claim_seen+=1)) ;;
  esac
  if (( hello_claim_seen > hello_seen || stream_claim_seen > stream_seen ||
        fallback_claim_seen > fallback_seen )); then
    echo 'FAIL actor claim precedes supervisor dispatch in receipt log' >&2
    exit 1
  fi
done < "$log"
printf 'PASS actor claim/dispatch receipts hello=%s/%s fallback=%s/%s stream=%s/%s; NOT task-retirement proof\n' \
  "$hello_claim" "$hello" "$fallback_claim" "$fallback" "$stream_claim" "$stream"
