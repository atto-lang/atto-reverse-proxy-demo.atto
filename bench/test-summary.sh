#!/usr/bin/env bash
set -euo pipefail
bench=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
printf '%s\n' '[
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":10,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":30,"p50_us":3,"p95_us":4,"p99_us":5},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":20,"p50_us":2,"p95_us":3,"p99_us":4},
{"status":"BLOCKED_OR_INVALID","target":"oreslang","profile":"forward"}
]' | jq -f "$bench/summarize.jq" | jq -e '
.passed[0].repetitions == 3 and .passed[0].requests_per_second.median == 20 and
.passed[0].requests_per_second.min == 10 and .passed[0].requests_per_second.max == 30 and
.passed[0].p99_us.median == 4 and (.blocked_or_invalid | length) == 1' >/dev/null
printf '%s\n' 'PASS summary aggregation and exclusion of blocked results'
