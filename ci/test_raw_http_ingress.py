#!/usr/bin/env python3
"""Negative raw HTTP/1.1 loopback probe; only native execution proves the server."""
from __future__ import annotations

import argparse
import socket
import sys

HOST = "127.0.0.1"
MAX_RECEIPT = 65536
GOOD_BODY = b"hello from native AttoLang actor service"
TIMEOUT = 2.0
GOOD = b"GET /actor HTTP/1.1\r\nHost: worker.example.test\r\nConnection: close\r\n\r\n"

# Only literal loopback is used. An unexpected 2xx/3xx/5xx response fails all
# malformed-input cases. A prompt connection drop also counts as fail-closed.
MALFORMED = (
    ("duplicate_host", b"GET /actor HTTP/1.1\r\nHost: worker.example.test\r\nHost: attacker.example.test\r\nConnection: close\r\n\r\n"),
    ("cl_te_conflict", b"GET /actor HTTP/1.1\r\nHost: worker.example.test\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n0\r\n\r\n"),
    ("duplicate_cl", b"GET /actor HTTP/1.1\r\nHost: worker.example.test\r\nContent-Length: 0\r\nContent-Length: 4\r\nConnection: close\r\n\r\n"),
    ("mixed_case_te", b"GET /actor HTTP/1.1\r\nHost: worker.example.test\r\ntRaNsFeR-EnCoDiNg: chunked\r\nConnection: close\r\n\r\n0\r\n\r\n"),
    ("cl_zero", b"GET /actor HTTP/1.1\r\nHost: worker.example.test\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"),
    ("obs_fold", b"GET /actor HTTP/1.1\r\nHost: worker.example.test\r\n folded: suspicious\r\nConnection: close\r\n\r\n"),
    ("header_space_before_colon", b"GET /actor HTTP/1.1\r\nHost : worker.example.test\r\nConnection: close\r\n\r\n"),
    ("bare_lf", b"GET /actor HTTP/1.1\nHost: worker.example.test\nConnection: close\n\n"),
    ("nul_in_host", b"GET /actor HTTP/1.1\r\nHost: worker.example.test\x00.evil.test\r\nConnection: close\r\n\r\n"),
    ("encoded_traversal", b"GET /%2e%2e/actor HTTP/1.1\r\nHost: worker.example.test\r\nConnection: close\r\n\r\n"),
    ("dot_traversal", b"GET /actor/../actor HTTP/1.1\r\nHost: worker.example.test\r\nConnection: close\r\n\r\n"),
    ("absolute_form", b"GET http://worker.example.test/actor HTTP/1.1\r\nHost: worker.example.test\r\nConnection: close\r\n\r\n"),
    ("fragment", b"GET /actor#other HTTP/1.1\r\nHost: worker.example.test\r\nConnection: close\r\n\r\n"),
    ("http_1_0", b"GET /actor HTTP/1.0\r\nHost: worker.example.test\r\nConnection: close\r\n\r\n"),
    ("duplicate_connection", b"GET /actor HTTP/1.1\r\nHost: worker.example.test\r\nConnection: close\r\nConnection: keep-alive\r\n\r\n"),
)

def status(receipt: bytes) -> int | None:
    if not receipt:
        return None
    if b"\r\n\r\n" not in receipt:
        raise AssertionError("partial HTTP response headers must not pass")
    line = receipt.split(b"\r\n", 1)[0]
    parts = line.split(b" ", 2)
    if len(parts) < 2 or parts[0] != b"HTTP/1.1" or len(parts[1]) != 3 or not parts[1].isdigit():
        raise AssertionError(f"noncanonical HTTP response status: {line[:120]!r}")
    return int(parts[1])

def verdict(receipt: bytes, expected: int, allow_close: bool = False) -> None:
    result = status(receipt)
    if result is None:
        if allow_close:
            return
        raise AssertionError("missing successful response")
    if result != expected:
        raise AssertionError(f"expected HTTP {expected}, got HTTP {result}")
    body = receipt.split(b"\r\n\r\n", 1)[1]
    if expected == 200 and GOOD_BODY not in body:
        raise AssertionError("HTTP 200 lacked the exact AttoLang actor response body")
    if expected == 400 and GOOD_BODY in body:
        raise AssertionError("rejected request leaked an actor response body")

def exchange(port: int, payload: bytes) -> bytes:
    with socket.create_connection((HOST, port), timeout=TIMEOUT) as conn:
        conn.settimeout(TIMEOUT)
        conn.sendall(payload)
        data = bytearray()
        while len(data) < MAX_RECEIPT:
            try:
                chunk = conn.recv(4096)
            except socket.timeout as exc:
                raise AssertionError("server did not respond or close within timeout") from exc
            except ConnectionResetError:
                # Peer reset is a closed connection; a partial response still
                # fails in status(), and an empty drop is only valid on denial.
                break
            if not chunk:
                break
            data.extend(chunk)
        if len(data) >= MAX_RECEIPT:
            raise AssertionError("server exceeded response header byte budget")
        return bytes(data)

def self_test() -> None:
    cases = (
        (b"HTTP/1.1 200 OK\r\n\r\n" + GOOD_BODY, 200, False, True),
        (b"HTTP/1.1 400 Bad Request\r\n\r\n", 400, True, True),
        (b"", 400, True, True),
        (b"", 200, False, False),
        (b"HTTP/1.1 200 OK\r\n\r\n" + GOOD_BODY, 400, True, False),
        (b"HTTP/1.0 400 Bad Request\r\n\r\n", 400, True, False),
        (b"HTTP/1.1 503 Unavailable\r\n\r\n", 400, True, False),
        (b"junk\r\n\r\n", 400, True, False),
        (b"HTTP/1.1 200 OK\r\n\r\n", 200, False, False),
        (b"HTTP/1.1 200 OK\r\n\r\n" + b"some other actor", 200, False, False),
        (b"HTTP/1.1 400 Bad Request\r\n\r\n" + GOOD_BODY, 400, True, False),
        (b"HTTP/1.1 400 Bad Request\r\n", 400, True, False),
        (b"HTTP/1.1 400 Bad Request\n\n", 400, True, False),
    )
    for idx, (receipt, expected, allow_close, should_pass) in enumerate(cases):
        passed = True
        try:
            verdict(receipt, expected, allow_close)
        except AssertionError:
            passed = False
        if passed != should_pass:
            raise AssertionError(f"raw-wire probe self-test vector {idx} did not discriminate")
    print(f"WIRE_PROBE_SELF_TEST_PASS={len(cases)}/{len(cases)}; NOT NATIVE EXECUTION")

def live(port: int) -> None:
    verdict(exchange(port, GOOD), 200)
    for name, request in MALFORMED:
        verdict(exchange(port, request), 400, allow_close=True)
        print(f"PASS live raw-wire fail-closed: {name}")
    # Surviving a malformed request does not prove ownership-loan quiescence;
    # it establishes the listener can still serve a clean actor request.
    verdict(exchange(port, GOOD), 200)
    print(f"RAW_WIRE_LOOPBACK_PASS={len(MALFORMED)}/"
          f"{len(MALFORMED)} malformed plus 2 clean actor responses")

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    if args.self_test:
        self_test()
    else:
        if args.port != 8080:
            parser.error("this guarded proof only permits loopback TCP 8080")
        live(args.port)
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError) as exc:
        print(f"FAIL raw-wire probe: {exc}", file=sys.stderr)
        raise SystemExit(1)
