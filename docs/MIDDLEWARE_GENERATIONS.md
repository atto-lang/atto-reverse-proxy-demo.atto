# Middleware manifests and generation boundaries

This is an **Oreslang-only control-plane contract**, not a working proxy listener. `src/middleware_manifest.ores` resolves named middleware against a **particular** `generation.Snapshot` and copies each immutable definition into a private ordered manifest. No global "latest middleware" pointer is consulted during evaluation.

- Reverse: `bind_reverse_route(snapshot, canonical_host, canonical_path)` selects the first matching route and freezes that route's middleware chain. The HTTP adapter must normalize both inputs and check Host/authority framing **before** calling this helper.
- Forward: `bind(snapshot, "egress", chain)` binds an egress or actor-specific chain explicitly. This **does not** mean the forward proxy can serve HTTP or CONNECT; network credentials, DNS pinning and allowlist checks remain unavailable.
- Actor-local middleware is allowed, but a changed code body needs a compatible newly spawned actor (or a new runtime image). This function copies *declarative policy definitions*, not executable actor code.
- A staged YAML parse is not a live deployment. Supervisor must stage actor instances, validate readiness, atomically publish an admission pointer, then pin each admitted request's generation and preserve the old immutable manifest until its request/stream/tunnel is complete.
- Add a bounded in-flight lease ledger, idempotent completion receipts, cancellation-safe drain, readiness rollback and terminal cleanup before calling `publish` in a serving proxy. Never combine old route state with new middleware state.
- `permitted(header,value)` is a **single-header policy proof helper**, not authorization: an actual adapter must normalize headers, reject duplicate/ambiguous credentials and enforce every gate before dispatch.
- Carrier/actor counts (20/100) remain **configuration admissions only**. They are not thread/actor runtime allocations. Benchmark against CPU/cgroup budgets, measured queue depths and p99 latency before choosing defaults.

Run the native Oreslang contract `tests/middleware_manifest_contract.ores` with the exact installed compiler for each backend. No shell, Python, or Rust script is needed for application startup or contract checks. The transport and exact-head cross-backend test receipts are still release blockers.
