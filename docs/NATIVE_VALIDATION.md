# Native compiler / contract validation

The proposed network data plane is **not** implemented. This document describes the actual executable verification gate without using a replacement parser or mocked Oreslang compiler.

## CI

`.github/workflows/native-contracts.yml` checks all five Oreslang source modules and runs three native Oreslang test entrypoints:

- `tests/yaml_policy_contract.ores`: strict YAML admission, malicious scalar/comment inputs, domain validation, and complexity bounds.
- `tests/generation_contract.ores`: pure prepare/publish/abort semantics, stale epoch rejection, prior-snapshot identity.
- `tests/middleware_generation_contract.ores`: old/new policy isolation and unsupported middleware rejection.

The workflow deliberately requires the self-hosted `oreslang-jdk25` runner label, `actions/setup-java` JDK 25, and an **approved and installed** `oreslang` executable in `PATH`. It uses only `contents: read`, does not check out the private compiler repository, and rejects fork-origin PR execution on this runner. The runner should be an ephemeral, unprivileged, dedicated validation environment with no deployment credentials and no untrusted co-tenants.

A **queued** workflow run is not a passing test. If there is no runner with this label, no guest code has executed. Before marking the PR ready, capture a green run on the exact PR head with actual individual steps, the Oreslang binary provenance, and the JDK 25 version.

## Local checks on an authorized runtime

With JDK 25 and the real Java/Graal `oreslang` launcher installed:

```text
oreslang --check src/main.ores
oreslang --check src/proxy_yaml.ores
oreslang --check src/route_policy.ores
oreslang --check src/middleware_policy.ores
oreslang --check src/generation.ores
oreslang --check tests/yaml_policy_contract.ores
oreslang --check tests/generation_contract.ores
oreslang --check tests/middleware_generation_contract.ores
oreslang tests/yaml_policy_contract.ores
oreslang tests/generation_contract.ores
oreslang tests/middleware_generation_contract.ores
```

Do **not** silently skip missing executables or replace commands with grep-only/mocked checks. `src/main.ores` intentionally exits with status 78 on valid configuration because no listening/forwarding data plane is certified; a successful parsing check cannot stand in for a healthy proxy.

## Gates after source compilation

Real HTTP/1.1 wire tests, correct reverse proxy response status/header/trailer streaming, forward CONNECT, TLS and destination IP pinning, request-smuggling/SSRF adversarial inputs, generation-pinned in-flight requests, actor cancellation/drain and bounded mailbox backpressure must pass before any release. LLVM, Graal AOT and hybrid must independently report verified support or explicit unsupported behavior.
