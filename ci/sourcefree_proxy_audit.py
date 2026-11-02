#!/usr/bin/env python3
"""Source-free proxy merge audit. Not a parser, compiler or native runtime test."""
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
checks = 0


def read(name: str) -> str:
    path = ROOT / name
    if not path.is_file() or path.is_symlink():
        raise AssertionError(f"missing or symbolic-link source: {name}")
    return path.read_text(encoding="utf-8")


def check(condition: bool, label: str) -> None:
    global checks
    if not condition:
        raise AssertionError(label)
    checks += 1
    print(f"PASS source-free: {label}")


def section(text: str, start: str, end: str) -> str:
    i = text.index(start)
    j = text.index(end, i + len(start))
    return text[i:j]


def inventory() -> None:
    actual = sorted(
        p.relative_to(ROOT).as_posix()
        for directory in ("src", "tests")
        for p in (ROOT / directory).rglob("*.ores")
    )
    check(not any(p.is_symlink() for directory in ("src", "tests")
                  for p in (ROOT / directory).rglob("*")),
          "all Oreslang source paths are regular, not symbolic links")
    for path in actual:
        check(bool(re.fullmatch(r"(src|tests)/[A-Za-z0-9_./-]+\.ores", path)),
              f"canonical path {path}")
    file_list = read("ci/oreslang-files.txt").splitlines()
    check(file_list == actual, "complete sorted source and test inventory")
    pure = sorted(p for p in actual if re.fullmatch(r"tests/[^/]+_contract\.ores", p))
    check(read("ci/pure-contracts.txt").splitlines() == pure,
          "complete sorted standalone contract inventory")
    check("tests/lexical_admission_contract.ores" in pure,
          "foundational lexical negative contract retained")
    check("tests/network_admission_contract.ores" in pure,
          "generation/route pre-dial contract retained")
    check("tests/actor_ingress_tcp_smoke.ores" not in pure
          and "tests/ingress_tcp_smoke.ores" not in pure,
          "TCP integrations are not mislabelled standalone pure tests")


def source_guards() -> None:
    controls = read("src/admission_text.ores")
    expected = [f"\\u{x:04x}" for x in range(32)] + ["\\u007f"]
    check(all(token in controls for token in expected),
          "all 32 C0 controls and DEL rejected by shared predicate")
    yaml = read("src/proxy_yaml.ores")
    check('import module admission_text from "./admission_text";' in yaml,
          "YAML imports raw lexical guard")
    # Schema evolution must update handwritten malformed-policy fixtures.
    config_schema = section(yaml, "  pub define class Config as", "  end")
    config_fields = config_schema.count("pub val ")
    lexical = read("tests/lexical_admission_contract.ores")
    forged = section(lexical, "  val forged = new proxy_yaml.Config(",
                     "  );\n  if middleware_policy.evaluate")
    forged_args = forged.split("Config(", 1)[1]
    check(config_fields == 13 and forged_args.count(",") + 1 == config_fields,
          "forged lexical Config fixture retains full nominal constructor arity")
    check("new Array<proxy_yaml.Route>()" in forged_args
          and "new Array<proxy_yaml.Service>()" in forged_args
          and "new Array<proxy_yaml.Backend>()" in forged_args,
          "forged lexical Config fixture preserves all three collection fields")
    check('import module header_policy from "./header_policy";' in yaml,
          "YAML imports conservative header policy")
    loop = section(yaml, "    for (const original of lines) {",
                   "      if original.starts_with(\"  - \")")
    check(loop.index("!admission_text.control_free(original)") <
          loop.index('if line == "" || line.starts_with("#")'),
          "control characters rejected before YAML comments or empty lines")
    check("without_spaces.trim() != without_spaces" in loop,
          "non-ASCII YAML whitespace cannot vanish during trim")
    check('if original.ends_with(" "); then' in loop,
          "non-comment trailing YAML spaces fail closed")
    domain = section(yaml, "  pub fnc valid_domain", "  // Narrow, lower-case HTTP")
    check("final_label_has_letter = letters != \"\"" in domain
          and "labels >= 2 && final_label_has_letter" in domain,
          "DNS final label must include a letter")
    middleware = section(yaml, "  fnc validate_middleware", "  // Exact duplicates")
    check('!header_policy.request_copy(header, "", "")' in middleware,
          "required headers cannot use sensitive or hop-by-hop fields")
    check('elif section == "services"; then' in yaml
          and 'valid_service_ref(route.upstream)' in yaml,
          "actor-service configuration support preserved")
    bindings = read("src/service_bindings.ores")
    check('if binding.network_capable; then' in bindings
          and 'network-capable actor image forbidden on public ingress route' in bindings,
          "public actor ingress rejects trusted-but-network-capable code images")
    check("pub fnc local_dispatch_allowed" in bindings
          and "binding.epoch == snapshot.epoch" in bindings
          and 'binding.target == expected_target' in bindings,
          "actor dispatch binding is generation and exact-target fenced")
    serving = read("src/serve_reverse.ores")
    check("service_bindings.local_dispatch_allowed" in serving
          and 'if request.method != "GET"; then' in serving
          and "Stale or overprivileged actor binding" in serving,
          "canonical GET-only HttpExchange handoff rechecks actor dispatch fence")
    # HEAD must be rejected before *all* route types, not merely local
    # service:// routes. The fallback 501 actor would otherwise emit a body.
    request_extract = serving.index('val request = admitted.unwrap();')
    method_gate = serving.index('if request.method != "GET"; then')
    route_select = serving.index('val matched = route_policy.select')
    fallback = serving.index('unavailable.dispatch(rt borrow mut exchange);')
    check(request_extract < method_gate < route_select < fallback
          and 'await exchange.respond(405, "text/plain; charset=utf-8", "");' in
          serving[method_gate:route_select],
          "GET-only method gate precedes all routes and actor dispatch")
    actor_wire = read("tests/actor_ingress_tcp_smoke.ores")
    check('HEAD /actor HTTP/1.1' in actor_wire
          and 'HEAD /stream HTTP/1.1' in actor_wire
          and 'starts_with("HTTP/1.1 405")' in actor_wire,
          "wire acceptance retains HEAD refusal before actor dispatch")
    # Header-level denial is defense in depth, not proof of raw HTTP parsing
    # or duplicate-header handling by the underlying transport adapter.
    guard_start = serving.index('if exchange.header("Content-Length") != "" ||')
    guard_end = serving.index('    fi', guard_start)
    body_guard = serving[guard_start:guard_end]
    check('exchange.header("Transfer-Encoding") != ""' in body_guard
          and 'await exchange.respond(400' in body_guard
          and guard_end < serving.index('val matched = route_policy.select'),
          "declared request-body denial precedes route and actor dispatch")
    check(all(token in actor_wire for token in
              ("Content-Length: 1\\r\\n", "Transfer-Encoding: chunked\\r\\n",
               "FAIL body-framed actor request admitted (Content-Length)",
               "FAIL body-framed actor request admitted (Transfer-Encoding)")),
          "real-wire fixtures reject length-delimited and chunked request bodies")
    check('HEAD /api HTTP/1.1\\r\\nHost: worker.example.test' in actor_wire
          and 'FAIL HEAD reached fallback upstream actor' in actor_wire,
          "HEAD to non-service fallback is rejected before actor handoff")
    # The raw transport must reject duplicates and conflicting framing before
    # normalizing to exchange.header(); this audit merely preserves native
    # negative test vectors. It is not evidence that the runtime rejects them.
    framing_vectors = {
        "zero_length": "Content-Length zero must not dispatch actor",
        "empty_length": "Empty Content-Length must not dispatch actor",
        "duplicate_length": "Conflicting duplicate Content-Length must not dispatch actor",
        "length_and_encoding": "Content-Length plus Transfer-Encoding must not dispatch actor",
        "duplicate_host": "Duplicate Host fields must not dispatch actor",
        "mixed_case_te": "Mixed-case transfer coding must not dispatch actor",
    }
    for vector, failure in framing_vectors.items():
        check(f"val {vector} = await network.connect_async" in actor_wire
              and f"FAIL {failure}" in actor_wire,
              f"native raw framing vector retained: {vector}")
    check('FAIL actor service unavailable after framing denial' in actor_wire
          and 'val post_framing = await network.connect_async' in actor_wire,
          "native recovery request after malformed framing retained")
    check(all(token in actor_wire for token in
              ("Content-Length: 0\\r\\n", "Content-Length:\\r\\n",
               "Content-Length: 1\\r\\nContent-Length: 0\\r\\n",
               "Content-Length: 1\\r\\nTransfer-Encoding: chunked\\r\\n",
               "Host: worker.example.test\\r\\nHost: second.example.test\\r\\n",
               "tRaNsFeR-EnCoDiNg: chunked\\r\\n")),
          "malformed wire request bytes preserve framing ambiguity vectors")
    headers = read("src/header_policy.ores")
    check('!admission_text.control_free' not in headers
          and "return admission_text.control_free(value)" in headers,
          "header values use complete control-byte filter")
    check("for (const original of connection_tokens.split_literal" in headers
          and "Only ASCII SP" in headers and "return !matched" in headers,
          "Connection nomination checks entire token list")
    admission = read("src/network_admission.ores")
    guard = section(admission, "    val route = selected.unwrap();",
                    "    return Ok(new ReversePermit")
    check('if route.middleware != ""; then' in guard and
          'return Err("middleware admission receipt required before upstream egress");' in guard,
          "middleware-bearing route cannot mint a pre-dial descriptor")
    check(guard.index('if route.middleware != ""; then') <
          guard.index('if route.upstream != endpoint.origin'),
          "middleware pre-dial denial precedes endpoint permit")
    check("network.connect" not in admission and "http.request" not in admission,
          "pure network admission module does not mint sockets")
    services = read("src/service_bindings.ores")
    service_route = section(services, "  pub fnc reverse_route(", "\n  }\nend")
    check('if route.middleware != ""; then' in service_route and
          "middleware receipt required before reverse service planning" in service_route and
          service_route.index('if route.middleware != ""; then') <
          service_route.index("valid_service_ref(route.upstream)"),
          "middleware-gated actor service planning fails closed")
    # Example service:// routes must not advertise a middleware receipt that
    # reverse_route cannot mint. Even trace-only middleware fails closed.
    # This is fixture consistency, NOT native actor-dispatch evidence.
    example = read("config/worker-example.yaml")
    check(example.count("\nroutes:\n") == 1,
          "worker example has one routes section")
    route_entries = example.split("\nroutes:\n", 1)[1].split("  - name: ")
    example_routes = {}
    for entry in route_entries[1:]:
        lines = entry.split("\n", 1)
        name = lines[0].strip()
        check(bool(name) and name not in example_routes,
              f"unique worker example route: {name}")
        example_routes[name] = lines[1] if len(lines) > 1 else ""
    for route, upstream in (
            ("workers", "service://greeting"),
            ("streaming-route", "service://streaming"),
            ("unregistered-route", "service://unavailable")):
        body = example_routes.get(route, "")
        check(f"    upstream: {upstream}\n" in body
              and "    middleware:" not in body,
              f"worker local service {route} has no unproven middleware receipt")
    origin = example_routes.get("origin", "")
    check("    upstream: http://127.0.0.1:9000\n" in origin
          and "    middleware: required\n" in origin
          and "  - name: required\n    kind: require_header\n" in example,
          "worker HTTP origin retains required-header denial fixture")
    check("  - name: trace\n" not in example,
          "worker example does not declare unused trace middleware")
    actor_tests = read("tests/service_bindings_contract.ores")
    check(all(token in actor_tests for token in
          ("gated_documents.add(gated_deny)", "kind: require_header",
           "kind: trace", "FAIL middleware-gated service route escaped admission")),
          "deny, required-header and trace actor-routing denial vectors retained")
    tests = read("tests/network_admission_contract.ores")
    check(all(token in tests for token in
              ("middleware: denied", "kind: require_header",
               "middleware: token", '"/deny/request"',
               '"/required/request"', "FAIL route middleware was bypassed")),
          "negative deny and required-header pre-dial regressions retained")


    pools = read("src/backend_pools.ores")
    check('define module backend_pools as' in pools and
          'load_balancer.choose' in pools and 'valid_upstream_origin' in pools,
          "backend selection remains a validated per-generation plan")
    check("network.connect" not in pools and "http.request" not in pools,
          "backend selection cannot grant transport or socket authority")
    check("pub val int epoch;" in pools
          and "pub fnc current(borrow Plan plan" in pools
          and "return plan.epoch == snapshot.epoch;" in pools,
          "reverse pool plans carry explicit generation identity")
    pool_contract = read("tests/backend_pools_contract.ores")
    check("FAIL stale pool plan generation fence" in pool_contract
          and "backend_pools.current(rt borrow direct_plan" in pool_contract
          and "backend_pools.current(rt borrow newer_plan" in pool_contract,
          "native pool contract rejects stale generation plans")
    check('if route.middleware != ""; then' in pools and
          'return Err("middleware receipt required before reverse pool planning");' in pools,
          "middleware-bearing reverse pools fail closed before planning")
    check("FAIL pool plan bypassed deny middleware" in read("tests/backend_pools_contract.ores")
          and "FAIL pool plan bypassed required header" in read("tests/backend_pools_contract.ores"),
          "deny and required-header pool negative fixtures retained")
    pool_tests = read("tests/backend_pools_contract.ores")
    check("weighted-round-robin" in pool_tests and
          "FAIL deterministic backend rotation" in pool_tests and
          "FAIL unknown backend pool" in pool_tests,
          "weighted pool native contract and negative cases retained")


    serving = read("src/serve_reverse.ores")
    check('http.listen("127.0.0.1", 8080, 1024, 65536, 30000)' in serving,
          "actor ingress listener remains loopback-only and bounded")
    check('new service_bindings.CodeImage(' in serving
          and '"hello-v1", "abi-v1", false' in serving
          and '"stream-v1", "abi-v1", false' in serving,
          "actor ingress only binds pre-registered code images")
    check("network.connect_async" not in serving and "http.request" not in serving,
          "reverse serving path has no guest outbound network API")
    # Attempted-dispatch receipts are checked by the native wire workflow.
    # These source checks alone cannot establish actor execution or retirement.
    first_gate = serving.index('if exchange.header("Content-Length") != "" ||')
    method_gate = serving.index('if request.method != "GET"; then')
    route_gate = serving.index('val matched = route_policy.select')
    for label, handler in (("HELLO", "hello"), ("STREAM", "stream"),
                           ("FALLBACK", "unavailable")):
        marker = f'stdio.println("ORES_PROXY_TEST_DISPATCH_{label}");'
        dispatch = f'{handler}.dispatch(rt borrow mut exchange);'
        check(serving.count(marker) == 1 and serving.count(dispatch) == 1
              and first_gate < method_gate < route_gate
              and route_gate < serving.index(marker) < serving.index(dispatch),
              f"fixed {label} receipt follows request gates and precedes dispatch")
    # The actor receipt occurs after the single-use http.claim, inside each
    # actor's receive handler, not in the calling supervisor before dispatch.
    for actor, label in (("HelloV1", "HELLO"), ("StreamV1", "STREAM"),
                         ("UpstreamUnavailable", "FALLBACK")):
        start = serving.index(f"define isoactor {actor} as")
        end = serving.index("\nend", start)
        segment = serving[start:end]
        claim = 'val exchange = http.claim(mail.value);'
        receipt = f'stdio.println("ORES_PROXY_TEST_CLAIM_{label}");'
        check(segment.count(claim) == 1 and segment.count(receipt) == 1
              and segment.index(claim) < segment.index(receipt),
              f"actor-side {label} receipt follows exchange claim")
    verifier = read("ci/verify_actor_dispatch_receipts.sh")
    synthetic_tests = read("ci/test_actor_dispatch_receipts.sh")
    check("hello != 3 || hello_claim != 3 || fallback != 1 || fallback_claim != 1" in verifier
          and "stream_claim < 1 || stream_claim > stream" in verifier
          and "all != hello + hello_claim + fallback + fallback_claim + stream + stream_claim" in verifier,
          "host verifier binds claim/dispatch receipt counts per actor")
    check("size > 1048576" in verifier
          and "grep -Ec '^ORES_PROXY_TEST_(DISPATCH|CLAIM)_'" in verifier
          and '|| -L "$log"' in verifier,
          "host verifier denies symlinked, oversized and unknown-receipt logs")
    check("SOURCE_FREE_ACTOR_CLAIM_RECEIPT_TESTS_PASS=21/21" in synthetic_tests
          and "unexpected_hello_claim" in synthetic_tests
          and "missing_fallback_claim" in synthetic_tests
          and "stream_claim_exceeds_dispatch" in synthetic_tests
          and "unknown_claim_marker" in synthetic_tests,
          "21 synthetic host-side claim and dispatch receipt tests retained")
    smoke = read("tests/actor_ingress_tcp_smoke.ores")
    check(smoke.count('network.connect_async("127.0.0.1", 8080)') >= 5
          and "FAIL unregistered actor code image must not execute" in smoke,
          "real-wire smoke is loopback-only and denies unregistered actor images")
    check('if !headers_done || !chunked || length_header; then' in smoke
          and 'FAIL streaming actor HTTP chunked headers' in smoke,
          "native streaming fixture rejects invalid framing headers")
    check('if !first_body || !second_body || !terminal_chunk; then' in smoke
          and 'line == "0" && second_body' in smoke
          and 'FAIL streaming body order or terminating chunk' in smoke,
          "native streaming fixture checks stage order and zero-chunk terminator")
    check('FAIL encoded noncanonical path not refused' in smoke
          and 'FAIL unknown route should not dispatch' in smoke
          and 'GET /%2e%2e/actor HTTP/1.1' in smoke,
          "malformed encoded target and unknown route require negative wire verdicts")
    check('for (let i = 0; i < 4; i++)' in smoke
          and 'await dropped.close_async();' in smoke
          and 'FAIL actor service did not recover after disconnected streams' in smoke,
          "bounded abandoned-stream survivability and recovery cases retained")
    check('GET /stream HTTP/1.1' in smoke
          and 'GET /actor HTTP/1.1' in smoke
          and "network.connect_async(\"127.0.0.1\", 8080)" in smoke,
          "disconnect recovery remains local loopback only")
    check(r'\\r\\n' not in smoke and r'\r\n' in smoke,
          "wire fixture contains encoded CRLF delimiters without double escaping")
    # A same-repository PR head is not a trusted runner authority. Keep both
    # legacy self-hosted workflows inert until protected-main native admission.
    legacy_native = read(".github/workflows/native-contracts.yml")
    check("if: ${{ false }}" in legacy_native,
          "PR-head native contracts cannot allocate self-hosted runner")
    check("    if: >-" not in legacy_native,
          "legacy native workflow has no alternate conditional runner path")
    wire = read(".github/workflows/actor-ingress-wire.yml")
    check("ci/test_actor_dispatch_receipts.sh ci/verify_actor_dispatch_receipts.sh" in wire
          and 'ci/verify_actor_dispatch_receipts.sh "$log"' in wire,
          "real-wire job preserves receipt verifier and synthetic test steps")
    check("actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09" in wire
          and "actions/setup-java@b6effb05e454b25005698d916606bdc6ffcbf961" in wire,
          "real-wire workflow dependencies pinned to reviewed v5 commits")
    check("if: ${{ false }}" in wire,
          "PR-head actor wire cannot allocate self-hosted runner")
    check("- 'src/**'" in wire and "- 'config/**'" in wire,
          "wire workflow covers all transitive source and configuration changes")
    wire_exec = "\n".join(
        line for line in wire.splitlines()
        if not line.lstrip().startswith("#")
    )
    check("--allow-net=127.0.0.1:8080" in wire_exec
          and "--allow-all" not in wire_exec
          and "APPROVED_ORESLANG_SHA256" in wire_exec,
          "real-wire workflow grants only loopback network and approved runtime")

def workflow_guards() -> None:
    wf = read(".github/workflows/native-contracts.yml")
    check("actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09" in wf
          and "actions/setup-java@b6effb05e454b25005698d916606bdc6ffcbf961" in wf,
          "native workflow dependencies pinned to reviewed commit IDs")
    check("APPROVED_ORESLANG_SHA256" in wf
          and "sha256sum" in wf and "EXPECTED_SHA" in wf,
          "native workflow requires exact source and approved runtime digest")
    check('timeout 15s "$wrapper" --build-info' in wf
          and 'timeout 15s "$wrapper" --version' in wf
          and 'timeout 15s "$wrapper" --help' in wf
          and 'timeout 15s "$launcher"' not in wf,
          "each native provenance probe revalidates approved launcher digest")
    check("diff -u ci/oreslang-files.txt" in wf
          and "diff -u ci/pure-contracts.txt" in wf,
          "native workflow enforces reviewed inventories")
    check("Run every reviewed standalone pure contract" in wf
          and '"$wrapper" "$file"' in wf,
          "all standalone Oreslang contracts remain required native steps")
    check("runs-on: [self-hosted, linux, x64, oreslang-jdk25]" in wf,
          "native validation cannot silently downgrade to static checks")
    check("persist-credentials: false" in wf,
          "native checkout does not persist token credentials")


if __name__ == "__main__":
    try:
        inventory()
        source_guards()
        workflow_guards()
    except (AssertionError, ValueError, OSError) as exc:
        print(f"FAIL source-free proxy audit: {exc}", file=sys.stderr)
        raise SystemExit(1)
    print(f"SOURCE_FREE_PROXY_AUDIT_PASS checks={checks}; NOT A NATIVE COMPILER PASS")
