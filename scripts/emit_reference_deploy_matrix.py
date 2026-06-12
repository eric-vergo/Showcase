#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.blueprint_harness_paths import detect_harness_layout
from scripts.blueprint_harness_projects import (
    HarnessProject,
    HarnessProjectCatalog,
    HarnessReleaseTarget,
    deploy_project_artifact_name,
    deploy_project_artifact_path,
    load_project_catalog,
    project_target_rc,
    project_target_toolchain,
    project_target_verso_ref,
    reference_dependency_cache_key,
    resolve_manifest_path,
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


def release_target_manifest_entry(target: HarnessReleaseTarget) -> dict[str, object]:
    return {
        "id": target.release_id,
        "toolchain": target.release_toolchain,
        "verso_ref": target.release_verso_ref,
        "branch": target.branch,
        "deploy_pages": target.deploy_pages,
    }


def project_manifest_entry(project: HarnessProject) -> dict[str, object]:
    if project.selected_release is None:
        raise ValueError(f"project `{project.project_id}` is missing selected release metadata")

    source: dict[str, object] = {
        "kind": project.source_kind,
        "project_root": project.project_root,
    }
    if project.repository is not None:
        source["repository"] = project.repository

    target: dict[str, object] = {"release": project.selected_release}
    if project.ref is not None:
        target["ref"] = project.ref
    if project.selected_rc is not None:
        target["rc"] = project.selected_rc

    entry: dict[str, object] = {
        "id": project.project_id,
        "source": source,
        "targets": [target],
        "site_subdir": project.site_subdir,
    }
    if project.description is not None:
        entry["description"] = project.description
    if project.build_target is not None:
        entry["build_target"] = project.build_target
    if project.generator is not None:
        entry["generator"] = project.generator
    if project.build_command is not None:
        entry["build_command"] = list(project.build_command)
    if project.generate_command is not None:
        entry["generate_command"] = list(project.generate_command)
    validation: dict[str, object] = {}
    if project.panel_regression_script is not None:
        validation["panel_regression_script"] = project.panel_regression_script
    if project.browser_tests_path is not None:
        validation["browser_tests_path"] = project.browser_tests_path
    if validation:
        entry["validation"] = validation
    return entry


def deploy_project_manifest(target: HarnessReleaseTarget, project: HarnessProject) -> dict[str, object]:
    return {
        "version": 2,
        "release_targets": [release_target_manifest_entry(target)],
        "projects": [project_manifest_entry(project)],
    }


def deploy_matrix_from_controller_catalog(
    controller_catalog: HarnessProjectCatalog,
    deployable_targets: tuple[HarnessReleaseTarget, ...],
) -> dict[str, list[dict[str, object]]]:
    include: list[dict[str, object]] = []
    for target in deployable_targets:
        controller_projects = resolve_projects_for_release(controller_catalog, target.release_id, None)
        if not controller_projects:
            raise ValueError(
                f"release target `{target.release_id}` has `deploy_pages: true` but no published "
                "reference project targets"
            )
        for project in controller_projects:
            include.append(
                {
                    "release_id": target.release_id,
                    "rc": project_target_rc(project),
                    "toolchain": project_target_toolchain(target, project),
                    "verso_ref": project_target_verso_ref(target, project),
                    "branch": target.branch,
                    "project_id": project.project_id,
                    "project_root": project.project_root,
                    "hash": project.ref,
                    "reference_cache_key": reference_dependency_cache_key(project) if project.git_checkout else "",
                    "artifact_name": deploy_project_artifact_name(project),
                    "artifact_path": deploy_project_artifact_path(project),
                    "project_manifest": deploy_project_manifest(target, project),
                }
            )
    return {"include": include}


def payload(args: argparse.Namespace) -> dict[str, object]:
    layout = detect_harness_layout(Path(__file__))
    manifest_path = resolve_manifest_path(args.manifest, layout.package_root)
    catalog = load_project_catalog(manifest_path)
    deployable_targets = tuple(
        target
        for target in catalog.release_targets
        if target.deploy_pages
    )
    matrix = deploy_matrix_from_controller_catalog(catalog, deployable_targets)
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
