from __future__ import annotations

from pathlib import Path
import unittest

from tests.preview_runtime_api import (
    BLUEPRINT_SRC,
    RUNTIME_BOOTSTRAP_JS,
    blueprint_js_files,
    blueprint_js_source,
    documented_bundled_helper_methods,
    documented_stable_api_methods,
    esm_named_exports,
    js_object_keys,
    js_object_methods,
)

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
API_DOC = PACKAGE_ROOT / "doc" / "API.md"
DESIGN_RATIONALE = PACKAGE_ROOT / "doc" / "DESIGN_RATIONALE.md"
INTERNAL_ONLY_HELPERS = {
    "bindCloseOnce",
    "bindDismissHandlers",
    "bindHoverablePanelLifetime",
    "bindPanelRepositioner",
    "bindTemplatePreview",
    "bindTemplatePreviewDescriptor",
    "bindTemplatePreviewDescriptors",
    "pointerWithinPanel",
    "positionAnchoredPanel",
    "readHtml",
    "readPanelBehavior",
    "readBlueprintManifestEntry",
    "readBlueprintHtmlCacheEntry",
    "renderHtmlInto",
    "resetPanelPosition",
    "shouldKeepOpen",
}
PREVIEW_ESM_EXTRA_EXPORTS = {
    "currentRenderApi",
    "getRenderApi",
    "normalizeGraphData",
    "onRenderReady",
    "ready",
    "version",
}
GRAPH_CORE_HELPERS = {
    "dataUrl",
    "graphCanvasFor",
    "readGraphJsonScript",
    "graphFallbackVariants",
    "normalizeGraphData",
    "graphsFromManifest",
    "getGraphData",
    "getGraphVariants",
    "loadJson",
    "loadManifestGraphs",
    "loadGraphs",
}
GRAPH_CORE_IMPLEMENTATION_HELPERS = {
    "dataUrl",
    "graphCanvasFor",
    "readGraphJsonScript",
    "graphFallbackVariants",
    "normalizeGraphData",
    "graphsFromManifest",
    "getGraphData",
    "getGraphVariants",
    "loadJson",
}
PREVIEW_CORE_HELPERS = {
    "dataUrl",
    "manifestUrl",
    "htmlCacheUrl",
    "graphApiModuleUrl",
    "previewApiModuleUrl",
    "previewKey",
    "statementPreviewKey",
}
GRAPH_RUNTIME_CORE_HELPERS = {
    "debounce",
    "normalizeGraphOptions",
    "graphPackAttr",
    "graphOptionsKey",
    "readPreviewBehaviorDefaults",
    "layoutGraphCanvas",
    "load",
    "graphNodeLabel",
    "graphNodeId",
    "ensureGraphBlockState",
    "rememberGraphLayoutMeasurements",
    "resizeRenderedGraphToCanvas",
    "resetGraphvizForVariant",
    "makeGroupPanelPositioner",
}


class PreviewRuntimeApiDocsTests(unittest.TestCase):
    def test_api_stable_api_table_matches_runtime_source(self) -> None:
        runtime = blueprint_js_source()
        api_doc = API_DOC.read_text(encoding="utf-8")

        source_methods = js_object_methods(runtime, "stableCustomClientApi")
        documented_methods = documented_stable_api_methods(api_doc)

        self.assertEqual(documented_methods, source_methods)
        self.assertIn("`window.VersoBlueprint.onRenderReady(callback)`", api_doc)
        self.assertIn("namespace.onRenderReady = onRenderReady", runtime)

    def test_api_stable_api_table_excludes_bundled_feature_helpers(self) -> None:
        runtime = blueprint_js_source()
        api_doc = API_DOC.read_text(encoding="utf-8")

        documented_methods = documented_stable_api_methods(api_doc)
        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(documented_methods & helper_methods)

    def test_api_bundled_helper_table_matches_runtime_source(self) -> None:
        runtime = blueprint_js_source()
        api_doc = API_DOC.read_text(encoding="utf-8")

        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")
        documented_methods = documented_bundled_helper_methods(api_doc)

        self.assertEqual(documented_methods, helper_methods)

    def test_runtime_api_tiers_remain_disjoint(self) -> None:
        runtime = blueprint_js_source()

        source_methods = js_object_methods(runtime, "stableCustomClientApi")
        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(source_methods & helper_methods)

    def test_preview_esm_exports_stable_custom_client_api(self) -> None:
        runtime = blueprint_js_source()
        source = (BLUEPRINT_SRC / "blueprint-preview-api.mjs").read_text(encoding="utf-8")

        stable_methods = js_object_methods(runtime, "stableCustomClientApi")
        named_exports = esm_named_exports(source)
        default_methods = js_object_keys(source, "previewApi")
        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertLessEqual(stable_methods, named_exports)
        self.assertLessEqual(stable_methods, default_methods)
        self.assertEqual(named_exports, stable_methods | PREVIEW_ESM_EXTRA_EXPORTS)
        self.assertEqual(default_methods, stable_methods | PREVIEW_ESM_EXTRA_EXPORTS)
        self.assertFalse(named_exports & helper_methods)
        self.assertFalse(default_methods & helper_methods)

    def test_internal_runtime_helpers_are_not_exported(self) -> None:
        runtime = blueprint_js_source()

        source_methods = js_object_methods(runtime, "stableCustomClientApi")
        helper_methods = js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(INTERNAL_ONLY_HELPERS & source_methods)
        self.assertFalse(INTERNAL_ONLY_HELPERS & helper_methods)

    def test_template_preview_descriptors_are_runtime_bound(self) -> None:
        runtime = blueprint_js_source()

        self.assertIn("function bindTemplatePreviewDescriptor(root)", runtime)
        self.assertIn("function bindTemplatePreviewDescriptors(root)", runtime)
        self.assertIn('const selector = "[data-bp-template-preview-root]";', runtime)
        self.assertIn("bindTemplatePreviewDescriptors(document);", runtime)
        self.assertNotIn("bindTemplatePreviewRoots", runtime)

    def test_preview_runtime_state_stays_runtime_local(self) -> None:
        runtime = blueprint_js_source()

        self.assertIn("const previewHydrators = new Map();", runtime)
        self.assertNotIn("window.bpPreviewHydrators", runtime)
        self.assertNotIn("window.bpPreviewTrace", runtime)

    def test_preview_runtime_component_boundaries_are_named(self) -> None:
        runtime = blueprint_js_source()

        for marker in (
            "Runtime-local diagnostics and page-local template capture.",
            "Generated-data URL helpers and graph-core delegation.",
            "Manifest/cache status, loading, and diagnostics.",
            "Preview resolution joins semantic manifest entries with opaque body fragments.",
            "Canonical generated-node rendering.",
            "Bundled preview lifecycle helpers.",
            "Bundled preview surface, panel, and content helpers.",
            "Template preview binding adapts the shared helpers to concrete surfaces.",
            "API assembly and readiness synchronization.",
        ):
            self.assertIn(marker, runtime)

    def test_preview_runtime_helpers_live_in_private_chunks(self) -> None:
        common = (BLUEPRINT_SRC / "Commands" / "Common.lean").read_text(
            encoding="utf-8"
        )
        base = (BLUEPRINT_SRC / "Commands" / "preview-runtime-base.mjs").read_text(
            encoding="utf-8"
        )
        data = (BLUEPRINT_SRC / "Commands" / "preview-runtime-data.mjs").read_text(
            encoding="utf-8"
        )
        render = (BLUEPRINT_SRC / "Commands" / "preview-runtime-render.mjs").read_text(
            encoding="utf-8"
        )
        hydration = (
            BLUEPRINT_SRC / "Commands" / "preview-runtime-hydration.mjs"
        ).read_text(encoding="utf-8")
        lifecycle = (
            BLUEPRINT_SRC / "Commands" / "preview-runtime-lifecycle.mjs"
        ).read_text(encoding="utf-8")
        surface = (BLUEPRINT_SRC / "Commands" / "preview-runtime-surface.mjs").read_text(
            encoding="utf-8"
        )
        template = (
            BLUEPRINT_SRC / "Commands" / "preview-runtime-template.mjs"
        ).read_text(encoding="utf-8")
        api = (BLUEPRINT_SRC / "Commands" / "preview-runtime-api.mjs").read_text(
            encoding="utf-8"
        )

        self.assertIn('include_str "preview-runtime-base.mjs"', common)
        self.assertIn('include_str "preview-runtime-data.mjs"', common)
        self.assertIn('include_str "preview-runtime-render.mjs"', common)
        self.assertIn('include_str "preview-runtime-hydration.mjs"', common)
        self.assertIn('include_str "preview-runtime-lifecycle.mjs"', common)
        self.assertIn('include_str "preview-runtime-surface.mjs"', common)
        self.assertIn('include_str "preview-runtime-template.mjs"', common)
        self.assertIn('include_str "preview-runtime-api.mjs"', common)
        self.assertIn('include_str "../blueprint-preview-core.mjs"', common)
        self.assertIn("private def previewRuntimeFragments : List String", common)
        self.assertIn('String.intercalate "\\n" previewRuntimeFragments', common)
        self.assertIn("installPreviewRuntimeApi();", common)
        self.assertIn("function collectPreviewTemplates(root, selector, keyAttr)", base)
        self.assertIn("function readHtml(entry)", base)
        self.assertIn("function escapeHtml(text)", base)
        self.assertIn("export const previewRuntimeBase = {", base)
        self.assertIn("function loadBlueprintStore(store)", data)
        self.assertIn("function previewKey(label, facet)", data)
        self.assertNotIn("function blueprintGraphApi()", data)
        self.assertNotIn("function callBlueprintGraphCore(name, args, fallback)", data)
        self.assertIn("function callRuntimeGraphCore(name, args, fallback)", common)
        self.assertIn("export const previewRuntimeData = {", data)
        self.assertIn("function readBlueprintManifestStatus()", data)
        self.assertIn("async function resolveBlueprintPreview(previewKey)", render)
        self.assertIn("function renderHtmlInto(target, html, options)", render)
        self.assertIn("async function resolveCanonicalBlueprintPreview(previewKey)", render)
        self.assertIn("export const previewRuntimeRender = {", render)
        self.assertIn("function hydrateRenderedPreview(root, options)", hydration)
        self.assertIn("function renderBlueprintMath(root)", hydration)
        self.assertIn("function registerPreviewHydrator(name, fn)", hydration)
        self.assertIn("function setTemplatePreviewDescriptorBinder(fn)", hydration)
        self.assertIn("export const previewRuntimeHydration = {", hydration)
        self.assertIn("function bindDismissHandlers(options)", lifecycle)
        self.assertIn("function bindPreviewTriggers(options)", lifecycle)
        self.assertIn("function bindAnchoredPopover(options)", lifecycle)
        self.assertIn('from "./preview-runtime-base.mjs";', lifecycle)
        self.assertNotIn('from "./preview-runtime-surface.mjs";', lifecycle)
        self.assertIn("export const previewRuntimeLifecycle = {", lifecycle)
        self.assertIn("function createPreviewSurface(options)", surface)
        self.assertIn("async function renderPreviewIntoSurface(surface, previewKey, options)", surface)
        self.assertIn("function previewMessageHtml(options)", surface)
        self.assertIn("export const previewRuntimeSurface = {", surface)
        self.assertIn("function bindTemplatePreview(options)", template)
        self.assertIn("function bindTemplatePreviewDescriptor(root)", template)
        self.assertIn("export const previewRuntimeTemplate = {", template)
        self.assertIn(
            "setTemplatePreviewDescriptorBinder(bindTemplatePreviewDescriptors)",
            template,
        )
        self.assertIn("const stableCustomClientApi = {", api)
        self.assertIn("export function installPreviewRuntimeApi()", api)
        self.assertIn("function onRenderReady(fn)", api)
        for helper in (
            "function loadBlueprintStore(store)",
            "function previewKey(label, facet)",
            "async function resolveBlueprintPreview(previewKey)",
            "function renderBlueprintMath(root)",
            "function createPreviewSurface(options)",
            "function bindTemplatePreview(options)",
        ):
            self.assertNotIn(helper, api)

    def test_design_rationale_explains_html_cache_boundary(self) -> None:
        design = DESIGN_RATIONALE.read_text(encoding="utf-8")

        self.assertIn("### Body Fragments vs Full Node Wrappers", design)
        self.assertIn(
            "The rendered-fragment cache should not grow into a second node-wrapper cache",
            design,
        )
        self.assertIn("renderCanonicalPreviewInto", design)
        self.assertIn("manifestEntry.href", design)

    def test_slide_runtime_uses_verso_blueprint_namespace(self) -> None:
        runtime = (BLUEPRINT_SRC / "Slides" / "blueprint-slides.mjs").read_text(
            encoding="utf-8"
        )

        self.assertIn("namespace.slides = slideRuntime", runtime)
        self.assertIn("slideRuntime.hydrate = hydrateWhenReady", runtime)
        self.assertIn("export function installBlueprintSlides()", runtime)
        self.assertNotIn("window.bpSlideNodeRuntime", runtime)
        self.assertNotIn("window.bpSlideNodeRuntimeConfig", runtime)

    def test_graph_runtime_uses_structured_variants_only(self) -> None:
        runtime = (BLUEPRINT_SRC / "Commands" / "graph.mjs").read_text(
            encoding="utf-8"
        )

        self.assertIn("readPublicGraphVariants(previewUtils, graphBlock)", runtime)
        self.assertIn("previewUtils.getGraphVariants(root)", runtime)
        self.assertIn("export function startGraphRuntime(previewUtils)", runtime)
        self.assertNotIn("legacyGraphVariants", runtime)

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

    def test_graph_helpers_are_owned_by_graph_core(self) -> None:
        core = (BLUEPRINT_SRC / "blueprint-graph-core.mjs").read_text(encoding="utf-8")
        graph_esm = (BLUEPRINT_SRC / "blueprint-graph-api.mjs").read_text(encoding="utf-8")
        runtime_data = (BLUEPRINT_SRC / "Commands" / "preview-runtime-data.mjs").read_text(
            encoding="utf-8"
        )
        common = (BLUEPRINT_SRC / "Commands" / "Common.lean").read_text(
            encoding="utf-8"
        )
        runtime = (BLUEPRINT_SRC / "Commands" / "preview-runtime-api.mjs").read_text(
            encoding="utf-8"
        )

        self.assertIn('from "./blueprint-graph-core.mjs";', graph_esm)
        self.assertIn('from "../blueprint-graph-core.mjs";', runtime_data)
        self.assertIn("callRuntimeGraphCore", common)
        self.assertIn("VersoBlueprint.__private", common)
        self.assertNotIn("VersoBlueprintGraphCore", common)
        self.assertIn("namespace.graphCore = existingCore", core)
        self.assertNotIn("VersoBlueprintGraphCore", core)
        self.assertNotIn("callBlueprintGraphCore", runtime_data)
        self.assertNotIn("callBlueprintGraphApi", runtime_data)
        self.assertNotIn("window.bpGraphApi", runtime_data)
        for helper in GRAPH_CORE_HELPERS:
            self.assertIn(f"function {helper}", core)
            self.assertNotIn(f"function {helper}", graph_esm)
        for helper in GRAPH_CORE_IMPLEMENTATION_HELPERS:
            self.assertNotIn(f"function {helper}", runtime_data)
            self.assertNotIn(f"function {helper}", runtime)

    def test_preview_helpers_are_owned_by_preview_core(self) -> None:
        core = (BLUEPRINT_SRC / "blueprint-preview-core.mjs").read_text(encoding="utf-8")
        preview_esm = (BLUEPRINT_SRC / "blueprint-preview-api.mjs").read_text(
            encoding="utf-8"
        )
        runtime_data = (BLUEPRINT_SRC / "Commands" / "preview-runtime-data.mjs").read_text(
            encoding="utf-8"
        )
        preview_manifest = (BLUEPRINT_SRC / "PreviewManifest.lean").read_text(
            encoding="utf-8"
        )

        self.assertIn('from "./blueprint-preview-core.mjs";', preview_esm)
        self.assertIn('from "../blueprint-preview-core.mjs";', runtime_data)
        self.assertIn('include_str "blueprint-preview-core.mjs"', preview_manifest)
        self.assertIn("IO.FS.writeFile (dataDir / previewCoreModuleFilename)", preview_manifest)
        for helper in PREVIEW_CORE_HELPERS:
            self.assertIn(f"function {helper}", core)
        self.assertNotIn("const trimmedLabel = typeof label", preview_esm)
        self.assertNotIn("const trimmedLabel = typeof label", runtime_data)
        self.assertIn("namespace.previewCore = existingCore", core)
        self.assertNotIn("VersoBlueprintPreviewCore", core)

    def test_graph_runtime_helpers_live_in_private_graph_chunk(self) -> None:
        graph_core = (BLUEPRINT_SRC / "Commands" / "graph-runtime-core.mjs").read_text(
            encoding="utf-8"
        )
        graph_runtime = (BLUEPRINT_SRC / "Commands" / "graph.mjs").read_text(
            encoding="utf-8"
        )
        graph_lean = (BLUEPRINT_SRC / "Commands" / "Graph.lean").read_text(
            encoding="utf-8"
        )

        self.assertIn('include_str "graph-runtime-core.mjs"', graph_lean)
        self.assertIn("esmModuleToClassicScript graphRuntimeCoreModuleMjs", graph_lean)
        self.assertIn("include_str \"graph.mjs\"", graph_lean)
        self.assertIn("startGraphRuntime(previewUtils)", graph_lean)
        self.assertIn("export const graphRuntimeCore = {", graph_core)
        self.assertNotIn("globalScope.VersoBlueprintGraphRuntimeCore", graph_core)
        self.assertNotIn("globalScope.VersoBlueprintGraphRuntimeCore", graph_lean)
        self.assertIn("privateNamespace.graphRuntimeCore = existingCore", graph_lean)
        self.assertIn('from "./graph-runtime-core.mjs";', graph_runtime)
        for helper in GRAPH_RUNTIME_CORE_HELPERS:
            self.assertIn(f"function {helper}", graph_core)
            self.assertNotIn(f"function {helper}", graph_runtime)
        self.assertNotIn("VersoBlueprintGraphRuntimeCore", graph_runtime)


if __name__ == "__main__":
    unittest.main()
