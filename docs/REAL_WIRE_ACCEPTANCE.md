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
- HTTP 200 for the allowlisted statically compiled local Oreslang actor service and a separate streaming actor response with two actual HTTP body chunks
- HTTP 501 for an admitted but unimplemented outbound HTTP upstream
- HTTP 403 when the configured presence-check middleware fails

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

The streaming proof exercises the existing server-side `exchange.start/write/finish` guest API and a separate native Oreslang TCP client. It does not turn the Java host-only outbound HTTP proof into a guest API. The test **does not** validate remote upstream HTTP streaming, authenticating
CONNECT, content framing under malicious inputs, true GraalVM AOT, or LLVM.
These remain separate transport acceptance gates. In particular, the
package-private Java host-only proof in `oreslang-source.java` PR #1943
does not make an Oreslang guest outbound request API available.

See `docs/WORKER_PARITY.md` for future HAProxy/NGINX/workerd goals.
