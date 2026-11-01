# Declarative Oreslang load-balancing contract (v1, pre-release)

This feature is **control-plane only**. It is not an HTTP reverse proxy, not a network load balancer, and does not make the current `serve_reverse.ores` forward requests. That entrypoint responds **501** for admitted pool routes until status/header-preserving streaming transport, bounded socket reservation, TLS and DNS authorization exist.

## YAML: strictly admitted subset

See [`config/lb-example.yaml`](../config/lb-example.yaml). A route's `upstream:` may be an existing direct HTTP(S) origin, or a `pool:pool-name` reference.

```yaml
upstreams:
  - name: api-pool
    algorithm: weighted_round_robin
    origins: https://node-a.example.test:9443,https://node-b.example.test:9443
    weights: 3,1
    max_connections: 128
```

Pool-bearing documents must use `version: ores.proxy/v2`. The parser continues to accept legacy `ores.proxy/v1` direct origins but *rejects* any pools in v1, and rejects v2 in forward mode. This prevents older controllers from treating new configuration syntax as the old contract.

For the first contract, only `round_robin`, `weighted_round_robin` and `least_conn` are admitted. Every pool needs 1–16 unique canonical HTTP(S) origins, one 1–16 integer weight per origin (strict nonzero decimal spelling), and `max_connections` in {16,32,64,128,256,512,1024}. There can be at most 64 pools. Repeated/unknown fields, duplicate names and unresolved pool references fail the **entire** config. Forward mode rejects `upstreams:`; forward CONNECT destination admission is a different security problem. No environment interpolation, imports, anchors, scripts, secrets or arbitrary expressions are accepted. Legacy direct-origin `ores.proxy/v1` configuration remains accepted.

## Selection and generation fencing

`lb_policy.choose(pool, epoch, healthy, active, ordinal)` is a pure Oreslang contract. Both metrics arrays align *exactly* with pool order and must be frozen from the same generation. A positive generation epoch is carried into `Choice`; the networking actor **must** revalidate the epoch and atomically reserve an individual backend slot *before* it connects. A pure choice is not an authorization or capacity reservation.

- `round_robin`: exactly the same bounded oracle with all weights required to be 1, rejecting nonunit weights.
- `weighted_round_robin`: ordinal is within the total **eligible** weight (0..sum-1); select over healthy, unsaturated backends only, with contiguous weighted slots. This is a deterministic **reference oracle**, not yet HAProxy-style smooth weighted RR under concurrency. Scheduler owner will manage a cyclic cursor, independent of transport requests.
- `least_conn`: ordinal is within the backend count (0..count-1) and rotates equal-load tie order. Weighted comparison uses `active_i / weight_i` via bounded integer cross-products; unhealthy or full backends are skipped.
- No healthy capacity: return `Err`; never silently revive a failed node or exceed a cap.
- Every backend's origin, positive weight and count is validated again even for a programmatically built `UpstreamPool`. Maximum 16 backends and 1024 active per backend bound integer scores.

## HAProxy/NGINX parity roadmap

| Capability | Current contract | Needed for production |
| --- | --- | --- |
| Weighted round-robin | Pure bounded selection and single-owner reservation oracle | Smooth concurrent scheduling and runtime-integrated atomic leases |
| Least connections | Pure normalized selection | Actor-owned, generation-safe counters and releases |
| Health & failover | Pure generation-fenced passive 3-failure/5000ms breaker, half-open probe state and external health bitmap | Actor-owned counters, timer/probes, atomic probe lease, configurable cooldown and slow-start |
| Backend pools & routes | Fail-closed v2 pooled YAML and legacy v1 direct origins | Atomic generation publication, live reload and graceful drain |
| Request routing | Canonical host/path matching | L7 streaming with status, headers, trailers, WebSocket and HTTP/2 |
| Retries | None | Replay safety, idempotence, retry budget and no retry after commit |
| Circuit breakers | None | Per-backend and per-route states, bounded queues |
| Sticky sessions | None | Signed cookies or authenticated consistent-hash keys, bounded stick tables |
| Transport and TLS | None | Pinned A/AAAA/CNAME resolution, SSRF protections, verified TLS and mTLS |
| Observability | Pure contract tests | Per-upstream metrics, traces, health/admin API with auth and redaction |
| L4 TCP/UDP | None | Bounded duplex streams, cancellation, half-close, UDP session budgets |
| Zero-downtime reload | Pure prepare/publish oracle | Listener handoff and old-generation drain |
| Static content/cache | None | Separate explicit scope and cache correctness/security policies |

This is an architecture target inspired by official HAProxy and NGINX documentation, **not a claim of performance or feature parity**.

The `lb_ledger` module is a **single-owner immutable reservation oracle**, not a concurrent runtime allocator. It combines a healthy/saturation filter with a unique generation/nonce/slot ticket on each accepted request, rejects stale sequence claims and duplicate or recycled releases, and begins with every backend unprobed/unhealthy. The actor supervisor must replace the published ledger atomically and must not allow clients to inject health state. The pure model globally caps tracked reservations at 1024 even when the sum of backend capacities would be higher; this is a conservative test profile, not HAProxy/NGINX scaling parity.

The `lb_health` module is a **single-owner immutable state oracle** (closed → open → half-open → closed/open) with sequence/epoch fencing; it does not schedule health checks, acquire a probe lease, publish a shared health table or guarantee concurrency-safe execution. The production scheduler must combine it with atomic actor-owned reservations and fully verified outbound transport.

## Release/CI gates

Run `tests/lb_policy_contract.ores` on an authorized compiler/runner against an exact immutable SHA; capture actual job steps. No automatic PR-head execution on privileged self-hosted runners. Test malformed YAML/fuzz limits, all-healthy/unhealthy, capacity races, reload while inflight, DNS rebinding, CONNECT and HTTP request smuggling, TLS validation, retries after partial write and cancellation before enabling production traffic. Until then keep all data-plane forwarding disabled.
