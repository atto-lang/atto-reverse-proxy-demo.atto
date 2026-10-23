# Oreslang reverse proxy (native Oreslang)

**Pre-release configuration/control-plane candidate, not an operational proxy.**

This repository now contains native Oreslang source for strict YAML-subset admission, deterministic route and middleware policy checking, CLI status handling, and self-contained Oreslang contract tests. The network data plane, actor-generation swaps and cross-backend transport integration remain gated. Valid YAML exits 78 instead of pretending an HTTP proxy has started.

Entry: `src/main.ores`. Config: `config/example.yaml`. Runtime architecture and limitations: `docs/ARCHITECTURE.md`. The source tree contains no Python, Rust, JavaScript or shell application scripts.

Config environment variable: **`ores_proxy_conf_yaml`** (lowercase exactly). CLI flag mapping: **`.cli-flags.toml`** for `flags-2-env`.
