# Data-oriented, cache-aware proxy plan

**Status:** the committed `src/data_layout.ores` is an Oreslang *semantic reference*, not a benchmarked, preallocated native transport slab. Neither proxy currently serves traffic. It does not allocate threads, actor workers, sockets, ECS storage, direct buffers, or perform hot reload. Do not infer real speed from these tests.

## Workload-specific layout (avoid applying every layout everywhere)

| Target | Candidate physical layout | Reason / guardrail |
| --- | --- | --- |
| Listener admissions, deadlines, conn/route indexes, in-flight flags and counters | **SoA**, one primitive dense column per field, owner-local contiguous arena | Keep queue-scan and timeout sweeps field-local; no object/box pointer chase |
| Active connection and HTTP request metadata | **AoSoA** (32/64-lane tiles; 16 as control), grouped by actor/shard | Batch hot-field scans while preserving per-lane gather of several fields; align tiles, measure actual cache misses |
| Immutable parsed YAML and route/middleware definitions | **AoS** (cold-control structs), then compile into compact numerical tables | Validation and debugging favor grouped records; never parse strings or allocate objects during hot dispatch |
| Route-indexed connection components | **ECS**: generational entity IDs + dense base components and sparse optional TLS, CONNECT, streaming, retry components | No per-connection payload for features not used; stale-handle/ABA rejection on reuse; sparse references need epoch checks |
| Sharded upstream-pool control or large mixed records | **SoAoS**: separate arrays *of* structured shard/pool descriptors, optionally containing SoA pages; benchmark this alternative | Group rare per-pool metadata while scanning one field across many shards; do not invent it as a mandatory universal layout |
| TLS, tracing spans, errors and infrequently accessed header maps | **AoS / sparse ECS components** | Keep expensive cold state away from hot transport cache lines |
| Payload bytes (including large read-only blobs) | Immutable ref-counted/shared buffers + zero-copy scatter/gather capabilities | Share with `rt share` only after freezing; owner-scoped lifetime, bounded pinning and explicit completion; no mutable aliasing |

AoSoA and SoAoS have different nesting orders. A complete implementation must encode them as distinct data layouts and compare against a simple SoA baseline. Favor the simplest winning layout for each workload; do not add indirection just to tick every acronym.

## Allocation, ownership, and actor scheduling

- One supervisor manages validated YAML, actor staging and generation publication. Adopt *single writer per shard* and shard by listener/connection ID; no global per-request mutex. Route/actor configuration is immutable and can be shared read-only across actors; live buffers and slot registries remain arena-owned and never shared mutably across actor boundaries.
- On GraalVM use the project's shared/isolated/untrusted global execution domains, lazy worker creation and actor-local off-heap arenas. No OS pool per actor and no per-request JVM facade or boxed field in the target hot path. For LLVM use native actor-local arenas and fixed-width primitive columns. Backends must agree on semantics and ownership, not identical implementation details.
- Initial YAML budget `carriers: 20`, `actors: 100`, `max_inflight: 1024` is **parsed only**, NOT an actual allocation. Benchmark 20 against CPU/cgroup-proportional carrier counts, a range of actor shards, and a bounded 1,024-in-flight admission cap. Prefer task and connection reuse, not an actor per packet or request.
- Connection/request handles must include a slot + incarnation, and separately pin the immutable policy generation; advance incarnation before slot reuse, reject wraparound, make release idempotent, and prevent stale timers/completions/middleware callbacks from operating on a reused slot.
- Plan for fixed-capacity slabs/rings with explicit release, tombstones, free lists, no unbounded append, proper memory alignment, worker-pool affinity and false-sharing avoidance. The reference `SoaRequests` is **append only** and currently creates wrapper objects, so it must not be attached to the hot path or benchmarked as the final native layout.
- Middleware chains should compile to integer stage IDs before publish. Route lookup should map to numeric route/upstream IDs; no string-split, linear YAML scan or allocation per request. In-flight requests keep their generation. Prefer precomputed filter sets or dense tables and a cold-path slow lookup only for config management.
- Timeouts/ratelimits/metrics: use bucketed time wheels or batch scans over SoA columns, per-shard counters and deferred aggregated publication. Backpressure must cap inflight requests, queued bytes, sockets, DNS jobs, tunneled connections and slow readers, not just actor count.

## Wire correctness before micro-optimization

No memory-layout gain justifies unsafe proxy behavior. Require HTTP request framing/header normalization, TCP half-close and streaming cancellation, TLS hostname verification, credential redaction, DNS/IP pinning (especially forward CONNECT), hop-by-hop header sanitation, strict keep-alive and bounded drain. Normalize transport inputs **before** data-oriented numeric tables are accessed.

## Measurement matrix (native Oreslang bench scripts, not Python/Rust)

The committed `tests/data_layout_contract.ores` checks column aggregation, bounds, AoSoA 32/64 tile mapping, stale-epoch rejection and ECS incarnation guard. Actual `bench/layout_bench.ores` remains a prerequisite for publishing performance results, since a reliable monotonic timer, request loop and optimized native slab are not established in these repos.

- Compare **AoS vs SoA vs AoSoA(16/32/64) vs SoAoS** under small, typical and large payload distributions. Record throughput (req/s, bytes/s), p50/p95/p99/p99.9 latency, allocations/req, RSS, CPU utilization, cache/branch misses and GC pauses where applicable.
- Sweep 1, 2, 4, 8, 16, 20 and hardware-proportional carriers; actor shards 16, 32, 64, 100, 128; connection fan-out; queue depths and rate limits. Evaluate 1-client, 1k, 10k keep-alive plus long-lived HTTP/2 and CONNECT where supported.
- Include adversarial slowloris/slow reader, retries, cancellation while forwarding, DNS rebinding, stale ECS IDs after slot recycle, actor drain during generation swaps, and per-shard starvation. Assess p99/p99.9 under mixed long/short streams and hot middleware reloads.
- **Promotion criterion:** same exact-head Java/Graal JDK25/AOT and LLVM semantic/transport tests pass first; then choose layout on measured end-to-end p99 *and* throughput, not synthetic microbenchmark wins.

## User-facing configuration remains unchanged

Configuration still comes solely from lowercase `ores_proxy_conf_yaml`, with `flags-2-env` mapping CLI `--config-yaml`. Hot-path layouts are currently engine internals; avoid exposing unstable array/tile knobs as YAML user configuration before validated cross-backend support.
