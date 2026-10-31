# Oreslang proxy native qualification — review/CI handoff

Updated 2026-10-31. **This is a test plan, not executable CI evidence.**

## Security admission

The legacy `.github/workflows/native-contracts.yml` on these audit branches is
**retired and fail-closed**. It does not accept pull-request triggers, does not
reserve a self-hosted runner and exits nonzero (`NOT_EXECUTED`) on manual
dispatch. Excluding forks alone was not enough: same-repository PR authors
could still control guest code on a privileged self-hosted runner.

Real native acceptance requires independently reviewed protected-default-main
control-plane workflows, a locked `oreslang-trusted-native` runner group,
an administrator-owned complete runtime directory/manifest and exact-head
frozen-source attestation. See forward security PR #19 and reverse #20.
Do not activate, bypass or merge these controls through an audit branch.

The source-only `.github/workflows/source-contract-inventory.yml` verifies
tracked source bytes and coverage, but **does not compile or execute Oreslang**.

## Exact immutable source snapshots for this audit

Record both full 40-character source commit SHAs and rooted Git-tree SHAs
from the reviewed source branches. Source execution is only valid if the
guest checkout matches the entire independently approved source tree:
paths, modes, blob SHAs, submodule/symlink policy and content, not merely
a few selected files. The working directory must have no modifications.
Any mirrored source must use a separately approved PRIVATE carrier with
recorded numeric destination ID, retention, least-privilege permissions,
runner separation and cleanup limitations. A copied loose blob is not a
complete validated mirror.

## Native compiler requirements (currently unmet for these snapshots)

Provide an independently attested **real** Oreslang Java/Graal runtime,
complete dependency/JDK25 manifest and exact compiler executable SHA-256.
A host JDK or Native Image binary alone is NOT an `oreslang` compiler.
The trusted runner must confirm the immutable approved runtime before
and between native guest invocations and enforce bounded time/resources.
No mock parser or synthetic Oreslang executable may satisfy this gate.

## Exhaustive native contract entrypoints

Check **every** tracked `src/*.ores` and `tests/*.ores` with the real
compiler, including `src/http_framing.ores`, `src/header_policy.ores`,
`src/proxy_wire.ores`, and their import closure. Do NOT run `src/main.ores`
as a ready server; it is intentionally not a production data plane.

Execute these 11 standalone native contract entrypoints for EACH source
snapshot, preserving nonzero exits and actual output:

- `tests/data_layout_contract.ores`
- `tests/generation_contract.ores`
- `tests/header_policy_contract.ores`
- `tests/http_framing_contract.ores`
- `tests/middleware_generation_contract.ores`
- `tests/middleware_manifest_contract.ores`
- `tests/path_admission_contract.ores`
- `tests/slot_lifecycle_contract.ores`
- `tests/slot_pool_contract.ores`
- `tests/wire_contract.ores`
- `tests/yaml_policy_contract.ores`

The shared framing test includes 45 native parser invocations covering
canonical bodyless requests, duplicate Host and ordinary header rejection,
CL/TE conflicts, malformed CRLF, pipelining, control bytes and CONNECT
authority mismatch. **Counting source invocations is not test execution.**

On reverse only, `tests/ingress_tcp_smoke.ores` is a separate controlled
loopback integration test. Record its exact configuration and listen
address, assert denied/unmatched/501 paths and bounded shutdown, and
do not classify it as upstream forwarding success. Never run network
smoke with unexpected host networking, ingress or egress capabilities.

## Evidence and honest verdicts

For every job: record immutable source head/tree, validated source-file
inventory, compiler source and launcher SHA-256, approved runtime
manifest, Java/native-image version where applicable, runner ID, run
attempt, individual executed step list, each command's exit status,
stdout/stderr (redacted, without source or secrets) and test summary.
For each tested backend, distinguish `PASS`, `FAIL`, `NOT_EXECUTED`,
`SKIPPED` and `UNSUPPORTED` explicitly. No step or assigned runner
means `NOT_EXECUTED`, not a source failure or a pass.

## Remaining production release boundaries

Neither proxy has a production-safe forwarding data plane. Real raw-byte
framing, correct response/status/trailer streaming, authenticated ingress,
pinned DNS and destination IP checks, TLS identity, SSRF and smuggling
controls, generation fencing, bounded actor mailboxes and cancellation
must be independently verified before any network serving release.
A strict text-frame parser alone does not prove raw wire safety.
