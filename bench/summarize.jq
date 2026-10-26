def median: sort | if length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end;
def stats: {median: median, min: min, max: max};
def baseline_target: . == "direct" or . == "nginx" or . == "haproxy";
([.[] | select(.status == "PASS")]
  | group_by([.target, .profile, .bytes, .concurrency])
  | map({target: .[0].target, profile: .[0].profile, bytes: .[0].bytes,
         concurrency: .[0].concurrency, repetitions: length,
         requests_per_second: (map(.requests_per_second) | stats),
         p50_us: (map(.p50_us) | stats), p95_us: (map(.p95_us) | stats),
         p99_us: (map(.p99_us) | stats)})) as $base
| ($base | map(
    if .profile == "forward" and .target != "direct" then
      . as $p
      | ([$base[] | select(.target == "direct" and .profile == "forward" and
          .bytes == $p.bytes and .concurrency == $p.concurrency)] | first) as $direct
      | if $direct == null then
          . + {metrics_comparable:false, capacity_status:"NO_DIRECT_BASELINE"}
        elif .requests_per_second.median <= 0 then
          . + {metrics_comparable:false, capacity_status:"INVALID_PROXY_RATE"}
        else
          ($direct.requests_per_second.median / .requests_per_second.median) as $ratio
          | . + {
              direct_capacity_ratio: (($ratio * 1000) | round / 1000),
              metrics_comparable: ($ratio >= 1.20),
              capacity_status: (if $ratio >= 1.20 then "PASS" else "BOTTLENECKED" end)
            }
        end
    elif .profile == "forward" and .target == "direct" then
      . + {metrics_comparable:true, capacity_status:"REFERENCE"}
    else
      . + {metrics_comparable:true, capacity_status:"NOT_APPLICABLE"}
    end
  )) as $annotated
| ([.[] | select(.profile == "forward" and (.target | baseline_target)) | [.bytes, .concurrency]] | unique) as $baseline_keys
| (($baseline_keys | sort) == ($expected_matrix | sort)) as $matrix_membership_exact
| ([$expected_matrix[] as $k |
    {bytes:$k[0], concurrency:$k[1], complete:
      (["direct","nginx","haproxy"] | all(. as $t |
        ([$annotated[] | select(.target == $t and .profile == "forward" and
          .bytes == $k[0] and .concurrency == $k[1] and
          .repetitions == $expected_repetitions)] | length) == 1
      ))}
  ]) as $matrix
| ($matrix_membership_exact and ($matrix | length) == $expected_baseline_groups and $expected_baseline_groups > 0 and ($matrix | all(.complete == true))) as $matrix_complete
| ([.[] | select(.status != "PASS" and .profile == "forward" and (.target | baseline_target))] | length == 0) as $baseline_failures_absent
| {
  schema: 4,
  interpretation: "Independent closed-loop connection-close repetitions; percentile medians are not pooled percentiles. Forward proxy results are comparable only when the complete expected body-size/concurrency matrix is present for direct/NGINX/HAProxy at the expected repetition count and direct-origin median throughput is at least 1.20x the proxy median for the same body size and concurrency.",
  expected_repetitions: $expected_repetitions,
  expected_baseline_groups: $expected_baseline_groups,
  expected_matrix: $expected_matrix,
  direct_capacity_margin_required: 1.20,
  baseline_matrix_membership_exact: $matrix_membership_exact,
  baseline_matrix_complete: $matrix_complete,
  baseline_matrix: $matrix,
  capacity_gate_passed: ($matrix_complete and $baseline_failures_absent and ([$annotated[] | select(.profile == "forward" and .target != "direct")] | length > 0) and ([$annotated[] | select(.profile == "forward" and .target != "direct")] | all(.metrics_comparable == true))),
  passed: $annotated,
  blocked_or_invalid: [.[] | select(.status != "PASS")]
}
