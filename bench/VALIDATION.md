# Local validation evidence

- Rust 1.90.0 compiled the dependency-free driver; all **7 tests passed**.
  Tests cover exact bodies/origin markers, response status, duplicate lengths,
  unsupported encodings, truncation/extra bytes, loopback/input bounds,
  nearest-rank percentiles, a live TCP fixture and preflight rejection of 501
  before forwarding measurement.
- Rust formatting checks, Bash syntax checks, jq summary aggregation/exclusion,
  and both workflow YAML syntax checks passed.
- The shared harness was exercised from both repository trees against real
  NGINX **1.24.0** and HAProxy **2.8.16**, plus the Rust loopback origin.
  Each smoke run completed **16 cases / 2,048 measured requests**, with **zero
  failed or blocked baseline cases**. Warm-up/readiness requests are additional.
- NGINX single-process sandbox mode was necessary because the local UID
  namespace cannot switch worker users. This mode is recorded, smoke-only,
  and explicitly refused for full runs. Local CPU placement was unpinned and
  process telemetry was unavailable. These smoke runs establish harness/wire
  correctness; no production throughput rankings are asserted.
- **Oreslang native workload execution: NOT_EXECUTED.** No local oreslang
  compiler or listener exists. The 50,000-operation native checksum workload
  and native CI steps are supplied, but compiler acceptance, Java/Graal/LLVM
  timings, upstream forwarding and authenticated CONNECT are unproven.

Run `bash bench/run.sh` for fresh raw per-case JSON, summaries, provenance,
configs and logs. Published comparisons require a controlled full run on the
same hardware, pinned product/runtime versions and matching capability gates.
