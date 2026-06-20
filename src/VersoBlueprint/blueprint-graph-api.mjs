import "./blueprint-graph-core.js";

const graphCore =
  typeof globalThis !== "undefined" && globalThis.VersoBlueprintGraphCore
    ? globalThis.VersoBlueprintGraphCore
    : {};

export const version = graphCore.version || 1;
export const dataUrl = graphCore.dataUrl;
export const graphApiModuleUrl = graphCore.graphApiModuleUrl;
export const graphCanvasFor = graphCore.graphCanvasFor;
export const readGraphJsonScript = graphCore.readGraphJsonScript;
export const graphFallbackVariants = graphCore.graphFallbackVariants;
export const normalizeGraphData = graphCore.normalizeGraphData;
export const graphsFromManifest = graphCore.graphsFromManifest;
export const getGraphData = graphCore.getGraphData;
export const getGraphVariants = graphCore.getGraphVariants;
export const loadJson = graphCore.loadJson;
export const loadManifestGraphs = graphCore.loadManifestGraphs;
export const loadGraphs = graphCore.loadGraphs;

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
