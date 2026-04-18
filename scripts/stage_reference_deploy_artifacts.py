#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import sys

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from scripts.blueprint_harness_projects import DEPLOY_PROJECT_ARTIFACT_SEPARATOR


ARTIFACT_PREFIX = "reference-blueprints-release-"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stage downloaded per-project deploy artifacts into a release-organized reference tree."
    )
    parser.add_argument(
        "--artifacts-root",
        default="_out/reference-artifact-downloads",
        help="Directory populated by actions/download-artifact with one subdirectory per artifact.",
    )
    parser.add_argument(
        "--output-root",
        default="_out/reference-blueprints",
        help="Directory where the combined reference blueprint tree should be rebuilt.",
    )
    return parser.parse_args()


def parse_artifact_name(name: str) -> tuple[str, str] | None:
    if not name.startswith(ARTIFACT_PREFIX):
        return None
    payload = name.removeprefix(ARTIFACT_PREFIX)
    release_id, separator, project_id = payload.partition(DEPLOY_PROJECT_ARTIFACT_SEPARATOR)
    if not separator or not release_id or not project_id:
        raise SystemExit(f"invalid deploy reference artifact name: {name}")
    return release_id, project_id


def resolve_artifact_project_root(artifact_dir: Path, release_id: str, project_id: str) -> Path:
    candidates = (
        artifact_dir,
        artifact_dir / project_id,
        artifact_dir / release_id / project_id,
    )
    for candidate in candidates:
        if (candidate / "html-multi").exists():
            return candidate
    raise SystemExit(
        f"artifact `{artifact_dir.name}` did not contain a recognizable `{project_id}` site payload"
    )


def stage_artifacts(artifacts_root: Path, output_root: Path) -> None:
    if not artifacts_root.exists():
        raise SystemExit(f"missing downloaded reference artifact root: {artifacts_root}")

    if output_root.exists():
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    staged = False
    for artifact_dir in sorted(path for path in artifacts_root.iterdir() if path.is_dir()):
        parsed = parse_artifact_name(artifact_dir.name)
        if parsed is None:
            continue
        release_id, project_id = parsed
        source_root = resolve_artifact_project_root(artifact_dir, release_id, project_id)
        destination = output_root / release_id / project_id
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source_root, destination)
        staged = True

    if not staged:
        raise SystemExit(f"no deploy reference artifacts found under {artifacts_root}")


def main() -> int:
    args = parse_args()
    artifacts_root = Path(args.artifacts_root).resolve()
    output_root = Path(args.output_root).resolve()
    stage_artifacts(artifacts_root, output_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
