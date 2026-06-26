import { callDefaultApi, callDefaultApiSync, createDefaultApiHandle, createPreviewUrlApi, fallbackStoreStatus, optionsWithDefaultDataBaseUrl, version } from "./blueprint-api-common.mjs";
import { createBlueprintDataApi } from "./Commands/preview-runtime-data.mjs";

/**
 * Generated-data API for custom Blueprint clients.
 *
 * This module is emitted as `-verso-data/api/data.mjs` in generated sites. It
 * exposes manifest, HTML cache, graph, and URL helpers without installing any
 * page-global render hook.
 *
 * @module blueprint-data-api
 */

/** @import { BlueprintDataApiOptions, BlueprintDataApi, BlueprintStoreStatus, BlueprintManifestEntry, BlueprintHtmlCacheEntry, BlueprintGraphData, BlueprintGraphVariant } from "./blueprint-api-types.mjs" */

export { version };

const moduleUrl = import.meta.url;
const previewUrls = createPreviewUrlApi(moduleUrl);

/**
 * Create an isolated data API instance.
 *
 * Use this when a custom client wants explicit loaders and cache state instead
 * of the module-level default singleton.
 *
 * @param {BlueprintDataApiOptions} [options] Loader and generated-data base URL options.
 * @returns {BlueprintDataApi} Data API instance.
 */
export function createPreviewData(options) {
  return createBlueprintDataApi(optionsWithDefaultDataBaseUrl(options, moduleUrl));
}

const defaultDataHandle = createDefaultApiHandle(createPreviewData);

/**
 * Return the module-level data API if it has already been created.
 *
 * @returns {BlueprintDataApi | null}
 */
export function currentDataApi() {
  return defaultDataHandle.currentApi();
}

/**
 * Return the module-level data API, creating it on first use.
 *
 * @returns {Promise<BlueprintDataApi>}
 */
export function getDataApi() {
  return defaultDataHandle.getApi();
}

/**
 * Promise for the default data API instance.
 *
 * @type {Promise<BlueprintDataApi>}
 */
export const ready = defaultDataHandle.ready;

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
    defaultDataHandle.readDefaultApi,
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
    defaultDataHandle.readDefaultApi,
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
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadManifest", [options]);
}

/**
 * Load and decode the rendered HTML fragment cache.
 *
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<Map<string, BlueprintHtmlCacheEntry>>}
 */
export function loadHtmlCache(options) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadHtmlCache", [options]);
}

/**
 * Load a single manifest entry by key.
 *
 * @param {string} key Manifest key.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintManifestEntry | null>}
 */
export function loadManifestEntry(key, options) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadManifestEntry", [key, options]);
}

/**
 * Load a single HTML-cache entry by key.
 *
 * @param {string} key HTML cache key.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintHtmlCacheEntry | null>}
 */
export function loadHtmlCacheEntry(key, options) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadHtmlCacheEntry", [key, options]);
}

/**
 * Extract graph variants from an already-loaded manifest object.
 *
 * @param {unknown} manifest Parsed manifest JSON.
 * @returns {BlueprintGraphData[]}
 */
export function graphsFromManifest(manifest) {
  return defaultDataHandle.readDefaultApi().graphsFromManifest(manifest);
}

/**
 * Read embedded graph data from a generated graph page.
 *
 * @param {ParentNode | Element | Document | DocumentFragment | null} [root] Search root. Defaults to `document`.
 * @returns {BlueprintGraphData | null}
 */
export function getGraphData(root) {
  return defaultDataHandle.readDefaultApi().getGraphData(root);
}

/**
 * Read graph variants embedded in a generated graph page.
 *
 * @param {ParentNode | Element | Document | DocumentFragment | null} [root] Search root. Defaults to `document`.
 * @returns {BlueprintGraphVariant[]}
 */
export function getGraphVariants(root) {
  return defaultDataHandle.readDefaultApi().getGraphVariants(root);
}

/**
 * Load graph variants from a manifest URL.
 *
 * @param {string} [url] Manifest URL. Defaults to this module's generated-data manifest.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintGraphData[]>}
 */
export function loadManifestGraphs(url, options) {
  return defaultDataHandle.readDefaultApi().loadManifestGraphs(url, options);
}

/**
 * Load graph variants from this generated site's default manifest.
 *
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintGraphData[]>}
 */
export function loadGraphs(options) {
  return defaultDataHandle.readDefaultApi().loadGraphs(options);
}

const dataApi = {
  version,
  dataUrl,
  manifestUrl,
  htmlCacheUrl,
  graphApiModuleUrl,
  dataApiModuleUrl,
  previewApiModuleUrl,
  createPreviewData,
  currentDataApi,
  getDataApi,
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
  previewKey,
  statementPreviewKey
};

export default dataApi;
