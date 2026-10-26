# Proxy performance evidence

This directory separates workloads that are comparable **today** from workloads that would fabricate proxy parity.

## Runnable now: HTTP ingress / actor dispatch

The manual `.github/workflows/perf-ingress.yml` lane measures three loopback HTTP/1.1 servers on the same runner:

- native Oreslang actor ingress from `src/serve_reverse.ores` on port 8080;
- nginx 1.31.8 on port 18080;
- HAProxy 3.4.7 on port 18081.

The measured endpoints have matching request semantics and status/body results:

| workload | request | expected result |
| --- | --- | --- |
| actor-hit | `Host: worker.example.test`, `GET /actor` | 200 + `hello from native Oreslang actor service` |
| policy-deny | same Host, `GET /api` without `x-demo-token` | 403 + `Request denied` |

Before timing, the workflow also checks the admitted `/api` path returns 501 with the same body on all three implementations. A wrong status or body aborts the run, so a fast 404 or empty response cannot become benchmark evidence.

The server side is pinned to one CPU and `wrk` to a different CPU. Each workload uses three rotated-order measurement rounds, preserves raw `wrk --latency` output, and records the repository SHA, Oreslang binary hash, Java version, kernel, CPU topology, nginx image digest and HAProxy image digest.

These are **ingress-dispatch measurements**, not reverse-proxy throughput. Server-generated headers are not byte-identical and should be reported as a limitation.

## Not runnable yet: true reverse forwarding

Do not compare the current Oreslang 501 upstream placeholder with nginx or HAProxy forwarding. A publishable reverse-proxy comparison requires all candidates to traverse the same upstream hop and preserve the same status, duplicate headers, body bytes and cancellation semantics.

The future gate must cover at least:

1. 1 KiB and 64 KiB fixed responses over keep-alive;
2. 1 MiB streamed response with a slow-reader variant;
3. 201/404/503 and duplicate `Set-Cookie`;
4. concurrent 1/16/64/256/1024 requests;
5. p50/p95/p99/p99.9 latency, requests/s, bytes/s, CPU, RSS and allocation/GC data where available;
6. connection reset, timeout, cancellation and graceful drain.

Oreslang cannot enter that table until the guest runtime exposes status/header-preserving bounded outbound streaming. Host-only Java transport experiments do not satisfy the application-level gate.

## Reproduction rules

Use a dedicated idle runner. Never benchmark fork-origin code on a privileged self-hosted machine. Do not accept an arbitrary benchmark command from workflow inputs. Keep access logs disabled, run semantic preflights first, retain all raw samples, and report every candidate version and exact Git SHA.

A single noisy CI run is exploratory evidence, not a regression threshold. Add automated percentage gates only after a dedicated stable host has enough baseline samples to establish variance.
