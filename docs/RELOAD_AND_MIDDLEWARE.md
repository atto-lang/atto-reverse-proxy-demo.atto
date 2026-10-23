# Reload, actors and middleware: proposed native Oreslang contract

**Implementation status:** the current `src/proxy_yaml.ores`, `src/route_policy.ores` and `src/middleware_policy.ores` are pure control-plane candidates; `src/generation.ores` also models single-writer prepare/publish/abort epoch fencing without changing a live listener. Neither repo has a serving data plane, an atomic generation publisher, streaming forwarding or a running reload manager. `tests/middleware_generation_contract.ores` checks two separately parsed policy snapshots only.

## Runtime topology

- Start with a **20-carrier scheduler budget** and a **100-actor reusable handler pool**, independently bounded by `max_inflight: 1024`. These are initial benchmark hypotheses, not a thread-per-actor model or production auto-tuning. Keep accept, DNS, transport I/O and disk parsing off scheduler carriers.
- A supervisor/control actor is the only writer to the active *generation descriptor*. A descriptor owns config version, immutable route/pipeline tables, middleware implementation version, allowed origin policy and actor/image handles.
- Every admitted request receives a generation lease **before route selection**. The same generation must apply through pre-routing, route matching, middleware and response completion, including streams. Retain the lease until both transport and handler cleanup finish.
- A request actor or pooled worker cannot start the next request while a prior request retains an unfinished mutable response/borrow. Bounded mailboxes and pending-request queues must reject overload instead of bypassing backpressure.
- Per-request data and socket authority must remain scoped to the request; only validated immutable payloads and explicit read-only shared leases cross actor boundaries.

## Middleware placement

| Phase | Use | Ownership |
| --- | --- | --- |
| `pre_route` | request bounds, trusted headers, address-normalization assertions | listener/control |
| `route` | dispatch, fixed route policy, bounded rewrites | generation snapshot |
| `route_middleware` | named declarative `trace`, `deny` or `require_header` | generation snapshot |
| `in_actor` | business auth, request-scoped sessions, service-specific hooks | selected actor only |
| `response` and `on_complete` | header filtering, completion receipts, tracing | same generation lease |

Current YAML v1 accepts named `middleware` definitions and reverse `routes[].middleware` references as a comma-separated scalar. This **is not yet** a general configurable phase/scope schema. Actor-internal middleware is Oreslang code owned by the actor type, not dynamically injected into its fields.

The current `require_header` kind tests only **presence of a nonempty header**. It is **not** token verification, authorization, mTLS, identity validation or a safe public ingress gate. Do not attach any security claim to it. Future authentication middleware needs signed/constant-time validation and an explicit credential authority.

## Candidate reload transaction

1. **Parse** config read from `ores_proxy_conf_yaml` using scoped filesystem permission; cap bytes/complexity and reject duplicate/unknown YAML keys. Current path-based filesystem metadata is not race-free and must not accept hostile mutable paths.
2. **Validate** DNS/listener/route/middleware references, permissions and unknown middleware versions. For forward mode, check every target resolution, rebinding, CONNECT port and destination IP at the actual socket capability boundary; a domain suffix check alone never authorizes a dial.
3. **Prepare** immutable pipeline tables and stage the next actor pool and code-image handle, with no public admission.
4. **Warm/health-check** the candidate without granting it production traffic. The candidate must be able to drain and retire independently if any step fails.
5. **Publish exactly once** by swapping a single active-generation pointer only after every preceding receipt succeeds. Never publish a partially updated route or pipeline table. Any failure retains the previous generation and retires the candidate.
6. **Drain** the old generation: stop new assignments, permit in-flight responses to finish, enforce deadlines, cancel/retire leases and guards exactly once, and release the actor arenas only after all tracked tasks and transports have settled. Failed cleanup quarantines the old generation rather than reporting a successful retire.
7. **Collect** the old generation after the final lease has closed. Late completion/cancel/retry from an old incarnation cannot affect the new generation (use generation IDs and fencing tokens).

**Code versus configuration:** YAML-only policy, route or middleware-parameter changes may eventually replace only the immutable generation and actors. *New Oreslang source code* can use newly created actors only if an explicitly loaded and compatible code image is already available; hot-loading that image is a separate gate, not a guarantee from actor replacement. Some runtime ABI / listener / TLS changes need rolling process upgrades.

## Native test gates still required

- Actual Java/Graal JDK25 grammar/typecheck + execution of both `tests/*.ores` at the exact head, and explicit AOT/hybrid/LLVM backend outcomes.
- Concurrent request-held old-generation leases versus reload/cancel/error/shutdown, repeated reloads, failures at each stage, late completions and exact-once cleanup.
- Streaming response and CONNECT tunnel wire tests, framing/header sanitization, DNS rebinding, authentication, IP/port-deny enforcement, TLS chain/hostname validation and fd/accounting leak tests.
- Fair scheduling and throughput comparison for `carriers=20 / actors=100` against CPU-proportional carrier counts, 25/50/200 actors, queue capacities and max connections.

No successful config-only test may be reported as evidence of a listening or forwarding proxy.
