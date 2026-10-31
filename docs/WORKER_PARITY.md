# Proxy platform compatibility and local actor services (2026-10-23)

**Status:** partial *source-level control-plane foundations*, NOT feature parity or a
production substitute for NGINX, HAProxy, Cloudflare Workers or workerd.
This work builds on the strict YAML-subset parser. No Python or Rust application
source is introduced. Read the repository README's fail-closed claims.

## Workerd / Cloudflare Workers pattern

Workerd uses capability bindings between worker services and external resources.
Its nanoservices are cheap and isolated by the runtime. We adapt that idea:
the trusted Oreslang supervisor parses the YAML `services` section, resolves
each `service://name` to a **pre-registered actor image**, and pins the resulting
symbolic plan to one configuration generation. The actor can be single-flight
per actor with multiplexed outstanding request lifetimes; I/O never holds a
carrier. Permission and resource budgets are granted by the *supervisor*, not
from a YAML string.

`src/proxy_yaml.ores` now admits `services:` entries with `name`,
`kind: actor` and `target`. All three identifiers are ASCII lower-case,
digits/hyphens only; every referenced service must exist. Duplicate names,
missing fields, unsupported kinds, whitespace, path escapes and arbitrary URL
bindings fail. `src/service_bindings.ores` now also requires a
supervisor-owned trusted code-image registry before a YAML target can bind.
YAML cannot register a code image or widen its capability manifest. The result
remains an immutable, generation-scoped **symbolic descriptor**, not a runtime
ActorRef or network grant.

The opt-in `src/serve_reverse.ores` has exactly TWO trusted local code
images: `hello-v1` -> `HelloV1` and `stream-v1` -> `StreamV1`.
`config/worker-example.yaml` declares symbolic service references for them.
The supervisor registry, not YAML, authorizes these images without granting
network capability. Local hello and streaming routes return 200, an unknown
code image fails binding with 503, and external HTTP/pool upstreams return
501. No untrusted actor sandbox or upstream forwarding is claimed.
`tests/actor_ingress_tcp_smoke.ores` is a separate native Oreslang TCP
integration candidate (200 local/streaming actor, 501 upstream, 403 denied,
503 unregistered image). It has NOT executed with a running listener.

## HAProxy and NGINX policy slices

`src/load_balancer.ores` implements a **pure deterministic oracle** for
block-weighted round-robin and weight-adjusted least-active backend selection.
It excludes drained/unhealthy backends, bounds weights and queue metadata,
and returns explicit failure when no eligible destination exists.
It is deliberately not yet an endpoint connection pool or a health checker.
Weighted block cycling is NOT smooth weighted round-robin. No sticky hashing.

`src/traffic_controls.ores` specifies actor-owned fixed-window counters
and an elementary failure-threshold circuit-breaker with cooldown. These are
reference calculations, **not** shared HAProxy stick tables, production-wide
rate limits or live latency sensors. Half-open admits MUST require an
exclusive supervisor-issued probe lease before network integration.
Generation changes intentionally reset counters, and monotonic time is
provided by a trusted caller, never derived from a request header.

`src/network_admission.ores` composes the current request-slot lease, immutable configuration epoch, rate decision, breaker state, selected reverse origin, and a trusted resolver/network-policy classification before any future outbound transport. Its permit objects are proof descriptors only; the transport must not treat them as dial authority.

## Future parity matrix

| Feature | Oreslang status / required gate |
|---|---|
| NGINX named routes and priorities | Pure longest-prefix routing implemented; host/raw framing normalization still requires wire proof |
| HAProxy weighted/least-active backends | Native pure selection policy; pre-dial gate can bind an admitted origin to a pinned endpoint, but no socket/load-balanced traffic exists |
| HAProxy stick tables and rate controls | Fixed-window actor-local reference only; key cardinality, bounded store/eviction and distributed sync missing |
| Health checks and passive circuit breakers | Pure health/drain flags and breaker oracle; no probes or single-winner half-open leases |
| Workerd service bindings | YAML + generation-pinned symbolic local actor service binding; no general service networking API |
| Cloudflare Workers programmable request handling | One opt-in statically pre-approved native Oreslang actor HTTP handler on loopback; backend-specific compiler and TCP proof open |
| Durable Objects | Design only; actor `state {}` and `critical handle_state` require persistence/migration/delivery proof |
| HTTP streaming, WebSockets, gRPC, HTTP/2, HTTP/3 | Missing or unverified guest portable transport capabilities |
| Caching, ETag, compression, TLS/mTLS, WAF | Not implemented; unsafe to claim coverage |
| Workerd compatibility dates and API versioning | Not implemented; future per-code-image ABI/capability manifest and compatibility-date gate |
| Deploy/reload without downtime | Pure generation coordinator only; no atomic live route swap/request pins/drain proof |
| Forward CONNECT, auth, SSRF-proof egress | No tunnel or authenticated egress; remains fail closed |
| LLVM/Graal cross-backend | Unverified; requires exact-head actual execution, not parser substitutes |

## Non-negotiable production acceptance

1. Cross-compile/run YAML, service-binding, LB, traffic and actor tests on
   exact head with reproducible compiler digest (Graal JDK25/JIT/AOT/hybrid,
   LLVM AOT + sanitizers).
2. Implement owned nonblocking byte-stream `std/net` with backpressure,
   cancellation/FD lifetime proofs and portable `std/http` status/headers/
   streaming. Correct framing and hop-by-hop stripping before forwarding.
3. Bind declared service identifiers only to trusted, versioned code images;
   reject code ABI and capability changes until staged, checked and ready.
4. Add isolated actor state consistency (single `state {}`, critical loans),
   readiness/barriers and one generation pin per in-flight request.
5. Endpoint health/active counters, half-open probe fencing, real rate-key
   store quotas, metrics/traces and adaptive concurrency with executable tests.
6. Forward-specific authenticated CONNECT + DNS A/AAAA/CNAME IP pinning,
   private/reserved IP denial, TLS hostname checks, socket half-close.
7. Attack simulations: CL/TE smuggling, malformed Host, duplicate headers,
   oversized headers/bodies, h2 downgrade, slowloris, DNS rebinding, 1k/10k
   connections, cancellation vs graceful drain.
8. Benchmark on identical hardware vs NGINX, HAProxy and workerd.
   Compare tail latency, throughput, CPU, L1/L2 cache misses, memory,
   cancellation/shutdown and reload error rates before claiming parity.

Sources: https://github.com/cloudflare/workerd ,
https://github.com/cloudflare/workerd/blob/main/src/workerd/server/workerd.capnp ,
https://nginx.org/en/docs/http/load_balancing.html ,
https://www.haproxy.com/documentation/

## Declarative weighted upstream pools (second vertical slice)

`config/backend-example.yaml` demonstrates end-user YAML `backends:` with
`name`, `pool`, `origin` and `weight`. For the provisional v1 format,
weights are restricted to **1, 2, 3, 4, 5, or 10**; max 128 backends.
Duplicate names or duplicate origin within a pool fail admission. An Oreslang
reverse route can reference `pool://api`; dangling pools are rejected.

`src/backend_pools.ores` compiles that YAML to the existing
`load_balancer.choose` policy. Supported planned choices are
`weighted-round-robin` (deterministic block-weighted rotation) and
`least-active` (which defaults to choosing the first configured node in
this **static** plan, because no live in-flight counters exist yet).
This returns an untrusted **decision descriptor**, not an authenticated
network connection. The current experimental reverse HTTP ingress returns
501 for these pool routes, not a counterfeit upstream response. The forward
proxy accepts backend declarations but does not route CONNECT through them.

A production implementation must additionally implement all of:
(1) resolved-address and certificate identity pinning; (2) egress-scoped
capability minting by the trusted supervisor; (3) actor-owned atomic backend
credit/reservation and exact-once release; (4) bounded connection pools and
HTTP/1.1+2 framing; (5) health/probe and failover policy; (6) retries only
for idempotent requests before headers commit; (7) streamed bodies with
backpressure and request-generation pins. No such capability is inferred
from a syntactically valid YAML origin.
