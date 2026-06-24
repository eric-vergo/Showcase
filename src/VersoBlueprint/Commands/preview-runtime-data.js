  // Generated-data URL helpers and graph-core delegation.

  const blueprintGlobal = typeof globalThis !== "undefined" ? globalThis : window;

  function blueprintPreviewCore() {
    const core = blueprintGlobal.VersoBlueprintPreviewCore;
    return core && typeof core === "object" ? core : null;
  }

  function callBlueprintPreviewCore(name, args, fallback) {
    const core = blueprintPreviewCore();
    const method = core && core[name];
    if (typeof method === "function") {
      return method.apply(core, args);
    }
    if (typeof fallback === "function") {
      return fallback();
    }
    return fallback;
  }

  function blueprintGraphCore() {
    const core = blueprintGlobal.VersoBlueprintGraphCore;
    return core && typeof core === "object" ? core : null;
  }

  function callBlueprintGraphCore(name, args, fallback) {
    const core = blueprintGraphCore();
    const method = core && core[name];
    if (typeof method === "function") {
      return method.apply(core, args);
    }
    if (typeof fallback === "function") {
      return fallback();
    }
    return fallback;
  }

  function blueprintDataUrl(filename) {
    return callBlueprintPreviewCore("dataUrl", [filename], function () {
      const safeFilename = String(filename || "").trim();
      return safeFilename ? "-verso-data/" + safeFilename : "-verso-data/";
    });
  }

  function fetchBlueprintJson(url) {
    return fetch(url).then(function (resp) {
      if (!resp.ok) {
        throw new Error("HTTP " + resp.status + " while loading " + url);
      }
      return resp.json();
    });
  }

  function decodeBlueprintKeyedEntries(data, spec) {
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

  function decodeBlueprintManifest(data) {
    return decodeBlueprintKeyedEntries(data, {
      arrayField: "previews",
      objectMessage: "Blueprint manifest must be an object with a previews array",
      missingArrayMessage: "Blueprint manifest is missing previews array",
      entryName: "Blueprint manifest entry",
      duplicateMessage: "Blueprint manifest contains duplicate key "
    });
  }

  function decodeBlueprintHtmlCache(data) {
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

  function blueprintManifestUrl() {
    return callBlueprintPreviewCore("manifestUrl", [], function () {
      return blueprintDataUrl("blueprint-manifest.json");
    });
  }

  function graphApiModuleUrl() {
    return callBlueprintPreviewCore("graphApiModuleUrl", [], function () {
      return blueprintDataUrl("api/graph.mjs");
    });
  }

  function previewApiModuleUrl() {
    return callBlueprintPreviewCore("previewApiModuleUrl", [], function () {
      return blueprintDataUrl("api/preview.mjs");
    });
  }

  function graphDataFromManifest(manifest) {
    return callBlueprintGraphCore("graphsFromManifest", [manifest], []);
  }

  function collectGraphData(root) {
    return callBlueprintGraphCore("getGraphData", [root], null);
  }

  function collectGraphVariants(root) {
    return callBlueprintGraphCore("getGraphVariants", [root], []);
  }

  function loadManifestGraphs(url, options) {
    const manifestUrl = typeof url === "string" && url.trim() ? url : blueprintManifestUrl();
    return callBlueprintGraphCore("loadManifestGraphs", [manifestUrl, options], function () {
      return Promise.reject(new Error("Blueprint graph API unavailable"));
    });
  }

  function loadBlueprintGraphs(options) {
    return callBlueprintGraphCore("loadGraphs", [options], function () {
      return loadManifestGraphs(blueprintManifestUrl(), options);
    });
  }

  // Manifest/cache status, loading, and diagnostics.

  function missingPreviewKeyDiagnosticHtml() {
    return (
      "<div class=\"bp_html_cache_preview_notice\">" +
      "<p><strong>Preview key missing.</strong></p>" +
      "<p>Provide a manifest/cache preview key such as " +
      "<code>some_label--statement</code> or <code>some_label--proof</code>.</p>" +
      "</div>"
    );
  }

  function blueprintHtmlCacheUrl() {
    return callBlueprintPreviewCore("htmlCacheUrl", [], function () {
      return blueprintDataUrl("blueprint-html-cache.json");
    });
  }

  const blueprintManifestStore = {
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

  const blueprintHtmlCacheStore = {
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

  function defaultBlueprintStoreStatus(store) {
    return {
      state: "idle",
      attempts: 0,
      url: store.url(),
      lastError: "",
      entryCount: 0
    };
  }

  function cloneBlueprintStoreStatus(store, status) {
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

  function readBlueprintStoreStatus(store) {
    return cloneBlueprintStoreStatus(store, store.status);
  }

  function setBlueprintStoreStatus(store, status) {
    store.status = status;
    return status;
  }

  function readBlueprintManifestStatus() {
    return readBlueprintStoreStatus(blueprintManifestStore);
  }

  function readBlueprintHtmlCacheStatus() {
    return readBlueprintStoreStatus(blueprintHtmlCacheStore);
  }

  function blueprintStoreDiagnosticHtml(store, previewKey) {
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

  function blueprintManifestDiagnosticHtml(previewKey) {
    return blueprintStoreDiagnosticHtml(blueprintManifestStore, previewKey);
  }

  function blueprintHtmlCacheDiagnosticHtml(previewKey) {
    return blueprintStoreDiagnosticHtml(blueprintHtmlCacheStore, previewKey);
  }

  function fetchBlueprintStoreData(store) {
    const jsonUrl = store.url();
    return fetchBlueprintJson(jsonUrl).then(function (data) {
      return { data: data, url: jsonUrl };
    });
  }

  function loadBlueprintStore(store) {
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

  function loadBlueprintManifest() {
    return loadBlueprintStore(blueprintManifestStore);
  }

  function loadBlueprintHtmlCache() {
    return loadBlueprintStore(blueprintHtmlCacheStore);
  }

  function readBlueprintStoreEntry(store, previewKey) {
    if (typeof previewKey !== "string" || previewKey.length === 0) return null;
    const map = store.map;
    if (!(map instanceof Map)) return null;
    return map.get(previewKey) || null;
  }

  function previewKey(label, facet) {
    return callBlueprintPreviewCore("previewKey", [label, facet], "");
  }

  function statementPreviewKey(label) {
    return callBlueprintPreviewCore("statementPreviewKey", [label], function () {
      return previewKey(label, "statement");
    });
  }

  async function loadBlueprintStoreEntry(store, previewKey) {
    const exact = readBlueprintStoreEntry(store, previewKey);
    if (exact) return exact;
    const entryMap = await loadBlueprintStore(store);
    if (!(entryMap instanceof Map)) return null;
    if (typeof previewKey === "string" && previewKey.length > 0 && entryMap.has(previewKey)) {
      return entryMap.get(previewKey) || null;
    }
    return null;
  }

  async function loadBlueprintManifestEntry(previewKey) {
    return loadBlueprintStoreEntry(blueprintManifestStore, previewKey);
  }

  async function loadBlueprintHtmlCacheEntry(previewKey) {
    return loadBlueprintStoreEntry(blueprintHtmlCacheStore, previewKey);
  }
