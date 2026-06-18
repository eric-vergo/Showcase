from __future__ import annotations

from pathlib import Path
import re
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[2]


def _js_object_methods(source: str, name: str) -> set[str]:
    marker = f"  const {name} = {{"
    start = source.index(marker) + len(marker)
    end = source.index("\n  };", start)
    body = source[start:end]
    return set(re.findall(r"^\s+([A-Za-z][A-Za-z0-9_]*):", body, flags=re.MULTILINE))


def _manual_stable_api_methods(source: str) -> set[str]:
    start_marker = "Stable custom-client entrypoints:"
    end_marker = "Blueprint's bundled graph"
    start = source.index(start_marker) + len(start_marker)
    end = source.index(end_marker, start)
    section = source[start:end]
    return set(re.findall(r"`api\.([A-Za-z][A-Za-z0-9_]*)\(", section))


class PreviewRuntimeApiDocsTests(unittest.TestCase):
    def test_manual_stable_api_table_matches_runtime_source(self) -> None:
        runtime = (
            PACKAGE_ROOT / "src" / "VersoBlueprint" / "Commands" / "preview-runtime.js"
        ).read_text(encoding="utf-8")
        manual = (PACKAGE_ROOT / "doc" / "MANUAL.md").read_text(encoding="utf-8")

        source_methods = _js_object_methods(runtime, "stableCustomClientApi")
        documented_methods = _manual_stable_api_methods(manual)

        self.assertEqual(documented_methods, source_methods)
        self.assertIn("`window.VersoBlueprint.onRenderReady(callback)`", manual)
        self.assertIn("namespace.onRenderReady = onRenderReady", runtime)

    def test_manual_stable_api_table_excludes_bundled_feature_helpers(self) -> None:
        runtime = (
            PACKAGE_ROOT / "src" / "VersoBlueprint" / "Commands" / "preview-runtime.js"
        ).read_text(encoding="utf-8")
        manual = (PACKAGE_ROOT / "doc" / "MANUAL.md").read_text(encoding="utf-8")

        documented_methods = _manual_stable_api_methods(manual)
        helper_methods = _js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(documented_methods & helper_methods)


if __name__ == "__main__":
    unittest.main()
