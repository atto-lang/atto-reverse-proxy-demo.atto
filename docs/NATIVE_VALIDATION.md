# Native compiler / contract validation

The proposed network data plane is **not** implemented. This document describes the actual executable verification gate without using a replacement parser or mocked AttoLang compiler.

## CI

`.github/workflows/native-contracts.yml` checks all six AttoLang source modules and runs four native AttoLang test entrypoints:

- `tests/path_admission_contract.atto`: canonical absolute POSIX YAML path admission, traversal/symlink-shaped lexical rejection and control characters (not race-free access).
- `tests/yaml_policy_contract.atto`: strict YAML admission, malicious scalar/comment inputs, domain validation, and complexity bounds.
- `tests/generation_contract.atto`: pure prepare/publish/abort semantics, stale epoch rejection, prior-snapshot identity.
- `tests/middleware_generation_contract.atto`: old/new policy isolation and unsupported middleware rejection.

The workflow deliberately requires the self-hosted `oreslang-jdk25` runner label, `actions/setup-java` JDK 25, and an **approved and installed** `oreslang` executable in `PATH`. It uses only `contents: read`, does not check out the private compiler repository, and rejects fork-origin PR execution on this runner. The runner should be an ephemeral, unprivileged, dedicated validation environment with no deployment credentials and no untrusted co-tenants.

A **queued** workflow run is not a passing test. If there is no runner with this label, no guest code has executed. Before marking the PR ready, capture a green run on the exact PR head with actual individual steps, the AttoLang binary provenance, and the JDK 25 version.

## Local checks on an authorized runtime

With JDK 25 and the real Java/Graal `oreslang` launcher installed:

```text
oreslang --check src/main.atto
oreslang --check src/config_path.atto
oreslang --check src/proxy_yaml.atto
oreslang --check src/route_policy.atto
oreslang --check src/middleware_policy.atto
oreslang --check src/generation.atto
oreslang --check tests/path_admission_contract.atto
oreslang --check tests/yaml_policy_contract.atto
oreslang --check tests/generation_contract.atto
oreslang --check tests/middleware_generation_contract.atto
oreslang tests/path_admission_contract.atto
oreslang tests/yaml_policy_contract.atto
oreslang tests/generation_contract.atto
oreslang tests/middleware_generation_contract.atto
```

Do **not** silently skip missing executables or replace commands with grep-only/mocked checks. `src/main.atto` intentionally exits with status 78 on valid configuration because no listening/forwarding data plane is certified; a successful parsing check cannot stand in for a healthy proxy.

## Gates after source compilation

`tests/network_admission_contract.atto` is the first executable reverse pre-dial invariant: an upstream descriptor is produced only when the request-slot lease belongs to the same immutable generation, rate and breaker state permit, the selected route's exact HTTP(S) origin matches the resolved endpoint, and trusted resolver/network policy marks that endpoint pinned and allowed. The descriptor is not a network capability and cannot substitute for a real resolver/transport test. **A matching route is not proof of middleware admission.** Until an opaque, generation-pinned request-header/middleware receipt exists, `authorize_reverse` must reject every route carrying a nonempty middleware chain, including `deny` and `require_header`. The native contract now includes two negative fixtures that ensure those routes cannot mint a pre-dial descriptor, even when route, lease, DNS, rate and breaker checks would otherwise pass. This intentionally blocks some otherwise valid configured routes; it is not full middleware support.

Real HTTP/1.1 wire tests, correct reverse proxy response status/header/trailer streaming, forward CONNECT, TLS and destination IP pinning, request-smuggling/SSRF adversarial inputs, generation-pinned in-flight requests, actor cancellation/drain and bounded mailbox backpressure must pass before any release. LLVM, Graal AOT and hybrid must independently report verified support or explicit unsupported behavior.

## Runtime dependency and policy limitations

The outbound HTTP/CONNECT transport required for a serving proxy is tracked in [Java backend issue #1942](https://github.com/ores-truffle-oreslang/oreslang-source.java/issues/1942). Route and CONNECT policy helpers make **syntactic and declarative decisions only**, not network access grants. Upstream numeric port/IP range checks, TLS identity, pinned DNS, egress restrictions and real HTTP smuggling defenses remain transport release gates.

The `config_path` module enforces a canonical absolute POSIX spelling for `ores_proxy_conf_yaml`. It cannot prevent concurrent file replacement, ancestor symlinks or TOCTOU attacks; only a capability-based descriptor API can close that gap. Do not authorize hostile configuration paths based on this helper alone.

## Reviewed verification inventory

CI does not discover-and-trust new AttoLang files implicitly. Two committed manifests make the verification surface reviewable:

- `ci/oreslang-files.txt` is the complete sorted inventory of `src/**/*.atto` and `tests/**/*.atto` that must be compiler-checked.
- `ci/pure-contracts.txt` is the complete sorted inventory of standalone `tests/*_contract.ores` programs that must execute successfully.

The workflow first regenerates both inventories from the checked-out tree and diffs them against the committed manifests. A source or pure contract added without updating the manifest fails before compilation. A manifest entry whose file is missing fails the same way. Only then does the runner compiler-check every reviewed AttoLang file and execute every reviewed pure contract.

Integration fixtures that require a separately running listener or another process are compiler-checked through the complete source inventory but are not falsely treated as standalone pure tests. They need their own orchestration gate before any transport claim is promoted.

The actor-service TCP smoke and upstream wire behavior remain separate integration gates. Source-free inventory checks are not native runtime evidence.
