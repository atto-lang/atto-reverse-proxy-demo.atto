#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v oreslang >/dev/null
[[ -x /usr/bin/time ]] || { echo '/usr/bin/time is required' >&2; exit 2; }
[[ "${ORESLANG_RUNTIME_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || { echo 'ORESLANG_RUNTIME_SHA must be exactly 40 lowercase hex characters' >&2; exit 2; }
out=$(mktemp -d "${TMPDIR:-/tmp}/ores-policy-bench.XXXXXXXX")
printf 'Results: %s\n' "$out"
printf 'runtime_source_sha=%s\n' "$ORESLANG_RUNTIME_SHA" > "$out/provenance.txt"
sha256sum "$(command -v oreslang)" "$repo/tests/perf_policy_contract.ores" >> "$out/provenance.txt"
oreslang --check "$repo/tests/perf_policy_contract.ores"
for repeat in 1 2 3 4 5; do
  # Whole-process elapsed/CPU/peak RSS. Includes startup, JIT and shutdown.
  /usr/bin/time -v -o "$out/repeat-$repeat.time" oreslang "$repo/tests/perf_policy_contract.ores" > "$out/repeat-$repeat.log" 2>&1
  grep -Fx 'PASS native policy workload: 10000 iterations, 50000 checked operations' "$out/repeat-$repeat.log" >/dev/null
done
