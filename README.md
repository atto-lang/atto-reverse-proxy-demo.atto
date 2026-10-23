# Oreslang reverse proxy (native Oreslang)

**Pre-release configuration/control-plane candidate, not an operational proxy.**

This repository now contains native Oreslang source for strict YAML-subset admission, deterministic route and middleware policy checking, CLI status handling, and self-contained Oreslang contract tests. The network data plane, actor-generation swaps and cross-backend transport integration remain gated. Valid YAML exits 78 instead of pretending an HTTP proxy has started.

Entry: `src/main.ores`. Config: `config/example.yaml`. Runtime architecture and limitations: `docs/ARCHITECTURE.md`. The source tree contains no Python, Rust, JavaScript or shell application scripts.

Config environment variable: **`ores_proxy_conf_yaml`** (lowercase exactly). CLI flag mapping: **`.cli-flags.toml`** for `flags-2-env`.


Further native-Oreslang regression coverage: `tests/middleware_generation_contract.ores` compares independent old/new immutable policy snapshots. See `docs/RELOAD_AND_MIDDLEWARE.md` for proposed actor staging, middleware placement, generation pinning, and drain semantics. **This is a pure test contract, not an implemented hot-reloader.**

Exact-head compiler/contract execution is not yet available; no passing PR CI checks have been observed. Keep the pull request draft and do not advertise active HTTP forwarding.

A native, **pure control-plane** coordinator in `src/generation.ores` exercises prepare/publish/abort fencing and snapshot epochs (see `tests/generation_contract.ores`). This does not publish a listener/actor generation or serve requests.

## Native verification gate

The exact-head native compiler/contract workflow is [`.github/workflows/native-contracts.yml`](.github/workflows/native-contracts.yml); runner prerequisites, executed commands and non-production release gates are in [`docs/NATIVE_VALIDATION.md`](docs/NATIVE_VALIDATION.md). A queued or absent workflow is **not** a passed compiler test. Network serving remains disabled.
