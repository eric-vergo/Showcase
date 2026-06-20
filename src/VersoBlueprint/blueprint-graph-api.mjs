export const version = 1;

function currentHref() {
  return typeof window !== "undefined" && window.location ? window.location.href : "";
}

function currentDocument() {
  return typeof document !== "undefined" ? document : null;
}

function isElement(node) {
  return typeof Element !== "undefined" && node instanceof Element;
}

function isDocumentLike(node) {
  return (
    (typeof Document !== "undefined" && node instanceof Document) ||
    (typeof DocumentFragment !== "undefined" && node instanceof DocumentFragment)
  );
}

function isScriptElement(node) {
  return !!node && typeof node.tagName === "string" && node.tagName.toLowerCase() === "script";
}

export function dataUrl(filename, baseUrl = currentHref()) {
  const safeFilename = String(filename || "").trim();
  if (!safeFilename) return "-verso-data/";
  try {
    const url = new URL(baseUrl);
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

export function graphApiModuleUrl(baseUrl = currentHref()) {
  return dataUrl("blueprint-graph-api.mjs", baseUrl);
}

export function graphCanvasFor(root = currentDocument()) {
  const node = root || currentDocument();
  if (!node) return null;
  if (isElement(node)) {
    if (node.matches(".bp_graph_canvas")) return node;
    const ownCanvas = node.querySelector(".bp_graph_canvas");
    if (isElement(ownCanvas)) return ownCanvas;
    const block = node.closest(".bp_graph_fullwidth");
    if (isElement(block)) {
      const blockCanvas = block.querySelector(".bp_graph_canvas");
      if (isElement(blockCanvas)) return blockCanvas;
    }
    return null;
  }
  if (isDocumentLike(node)) {
    const canvas = node.querySelector(".bp_graph_canvas");
    return isElement(canvas) ? canvas : null;
  }
  return null;
}

export function readGraphJsonScript(root, selector) {
  const container = graphCanvasFor(root);
  if (!isElement(container)) return null;
  const payloadNode = container.querySelector(selector);
  if (!isScriptElement(payloadNode)) return null;
  try {
    return JSON.parse((payloadNode.textContent || "").trim());
  } catch (_err) {
    return null;
  }
}

export function graphFallbackVariants(root = currentDocument()) {
  const graphRoot = graphCanvasFor(root);
  if (!isElement(graphRoot)) return [];
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

export function getGraphData(root = currentDocument()) {
  return normalizeGraphData(readGraphJsonScript(root, "script.bp-graph-data"));
}

export function getGraphVariants(root = currentDocument()) {
  const parsed = readGraphJsonScript(root, "script.bp-graph-variants");
  if (Array.isArray(parsed) && parsed.length > 0) return parsed;
  return graphFallbackVariants(root);
}

export function loadJson(url, options) {
  return fetch(url, options).then(function (response) {
    if (!response.ok) {
      throw new Error("Could not load Blueprint JSON: " + response.status);
    }
    return response.json();
  });
}

export function loadManifestGraphs(url = dataUrl("blueprint-manifest.json"), options) {
  return fetch(url, options).then(function (response) {
    if (!response.ok) {
      throw new Error("Could not load Blueprint graph manifest: " + response.status);
    }
    return response.json();
  }).then(graphsFromManifest);
}

export function loadGraphs(options) {
  return loadManifestGraphs(dataUrl("blueprint-manifest.json"), options);
}

const graphApi = {
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

export default graphApi;
