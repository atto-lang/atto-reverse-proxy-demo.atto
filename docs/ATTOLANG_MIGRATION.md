# AttoLang source-extension migration

This branch migrates the active reverse-proxy semantic stack from the former Oreslang public name and `.ores` guest-source extension to **AttoLang** and `.atto`.

The migration parent is exact commit `0bdad39fc4f4dd04f90b6860303f9dafa1064853` (reverse PR #11). The historical frozen release PR #13 remains untouched at its existing `.ores` SHA/tree and must not be rewritten for CI.

## Compatibility boundary

New guest source, tests and benchmark fixtures use `.atto`. User-facing documentation uses **AttoLang**.

Existing runtime/CLI compatibility identifiers such as the `oreslang` executable, `ORESLANG_*` Actions variables, repository names, and runner label `oreslang-jdk25` remain unchanged until a separately reviewed runtime-provenance migration attests their replacements. Renaming those identifiers here would manufacture runtime evidence that does not exist.

## Gate

`ci/attolang_source_policy.sh` rejects tracked or untracked legacy `.ores` files, symlinked/misplaced `.atto` files, executable-bit drift, group/world-writable files, and working-tree byte drift. Its source-free test harness exercises thirteen positive/negative cases.

This migration is source/contract policy work only. It is not native AttoLang execution evidence and does not relax the protected-main, independent-review, trusted-runner, or runtime-manifest release gates.
