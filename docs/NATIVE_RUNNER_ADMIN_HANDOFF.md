# Reverse proxy: trusted native runner and merge-admission handoff

This is an **administrator action checklist** for the source repository
`ores-truffle-oreslang/oreslang-reverse-proxy-demo.ores`. It is not permission to
mirror private source into another GitHub organization, to weaken branch rules,
or to assume that a queued job passed.

## 1. Source-org runner and runtime

An organization/repository administrator must provision an isolated,
ephemeral or dedicated, **trusted** GitHub Actions runner assigned only to
approved Oreslang repositories, with labels exactly:

`self-hosted`, `linux`, `x64`, `oreslang-jdk25`.

Before accepting PR workloads, verify the registered runner is online, not
occupied by an unrelated tenant, and permitted for this repository. Use a
pinned, independently reviewed Oreslang Java/Graal executable and JDK 25.
The runner setup must have source-independent bootstrap and a bounded
workload lifetime. Do not place repository-write credentials or reusable
cross-organization secrets in PR job environments.

In **Settings → Secrets and variables → Actions → Variables**, set
`ORESLANG_APPROVED_SHA256` to the exact 64-character lowercase SHA-256 of
the reviewed launcher file. This value is an administrator decision, **not**
a value supplied by a test PR or author. The existing native/wire workflows
fail closed if the digest is absent, malformed or different at execution.

The compiler launcher must be usable through `oreslang` on the runner PATH.
A successful JDK 25 installation alone is not evidence that this guest
compiler exists or supports the syntax in the PR.

## 2. Existing workflows and actual execution

After the runner is online, let GitHub schedule the workflows at **each PR's
current HEAD**. Do not test old commit SHAs and relabel results as current.

- `.github/workflows/native-contracts.yml`: exact source checkout,
  checked-out tree and approved launcher digest, inventory diff, compiler
  checks of all reviewed `.ores` files, every standalone contract test.
- `.github/workflows/actor-ingress-wire.yml` (PR #11): same provenance
  checks, server/client native compilation, isolated localhost TCP listener,
  streaming response and malformed-route/abandoned-stream smoke tests.
- `.github/workflows/sourcefree-proxy-security.yml`: defense-in-depth
  structure checks only. It **cannot** replace the compiler or wire jobs.

For each run, preserve the run ID, run attempt, exact `head_sha`,
`git rev-parse HEAD`, `git rev-parse HEAD^{tree}`, launcher SHA-256,
runner identity, JDK version, full job-step conclusions and failures.
A run with `steps=[]`, no runner, `queued` or `pending` is
**not an executed test**. A green source-free job is not native evidence.

If hosted Actions fail with zero steps, inspect runner allocation, repository
Actions permissions/billing and org policy. Do not label that a syntax or
runtime test failure.

## 3. Branch governance (source repo)

In **Settings → Branches / Rulesets**, establish an enforced rule for
`main` that requires pull requests, independent approval after the latest
push (dismiss stale approvals), conversation resolution, the genuine native check and the applicable
actor-wire check, blocks force-push/deletion and has no administrator bypass.
Require the expected final status-check names from the actually executed
workflows, not placeholder or historically green checks.

Obtain a submitted independent approval from `ORESoftware` or another
authorized reviewer for every exact head. Requested reviewers and draft
status do not count as approval. Do not make author-controlled status markers
the release admission oracle.

## 4. Cross-org capacity is separate from authorization

The private-source transfer approval is tracked at
`ores-truffle-oreslang/oreslang-source.java#1501`. A source-free test in
another private organization demonstrates **capacity**, not permission to
copy private Git objects. No cross-org source mirroring without separately
reviewed numeric source/destination repository IDs, a protected allowlist,
a one-use authorization, exact tree manifest/digest verification and
approved private-source retention/cleanup rules.

Prefer the source-org trusted runner if it can execute all native steps.

## 5. Final merge sequence, only after the gates above pass

The required dependency order is **#7 → #9 → #10 → #11**. Re-fetch every
PR's head and base immediately before merge. Promote eligible drafts to ready
only after native checks and independent review, use the expected-head SHA
when merging, and retest dependents after their base changes.

For #11, the actor TCP fixture exercises disconnect survivability, **not**
the stronger physical-quiescence/loan-retirement safety property. Do not
claim the latter without a runtime instrumentation/retirement gate.
