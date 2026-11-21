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
    # Hand-constructed negative fixtures must evolve with the nominal
    # parser type; otherwise the native suite fails before policy evaluation.
    config_schema = section(yaml, "  pub define class Config as", "  end")
    fields = config_schema.count("pub val ")
    lexical = read("tests/lexical_admission_contract.ores")
    forged = section(lexical, "  val forged = new proxy_yaml.Config(",
                     "  );\n  if middleware_policy.evaluate")
    args = forged.split("Config(", 1)[1]
    check(fields in (11, 12, 13) and args.count(",") + 1 == fields,
          "forged policy fixture has nominal Config constructor arity")
    check("new Array<proxy_yaml.Route>()" in args
          and ("new Array<proxy_yaml.Service>()" in args) == (fields >= 12)
          and ("new Array<proxy_yaml.Backend>()" in args) == (fields >= 13),
          "forged fixture carries exactly the declared collections")
    check('import module admission_text from "./admission_text";' in yaml,
          "YAML imports raw lexical guard")
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


def workflow_guards() -> None:
    wf = read(".github/workflows/native-contracts.yml")
    check("actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09" in wf
          and "actions/setup-java@b6effb05e454b25005698d916606bdc6ffcbf961" in wf,
          "native workflow dependencies pinned to reviewed commit IDs")
    check("APPROVED_ORESLANG_SHA256" in wf
          and "sha256sum" in wf and "EXPECTED_SHA" in wf,
          "native workflow requires exact source and approved runtime digest")
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
