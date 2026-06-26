import {
  getGraphData,
  getGraphVariants,
  graphsFromManifest,
  loadGraphs,
  loadManifestGraphs,
  normalizeGraphData
} from "./blueprint-graph-api.mjs";
import { callDefaultApi, callDefaultApiSync, createDefaultApiHandle, createPreviewUrlApi, fallbackStoreStatus, optionsWithDefaultDataBaseUrl, version } from "./blueprint-api-common.mjs";
import { createPreviewRuntimeApi } from "./Commands/preview-runtime-api.mjs";

/**
 * Render-capable Blueprint preview API for custom browser clients.
 *
 * This module is emitted as `-verso-data/api/preview.mjs` in generated sites.
 * It composes the data API with DOM rendering, hydration, canonical-node
 * insertion, and call-scoped external-markup fallback renderers.
 *
 * @module blueprint-preview-api
 */

/** @import { BlueprintDataApiOptions, BlueprintPreviewOptions, BlueprintPreviewApi, BlueprintStoreStatus, BlueprintManifestEntry, BlueprintHtmlCacheEntry, BlueprintGraphData, BlueprintGraphVariant, BlueprintPreviewResult, BlueprintCanonicalPreviewResult, BlueprintRenderNodeRequest, BlueprintRenderNodeResult } from "./blueprint-api-types.mjs" */

export {
  getGraphData,
  getGraphVariants,
  graphsFromManifest,
  loadGraphs,
  loadManifestGraphs,
  normalizeGraphData
};

export { version };

const moduleUrl = import.meta.url;
const previewUrls = createPreviewUrlApi(moduleUrl);

/**
 * Create an isolated render-capable preview API instance.
 *
 * @param {BlueprintPreviewOptions} [options] Loader, hydration, and generated-data options.
 * @returns {BlueprintPreviewApi} Preview API instance.
 */
export function createPreview(options) {
  return createPreviewRuntimeApi(optionsWithDefaultDataBaseUrl(options, moduleUrl));
}

const defaultRenderHandle = createDefaultApiHandle(createPreview);

/**
 * Return the module-level preview API if it has already been created.
 *
 * @returns {BlueprintPreviewApi | null}
 */
export function currentRenderApi() {
  return defaultRenderHandle.currentApi();
}

/**
 * Return the module-level preview API, creating it on first use.
 *
 * @returns {Promise<BlueprintPreviewApi>}
 */
export function getRenderApi() {
  return defaultRenderHandle.getApi();
}

/**
 * Promise for the default preview API instance.
 *
 * @type {Promise<BlueprintPreviewApi>}
 */
export const ready = defaultRenderHandle.ready;

/**
 * Resolve a generated data filename under `-verso-data/`.
 *
 * @param {string} filename Generated data filename.
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export function dataUrl(filename, baseUrl) {
  return previewUrls.dataUrl(filename, baseUrl);
}

/**
 * Resolve `blueprint-manifest.json`.
 *
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export function manifestUrl(baseUrl) {
  return previewUrls.manifestUrl(baseUrl);
}

/**
 * Resolve `blueprint-html-cache.json`.
 *
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export function htmlCacheUrl(baseUrl) {
  return previewUrls.htmlCacheUrl(baseUrl);
}

/**
 * Resolve the generated graph API module URL.
 *
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export function graphApiModuleUrl(baseUrl) {
  return previewUrls.graphApiModuleUrl(baseUrl);
}

/**
 * Resolve the generated data API module URL.
 *
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export function dataApiModuleUrl(baseUrl) {
  return previewUrls.dataApiModuleUrl(baseUrl);
}

/**
 * Resolve the generated preview API module URL.
 *
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export function previewApiModuleUrl(baseUrl) {
  return previewUrls.previewApiModuleUrl(baseUrl);
}

/**
 * Build the preview key for a Blueprint label and facet.
 *
 * @param {string} label Blueprint label.
 * @param {string} [facet] Preview facet. Defaults to `statement`.
 * @returns {string}
 */
export function previewKey(label, facet) {
  return previewUrls.previewKey(label, facet);
}

/**
 * Build the statement preview key for a Blueprint label.
 *
 * @param {string} label Blueprint label.
 * @returns {string}
 */
export function statementPreviewKey(label) {
  return previewUrls.statementPreviewKey(label);
}

/**
 * Read cached manifest loader status without triggering a load.
 *
 * @returns {BlueprintStoreStatus}
 */
export function readManifestStatus() {
  return callDefaultApiSync(
    defaultRenderHandle.readDefaultApi,
    "readManifestStatus",
    function () { return fallbackStoreStatus(manifestUrl()); },
    []
  );
}

/**
 * Read cached HTML-cache loader status without triggering a load.
 *
 * @returns {BlueprintStoreStatus}
 */
export function readHtmlCacheStatus() {
  return callDefaultApiSync(
    defaultRenderHandle.readDefaultApi,
    "readHtmlCacheStatus",
    function () { return fallbackStoreStatus(htmlCacheUrl()); },
    []
  );
}

/**
 * Load and decode the Blueprint manifest.
 *
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<Map<string, BlueprintManifestEntry>>}
 */
export function loadManifest(options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadManifest", [options]);
}

/**
 * Load and decode the rendered HTML fragment cache.
 *
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<Map<string, BlueprintHtmlCacheEntry>>}
 */
export function loadHtmlCache(options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadHtmlCache", [options]);
}

/**
 * Load a single manifest entry by key.
 *
 * @param {string} key Manifest key.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintManifestEntry | null>}
 */
export function loadManifestEntry(key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadManifestEntry", [key, options]);
}

/**
 * Load a single HTML-cache entry by key.
 *
 * @param {string} key HTML cache key.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintHtmlCacheEntry | null>}
 */
export function loadHtmlCacheEntry(key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadHtmlCacheEntry", [key, options]);
}

/**
 * Resolve a preview key against the manifest and HTML cache.
 *
 * @param {string} key Preview key such as `label--statement`.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintPreviewResult>}
 */
export function resolvePreview(key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "resolvePreview", [key, options]);
}

/**
 * Render a cached preview fragment into a target element.
 *
 * @param {Element} element Target element to replace with the resolved fragment.
 * @param {string} key Preview key such as `label--statement`.
 * @param {BlueprintPreviewOptions} [options] Optional render and load overrides.
 * @returns {Promise<BlueprintPreviewResult>}
 */
export function renderPreviewInto(element, key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "renderPreviewInto", [element, key, options]);
}

/**
 * Resolve a preview key to its canonical generated-node shell.
 *
 * @param {string} key Preview key such as `label--statement`.
 * @param {BlueprintPreviewOptions} [options] Optional render and load overrides.
 * @returns {Promise<BlueprintCanonicalPreviewResult>}
 */
export function resolveCanonicalPreview(key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "resolveCanonicalPreview", [key, options]);
}

/**
 * Render the canonical generated-node shell for a preview key into a target.
 *
 * @param {Element} element Target element to replace with the canonical node.
 * @param {string} key Preview key such as `label--statement`.
 * @param {BlueprintPreviewOptions} [options] Optional render and load overrides.
 * @returns {Promise<BlueprintCanonicalPreviewResult>}
 */
export function renderCanonicalPreviewInto(element, key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "renderCanonicalPreviewInto", [element, key, options]);
}

/**
 * Render a Blueprint label, preferring the native rendered preview and falling
 * back to call-scoped external-markup renderers when needed.
 *
 * @param {Element} element Target element to replace with the rendered node.
 * @param {string | BlueprintRenderNodeRequest} request Label or detailed render request.
 * @param {BlueprintPreviewOptions} [options] Optional render and load overrides.
 * @returns {Promise<BlueprintRenderNodeResult>}
 */
export function renderNode(element, request, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "renderNode", [element, request, options]);
}

/**
 * Hydrate Blueprint-specific behavior inside an already-rendered subtree.
 *
 * @param {Element} element Root element to hydrate.
 * @param {BlueprintPreviewOptions} [options] Hydration options.
 * @returns {Promise<boolean>}
 */
export function hydrate(element, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "hydrate", [element, options]);
}

const previewApi = {
  version,
  dataUrl,
  manifestUrl,
  htmlCacheUrl,
  graphApiModuleUrl,
  dataApiModuleUrl,
  previewApiModuleUrl,
  createPreview,
  currentRenderApi,
  getRenderApi,
  ready,
  loadManifest,
  readManifestStatus,
  loadManifestEntry,
  loadHtmlCache,
  readHtmlCacheStatus,
  loadHtmlCacheEntry,
  getGraphData,
  getGraphVariants,
  graphsFromManifest,
  loadManifestGraphs,
  loadGraphs,
  normalizeGraphData,
  previewKey,
  statementPreviewKey,
  resolvePreview,
  renderPreviewInto,
  resolveCanonicalPreview,
  renderCanonicalPreviewInto,
  renderNode,
  hydrate
};

export default previewApi;
