#!/usr/bin/env bash
# Source-free verification of fixed dispatch-site markers. Real evidence only
# when run after the Oreslang native TCP test against the same server process.
set -euo pipefail
export LC_ALL=C
if (( $# != 1 )); then
  echo 'usage: verify_actor_dispatch_receipts.sh <server-log>' >&2
  exit 64
fi
log=$1
if [[ ! -f "$log" || -L "$log" ]]; then
  echo 'missing or symlinked actor dispatch log' >&2
  exit 65
fi
# Do not parse unbounded output even if a damaged guest floods the runner.
size=$(/usr/bin/stat -c %s -- "$log")
if (( size > 1048576 )); then
  echo 'actor dispatch log exceeds 1 MiB bound' >&2
  exit 65
fi
# Match full, constant lines. The test never interprets raw request metadata.
hello=$(/usr/bin/grep -Fxc 'ORES_PROXY_TEST_DISPATCH_HELLO' -- "$log" || true)
stream=$(/usr/bin/grep -Fxc 'ORES_PROXY_TEST_DISPATCH_STREAM' -- "$log" || true)
fallback=$(/usr/bin/grep -Fxc 'ORES_PROXY_TEST_DISPATCH_FALLBACK' -- "$log" || true)
all=$(/usr/bin/grep -c '^ORES_PROXY_TEST_DISPATCH_' -- "$log" || true)
if [[ ! "$hello" =~ ^[0-9]+$ || ! "$stream" =~ ^[0-9]+$ ||
      ! "$fallback" =~ ^[0-9]+$ || ! "$all" =~ ^[0-9]+$ ]]; then
  echo 'malformed dispatch count' >&2
  exit 1
fi
# Three complete, successful hello requests; one deliberately admitted /api
# fallback; one complete streamed response. Four abandoned streams may or may
# not reach dispatch depending on cancellation timing and are not a proof of
# task retirement or physical loan release.
if (( hello != 3 || fallback != 1 || stream < 1 || stream > 5 ||
      all != hello + fallback + stream )); then
  printf 'FAIL dispatch receipts hello=%s fallback=%s stream=%s total=%s\n' \
    "$hello" "$fallback" "$stream" "$all" >&2
  exit 1
fi
printf 'PASS dispatch-site receipts hello=%s fallback=%s stream=%s; NOT actor-claim or retirement proof\n' \
  "$hello" "$fallback" "$stream"
