# Proxy performance laboratory

Run the same bounded HTTP workload through a direct origin, NGINX, HAProxy,
and an explicitly supplied Oreslang listener. Source code remains Oreslang;
the external load generator and fixture are dependency-free Rust, with Bash/jq
orchestration. This does not enable an Oreslang socket or forwarding path.

## Current capability gates

| Workload | Oreslang demo | NGINX configuration | HAProxy configuration |
|---|---|---|---|
| Loopback HTTP admission, exact 501 body | Reverse opt-in listener; native execution required | Local 501 response | Local 501 response |
| HTTP reverse forwarding, exact origin bytes/marker | Not implemented; a 501 fails preflight | Configured | Configured |
| Authenticated CONNECT tunnel | Not implemented | Not configured; select/version a CONNECT-capable distribution separately | Not configured; TCP passthrough is not authenticated CONNECT |
| Native policy workload | 50,000 checked operations; native runtime required | Not comparable | Not comparable |

No speedup or parity claim may compare the 501 workload with a 200 upstream
round trip. The forward repository has no working forward listener. Its shared
baseline harness is infrastructure for future comparisons, not a simulated
forward-proxy result. NGINX's official CONNECT guide describes a distinct
NGINX Plus feature/configuration; do not assume stock reverse proxy settings
supply the same functionality.

## Run

Prerequisites on a dedicated Linux host: Rust 1.90.0/rustup, NGINX, HAProxy,
Bash, jq, coreutils (`timeout`, `sha256sum`), procps and optionally taskset.
The checked toolchain file is in `bench/`; the CI workflow installs dependencies
and runs only correctness smoke. No paid or external load generator is needed.

```sh
cd bench
cargo test --manifest-path driver/Cargo.toml --locked
bash test-summary.sh
bash run.sh                            # 128 requests/case, concurrency 1/8
BENCH_MODE=full bash run.sh             # 10,000/case, 5 repetitions
```

Each invocation creates a fresh private results directory and prints its path.
Services bind only loopback, on origin 9090, NGINX 9081 and HAProxy 9082. Keep
those ports free. Child processes owned by the harness are stopped on exit.
The script fails if any attempted case fails readiness, transport or response
correctness. Missing Oreslang is explicitly `NOT_EXECUTED` in baseline-only
runs; `REQUIRE_ORESLANG=1` makes missing Oreslang fail the run too.

In the reverse repository, start the existing incomplete ingress separately:

```sh
ores_proxy_conf_yaml="$(realpath bench/oreslang.yaml)" oreslang src/serve_reverse.ores
# In a second terminal, from repo root:
ORESLANG_ADDR=127.0.0.1:8080 ORESLANG_RUNTIME_SHA=<exact-runtime-source-sha> \
  ORESLANG_BACKEND=java-jit \
  REQUIRE_ORESLANG=1 bash bench/run.sh
```

Current ingress can qualify only for the 501 workload. Forwarding preflights
should fail and produce `BLOCKED_OR_INVALID` without throughput/latency values.
Do not replace the listener with an external-language stub or enable egress
just to make a benchmark pass. Record Java/Graal JIT, Native Image or LLVM,
compiler flags, artifact hashes and the source SHA of the actual serving
runtime; a user-supplied address is not an identity attestation.

Full/publishable runs require three distinct, allowed CPU IDs:

```sh
BENCH_MODE=full BENCH_PROXY_CPU=2 BENCH_LOAD_CPU=3 BENCH_ORIGIN_CPU=4 bash bench/run.sh
```

That pins one NGINX worker / one HAProxy thread, generator and fixture to
separate CPUs. If Oreslang is supplied, pin that separately started process to
the same proxy CPU and record its actual carrier/actor limits. This is a
single-core budget comparison, not the language's default multi-pool topology.
Smoke runs without explicit placement remain exploratory; full mode now
fails closed unless all three CPU IDs are provided. Provenance records CPU
quota, governor/boost state, NUMA/topology and process snapshots. For every
forward profile, the matching direct-origin median must be at least 1.20x the
proxy median. Otherwise the summary marks that proxy result `BOTTLENECKED` and
`metrics_comparable=false`; full mode fails the capacity gate. This prevents a
loopback fixture or load-generator ceiling from masquerading as proxy parity.

`BENCH_SANDBOX_SMOKE=1` permits config/wire testing in restricted UID namespaces
using NGINX's single-process mode and the invoking user. Provenance records this
mode, and the script refuses to combine it with `BENCH_MODE=full`. Those smoke
numbers are not production comparisons.

## Workload and outputs

Full runs sweep concurrency 1/16/64/256 and 0/1 KiB/64 KiB bodies, with 200
serial warm-up requests per case, five independent repetitions and alternating
baseline order. Each measured request opens a TCP connection, sends a bodyless
GET with fixed Host and `Connection: close`, reads the whole response through
EOF and checks status, exactly one Content-Length, exact body and a fresh
per-run origin nonce. The nonce is supplied only to the fixture and load
generator, not to the proxy under test, so a static synthetic marker cannot
qualify as upstream traversal. Unsupported encodings, duplicate lengths, truncation, extra bytes or
any transport error invalidate the case. Every request is checked; preflight
and warm-up are excluded from measurements.

Per-request latency is connect-to-complete-response in integer microseconds,
including connection setup, but excluding response-validation CPU. Overall
throughput includes generator/validation overhead. The generator runs closed
loop: its p99 is not an open-loop/service-SLO latency estimate and has coordinated
omission under overload. There are no retries. Per-operation timeouts, a total
response deadline, response byte cap and 180-second case watchdog bound work.
A one-million-request input cap bounds latency storage; raw individual timings
are held only to compute exact nearest-rank p50/p95/p99, then discarded.

Per-case JSON includes successful request count, errors, concurrency, warm-up,
throughput, p50/p95/p99/max, and elapsed seconds. Invalid cases have diagnostic
logs and no comparable metrics. `summary.json` groups only matching target,
profile, body size and concurrency, reporting median/min/max across repetitions.
Medians of per-run percentiles are labelled as such, never pooled percentiles.
No cross-profile ratios, automatic winners or flaky timing thresholds are used.

`provenance.txt` requires a canonical 40-lowercase-hex source SHA and captures compiler and
product versions/build options, executable/config hashes, kernel/CPU information
and optional affinity/runtime SHA. Distro package versions are recorded, not
bit-for-bit pinned; use a reviewed pinned package/image manifest for published
comparisons. Per-process RSS/current-CPU snapshots are diagnostic only; they
are not peak memory, whole-tree CPU, per-request allocation or a leak proof.
Unavailable telemetry is explicit. CI uploads raw case results, logs, provenance
and summaries, and treats the suite as a functional harness test. The Oreslang
runtime source SHA is likewise required to be canonical before native policy
timings are accepted.

## Oreslang policy workload

```sh
ORESLANG_RUNTIME_SHA=<exact-runtime-source-sha> bash bench/policy.sh
```

This checks and executes `tests/perf_policy_contract.ores` five times, requiring
its 50,000-operation checksum each time. `/usr/bin/time -v` records whole-process
elapsed/CPU/peak RSS, including startup, JIT and shutdown. These numbers compare
Oreslang runtime configurations only, not NGINX/HAProxy forwarding. The native
workflow also checks/executes this workload, without a machine-speed threshold.

## Next acceptance profiles

Before adding keep-alive, open-loop fixed-rate overload, slow readers, body
streaming, WebSockets/TLS or reload-under-load, implement and verify the matching
Oreslang transport semantics. A CONNECT profile additionally needs authenticated
admission, all-address DNS/IP pinning, scoped NET authority, nonces proving
bidirectional relay, half-close, cancellation and byte/deadline limits. Hot
reload needs per-request generation pins, completion accounting, no lost or
duplicated responses, and physical quiescence before reclamation. Publish each
capability as unimplemented until its real transport correctness gate passes.

References: [NGINX proxy module](https://nginx.org/en/docs/http/ngx_http_proxy_module.html),
[HAProxy configuration](https://docs.haproxy.org/3.2/configuration.html),
[NGINX Plus CONNECT guide](https://docs.nginx.com/nginx/admin-guide/web-server/http-connect-proxy/).
