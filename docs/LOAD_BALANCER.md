# Oreslang native load-balancer control-plane plan

Status (October 31, 2026): **pure Oreslang upstream selection and strict YAML admission only**. The reverse-proxy entrypoint still exits 78 and optional loopback ingress still emits 501. No DNS lookup, outbound connection, TLS session, real HTTP forwarding, health probe, observed connection accounting, retry, circuit breaker, or production load balancing is implemented.

## Design boundary

Use a **strict declarative YAML format**, not a second programming language. Upstream-pool admission is separate from request routing and listener configuration until atomic generation-pinned publication and safe outbound transport exist.

- Current config/example.yaml is the legacy ores.proxy/v1 route/listener demo, which requires a literal HTTP(S) upstream origin and is *not* automatically composed with pool YAML.
- Experimental config/load_balancer.example.yaml is **ores.lb/v1**; src/lb_yaml.ores parses it into a typed lb_policy.Pool. Current API is pure, with no config watcher, filesystem loader, or data-plane binding. src/main.ores does **not** load this file.
- No YAML anchors, aliases, tags, implicit coercion, quoted strings, multiline scalars, inline comments, or includes. Unknown/duplicate entries, invalid indentation, unsafe names or origins, missing required fields and resource-budget violations reject the whole document. No secrets should live in the file.
- The bounded initial YAML profile permits weights **1–8**, backend max_connections values **1/2/4/8/16/32/64/128/256/512/1024**, and up to **32** backends. The pure selection type permits a larger bounded integer domain, but the parser intentionally exposes less until checked numeric conversion is available across Oreslang backends.
- Origin is *syntax-only*. A connector MUST resolve both A/AAAA/CNAME, enforce a configured IP-range policy, reject private/loopback/metadata endpoints unless explicitly authorized for a trusted internal deployment, pin the resolved destination to the TCP connection, verify TLS SNI/peer, and prevent rebinding/reuse bypass. No outbound socket is authorized by this module.

## Implemented pure rules

- weighted_round_robin: deterministic weighted distribution across **currently eligible** targets (does not implement smooth weighted RR).
- least_connections: minimum active-connections-to-weight ratio among eligible backends; deterministic tie rotation among eligible servers. Requests must be atomically reserved by the owning actor after this advisory selection.
- source_hash: deterministic weighted bucket chosen by a trusted nonnegative hash; **not** rendezvous/consistent hashing. Adding/removing or ejection of a backend may remap client affinity. Do not use raw unauthenticated Forwarded/XFF headers.
- A server is ineligible if unhealthy, draining, ejected, or at its individual connection limit. All state observations are supplied by a caller, NOT discovered by this module.
- Backups receive traffic only if there are **zero usable primaries**. If no backend capacity remains, fail closed (no hidden queue, fallback to unchecked origin, or overcommit).
- Validate all backend metadata and the entire health snapshot before selecting, including backends not chosen.

## Generation and actor ownership contract (required integration)

1. Supervisor validates the full YAML, compiles route-to-pool references, stage-tests resolvers/TLS/probes and publishes one immutable generation with an atomic pointer swap.
2. One pool-owning actor provides health/connection counters and atomically reserves capacity **before** dispatch. The choose function is only a pure selection oracle: its observations may be stale. Do not share mutable counters across actor carriers.
3. Each request/stream keeps a receipt referencing pool generation, endpoint ID, reserved capacity, and finalization state. The receipt is settled exactly once on completion, timeout, client disconnect, upstream failure or actor cancellation.
4. Support bounded admission queues, deadlines, per-backend inflight caps, global/body/header budgets and backpressure. Do not retry non-idempotent/unreplayable requests; never retry after response headers commit.
5. Active probes, passive failure windows, circuit breaker ejection/recovery, slow start and backup failover must be generation-stable. Draining must keep existing streams but prevent new admissions; monitor terminal receipts before retiring a generation.
6. Preserve raw status, response/request headers, streaming bodies, trailers, HTTP/2/gRPC semantics, WebSockets and HTTP CONNECT only with verified framing, hop-by-hop handling and streaming adapters. Fail closed otherwise.

## Feature parity / delivery milestones

| Capability | Today | Next gate |
| --- | --- | --- |
| YAML control-plane with strict admission | **Pure ores.lb/v1 parser** | atomic route-to-pool binding; schema/version migration; descriptor-safe file load |
| Weighted round robin / least connections / source hash | **Pure deterministic oracle** | actor-owned admission/settlement; sharded counters; fairness/performance benchmarks |
| Weighted backends, connection caps, backup | **Pure selection rules** | enforce at socket dispatch with bounded queue |
| Active/passive health checks, slow start | **Not implemented** | probe actors, reason-coded failure accounting, hysteresis |
| Circuit breaker, outlier detection, retry budgets | **Not implemented** | bounded single-writer policy state; idempotent retry gate |
| TLS termination, TLS upstream, SNI, ALPN, mTLS | **Not implemented** | verified native transport and certificate reload |
| HTTP/1.1 streaming, HTTP/2, gRPC, WebSocket | **Not implemented** | correct byte-preserving, cancellation-safe transport |
| Host/path/header routing; rewrites, ACL, WAF, rate limits | **Demo route/middleware predicates only** | transport-level canonicalization, identity + quota enforcement |
| TCP/UDP L4 load balancing; PROXY protocol | **Not implemented** | typed listener profiles and trust-boundary tests |
| Sticky cookie/consistent hashing | **Not implemented** | stable hash ring and bounded, signed cookie policies |
| Observability / metrics / tracing / admin API | **Not implemented** | redacted cardinality-bounded telemetry, authenticated admin |
| Zero-downtime reload, graceful drain | **Generation reference models only** | supervisor-controlled atomic live publication |
| Java/LLVM/WASM/.NET/Forge parity | **Not demonstrated for this module** | separately executed native contracts, exact-tree reports |

HAProxy/NGINX equivalence is a **long-term target**, not a current capability. Compare latency, throughput, p95/p99, connection churn, CPU, memory, correctness and failure handling against pinned configurations of both projects before claiming parity.

## Verification gates

The tests/lb_policy_contract.ores fixture covers valid/invalid YAML, 3:1 scheduling, backup exclusion and failover, source hash, least connections, malformed status cardinality, drain/ejection/capacity and duplicate/unknown declarations. This file is **added, not executed** in this change. Source inventory does not imply compilation.

Native gate: run the exact review SHA with a pinned Oreslang compiler/JDK 25 on a privileged runner that **never** executes untrusted PR code. Source main is still unprotected; CI security PR #20 and independent approval must land before enabling native execution. Do not silently treat runner_id=0, queued jobs, or step-less workflow failures as guest test results. Avoid unauthorized cross-org private-source mirroring.
