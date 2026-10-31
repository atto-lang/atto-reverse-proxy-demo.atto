# Exact-head Oreslang real-wire actor ingress acceptance

This is an *executable regression gate*, not an assertion of a successful run.
Use the native Oreslang launcher supplied by the trusted isolated
`oreslang-jdk25` GitHub Actions runner. Workflow:
`.github/workflows/actor-ingress-wire.yml`.

The candidate workflow is **manual-dispatch only from protected main**;
it does not accept PR-head source on a trusted self-hosted runner. A
source-free hosted preflight validates the live private repository
identity, current protected-`main` commit, and effective GitHub rules:
independent approval, stale-review dismissal, last-push approval,
resolved conversations, at least one required status check, and protections
against force-pushes and branch deletion. The native job repeats those live
checks before running guest code, because the protected branch's settings
may change after the hosted job passes. An independent administrator
must also restrict `oreslang-trusted-native` to this specifically approved
workflow, verify review/no-bypass settings, and approve the root-owned
`/opt/oreslang-approved/oreslang-runtime` runtime manifest. Neither
`main` branch protection nor runner provisioning is presently verified.

If those gates eventually pass, the job checks out the exact protected-main
commit, records its Git tree and the Oreslang runtime manifest plus launcher
digest, validates the embedded JDK25, checks both Oreslang programs, and
launches `src/serve_reverse.ores` in a subprocess on
`127.0.0.1:8080`, and calls `tests/actor_ingress_tcp_smoke.ores` as a
separate native Oreslang client. The client checks:
- HTTP 200 for the allowlisted statically compiled local Oreslang actor service, plus a separate streaming actor response with chunked HTTP/1.1 transfer framing, no conflicting Content-Length, both text body stages in order, and a terminal zero-length chunk
- HTTP 501 for an admitted but unimplemented outbound HTTP upstream
- HTTP 403 when the configured presence-check middleware fails
- HTTP 400 for a percent-encoded noncanonical traversal target and HTTP 404 for an unconfigured route, each tested through a separate loopback TCP connection
- Four clients that send a complete streaming request and immediately close their TCP connections, followed by a fresh local actor-service request that must still return HTTP 200

The disconnect sequence is **listener survivability evidence only** if it executes: it cannot prove that the abandoned stream's task was cancelled at a specific linearization point or that a receiver/state loan was physically retired. Those claims require actor-local continuation accounting, an observable quiescence barrier, scheduler/task-retirement instrumentation, and explicit bounded-retirement tests; none is present in this fixture.


The server receives `ores_proxy_conf_yaml` containing the canonical
absolute `config/worker-example.yaml` path; the runner only grants its
single configuration file as filesystem read authority, one named env variable
and loopback TCP port 8080. There is no `--allow-all` or remote outbound
network grant. All application and test code is native Oreslang; minimal Bash
is GitHub Actions process orchestration only, not a deployed proxy script.

Source uses the documented `handler.dispatch(rt borrow mut exchange)`
single-owner exchange handoff. The bounded readiness loop and EXIT cleanup
ensure the test fails explicitly instead of silently passing when the server
never starts. If runner admission is queued, **no program has executed**.

The wire client explicitly separates HTTP headers from the body before accepting the two text stage markers. It fails on absent/incorrect chunked transfer headers, conflicting Content-Length, duplicate/reordered stages, or a missing terminal chunk. Its line-oriented fixture check is **not** a general binary-safe RFC 9112 chunk parser and does not validate trailers or malicious chunk extensions.

The streaming proof exercises the existing server-side `exchange.start/write/finish` guest API and a separate native Oreslang TCP client. It does not turn the Java host-only outbound HTTP proof into a guest API. The test **does not** validate remote upstream HTTP streaming, authenticating
CONNECT, content framing under malicious inputs, true GraalVM AOT, or LLVM.
These remain separate transport acceptance gates. In particular, the
package-private Java host-only proof in `oreslang-source.java` PR #1943
does not make an Oreslang guest outbound request API available.

See `docs/WORKER_PARITY.md` for future HAProxy/NGINX/workerd goals.

## Security of the execution control plane

The previous actor-ingress workflow admitted same-repository `pull_request`
events on a generic self-hosted runner, even though the source remained
unreviewed and `main` was not protected. This is **not** an acceptable native
runner boundary for private source. The current PR removes that admission path,
requires `workflow_dispatch` on protected main, checks live private-repository identity, effective review/status/branch
integrity rules and the exact default-branch SHA before allocating a native
runner, and uses the approved `oreslang-trusted-native` runner group rather
than the default pool. A second live governance check on the native job
detects configuration drift before invoking any Oreslang guest code. The
effective-rules API does **not** prove the absence of administrator or
organization bypass exceptions; an independent administrator must verify
those privileges and the selected-workflow runner-group restriction.

The native step requires an unprivileged runner, root-owned and
non-group/world-writable runtime files, no symlinks or special objects, a
complete runtime manifest digest supplied by an administrator, embedded JDK25,
and an approved launcher SHA-256. Server and client invocation use the
digest-and-manifest checking wrapper. This is a **proposed** gate, not evidence
that the workflow has passed, that every runtime race has been eliminated,
or that the protected-main governance is configured.

The serving guest still uses the pre-migration `define isoactor` /
`receive(ActorMail<String>)` syntax. A compiler-backed migration to
`define isolated actor`, explicit `state` and `handle_state` with
`critical` state mutations is outstanding. Do not claim verified guest
syntax until an exact-head compiler check actually executes.

### Physical source-checkout identity gate

After the native runner rechecks private protected-main governance **before
checkout**, the pinned checkout is audited before any compiler invocation.
The check uses explicit `--git-dir` and `--work-tree` paths for the actual
job workspace and clears ambient Git object/index/repository routing variables.
The checkout's Git directory must be real, not a symbolic link.

Acceptance requires the exact `github.sha` HEAD, a canonical 40-hex tree
identity, identical index and tracked worktree contents, and **zero** extra
untracked files, including ignored files. `core.filemode=true` ensures
executable-bit changes are not hidden by runner Git configuration. A separate
frozen runtime manifest and launcher digest gate follows this source audit.

A local hermetic Git test on October 31, 2026 accepted the clean checkout and
an invocation with poisoned ambient Git routing, and rejected dirty tracked
bytes, staged modifications, ignored/untracked files, and chmod drift. These
checks only prove the standalone Bash identity predicate on a synthetic Git
repository. They are **not** a successful GitHub workflow run, native Oreslang
compile, or on-wire proxy receipt.

### Acceptance evidence ledger

- Admission: hosted preflight job has **nonzero steps** and binds current
  protected-main SHA; a missing hosted runner is NOT_EXECUTED.
- Native: runner-group access and manifest approvals are independently
  reviewed, nonzero steps prove approved JDK and launcher, and both programs
  compile at that exact SHA.
- Loopback: native server reaches readiness, the native client verifies
  authorized HTTP 200, denied HTTP 403, unimplemented HTTP 501, invalid
  HTTP 400, unknown HTTP 404, and bounded streaming receipts.
- Security: stale actor receipts, true cancellation/retirement, DNS-to-dial
  integrity, off-host upstream forwarding and CONNECT remain **not proven**
  by this local actor test.

## Source-free Bash audit and CI integration

This draft now replaces the obsolete Python source-only checker and legacy
native-workflow provenance tests with `ci/sourcefree_proxy_audit.sh` and
`ci/test_workflow_admission.sh`. The former defines 62 authored static
assertions plus complete reviewed source/contract inventory and lexical
C0/DEL checks; the latter defines nine adverse workflow mutations. These
assertions preserve critical actor-receipt, header, middleware, route, and
loopback constraints, but are **not** byte-for-byte or semantic replacements
for every historical Python assertion. Guest compiler and transport proof
remain separate mandatory gates.

`.github/workflows/sourcefree-proxy-security.yml` now uses Bash on a
GitHub-hosted `ubuntu-24.04` runner only. Its same-repository PR, manual-main,
and exact actor-branch push triggers require a pinned event checkout and
no privileged native runner. The committed branch has no tracked `.py`,
`.pyi`, or `.ipynb` files. This is compatible with the Python-source
prohibition in reverse control-plane PR #20.

PR #22 still targets the earlier actor-ingress feature branch rather than
`main`. The current `.github/workflows/native-contracts.yml` Git blob is
identical in #20 and #22 (`4f167ddefc97fcead03723f6b7f109663040942e`).
The source-only Bash audit and the protected-main native workflow are
complementary, but merging/rebasing stacked branches must preserve the
exact source inventories and rerun all checks on the new resulting head.

**Evidence:** source inspection and exact-tree/manifest comparisons only.
GitHub run #41228083823 failed with no reported executed steps, so the new
Bash suite is **NOT_EXECUTED** in Actions. No Oreslang compilation, HTTP
wire verification, approval, or merge readiness follows from the static
source-policy reconciliation.
