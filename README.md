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

`src/serve_reverse.ores` is an **experimental loopback-only** Java/Graal HTTP/1.1 entrypoint, not a production proxy. It loads `ores_proxy_conf_yaml` once, applies strict routes and declarative middleware, and bounds pooled actors to 100: 50 `HelloV1`, 25 `StreamV1`, and 25 unavailable-upstream handlers. A trusted supervisor registry admits only `hello-v1` (200 local response) and `stream-v1` (200 streamed response); an unregistered YAML actor image fails binding with 503. External HTTP and `pool://` upstreams return 501 because safe outbound transport is not implemented. No off-process forwarding is performed.

`tests/ingress_tcp_smoke.ores` covers earlier native TCP ingress paths. `tests/actor_ingress_tcp_smoke.ores` additionally checks the local actor response (200), streamed actor body (200), unavailable upstream (501), missing required header (403), and unregistered code image (503). These are native Oreslang integration candidates requiring a separately launched loopback listener and scoped network capabilities; no current-head native execution has been verified.

`src/proxy_wire.ores`, `src/header_policy.ores`, `tests/wire_contract.ores`, and `tests/header_policy_contract.ores` define further strict HTTP request-target and safe-header predicates with separate native Oreslang contract tests. They do **not** implement full HTTP parsing or copying and never grant outbound network authority. Read `docs/WIRE_AND_INGRESS.md` for the release blockers.

## Security audit (reverse, October 22, 2026)

The runtime is **NOT a forwarding proxy**. No destination capability may be created from `configured_domain`, `configured_connect`, or `upstream_origin` alone. `require_header` means *header presence*, NOT authentication or authorization. Never use it to protect a real upstream service without a separately verified authentication middleware.

The strict YAML subset now uses canonical [a-z0-9-] names for routes/middleware; forbids hop-by-hop, proxy credentials, and request-framing control header names as `require_header`; and rejects arbitrary IPv4 upstream spellings (v0 explicitly permits loopback `127.0.0.1`, `localhost`, or syntactically valid DNS names). Exact DNS/IP/TLS safety remains a separate network-layer release gate. Source policy still lacks a race-free configuration file descriptor and an input byte-size cap before `fs.read_text`.

The Actions workflow now has explicit native Oreslang compile/execute gates for the larger source/test tree, not just YAML. Self-hosted runner admission and actual executed test results are still required; a queued job is not a passing check. The alternative opt-in reverse ingress remains loopback-only and must not be counted as a tested production service.

## AttoLang migration inventory gate (November 2026)

The `.atto` migration requires exact source and standalone-test manifests, with an executable source-only checker (`python3 ci/check_atto_inventory.py`) and eleven local synthetic controls (`--self-test`). The manifest names `ci/oreslang-files.txt` and `ci/pure-contracts.txt` remain compatibility CI identifiers, but their contents contain only `.atto` paths. This gate catches extension drift and inventory omissions; **it does not run the AttoLang compiler, permit network egress, or establish a working HTTP data plane**. The native self-hosted runner hold remains in place pending independently approved exact-head admission and guest execution.
