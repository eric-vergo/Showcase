"""Tracked-source hygiene checks.

CX-029: two literal NUL bytes in `Tikz.lean` made an ordinary Lean module read as binary
under default Git text diff/stat and binary-aware line search. They were the delimiter of
a memoization cache key and are now written with the textual `\\x00` Lean escape (which
compiles to the same NUL bytes, so the runtime cache key is byte-identical). This guard
keeps raw NUL bytes out of tracked Lean/text sources so the regression cannot recur.
"""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parents[2]

# Extensions whose tracked files must stay plain text (no raw NUL bytes).
_TEXT_SUFFIXES = {".lean", ".py", ".mjs", ".js", ".cjs", ".css", ".yml", ".yaml", ".md", ".sh", ".json"}


def _tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(PACKAGE_ROOT), "ls-files", "-z"],
        capture_output=True,
        check=True,
    )
    return [PACKAGE_ROOT / name for name in result.stdout.decode().split("\0") if name]


class SourceHygieneTests(unittest.TestCase):
    def test_no_raw_nul_bytes_in_tracked_text_sources(self) -> None:
        offenders: list[str] = []
        for path in _tracked_files():
            if path.suffix.lower() not in _TEXT_SUFFIXES:
                continue
            if not path.exists():
                continue
            if b"\x00" in path.read_bytes():
                offenders.append(str(path.relative_to(PACKAGE_ROOT)))
        self.assertEqual(
            offenders,
            [],
            f"raw NUL byte(s) in tracked text source(s): {offenders}. Use a textual escape "
            "(e.g. Lean `\\x00`) so the file stays plain text (CX-029).",
        )

    def test_gitattributes_marks_lean_as_text(self) -> None:
        # Defense in depth: `*.lean text` keeps Git from ever treating a Lean file as binary.
        gitattributes = PACKAGE_ROOT / ".gitattributes"
        self.assertTrue(gitattributes.exists(), ".gitattributes is missing")
        text = gitattributes.read_text(encoding="utf-8")
        self.assertRegex(
            text,
            r"(?m)^\*\.lean\s+text",
            ".gitattributes must declare `*.lean text` (CX-029 defense in depth)",
        )


if __name__ == "__main__":
    unittest.main()
