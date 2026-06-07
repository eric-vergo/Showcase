from __future__ import annotations

import json
from dataclasses import dataclass
import re
import subprocess
from pathlib import Path


BRANCH_POLICY_FILENAME = "branch-policy.json"
LEAN_TOOLCHAIN_PREFIX = "leanprover/lean4:"
ROOT_WORKTREE_NAME = "root"
CHECKOUT_ROLE_DEFAULT_DEV = "default_dev"
CHECKOUT_ROLE_BACKPORT = "backport"
CHECKOUT_ROLE_CHOICES = (CHECKOUT_ROLE_DEFAULT_DEV, CHECKOUT_ROLE_BACKPORT)
NUMERIC_LEAN_RELEASE_PATTERN = re.compile(r"^v?\d+\.\d+\.\d+$")
LEAN_RELEASE_CANDIDATE_PATTERN = re.compile(
    r"^v?(?P<major>\d+)\.(?P<minor>\d+)(?:\.(?P<patch>\d+))?-rc(?P<rc>\d+)$"
)


@dataclass(frozen=True)
class BranchPolicy:
    version: int
    default_dev_branch: str
    required_backport_branches: tuple[str, ...]
    source_path: Path


def clean_lean_ref(raw_ref: str) -> str:
    ref = raw_ref.strip()
    if ref.startswith(LEAN_TOOLCHAIN_PREFIX):
        ref = ref[len(LEAN_TOOLCHAIN_PREFIX) :]
    if not ref or any(char.isspace() for char in ref) or any(char in ref for char in {'"', "\n", "\r"}):
        raise SystemExit("[blueprint-harness] expected a Lean release ref without whitespace, quotes, or newlines")
    return ref


def normalize_release_candidate_name(raw_ref: str) -> str:
    ref = clean_lean_ref(raw_ref)
    match = LEAN_RELEASE_CANDIDATE_PATTERN.fullmatch(ref)
    if match is None:
        raise SystemExit("[blueprint-harness] expected an official Lean release candidate name like `4.30-rc2`")

    major = match.group("major")
    minor = match.group("minor")
    patch = match.group("patch")
    rc = match.group("rc")
    if patch is None or patch == "0":
        return f"{major}.{minor}-rc{rc}"
    return f"{major}.{minor}.{patch}-rc{rc}"


def release_candidate_name_or_none(raw_ref: str) -> str | None:
    ref = clean_lean_ref(raw_ref)
    if LEAN_RELEASE_CANDIDATE_PATTERN.fullmatch(ref) is None:
        return None
    return normalize_release_candidate_name(ref)


def release_candidate_ref(raw_ref: str) -> str:
    name = normalize_release_candidate_name(raw_ref)
    match = LEAN_RELEASE_CANDIDATE_PATTERN.fullmatch(name)
    if match is None:
        raise AssertionError(f"normalized release candidate did not parse: {name}")

    patch = match.group("patch") or "0"
    return f"v{match.group('major')}.{match.group('minor')}.{patch}-rc{match.group('rc')}"


def normalize_lean_release_ref(raw_ref: str) -> str:
    ref = clean_lean_ref(raw_ref)
    if LEAN_RELEASE_CANDIDATE_PATTERN.fullmatch(ref) is not None:
        return release_candidate_ref(ref)
    if NUMERIC_LEAN_RELEASE_PATTERN.fullmatch(ref) is not None and not ref.startswith("v"):
        ref = f"v{ref}"
    return ref


def release_branch_from_lean_ref(raw_ref: str) -> str:
    ref = normalize_lean_release_ref(raw_ref)
    match = LEAN_RELEASE_CANDIDATE_PATTERN.fullmatch(ref)
    if match is not None:
        patch = match.group("patch") or "0"
        return f"v{match.group('major')}.{match.group('minor')}.{patch}"
    return ref


def lean_release_order_key(raw_ref: str) -> tuple[int, int, int, int] | None:
    ref = normalize_lean_release_ref(raw_ref)
    if NUMERIC_LEAN_RELEASE_PATTERN.fullmatch(ref) is not None:
        version = ref[1:] if ref.startswith("v") else ref
        major, minor, patch = (int(part) for part in version.split("."))
        return major, minor, patch, 1_000_000

    match = LEAN_RELEASE_CANDIDATE_PATTERN.fullmatch(ref)
    if match is None:
        return None

    patch = int(match.group("patch") or "0")
    return int(match.group("major")), int(match.group("minor")), patch, int(match.group("rc"))


def lean_toolchain_spec(lean_ref: str) -> str:
    return f"{LEAN_TOOLCHAIN_PREFIX}{lean_ref}"


def rewrite_lean_toolchain(path: Path, lean_ref: str) -> None:
    existing = path.read_text(encoding="utf-8")
    suffix = "\n" if existing.endswith("\n") else ""
    path.write_text(f"{lean_toolchain_spec(lean_ref)}{suffix}", encoding="utf-8")


def active_release_branch(repo_root: Path) -> str:
    toolchain_path = repo_root / "lean-toolchain"
    if not toolchain_path.exists():
        raise SystemExit(f"[blueprint-harness] missing lean toolchain file: {toolchain_path}")
    return release_branch_from_lean_ref(toolchain_path.read_text(encoding="utf-8"))


def branch_policy_path(checkout_root: Path) -> Path:
    return checkout_root / BRANCH_POLICY_FILENAME


def format_branch_policy(
    *,
    default_dev_branch: str,
    required_backport_branches: tuple[str, ...] | list[str],
    version: int = 1,
) -> str:
    backports = ", ".join(f'"{release_branch_from_lean_ref(branch)}"' for branch in required_backport_branches)
    return (
        "{\n"
        f'  "version": {version},\n'
        f'  "default_dev_branch": "{release_branch_from_lean_ref(default_dev_branch)}",\n'
        f'  "required_backport_branches": [{backports}]\n'
        "}\n"
    )


def write_branch_policy(
    checkout_root: Path,
    *,
    default_dev_branch: str,
    required_backport_branches: tuple[str, ...] | list[str],
    version: int = 1,
) -> BranchPolicy:
    path = branch_policy_path(checkout_root)
    text = format_branch_policy(
        default_dev_branch=default_dev_branch,
        required_backport_branches=required_backport_branches,
        version=version,
    )
    path.write_text(text, encoding="utf-8")
    return load_branch_policy(checkout_root)


def load_branch_policy(checkout_root: Path) -> BranchPolicy:
    path = branch_policy_path(checkout_root)
    if not path.exists():
        return BranchPolicy(
            version=1,
            default_dev_branch=active_release_branch(checkout_root),
            required_backport_branches=(),
            source_path=path,
        )

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        raise SystemExit(f"[blueprint-harness] invalid branch policy file `{path}`: {err}") from err

    if not isinstance(data, dict):
        raise SystemExit(f"[blueprint-harness] invalid branch policy file `{path}`: expected a JSON object")

    raw_default = data.get("default_dev_branch")
    if not isinstance(raw_default, str):
        raise SystemExit(f"[blueprint-harness] invalid branch policy file `{path}`: missing string `default_dev_branch`")

    raw_backports = data.get("required_backport_branches", [])
    if not isinstance(raw_backports, list) or not all(isinstance(item, str) for item in raw_backports):
        raise SystemExit(
            f"[blueprint-harness] invalid branch policy file `{path}`: "
            "`required_backport_branches` must be a list of strings"
        )

    raw_version = data.get("version", 1)
    if not isinstance(raw_version, int):
        raise SystemExit(f"[blueprint-harness] invalid branch policy file `{path}`: `version` must be an integer")

    return BranchPolicy(
        version=raw_version,
        default_dev_branch=release_branch_from_lean_ref(raw_default),
        required_backport_branches=tuple(release_branch_from_lean_ref(item) for item in raw_backports),
        source_path=path,
    )


def default_dev_branch(checkout_root: Path) -> str:
    return load_branch_policy(checkout_root).default_dev_branch


def checkout_branch_role(checkout_root: Path) -> str:
    return (
        CHECKOUT_ROLE_DEFAULT_DEV
        if active_release_branch(checkout_root) == default_dev_branch(checkout_root)
        else CHECKOUT_ROLE_BACKPORT
    )


def checkout_is_backport_only(checkout_root: Path) -> bool:
    return checkout_branch_role(checkout_root) == CHECKOUT_ROLE_BACKPORT


def require_checkout_role(checkout_root: Path, *, required_role: str, operation: str) -> None:
    if required_role not in CHECKOUT_ROLE_CHOICES:
        known = ", ".join(CHECKOUT_ROLE_CHOICES)
        raise SystemExit(f"[blueprint-harness] unknown checkout role `{required_role}`; known roles: {known}")

    actual_role = checkout_branch_role(checkout_root)
    if actual_role == required_role:
        return

    active_branch = active_release_branch(checkout_root)
    default_branch = default_dev_branch(checkout_root)
    if required_role == CHECKOUT_ROLE_DEFAULT_DEV:
        raise SystemExit(
            f"[blueprint-harness] refusing to run `{operation}` from backport-only checkout `{active_branch}`; "
            f"the default development branch is `{default_branch}`"
        )

    raise SystemExit(
        f"[blueprint-harness] refusing to run `{operation}` from default-development checkout `{active_branch}`; "
        f"backport-only work must target a non-default release branch (default: `{default_branch}`)"
    )


def ref_exists(repo_root: Path, ref: str) -> bool:
    return (
        subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", ref],
            cwd=repo_root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def resolve_git_ref(repo_root: Path, ref: str) -> str:
    if ref.startswith("refs/"):
        return ref

    candidates: list[str] = []
    if ref.startswith("origin/"):
        candidates.append(f"refs/remotes/{ref}")
    else:
        candidates.append(f"refs/heads/{ref}")
        candidates.append(f"refs/remotes/{ref}")
    candidates.append(ref)

    seen: set[str] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        if ref_exists(repo_root, candidate):
            return candidate
    return ref


def remote_head_ref(repo_root: Path) -> str | None:
    result = subprocess.run(
        ["git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
        cwd=repo_root,
        check=False,
        text=True,
        capture_output=True,
    )
    ref = result.stdout.strip()
    return ref or None


def preferred_release_ref(repo_root: Path) -> str:
    branch = active_release_branch(repo_root)
    if ref_exists(repo_root, f"refs/remotes/origin/{branch}"):
        return f"origin/{branch}"
    if ref_exists(repo_root, f"refs/heads/{branch}"):
        return branch
    remote_head = remote_head_ref(repo_root)
    if remote_head is not None and ref_exists(repo_root, f"refs/remotes/{remote_head}"):
        return remote_head
    for candidate in ("origin/main", "main", "origin/master", "master"):
        ref = f"refs/remotes/{candidate}" if candidate.startswith("origin/") else f"refs/heads/{candidate}"
        if ref_exists(repo_root, ref):
            return candidate
    return branch


def local_release_ref(repo_root: Path) -> str:
    branch = active_release_branch(repo_root)
    if ref_exists(repo_root, f"refs/heads/{branch}"):
        return branch
    remote_head = remote_head_ref(repo_root)
    if remote_head is not None and remote_head.startswith("origin/"):
        local_head = remote_head[len("origin/") :]
        if ref_exists(repo_root, f"refs/heads/{local_head}"):
            return local_head
    for candidate in ("main", "master"):
        if ref_exists(repo_root, f"refs/heads/{candidate}"):
            return candidate
    return branch


def root_checkout_namespace(repo_root: Path) -> str:
    return local_release_ref(repo_root)
