## Rust flags-2-env host gate

`.github/workflows/safe-defaults.yml` compiles and runs `ci/flags_contract.rs` using `rustc` (no Python or external Rust crates). It tests invalid keys, duplicate tables, unsupported/ambiguous TOML encodings, ordering, and untrusted symlinks. This intentionally validates only the reviewed subset of TOML needed for `.cli-flags.toml`; changes requiring richer TOML must extend the parser and negative tests before acceptance.

The gate checks the exact checked-out PR head and refuses missing or altered policy fields. It is **HOST_ONLY** and makes no claim that a native `.atto` guest, transport, or backend AOT was compiled or executed. Rust compiler/test and GitHub Actions execution must succeed at the final exact head before this draft can be promoted.
