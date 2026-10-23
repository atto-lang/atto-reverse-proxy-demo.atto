# Native proxy ingress and wire admission: October 22, 2026

This branch adds Oreslang-only strict request-target and upstream-origin checks, plus native contract vectors. These are **not full HTTP parsers**, not TLS implementations, and do not confer outbound network authority.

## Exact runtime status

`src/serve_reverse.ores` is an **opt-in loopback-only ingress** entrypoint, separate from the default fail-closed `src/main.ores`. It parses `ores_proxy_conf_yaml` once, refuses any listen address/port other than 127.0.0.1:8080, binds YAML route and require_header/deny/trace middleware on a stable config, and dispatches admitted requests to a lazy pool of 100 isolated Oreslang handlers. Each claimed request receives HTTP **501**, never fabricated 200 or a fabricated upstream response. Missing route → 404, denial → 403, unsupported origin form → 400. Existing Java/Graal `http.listen` remains a host-backed HTTP/1.1 transport, not a native Oreslang parser. This example does **not** forward a byte.

## Invariants for the eventual network adapter

- Preserve the transport's single-use, actor-owned HTTP exchange and exactly-once response/abort behavior.
- Validate raw request bytes, duplicate Host and framing semantics before calling `proxy_wire`; synthesized request lines in the ingress proof are *not wire validation*.
- Enforce maximum request-header bytes/count, body quotas, chunked-vs-Content-Length conflicts, no CL/TE request smuggling, no unbounded decompression and no CR/LF header injection.
- Enforce auth/rate/middleware rules before allocating outbound sockets. Set client deadlines, bounded queues, low-priority tracing and backpressure.
- Reverse proxy: status, headers, streaming body/trailers, Set-Cookie multiplicity, hop-by-hop header removal, WebSocket/upgrade and TLS verification require new portable guest capabilities. Current `http.get_text_async` only returns body, so it cannot preserve HTTP semantics and MUST NOT be used as a reverse proxy.
- Forward proxy: refuse open egress by default. Authenticate before CONNECT; pin resolved A/AAAA/CNAME results, block loopback/private/link-local/reserved/cloud-metadata and IPv4-mapped IPv6, enforce SNI/cert/port policy and DNS rebinding resistance at connect. Abort on half-close/timeout without leaking FDs. A string domain allowlist is not sufficient.
- Actor pools do not determine carrier parallelism. 100 pooled actors, 20 carriers and 1024 in-flight are *baseline settings only* pending quota-aware benchmark and runtime integration.
- Hot config reload: pin immutable snapshot and pipeline per exchange across suspension, stage actors, check readiness and health, atomically publish, drain old requests and safely retire. Code reload also needs code-image ABI/capability compatibility checks.

## Evidence required

Run `tests/wire_contract.ores` and existing tests as genuine Oreslang programs with JDK25 Java/Graal interpreter and native-image AOT/hybrid. Run same accepted/rejected vectors on LLVM after missing host HTTP/CONNECT capabilities are added. Capture exact Git tree SHA and executed steps. Then run real loopback integration checks for 400/403/404/501, pooled actor completion, cancellation, admission saturation, graceful shutdown and actor generation isolation. No execution evidence was available when this source candidate was prepared.
