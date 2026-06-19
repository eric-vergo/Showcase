from __future__ import annotations

from pathlib import Path
import unittest

from tests.preview_runtime_api import (
    BLUEPRINT_SRC,
    RUNTIME_BOOTSTRAP_JS,
    blueprint_js_files,
    blueprint_js_source,
    js_object_methods,
    manual_bundled_helper_methods,
    manual_stable_api_methods,
)

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
INTERNAL_ONLY_HELPERS = {
    "bindCloseOnce",
    "bindDismissHandlers",
    "bindHoverablePanelLifetime",
    "bindPanelRepositioner",
    "bindTemplatePreview",
    "pointerWithinPanel",
    "positionAnchoredPanel",
    "readHtml",
    "readBlueprintManifestEntry",
    "readBlueprintHtmlCacheEntry",
    "renderHtmlInto",
    "resetPanelPosition",
    "shouldKeepOpen",
}


class PreviewRuntimeApiDocsTests(unittest.TestCase):
    def test_manual_stable_api_table_matches_runtime_source(self) -> None:
        runtime = blueprint_js_source()
        manual = (PACKAGE_ROOT / "doc" / "MANUAL.md").read_text(encoding="utf-8")

        source_methods = js_object_methods(runtime, "stableCustomClientApi")
        documented_methods = manual_stable_api_methods(manual)

        self.assertEqual(documented_methods, source_methods)
        self.assertIn("`window.VersoBlueprint.onRenderReady(callback)`", manual)
        self.assertIn("namespace.onRenderReady = onRenderReady", runtime)

    def test_manual_stable_api_table_excludes_bundled_feature_helpers(self) -> None:
        runtime = blueprint_js_source()
        manual = (PACKAGE_ROOT / "doc" / "MANUAL.md").read_text(encoding="utf-8")

        documented_methods = manual_stable_api_methods(manual)
        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(documented_methods & helper_methods)

    def test_manual_bundled_helper_table_matches_runtime_source(self) -> None:
        runtime = blueprint_js_source()
        manual = (PACKAGE_ROOT / "doc" / "MANUAL.md").read_text(encoding="utf-8")

        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")
        documented_methods = manual_bundled_helper_methods(manual)

        self.assertEqual(documented_methods, helper_methods)

    def test_runtime_api_tiers_remain_disjoint(self) -> None:
        runtime = blueprint_js_source()

        source_methods = js_object_methods(runtime, "stableCustomClientApi")
        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(source_methods & helper_methods)

    def test_internal_runtime_helpers_are_not_exported(self) -> None:
        runtime = blueprint_js_source()

        source_methods = js_object_methods(runtime, "stableCustomClientApi")
        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(INTERNAL_ONLY_HELPERS & source_methods)
        self.assertFalse(INTERNAL_ONLY_HELPERS & helper_methods)

    def test_preview_runtime_state_stays_runtime_local(self) -> None:
        runtime = blueprint_js_source()

        self.assertIn("const previewHydrators = new Map();", runtime)
        self.assertNotIn("window.bpPreviewHydrators", runtime)
        self.assertNotIn("window.bpPreviewTrace", runtime)

    def test_slide_runtime_uses_verso_blueprint_namespace(self) -> None:
        runtime = (BLUEPRINT_SRC / "Slides" / "blueprint-slides.js").read_text(
            encoding="utf-8"
        )

        self.assertIn("namespace.slides = slideRuntime", runtime)
        self.assertIn("slideRuntime.hydrate = hydrateWhenReady", runtime)
        self.assertNotIn("window.bpSlideNodeRuntime", runtime)
        self.assertNotIn("window.bpSlideNodeRuntimeConfig", runtime)

    def test_feature_js_uses_render_ready_instead_of_direct_runtime_reads(self) -> None:
        direct_runtime_reads: list[str] = []
        missing_ready_callbacks: list[str] = []

        for path in blueprint_js_files():
            relative_path = path.relative_to(BLUEPRINT_SRC)
            if relative_path in RUNTIME_BOOTSTRAP_JS:
                continue
            source = path.read_text(encoding="utf-8")
            display_path = relative_path.as_posix()
            if "window.VersoBlueprint.render" in source:
                direct_runtime_reads.append(display_path)
            if (
                "window.VersoBlueprint" in source
                and "window.VersoBlueprint.onRenderReady(" not in source
            ):
                missing_ready_callbacks.append(display_path)

        self.assertEqual([], direct_runtime_reads)
        self.assertEqual([], missing_ready_callbacks)


if __name__ == "__main__":
    unittest.main()
