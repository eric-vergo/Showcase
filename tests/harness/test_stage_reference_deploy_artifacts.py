from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


class StageReferenceDeployArtifactsTests(unittest.TestCase):
    def run_helper(self, artifacts_root: Path, output_root: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                "scripts/stage_reference_deploy_artifacts.py",
                "--artifacts-root",
                str(artifacts_root),
                "--output-root",
                str(output_root),
            ],
            cwd=PACKAGE_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_stage_artifacts_rebuilds_release_project_tree(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            artifacts_root = tmp_path / "reference-artifact-downloads"
            output_root = tmp_path / "reference-blueprints"

            direct = artifacts_root / "reference-blueprints-release-v4.28.0__project__project-template"
            (direct / "html-multi").mkdir(parents=True)
            (direct / "html-multi" / "index.html").write_text("project template v4.28.0", encoding="utf-8")

            nested = artifacts_root / "reference-blueprints-release-v4.29.0__project__noperthedron"
            (nested / "noperthedron" / "html-multi").mkdir(parents=True)
            (nested / "noperthedron" / "html-multi" / "index.html").write_text(
                "noperthedron v4.29.0",
                encoding="utf-8",
            )

            result = self.run_helper(artifacts_root, output_root)
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            self.assertEqual(
                (output_root / "v4.28.0" / "project-template" / "html-multi" / "index.html").read_text(
                    encoding="utf-8"
                ),
                "project template v4.28.0",
            )
            self.assertEqual(
                (output_root / "v4.29.0" / "noperthedron" / "html-multi" / "index.html").read_text(
                    encoding="utf-8"
                ),
                "noperthedron v4.29.0",
            )


if __name__ == "__main__":
    unittest.main()
