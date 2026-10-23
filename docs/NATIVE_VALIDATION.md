# Native compiler / contract validation

The proposed network data plane is **not** implemented. This document describes the actual executable verification gate without using a replacement parser or mocked Oreslang compiler.

## CI

`.github/workflows/native-contracts.yml` checks all six Oreslang source modules and runs four native Oreslang test entrypoints:

- `tests/path_admission_contract.ores`: canonical absolute POSIX YAML path admission, traversal/symlink-shaped lexical rejection and control characters (not race-free access).
- `tests/yaml_policy_contract.ores`: strict YAML admission, malicious scalar/comment inputs, domain validation, and complexity bounds.
- `tests/generation_contract.ores`: pure prepare/publish/abort semantics, stale epoch rejection, prior-snapshot identity.
- `tests/middleware_generation_contract.ores`: old/new policy isolation and unsupported middleware rejection.

The workflow deliberately requires the self-hosted `oreslang-jdk25` runner label, `actions/setup-java` JDK 25, and an **approved and installed** `oreslang` executable in `PATH`. It uses only `contents: read`, does not check out the private compiler repository, and rejects fork-origin PR execution on this runner. The runner should be an ephemeral, unprivileged, dedicated validation environment with no deployment credentials and no untrusted co-tenants.

A **queued** workflow run is not a passing test. If there is no runner with this label, no guest code has executed. Before marking the PR ready, capture a green run on the exact PR head with actual individual steps, the Oreslang binary provenance, and the JDK 25 version.

## Local checks on an authorized runtime

With JDK 25 and the real Java/Graal `oreslang` launcher installed:

```text
oreslang --check src/main.ores
oreslang --check src/config_path.ores
oreslang --check src/proxy_yaml.ores
oreslang --check src/route_policy.ores
oreslang --check src/middleware_policy.ores
oreslang --check src/generation.ores
oreslang --check tests/path_admission_contract.ores
oreslang --check tests/yaml_policy_contract.ores
oreslang --check tests/generation_contract.ores
oreslang --check tests/middleware_generation_contract.ores
oreslang tests/path_admission_contract.ores
oreslang tests/yaml_policy_contract.ores
oreslang tests/generation_contract.ores
oreslang tests/middleware_generation_contract.ores
```

Do **not** silently skip missing executables or replace commands with grep-only/mocked checks. `src/main.ores` intentionally exits with status 78 on valid configuration because no listening/forwarding data plane is certified; a successful parsing check cannot stand in for a healthy proxy.

## Gates after source compilation

Real HTTP/1.1 wire tests, correct reverse proxy response status/header/trailer streaming, forward CONNECT, TLS and destination IP pinning, request-smuggling/SSRF adversarial inputs, generation-pinned in-flight requests, actor cancellation/drain and bounded mailbox backpressure must pass before any release. LLVM, Graal AOT and hybrid must independently report verified support or explicit unsupported behavior.

## Runtime dependency and policy limitations

The outbound HTTP/CONNECT transport required for a serving proxy is tracked in [Java backend issue #1942](https://github.com/ores-truffle-oreslang/oreslang-source.java/issues/1942). Route and CONNECT policy helpers make **syntactic and declarative decisions only**, not network access grants. Upstream numeric port/IP range checks, TLS identity, pinned DNS, egress restrictions and real HTTP smuggling defenses remain transport release gates.

The `config_path` module enforces a canonical absolute POSIX spelling for `ores_proxy_conf_yaml`. It cannot prevent concurrent file replacement, ancestor symlinks or TOCTOU attacks; only a capability-based descriptor API can close that gap. Do not authorize hostile configuration paths based on this helper alone.
