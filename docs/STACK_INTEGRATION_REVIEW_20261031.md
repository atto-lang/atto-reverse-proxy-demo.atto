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
