#!/usr/bin/env python3
"""Post-adversarial native actor handoff receipts; synthetic self-tests are not guest evidence."""
from __future__ import annotations

import sys
from pathlib import Path
from tempfile import TemporaryDirectory

PREFIX = "ORES_PROXY_TEST_"
FIELDS = (
    "DISPATCH_HELLO", "CLAIM_HELLO",
    "DISPATCH_STREAM", "CLAIM_STREAM",
    "DISPATCH_FALLBACK", "CLAIM_FALLBACK",
)
MAX_LOG_BYTES = 1048576


def validate_text(content: str) -> None:
    counts = {field: 0 for field in FIELDS}
    for line in content.splitlines():
        if not line.startswith(PREFIX):
            continue
        key = line[len(PREFIX):]
        if key not in counts:
            raise AssertionError("unexpected actor test receipt marker")
        counts[key] += 1
        if key.startswith("CLAIM_") and (
            counts[key] > counts["DISPATCH_" + key.removeprefix("CLAIM_")]
        ):
            raise AssertionError("actor claim logged before supervisor dispatch")
    if counts["DISPATCH_HELLO"] != 5 or counts["CLAIM_HELLO"] != 5:
        raise AssertionError("malformed raw requests caused unexpected actor hello dispatch")
    if counts["DISPATCH_FALLBACK"] != 1 or counts["CLAIM_FALLBACK"] != 1:
        raise AssertionError("malformed raw requests reached fallback actor")
    if not (1 <= counts["DISPATCH_STREAM"] <= 5):
        raise AssertionError("unexpected stream dispatch count")
    if not (1 <= counts["CLAIM_STREAM"] <= counts["DISPATCH_STREAM"]):
        raise AssertionError("stream actor claim count outside bounded range")


def validate_log(path: Path) -> None:
    if not path.is_file() or path.is_symlink():
        raise AssertionError("missing, nonregular or symlinked actor log")
    if path.stat().st_size > MAX_LOG_BYTES:
        raise AssertionError("actor log exceeds 1MiB")
    validate_text(path.read_text(encoding="utf-8"))


def fixture() -> str:
    lines = []
    for _ in range(3):
        lines += [PREFIX + "DISPATCH_HELLO", PREFIX + "CLAIM_HELLO"]
    lines += [PREFIX + "DISPATCH_STREAM", PREFIX + "CLAIM_STREAM"]
    lines += [PREFIX + "DISPATCH_FALLBACK", PREFIX + "CLAIM_FALLBACK"]
    for _ in range(2):
        lines += [PREFIX + "DISPATCH_HELLO", PREFIX + "CLAIM_HELLO"]
    return "\n".join(lines) + "\n"


def self_test() -> None:
    base = fixture()
    cases = (
        ("baseline", base, True),
        ("extra_dispatch", base + PREFIX + "DISPATCH_HELLO\n", False),
        ("extra_claim", base + PREFIX + "CLAIM_HELLO\n", False),
        ("extra_fallback", base + PREFIX + "DISPATCH_FALLBACK\n", False),
        ("extra_stream", base + 5 * (PREFIX + "DISPATCH_STREAM\n"), False),
        ("missing_hello", base.replace(PREFIX + "CLAIM_HELLO\n", "", 1), False),
        ("missing_fallback", base.replace(PREFIX + "CLAIM_FALLBACK\n", "", 1), False),
        ("unknown_marker", base + PREFIX + "CLAIM_ADMIN\n", False),
        ("claim_first", PREFIX + "CLAIM_HELLO\n" + base, False),
        ("empty", "", False),
    )
    for name, data, expected in cases:
        passed = True
        try:
            validate_text(data)
        except AssertionError:
            passed = False
        if passed != expected:
            raise AssertionError(f"post-probe synthetic control misclassified {name}")
        print(f"PASS post-probe receipt control: {name}")
    with TemporaryDirectory(prefix="atto-post-probe-") as tmp:
        target = Path(tmp) / "log"
        target.write_text(base)
        validate_log(target)
        target.unlink()
        target.symlink_to("/dev/null")
        try:
            validate_log(target)
        except AssertionError:
            pass
        else:
            raise AssertionError("symlink actor log should be denied")
    print(f"POST_PROBE_RECEIPT_SELF_TEST_PASS={len(cases) + 2}/{len(cases) + 2}; NOT NATIVE")


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["--self-test"]:
            self_test()
        elif len(sys.argv) == 2 and sys.argv[1] != "--self-test":
            validate_log(Path(sys.argv[1]))
            print("POST_RAW_WIRE_ACTOR_DISPATCH_RECEIPTS_PASS; native run required")
        else:
            raise AssertionError("usage: verify_raw_probe_receipts.py [--self-test | logfile]")
    except (AssertionError, UnicodeError, OSError) as exc:
        print(f"FAIL post-probe actor receipts: {exc}", file=sys.stderr)
        raise SystemExit(1)
