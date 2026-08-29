"""Static repository-topology contract tests for tracked GitHub workflows and wrappers.

Two recurrence checks introduced with the CITOPO audit batch:

* CX-040 — every ``workflow_run.workflows`` entry a tracked workflow listens for must
  resolve to the ``name:`` of a tracked workflow in the same repository root. A stale
  listener name silently disables an automatic build-to-deploy route while CI stays
  green (the ``Reference Blueprints`` vs ``Reference Showcases`` mismatch).

* CX-039 — every repository script or executable invoked by a *root-context* workflow
  (i.e. one that runs against this checkout, not a reusable ``workflow_call`` workflow
  dispatched into a consumer's tree) or by a ``scripts/*.sh`` wrapper must exist as a
  tracked path. A wrapper invoking an absent checker aborts the whole job under
  ``set -euo pipefail`` (the removed ``tests/integration/check_lean_run_external_markup.py``).

  A reusable workflow's *consumer-side* paths cannot be resolved here, which is why the
  root-context check skips those files — but its ``ci/`` paths can be, because they are
  OURS: ``ci/`` is the subtree a reusable workflow materialises on the runner by checking
  this repository out at ``job.workflow_sha``. A reference to a script that moved is the
  same silent-abort failure, in a job that has already been dispatched into somebody
  else's repository, so it gets its own check below.

Both checks parse the YAML textually rather than importing PyYAML: the harness has no
third-party dependencies and the CI ``harness-tests`` job runs under the runner's bare
``python3``. The constructs inspected here (a top-level ``name:``, a ``workflow_run``
``workflows:`` list, and shell ``run:`` invocations) are simple enough to read directly.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parents[2]

# Repository roots that carry their own `.github/workflows/`. Script paths in a
# workflow resolve relative to the root that contains it (the project template is a
# self-contained consumer checkout with its own `scripts/`).
WORKFLOW_ROOTS = (
    PACKAGE_ROOT,
    PACKAGE_ROOT / "project_template",
)

# Reference targets provided by a *consumer's* checkout of the shared harness tooling,
# never by this repository. Root-context path resolution must ignore them.
CONSUMER_PROVIDED_PREFIXES = ("tools/verso-harness/",)

# How a reusable workflow names a script in this repository's `ci/` subtree. The
# workflows stage that subtree outside the consumer's workspace and address it through
# `$CI_DIR`; the literal `ci/scripts/...` spelling appears in prose and is checked too.
_CI_SCRIPT_PATTERNS = (
    re.compile(r"\$CI_DIR/(scripts/[A-Za-z0-9_][A-Za-z0-9_./-]*)"),
    re.compile(r"(?<![\w./$-])(?:ci/)(scripts/[A-Za-z0-9_][A-Za-z0-9_./-]*\.(?:py|sh))"),
)


def _iter_workflow_files(root: Path) -> list[Path]:
    workflows_dir = root / ".github" / "workflows"
    if not workflows_dir.is_dir():
        return []
    return sorted(p for p in workflows_dir.glob("*.yml") if p.is_file())


def _workflow_name(text: str) -> str | None:
    for line in text.splitlines():
        match = re.match(r"name:\s*(.+?)\s*$", line)
        if match:
            return match.group(1).strip().strip("'\"")
    return None


def _is_reusable_workflow(text: str) -> bool:
    """A workflow triggered (also) by ``workflow_call`` is dispatched into an arbitrary
    consumer checkout, so its repository-relative script paths cannot be resolved here."""
    return re.search(r"^\s*workflow_call\s*:", text, re.MULTILINE) is not None


def _workflow_run_listeners(text: str) -> list[str]:
    """Extract the ``on.workflow_run.workflows`` list entries, if any."""
    lines = text.splitlines()
    listeners: list[str] = []
    in_workflow_run = False
    in_workflows_list = False
    workflows_indent = 0
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if re.match(r"workflow_run\s*:", stripped):
            in_workflow_run = True
            in_workflows_list = False
            continue
        if in_workflow_run and re.match(r"workflows\s*:", stripped):
            in_workflows_list = True
            workflows_indent = indent
            continue
        if in_workflows_list:
            item = re.match(r"-\s*(.+?)\s*$", stripped)
            if item and indent > workflows_indent:
                listeners.append(item.group(1).strip().strip("'\""))
                continue
            # A sibling/dedented key ends the workflows list (and possibly the block).
            in_workflows_list = False
            if indent <= workflows_indent:
                in_workflow_run = False
    return listeners


# Repository-relative script references. Each pattern's capture group (or whole match)
# is a path relative to the referencing file's repository root.
_SCRIPT_PATTERNS = (
    # `python3 -m scripts.foo.bar` -> scripts/foo/bar.py
    (re.compile(r"python3\s+-m\s+(scripts(?:\.[A-Za-z0-9_]+)+)"), "module"),
    # `./scripts/foo.py`, `scripts/foo.sh`, `python3 tests/foo.py`, `bash scripts/foo.sh`
    (re.compile(r"(?<![\w./-])\.?/?((?:scripts|tests)/[A-Za-z0-9_][A-Za-z0-9_./-]*\.(?:py|sh|mjs))"), "path"),
    # extensionless helper executables that live in scripts/ (e.g. `./scripts/lean-low-priority`)
    (re.compile(r"(?<![\w./-])\./(scripts/[A-Za-z0-9_][A-Za-z0-9_-]*)(?![\w./-])"), "path"),
)


def _strip_comment(line: str) -> str:
    stripped = line.lstrip()
    if stripped.startswith("#"):
        return ""
    return line


def _referenced_repo_paths(text: str) -> set[str]:
    refs: set[str] = set()
    for raw in text.splitlines():
        line = _strip_comment(raw)
        if not line:
            continue
        for pattern, kind in _SCRIPT_PATTERNS:
            for match in pattern.finditer(line):
                token = match.group(1)
                if any(token.startswith(prefix) for prefix in CONSUMER_PROVIDED_PREFIXES):
                    continue
                if kind == "module":
                    rel = token.replace(".", "/") + ".py"
                else:
                    rel = token
                if any(rel.startswith(prefix) for prefix in CONSUMER_PROVIDED_PREFIXES):
                    continue
                refs.add(rel)
    return refs


class WorkflowRunTopologyTests(unittest.TestCase):
    def test_every_workflow_run_listener_resolves_to_a_tracked_workflow(self) -> None:
        checked = 0
        for root in WORKFLOW_ROOTS:
            files = _iter_workflow_files(root)
            names = {
                name
                for f in files
                if (name := _workflow_name(f.read_text(encoding="utf-8"))) is not None
            }
            for f in files:
                for listener in _workflow_run_listeners(f.read_text(encoding="utf-8")):
                    checked += 1
                    self.assertIn(
                        listener,
                        names,
                        msg=(
                            f"{f.relative_to(PACKAGE_ROOT)} listens for workflow_run "
                            f"`{listener}`, which no tracked workflow in {root.name} declares. "
                            f"Known names: {sorted(names)}"
                        ),
                    )
        # Guard the guard: the reference-deploy listener must actually be exercised.
        self.assertGreaterEqual(checked, 1, "no workflow_run listeners were checked")


class WorkflowScriptPathTests(unittest.TestCase):
    def _assert_paths_exist(self, root: Path, referencing: Path, text: str) -> None:
        for rel in sorted(_referenced_repo_paths(text)):
            target = root / rel
            self.assertTrue(
                target.exists(),
                msg=(
                    f"{referencing.relative_to(PACKAGE_ROOT)} invokes `{rel}`, which does "
                    f"not exist under {root.name}. Remove the stale invocation or restore "
                    f"the target (see CX-039)."
                ),
            )

    def test_root_context_workflows_reference_only_existing_scripts(self) -> None:
        for root in WORKFLOW_ROOTS:
            for f in _iter_workflow_files(root):
                text = f.read_text(encoding="utf-8")
                if _is_reusable_workflow(text):
                    # Reusable (`workflow_call`) workflows run in a consumer checkout.
                    continue
                self._assert_paths_exist(root, f, text)

    def test_reusable_workflows_reference_only_existing_ci_scripts(self) -> None:
        """CX-039 for the ``workflow_call`` half the check above deliberately skips."""
        checked = 0
        reusable = 0
        for root in WORKFLOW_ROOTS:
            ci_root = root / "ci"
            for f in _iter_workflow_files(root):
                text = f.read_text(encoding="utf-8")
                if not _is_reusable_workflow(text):
                    continue
                reusable += 1
                for pattern in _CI_SCRIPT_PATTERNS:
                    for match in pattern.finditer(text):
                        rel = match.group(1)
                        checked += 1
                        self.assertTrue(
                            (ci_root / rel).exists(),
                            msg=(
                                f"{f.relative_to(PACKAGE_ROOT)} invokes `ci/{rel}`, which does "
                                f"not exist under {root.name}. A reusable workflow runs in a "
                                f"consumer's repository, so this aborts a job that has already "
                                f"been dispatched there (see CX-039)."
                            ),
                        )
        if reusable:
            self.assertGreaterEqual(
                checked, 1,
                "a reusable workflow is tracked but references no ci/ script; either the "
                "workflows stopped using the shared scripts or the patterns above moved",
            )

    def test_shell_wrappers_reference_only_existing_scripts(self) -> None:
        wrappers = sorted((PACKAGE_ROOT / "scripts").glob("*.sh"))
        self.assertGreaterEqual(len(wrappers), 1, "no shell wrappers found under scripts/")
        for wrapper in wrappers:
            self._assert_paths_exist(PACKAGE_ROOT, wrapper, wrapper.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
