#!/usr/bin/env bash
set -euo pipefail
bench=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Matrix construction must produce numeric [bytes, concurrency] pairs. Parentheses
# are intentional: jq's comma/pipe precedence otherwise indexes a string.
expected_matrix=$(printf '%s\n' '0 1' '1024 1' '0 8' '1024 8' | jq -Rsc -f "$bench/matrix.jq")
printf '%s\n' "$expected_matrix" | jq -e '. == [[0,1],[0,8],[1024,1],[1024,8]]' >/dev/null
printf '%s\n' 'PASS expected benchmark matrix is numeric and deterministically sorted'

# Complete matrix, but HAProxy lacks enough direct headroom: gate must fail.
printf '%s\n' '[
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":10,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":30,"p50_us":3,"p95_us":4,"p99_us":5},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":20,"p50_us":2,"p95_us":3,"p99_us":4},
{"status":"PASS","target":"haproxy","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":54,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"haproxy","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":54,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"haproxy","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":54,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":50,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":60,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":55,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"BLOCKED_OR_INVALID","target":"oreslang","profile":"forward"}
]' | jq --argjson expected_repetitions 3 --argjson expected_baseline_groups 1 --argjson expected_matrix '[[0,1]]' -f "$bench/summarize.jq" | jq -e '
.schema == 4 and
.baseline_matrix_complete == true and
(.passed[] | select(.target == "nginx")).repetitions == 3 and
(.passed[] | select(.target == "nginx")).requests_per_second.median == 20 and
(.passed[] | select(.target == "nginx")).capacity_status == "PASS" and
(.passed[] | select(.target == "nginx")).metrics_comparable == true and
(.passed[] | select(.target == "haproxy")).capacity_status == "BOTTLENECKED" and
(.passed[] | select(.target == "haproxy")).metrics_comparable == false and
.capacity_gate_passed == false and
(.blocked_or_invalid | length) == 1' >/dev/null
printf '%s\n' 'PASS complete matrix detects bottlenecked proxy'

# Empty input must never qualify.
printf '%s\n' '[]' | jq --argjson expected_repetitions 1 --argjson expected_baseline_groups 1 --argjson expected_matrix '[[0,1]]' -f "$bench/summarize.jq" | jq -e '
.baseline_matrix_complete == false and .capacity_gate_passed == false' >/dev/null

# A failed direct reference must fail closed.
printf '%s\n' '[
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":100,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":20,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"haproxy","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":20,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"BLOCKED_OR_INVALID","target":"direct","profile":"forward","bytes":0,"concurrency":1,"repeat":2}
]' | jq --argjson expected_repetitions 1 --argjson expected_baseline_groups 1 --argjson expected_matrix '[[0,1]]' -f "$bench/summarize.jq" | jq -e '.capacity_gate_passed == false' >/dev/null
printf '%s\n' 'PASS empty and failed-direct-reference fail-closed gates'

# A healthy complete matrix with >=1.20x headroom must make the gate reachable.
printf '%s\n' '[
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":120,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":80,"p50_us":2,"p95_us":3,"p99_us":4},
{"status":"PASS","target":"haproxy","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":90,"p50_us":2,"p95_us":3,"p99_us":4}
]' | jq --argjson expected_repetitions 1 --argjson expected_baseline_groups 1 --argjson expected_matrix '[[0,1]]' -f "$bench/summarize.jq" | jq -e '
.capacity_gate_passed == true and
.baseline_matrix_complete == true and
([.passed[] | select(.target != "direct")] | all(.capacity_status == "PASS" and .metrics_comparable == true))' >/dev/null
printf '%s\n' 'PASS healthy direct-capacity gate is reachable'

# A missing baseline target must fail even when the remaining proxy has headroom.
printf '%s\n' '[
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":120,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":80,"p50_us":2,"p95_us":3,"p99_us":4}
]' | jq --argjson expected_repetitions 1 --argjson expected_baseline_groups 1 --argjson expected_matrix '[[0,1]]' -f "$bench/summarize.jq" | jq -e '
.baseline_matrix_complete == false and .capacity_gate_passed == false' >/dev/null

# A complete target set with fewer repetitions than required must also fail.
printf '%s\n' '[
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":120,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":80,"p50_us":2,"p95_us":3,"p99_us":4},
{"status":"PASS","target":"haproxy","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":90,"p50_us":2,"p95_us":3,"p99_us":4}
]' | jq --argjson expected_repetitions 2 --argjson expected_baseline_groups 1 --argjson expected_matrix '[[0,1]]' -f "$bench/summarize.jq" | jq -e '
.baseline_matrix_complete == false and .capacity_gate_passed == false' >/dev/null
printf '%s\n' 'PASS missing target and incomplete repetition matrix fail closed'

# A proxy result without the matching direct reference must remain non-comparable.
printf '%s\n' '[
{"status":"PASS","target":"nginx","profile":"forward","bytes":1024,"concurrency":16,"requests_per_second":100,"p50_us":2,"p95_us":3,"p99_us":4}
]' | jq --argjson expected_repetitions 1 --argjson expected_baseline_groups 1 --argjson expected_matrix '[[0,1]]' -f "$bench/summarize.jq" | jq -e '
.capacity_gate_passed == false and
.baseline_matrix_complete == false and
(.passed[] | select(.target == "nginx")).capacity_status == "NO_DIRECT_BASELINE" and
(.passed[] | select(.target == "nginx")).metrics_comparable == false' >/dev/null
printf '%s\n' 'PASS missing direct baseline fails closed'

# If a whole expected body-size/concurrency combination is absent for every baseline,
# it must still fail closed; observed keys alone cannot define completeness.
printf '%s\n' '[
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":120,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":80,"p50_us":2,"p95_us":3,"p99_us":4},
{"status":"PASS","target":"haproxy","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":90,"p50_us":2,"p95_us":3,"p99_us":4}
]' | jq --argjson expected_repetitions 1 --argjson expected_baseline_groups 2 --argjson expected_matrix '[[0,1],[1024,1]]' -f "$bench/summarize.jq" | jq -e '
.baseline_matrix_complete == false and
(.baseline_matrix | length) == 2 and
.capacity_gate_passed == false' >/dev/null
printf '%s\n' 'PASS wholly missing matrix combination fails closed'


# Cardinality alone is insufficient: an unexpected key must not substitute for an expected one.
printf '%s\n' '[
{"status":"PASS","target":"direct","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":120,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"nginx","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":80,"p50_us":2,"p95_us":3,"p99_us":4},
{"status":"PASS","target":"haproxy","profile":"forward","bytes":0,"concurrency":1,"requests_per_second":90,"p50_us":2,"p95_us":3,"p99_us":4},
{"status":"PASS","target":"direct","profile":"forward","bytes":2048,"concurrency":1,"requests_per_second":120,"p50_us":1,"p95_us":2,"p99_us":3},
{"status":"PASS","target":"nginx","profile":"forward","bytes":2048,"concurrency":1,"requests_per_second":80,"p50_us":2,"p95_us":3,"p99_us":4},
{"status":"PASS","target":"haproxy","profile":"forward","bytes":2048,"concurrency":1,"requests_per_second":90,"p50_us":2,"p95_us":3,"p99_us":4}
]' | jq --argjson expected_repetitions 1 --argjson expected_baseline_groups 2 --argjson expected_matrix '[[0,1],[1024,1]]' -f "$bench/summarize.jq" | jq -e '
.baseline_matrix_membership_exact == false and
.baseline_matrix_complete == false and
.capacity_gate_passed == false' >/dev/null
printf '%s\n' 'PASS unexpected matrix substitution fails closed'
