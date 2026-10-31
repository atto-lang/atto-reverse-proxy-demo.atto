# Proxy admission hardening

This audit extends the existing strict-boundary draft. Neither demo is a
production proxy. The CLI validates configuration and exits nonzero; reverse
opt-in ingress has no upstream forwarding, and forward CONNECT parsing grants
no socket authority. Keep those boundaries closed.

## Corrected source behavior

- A shared predicate rejects all 32 C0 controls plus DEL in header values,
  configuration paths and HTTP origin-form paths. YAML applies it to each raw
  line after splitting LF, including comments, and to individual scalar values.
- Connection nominations accept only the existing lowercase ASCII name subset
  with optional ASCII spaces around each token. Validate the original token
  before trimming and inspect the complete list before returning. A nominated
  response field still produces the existing explicit error; no response-action
  contract is silently changed.
- YAML refuses whitespace that trim would erase outside the ASCII-space
  profile, and trailing ASCII spaces on non-comment, nonempty lines. This is an
  intentionally strict subset, not a general YAML whitespace implementation.
- DNS-name syntax now requires a letter in the final label. Alternate dotted
  numeric hosts such as `0x7f.0.0.1` can no longer enter the DNS-only path.
  Explicit configuration loopback exceptions remain metadata only.
- Presence-only middleware header selection uses the conservative request-copy
  policy, rejecting hop-by-hop, credential, identity, framing and unsupported
  body metadata. This does not authenticate requests.
- Middleware evaluators reject malformed supplied header names/values and
  unknown rule kinds. Empty name plus empty value remains the existing
  no-header sentinel for trace/deny-only models.

## Verification and evidence

`tests/lexical_admission_contract.ores` covers every C0/DEL code point,
Connection token normalization, numeric DNS suffixes, YAML whitespace,
unsupported presence-only headers, forged unknown middleware and the no-header
sentinel. The native workflow compiler-checks and executes that contract.

A local, restricted JavaScript translation of selected source predicates and
static wiring checks passed 708 assertions across both repositories, including
baseline counterexamples and shared-code comparison. This is a source-derived
oracle, not Oreslang parsing, typechecking, guest execution, concurrency or
network proof. The JavaScript oracle is not an application/runtime dependency.
The local environment has no `oreslang` executable.

Latest workflow records inspected during this audit were cancelled and had
`steps=null`: forward run 40058260120 and reverse run 40058268522. These are
unexecuted jobs, not native test failures or passes. They establish neither a
billing diagnosis nor permission to copy private source elsewhere.

## Remaining acceptance gates

1. Execute every existing and new native contract at the exact candidate SHA
   on an authorized runner; record the compiler/runtime source SHA and artifact
   identity. Keep draft while compiler checking or execution remains absent.
2. Repeat relevant contracts on pinned Java/Graal and LLVM runtimes. Require
   real executed steps; source models cannot establish backend parity.
3. Reverse ingress: execute raw-wire framing/duplicate-Host/CL-TE/size-limit
   tests, the 400/403/404/501 paths, completion, disconnect and timeout cases.
   The host HTTP adapter currently reconstructs a request line, so the helper
   cannot independently establish the original protocol/framing.
4. Before any egress, implement authenticated CONNECT, runtime-minted scoped
   NET authority, all-answer DNS/CNAME/IP pinning and reserved-address denial,
   TLS identity, deadlines, byte budgets, backpressure and duplex half-close.
   DNS length limits, general port bounds and bounded config reads also remain
   separate gaps; a valid string never grants network or filesystem authority.
5. Before live reload, integrate generation pins with physical request/actor
   completion and shutdown. Pure immutable snapshots and slot receipts are
   models, not proof that active transport buffers or actors are quiescent.

Configuration `exists`/symlink/directory checks followed by `read_text` are not
a race-free regular-file open. A scoped descriptor open with no-follow rules,
regular-file verification and a pre-read byte bound remains necessary.
Dependent feature branches must take these changes and rerun their own exact
head contracts before promotion; this audit does not rebase those branches.
