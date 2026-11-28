# Middleware header admission: five-toolchain conformance gate

Status: **authored native Oreslang source/tests; NOT_EXECUTED on Java, LLVM, Wasm, Cranelift, or .NET.**

This is a *pure policy* contract. A nonempty `require_header` value is not sufficient when its name or value is malformed. Both the YAML-snapshot evaluator and generation-pinned immutable manifest must return **deny** for the same input. This change does not imply an HTTP listener, a wire parser, a trusted authentication mechanism, or production forwarding.

## Shared regression matrix

| Input | Snapshot evaluator | Pinned manifest |
| --- | --- | --- |
| exact canonical `x-auth-token`, nonempty safe value | allow | allow |
| empty or whitespace-only value | deny | deny |
| uppercase/mismatched field name | deny | deny |
| CRLF and forged field line | deny | deny |
| newline-only injection | deny | deny |
| embedded NUL | deny | deny |
| embedded horizontal tab | deny | deny |
| `deny` middleware | deny | deny |
| unchanged prior `trace` generation | allow | allow |

The regression fixtures are **tests/middleware_generation_contract.ores** and **tests/middleware_manifest_contract.ores**, and they exercise the actual `src/middleware_policy.ores`, `src/middleware_manifest.ores`, and `src/header_policy.ores` modules. None of these predicates is a replacement for byte-level HTTP parser and framing admission.

## Required independent backend qualification

For **each** of these five toolchains, run the same checked-in `.ores` source, not translated JavaScript/Python test lookalikes:

1. **Java / GraalVM:** exact-head parser/type/ownership checks and both regression executables.
2. **LLVM:** same source and expected exit status/stdout; run native sanitizer builds where available.
3. **Wasm:** same source and expected exit status/stdout under a deterministic host; enforce sandbox capability denial.
4. **Cranelift / Forge:** same source and outputs under the independent compiler/runtime, not just a Java fallback.
5. **.NET NativeAOT:** same source and outputs in release NativeAOT mode, including fail-closed result handling.

For each compiler/launcher, equivalent checks must cover:

```text
<approved-backend-launcher> --check src/middleware_policy.ores
<approved-backend-launcher> --check src/middleware_manifest.ores
<approved-backend-launcher> --check tests/middleware_generation_contract.ores
<approved-backend-launcher> --check tests/middleware_manifest_contract.ores
<approved-backend-launcher> tests/middleware_generation_contract.ores
<approved-backend-launcher> tests/middleware_manifest_contract.ores
```

Replace the placeholder with the backend's **documented, verified** CLI; do not assume the five launchers support identical flags. Both test entrypoints must exit **0** and print a `PASS` line. A missing compiler, queued job, absent runner, skipped step, or source-inventory-only success is **NOT_EXECUTED**, never parity.

## Security and release requirements

- Pin exact **source commit and Git tree**, build/runtime/launcher identity, platform and test artifacts; collect executed job IDs, actual step records, exit statuses and logs for each backend.
- Do **not** allow an unreviewed PR head to execute on privileged self-hosted runners. Do not transfer private source to an alternate CI organization without separately approved immutable repo IDs, visibility, source/destination authorization, access, retention and cleanup policy.
- Reject duplicate, obs-folded or invalid raw HTTP fields; enforce `Content-Length`/`Transfer-Encoding` precedence; enforce canonical Host/authority, trusted proxy headers, response framing, DNS pinning and egress ACLs in the **transport** before treating these predicates as meaningful.
- Require independent review and protected release branches before merge. This document and its source tests do not remove the current **data plane unavailable** status.
