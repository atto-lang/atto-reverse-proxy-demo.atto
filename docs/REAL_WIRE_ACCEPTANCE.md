# Exact-head AttoLang real-wire actor ingress acceptance

This is an *executable regression gate*, not an assertion of a successful run.
Use the native AttoLang launcher supplied by the trusted isolated
`oreslang-jdk25` GitHub Actions runner. Workflow:
`.github/workflows/actor-ingress-wire.yml`.

The job checks out the **exact PR HEAD**, verifies the source revision,
records the AttoLang compiler binary digest and JDK25, checks both AttoLang
programs, launches `src/serve_reverse.atto` in a subprocess on
`127.0.0.1:8080`, and calls `tests/actor_ingress_tcp_smoke.atto` as a
separate native AttoLang client. The client checks:
- HTTP 200 for the allowlisted statically compiled local AttoLang actor service, plus a separate streaming actor response with chunked HTTP/1.1 framing: either one coalesced 0x14 (20-byte) chunk or two stage-aligned 0x0a (10-byte) chunks, exact ordered payload, each chunk boundary, a zero-length terminal chunk, an empty trailer section, and EOF with no trailing bytes; Content-Length is forbidden
- HTTP 501 for an admitted but unimplemented outbound HTTP upstream
- HTTP 405 with an empty response body for HEAD on local actor and fallback upstream routes, before route or actor dispatch; the demo has no proven HEAD metadata/response-body suppression contract
- Raw-framing negative vectors (zero/empty Content-Length, conflicting duplicate Content-Length, Content-Length plus Transfer-Encoding, duplicate Host, mixed-case Transfer-Encoding) require HTTP 400 or a transport-initiated close, **never** local actor dispatch; a subsequent clean GET must still receive HTTP 200. The guest's scalar `exchange.header()` cannot itself validate duplicate raw fields, so these remain transport-level acceptance requirements until native execution proves them
- HTTP 400, or transport-initiated connection close, for actor GET requests declaring `Content-Length: 1` or `Transfer-Encoding: chunked`; source-level body-framing denial runs before route selection and actor dispatch
- HTTP 403 when the configured presence-check middleware fails
- HTTP 400 for a percent-encoded noncanonical traversal target and HTTP 404 for an unconfigured route, each tested through a separate loopback TCP connection
- Four clients that send a complete streaming request and immediately close their TCP connections, followed by a fresh local actor-service request that must still return HTTP 200

The trusted-native wire workflow is prepared to check fixed
`ORES_PROXY_TEST_DISPATCH_*` markers immediately before supervisor
handoff and separate `ORES_PROXY_TEST_CLAIM_*` markers emitted inside each
actor's receive handler **after** `http.claim`. Exactly three Hello
dispatches and three Hello claims, plus one fallback dispatch and one fallback
claim, are required. Streaming dispatches may range from one to five; at
least one stream must be claimed, and claims cannot exceed dispatches because
four abandoned streaming clients can cancel before actor claim. Unknown
receipt markers, extra/missing claims, symlinked logs, and logs over 1 MiB
are rejected by a source-free verifier with **24 synthetic test cases**.
The verifier also rejects an actor claim appearing before its corresponding
supervisor dispatch in the observed log, even if final counts match. This is
a log-order invariant, not a unique-request or cancellation proof.

**Markers prove the code reached the point after claim if the native job
actually runs and produces the receipts. They do not prove task retirement,
response teardown, quiescence, or physical resource reclamation. No native
guest execution has yet been verified.**

The disconnect sequence is **listener survivability evidence only** if it executes: it cannot prove that the abandoned stream's task was cancelled at a specific linearization point or that a receiver/state loan was physically retired. Those claims require actor-local continuation accounting, an observable quiescence barrier, scheduler/task-retirement instrumentation, and explicit bounded-retirement tests; none is present in this fixture.


The server receives `ores_proxy_conf_yaml` containing the canonical
absolute `config/worker-example.yaml` path; the runner only grants its
single configuration file as filesystem read authority, one named env variable
and loopback TCP port 8080. There is no `--allow-all` or remote outbound
network grant. All application and test code is native AttoLang; minimal Bash
is GitHub Actions process orchestration only, not a deployed proxy script.

Source uses the documented `handler.dispatch(rt borrow mut exchange)`
single-owner exchange handoff. The bounded readiness loop and EXIT cleanup
ensure the test fails explicitly instead of silently passing when the server
never starts. If runner admission is queued, **no program has executed**.

The native wire client explicitly separates headers from body and validates the chunk-size lines and CRLF boundaries for the two supported adapter shapes: one coalesced 0x14 (20-byte) chunk, or two stage-aligned 0x0a (10-byte) chunks. It requires the exact `stage-one\nstage-two\n` payload, a zero-length terminal chunk, an empty trailer section and EOF with no trailing bytes. The source-free Python model executes positive and malformed synthetic vectors for those same shapes; it is **not** a live AttoLang result. The native client remains line-oriented and is **not** a general binary-safe RFC 9112 chunk parser: arbitrary chunk segmentation, trailers and chunk extensions are intentionally outside this narrow fixture contract.

The streaming proof exercises the existing server-side `exchange.start/write/finish` guest API and a separate native AttoLang TCP client. It does not turn the Java host-only outbound HTTP proof into a guest API. The test **does not** validate remote upstream HTTP streaming, authenticating
CONNECT, content framing under malicious inputs, true GraalVM AOT, or LLVM.
These remain separate transport acceptance gates. In particular, the
package-private Java host-only proof in `oreslang-source.java` PR #1943
does not make an AttoLang guest outbound request API available.

See `docs/WORKER_PARITY.md` for future HAProxy/NGINX/workerd goals.
