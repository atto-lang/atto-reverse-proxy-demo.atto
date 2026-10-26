def median: sort | if length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end;
def stats: {median: median, min: min, max: max};
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
| {
  schema: 2,
  interpretation: "Independent closed-loop connection-close repetitions; percentile medians are not pooled percentiles. Forward proxy results are comparable only when direct-origin median throughput is at least 1.20x the proxy median for the same body size and concurrency.",
  direct_capacity_margin_required: 1.20,
  capacity_gate_passed: (([$annotated[] | select(.profile == "forward" and .target != "direct")] | length > 0) and ([$annotated[] | select(.profile == "forward" and .target != "direct")] | all(.metrics_comparable == true)) and ([.[] | select(.status != "PASS" and (.target == "direct" or .target == "nginx" or .target == "haproxy") and .profile == "forward")] | length == 0)),
  passed: $annotated,
  blocked_or_invalid: [.[] | select(.status != "PASS")]
}
