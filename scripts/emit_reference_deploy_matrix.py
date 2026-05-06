#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections.abc import Callable
import json
from pathlib import Path
import subprocess
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.blueprint_harness_paths import detect_harness_layout
from scripts.blueprint_harness_projects import (
    HarnessProjectCatalog,
    HarnessReleaseTarget,
    default_project_manifest,
    deploy_project_artifact_name,
    deploy_project_artifact_path,
    load_project_catalog,
    load_project_catalog_text,
    reference_blueprint_ids_for_toolchain,
    resolve_projects_for_release,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Emit deployable reference-release metadata for the Pages deployment workflow."
    )
    parser.add_argument(
        "--manifest",
        default=None,
        help="Project manifest path. Defaults to tests/harness/projects.json in the current checkout.",
    )
    parser.add_argument(
        "--github-output",
        action="store_true",
        help="Print GitHub Actions step outputs instead of plain JSON.",
    )
    return parser.parse_args()


def resolve_manifest_path(layout, path_text: str | None) -> Path:
    if path_text is None:
        return default_project_manifest(layout.package_root)
    path = Path(path_text)
    if path.is_absolute():
        return path.resolve()
    return (Path.cwd() / path).resolve()


def manifest_relative_to_package(manifest_path: Path, package_root: Path) -> Path | None:
    try:
        return manifest_path.relative_to(package_root)
    except ValueError:
        return None


def release_branch_ref_candidates(branch: str) -> tuple[str, ...]:
    return (f"origin/{branch}", f"refs/remotes/origin/{branch}", branch)


def load_branch_project_catalog(
    *,
    branch: str,
    manifest_path: Path,
    package_root: Path,
) -> HarnessProjectCatalog:
    manifest_relpath = manifest_relative_to_package(manifest_path, package_root)
    if manifest_relpath is None:
        return load_project_catalog(manifest_path)

    errors: list[str] = []
    for ref in release_branch_ref_candidates(branch):
        result = subprocess.run(
            ["git", "show", f"{ref}:{manifest_relpath.as_posix()}"],
            cwd=package_root,
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode == 0:
            return load_project_catalog_text(result.stdout, f"{ref}:{manifest_relpath.as_posix()}")
        errors.append(result.stderr.strip() or result.stdout.strip())

    raise ValueError(
        f"could not load reference project catalog for release branch `{branch}` from `{manifest_relpath}`; "
        + "; ".join(error for error in errors if error)
    )


def deploy_matrix_from_release_catalogs(
    controller_catalog: HarnessProjectCatalog,
    deployable_targets: tuple[HarnessReleaseTarget, ...],
    catalog_for_target: Callable[[HarnessReleaseTarget], HarnessProjectCatalog],
) -> dict[str, list[dict[str, object]]]:
    include: list[dict[str, object]] = []
    for target in deployable_targets:
        selected_blueprints = [
            blueprint
            for blueprint in controller_catalog.reference_blueprints
            if blueprint.toolchain == target.toolchain
        ]
        selected_project_ids = reference_blueprint_ids_for_toolchain(controller_catalog, target.toolchain)
        expected_hash_by_project = {blueprint.blueprint: blueprint.hash for blueprint in selected_blueprints}
        if controller_catalog.reference_blueprints and not selected_blueprints:
            raise ValueError(
                f"release target `{target.release_id}` has `deploy_pages: true` but no reference "
                f"blueprints for toolchain `{target.toolchain}`"
            )
        release_catalog = catalog_for_target(target)
        release_target = release_catalog.release_target(target.release_id)
        if release_target is None:
            raise ValueError(
                f"catalog for branch `{target.branch}` does not define release target `{target.release_id}`"
            )
        projects = resolve_projects_for_release(
            release_catalog,
            release_target.release_id,
            selected_project_ids or None,
        )
        for project in projects:
            expected_hash = expected_hash_by_project.get(project.project_id)
            if expected_hash is not None and project.ref != expected_hash:
                raise ValueError(
                    f"reference blueprint `{project.project_id}` for toolchain `{target.toolchain}` resolves "
                    f"to `{project.ref}` on branch `{target.branch}`, but the deploy catalog declares `{expected_hash}`"
                )
            include.append(
                {
                    "release_id": release_target.release_id,
                    "rc": getattr(release_target, "rc", None),
                    "toolchain": release_target.toolchain,
                    "verso_ref": release_target.verso_ref,
                    "branch": release_target.branch,
                    "project_id": project.project_id,
                    "hash": project.ref,
                    "artifact_name": deploy_project_artifact_name(project),
                    "artifact_path": deploy_project_artifact_path(project),
                }
            )
    return {"include": include}


def payload(args: argparse.Namespace) -> dict[str, object]:
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_manifest_path(layout, args.manifest)
    catalog = load_project_catalog(manifest_path)
    deployable_targets = tuple(
        target
        for target in catalog.release_targets
        if target.deploy_pages
    )
    matrix = deploy_matrix_from_release_catalogs(
        catalog,
        deployable_targets,
        lambda target: load_branch_project_catalog(
            branch=target.branch,
            manifest_path=manifest_path,
            package_root=layout.package_root,
        ),
    )
    deployable_release_count = len({entry["release_id"] for entry in matrix["include"]})
    return {
        "manifest_path": str(manifest_path),
        "deployable_release_count": deployable_release_count,
        "deployable_project_count": len(matrix["include"]),
        "deployable_project_matrix": matrix,
    }


def emit_github_output(data: dict[str, object]) -> None:
    print(f"manifest_path={data['manifest_path']}")
    print(f"deployable_release_count={data['deployable_release_count']}")
    print(f"deployable_project_count={data['deployable_project_count']}")
    print("deployable_project_matrix<<__CODEX__")
    print(json.dumps(data["deployable_project_matrix"], separators=(",", ":")))
    print("__CODEX__")


def main() -> int:
    args = parse_args()
    data = payload(args)
    if args.github_output:
        emit_github_output(data)
    else:
        print(json.dumps(data, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
