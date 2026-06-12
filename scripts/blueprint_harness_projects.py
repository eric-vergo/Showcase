from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, replace
import json
from pathlib import Path
import subprocess

from scripts.blueprint_harness_branches import active_release_branch, normalize_lean_release_ref
from scripts.blueprint_harness_manifest import (
    load_json_object,
    optional_bool as _optional_bool,
    optional_command as _optional_command,
    optional_string as _optional_string,
    require_string as _require_string,
    resolve_manifest_path as resolve_manifest_file_path,
)


IN_REPO_PROJECT_SOURCE_KIND = "in_repo_project"
GIT_CHECKOUT_SOURCE_KIND = "git_checkout"


@dataclass(frozen=True)
class HarnessReleaseTarget:
    release_id: str
    toolchain: str
    verso_ref: str
    branch: str
    deploy_pages: bool


@dataclass(frozen=True)
class HarnessProjectTarget:
    release: str
    ref: str | None


@dataclass(frozen=True)
class HarnessReferenceBlueprint:
    blueprint: str
    hash: str
    toolchain: str


@dataclass(frozen=True)
class HarnessProjectCatalog:
    version: int
    release_targets: tuple[HarnessReleaseTarget, ...]
    projects: tuple["HarnessProject", ...]
    reference_blueprints: tuple[HarnessReferenceBlueprint, ...] = ()

    def release_target(self, release_id: str) -> HarnessReleaseTarget | None:
        for target in self.release_targets:
            if target.release_id == release_id:
                return target
        return None


@dataclass(frozen=True)
class HarnessProject:
    project_id: str
    source_kind: str
    project_root: str
    build_target: str | None
    generator: str | None
    repository: str | None
    ref: str | None
    build_command: tuple[str, ...] | None
    generate_command: tuple[str, ...] | None
    site_subdir: str
    panel_regression_script: str | None
    browser_tests_path: str | None
    description: str | None
    targets: tuple[HarnessProjectTarget, ...] = ()
    selected_release: str | None = None

    @property
    def in_repo_project(self) -> bool:
        return self.source_kind == IN_REPO_PROJECT_SOURCE_KIND

    @property
    def git_checkout(self) -> bool:
        return self.source_kind == GIT_CHECKOUT_SOURCE_KIND

    @property
    def in_repo_target_project(self) -> bool:
        return self.in_repo_project and self.build_target is not None and self.generator is not None

    @property
    def in_repo_command_project(self) -> bool:
        return self.in_repo_project and self.generate_command is not None

    def target_for_release(self, release: str) -> HarnessProjectTarget | None:
        for target in self.targets:
            if target.release == release:
                return target
        return None


def default_project_manifest(package_root: Path) -> Path:
    return package_root / "tests" / "harness" / "projects.json"


def resolve_manifest_path(path_text: str | None, package_root: Path) -> Path:
    return resolve_manifest_file_path(path_text, default_project_manifest(package_root))


def _load_release_targets(raw: dict, manifest_path: Path | str) -> tuple[HarnessReleaseTarget, ...]:
    entries = raw.get("release_targets")
    if not isinstance(entries, list) or not entries:
        raise ValueError(f"{manifest_path}: expected non-empty top-level `release_targets` list")

    targets: list[HarnessReleaseTarget] = []
    seen_ids: set[str] = set()
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict):
            raise ValueError(f"{manifest_path}: release target #{index} must be an object")
        context = f"{manifest_path}: release target #{index}"
        release_id = normalize_lean_release_ref(_require_string(entry, "id", context=context))
        if release_id in seen_ids:
            raise ValueError(f"{context}: duplicate release target id `{release_id}`")
        seen_ids.add(release_id)
        toolchain = normalize_lean_release_ref(_require_string(entry, "toolchain", context=context))
        verso_ref = normalize_lean_release_ref(_require_string(entry, "verso_ref", context=context))
        branch = normalize_lean_release_ref(_require_string(entry, "branch", context=context))
        deploy_pages = _optional_bool(entry, "deploy_pages", default=False, context=context)
        targets.append(
            HarnessReleaseTarget(
                release_id=release_id,
                toolchain=toolchain,
                verso_ref=verso_ref,
                branch=branch,
                deploy_pages=deploy_pages,
            )
        )
    return tuple(targets)


def _load_reference_blueprints(raw: dict, manifest_path: Path | str) -> tuple[HarnessReferenceBlueprint, ...]:
    entries = raw.get("reference_blueprints")
    if entries is None:
        return ()
    if not isinstance(entries, list):
        raise ValueError(f"{manifest_path}: expected top-level `reference_blueprints` list")

    blueprints: list[HarnessReferenceBlueprint] = []
    seen: set[tuple[str, str]] = set()
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict):
            raise ValueError(f"{manifest_path}: reference blueprint #{index} must be an object")
        context = f"{manifest_path}: reference blueprint #{index}"
        blueprint = _require_string(entry, "blueprint", context=context)
        commit_hash = _require_string(entry, "hash", context=context)
        toolchain = normalize_lean_release_ref(_require_string(entry, "toolchain", context=context))
        key = (blueprint, toolchain)
        if key in seen:
            raise ValueError(f"{context}: duplicate reference blueprint `{blueprint}` for toolchain `{toolchain}`")
        seen.add(key)
        blueprints.append(HarnessReferenceBlueprint(blueprint=blueprint, hash=commit_hash, toolchain=toolchain))
    return tuple(blueprints)


def _load_project_targets(
    entry: dict,
    *,
    context: str,
    release_ids: set[str],
    source_kind: str,
) -> tuple[HarnessProjectTarget, ...]:
    raw_targets = entry.get("targets")
    if not isinstance(raw_targets, list) or not raw_targets:
        raise ValueError(f"{context}: expected non-empty `targets` list")

    targets: list[HarnessProjectTarget] = []
    seen_releases: set[str] = set()
    for index, raw_target in enumerate(raw_targets, start=1):
        if not isinstance(raw_target, dict):
            raise ValueError(f"{context}: target #{index} must be an object")
        target_context = f"{context}: target #{index}"
        release = normalize_lean_release_ref(_require_string(raw_target, "release", context=target_context))
        if release not in release_ids:
            raise ValueError(f"{target_context}: unknown release target `{release}`")
        if release in seen_releases:
            raise ValueError(f"{target_context}: duplicate release target `{release}`")
        seen_releases.add(release)
        ref = _optional_string(raw_target, "ref", context=target_context)
        if source_kind == GIT_CHECKOUT_SOURCE_KIND and ref is None:
            raise ValueError(f"{target_context}: git checkout targets must declare `ref`")
        if source_kind == IN_REPO_PROJECT_SOURCE_KIND and ref is not None:
            raise ValueError(f"{target_context}: in-repo project targets must not declare `ref`")
        targets.append(
            HarnessProjectTarget(
                release=release,
                ref=ref,
            )
        )
    return tuple(targets)


def load_project_catalog_data(raw: dict, manifest_path: Path | str) -> HarnessProjectCatalog:
    if raw.get("version") != 2:
        raise ValueError(f"{manifest_path}: unsupported manifest version {raw.get('version')!r}")
    release_targets = _load_release_targets(raw, manifest_path)
    reference_blueprints = _load_reference_blueprints(raw, manifest_path)
    release_ids = {target.release_id for target in release_targets}

    entries = raw.get("projects")
    if not isinstance(entries, list):
        raise ValueError(f"{manifest_path}: expected top-level `projects` list")

    projects: list[HarnessProject] = []
    seen_ids: set[str] = set()
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict):
            raise ValueError(f"{manifest_path}: project #{index} must be an object")

        context = f"{manifest_path}: project #{index}"
        project_id = _require_string(entry, "id", context=context)
        if project_id in seen_ids:
            raise ValueError(f"{context}: duplicate project id `{project_id}`")
        seen_ids.add(project_id)

        source = entry.get("source")
        if not isinstance(source, dict):
            raise ValueError(f"{context}: missing object field `source`")
        source_kind = _require_string(source, "kind", context=context)
        project_root = _optional_string(source, "project_root", context=context) or "."

        build_target = _optional_string(entry, "build_target", context=context)
        generator = _optional_string(entry, "generator", context=context)
        repository = _optional_string(source, "repository", context=context)
        ref = _optional_string(source, "ref", context=context)
        build_command = _optional_command(entry, "build_command", context=context)
        generate_command = _optional_command(entry, "generate_command", context=context)

        validation = entry.get("validation") or {}
        if not isinstance(validation, dict):
            raise ValueError(f"{context}: expected object field `validation`")
        panel_regression_script = _optional_string(validation, "panel_regression_script", context=context)
        browser_tests_path = _optional_string(validation, "browser_tests_path", context=context)
        description = _optional_string(entry, "description", context=context)
        site_subdir = _optional_string(entry, "site_subdir", context=context) or "html-multi"
        targets = _load_project_targets(entry, context=context, release_ids=release_ids, source_kind=source_kind)

        if source_kind == IN_REPO_PROJECT_SOURCE_KIND:
            target_mode = build_target is not None or generator is not None
            command_mode = build_command is not None or generate_command is not None
            if target_mode and command_mode:
                raise ValueError(
                    f"{context}: in-repo projects must use either `build_target`/`generator` or "
                    "`build_command`/`generate_command`, not both"
                )
            if target_mode:
                if build_target is None or generator is None:
                    raise ValueError(
                        f"{context}: in-repo projects using root-package targets must declare both "
                        "`build_target` and `generator`"
                    )
                if repository is not None or build_command is not None or generate_command is not None:
                    raise ValueError(
                        f"{context}: in-repo projects using root-package targets must not declare "
                        "`repository`, `build_command`, or `generate_command`"
                    )
            elif command_mode:
                if generate_command is None:
                    raise ValueError(
                        f"{context}: in-repo projects using nested project commands must declare "
                        "`generate_command`"
                    )
                if repository is not None or build_target is not None or generator is not None:
                    raise ValueError(
                        f"{context}: in-repo projects using nested project commands must not declare "
                        "`repository`, `build_target`, or `generator`"
                    )
            else:
                raise ValueError(
                    f"{context}: in-repo projects must declare either `build_target`/`generator` "
                    "or `generate_command`"
                )
        elif source_kind == GIT_CHECKOUT_SOURCE_KIND:
            if repository is None:
                raise ValueError(f"{context}: git checkout projects must declare `source.repository`")
            if generate_command is None:
                raise ValueError(f"{context}: git checkout projects must declare `generate_command`")
            if ref is not None:
                raise ValueError(f"{context}: git checkout projects must declare release-specific refs under `targets`, not `source.ref`")
            if build_target is not None or generator is not None:
                raise ValueError(
                    f"{context}: git checkout projects must not declare `build_target` or `generator`"
                )
        else:
            raise ValueError(f"{context}: unsupported source kind `{source_kind}`")

        projects.append(
            HarnessProject(
                project_id=project_id,
                source_kind=source_kind,
                project_root=project_root,
                build_target=build_target,
                generator=generator,
                repository=repository,
                ref=ref,
                build_command=build_command,
                generate_command=generate_command,
                site_subdir=site_subdir,
                panel_regression_script=panel_regression_script,
                browser_tests_path=browser_tests_path,
                description=description,
                targets=targets,
            )
        )

    project_by_id = {project.project_id: project for project in projects}
    for blueprint in reference_blueprints:
        project = project_by_id.get(blueprint.blueprint)
        if project is None:
            known = ", ".join(sorted(project_by_id))
            raise ValueError(
                f"{manifest_path}: reference blueprint `{blueprint.blueprint}` is not a known project; "
                f"known projects: {known}"
            )
        if not project.git_checkout:
            raise ValueError(f"{manifest_path}: reference blueprint `{blueprint.blueprint}` must be a git checkout project")
        release = normalize_lean_release_ref(blueprint.toolchain)
        target = project.target_for_release(release)
        if target is None:
            raise ValueError(
                f"{manifest_path}: reference blueprint `{blueprint.blueprint}` for toolchain "
                f"`{blueprint.toolchain}` has no project target for release `{release}`"
            )
        if target.ref is not None and target.ref != blueprint.hash:
            raise ValueError(
                f"{manifest_path}: reference blueprint `{blueprint.blueprint}` hash `{blueprint.hash}` "
                f"does not match target ref `{target.ref}` for release `{release}`"
            )

    return HarnessProjectCatalog(
        version=2,
        release_targets=release_targets,
        projects=tuple(projects),
        reference_blueprints=reference_blueprints,
    )


def load_project_catalog(manifest_path: Path) -> HarnessProjectCatalog:
    raw = load_json_object(manifest_path)
    return load_project_catalog_data(raw, manifest_path)


def load_project_catalog_text(text: str, manifest_path: Path | str) -> HarnessProjectCatalog:
    raw = json.loads(text)
    if not isinstance(raw, dict):
        raise ValueError(f"{manifest_path}: expected JSON object")
    return load_project_catalog_data(raw, manifest_path)


def load_projects_manifest(manifest_path: Path) -> list[HarnessProject]:
    return list(load_project_catalog(manifest_path).projects)


def resolve_release_target(catalog: HarnessProjectCatalog, release: str | None, package_root: Path) -> HarnessReleaseTarget:
    selected = normalize_lean_release_ref(release) if release is not None else active_release_branch(package_root)
    target = catalog.release_target(selected)
    if target is None:
        known = ", ".join(sorted(entry.release_id for entry in catalog.release_targets))
        raise ValueError(f"{package_root}: unknown release target `{selected}`; known release targets: {known}")
    return target


def resolve_projects_for_release(
    catalog: HarnessProjectCatalog,
    release: str,
    selected_ids: list[str] | None,
) -> list[HarnessProject]:
    by_id = {project.project_id: project for project in catalog.projects}
    release_target = catalog.release_target(release)
    if catalog.reference_blueprints and release_target is not None and selected_ids is None:
        matching = [
            blueprint
            for blueprint in catalog.reference_blueprints
            if blueprint.toolchain == release_target.toolchain
        ]
        resolved_from_blueprints: list[HarnessProject] = []
        for blueprint in matching:
            project = by_id[blueprint.blueprint]
            target = project.target_for_release(release)
            if target is None:
                raise ValueError(f"project `{project.project_id}` has no target for release `{release}`")
            resolved_from_blueprints.append(
                replace(
                    project,
                    ref=blueprint.hash,
                    selected_release=release,
                )
            )
        return resolved_from_blueprints

    if selected_ids is None:
        candidates = list(catalog.projects)
    else:
        seen: set[str] = set()
        candidates: list[HarnessProject] = []
        for value in selected_ids:
            if value not in by_id:
                known = ", ".join(sorted(by_id))
                raise ValueError(f"unknown project `{value}`; known projects: {known}")
            if value not in seen:
                candidates.append(by_id[value])
                seen.add(value)

    resolved: list[HarnessProject] = []
    for project in candidates:
        target = project.target_for_release(release)
        if target is None:
            if selected_ids is not None:
                raise ValueError(f"project `{project.project_id}` has no target for release `{release}`")
            continue
        resolved.append(
            replace(
                project,
                ref=target.ref,
                selected_release=release,
            )
        )
    return resolved


def reference_artifact_name(project: HarnessProject) -> str:
    return f"reference-blueprints-{project.project_id}"


def reference_artifact_path(project: HarnessProject) -> str:
    return f"_out/reference-blueprints/{project.project_id}"


def reference_build_matrix(projects: list[HarnessProject]) -> dict[str, list[dict[str, object]]]:
    return {
        "include": [
            {
                "project_id": project.project_id,
                "hash": project.ref,
                "artifact_name": reference_artifact_name(project),
                "artifact_path": reference_artifact_path(project),
            }
            for project in projects
        ]
    }


def reference_release_payload(
    manifest_path: Path,
    catalog: HarnessProjectCatalog,
    release: str | None,
    package_root: Path,
) -> dict[str, object]:
    release_target = resolve_release_target(catalog, release, package_root)
    projects = resolve_projects_for_release(catalog, release_target.release_id, None)
    return {
        "manifest_path": str(manifest_path),
        "release_id": release_target.release_id,
        "rc": "",
        "toolchain": release_target.toolchain,
        "verso_ref": release_target.verso_ref,
        "branch": release_target.branch,
        "deploy_pages": release_target.deploy_pages,
        "reference_project_count": len(projects),
        "reference_matrix": reference_build_matrix(projects),
    }


DEPLOY_PROJECT_ARTIFACT_SEPARATOR = "__project__"


def deploy_project_artifact_name(project: HarnessProject) -> str:
    if project.selected_release is None:
        raise ValueError(f"project `{project.project_id}` is missing selected release metadata")
    return (
        f"reference-blueprints-release-{project.selected_release}"
        f"{DEPLOY_PROJECT_ARTIFACT_SEPARATOR}{project.project_id}"
    )


def deploy_project_artifact_path(project: HarnessProject) -> str:
    if project.selected_release is None:
        raise ValueError(f"project `{project.project_id}` is missing selected release metadata")
    return f"_out/reference-blueprints/{project.selected_release}/{project.project_id}"


def reference_blueprint_ids_for_toolchain(catalog: HarnessProjectCatalog, toolchain: str) -> list[str]:
    normalized_toolchain = normalize_lean_release_ref(toolchain)
    return [
        blueprint.blueprint
        for blueprint in catalog.reference_blueprints
        if blueprint.toolchain == normalized_toolchain
    ]


def deploy_project_matrix(
    release_targets: tuple[HarnessReleaseTarget, ...],
    catalog: HarnessProjectCatalog,
) -> dict[str, list[dict[str, object]]]:
    include: list[dict[str, object]] = []
    for target in release_targets:
        if not target.deploy_pages:
            continue
        for project in resolve_projects_for_release(catalog, target.release_id, None):
            include.append(
                {
                    "release_id": target.release_id,
                    "toolchain": target.toolchain,
                    "verso_ref": target.verso_ref,
                    "branch": target.branch,
                    "project_id": project.project_id,
                    "hash": project.ref,
                    "artifact_name": deploy_project_artifact_name(project),
                    "artifact_path": deploy_project_artifact_path(project),
                }
            )
    return {"include": include}


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
