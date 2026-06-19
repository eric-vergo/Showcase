from __future__ import annotations

from pathlib import Path
import re
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
BLUEPRINT_SRC = PACKAGE_ROOT / "src" / "VersoBlueprint"
RUNTIME_BOOTSTRAP_JS = {
    Path("Commands/preview-runtime.js"),
    Path("Commands/preview-ready.js"),
}
EXPECTED_BUNDLED_HELPERS = {
    "bindHoverablePanelLifetime",
    "bindTemplatePreviewRoots",
    "collectPreviewTemplates",
    "configureCloseButton",
    "createPanelController",
    "escapeHtml",
    "hidePanelContent",
    "pointerWithinPanel",
    "positionAnchoredPanel",
    "previewDebug",
    "previewDebugLabel",
    "readPanelBehavior",
    "registerPreviewHydrator",
    "renderHtmlInto",
    "resetPanelPosition",
    "setPreviewHeaderLink",
    "shouldKeepOpen",
    "showPanelContent",
}


def _blueprint_js_files() -> list[Path]:
    return sorted(BLUEPRINT_SRC.rglob("*.js"))


def _blueprint_js_source() -> str:
    return "\n\n".join(
        path.read_text(encoding="utf-8")
        for path in _blueprint_js_files()
    )


def _find_balanced_js_object_body(source: str, name: str) -> str:
    match = re.search(rf"\bconst\s+{re.escape(name)}\s*=\s*{{", source)
    if match is None:
        raise AssertionError(f"missing JavaScript object literal {name}")
    depth = 1
    pos = match.end()
    while pos < len(source):
        char = source[pos]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[match.end():pos]
        pos += 1
    raise AssertionError(f"unterminated JavaScript object literal {name}")


def _js_object_methods(source: str, name: str) -> set[str]:
    body = _find_balanced_js_object_body(source, name)
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
        runtime = _blueprint_js_source()
        manual = (PACKAGE_ROOT / "doc" / "MANUAL.md").read_text(encoding="utf-8")

        source_methods = _js_object_methods(runtime, "stableCustomClientApi")
        documented_methods = _manual_stable_api_methods(manual)

        self.assertEqual(documented_methods, source_methods)
        self.assertIn("`window.VersoBlueprint.onRenderReady(callback)`", manual)
        self.assertIn("namespace.onRenderReady = onRenderReady", runtime)

    def test_manual_stable_api_table_excludes_bundled_feature_helpers(self) -> None:
        runtime = _blueprint_js_source()
        manual = (PACKAGE_ROOT / "doc" / "MANUAL.md").read_text(encoding="utf-8")

        documented_methods = _manual_stable_api_methods(manual)
        helper_methods = _js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(documented_methods & helper_methods)

    def test_runtime_api_tiers_remain_disjoint(self) -> None:
        runtime = _blueprint_js_source()

        source_methods = _js_object_methods(runtime, "stableCustomClientApi")
        helper_methods = _js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(source_methods & helper_methods)

    def test_bundled_feature_helper_surface_is_intentional(self) -> None:
        runtime = _blueprint_js_source()

        helper_methods = _js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertEqual(EXPECTED_BUNDLED_HELPERS, helper_methods)

    def test_hydrator_registry_stays_runtime_local(self) -> None:
        runtime = _blueprint_js_source()

        self.assertIn("const previewHydrators = new Map();", runtime)
        self.assertNotIn("window.bpPreviewHydrators", runtime)

    def test_feature_js_uses_render_ready_instead_of_direct_runtime_reads(self) -> None:
        direct_runtime_reads: list[str] = []
        missing_ready_callbacks: list[str] = []

        for path in _blueprint_js_files():
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
