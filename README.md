# Oreslang reverse proxy (native Oreslang)

## AttoLang naming migration (2026-11-18)

**AttoLang** is the new public name for **Oreslang**. This `ores-truffle-oreslang/oreslang-reverse-proxy-demo.ores` repository is a legacy-named checkout. The corresponding AttoLang project for new work is [atto-lang/atto-reverse-proxy-demo.atto](https://github.com/atto-lang/atto-reverse-proxy-demo.atto). Do not assume that matching project names mean GitHub history, PRs, issues, code or feature completeness has been transferred. The existing project commands and implementation status below refer to this historical checkout.

The authoritative language specification is **[atto-spec](https://github.com/atto-lang/atto-spec)** (not old Oreslang README/spec prose); portable test fixtures belong in [atto-platform-conformance](https://github.com/atto-lang/atto-platform-conformance), and portable libraries in [atto-common-source](https://github.com/atto-lang/atto-common-source). The evolving language contracts include canonical `.atto` source, `snake_case` callable names, `borrow!`/`take!`/`copy!`/`copy!!`/`share!`, [implicit borrowing](https://github.com/atto-lang/atto-spec/blob/main/language/implicit-argument-borrow-v1.md), [file/module `define const` with guarded one-time `os.read_env`](https://github.com/atto-lang/atto-spec/blob/main/language/file-module-const-v1.md), and [bitwise `<<<`/`>>>`/`ashr` versus stream `<<`/`>>`](https://github.com/atto-lang/atto-spec/blob/main/language/bitwise-and-stream-operators-v1.md). These are **target rules**, not automatic execution claims for this repo.

Treat historical `.ores` fixtures, `oreslang-*` commands, package IDs, ABIs and examples below as compatibility instructions until verified changes supersede them. No Python project tooling/tests; prefer Rust support tooling. Compiler/runtime support and parity require exact source SHA/tree, target/toolchain, executed positive and negative guest tests; host-only or zero-step CI is **not executed** evidence.

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

`src/serve_reverse.ores` is a separate **experimental** Java/Graal HTTP/1.1 entrypoint. It reads the YAML path from `ores_proxy_conf_yaml` exactly once, accepts only loopback port 8080, matches routes, applies declarative `deny` / `require_header` middleware, and uses 100 pooled isolated request actors. Matched requests **always return HTTP 501**, because the runtime does not yet provide a safe status/header/binary-stream-preserving upstream HTTP client. It does not forward any request. Admission overload can reject requests separately.

`tests/ingress_tcp_smoke.ores` is a **native Oreslang** TCP test client, intended to run as a separate process while the experimental ingress is listening. It checks 501/403/404/400, including a path-normalization trap. The application and test client both require explicitly scoped Oreslang network capabilities. These tests have not yet been executed on the current PR head; treat the 400 path test as an open semantic gate until real wire evidence exists.

`src/proxy_wire.ores`, `src/header_policy.ores`, `tests/wire_contract.ores`, and `tests/header_policy_contract.ores` define further strict HTTP request-target and safe-header predicates with separate native Oreslang contract tests. They do **not** implement full HTTP parsing or copying and never grant outbound network authority. Read `docs/WIRE_AND_INGRESS.md` for the release blockers.
