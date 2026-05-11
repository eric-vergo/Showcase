from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

import scripts.blueprint_harness_toolchains as toolchains_mod


class BlueprintHarnessToolchainTests(unittest.TestCase):
    def write(self, path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_normalize_lean_release_ref_accepts_short_numeric_version(self) -> None:
        self.assertEqual(toolchains_mod.normalize_lean_release_ref("4.29.0"), "v4.29.0")
        self.assertEqual(toolchains_mod.normalize_lean_release_ref("leanprover/lean4:v4.29.0"), "v4.29.0")

    def test_rewrite_pinned_verso_dependency_replaces_official_git_require(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project_dir = Path(tmp)
            lakefile = project_dir / "lakefile.lean"
            lakefile.write_text(
                '\n'.join(
                    [
                        "import Lake",
                        "open Lake DSL",
                        'require verso from git "https://github.com/leanprover/verso"@"main"',
                        "",
                    ]
                ),
                encoding="utf-8",
            )

            result, previous_ref = toolchains_mod.rewrite_pinned_verso_dependency(project_dir, "v4.29.0")

            self.assertEqual(result, lakefile)
            self.assertEqual(previous_ref, "main")
            self.assertIn('require verso from git "https://github.com/leanprover/verso"@"v4.29.0"', lakefile.read_text(encoding="utf-8"))

    def test_bump_toolchain_checkout_updates_managed_files_and_preserves_inherited_dependencies(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            package_root = Path(tmp)
            root_lakefile = "\n".join(
                [
                    "import Lake",
                    "open Lake DSL",
                    'require verso from git "https://github.com/leanprover/verso"@"main"',
                    'require proofwidgets from git "https://github.com/leanprover-community/ProofWidgets4"@"v0.0.92"',
                    "",
                ]
            )
            template_lakefile = "\n".join(
                [
                    "import Lake",
                    "open Lake DSL",
                    'require VersoBlueprint from git "https://github.com/leanprover/verso-blueprint"@"main"',
                    "",
                ]
            )
            preview_lakefile = "\n".join(
                [
                    "import Lake",
                    "open Lake DSL",
                    'require VersoBlueprint from "../../../"',
                    "",
                ]
            )

            self.write(package_root / "lean-toolchain", "leanprover/lean4:v4.29.0-rc6")
            self.write(package_root / "lakefile.lean", root_lakefile)
            self.write(package_root / "project_template" / "lean-toolchain", "leanprover/lean4:v4.29.0-rc6\n")
            self.write(package_root / "project_template" / "lakefile.lean", template_lakefile)
            self.write(
                package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lean-toolchain",
                "leanprover/lean4:v4.29.0-rc6\n",
            )
            self.write(
                package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lakefile.lean",
                preview_lakefile,
            )

            originals = {
                "resolve_remote_verso_tag_oid": toolchains_mod.resolve_remote_verso_tag_oid,
                "run": toolchains_mod.run,
            }
            commands: list[tuple[list[str], Path]] = []
            try:
                toolchains_mod.resolve_remote_verso_tag_oid = lambda _package_root, _ref: "deadbeef"
                toolchains_mod.run = lambda command, *, cwd: commands.append((command, cwd))

                result = toolchains_mod.bump_toolchain_checkout(package_root, "4.29.0", validate=False)
            finally:
                for name, value in originals.items():
                    setattr(toolchains_mod, name, value)

            self.assertEqual(result.lean_ref, "v4.29.0")
            self.assertEqual(result.verso_ref, "v4.29.0")
            self.assertEqual((package_root / "lean-toolchain").read_text(encoding="utf-8"), "leanprover/lean4:v4.29.0")
            self.assertEqual(
                (package_root / "project_template" / "lean-toolchain").read_text(encoding="utf-8"),
                "leanprover/lean4:v4.29.0\n",
            )
            self.assertEqual(
                (package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lean-toolchain").read_text(
                    encoding="utf-8"
                ),
                "leanprover/lean4:v4.29.0\n",
            )
            self.assertIn('require verso from git "https://github.com/leanprover/verso"@"v4.29.0"', (package_root / "lakefile.lean").read_text(encoding="utf-8"))
            template_text = (package_root / "project_template" / "lakefile.lean").read_text(encoding="utf-8")
            self.assertNotIn("require verso", template_text)
            self.assertIn(
                'require VersoBlueprint from git "https://github.com/leanprover/verso-blueprint"@"main"',
                template_text,
            )
            preview_text = (
                package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lakefile.lean"
            ).read_text(encoding="utf-8")
            self.assertIn(
                'require VersoBlueprint from "../../../"',
                preview_text,
            )
            self.assertNotIn(
                "require verso",
                preview_text,
            )
            expected_script = str(package_root / "scripts" / "lean-low-priority")
            self.assertEqual(
                commands,
                [
                    ([expected_script, "lake", "update"], package_root),
                    ([expected_script, "lake", "update"], package_root / "project_template"),
                    (
                        [expected_script, "lake", "update"],
                        package_root / "tests" / "test_blueprints" / "preview_runtime_showcase",
                    ),
                ],
            )

    def test_bump_toolchain_checkout_rejects_missing_matching_verso_tag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            package_root = Path(tmp)
            self.write(package_root / "lean-toolchain", "leanprover/lean4:v4.29.0-rc6")
            self.write(
                package_root / "lakefile.lean",
                'require verso from git "https://github.com/leanprover/verso"@"main"\n',
            )
            self.write(package_root / "project_template" / "lean-toolchain", "leanprover/lean4:v4.29.0-rc6\n")
            self.write(
                package_root / "project_template" / "lakefile.lean",
                'require VersoBlueprint from git "https://github.com/leanprover/verso-blueprint"@"main"\n',
            )
            self.write(
                package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lean-toolchain",
                "leanprover/lean4:v4.29.0-rc6\n",
            )
            self.write(
                package_root / "tests" / "test_blueprints" / "preview_runtime_showcase" / "lakefile.lean",
                'require VersoBlueprint from "../../../"\n',
            )

            original = toolchains_mod.resolve_remote_verso_tag_oid
            try:
                toolchains_mod.resolve_remote_verso_tag_oid = lambda _package_root, _ref: None
                with self.assertRaisesRegex(SystemExit, "no matching `verso` tag"):
                    toolchains_mod.bump_toolchain_checkout(package_root, "v4.29.0", validate=False)
            finally:
                toolchains_mod.resolve_remote_verso_tag_oid = original


if __name__ == "__main__":
    unittest.main()
