#!/usr/bin/env python3
"""Fail-closed exact-tree AttoLang native qualification; synthetic tests are NOT native."""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import sys
import time
from tempfile import TemporaryDirectory

SOURCE_RE = re.compile(r"(?:src|tests)/[A-Za-z0-9_./-]+\.atto\Z")
SHA256_RE = re.compile(r"[0-9a-fA-F]{64}\Z")
TREE_RE = re.compile(r"[0-9a-fA-F]{40}\Z")
MAX_OUTPUT = 1_048_576
GIT_ENV = {"PATH": "/usr/bin:/bin", "HOME": "/nonexistent", "LC_ALL": "C",
           "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
           "GIT_ATTR_NOSYSTEM": "1", "GIT_OPTIONAL_LOCKS": "0"}


def git_bytes(root: Path, *args: str) -> bytes:
    p = subprocess.run(["/usr/bin/git", "-C", str(root), *args],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       env=GIT_ENV, timeout=15)
    return p.stdout


def git(root: Path, *args: str) -> str:
    return git_bytes(root, *args).decode("utf-8").strip()


def file_digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def assert_clean_checkout(root: Path, expected_tree: str) -> None:
    # Compare committed Git tree blobs with filesystem bytes directly. This
    # deliberately does NOT trust Git's index, assume-unchanged flags, ignored
    # paths, smudge filters or user-supplied GIT_CONFIG_* settings.
    if git(root, "rev-parse", "HEAD^{tree}") != expected_tree.lower():
        raise ValueError("HEAD Git tree differs from approved exact source tree")
    records = git_bytes(root, "ls-tree", "-rz", "--full-tree", "HEAD").split(b"\0")
    expected: set[str] = set()
    for record in records:
        if not record:
            continue
        metadata, path_bytes = record.split(b"\t", 1)
        mode, obj_type, obj_sha = metadata.decode("ascii").split(" ")
        path = path_bytes.decode("utf-8", "strict")
        if path == ".git" or path.startswith(".git/") or path.startswith("/") or ".." in Path(path).parts:
            raise ValueError("unsafe source-tree path")
        if obj_type != "blob" or mode not in ("100644", "100755") or path in expected:
            raise ValueError("nonregular or duplicate source-tree entry: " + path)
        expected.add(path)
        f = root / path
        if f.is_symlink() or not f.is_file():
            raise ValueError("missing or symlinked committed source: " + path)
        st = f.stat()
        if not stat.S_ISREG(st.st_mode) or (st.st_mode & 0o022):
            raise ValueError("nonregular or writable committed source: " + path)
        executable = bool(st.st_mode & 0o111)
        if executable != (mode == "100755"):
            raise ValueError("committed executable mode drift: " + path)
        content = f.read_bytes()
        blob = hashlib.sha1(b"blob " + str(len(content)).encode("ascii") + b"\0" + content).hexdigest()
        if blob != obj_sha:
            raise ValueError("committed blob drift: " + path)
    if not expected:
        raise ValueError("empty committed source tree")
    observed: set[str] = set()
    for directory, dirs, files in os.walk(root, topdown=True, followlinks=False):
        d = Path(directory)
        if d == root:
            dirs[:] = [name for name in dirs if name != ".git"]
        for name in dirs:
            if (d / name).is_symlink():
                raise ValueError("unapproved symlinked directory: " + str(d / name))
        for name in files:
            f = d / name
            path = f.relative_to(root).as_posix()
            if path not in expected or f.is_symlink():
                raise ValueError("untracked/ignored/aliased checkout file: " + path)
            observed.add(path)
    if observed != expected:
        raise ValueError("committed tree and filesystem file set mismatch")


def inventory(root: Path) -> tuple[list[str], list[str]]:
    discovered: list[str] = []
    for dirname in ("src", "tests"):
        folder = root / dirname
        if not folder.is_dir() or folder.is_symlink():
            raise ValueError("missing or symbolic source root: " + dirname)
        for f in folder.rglob("*"):
            if f.is_symlink() or f.name.lower().endswith(".ores"):
                raise ValueError("symbolic/legacy guest source: " + str(f))
            if f.name.lower().endswith(".atto"):
                path = f.relative_to(root).as_posix()
                if not f.is_file() or not SOURCE_RE.fullmatch(path):
                    raise ValueError("noncanonical guest source: " + path)
                discovered.append(path)
    discovered.sort()

    def manifest(name: str) -> list[str]:
        p = root / "ci" / name
        if not p.is_file() or p.is_symlink():
            raise ValueError("missing or symlinked source manifest: " + name)
        entries = p.read_text(encoding="utf-8").splitlines()
        if not entries or entries != sorted(set(entries)) or not all(SOURCE_RE.fullmatch(x) for x in entries):
            raise ValueError("invalid source manifest: " + name)
        return entries

    if discovered != manifest("oreslang-files.txt"):
        raise ValueError("source inventory does not match committed .atto files")
    pure = [x for x in discovered if re.fullmatch(r"tests/[^/]+_contract\.atto", x)]
    if not pure or pure != manifest("pure-contracts.txt"):
        raise ValueError("pure contract inventory does not match source files")
    return discovered, pure


def preflight(root: Path, launcher: Path, digest: str, tree: str) -> tuple[list[str], list[str]]:
    if not SHA256_RE.fullmatch(digest) or not TREE_RE.fullmatch(tree):
        raise ValueError("invalid approved SHA-256 or source tree SHA")
    if not launcher.is_absolute() or launcher.is_symlink() or not launcher.is_file():
        raise ValueError("native launcher must be an absolute regular non-symlink")
    if launcher == root or root in launcher.parents:
        raise ValueError("native launcher must not be controlled by the source checkout")
    mode = launcher.stat()
    if not stat.S_ISREG(mode.st_mode) or not (mode.st_mode & 0o111) or (mode.st_mode & 0o022):
        raise ValueError("native launcher must be executable and not group/world writable")
    if file_digest(launcher) != digest.lower():
        raise ValueError("native launcher SHA-256 differs from administrator-approved digest")
    assert_clean_checkout(root, tree)
    return inventory(root)


def expected_contract_marker(root: Path, path: str) -> bytes:
    if not SOURCE_RE.fullmatch(path) or not re.fullmatch(r"tests/[^/]+_contract\.atto", path):
        raise ValueError("not a canonical standalone contract path")
    code = (root / path).read_text(encoding="utf-8")
    markers = re.findall(r'stdio\.println\("(PASS [^"\r\n]{1,239})"\)', code)
    if len(markers) != 1:
        raise ValueError("contract must have exactly one literal, reviewed success marker: " + path)
    return markers[0].encode("utf-8")


def verify_contract_receipt(output: bytes, expected: bytes) -> None:
    if not expected.startswith(b"PASS ") or len(expected) > 240:
        raise ValueError("unapproved contract success marker")
    lines = [line.rstrip(b"\r") for line in output.split(b"\n")]
    passes = [line for line in lines if line.startswith(b"PASS ")]
    if passes != [expected]:
        raise ValueError("expected exactly one contract-specific PASS marker")
    if any(line.startswith(b"FAIL") for line in lines):
        raise ValueError("native contract emitted FAIL despite zero exit status")


def minimal_env(scratch: Path) -> dict[str, str]:
    env = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "LANG": "C",
           "HOME": str(scratch), "TMPDIR": str(scratch)}
    for var in ("JAVA_HOME", "GRAALVM_HOME"):
        value = os.environ.get(var)
        if value:
            p = Path(value)
            if not p.is_absolute() or not p.is_dir():
                raise ValueError("untrusted native toolchain location: " + var)
            env[var] = value
            if var == "JAVA_HOME":
                env["PATH"] = str(p / "bin") + ":" + env["PATH"]
    return env


def bounded_invoke(root: Path, launcher: Path, args: list[str], timeout: int,
                   env: dict[str, str]) -> tuple[int, bytes]:
    # Reads combined stdout/stderr with a hard 1 MiB cap. A process-group kill
    # stops child processes on output exhaustion or timeout. No inherited stdin.
    proc = subprocess.Popen([str(launcher), *args], cwd=root, env=env,
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, start_new_session=True)
    sel = selectors.DefaultSelector()
    output = bytearray()
    deadline = time.monotonic() + timeout
    try:
        assert proc.stdout is not None
        sel.register(proc.stdout, selectors.EVENT_READ)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ValueError("native invocation exceeded bounded deadline")
            for key, _ in sel.select(min(remaining, 0.25)):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    rc = proc.wait(timeout=max(0.1, deadline - time.monotonic()))
                    return rc, bytes(output)
                output.extend(chunk)
                if len(output) > MAX_OUTPUT:
                    raise ValueError("native output exceeds 1 MiB budget")
    except (Exception, KeyboardInterrupt):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=5)
        raise
    finally:
        sel.close()
        if proc.stdout is not None:
            proc.stdout.close()


def run_guest(root: Path, launcher: Path, digest: str,
              args: list[str], timeout: int, allow_failure: bool = False) -> bytes:
    if launcher.is_symlink() or file_digest(launcher) != digest.lower():
        raise ValueError("native launcher changed between executions")
    with TemporaryDirectory(prefix="atto-guest-env-") as scratch:
        env = minimal_env(Path(scratch))
        rc, output = bounded_invoke(root, launcher, args, timeout, env)
    if (rc != 0) != allow_failure:
        raise ValueError(f"native invocation had unexpected exit rc={rc} args={args!r}; "
                         f"tail={output[-1024:].decode('utf-8', 'replace')!r}")
    return output


def execute(root: Path, launcher: Path, digest: str, tree: str, timeout: int) -> None:
    sources, contracts = preflight(root, launcher, digest, tree)
    # This deliberately invalid program must be rejected before any positive
    # results; compiler failure alone is not counted as a guest test pass.
    with TemporaryDirectory(prefix="atto-negative-") as folder:
        invalid = Path(folder) / "invalid.atto"
        invalid.write_text("@@@ NOT_VALID_ATTO_SYNTAX @@@\n", encoding="utf-8")
        run_guest(root, launcher, digest, ["--check", str(invalid)], timeout, allow_failure=True)
    print("NATIVE_NEGATIVE_COMPILER_CONTROL_PASS=1/1", flush=True)

    for index, path in enumerate(sources, start=1):
        run_guest(root, launcher, digest, ["--check", path], timeout)
        print(f"NATIVE_CHECK_PASS={index}/{len(sources)} {path}", flush=True)
    for index, path in enumerate(contracts, start=1):
        expected = expected_contract_marker(root, path)
        output = run_guest(root, launcher, digest, [path], timeout)
        verify_contract_receipt(output, expected)
        print(f"NATIVE_CONTRACT_PASS={index}/{len(contracts)} {path}", flush=True)
    preflight(root, launcher, digest, tree)
    print(f"VERIFIED_NATIVE_ATTO_GUEST_PASS checks={len(sources)} contracts={len(contracts)} "
          f"tree={tree} compiler_sha256={digest.lower()}; EXECUTED", flush=True)


def self_test() -> None:
    cases = ("baseline", "wrong_sha", "wrong_tree", "bad_digest", "symlink_launcher",
             "changed_source", "unlisted_source", "legacy_source", "missing_contract",
             "untrusted_mode", "unexecutable_launcher", "untracked_manifest",
             "changed_config", "changed_workflow", "untracked_shell", "ignored_file",
             "index_poison", "nonatto_symlink", "source_launcher")
    for case in cases:
        with TemporaryDirectory(prefix="atto-native-preflight-") as base:
            folder = Path(base)
            root = folder / "repo"
            for dirname in ("src", "tests", "ci", "config", ".github/workflows"):
                (root / dirname).mkdir(parents=True, exist_ok=True)
            (root / "src/main.atto").write_text("pub routine main(): int { return 0; }\n")
            (root / "tests/basic_contract.atto").write_text(
                'pub routine main(): int { stdio.println("PASS sample"); return 0; }\n')
            (root / "ci/oreslang-files.txt").write_text("src/main.atto\ntests/basic_contract.atto\n")
            (root / "ci/pure-contracts.txt").write_text("tests/basic_contract.atto\n")
            (root / "config/example.yml").write_text("bind: loopback\n")
            (root / ".github/workflows/example.yml").write_text("name: example\n")
            (root / ".gitignore").write_text("ci/*.ignored\n")
            git(root, "init", "-q")
            git(root, "-c", "user.name=ci", "-c", "user.email=ci@example.invalid", "add", ".")
            git(root, "-c", "user.name=ci", "-c", "user.email=ci@example.invalid", "commit", "-qm", "fixture")
            launcher = folder / "approved-launcher"
            launcher.write_text("#!/bin/sh\nexit 1\n")
            launcher.chmod(0o700)
            tree = git(root, "rev-parse", "HEAD^{tree}")
            digest = file_digest(launcher)
            if case == "wrong_sha":
                digest = "0" * 64
            elif case == "wrong_tree":
                tree = "0" * 40
            elif case == "bad_digest":
                digest = "not-approval"
            elif case == "symlink_launcher":
                launcher.rename(folder / "actual-launcher")
                launcher.symlink_to("actual-launcher")
            elif case == "changed_source":
                (root / "src/main.atto").write_text("changed\n")
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
            elif case == "changed_config":
                (root / "config/example.yml").write_text("bind: public\n")
            elif case == "changed_workflow":
                (root / ".github/workflows/example.yml").write_text("name: hostile\n")
            elif case == "untracked_shell":
                (root / "ci/injected.sh").write_text("exit 0\n")
            elif case == "ignored_file":
                (root / "ci/hidden.ignored").write_text("injected\n")
            elif case == "index_poison":
                git(root, "update-index", "--assume-unchanged", "src/main.atto")
                (root / "src/main.atto").write_text("changed despite index flag\n")
            elif case == "nonatto_symlink":
                (root / "ci/alias").symlink_to("pure-contracts.txt")
            elif case == "source_launcher":
                launcher = root / "fake-native"
                launcher.write_text("#!/bin/sh\nexit 1\n")
                launcher.chmod(0o700)
                digest = file_digest(launcher)
            accepted = True
            try:
                preflight(root, launcher, digest, tree)
            except (ValueError, subprocess.CalledProcessError):
                accepted = False
            if accepted != (case == "baseline"):
                raise AssertionError("synthetic native preflight misclassified: " + case)
            print("PASS synthetic native preflight: " + case, flush=True)
    print(f"NATIVE_PREFLIGHT_SYNTHETIC_PASS={len(cases)}/{len(cases)}; NOT NATIVE COMPILER EVIDENCE")

    receipt_cases = (
        (b"PASS sample\n", b"PASS sample", True),
        (b"log\nPASS sample\r\n", b"PASS sample", True),
        (b"PASS sample\nFAIL leaked\n", b"PASS sample", False),
        (b"PASS sample\nPASS sample\n", b"PASS sample", False),
        (b"PASS something else\n", b"PASS sample", False),
        (b"PASS\n", b"PASS sample", False),
        (b"not a PASS sample\n", b"PASS sample", False),
        (b"", b"PASS sample", False),
        (b"FAIL hidden\nPASS sample\n", b"PASS sample", False),
        (b"PASS sample\r\nPASS unrelated\r\n", b"PASS sample", False),
    )
    for data, expected, should_accept in receipt_cases:
        accepted = True
        try:
            verify_contract_receipt(data, expected)
        except ValueError:
            accepted = False
        if accepted != should_accept:
            raise AssertionError("synthetic contract receipt verifier misclassified output")
    print(f"NATIVE_CONTRACT_RECEIPT_SYNTHETIC_PASS={len(receipt_cases)}/"
          f"{len(receipt_cases)}; NOT NATIVE")

    with TemporaryDirectory(prefix="atto-host-constraints-") as tmp:
        root = Path(tmp)
        launcher = root / "fake-host-program"
        launcher.write_text("#!/bin/sh\nif /usr/bin/env | /bin/grep -q '^GITHUB_TOKEN='; then echo 'ENV leaked'; else echo 'ENV unset'; fi\n")
        launcher.chmod(0o700)
        with TemporaryDirectory(prefix="atto-env-") as scratch:
            rc, output = bounded_invoke(root, launcher, [], 3, minimal_env(Path(scratch)))
        if rc != 0 or output != b"ENV unset\n":
            raise AssertionError("host test inherited credentials")
        launcher.write_text("#!/bin/sh\nwhile :; do printf '%01024d\\n' 0; done\n")
        try:
            with TemporaryDirectory(prefix="atto-env-") as scratch:
                bounded_invoke(root, launcher, [], 3, minimal_env(Path(scratch)))
        except ValueError as exc:
            if "output exceeds" not in str(exc):
                raise
        else:
            raise AssertionError("unbounded host stdout was accepted")
    print("NATIVE_PROCESS_HOST_SYNTHETIC_PASS=2/2; NOT ATTO EXECUTION")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--launcher", type=Path)
    parser.add_argument("--sha256")
    parser.add_argument("--tree")
    parser.add_argument("--timeout", type=int, default=60)
    opts = parser.parse_args()
    try:
        if opts.self_test:
            if opts.launcher or opts.sha256 or opts.tree:
                raise ValueError("synthetic tests do not authorize native execution")
            self_test()
        else:
            if not (opts.launcher and opts.sha256 and opts.tree) or not (1 <= opts.timeout <= 120):
                raise ValueError("independently approved launcher/SHA256/tree and bounded timeout required")
            execute(Path.cwd(), opts.launcher, opts.sha256, opts.tree, opts.timeout)
    except (ValueError, AssertionError, OSError, subprocess.SubprocessError, UnicodeError) as exc:
        print("FAIL exact-tree native AttoLang qualification: " + str(exc), file=sys.stderr)
        raise SystemExit(1)
