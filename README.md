# Oreslang reverse proxy (native Oreslang)

**Pre-release configuration/control-plane candidate, not an operational proxy.**

This repository now contains native Oreslang source for strict YAML-subset admission, deterministic route and middleware policy checking, CLI status handling, and self-contained Oreslang contract tests. The network data plane, actor-generation swaps and cross-backend transport integration remain gated. Valid YAML exits 78 instead of pretending an HTTP proxy has started.

Entry: `src/main.ores`. Config: `config/example.yaml`. Runtime architecture and limitations: `docs/ARCHITECTURE.md`. The source tree contains no Python, Rust, JavaScript or shell application scripts.

Config environment variable: **`ores_proxy_conf_yaml`** (lowercase exactly). CLI flag mapping: **`.cli-flags.toml`** for `flags-2-env`.


Further native-Oreslang regression coverage: `tests/middleware_generation_contract.ores` compares independent old/new immutable policy snapshots. See `docs/RELOAD_AND_MIDDLEWARE.md` for proposed actor staging, middleware placement, generation pinning, and drain semantics. **This is a pure test contract, not an implemented hot-reloader.**

Exact-head compiler/contract execution is not yet available; no passing PR CI checks have been observed. Do not advertise production reverse proxying until exact-head compiler, contract, and transport tests pass.

A native, **pure control-plane** coordinator in `src/generation.ores` exercises prepare/publish/abort fencing and snapshot epochs (see `tests/generation_contract.ores`). This does not publish a listener/actor generation or serve requests.

## Declarative load balancing (pure contract, not network forwarding)

The experimental v2 YAML subset now optionally supports bounded, named `upstreams:` backend pools and `upstream: pool:NAME` route targets. The source-only Oreslang contract supplies weighted round-robin, weighted least-connections, fail-closed health and capacity selection, and a generation-fenced pure passive circuit-breaker oracle. No real health probes, atomic backend reservations or outbound forwarding are implemented. See [the example YAML](config/lb-example.yaml), [feature/limitations](docs/LOAD_BALANCING.md), and the new `tests/lb_policy_contract.ores` / `tests/lb_health_contract.ores`. No native pass is claimed.

## Native verification gate

The legacy native workflow [`.github/workflows/native-contracts.yml`](.github/workflows/native-contracts.yml) is intentionally disabled on this audit-derived branch to prevent untrusted PR-head execution on privileged self-hosted runners; runner prerequisites, executed commands and non-production release gates are in [`docs/NATIVE_VALIDATION.md`](docs/NATIVE_VALIDATION.md). A queued or absent workflow is **not** a passed compiler test. Network serving remains disabled.

## Opt-in native Oreslang loopback ingress

`src/serve_reverse.ores` is a separate **experimental** Java/Graal HTTP/1.1 entrypoint. It reads the YAML path from `ores_proxy_conf_yaml` exactly once, accepts only loopback port 8080, matches routes, applies declarative `deny` / `require_header` middleware, and uses 100 pooled isolated request actors. Matched requests **always return HTTP 501**, because the runtime does not yet provide a safe status/header/binary-stream-preserving upstream HTTP client. It does not forward any request. Admission overload can reject requests separately.

`tests/ingress_tcp_smoke.ores` is a **native Oreslang** TCP test client, intended to run as a separate process while the experimental ingress is listening. It checks 501/403/404/400, including a path-normalization trap. The application and test client both require explicitly scoped Oreslang network capabilities. These tests have not yet been executed on the current PR head; treat the 400 path test as an open semantic gate until real wire evidence exists.

`src/proxy_wire.ores`, `src/header_policy.ores`, `tests/wire_contract.ores`, and `tests/header_policy_contract.ores` define further strict HTTP request-target and safe-header predicates with separate native Oreslang contract tests. They do **not** implement full HTTP parsing or copying and never grant outbound network authority. Read `docs/WIRE_AND_INGRESS.md` for the release blockers.
