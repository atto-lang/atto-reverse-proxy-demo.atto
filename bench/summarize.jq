def median: sort | if length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end;
def stats: {median: median, min: min, max: max};
{
  schema: 1,
  interpretation: "Independent closed-loop connection-close repetitions; percentile medians are not pooled percentiles. No cross-profile ratios.",
  passed: ([.[] | select(.status == "PASS")]
    | group_by([.target, .profile, .bytes, .concurrency])
    | map({target: .[0].target, profile: .[0].profile, bytes: .[0].bytes,
           concurrency: .[0].concurrency, repetitions: length,
           requests_per_second: (map(.requests_per_second) | stats),
           p50_us: (map(.p50_us) | stats), p95_us: (map(.p95_us) | stats),
           p99_us: (map(.p99_us) | stats)})),
  blocked_or_invalid: [.[] | select(.status != "PASS")]
}
