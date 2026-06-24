(function (globalScope) {
  const version = 1;

  function graphCore() {
    const core = globalScope && globalScope.VersoBlueprintGraphCore;
    return core && typeof core === "object" ? core : null;
  }

  function dataUrl(filename, baseUrl) {
    const core = graphCore();
    if (core && typeof core.dataUrl === "function") {
      return core.dataUrl(filename, baseUrl);
    }
    const safeFilename = String(filename || "").trim();
    return safeFilename ? "-verso-data/" + safeFilename : "-verso-data/";
  }

  function manifestUrl(baseUrl) {
    return dataUrl("blueprint-manifest.json", baseUrl);
  }

  function htmlCacheUrl(baseUrl) {
    return dataUrl("blueprint-html-cache.json", baseUrl);
  }

  function graphApiModuleUrl(baseUrl) {
    return dataUrl("api/graph.mjs", baseUrl);
  }

  function previewApiModuleUrl(baseUrl) {
    return dataUrl("api/preview.mjs", baseUrl);
  }

  function previewKey(label, facet) {
    const trimmedLabel = typeof label === "string" ? label.trim() : "";
    if (!trimmedLabel) return "";
    const trimmedFacet = typeof facet === "string" && facet.trim() ? facet.trim() : "statement";
    return trimmedLabel + "--" + trimmedFacet;
  }

  function statementPreviewKey(label) {
    return previewKey(label, "statement");
  }

  const previewCore = {
    version,
    dataUrl,
    manifestUrl,
    htmlCacheUrl,
    graphApiModuleUrl,
    previewApiModuleUrl,
    previewKey,
    statementPreviewKey
  };

  const existingCore =
    globalScope.VersoBlueprintPreviewCore && typeof globalScope.VersoBlueprintPreviewCore === "object"
      ? globalScope.VersoBlueprintPreviewCore
      : {};
  Object.assign(existingCore, previewCore);
  globalScope.VersoBlueprintPreviewCore = existingCore;
})(
  typeof globalThis !== "undefined"
    ? globalThis
    : (typeof window !== "undefined" ? window : this)
);
