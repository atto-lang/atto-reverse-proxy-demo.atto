#!/usr/bin/env python3
"""Exact-tree AttoLang guest qualification. Requires an independently approved launcher."""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from tempfile import TemporaryDirectory

SOURCE_RE = re.compile(r"(?:src|tests)/[A-Za-z0-9_./-]+\.atto\Z")
SHA256_RE = re.compile(r"[0-9a-fA-F]{64}\Z")
TREE_RE = re.compile(r"[0-9a-fA-F]{40}\Z")


def git(root: Path, *args: str) -> str:
    p = subprocess.run(["/usr/bin/git", "-C", str(root), *args],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       text=True, timeout=15)
    return p.stdout.strip()


def inventory(root: Path) -> tuple[list[str], list[str]]:
    discovered: list[str] = []
    for dirname in ("src", "tests"):
        folder = root / dirname
        if not folder.is_dir() or folder.is_symlink():
            raise ValueError(f"missing or symbolic guest source root: {dirname}")
        for f in folder.rglob("*"):
            if f.is_symlink() or f.name.lower().endswith(".ores"):
                raise ValueError(f"symlink/legacy guest source: {f}")
            if f.name.lower().endswith(".atto"):
                path = f.relative_to(root).as_posix()
                if not f.is_file() or not SOURCE_RE.fullmatch(path):
                    raise ValueError(f"noncanonical guest source: {path}")
                discovered.append(path)
    discovered.sort()
    def read_manifest(name: str) -> list[str]:
        p = root / "ci" / name
        if not p.is_file() or p.is_symlink():
            raise ValueError(f"invalid manifest: {name}")
        paths = p.read_text(encoding="utf-8").splitlines()
        if not paths or paths != sorted(set(paths)) or not all(SOURCE_RE.fullmatch(v) for v in paths):
            raise ValueError(f"unordered/duplicate/invalid manifest: {name}")
        return paths
    if discovered != read_manifest("oreslang-files.txt"):
        raise ValueError("source inventory differs from reviewed tree")
    pure = [x for x in discovered if re.fullmatch(r"tests/[^/]+_contract\.atto", x)]
    if not pure or pure != read_manifest("pure-contracts.txt"):
        raise ValueError("standalone contract inventory differs from reviewed tree")
    return discovered, pure


def preflight(root: Path, launcher: Path, digest: str, expected_tree: str) -> tuple[list[str], list[str]]:
    if not SHA256_RE.fullmatch(digest) or not TREE_RE.fullmatch(expected_tree):
        raise ValueError("invalid independently approved SHA-256 or tree SHA")
    if not launcher.is_absolute() or launcher.is_symlink() or not launcher.is_file():
        raise ValueError("approved native launcher must be an absolute regular, non-symlinked file")
    mode = launcher.stat()
    if not stat.S_ISREG(mode.st_mode) or not (mode.st_mode & stat.S_IXUSR):
        raise ValueError("approved launcher must be regular and executable")
    if mode.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        raise ValueError("approved launcher is group/world-writable")
    actual_digest = hashlib.sha256(launcher.read_bytes()).hexdigest()
    if actual_digest != digest.lower():
        raise ValueError("native launcher SHA-256 does not match independent approval")
    tree = git(root, "rev-parse", "HEAD^{tree}")
    if tree != expected_tree.lower():
        raise ValueError(f"unexpected source tree: {tree}")
    if subprocess.run(["/usr/bin/git", "-C", str(root), "diff", "--quiet", "HEAD", "--", "src", "tests", "ci"],
                      check=False, timeout=15).returncode != 0:
        raise ValueError("working guest sources or CI inputs differ from committed tree")
    if subprocess.run(["/usr/bin/git", "-C", str(root), "diff", "--cached", "--quiet"],
                      check=False, timeout=15).returncode != 0:
        raise ValueError("staged mutations invalidate source tree")
    return inventory(root)


def verify_contract_receipt(output: bytes) -> None:
    if not re.search(rb"(?m)^PASS [^\r\n]{1,240}\r?$", output):
        raise ValueError("native contract did not emit a standalone PASS marker")
    if re.search(rb"(?m)^FAIL(?:\s|$)", output):
        raise ValueError("native contract printed FAIL despite zero exit status")


def run_guest(root: Path, launcher: Path, digest: str, args: list[str], timeout: int) -> bytes:
    # A staged/mutated native executable must not be used between invocations.
    if launcher.is_symlink() or hashlib.sha256(launcher.read_bytes()).hexdigest() != digest.lower():
        raise ValueError("native executable changed since preflight")
    # Do not pass destination GitHub Actions tokens or service credentials
    # into user-authored guest code. Trusted runner provides only JVM basics.
    safe_names = ("PATH", "HOME", "LANG", "LC_ALL", "JAVA_HOME", "TMPDIR", "TZ", "GRAALVM_HOME")
    safe_env = {k: os.environ[k] for k in safe_names if k in os.environ}
    safe_env["LC_ALL"] = "C"
    try:
        result = subprocess.run([str(launcher), *args], cwd=root, env=safe_env,
                                capture_output=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired as exc:
        raise ValueError("guest compiler/runtime timeout: " + " ".join(args)) from exc
    if result.returncode != 0:
        tail = (result.stdout + result.stderr)[-2048:].decode("utf-8", "replace")
        raise ValueError(f"guest invocation failed rc={result.returncode} args={args!r}; tail={tail!r}")
    return result.stdout


def execute(root: Path, launcher: Path, digest: str, tree: str, timeout: int) -> None:
    sources, contracts = preflight(root, launcher, digest, tree)
    # Negative compiler control rejects fake launchers returning 0 for any file.
    with TemporaryDirectory(prefix="atto-negative-") as folder:
        invalid = Path(folder) / "invalid.atto"
        invalid.write_text("@@@ NOT_VALID_ATTO_SYNTAX @@@\n", encoding="utf-8")
        if hashlib.sha256(launcher.read_bytes()).hexdigest() != digest.lower():
            raise ValueError("launcher mutated before compiler negative control")
        env = {k: os.environ[k] for k in ("PATH", "HOME", "JAVA_HOME", "LANG", "TMPDIR") if k in os.environ}
        env["LC_ALL"] = "C"
        rejected = subprocess.run([str(launcher), "--check", str(invalid)],
                                  cwd=root, env=env, capture_output=True, timeout=timeout)
        if rejected.returncode == 0:
            raise ValueError("native compiler negative-control source was ACCEPTED")
    print("NATIVE_NEGATIVE_COMPILER_CONTROL_PASS=1/1", flush=True)
    for index, path in enumerate(sources, start=1):
        run_guest(root, launcher, digest, ["--check", path], timeout)
        print(f"NATIVE_CHECK_PASS={index}/{len(sources)} {path}", flush=True)
    for index, path in enumerate(contracts, start=1):
        stdout = run_guest(root, launcher, digest, [path], timeout)
        verify_contract_receipt(stdout)
        print(f"NATIVE_CONTRACT_PASS={index}/{len(contracts)} {path}", flush=True)
    # No generated or mutated reviewed sources may be laundered as guest receipts.
    preflight(root, launcher, digest, tree)
    print(f"VERIFIED_NATIVE_ATTO_GUEST_PASS checks={len(sources)} contracts={len(contracts)} "
          f"tree={tree} compiler_sha256={digest.lower()}; EXECUTED", flush=True)


def self_test() -> None:
    cases = ("baseline", "wrong_sha", "wrong_tree", "bad_digest", "symlink_launcher",
             "changed_source", "unlisted_source", "legacy_source", "missing_contract",
             "untrusted_mode", "unexecutable_launcher", "untracked_manifest")
    for case in cases:
        with TemporaryDirectory(prefix="atto-native-preflight-") as base:
            root = Path(base)
            for d in ("src", "tests", "ci"):
                (root / d).mkdir()
            (root / "src/main.atto").write_text("pub routine main(): int { return 0; }\n")
            (root / "tests/basic_contract.atto").write_text("pub routine main(): int { return 0; }\n")
            (root / "ci/oreslang-files.txt").write_text("src/main.atto\ntests/basic_contract.atto\n")
            (root / "ci/pure-contracts.txt").write_text("tests/basic_contract.atto\n")
            git(root, "init", "-q")
            git(root, "-c", "user.name=ci", "-c", "user.email=ci@example.invalid", "add", ".")
            git(root, "-c", "user.name=ci", "-c", "user.email=ci@example.invalid", "commit", "-qm", "fixture")
            launcher = root / "approved-launcher"
            launcher.write_text("#!/bin/sh\nexit 1\n")
            launcher.chmod(0o700)
            tree = git(root, "rev-parse", "HEAD^{tree}")
            digest = hashlib.sha256(launcher.read_bytes()).hexdigest()
            if case == "wrong_sha":
                digest = "0" * 64
            elif case == "wrong_tree":
                tree = "0" * 40
            elif case == "bad_digest":
                digest = "not-approval"
            elif case == "symlink_launcher":
                launcher.rename(root / "actual-launcher")
                launcher.symlink_to("actual-launcher")
            elif case == "changed_source":
                (root / "src/main.atto").write_text("changed after commit\n")
            elif case == "unlisted_source":
                (root / "src/unlisted.atto").write_text("x\n")
            elif case == "legacy_source":
                (root / "tests/legacy.ores").write_text("x\n")
            elif case == "missing_contract":
                (root / "ci/pure-contracts.txt").write_text("")
            elif case == "untrusted_mode":
                launcher.chmod(0o722)
            elif case == "unexecutable_launcher":
                launcher.chmod(0o600)
            elif case == "untracked_manifest":
                (root / "ci/oreslang-files.txt").write_text("tests/basic_contract.atto\n")
            accepted = True
            try:
                preflight(root, launcher, digest, tree)
            except (ValueError, subprocess.CalledProcessError):
                accepted = False
            if accepted != (case == "baseline"):
                raise AssertionError(f"preflight misclassified synthetic case: {case}")
            print(f"PASS synthetic native preflight: {case}", flush=True)
    print(f"NATIVE_PREFLIGHT_SYNTHETIC_PASS={len(cases)}/{len(cases)}; NOT NATIVE COMPILER EVIDENCE")
    receipts = (
        (b"PASS native contract\n", True),
        (b"log\nPASS native contract\r\n", True),
        (b"PASS native contract\nFAIL leaked\n", False),
        (b"PASS\n", False),
        (b"not a PASS contract\n", False),
        (b"", False),
    )
    for payload, expected in receipts:
        accepted = True
        try:
            verify_contract_receipt(payload)
        except ValueError:
            accepted = False
        if accepted != expected:
            raise AssertionError("synthetic success marker verifier misclassified output")
    print(f"NATIVE_CONTRACT_RECEIPT_SYNTHETIC_PASS={len(receipts)}/{len(receipts)}; NOT NATIVE")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--launcher", type=Path)
    p.add_argument("--sha256")
    p.add_argument("--tree")
    p.add_argument("--timeout", type=int, default=60)
    args = p.parse_args()
    try:
        if args.self_test:
            if args.launcher or args.sha256 or args.tree:
                raise ValueError("synthetic tests do not accept a caller-provided launcher")
            self_test()
        else:
            if not (args.launcher and args.sha256 and args.tree) or not (1 <= args.timeout <= 120):
                raise ValueError("approved --launcher, --sha256, --tree and 1..120s timeout required")
            execute(Path.cwd(), args.launcher, args.sha256, args.tree, args.timeout)
    except (ValueError, AssertionError, OSError, subprocess.SubprocessError) as exc:
        print(f"FAIL exact-tree native AttoLang qualification: {exc}", file=sys.stderr)
        raise SystemExit(1)
