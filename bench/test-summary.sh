#!/usr/bin/env bash
set -euo pipefail
bench=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
printf '%s\n' '[
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":10,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":30,"p50_us":3,"p95_us":4,"p99_us":5},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":20,"p50_us":2,"p95_us":3,"p99_us":4},
{"status":"PASS","target":"haproxy","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":54,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":50,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":60,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":55,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"BLOCKED_OR_INVALID","target":"oreslang","profile":"forward"}
]' | jq -f "$bench/summarize.jq" | jq -e '
.schema == 2 and
(.passed[] | select(.target == "nginx")).repetitions == 3 and
(.passed[] | select(.target == "nginx")).requests_per_second.median == 20 and
(.passed[] | select(.target == "nginx")).capacity_status == "PASS" and
(.passed[] | select(.target == "nginx")).metrics_comparable == true and
(.passed[] | select(.target == "haproxy")).capacity_status == "BOTTLENECKED" and
(.passed[] | select(.target == "haproxy")).metrics_comparable == false and
.capacity_gate_passed == false and
(.blocked_or_invalid | length) == 1' >/dev/null
printf '%s\n' 'PASS summary aggregation, blocked exclusion and direct-capacity gate'

# An empty/invalid dataset must never qualify as a publishable comparison.
printf '%s\n' '[]' | jq -f "$bench/summarize.jq" | jq -e '.capacity_gate_passed == false' >/dev/null
printf '%s\n' '[
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":100,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":20,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"BLOCKED_OR_INVALID","target":"direct","profile":"forward","bytes":0,"concurrency":1,"repeat":2}
]' | jq -f "$bench/summarize.jq" | jq -e '.capacity_gate_passed == false' >/dev/null
printf '%s\n' 'PASS empty and failed-direct-reference fail-closed gates'

# A healthy direct reference with >=1.20x headroom must make the gate reachable.
printf '%s\n' '[
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":120,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":80,"p50_us":2,"p95_us":3,"p99_us":4},
{"status":"PASS","target":"haproxy","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":90,"p50_us":2,"p95_us":3,"p99_us":4}
]' | jq -f "$bench/summarize.jq" | jq -e '
.capacity_gate_passed == true and
([.passed[] | select(.target != "direct")] | all(.capacity_status == "PASS" and .metrics_comparable == true))' >/dev/null
printf '%s\n' 'PASS healthy direct-capacity gate is reachable'

# A proxy result without the matching direct reference must fail closed.
printf '%s\n' '[
{"status":"PASS","target":"nginx","profile":"forward","bytes":1024,"concurrency":16,"requests_per_second":100,"p50_us":2,"p95_us":3,"p99_us":4}
]' | jq -f "$bench/summarize.jq" | jq -e '
.capacity_gate_passed == false and
(.passed[] | select(.target == "nginx")).capacity_status == "NO_DIRECT_BASELINE" and
(.passed[] | select(.target == "nginx")).metrics_comparable == false' >/dev/null
printf '%s\n' 'PASS missing direct baseline fails closed'
