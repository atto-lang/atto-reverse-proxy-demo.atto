> **AI agent instructions (organization-wide):** Before working on code, issues, or pull requests, read and follow the [organization `AGENTS.md`](https://github.com/atto-lang/.github/blob/main/AGENTS.md), including its **merge-first stealth-development policy**. Honor any repository-local `AGENTS.md`, explicit holds, and GitHub-enforced rules.

# atto-reverse-proxy-demo.atto

Reverse proxy implementation demonstrating AttoLang networking and concurrency.

## Naming migration and language authority

This repository is maintained at [atto-lang/atto-reverse-proxy-demo.atto](https://github.com/atto-lang/atto-reverse-proxy-demo.atto); use `https://github.com/atto-lang/atto-reverse-proxy-demo.atto.git` for Git remotes and canonical `.atto` source examples. The normative language contract is [atto-spec](https://github.com/atto-lang/atto-spec), with executable guest evidence tracked by [atto-platform-conformance](https://github.com/atto-lang/atto-platform-conformance). Follow current ownership, borrowing, effects, actor, and syntax rules there; do not infer implemented features from a README or unexecuted CI.

## Demonstration focus

Reverse proxy routing, forwarding, and connection lifecycle.

## Running the example

Inspect the checked-in source, project manifest, and workflows for supported compiler backends and actual run commands. Source files use the intended `.atto` extension for AttoLang; backend support must be confirmed rather than presumed.

## Expected verification

Examples should document their dependencies, expected output, negative/error cases, and exact compiler/runtime versions used to verify execution. Host-side tests do not establish AttoLang guest execution.

## Status

This README describes the demonstration's intended purpose. Current executable coverage and feature support should be verified against code and CI.

## AttoLang ecosystem

- [AttoLang](https://github.com/atto-lang)
- [Specification](https://github.com/atto-lang/atto-spec)
- [Platform conformance](https://github.com/atto-lang/atto-platform-conformance)

## Repository ownership and contribution routing

**Belongs here:** An AttoLang reverse proxy demonstration with upstream selection, request forwarding, retries and graceful upstream failover.

**Belongs elsewhere:** Outbound forward proxy demonstration in atto-forward-proxy-demo.atto, general routing in atto-http-routing and production hosting in atto-co.

**Security and portability boundary:** Authenticate ingress where needed, bound requests and retries, defend header confusion/request smuggling, isolate upstream credentials and test cancel-vs-close.

AttoLang is the canonical project name; new source, examples and documentation use `.atto` and the `atto-lang` repository organization. This README defines scope, not feature readiness.

**Acceptance:** name exact source SHA/tree, runtime/toolchain, positive and negative checks and execution receipt before claiming support. Host-only tests and empty CI steps do not prove guest execution.

## Legacy migration provenance and gates

The original `ores-truffle-oreslang/oreslang-reverse-proxy-demo.ores` repository is archived; the current AttoLang repository has a separate numeric GitHub ID. Historical `.ores` files and CLI/package names are compatibility history, not evidence of current `.atto` execution. Reverse proxy routing/security policy and isolation acceptance belong here; production load balancing/control planes and unsupported full-forwarding claims do not.

[atto-lang](https://github.com/atto-lang) owns language, portable libraries, runtime/compiler contracts and demos; [atto-co](https://github.com/atto-co) owns managed production services, tenancy, billing and deployment. Any future original-ID transfer or commercial carve-out requires separate owner approval and security review. Inventory exact SHA/tree, numeric ID, protections, permissions, PRs, releases, packages, dependencies, runners, secrets, applications, webhooks, Pages and rollback owner; verify preservation and retest references after an actual transfer. Never mirror private code without authorization. Zero-step jobs are NOT_EXECUTED; host-only checks do not establish compiled guest execution or production networking behavior.
