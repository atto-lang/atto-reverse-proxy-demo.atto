# Oreslang reverse proxy (native Oreslang)

**Pre-release configuration/control-plane candidate, not an operational proxy.**

This repository now contains native Oreslang source for strict YAML-subset admission, deterministic route and middleware policy checking, CLI status handling, and self-contained Oreslang contract tests. The network data plane, actor-generation swaps and cross-backend transport integration remain gated. Valid YAML exits 78 instead of pretending an HTTP proxy has started.

Entry: `src/main.ores`. Config: `config/example.yaml`. Runtime architecture and limitations: `docs/ARCHITECTURE.md`. The source tree contains no Python, Rust, JavaScript or shell application scripts.

Config environment variable: **`ores_proxy_conf_yaml`** (lowercase exactly). CLI flag mapping: **`.cli-flags.toml`** for `flags-2-env`.


Further native-Oreslang regression coverage: `tests/middleware_generation_contract.ores` compares independent old/new immutable policy snapshots. See `docs/RELOAD_AND_MIDDLEWARE.md` for proposed actor staging, middleware placement, generation pinning, and drain semantics. **This is a pure test contract, not an implemented hot-reloader.**

Exact-head compiler/contract execution is not yet available; no passing PR CI checks have been observed. Do not advertise production reverse proxying until exact-head compiler, contract, and transport tests pass.

A native, **pure control-plane** coordinator in `src/generation.ores` exercises prepare/publish/abort fencing and snapshot epochs (see `tests/generation_contract.ores`). This does not publish a listener/actor generation or serve requests.

## Native verification gate

The exact-head native compiler/contract workflow is [`.github/workflows/native-contracts.yml`](.github/workflows/native-contracts.yml); runner prerequisites, executed commands and non-production release gates are in [`docs/NATIVE_VALIDATION.md`](docs/NATIVE_VALIDATION.md). A queued or absent workflow is **not** a passed compiler test. Network serving remains disabled.

## Opt-in native Oreslang loopback ingress

`src/serve_reverse.ores` is a separate **experimental** Java/Graal HTTP/1.1 entrypoint. It reads the YAML path from `ores_proxy_conf_yaml` exactly once, accepts only loopback port 8080, matches routes, and applies declarative `deny` / `require_header` middleware. The bounded 100-actor demonstration budget is split between a statically trusted local `HelloV1` actor pool and the unavailable-upstream pool. Only the exact trusted registry entry `hello-v1` may dispatch locally and return 200; arbitrary actor targets and all external HTTP upstreams remain unavailable/501 because there is no safe status/header/binary-stream-preserving upstream client. It does not forward any request off-process. Pool references remain declarative and return 501; no upstream socket is opened.

`tests/ingress_tcp_smoke.ores` is a **native Oreslang** TCP test client for the older ingress-only paths. `tests/actor_ingress_tcp_smoke.ores` separately covers the local actor-service candidate (200 local actor, 501 external upstream, 403 denied) while the experimental ingress is listening. Neither TCP client is executed by CI today. The application and test client both require explicitly scoped Oreslang network capabilities. These tests have not yet been executed on the current PR head; treat the 400 path test as an open semantic gate until real wire evidence exists.

`src/proxy_wire.ores`, `src/header_policy.ores`, `tests/wire_contract.ores`, and `tests/header_policy_contract.ores` define further strict HTTP request-target and safe-header predicates with separate native Oreslang contract tests. They do **not** implement full HTTP parsing or copying and never grant outbound network authority. Read `docs/WIRE_AND_INGRESS.md` for the release blockers.

## Security audit (reverse, October 22, 2026)

The runtime is **NOT a forwarding proxy**. No destination capability may be created from `configured_domain`, `configured_connect`, or `upstream_origin` alone. `require_header` means *header presence*, NOT authentication or authorization. Never use it to protect a real upstream service without a separately verified authentication middleware.

The strict YAML subset now uses canonical [a-z0-9-] names for routes/middleware; forbids hop-by-hop, proxy credentials, and request-framing control header names as `require_header`; and rejects arbitrary IPv4 upstream spellings (v0 explicitly permits loopback `127.0.0.1`, `localhost`, or syntactically valid DNS names). Exact DNS/IP/TLS safety remains a separate network-layer release gate. Source policy still lacks a race-free configuration file descriptor and an input byte-size cap before `fs.read_text`.

The Actions workflow now has explicit native Oreslang compile/execute gates for the larger source/test tree, not just YAML. Self-hosted runner admission and actual executed test results are still required; a queued job is not a passing check. The alternative opt-in reverse ingress remains loopback-only and must not be counted as a tested production service.
