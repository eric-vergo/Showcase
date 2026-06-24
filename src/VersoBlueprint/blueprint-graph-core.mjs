const version = 1;

function defaultGlobalScope() {
  return typeof globalThis !== "undefined" ? globalThis : {};
}

function currentHref(globalScope = defaultGlobalScope()) {
  const windowObj = globalScope && globalScope.window;
  return windowObj && windowObj.location ? windowObj.location.href : "";
}

function currentDocument(globalScope = defaultGlobalScope()) {
  return globalScope && globalScope.document ? globalScope.document : null;
}

function isElement(node, globalScope = defaultGlobalScope()) {
  const ElementCtor = globalScope && globalScope.Element;
  return typeof ElementCtor !== "undefined" && node instanceof ElementCtor;
}

function isDocumentLike(node, globalScope = defaultGlobalScope()) {
  const DocumentCtor = globalScope && globalScope.Document;
  const DocumentFragmentCtor = globalScope && globalScope.DocumentFragment;
  return (
    (typeof DocumentCtor !== "undefined" && node instanceof DocumentCtor) ||
    (typeof DocumentFragmentCtor !== "undefined" && node instanceof DocumentFragmentCtor)
  );
}

function isScriptElement(node) {
  return !!node && typeof node.tagName === "string" && node.tagName.toLowerCase() === "script";
}

export function dataUrl(filename, baseUrl) {
  const safeFilename = String(filename || "").trim();
  if (!safeFilename) return "-verso-data/";
  const sourceUrl =
    typeof baseUrl === "string" && baseUrl.length > 0 ? baseUrl : currentHref();
  try {
    const url = new URL(sourceUrl);
    const markers = ["/html-multi/", "/html-single/"];
    for (const marker of markers) {
      const idx = url.pathname.indexOf(marker);
      if (idx >= 0) {
        const rootPath = url.pathname.slice(0, idx + marker.length);
        return rootPath + "-verso-data/" + safeFilename;
      }
    }
  } catch (_err) {}
  return "-verso-data/" + safeFilename;
}

export function graphApiModuleUrl(baseUrl) {
  return dataUrl("api/graph.mjs", baseUrl);
}

export function graphCanvasFor(root) {
  const globalScope = defaultGlobalScope();
  const node = root || currentDocument(globalScope);
  if (!node) return null;
  if (isElement(node, globalScope)) {
    if (node.matches(".bp_graph_canvas")) return node;
    const ownCanvas = node.querySelector(".bp_graph_canvas");
    if (isElement(ownCanvas, globalScope)) return ownCanvas;
    const block = node.closest(".bp_graph_fullwidth");
    if (isElement(block, globalScope)) {
      const blockCanvas = block.querySelector(".bp_graph_canvas");
      if (isElement(blockCanvas, globalScope)) return blockCanvas;
    }
    return null;
  }
  if (isDocumentLike(node, globalScope)) {
    const canvas = node.querySelector(".bp_graph_canvas");
    return isElement(canvas, globalScope) ? canvas : null;
  }
  return null;
}

export function readGraphJsonScript(root, selector) {
  const container = graphCanvasFor(root);
  if (!container) return null;
  const payloadNode = container.querySelector(selector);
  if (!isScriptElement(payloadNode)) return null;
  try {
    return JSON.parse((payloadNode.textContent || "").trim());
  } catch (_err) {
    return null;
  }
}

export function graphFallbackVariants(root) {
  const graphRoot = graphCanvasFor(root);
  if (!graphRoot) return [];
  const dotSource = graphRoot.querySelector("script.dot-source");
  const dotTxt = dotSource ? (dotSource.textContent || "").trim() : "";
  if (!dotTxt) return [];
  return [{
    key: "full",
    label: "Full Graph",
    dot: dotTxt,
    options: {
      direction: graphRoot.getAttribute("data-bp-graph-direction"),
      pack: graphRoot.getAttribute("data-bp-graph-pack")
    },
    selectOnNodeId: [],
    hoverOnNodeId: []
  }];
}

export function normalizeGraphData(rawData) {
  if (!rawData || typeof rawData !== "object" || Array.isArray(rawData)) return null;
  return {
    schemaVersion: Number.isFinite(rawData.schemaVersion) ? rawData.schemaVersion : 1,
    key: typeof rawData.key === "string" ? rawData.key : "graph",
    nodes: Array.isArray(rawData.nodes) ? rawData.nodes : [],
    edges: Array.isArray(rawData.edges) ? rawData.edges : [],
    groups: Array.isArray(rawData.groups) ? rawData.groups : []
  };
}

export function graphsFromManifest(manifest) {
  if (!manifest || typeof manifest !== "object" || !Array.isArray(manifest.graphs)) {
    return [];
  }
  return manifest.graphs
    .map(normalizeGraphData)
    .filter(function (graphData) { return !!graphData; });
}

export function getGraphData(root) {
  return normalizeGraphData(readGraphJsonScript(root || currentDocument(), "script.bp-graph-data"));
}

export function getGraphVariants(root) {
  const parsed = readGraphJsonScript(root || currentDocument(), "script.bp-graph-variants");
  if (Array.isArray(parsed) && parsed.length > 0) return parsed;
  return graphFallbackVariants(root || currentDocument());
}

export function loadJson(url, options, errorPrefix) {
  const globalScope = defaultGlobalScope();
  const fetchFn = globalScope && globalScope.fetch;
  if (typeof fetchFn !== "function") {
    return Promise.reject(new Error("Blueprint graph API requires fetch"));
  }
  const prefix =
    typeof errorPrefix === "string" && errorPrefix.length > 0
      ? errorPrefix
      : "Could not load Blueprint JSON";
  return fetchFn.call(globalScope, url, options).then(function (response) {
    if (!response.ok) {
      throw new Error(prefix + ": " + response.status);
    }
    return response.json();
  });
}

export function loadManifestGraphs(url, options) {
  const manifestUrl =
    typeof url === "string" && url.trim() ? url : dataUrl("blueprint-manifest.json");
  return loadJson(
    manifestUrl,
    options,
    "Could not load Blueprint graph manifest"
  ).then(graphsFromManifest);
}

export function loadGraphs(options) {
  return loadManifestGraphs(dataUrl("blueprint-manifest.json"), options);
}

export const graphCore = {
  version,
  dataUrl,
  graphApiModuleUrl,
  graphCanvasFor,
  readGraphJsonScript,
  graphFallbackVariants,
  normalizeGraphData,
  graphsFromManifest,
  getGraphData,
  getGraphVariants,
  loadJson,
  loadManifestGraphs,
  loadGraphs
};

export function installGraphCoreGlobal(globalScope = defaultGlobalScope()) {
  const existingCore =
    globalScope.VersoBlueprintGraphCore && typeof globalScope.VersoBlueprintGraphCore === "object"
      ? globalScope.VersoBlueprintGraphCore
      : {};
  Object.assign(existingCore, graphCore);
  globalScope.VersoBlueprintGraphCore = existingCore;

  const windowObj = globalScope && globalScope.window;
  if (windowObj && typeof windowObj === "object") {
    const existingGlobalApi =
      windowObj.bpGraphApi && typeof windowObj.bpGraphApi === "object"
        ? windowObj.bpGraphApi
        : {};
    Object.assign(existingGlobalApi, existingCore);
    windowObj.bpGraphApi = existingGlobalApi;
  }
  return existingCore;
}

export { version };

export default graphCore;
