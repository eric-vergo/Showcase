(function (globalScope) {
  const version = 1;

  function currentHref() {
    const windowObj = globalScope && globalScope.window;
    return windowObj && windowObj.location ? windowObj.location.href : "";
  }

  function currentDocument() {
    return globalScope && globalScope.document ? globalScope.document : null;
  }

  function isElement(node) {
    const ElementCtor = globalScope && globalScope.Element;
    return typeof ElementCtor !== "undefined" && node instanceof ElementCtor;
  }

  function isDocumentLike(node) {
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

  function dataUrl(filename, baseUrl) {
    const safeFilename = String(filename || "").trim();
    if (!safeFilename) return "-verso-data/";
    const sourceUrl = typeof baseUrl === "string" && baseUrl.length > 0 ? baseUrl : currentHref();
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

  function graphApiModuleUrl(baseUrl) {
    return dataUrl("api/graph.mjs", baseUrl);
  }

  function graphCanvasFor(root) {
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

  function readGraphJsonScript(root, selector) {
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

  function graphFallbackVariants(root) {
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

  function normalizeGraphData(rawData) {
    if (!rawData || typeof rawData !== "object" || Array.isArray(rawData)) return null;
    return {
      schemaVersion: Number.isFinite(rawData.schemaVersion) ? rawData.schemaVersion : 1,
      key: typeof rawData.key === "string" ? rawData.key : "graph",
      nodes: Array.isArray(rawData.nodes) ? rawData.nodes : [],
      edges: Array.isArray(rawData.edges) ? rawData.edges : [],
      groups: Array.isArray(rawData.groups) ? rawData.groups : []
    };
  }

  function graphsFromManifest(manifest) {
    if (!manifest || typeof manifest !== "object" || !Array.isArray(manifest.graphs)) {
      return [];
    }
    return manifest.graphs
      .map(normalizeGraphData)
      .filter(function (graphData) { return !!graphData; });
  }

  function getGraphData(root) {
    return normalizeGraphData(readGraphJsonScript(root || currentDocument(), "script.bp-graph-data"));
  }

  function getGraphVariants(root) {
    const parsed = readGraphJsonScript(root || currentDocument(), "script.bp-graph-variants");
    if (Array.isArray(parsed) && parsed.length > 0) return parsed;
    return graphFallbackVariants(root || currentDocument());
  }

  function loadJson(url, options, errorPrefix) {
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

  function loadManifestGraphs(url, options) {
    const manifestUrl = typeof url === "string" && url.trim()
      ? url
      : dataUrl("blueprint-manifest.json");
    return loadJson(
      manifestUrl,
      options,
      "Could not load Blueprint graph manifest"
    ).then(graphsFromManifest);
  }

  function loadGraphs(options) {
    return loadManifestGraphs(dataUrl("blueprint-manifest.json"), options);
  }

  const graphCore = {
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
})(
  typeof globalThis !== "undefined"
    ? globalThis
    : (typeof window !== "undefined" ? window : this)
);
