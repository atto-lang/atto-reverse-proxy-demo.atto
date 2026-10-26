# Validation evidence

## Prior baseline evidence

- Rust 1.90.0 compiled the dependency-free driver; all **7 original tests passed**.
- Rust formatting checks, Bash syntax checks, jq summary aggregation/exclusion,
  and workflow YAML syntax checks passed.
- The shared harness was exercised against real NGINX **1.24.0** and HAProxy
  **2.8.16**, plus the Rust loopback origin. Each smoke run completed **16
  cases / 2,048 measured requests** with zero baseline failures.
- Those runs used NGINX single-process sandbox mode and unpinned CPU placement.
  They establish harness/wire correctness only and are not production rankings.

## Current-head hardening that must be re-executed

The benchmark now additionally:

- requires canonical 40-lowercase-hex source/runtime provenance;
- generates a fresh 128-bit-equivalent lowercase-hex origin nonce per run and
  requires that nonce in real forwarding responses;
- rejects the old static origin marker as stale forwarding proof;
- labels forward-proxy metrics non-comparable unless the matching direct-origin
  median has at least **1.20x** throughput headroom;
- fails full mode when that direct-capacity gate does not pass;
- requires explicit, distinct proxy/load/origin CPU affinity in full mode and
  records CPU quota, governor/boost state and topology.

The current Rust suite therefore includes an additional stale-nonce regression,
and the summary regression now covers both passing and `BOTTLENECKED` capacity
outcomes. Do not carry the earlier 7-test/smoke evidence forward as proof of
these new gates until the exact current Git head executes successfully.

**Oreslang native workload execution remains NOT_EXECUTED** until a trusted
runner actually starts the native jobs. The 50,000-operation checksum workload
is present, but compiler acceptance, Java/Graal/LLVM timings, real upstream
forwarding and authenticated CONNECT remain unproven.

Run `bash bench/run.sh` for fresh raw per-case JSON, summaries, provenance,
configs and logs. Published comparisons require a controlled full run on the
same hardware, pinned product/runtime versions, direct-capacity headroom and
matching capability gates.
