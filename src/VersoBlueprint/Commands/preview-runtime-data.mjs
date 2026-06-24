import { dataUrl as coreDataUrl, graphApiModuleUrl as coreGraphApiModuleUrl, htmlCacheUrl as coreHtmlCacheUrl, manifestUrl as coreManifestUrl, previewApiModuleUrl as corePreviewApiModuleUrl, previewKey as corePreviewKey, statementPreviewKey as coreStatementPreviewKey } from "../blueprint-preview-core.mjs";
import { getGraphData as coreGetGraphData, getGraphVariants as coreGetGraphVariants, graphsFromManifest as coreGraphsFromManifest, loadGraphs as coreLoadGraphs, loadManifestGraphs as coreLoadManifestGraphs } from "../blueprint-graph-core.mjs";
import { escapeHtml, previewDebug } from "./preview-runtime-base.mjs";

  // Generated-data URL helpers and graph-core delegation.

  export function blueprintDataUrl(filename) {
    return coreDataUrl(filename);
  }

  export function fetchBlueprintJson(url) {
    return fetch(url).then(function (resp) {
      if (!resp.ok) {
        throw new Error("HTTP " + resp.status + " while loading " + url);
      }
      return resp.json();
    });
  }

  export function decodeBlueprintKeyedEntries(data, spec) {
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new Error(spec.objectMessage);
    }
    const entries = data[spec.arrayField];
    if (!Array.isArray(entries)) {
      throw new Error(spec.missingArrayMessage);
    }
    const map = new Map();
    entries.forEach(function (entry, index) {
      if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
        throw new Error(spec.entryName + " " + index + " must be an object");
      }
      const key = typeof entry.key === "string" ? entry.key.trim() : "";
      if (!key) {
        throw new Error(spec.entryName + " " + index + " is missing key");
      }
      if (typeof spec.validateEntry === "function") {
        spec.validateEntry(entry, index);
      }
      if (map.has(key)) {
        throw new Error(spec.duplicateMessage + key);
      }
      map.set(key, entry);
    });
    return map;
  }

  export function decodeBlueprintManifest(data) {
    return decodeBlueprintKeyedEntries(data, {
      arrayField: "previews",
      objectMessage: "Blueprint manifest must be an object with a previews array",
      missingArrayMessage: "Blueprint manifest is missing previews array",
      entryName: "Blueprint manifest entry",
      duplicateMessage: "Blueprint manifest contains duplicate key "
    });
  }

  export function decodeBlueprintHtmlCache(data) {
    return decodeBlueprintKeyedEntries(data, {
      arrayField: "entries",
      objectMessage: "Blueprint HTML cache must be an object with an entries array",
      missingArrayMessage: "Blueprint HTML cache is missing entries array",
      entryName: "Blueprint HTML cache entry",
      duplicateMessage: "Blueprint HTML cache contains duplicate key ",
      validateEntry: function (entry, index) {
        if (typeof entry.html !== "string") {
          throw new Error("Blueprint HTML cache entry " + index + " is missing html");
        }
        if (!entry.html.trim()) {
          throw new Error("Blueprint HTML cache entry " + index + " has empty html");
        }
      }
    });
  }

  export function blueprintManifestUrl() {
    return coreManifestUrl();
  }

  export function graphApiModuleUrl() {
    return coreGraphApiModuleUrl();
  }

  export function previewApiModuleUrl() {
    return corePreviewApiModuleUrl();
  }

  export function graphDataFromManifest(manifest) {
    return coreGraphsFromManifest(manifest);
  }

  export function collectGraphData(root) {
    return coreGetGraphData(root);
  }

  export function collectGraphVariants(root) {
    return coreGetGraphVariants(root);
  }

  export function loadManifestGraphs(url, options) {
    const manifestUrl = typeof url === "string" && url.trim() ? url : blueprintManifestUrl();
    return coreLoadManifestGraphs(manifestUrl, options);
  }

  export function loadBlueprintGraphs(options) {
    return coreLoadGraphs(options);
  }

  // Manifest/cache status, loading, and diagnostics.

  export function missingPreviewKeyDiagnosticHtml() {
    return (
      "<div class=\"bp_html_cache_preview_notice\">" +
      "<p><strong>Preview key missing.</strong></p>" +
      "<p>Provide a manifest/cache preview key such as " +
      "<code>some_label--statement</code> or <code>some_label--proof</code>.</p>" +
      "</div>"
    );
  }

  export function blueprintHtmlCacheUrl() {
    return coreHtmlCacheUrl();
  }

  export const blueprintManifestStore = {
    status: null,
    map: null,
    promise: null,
    url: blueprintManifestUrl,
    decode: decodeBlueprintManifest,
    debugLabel: "manifest.loadFailed",
    consoleLabel: "Blueprint manifest",
    unavailableTitle: "Preview manifest unavailable.",
    requiredFilename: "blueprint-manifest.json",
    missingTitle: "Preview entry missing from manifest.",
    missingReadyText: "The site emitted a Blueprint manifest, but this preview key was not present."
  };

  export const blueprintHtmlCacheStore = {
    status: null,
    map: null,
    promise: null,
    url: blueprintHtmlCacheUrl,
    decode: decodeBlueprintHtmlCache,
    debugLabel: "htmlCache.loadFailed",
    consoleLabel: "Blueprint HTML cache",
    unavailableTitle: "Preview HTML cache unavailable.",
    requiredFilename: "blueprint-html-cache.json",
    missingTitle: "Preview entry missing from HTML cache.",
    missingReadyText: "The site emitted a rendered-fragment cache, but this preview key was not present."
  };

  export function defaultBlueprintStoreStatus(store) {
    return {
      state: "idle",
      attempts: 0,
      url: store.url(),
      lastError: "",
      entryCount: 0
    };
  }

  export function cloneBlueprintStoreStatus(store, status) {
    const fallback = defaultBlueprintStoreStatus(store);
    if (!status || typeof status !== "object") return fallback;
    return {
      state: typeof status.state === "string" ? status.state : fallback.state,
      attempts: Number.isFinite(status.attempts) ? status.attempts : fallback.attempts,
      url: typeof status.url === "string" ? status.url : fallback.url,
      lastError: typeof status.lastError === "string" ? status.lastError : fallback.lastError,
      entryCount: Number.isFinite(status.entryCount) ? status.entryCount : fallback.entryCount
    };
  }

  export function readBlueprintStoreStatus(store) {
    return cloneBlueprintStoreStatus(store, store.status);
  }

  export function setBlueprintStoreStatus(store, status) {
    store.status = status;
    return status;
  }

  export function readBlueprintManifestStatus() {
    return readBlueprintStoreStatus(blueprintManifestStore);
  }

  export function readBlueprintHtmlCacheStatus() {
    return readBlueprintStoreStatus(blueprintHtmlCacheStore);
  }

  export function blueprintStoreDiagnosticHtml(store, previewKey) {
    const status = readBlueprintStoreStatus(store);
    const trimmedKey = typeof previewKey === "string" ? previewKey.trim() : "";
    const keyHtml = trimmedKey ? "<code>" + escapeHtml(trimmedKey) + "</code>" : "this preview";
    if (status.state === "error") {
      const errorHtml = status.lastError
        ? "<p>Last load error: <code>" + escapeHtml(status.lastError) + "</code></p>"
        : "";
      return (
        "<div class=\"bp_html_cache_preview_notice\">" +
        "<p><strong>" + store.unavailableTitle + "</strong></p>" +
        "<p>Blueprint previews require <code>-verso-data/" + store.requiredFilename + "</code>. " +
        "Rebuild the site or retry after the current build finishes.</p>" +
        "<p>Requested preview: " + keyHtml + "</p>" +
        errorHtml +
        "</div>"
      );
    }
    if (status.state === "ready" && trimmedKey) {
      return (
        "<div class=\"bp_html_cache_preview_notice\">" +
        "<p><strong>" + store.missingTitle + "</strong></p>" +
        "<p>Requested preview: " + keyHtml + "</p>" +
        "<p>" + store.missingReadyText + "</p>" +
        "</div>"
      );
    }
    return "";
  }

  export function blueprintManifestDiagnosticHtml(previewKey) {
    return blueprintStoreDiagnosticHtml(blueprintManifestStore, previewKey);
  }

  export function blueprintHtmlCacheDiagnosticHtml(previewKey) {
    return blueprintStoreDiagnosticHtml(blueprintHtmlCacheStore, previewKey);
  }

  export function fetchBlueprintStoreData(store) {
    const jsonUrl = store.url();
    return fetchBlueprintJson(jsonUrl).then(function (data) {
      return { data: data, url: jsonUrl };
    });
  }

  export function loadBlueprintStore(store) {
    const existing = store.map;
    if (existing instanceof Map) {
      return Promise.resolve(existing);
    }
    const existingPromise = store.promise;
    if (existingPromise) {
      return existingPromise;
    }
    const url = store.url();
    const previousStatus = readBlueprintStoreStatus(store);
    const attempts =
      Number.isFinite(previousStatus.attempts) ? previousStatus.attempts + 1 : 1;
    setBlueprintStoreStatus(store, {
      state: "loading",
      attempts: attempts,
      url: url,
      lastError: "",
      entryCount: 0
    });
    let promise = null;
    promise = fetchBlueprintStoreData(store)
      .then(function (result) {
        const map = store.decode(result.data);
        store.map = map;
        setBlueprintStoreStatus(store, {
          state: "ready",
          attempts: attempts,
          url: result.url,
          lastError: "",
          entryCount: map.size
        });
        return map;
      })
      .catch(function (err) {
        const message =
          err && typeof err.message === "string" && err.message.length > 0
            ? err.message
            : String(err);
        store.map = null;
        setBlueprintStoreStatus(store, {
          state: "error",
          attempts: attempts,
          url: url,
          lastError: message,
          entryCount: 0
        });
        previewDebug(store.debugLabel, {
          url: url,
          attempts: attempts,
          error: message
        });
        try {
          console.error("[bp-preview] " + store.consoleLabel + " load failed", {
            url: url,
            error: message
          });
        } catch (_consoleErr) {}
        return new Map();
      })
      .then(function (map) {
        if (store.promise === promise) {
          store.promise = null;
        }
        return map;
      });
    store.promise = promise;
    return promise;
  }

  export function loadBlueprintManifest() {
    return loadBlueprintStore(blueprintManifestStore);
  }

  export function loadBlueprintHtmlCache() {
    return loadBlueprintStore(blueprintHtmlCacheStore);
  }

  export function readBlueprintStoreEntry(store, previewKey) {
    if (typeof previewKey !== "string" || previewKey.length === 0) return null;
    const map = store.map;
    if (!(map instanceof Map)) return null;
    return map.get(previewKey) || null;
  }

  export function previewKey(label, facet) {
    return corePreviewKey(label, facet);
  }

  export function statementPreviewKey(label) {
    return coreStatementPreviewKey(label);
  }

  export async function loadBlueprintStoreEntry(store, previewKey) {
    const exact = readBlueprintStoreEntry(store, previewKey);
    if (exact) return exact;
    const entryMap = await loadBlueprintStore(store);
    if (!(entryMap instanceof Map)) return null;
    if (typeof previewKey === "string" && previewKey.length > 0 && entryMap.has(previewKey)) {
      return entryMap.get(previewKey) || null;
    }
    return null;
  }

  export async function loadBlueprintManifestEntry(previewKey) {
    return loadBlueprintStoreEntry(blueprintManifestStore, previewKey);
  }

  export async function loadBlueprintHtmlCacheEntry(previewKey) {
    return loadBlueprintStoreEntry(blueprintHtmlCacheStore, previewKey);
  }

  export const previewRuntimeData = {
    blueprintDataUrl,
    fetchBlueprintJson,
    decodeBlueprintKeyedEntries,
    decodeBlueprintManifest,
    decodeBlueprintHtmlCache,
    blueprintManifestUrl,
    graphApiModuleUrl,
    previewApiModuleUrl,
    graphDataFromManifest,
    collectGraphData,
    collectGraphVariants,
    loadManifestGraphs,
    loadBlueprintGraphs,
    missingPreviewKeyDiagnosticHtml,
    blueprintHtmlCacheUrl,
    blueprintManifestStore,
    blueprintHtmlCacheStore,
    defaultBlueprintStoreStatus,
    cloneBlueprintStoreStatus,
    readBlueprintStoreStatus,
    setBlueprintStoreStatus,
    readBlueprintManifestStatus,
    readBlueprintHtmlCacheStatus,
    blueprintStoreDiagnosticHtml,
    blueprintManifestDiagnosticHtml,
    blueprintHtmlCacheDiagnosticHtml,
    fetchBlueprintStoreData,
    loadBlueprintStore,
    loadBlueprintManifest,
    loadBlueprintHtmlCache,
    readBlueprintStoreEntry,
    previewKey,
    statementPreviewKey,
    loadBlueprintStoreEntry,
    loadBlueprintManifestEntry,
    loadBlueprintHtmlCacheEntry
  };

export default previewRuntimeData;
