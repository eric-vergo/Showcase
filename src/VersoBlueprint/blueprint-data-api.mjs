import { callDefaultApi, callDefaultApiSync, createDefaultApiHandle, createPreviewUrlApi, fallbackStoreStatus, optionsWithDefaultDataBaseUrl, version } from "./blueprint-api-common.mjs";
import { createBlueprintDataApi } from "./Commands/preview-runtime-data.mjs";

export { version };

const moduleUrl = import.meta.url;
const previewUrls = createPreviewUrlApi(moduleUrl);

export function createPreviewData(options) {
  return createBlueprintDataApi(optionsWithDefaultDataBaseUrl(options, moduleUrl));
}

const defaultDataHandle = createDefaultApiHandle(createPreviewData);

export function currentDataApi() {
  return defaultDataHandle.currentApi();
}

export function getDataApi() {
  return defaultDataHandle.getApi();
}

export const ready = defaultDataHandle.ready;

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
    defaultDataHandle.readDefaultApi,
    "readManifestStatus",
    function () { return fallbackStoreStatus(manifestUrl()); },
    arguments
  );
}

export function readHtmlCacheStatus() {
  return callDefaultApiSync(
    defaultDataHandle.readDefaultApi,
    "readHtmlCacheStatus",
    function () { return fallbackStoreStatus(htmlCacheUrl()); },
    arguments
  );
}

export function loadManifest() {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadManifest", arguments);
}

export function loadHtmlCache() {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadHtmlCache", arguments);
}

export function loadManifestEntry(key) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadManifestEntry", arguments);
}

export function loadHtmlCacheEntry(key) {
  return callDefaultApi(defaultDataHandle.readDefaultApi, "data", "loadHtmlCacheEntry", arguments);
}

export function graphsFromManifest(manifest) {
  return defaultDataHandle.readDefaultApi().graphsFromManifest(manifest);
}

export function getGraphData(root) {
  return defaultDataHandle.readDefaultApi().getGraphData(root);
}

export function getGraphVariants(root) {
  return defaultDataHandle.readDefaultApi().getGraphVariants(root);
}

export function loadManifestGraphs(url, options) {
  return defaultDataHandle.readDefaultApi().loadManifestGraphs(url, options);
}

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
