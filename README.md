# Oreslang reverse proxy

Native Oreslang proxy project. Status: pre-release implementation; not a production proxy.

The supported transport contracts and configuration model are tracked under `src/`, `config/`, `tests/` and `docs/` on the implementation branch. There is no JavaScript, Python, Rust, or shell application source in this repository.

Security rule: configuration validation does not imply that a network listener, TLS proxy, CONNECT tunnel or zero-downtime reload is operational. Never expose this project as an unrestricted public proxy until exact-head transport/security tests pass.
