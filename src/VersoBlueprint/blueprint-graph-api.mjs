export const version = 1;

export function dataUrl(filename, baseUrl = window.location.href) {
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

export function graphApiModuleUrl(baseUrl = window.location.href) {
  return dataUrl("blueprint-graph-api.mjs", baseUrl);
}

export function graphCanvasFor(root = document) {
  const node = root || document;
  if (node instanceof Element) {
    if (node.matches(".bp_graph_canvas")) return node;
    const ownCanvas = node.querySelector(".bp_graph_canvas");
    if (ownCanvas instanceof Element) return ownCanvas;
    const block = node.closest(".bp_graph_fullwidth");
    if (block instanceof Element) {
      const blockCanvas = block.querySelector(".bp_graph_canvas");
      if (blockCanvas instanceof Element) return blockCanvas;
    }
    return null;
  }
  if (node instanceof Document || node instanceof DocumentFragment) {
    const canvas = node.querySelector(".bp_graph_canvas");
    return canvas instanceof Element ? canvas : null;
  }
  return null;
}

export function readGraphJsonScript(root, selector) {
  const container = graphCanvasFor(root);
  if (!(container instanceof Element)) return null;
  const payloadNode = container.querySelector(selector);
  if (!(payloadNode instanceof HTMLScriptElement)) return null;
  try {
    return JSON.parse((payloadNode.textContent || "").trim());
  } catch (_err) {
    return null;
  }
}

export function graphFallbackVariants(root = document) {
  const graphRoot = graphCanvasFor(root);
  if (!(graphRoot instanceof Element)) return [];
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

export function getGraphData(root = document) {
  return normalizeGraphData(readGraphJsonScript(root, "script.bp-graph-data"));
}

export function getGraphVariants(root = document) {
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
