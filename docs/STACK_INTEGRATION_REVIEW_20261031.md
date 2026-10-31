# Reverse proxy integrated candidate — REVIEW ONLY

**Date:** October 31, 2026  
**Status:** Draft integration candidate, not merge-ready. No native/guest evidence.

## Pinned input SHAs

| Input | Commit |
| --- | --- |
| protected-main target (currently unprotected) | `f3d4976b4321bd259d900e6a8d9819f05e52963a` |
| actor PR #22, including stacked #7→#9→#10→#11 | `f4cfaa669532a9d30de11f38ff8ad027eaf1b48d` |
| native control-plane PR #20 | `4fae92102da87ed01f820635005da32c39358d85` |
| safe-defaults PR #30 | `fbe80539760f2bcb064dd91eea601e036c740001` |

Integration candidate's first assembled **source tree**:
`c20b120a3346bb555a4a06640f6eb246bb2cee16`.
Its integration commit `72be6ec11526e004924e95dda34cf82fd3ade6e4`
is a single-parent commit based on the current main above. It does not
merge any existing PR or certify semantic conflict resolution.

## Construction and collision resolution

- Begin with the exact **current main tree**. Retain unrelated existing
  paths, especially `.github/PULL_REQUEST_TEMPLATE.md`,
  `.github/workflows/upstream-source-hygiene.yml`,
  `docs/DEMO_RELEASE_GATES.md`, and
  `docs/UPSTREAM_SOURCE_TIPS_2026-10-29.md`.
- Apply the **39 changed file blobs** from PR #22's full stacked actor
  tree; retain all reviewed actor, middleware, lexical, generation and
  on-wire fixtures. This supersedes portions of older main Oreslang source
  and documentation: these are **explicit review conflicts**, not proof
  that the actor version is semantically safe.
- Overlay the six PR #20 native-control file blobs. Its
  `.github/workflows/native-contracts.yml` is byte-identical to the
  actor version (blob `4f167ddefc97fcead03723f6b7f109663040942e`);
  this resolves the only direct native workflow overlap.
- Overlay the two PR #30 safe-defaults file blobs. The canonical
  `.cli-flags.toml` and `config/example.yaml` are byte-identical across
  the four pinned inputs; these original config bytes are retained.
- The assembled tree has **75 regular tracked files**, **38 .ores
  source/test files**, **17 standalone pure contracts**, **no tracked
  Python files**, and no special Git file modes. File-level critical
  source/workflow/config blob hashes were checked against the inputs.

## Manual source-level review required (unresolved)

The following old-main paths differ materially from actor PR #22. Do not
treat selecting actor blobs as a completed semantic merge:

- `src/config_path.ores`: broader control-byte rejection.
- `src/header_policy.ores`: full header control-byte filtering and
  connection nomination checks.
- `src/middleware_manifest.ores` and `src/middleware_policy.ores`:
  middleware header/value validation and fail-closed policy.
- `src/proxy_wire.ores`: canonical request target and control-byte rules.
- `src/proxy_yaml.ores`: substantial schema expansion (services, backends,
  routes) and stricter hostname/IP validation. Confirm against current
  valid/negative YAML fixtures and independently approve behavior changes.
- `src/serve_reverse.ores`: replaces the legacy 501-only listener with
  local service-dispatch actors. No native execution receipts exist.
- `tests/yaml_policy_contract.ores`: one former negative fixture now
  explicitly rejects ambiguous middleware names; verify with compiler.
- `README.md`: distinct main-versus-actor descriptions need editorial
  reconciliation. Retain main's restriction on `require_header`
  (header presence is **not** authentication).

Before any merge, obtain independent review on the final integrated head,
check no syntax/ABI incompatibilities against the current Java/Graal runtime,
and verify `define isolated actor`/state/`handle_state`/`critical`
migration. Current `define isoactor` syntax is still unverified.

## Native and CI evidence separation

- `trusted-frozen-reverse-native.yml` from PR #20 pins source commit
  `1a667fcd4481e3511e0cfa1008e855d96540c200` and tree
  `5937599df00b6122dccaf22bcdebdaf836f6d3ee`.
  **Running it does not test this integrated candidate.** Never repoint
  a trusted runner to PR-controlled source or relax its protected-main
  preflight as a shortcut.
- `actor-ingress-wire.yml` is dispatch-only, protected-main only, and
  requires a restricted `oreslang-trusted-native` group and an approved
  root-owned runtime manifest. It must stay disabled for this draft PR.
- Hosted source-only Bash gates from #20, #22 and #30 need real stepful
  execution on this **exact resulting commit**, not a zero-step failure.
- Previous PR #22 run #41229048820, attempt 2, had no assigned runner and
  `steps=null`, so it provides **NOT_EXECUTED**, not failed Bash/guest tests.
- No source tree was mirrored outside this repository, and no release PR
  was merged by creating this candidate.

## Acceptance sequence

1. Administrative owner: diagnose Actions admission; protect private main,
   require nonauthor review/status checks and verify bypass restrictions.
2. Independent reviewer: review all manual semantic conflicts above,
   canonical source/defaults, frozen-source control-plane boundaries,
   nested actor-PR dependency order and source policy.
3. Hosted CI: execute complete source manifests, Bash audit,
   checkout-integrity negatives, policy and safe-defaults fixtures on
   this commit and retain nonzero step logs, exact head/tree/run attempt.
4. Native admission: approve runtime manifest, designated workflow runner
   group, and execute actual compiler-backed actor+TCP tests only on an
   independently approved protected source.
5. Revalidate upstream/CONNECT authority, DNS-to-dial pinning, request
   cancellation, stream framing and actor generation fences separately.

**Release gate: BLOCKED. Keep this candidate in draft.**

## October 31 semantic reconciliation patch

The audit of the integrated application/header/YAML sources found two
config-admission inconsistencies that can be fixed without granting transport
authority:

1. `src/proxy_yaml.ores::validate_route` previously permitted route prefixes
   containing `..` within a segment (for example `/api..v2`) even though
   `src/proxy_wire.ores::strict_path` rejects **any** `..` sequence in an
   incoming request path. The configured route could never be selected via the
   admitted HTTP request path. The parser now rejects such prefixes.
2. `src/proxy_yaml.ores::parse` previously allowed a duplicated name in the
   same route middleware chain (for example `guard,guard`) while
   `middleware_manifest.bind` rejects duplicate pipeline entries. The parser
   now requires each route middleware identifier to be canonical, unique,
   and resolvable to a snapshot middleware definition.

`tests/yaml_policy_contract.ores` now includes negative probes for
embedded-dot prefixes, repeated/malformed middleware lists, and a positive
`guard,audit` pipeline with distinct valid stages.
`tests/header_policy_contract.ores` now checks malformed
`Connection` nominations, Unicode whitespace, and C0/DEL values.
`ci/sourcefree_proxy_audit.sh` records six additional structural
assertions about these guards and guest test verdicts. The existing
`src/header_policy.ores` implementation did not require a source change.

**Evidence classes:** source diffs and static assertions are reviewable;
there is **no executed Oreslang guest parser, JDK25 compiler, or TCP receipt**
for these new cases. A text-match guard is not a semantic test pass.

### Actor runtime ABI and ownership migration — still blocked

The integration's `src/serve_reverse.ores` still contains the legacy actor
definitions `define isoactor UpstreamUnavailable/HelloV1/StreamV1`,
`receive(ActorMail<String> mail)`, and `http.claim(mail.value)`. This is
**not yet compiler-verified** against the current language direction:
`define isolated actor Name as ... end`, explicit actor-owned `state`,
`handle_state`, `critical` state mutation and structured cancellation.

The runtime's `http.handler(...).scoped(...).pooled(...).dispatch(...)`
adapter must be checked for the **exact native guest ABI**, including:

- Whether a typed, generation-fenced message can be received by a
  `handle_state` handler without violating actor non-reentrancy.
- Who exclusively owns the single-use `HttpExchange` and TCP FD before
  `http.claim`, after `dispatch`, and after completion or cancellation.
- Whether a stale, wrong-service, wrong-image, or wrong-generation receipt
  is rejected **before** any actor response, including after suspension.
- Whether an abandoned streaming client releases all credits, leases,
  continuations and actor ownership without reusing a stale receipt.
- Whether actor state uses `critical` for every mutation; no synchronous
  blocking I/O should be introduced on the actor carrier.

Do **not** mechanically rename `isoactor` to `isolated actor` or replace
`receive` with `handle_state` without checking the actual compiled
runtime adapter and ensuring negative receipts compile/execute. Keep the
legacy guest syntax and this integration draft as **unqualified** until
an independently approved native execution produces exact-source compiler
and HTTP/TCP receipts.

This work does not repair the pre-read configuration byte cap or symlink/
TOCTOU race in `fs.read_text`; those still need a verified bounded
file-open API and actor-owned descriptor lifetime.

### Revalidation after this source patch

- Recompute root tree and both inventories (38 .ores files and 17 pure
  contracts unless intentionally updated).
- Run Bash syntax, the source-free audit and source-policy/safe-defaults
  negative fixtures on a **stepful, exact-head hosted runner**.
- Compile `src/proxy_yaml.ores`, `tests/yaml_policy_contract.ores`,
  `tests/header_policy_contract.ores`, `src/serve_reverse.ores` and
  `tests/actor_ingress_tcp_smoke.ores` using an approved source-pinned
  runtime. Execute valid and negative guest fixtures, then bounded TCP tests.
- Obtain nonauthor approval *after* the final commit, require protected
  `main` and independently reviewed native runner authorization.

No release promotion or self-hosted native execution is authorized by this
source-only change.
