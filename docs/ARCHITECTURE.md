# Control/data plane and v1 admissions

Status: native Oreslang source **control-plane candidate**. NOT a working HTTP forward/reverse proxy, tunnel, production-safe YAML parser, live reloader, or release.

## Configuration contract

Read the configuration **only** from the `ores_proxy_conf_yaml` environment variable. `flags-2-env` reads `.cli-flags.toml` and exports this variable from `--config-yaml`; the deployed Oreslang entrypoint reads `env.get("ores_proxy_conf_yaml")`.

This project deliberately supports a tightly constrained *YAML subset*: LF line endings, unquoted scalars, two-space mapping fields, named sequence entries with two/four-space indentation, one property per line, no inline comments, no YAML anchors, tags, aliases, multiline scalars or flow-style collections. Unrecognized and duplicate keys fail validation. Cap file size and resolve the path by race-safe descriptor-based I/O before this parser can accept hostile filesystem input. The demo's `fs.is_symlink` and `fs.read_text` checks are NOT race-free.

The profile temporarily requires `carriers: 20`, `actors: 100`, `max_inflight: 1024`. This validates intent; **it does not set a carrier pool or start HTTP actors**. Tune active carrier count to CPUs/cgroups under benchmark, rather than assuming 20 OS threads are optimal.

## Proposed runtime

- One supervisor owns listeners, config generations, and telemetry, with *single-writer* publication.
- Keep immutable versioned route/policy snapshots. Compile middleware references into a route pipeline table. A request is pinned to one generation for its entire lifetime, including streaming completion. No half-old/half-new chain.
- Stage new actors and route snapshot; readiness and health checks must pass *before* atomic admission-pointer swap. New requests use the new generation; old actors drain, bounded by graceful deadline, and are retired after final response. Roll back on any failed stage.
- For code-image updates, do **not** assume in-process class code hot swapping is implemented. Changing actor behavior may require a new runtime/code image or rolling process upgrade; replacing actor instances only works when the new code is already loaded and version-compatible.
- Use 100 reusable actors as an initial **per-handler pool hypothesis**, not 100 actors globally in addition to unlimited connection actors. Oreslang's existing `http.handler("X").pooled(100)` is Java/Graal-specific and serializes turns per actor; application data-plane integration is not yet written. Bound admission separately (e.g., 1024 requests), queue depth, outbound concurrency and TCP connection counts. Cancellation of a pooled worker must not silently strand another in-flight request.
- Assign transport I/O to nonblocking readiness loops when portable `std/net` exists; actor carriers should never block on DNS, socket I/O or YAML reload parsing. The current Java runtime uses virtual-thread offload, and the native LLVM network primitives are not yet at parity.

## Middleware execution

Policies may run in a pre-route global stage (connection/request limits, header normalization, TLS metadata), after route selection (auth, rate limits, rewrites, telemetry), or inside a route's actor (business/request-specific checks). A middleware version is part of a published snapshot; load it before dispatch. Actors may have their own immutable middleware logic but never share cross-actor mutable hooks or retain HttpExchange capabilities past completion.

Pipeline phases: `on_accept → pre_route → route → route_middleware → actor → response_middleware → on_complete`. Denial must stop dispatch. A request retry requires idempotence and bounded replayable bodies. No retry after response headers commit. Trace/logging must be nonblocking and redact credentials.

The included `src/middleware_policy.ores` helper only computes a **single-header, pure decision**. It is not wired into a live exchange and is not yet sufficient for header-level authentication.

## reverse proxy release gates

Reverse mode needs: streaming upstream HTTP client with response status/headers/trailers, safe hop-by-hop filtering, Host/prefix rewrites, strict inbound framing, TLS upstream verification, retries with idempotence controls, circuit breaking, pooling and health checks. Current `http.get_text_async` only returns a response body, so it cannot be used as a correct HTTP reverse-proxy adapter.

Before announcing support, pass exact-source compilation on Java/Graal and LLVM, config malformed-input/fuzz tests, request smuggling, header injection, slowloris, slow reader/writer, body limits, connection exhaustion, TLS and DNS rebinding checks, cancellation/drain/reload races, and real HTTP wire tests. A failed workflow before job steps is runner evidence, NOT a compiler failure. No cross-org private-source transfer without authorization.

## CLI

Invoke canonical `flags2env shell-env --config .cli-flags.toml -- ores-proxy --config-yaml PATH` from a *trusted* launch environment. Its output is intended for the invoking process environment; do not blindly eval untrusted output. Then launch the Oreslang `src/main.ores` with narrowly scoped read permissions for the admitted config path. The entrypoint exits with 78 after a valid file to make **unavailable data plane** unmistakable. Config check returning 0 must not be interpreted as a serving-proxy health check.

## Inspiration

NGINX separates master configuration/lifecycle from workers and drains old workers on reload. HAProxy's Runtime API can make some route/server changes without reload, while changes requiring a new worker use graceful drain. Neither guarantees that arbitrary new program code is live in an existing worker image.


## Native policy hardening and transport dependency (October 22, 2026)

The pure Oreslang control-plane now admits only canonical HTTP(S) upstream **origin** syntax for reverse routes: scheme, host, optional decimal port; no credentials, URL paths, fragments, encoded authorities or ambiguous IPv6 bracket forms in v1. The current IP and port helpers are syntax admission, **not** full RFC IP/port verification or an outbound connection authorization. Transport must still verify each resolved address, TLS peer, connection destination and numeric port range.

Reverse routes use **most-specific boundary-safe path-prefix selection** regardless of YAML order. Raw request paths, Host and scheme must be strictly canonicalized before this pure helper; it does not defend against malformed wire framing by itself.

Declarative middleware `require_header` now admits only a narrow lowercase ASCII header-name subset. Its pure nonempty-header predicate is **not authentication** and must not protect public ingress without a real identity/authentication adapter.

Forward `configured_connect` requires an explicit `CONNECT` method, one unambiguous `host:443` authority, syntactically valid lowercase DNS name and configured domain allowlist. It is **not** permission to dial: the transport must check pinned DNS/IP addresses and forbid unsafe networks (including rebinding, link-local, metadata-service and other private endpoints) before opening or reusing a socket.

**Blocking runtime dependency:** [Oreslang Java outbound proxy transport issue #1942](https://github.com/ores-truffle-oreslang/oreslang-source.java/issues/1942) specifies the missing status/header-preserving streaming client, bounded CONNECT duplex transport, cancellation/close semantics and real wire evidence. Current `http.get_text_async` is body-only and must not be used as a transparent proxy implementation.

All new security and route-selection regressions live in native `tests/yaml_policy_contract.ores`. A workflow `queued` status, static source inspection or successful config parsing is not a compiler/test pass and does not make either demo a serving proxy.
