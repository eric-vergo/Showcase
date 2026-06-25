import {
  getGraphData,
  getGraphVariants,
  graphsFromManifest,
  loadGraphs,
  loadManifestGraphs,
  normalizeGraphData
} from "./blueprint-graph-api.mjs";
import {
  dataUrl as coreDataUrl,
  graphApiModuleUrl as coreGraphApiModuleUrl,
  htmlCacheUrl as coreHtmlCacheUrl,
  manifestUrl as coreManifestUrl,
  previewApiModuleUrl as corePreviewApiModuleUrl,
  previewKey as corePreviewKey,
  statementPreviewKey as coreStatementPreviewKey,
  version as coreVersion
} from "./blueprint-preview-core.mjs";

export {
  getGraphData,
  getGraphVariants,
  graphsFromManifest,
  loadGraphs,
  loadManifestGraphs,
  normalizeGraphData
};

export const version = coreVersion;

function currentHref() {
  return typeof window !== "undefined" && window.location ? window.location.href : "";
}

function ensureNamespace() {
  if (typeof window === "undefined") return null;
  const namespace =
    window.VersoBlueprint && typeof window.VersoBlueprint === "object"
      ? window.VersoBlueprint
      : {};
  if (!Array.isArray(namespace.renderReadyCallbacks)) {
    namespace.renderReadyCallbacks = [];
  }
  window.VersoBlueprint = namespace;
  return namespace;
}

export function currentRenderApi() {
  const namespace = ensureNamespace();
  if (!namespace || !namespace.render || typeof namespace.render !== "object") return null;
  return namespace.render;
}

export function onRenderReady(callback) {
  if (typeof callback !== "function") return;
  const namespace = ensureNamespace();
  if (!namespace) return;
  if (namespace.render && typeof namespace.render === "object") {
    callback(namespace.render);
    return;
  }
  const installed = namespace.onRenderReady;
  if (typeof installed === "function" && installed !== onRenderReady) {
    installed(callback);
    return;
  }
  namespace.renderReadyCallbacks.push(callback);
}

const namespace = ensureNamespace();
if (namespace && typeof namespace.onRenderReady !== "function") {
  namespace.onRenderReady = onRenderReady;
}

export function getRenderApi() {
  const api = currentRenderApi();
  if (api) return Promise.resolve(api);
  return new Promise(function (resolve) {
    onRenderReady(resolve);
  });
}

export const ready = getRenderApi();

export function dataUrl(filename, baseUrl = currentHref()) {
  const api = currentRenderApi();
  if (api && typeof api.dataUrl === "function" && baseUrl === currentHref()) {
    return api.dataUrl(filename);
  }
  return coreDataUrl(filename, baseUrl);
}

export function manifestUrl(baseUrl = currentHref()) {
  const api = currentRenderApi();
  if (api && typeof api.manifestUrl === "function" && baseUrl === currentHref()) {
    return api.manifestUrl();
  }
  return coreManifestUrl(baseUrl);
}

export function htmlCacheUrl(baseUrl = currentHref()) {
  const api = currentRenderApi();
  if (api && typeof api.htmlCacheUrl === "function" && baseUrl === currentHref()) {
    return api.htmlCacheUrl();
  }
  return coreHtmlCacheUrl(baseUrl);
}

export function graphApiModuleUrl(baseUrl = currentHref()) {
  const api = currentRenderApi();
  if (api && typeof api.graphApiModuleUrl === "function" && baseUrl === currentHref()) {
    return api.graphApiModuleUrl();
  }
  return coreGraphApiModuleUrl(baseUrl);
}

export function previewApiModuleUrl(baseUrl = currentHref()) {
  const api = currentRenderApi();
  if (api && typeof api.previewApiModuleUrl === "function" && baseUrl === currentHref()) {
    return api.previewApiModuleUrl();
  }
  return corePreviewApiModuleUrl(baseUrl);
}

export function previewKey(label, facet) {
  return corePreviewKey(label, facet);
}

export function statementPreviewKey(label) {
  return coreStatementPreviewKey(label);
}

function fallbackStatus(url) {
  return {
    state: "idle",
    attempts: 0,
    url: url,
    lastError: "",
    entryCount: 0
  };
}

function callRuntimeSync(name, fallback) {
  const api = currentRenderApi();
  const method = api && api[name];
  if (typeof method === "function") {
    return method.apply(api, Array.prototype.slice.call(arguments, 2));
  }
  return fallback();
}

async function callRuntime(name, args) {
  const api = await getRenderApi();
  const method = api && api[name];
  if (typeof method !== "function") {
    throw new Error("Blueprint render API method unavailable: " + name);
  }
  return method.apply(api, args);
}

export function readManifestStatus() {
  return callRuntimeSync("readManifestStatus", function () {
    return fallbackStatus(manifestUrl());
  });
}

export function readHtmlCacheStatus() {
  return callRuntimeSync("readHtmlCacheStatus", function () {
    return fallbackStatus(htmlCacheUrl());
  });
}

export function loadManifest() {
  return callRuntime("loadManifest", arguments);
}

export function loadHtmlCache() {
  return callRuntime("loadHtmlCache", arguments);
}

export function loadManifestEntry(key) {
  return callRuntime("loadManifestEntry", arguments);
}

export function loadHtmlCacheEntry(key) {
  return callRuntime("loadHtmlCacheEntry", arguments);
}

export function resolvePreview(key) {
  return callRuntime("resolvePreview", arguments);
}

export function renderPreviewInto(element, key, options) {
  return callRuntime("renderPreviewInto", arguments);
}

export function resolveCanonicalPreview(key) {
  return callRuntime("resolveCanonicalPreview", arguments);
}

export function renderCanonicalPreviewInto(element, key, options) {
  return callRuntime("renderCanonicalPreviewInto", arguments);
}

export function hydrate(element, options) {
  return callRuntime("hydrate", arguments);
}

const previewApi = {
  version,
  dataUrl,
  manifestUrl,
  htmlCacheUrl,
  graphApiModuleUrl,
  previewApiModuleUrl,
  currentRenderApi,
  getRenderApi,
  ready,
  onRenderReady,
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
  hydrate
};

export default previewApi;
