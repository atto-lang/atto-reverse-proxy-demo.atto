# Exact-head Oreslang real-wire actor ingress acceptance

This is an *executable regression gate*, not an assertion of a successful run.
Use the native Oreslang launcher supplied by the trusted isolated
`oreslang-jdk25` GitHub Actions runner. Workflow:
`.github/workflows/actor-ingress-wire.yml`.

The job checks out the **exact PR HEAD**, verifies the source revision,
records the Oreslang compiler binary digest and JDK25, checks both Oreslang
programs, launches `src/serve_reverse.ores` in a subprocess on
`127.0.0.1:8080`, and calls `tests/actor_ingress_tcp_smoke.ores` as a
separate native Oreslang client. The client checks:
- HTTP 200 for the allowlisted statically compiled local Oreslang actor service, plus a separate streaming actor response with chunked HTTP/1.1 transfer framing, no conflicting Content-Length, both text body stages in order, and a terminal zero-length chunk
- HTTP 501 for an admitted but unimplemented outbound HTTP upstream
- HTTP 405 with an empty response body for HEAD on local actor and fallback upstream routes, before route or actor dispatch; the demo has no proven HEAD metadata/response-body suppression contract
- HTTP 400, or transport-initiated connection close, for actor GET requests declaring `Content-Length: 1` or `Transfer-Encoding: chunked`; source-level body-framing denial runs before route selection and actor dispatch
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
