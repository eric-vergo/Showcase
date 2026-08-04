from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path
import shutil
import sys

from scripts.blueprint_harness_utils import StepFailure, run_capturing_failure
from scripts.check_off_origin_assets import scan_tree


UV_CACHE_DIR = "/tmp/verso-blueprint-uv-cache"


def off_origin_failure(label: str, site_dir: Path) -> StepFailure | None:
    """Fail if the generated site references any off-origin asset (CX-013).

    Uses the format-aware scanner rather than a substring gate, so it enumerates every
    URL-bearing HTML attribute, CSS construct, and JS network sink. A self-contained
    blueprint site must load nothing from another origin.
    """
    if not site_dir.exists():
        return None
    hits = scan_tree(site_dir)
    if not hits:
        return None
    detail = "\n".join(f"  {hit}" for hit in hits[:50])
    more = "" if len(hits) <= 50 else f"\n  … and {len(hits) - 50} more"
    return StepFailure(
        f"{label} off-origin assets",
        f"{len(hits)} off-origin asset reference(s) in {site_dir}:\n{detail}{more}",
    )


@dataclass(frozen=True)
class SiteValidationCheck:
    label: str
    site_dir: Path
    panel_regression_script: str | None
    browser_tests_path: str | None


def resolve_package_relative_path(package_root: Path, path_text: str) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        return path
    return package_root / path


def panel_regression_command(package_root: Path, script_path: str, site_dir: Path) -> list[str]:
    return [
        sys.executable,
        str(resolve_package_relative_path(package_root, script_path)),
        "--site-dir",
        str(site_dir),
    ]


def browser_test_command(
    package_root: Path,
    tests_path_text: str,
    site_dir: Path,
    pytest_args: Sequence[str],
) -> list[str]:
    tests_path = resolve_package_relative_path(package_root, tests_path_text)
    if shutil.which("uv") is not None:
        command = [
            "env",
            f"UV_CACHE_DIR={UV_CACHE_DIR}",
            "uv",
            "run",
            "--project",
            str(tests_path),
            "--extra",
            "test",
            "python",
            "-m",
            "pytest",
        ]
    else:
        command = [sys.executable, "-m", "pytest"]
    return [
        *command,
        str(tests_path),
        "-q",
        "--browser",
        "chromium",
        "--site-dir",
        str(site_dir),
        *pytest_args,
    ]


def run_site_validation_checks(
    package_root: Path,
    checks: Iterable[SiteValidationCheck],
    pytest_args: Sequence[str],
    *,
    skip_panel_regression: bool = False,
    skip_browser_tests: bool = False,
    stop_on_first_failure: bool = False,
) -> list[StepFailure]:
    failures: list[StepFailure] = []
    for check in checks:
        # Off-origin gate: unconditional, format-aware, and dependency-free (CX-013).
        off_origin = off_origin_failure(check.label, check.site_dir)
        if off_origin is not None:
            failures.append(off_origin)
            if stop_on_first_failure:
                return failures

        if check.panel_regression_script is not None and not skip_panel_regression:
            failure = run_capturing_failure(
                f"{check.label} panel regression",
                panel_regression_command(package_root, check.panel_regression_script, check.site_dir),
                cwd=package_root,
            )
            if failure is not None:
                failures.append(failure)
                if stop_on_first_failure:
                    return failures

        if check.browser_tests_path is not None and not skip_browser_tests:
            failure = run_capturing_failure(
                f"{check.label} browser tests",
                browser_test_command(package_root, check.browser_tests_path, check.site_dir, pytest_args),
                cwd=package_root,
            )
            if failure is not None:
                failures.append(failure)
                if stop_on_first_failure:
                    return failures
    return failures
