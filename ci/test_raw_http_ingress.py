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
STREAM_PAYLOAD = b"stage-one\nstage-two\n"
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

def decode_textual_chunked_body(body: bytes) -> bytes:
    """Decode only the two documented textual fixture segmentations."""
    offset = 0
    chunks: list[int] = []
    decoded = bytearray()
    while True:
        line_end = body.find(b"\r\n", offset)
        if line_end < 0:
            raise AssertionError("missing CRLF after chunk-size line")
        size_line = body[offset:line_end]
        offset = line_end + 2
        if size_line == b"0":
            if body[offset:offset + 2] != b"\r\n":
                raise AssertionError("trailers are outside this fixture contract")
            offset += 2
            if offset != len(body):
                raise AssertionError("bytes after terminal chunk")
            break
        if size_line not in (b"a", b"A", b"14"):
            raise AssertionError("unexpected chunk size or extension")
        size = int(size_line, 16)
        if offset + size + 2 > len(body):
            raise AssertionError("truncated chunk data")
        decoded.extend(body[offset:offset + size])
        offset += size
        if body[offset:offset + 2] != b"\r\n":
            raise AssertionError("missing chunk-data CRLF boundary")
        offset += 2
        chunks.append(size)
        if len(chunks) > 2:
            raise AssertionError("too many chunks")
    if tuple(chunks) not in ((20,), (10, 10)):
        raise AssertionError("unsupported chunk segmentation")
    if bytes(decoded) != STREAM_PAYLOAD:
        raise AssertionError("stream payload bytes or order mismatch")
    return bytes(decoded)


def verify_streaming_response(receipt: bytes) -> bytes:
    if status(receipt) != 200:
        raise AssertionError("expected HTTP/1.1 200 streaming response")
    head, body = receipt.split(b"\r\n\r\n", 1)
    transfer: list[bytes] = []
    content_lengths: list[bytes] = []
    for line in head.split(b"\r\n")[1:]:
        if b":" not in line:
            raise AssertionError("malformed streaming response header")
        name, value = line.split(b":", 1)
        name = name.strip().lower()
        value = value.strip().lower()
        if name == b"transfer-encoding":
            transfer.append(value)
        elif name == b"content-length":
            content_lengths.append(value)
    if transfer != [b"chunked"] or content_lengths:
        raise AssertionError("expected one chunked coding and no Content-Length")
    return decode_textual_chunked_body(body)


def streaming_self_test() -> None:
    def receipt(body: bytes, headers: bytes =
                b"Transfer-Encoding: chunked\r\nConnection: close",
                status_line: bytes = b"HTTP/1.1 200 OK") -> bytes:
        return status_line + b"\r\n" + headers + b"\r\n\r\n" + body

    valid = (
        ("coalesced", b"14\r\n" + STREAM_PAYLOAD + b"\r\n0\r\n\r\n"),
        ("two_chunks", b"a\r\nstage-one\n\r\na\r\nstage-two\n\r\n0\r\n\r\n"),
        ("uppercase_hex", b"A\r\nstage-one\n\r\nA\r\nstage-two\n\r\n0\r\n\r\n"),
    )
    invalid = (
        ("missing_size", b"stage-one\nstage-two\n0\r\n\r\n",
         b"Transfer-Encoding: chunked\r\nConnection: close", b"HTTP/1.1 200 OK"),
        ("wrong_size", b"9\r\nstage-one\n\r\n0\r\n\r\n",
         b"Transfer-Encoding: chunked\r\nConnection: close", b"HTTP/1.1 200 OK"),
        ("wrong_second_chunk_size", b"a\r\nstage-one\n\r\nbogus\r\nstage-two\n\r\n0\r\n\r\n",
         b"Transfer-Encoding: chunked\r\nConnection: close", b"HTTP/1.1 200 OK"),
        ("missing_chunk_boundary", b"14\r\n" + STREAM_PAYLOAD + b"0\r\n\r\n",
         b"Transfer-Encoding: chunked\r\nConnection: close", b"HTTP/1.1 200 OK"),
        ("truncated_data", b"14\r\nstage-one\nstage-two\r\n0\r\n\r\n",
         b"Transfer-Encoding: chunked\r\nConnection: close", b"HTTP/1.1 200 OK"),
        ("missing_terminal", b"14\r\n" + STREAM_PAYLOAD + b"\r\n",
         b"Transfer-Encoding: chunked\r\nConnection: close", b"HTTP/1.1 200 OK"),
        ("trailer", b"14\r\n" + STREAM_PAYLOAD + b"\r\n0\r\nX: y\r\n\r\n",
         b"Transfer-Encoding: chunked\r\nConnection: close", b"HTTP/1.1 200 OK"),
        ("extra_after_terminal", b"14\r\n" + STREAM_PAYLOAD + b"\r\n0\r\n\r\nextra",
         b"Transfer-Encoding: chunked\r\nConnection: close", b"HTTP/1.1 200 OK"),
        ("reordered", b"14\r\nstage-two\nstage-one\n\r\n0\r\n\r\n",
         b"Transfer-Encoding: chunked\r\nConnection: close", b"HTTP/1.1 200 OK"),
        ("wrong_headers_cl", b"14\r\n" + STREAM_PAYLOAD + b"\r\n0\r\n\r\n",
         b"Transfer-Encoding: chunked\r\nContent-Length: 20", b"HTTP/1.1 200 OK"),
        ("duplicate_te", b"14\r\n" + STREAM_PAYLOAD + b"\r\n0\r\n\r\n",
         b"Transfer-Encoding: chunked\r\nTransfer-Encoding: chunked", b"HTTP/1.1 200 OK"),
        ("non_chunked", b"14\r\n" + STREAM_PAYLOAD + b"\r\n0\r\n\r\n",
         b"Transfer-Encoding: gzip, chunked", b"HTTP/1.1 200 OK"),
        ("wrong_status", b"14\r\n" + STREAM_PAYLOAD + b"\r\n0\r\n\r\n",
         b"Transfer-Encoding: chunked", b"HTTP/1.1 201 Created"),
        ("chunk_extension", b"a;foo=bar\r\nstage-one\n\r\n0\r\n\r\n",
         b"Transfer-Encoding: chunked", b"HTTP/1.1 200 OK"),
        ("unsupported_split", b"5\r\nstage\r\nf\r\n-one\nstage-two\n\r\n0\r\n\r\n",
         b"Transfer-Encoding: chunked", b"HTTP/1.1 200 OK"),
    )
    for name, body in valid:
        if verify_streaming_response(receipt(body)) != STREAM_PAYLOAD:
            raise AssertionError(f"valid streaming response rejected: {name}")
    for name, body, headers, status_line in invalid:
        accepted = True
        try:
            verify_streaming_response(receipt(body, headers, status_line))
        except AssertionError:
            accepted = False
        if accepted:
            raise AssertionError(f"invalid streaming response accepted: {name}")
    total = len(valid) + len(invalid)
    print(f"STREAM_CHUNK_SELF_TEST_PASS={total}/{total}; SOURCE_FREE_MODEL_ONLY")


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
    streaming_self_test()
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
