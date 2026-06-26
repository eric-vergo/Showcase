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

export function createPreview(options) {
  return createPreviewRuntimeApi(optionsWithDefaultDataBaseUrl(options, moduleUrl));
}

const defaultRenderHandle = createDefaultApiHandle(createPreview);

export function currentRenderApi() {
  return defaultRenderHandle.currentApi();
}

export function getRenderApi() {
  return defaultRenderHandle.getApi();
}

export const ready = defaultRenderHandle.ready;

export const dataUrl = previewUrls.dataUrl;
export const manifestUrl = previewUrls.manifestUrl;
export const htmlCacheUrl = previewUrls.htmlCacheUrl;
export const graphApiModuleUrl = previewUrls.graphApiModuleUrl;
export const dataApiModuleUrl = previewUrls.dataApiModuleUrl;
export const previewApiModuleUrl = previewUrls.previewApiModuleUrl;
export const previewKey = previewUrls.previewKey;
export const statementPreviewKey = previewUrls.statementPreviewKey;

export function readManifestStatus() {
  return callDefaultApiSync(
    defaultRenderHandle.readDefaultApi,
    "readManifestStatus",
    function () { return fallbackStoreStatus(manifestUrl()); },
    arguments
  );
}

export function readHtmlCacheStatus() {
  return callDefaultApiSync(
    defaultRenderHandle.readDefaultApi,
    "readHtmlCacheStatus",
    function () { return fallbackStoreStatus(htmlCacheUrl()); },
    arguments
  );
}

export function loadManifest() {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadManifest", arguments);
}

export function loadHtmlCache() {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadHtmlCache", arguments);
}

export function loadManifestEntry(key) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadManifestEntry", arguments);
}

export function loadHtmlCacheEntry(key) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "loadHtmlCacheEntry", arguments);
}

export function resolvePreview(key) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "resolvePreview", arguments);
}

export function renderPreviewInto(element, key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "renderPreviewInto", arguments);
}

export function resolveCanonicalPreview(key) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "resolveCanonicalPreview", arguments);
}

export function renderCanonicalPreviewInto(element, key, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "renderCanonicalPreviewInto", arguments);
}

export function renderNode(element, request, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "renderNode", arguments);
}

export function hydrate(element, options) {
  return callDefaultApi(defaultRenderHandle.readDefaultApi, "render", "hydrate", arguments);
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
