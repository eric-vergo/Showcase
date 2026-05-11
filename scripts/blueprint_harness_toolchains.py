from __future__ import annotations

from dataclasses import dataclass
import re
import subprocess
from pathlib import Path

from scripts.blueprint_harness_branches import LEAN_TOOLCHAIN_PREFIX, normalize_lean_release_ref
from scripts.blueprint_harness_references import maybe_rewrite_in_repo_blueprint_dependency
from scripts.blueprint_harness_utils import lean_low_priority_command, run


VERSO_REPOSITORY_URL = "https://github.com/leanprover/verso"
OFFICIAL_VERSO_URL_PATTERNS = (
    r"https://github\.com/leanprover/verso(?:\.git)?",
    r"git@github\.com:leanprover/verso\.git",
    r"ssh://git@github\.com/leanprover/verso\.git",
)
VERSO_REQUIRE_PATTERN = re.compile(
    r'^(?P<indent>\s*)require\s+verso\s+from\s+git\s+"(?P<url>[^"]+)"(?:\s*@\s*"(?P<ref>[^"]+)")?\s*$',
    re.MULTILINE,
)


@dataclass(frozen=True)
class ToolchainBumpResult:
    lean_ref: str
    toolchain_spec: str
    verso_ref: str
    verso_tag_oid: str


def lean_toolchain_spec(lean_ref: str) -> str:
    return f"{LEAN_TOOLCHAIN_PREFIX}{lean_ref}"


def managed_toolchain_project_dirs(package_root: Path) -> tuple[Path, ...]:
    return (
        package_root,
        package_root / "project_template",
        package_root / "tests" / "test_blueprints" / "preview_runtime_showcase",
    )


def rewrite_lean_toolchain(path: Path, lean_ref: str) -> None:
    existing = path.read_text(encoding="utf-8")
    suffix = "\n" if existing.endswith("\n") else ""
    path.write_text(f"{lean_toolchain_spec(lean_ref)}{suffix}", encoding="utf-8")


def _require_official_verso_git_dependency(project_dir: Path, *, action: str) -> tuple[Path, str, re.Match[str]]:
    lakefile = project_dir / "lakefile.lean"
    if not lakefile.exists():
        raise SystemExit(f"[blueprint-harness] missing lakefile: {lakefile}")

    text = lakefile.read_text(encoding="utf-8")
    match = next(
        (
            candidate
            for candidate in VERSO_REQUIRE_PATTERN.finditer(text)
            if any(re.fullmatch(pattern, candidate.group("url")) for pattern in OFFICIAL_VERSO_URL_PATTERNS)
        ),
        None,
    )
    if match is None:
        raise SystemExit(
            "[blueprint-harness] expected the managed project to declare `verso` in `lakefile.lean` "
            "from the official `leanprover/verso` Git source; cannot "
            f"{action}."
        )
    return lakefile, text, match


def rewrite_pinned_verso_dependency(project_dir: Path, ref: str) -> tuple[Path, str | None]:
    if not ref or any(char.isspace() for char in ref) or any(char in ref for char in {'"', "\n", "\r"}):
        raise SystemExit("[blueprint-harness] expected a non-empty `verso` ref without whitespace, quotes, or newlines")

    lakefile, text, match = _require_official_verso_git_dependency(
        project_dir,
        action="rewrite the pinned `verso` ref automatically",
    )
    replacement = f'{match.group("indent")}require verso from git "{match.group("url")}"@"{ref}"'
    rewritten = text[: match.start()] + replacement + text[match.end() :]
    lakefile.write_text(rewritten, encoding="utf-8")
    return lakefile, match.group("ref")


def resolve_remote_verso_tag_oid(package_root: Path, ref: str) -> str | None:
    result = subprocess.run(
        ["git", "ls-remote", "--exit-code", "--refs", "--tags", VERSO_REPOSITORY_URL, f"refs/tags/{ref}"],
        cwd=package_root,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode == 2:
        return None
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit code {result.returncode}"
        raise SystemExit(f"[blueprint-harness] failed to query `verso` tag `{ref}`: {detail}")
    line = result.stdout.strip().splitlines()[0]
    oid = line.split()[0]
    return oid


def refresh_managed_manifest(package_root: Path, project_dir: Path) -> None:
    rewritten_lakefile, original_lakefile_text = maybe_rewrite_in_repo_blueprint_dependency(project_dir, package_root)
    try:
        run(lean_low_priority_command(package_root, "lake", "update"), cwd=project_dir)
    finally:
        if rewritten_lakefile is not None and original_lakefile_text is not None:
            rewritten_lakefile.write_text(original_lakefile_text, encoding="utf-8")


def validate_bumped_toolchain(package_root: Path) -> None:
    run(lean_low_priority_command(package_root, "lake", "build"), cwd=package_root)
    run(lean_low_priority_command(package_root, "lake", "test"), cwd=package_root)
    run(lean_low_priority_command(package_root, "lake", "build"), cwd=package_root / "project_template")
    run(
        lean_low_priority_command(package_root, "lake", "build"),
        cwd=package_root / "tests" / "test_blueprints" / "preview_runtime_showcase",
    )


def bump_toolchain_checkout(
    package_root: Path,
    requested_toolchain: str,
    *,
    verso_ref: str | None = None,
    validate: bool = True,
) -> ToolchainBumpResult:
    lean_ref = normalize_lean_release_ref(requested_toolchain)
    selected_verso_ref = normalize_lean_release_ref(verso_ref) if verso_ref is not None else lean_ref
    verso_tag_oid = resolve_remote_verso_tag_oid(package_root, selected_verso_ref)
    if verso_tag_oid is None:
        raise SystemExit(
            f"[blueprint-harness] no matching `verso` tag `{selected_verso_ref}` found in `{VERSO_REPOSITORY_URL}`. "
            "Pass `--verso-ref` explicitly if the Lean toolchain and `verso` release names differ."
        )

    for project_dir in managed_toolchain_project_dirs(package_root):
        rewrite_lean_toolchain(project_dir / "lean-toolchain", lean_ref)

    rewrite_pinned_verso_dependency(package_root, selected_verso_ref)

    for project_dir in managed_toolchain_project_dirs(package_root):
        refresh_managed_manifest(package_root, project_dir)

    if validate:
        validate_bumped_toolchain(package_root)

    return ToolchainBumpResult(
        lean_ref=lean_ref,
        toolchain_spec=lean_toolchain_spec(lean_ref),
        verso_ref=selected_verso_ref,
        verso_tag_oid=verso_tag_oid,
    )
