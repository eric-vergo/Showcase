from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from scripts.blueprint_test_blueprints import (
    TAG_PATTERN,
    StandaloneTestBlueprint,
    default_test_blueprint_manifest,
    find_test_blueprint,
    load_test_blueprint_categories,
    load_test_blueprints_manifest,
)


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


class StandaloneTestBlueprintTests(unittest.TestCase):
    def test_default_manifest_contains_preview_runtime_showcase(self) -> None:
        manifest = default_test_blueprint_manifest(PACKAGE_ROOT)
        categories = load_test_blueprint_categories(manifest)
        fixtures = load_test_blueprints_manifest(manifest)
        fixture = find_test_blueprint(fixtures, "preview_runtime_showcase")

        self.assertEqual(
            categories,
            ("Code", "Preview", "Relationships", "Summary", "Metadata", "Imports", "Graph", "Runtime"),
        )
        self.assertEqual(fixture.slug, "preview_runtime_showcase")
        self.assertEqual(fixture.kind, "standalone_project")
        self.assertEqual(fixture.category, "Runtime")
        self.assertEqual(
            fixture.tags,
            ("preview", "runtime", "browser", "graph", "summary", "relationships"),
        )
        self.assertEqual(fixture.project_root, "tests/test_blueprints/preview_runtime_showcase")
        self.assertEqual(fixture.browser_tests_path, "tests/browser")
        self.assertEqual(
            fixture.panel_regression_script,
            "tests/harness/preview_runtime_showcase/check_blueprint_code_panels.py",
        )

    def test_duplicate_fixture_slugs_are_rejected(self) -> None:
        manifest_data = {
            "version": 1,
            "fixtures": [
                {
                    "slug": "dup",
                    "title": "One",
                    "category": "Runtime",
                    "summary": "First",
                    "project_root": "tests/test_blueprints/one",
                    "generate_command": ["lake", "exe", "blueprint-gen", "--output", "{output_dir}"],
                },
                {
                    "slug": "dup",
                    "title": "Two",
                    "category": "Runtime",
                    "summary": "Second",
                    "project_root": "tests/test_blueprints/two",
                    "generate_command": ["lake", "exe", "blueprint-gen", "--output", "{output_dir}"],
                },
            ],
            "categories": ["Runtime"],
        }
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "test_blueprints.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate fixture slug"):
                load_test_blueprints_manifest(manifest)

    def test_missing_generate_command_is_rejected(self) -> None:
        manifest_data = {
            "version": 1,
            "fixtures": [
                {
                    "slug": "missing",
                    "title": "Missing Generate",
                    "category": "Runtime",
                    "summary": "Bad fixture",
                    "project_root": "tests/test_blueprints/bad",
                }
            ],
            "categories": ["Runtime"],
        }
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "test_blueprints.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "generate_command"):
                load_test_blueprints_manifest(manifest)

    def test_unknown_category_is_rejected(self) -> None:
        manifest_data = {
            "version": 1,
            "categories": ["Preview"],
            "fixtures": [
                {
                    "slug": "bad-category",
                    "title": "Bad Category",
                    "category": "Runtime",
                    "summary": "Bad fixture",
                    "project_root": "tests/test_blueprints/bad",
                    "generate_command": ["lake", "exe", "blueprint-gen", "--output", "{output_dir}"],
                }
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "test_blueprints.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "unknown category"):
                load_test_blueprints_manifest(manifest)

    def test_invalid_tags_are_rejected(self) -> None:
        manifest_data = {
            "version": 1,
            "categories": ["Runtime"],
            "fixtures": [
                {
                    "slug": "bad-tag",
                    "title": "Bad Tag",
                    "category": "Runtime",
                    "summary": "Bad fixture",
                    "tags": ["not valid"],
                    "project_root": "tests/test_blueprints/bad",
                    "generate_command": ["lake", "exe", "blueprint-gen", "--output", "{output_dir}"],
                }
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "test_blueprints.json"
            manifest.write_text(json.dumps(manifest_data), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "invalid tag"):
                load_test_blueprints_manifest(manifest)

    def test_curated_docs_follow_shared_category_vocabulary(self) -> None:
        manifest = default_test_blueprint_manifest(PACKAGE_ROOT)
        categories = set(load_test_blueprint_categories(manifest))
        result = subprocess.run(
            ["./scripts/lean-low-priority", "lake", "exe", "blueprint-test-docs", "--list-json"],
            cwd=PACKAGE_ROOT,
            check=True,
            text=True,
            capture_output=True,
        )
        entries = json.loads(result.stdout)
        self.assertTrue(entries)
        for entry in entries:
            self.assertIn(entry["category"], categories)
            self.assertEqual(entry["kind"], "curated_doc")
            self.assertIsInstance(entry.get("tags"), list)
            self.assertTrue(all(isinstance(tag, str) and tag for tag in entry["tags"]))
            self.assertEqual(len(entry["tags"]), len(set(entry["tags"])))
            self.assertTrue(all(TAG_PATTERN.fullmatch(tag) for tag in entry["tags"]))

    def test_meta_uses_unified_shape(self) -> None:
        fixture = StandaloneTestBlueprint(
            slug="preview_runtime_showcase",
            title="Preview Runtime Showcase",
            category="Runtime",
            summary="Summary",
            tags=("preview", "runtime"),
            project_root="tests/test_blueprints/preview_runtime_showcase",
            build_command=("lake", "build"),
            generate_command=("lake", "exe", "blueprint-gen", "--output", "{output_dir}"),
            panel_regression_script=None,
            browser_tests_path=None,
        )
        self.assertEqual(
            fixture.meta,
            {
                "slug": "preview_runtime_showcase",
                "title": "Preview Runtime Showcase",
                "category": "Runtime",
                "summary": "Summary",
                "tags": ["preview", "runtime"],
                "kind": "standalone_project",
            },
        )


if __name__ == "__main__":
    unittest.main()
