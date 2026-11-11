#!/usr/bin/env python3
"""Fail-closed source inventory check; never claim native AttoLang execution."""
from __future__ import annotations
import re
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

PATH_RE = re.compile(r"(?:src|tests)/[A-Za-z0-9_./-]+\.atto\Z")


def validate(root: Path) -> tuple[int, int]:
    actual: list[str] = []
    for name in ("src", "tests"):
        folder = root / name
        if not folder.is_dir() or folder.is_symlink():
            raise ValueError(f"missing or symlinked source root: {name}")
        for path in folder.rglob("*"):
            if path.is_symlink():
                raise ValueError(f"source symlink forbidden: {path}")
            lower = path.name.lower()
            if lower.endswith(".ores"):
                raise ValueError(f"legacy source forbidden: {path}")
            if lower.endswith(".atto"):
                relative = path.relative_to(root).as_posix()
                if not path.is_file() or not PATH_RE.fullmatch(relative):
                    raise ValueError(f"noncanonical AttoLang source: {relative}")
                actual.append(relative)
    actual.sort()

    def manifest(name: str) -> list[str]:
        path = root / "ci" / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"missing or symlinked manifest: {name}")
        lines = path.read_text(encoding="utf-8").splitlines()
        if not lines or lines != sorted(set(lines)) or not all(PATH_RE.fullmatch(p) for p in lines):
            raise ValueError(f"noncanonical inventory: {name}")
        return lines

    files = manifest("oreslang-files.txt")  # historical CI filename; contents must use .atto
    pure = manifest("pure-contracts.txt")
    contracts = [p for p in actual if re.fullmatch(r"tests/[^/]+_contract\.atto", p)]
    if files != actual:
        raise ValueError("source inventory does not match live .atto files")
    if pure != contracts:
        raise ValueError("standalone contract inventory does not match .atto tests")
    return len(actual), len(contracts)


def self_test() -> None:
    cases = ("baseline", "stale_source", "stale_contract", "missing_source",
             "missing_contract", "duplicate_source", "unknown_source",
             "wrong_case", "legacy_source", "symlink_source", "non_contract")
    for case in cases:
        with TemporaryDirectory(prefix="atto-inventory-") as tmp:
            root = Path(tmp)
            for directory in ("src", "tests", "ci"):
                (root / directory).mkdir()
            (root / "src/main.atto").write_text("pub routine main(): int { return 0; }\n")
            (root / "tests/basic_contract.atto").write_text("pub routine main(): int { return 0; }\n")
            (root / "ci/oreslang-files.txt").write_text("src/main.atto\ntests/basic_contract.atto\n")
            (root / "ci/pure-contracts.txt").write_text("tests/basic_contract.atto\n")
            if case == "stale_source":
                (root / "ci/oreslang-files.txt").write_text("src/main.ores\ntests/basic_contract.atto\n")
            elif case == "stale_contract":
                (root / "ci/pure-contracts.txt").write_text("tests/basic_contract.ores\n")
            elif case == "missing_source":
                (root / "ci/oreslang-files.txt").write_text("tests/basic_contract.atto\n")
            elif case == "missing_contract":
                (root / "ci/pure-contracts.txt").write_text("src/main.atto\n")
            elif case == "duplicate_source":
                (root / "ci/oreslang-files.txt").write_text("src/main.atto\nsrc/main.atto\ntests/basic_contract.atto\n")
            elif case == "unknown_source":
                (root / "src/unknown.atto").write_text("pub routine x(): int { return 0; }\n")
            elif case == "wrong_case":
                (root / "src/unexpected.ATTO").write_text("x\n")
            elif case == "legacy_source":
                (root / "src/legacy.ores").write_text("x\n")
            elif case == "symlink_source":
                (root / "src/link.atto").symlink_to("main.atto")
            elif case == "non_contract":
                (root / "tests/new_contract.atto").write_text("pub routine x(): int { return 0; }\n")
            accepted = True
            try:
                validate(root)
            except ValueError:
                accepted = False
            if accepted != (case == "baseline"):
                raise AssertionError(f"inventory mutation control failed: {case}")
            print(f"PASS inventory control: {case}")
    print(f"ATTO_INVENTORY_MUTATIONS_PASS={len(cases)}/{len(cases)}")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    elif not sys.argv[1:]:
        src, pure = validate(Path(__file__).resolve().parent.parent)
        print(f"ATTO_SOURCE_INVENTORY_PASS files={src} pure_contracts={pure}; NOT NATIVE EXECUTION")
    else:
        raise SystemExit("usage: check_atto_inventory.py [--self-test]")
