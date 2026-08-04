"""Recurrence checks for the documentation-versus-implementation contract.

Two classes of drift produced the CX-006 / CX-007 audit findings, and both are
mechanically detectable:

1. **Advertised CLI flags that the binary rejects.** The start-here documents told
   readers to run `lake exe vbp build --pdf` while `VbpMain`'s exhaustive parser
   answered `unknown build option '--pdf'`. Every command-line flag a document
   mentions must be one the tools actually parse, and any `vbp build` synopsis a
   document prints must be the one `VbpMain.helpText` prints.

2. **Backticked source paths that do not exist.** The design rationale directed
   implementers at `Informal/ExternalMarkupRender.lean` and
   `PreviewManifest/Cli.lean`, modules this fork deleted relative to upstream.
   Every backticked `.lean` path in the two architecture documents must resolve
   against the tree.

Both checks read the Lean source as text rather than running Lean, so they stay
cheap enough to belong to the python harness.
"""

from __future__ import annotations

import re
from pathlib import Path
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[2]

# Documents that describe the command-line contract to a reader about to run it.
CLI_CONTRACT_DOCS = (
    Path("README.md"),
    Path("project_template") / "README.md",
    Path("doc") / "GETTING_STARTED.md",
    Path("doc") / "MAINTAINER_GUIDE.md",
    Path("skills") / "verso-blueprint" / "references" / "vbp.md",
)

# Documents that name source modules as architectural references.
SOURCE_PATH_DOCS = (
    Path("README.md"),
    Path("doc") / "DESIGN_RATIONALE.md",
)

# Roots a backticked module path may be written relative to. The design rationale
# names modules relative to the Lean source root (`Informal/Code.lean`) as well as
# from the package root (`src/VersoBlueprint/Informal/Code.lean`).
SOURCE_PATH_ROOTS = (
    Path("."),
    Path("src"),
    Path("src") / "VersoBlueprint",
)

# Lean sources whose `"--flag"` string literals are the flags the tools parse:
# `vbp` itself, and the generator that `vbp build` (or a bare `lake env lean --run`)
# invokes.
FLAG_SOURCES = (
    Path("src") / "VersoBlueprint" / "VbpMain.lean",
    Path("src") / "VersoBlueprint" / "PreviewManifest.lean",
)

# The maintainer guide also documents the python/shell maintainer harnesses, whose
# flags are theirs rather than the Lean tools'. Their `"--flag"` literals are read
# the same way, so a maintainer-facing flag that does not exist still fails.
SCRIPT_FLAG_GLOBS = ("scripts/*.py", "scripts/*.sh")

# Modules this fork deleted relative to upstream. The documentation names them —
# saying what is gone is the point of the fork-status section — so the resolvability
# check must not read those sentences as live references.
# `test_deleted_module_allowlist_is_current` fails if one of them comes back, which
# is what keeps the list from silently going stale.
DELETED_UPSTREAM_MODULES = frozenset(
    {
        "Informal/ExternalMarkupRender.lean",
        "PreviewManifest/Cli.lean",
    }
)

# Flags this fork deliberately does not implement. Documentation may name them
# *only* to record their absence — that is CX-006's resolution, one contract stated
# once — so the scan must not read those sentences as advertisements. Removing a
# name from this set is how a flag stops being mentionable at all; adding one is a
# deliberate, reviewable act. `test_start_here_docs_carry_no_pdf_instructions`
# separately pins that the absence is never phrased as an instruction.
DOCUMENTED_ABSENCES = frozenset(
    {"--pdf", "--pdf-engine", "--pdf-runs", "--external-markup-render"}
)

FLAG_RE = re.compile(r"--[A-Za-z][A-Za-z0-9-]*")
BACKTICKED_RE = re.compile(r"`([^`\n]+)`")
LEAN_STRING_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
BUILD_SYNOPSIS_RE = re.compile(r"^.*lake exe vbp build \[.*$", re.MULTILINE)


def read(path: Path) -> str:
    return (PACKAGE_ROOT / path).read_text(encoding="utf-8")


def lean_list_literals(text: str, name: str) -> list[str]:
    """The string literals of a `def <name> : List String := [ ... ]` block.

    The closing bracket is found at the start of a line, because the literals
    themselves contain `]` (`build [--output <dir>]`).
    """
    start = text.index(f"def {name} : List String := [")
    end = text.index("\n]", start)
    literals = LEAN_STRING_RE.findall(text[start:end])
    assert literals, f"no string literals recovered from {name}"
    return literals


def build_synopsis() -> str:
    """The `vbp build` usage line `VbpMain.helpText` prints."""
    main = read(FLAG_SOURCES[0])
    for line in lean_list_literals(main, "mainCommandLines"):
        if line.startswith("lake exe vbp build"):
            return line
    raise AssertionError("no `lake exe vbp build` line in mainCommandLines")


def help_text_flags() -> set[str]:
    """Flags advertised by `VbpMain.helpText`.

    `helpText` is assembled from `mainCommandLines`, `Vbp.querySelectorLines`, and
    `defaultHelpLines`; taking the flags out of those literals models it exactly
    without running Lean.
    """
    main = read(FLAG_SOURCES[0])
    vbp = read(Path("src") / "VersoBlueprint" / "Vbp.lean")
    lines = (
        lean_list_literals(main, "mainCommandLines")
        + lean_list_literals(main, "defaultHelpLines")
        + lean_list_literals(vbp, "querySelectorLines")
    )
    return {flag for line in lines for flag in FLAG_RE.findall(line)}


def parsed_flags() -> set[str]:
    """Every flag the tools actually parse, as `"--flag"` literals in their sources."""
    flags: set[str] = set()
    for source in FLAG_SOURCES:
        for literal in LEAN_STRING_RE.findall(read(source)):
            if FLAG_RE.fullmatch(literal):
                flags.add(literal)
    assert flags, "no flag literals recovered from the CLI sources"
    return flags


def script_flags() -> set[str]:
    """Flags the maintainer harnesses parse, from their own sources."""
    flags: set[str] = set()
    for glob in SCRIPT_FLAG_GLOBS:
        for path in PACKAGE_ROOT.glob(glob):
            text = path.read_text(encoding="utf-8", errors="replace")
            for match in re.findall(r"""["'](--[A-Za-z][A-Za-z0-9-]*)["']""", text):
                flags.add(match)
    assert flags, "no flag literals recovered from the maintainer scripts"
    return flags


def blocks(text: str) -> list[str]:
    """Split a Markdown document into fenced code blocks and blank-line-separated
    prose blocks, preserving order."""
    out: list[str] = []
    current: list[str] = []
    fence: str | None = None
    for line in text.splitlines():
        stripped = line.lstrip()
        if fence is None and stripped.startswith("```"):
            if current:
                out.append("\n".join(current))
                current = []
            fence = "````" if stripped.startswith("````") else "```"
            current.append(line)
        elif fence is not None:
            current.append(line)
            if stripped.startswith(fence):
                out.append("\n".join(current))
                current = []
                fence = None
        elif not line.strip():
            if current:
                out.append("\n".join(current))
                current = []
        else:
            current.append(line)
    if current:
        out.append("\n".join(current))
    return out


def advertised_flags(text: str) -> set[str]:
    """Flags a document presents as options of the Blueprint command line.

    Scoped by adjacency: a block mentioning `vbp` or `lean --run`, and the blocks
    immediately before and after it. That is how these documents are written — a
    lead-in sentence, a command fence, and a follow-up sentence about the same
    command — and it is what lets the check see a `--pdf-engine` mentioned in prose
    that never repeats the command name. One hop only; scoping does not chain down
    the document.
    """
    parts = blocks(text)
    mentions = [i for i, block in enumerate(parts) if "vbp" in block or "lean --run" in block]
    scoped: set[int] = set()
    for i in mentions:
        scoped.update({i - 1, i, i + 1})
    return {
        flag
        for i in sorted(scoped)
        if 0 <= i < len(parts)
        for flag in FLAG_RE.findall(parts[i])
    }


def looks_like_source_path(token: str) -> bool:
    token = token.strip()
    if " " in token or token.startswith("-"):
        return False
    return token.endswith(".lean") and "/" in token


def source_path_resolves(token: str) -> bool:
    return any((PACKAGE_ROOT / root / token).exists() for root in SOURCE_PATH_ROOTS)


class DocCliContractTests(unittest.TestCase):
    def test_flag_extraction_is_recoverable(self) -> None:
        # Guards the extraction itself: if the CLI sources change shape, this fails
        # loudly instead of silently reporting an empty (vacuously satisfied) set.
        self.assertEqual(
            build_synopsis(), "lake exe vbp build [--output <dir>] [--serve] [--port <n>]"
        )
        for flag in ("--output", "--serve", "--port", "--site"):
            self.assertIn(flag, help_text_flags())
        for flag in ("--output", "--serve", "--port", "--help", "--dump-manifest"):
            self.assertIn(flag, parsed_flags())
        self.assertNotIn("--pdf", parsed_flags())

    def test_docs_advertise_only_implemented_flags(self) -> None:
        supported = parsed_flags() | help_text_flags() | script_flags() | DOCUMENTED_ABSENCES
        for doc in CLI_CONTRACT_DOCS:
            unknown = sorted(advertised_flags(read(doc)) - supported)
            self.assertEqual(
                unknown,
                [],
                f"{doc} advertises command-line flag(s) no tool in this fork parses: "
                f"{unknown}. Implement them, or remove them from the document.",
            )

    def test_build_synopsis_matches_help_text(self) -> None:
        expected = build_synopsis()
        for doc in CLI_CONTRACT_DOCS:
            for line in BUILD_SYNOPSIS_RE.findall(read(doc)):
                self.assertIn(
                    expected,
                    line,
                    f"{doc} prints a `vbp build` synopsis that is not the one "
                    f"VbpMain.helpText prints ({expected!r}).",
                )

    def test_documented_vbp_build_invocations_use_only_build_options(self) -> None:
        # The sharpest form of the CX-006 check: a line that *invokes* `vbp build`
        # may carry only the options `parseBuildOptionsCore` accepts, which are
        # exactly the ones the synopsis lists. This is narrower than the corpus-wide
        # flag scan and does not depend on any allowlist, so a reintroduced
        # `lake exe vbp build --pdf` fails here whatever else the document says.
        # Full-invocation form only (`lake exe vbp build`), so prose *about* the
        # command — including the fork-status sentence naming the flags it lacks —
        # is not read as an invocation. The synopsis line itself is skipped.
        allowed = set(FLAG_RE.findall(build_synopsis()))
        for doc in CLI_CONTRACT_DOCS:
            for line in read(doc).splitlines():
                if "lake exe vbp build" not in line or "[--output" in line:
                    continue
                unknown = sorted(set(FLAG_RE.findall(line)) - allowed)
                self.assertEqual(
                    unknown,
                    [],
                    f"{doc} invokes `vbp build` with option(s) it does not accept: "
                    f"{unknown}\n  {line.strip()}",
                )

    def test_start_here_docs_carry_no_pdf_instructions(self) -> None:
        # The fork-status section is the single source for the claim; the
        # start-here documents must not carry PDF build instructions.
        for doc in (
            Path("project_template") / "README.md",
            Path("doc") / "GETTING_STARTED.md",
            Path("skills") / "verso-blueprint" / "references" / "vbp.md",
        ):
            text = read(doc)
            self.assertNotIn("vbp build --pdf", text, f"{doc} still instructs a PDF build")
            self.assertNotIn(
                "Pass `--pdf", text, f"{doc} still instructs the reader to pass a PDF flag"
            )


class DocSourcePathTests(unittest.TestCase):
    def test_source_path_check_sees_real_paths(self) -> None:
        # Guards the extraction: a path that does exist must be recognized, and the
        # two modules CX-007 caught must still read as absent.
        self.assertTrue(looks_like_source_path("Informal/Code.lean"))
        self.assertTrue(source_path_resolves("Informal/Code.lean"))
        self.assertTrue(source_path_resolves("src/VersoBlueprint/VbpMain.lean"))
        self.assertFalse(source_path_resolves("Informal/ExternalMarkupRender.lean"))
        self.assertFalse(source_path_resolves("PreviewManifest/Cli.lean"))

    def test_deleted_module_allowlist_is_current(self) -> None:
        # A module that comes back must leave the allowlist, so the documentation's
        # "deleted relative to upstream" claim cannot outlive the deletion.
        back = sorted(m for m in DELETED_UPSTREAM_MODULES if source_path_resolves(m))
        self.assertEqual(
            back,
            [],
            f"module(s) documented as deleted relative to upstream now exist: {back}. "
            "Drop them from DELETED_UPSTREAM_MODULES and update the documentation.",
        )

    def test_backticked_source_paths_resolve(self) -> None:
        for doc in SOURCE_PATH_DOCS:
            missing = sorted(
                {
                    token
                    for token in BACKTICKED_RE.findall(read(doc))
                    if looks_like_source_path(token)
                    and token not in DELETED_UPSTREAM_MODULES
                    and not source_path_resolves(token)
                }
            )
            self.assertEqual(
                missing,
                [],
                f"{doc} cites source path(s) that do not exist: {missing}. "
                "Point at the real module, or say explicitly that it was deleted "
                "relative to upstream, without backticking it as a live path.",
            )


if __name__ == "__main__":
    unittest.main()
