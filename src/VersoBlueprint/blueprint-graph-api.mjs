import {
  dataUrl as coreDataUrl,
  getGraphData as coreGetGraphData,
  getGraphVariants as coreGetGraphVariants,
  graphApiModuleUrl as coreGraphApiModuleUrl,
  graphCanvasFor as coreGraphCanvasFor,
  graphFallbackVariants as coreGraphFallbackVariants,
  graphsFromManifest as coreGraphsFromManifest,
  loadGraphs as coreLoadGraphs,
  loadJson as coreLoadJson,
  loadManifestGraphs as coreLoadManifestGraphs,
  normalizeGraphData as coreNormalizeGraphData,
  readGraphJsonScript as coreReadGraphJsonScript,
  version as coreVersion
} from "./blueprint-graph-core.mjs";

export const version = coreVersion;
export const dataUrl = coreDataUrl;
export const graphApiModuleUrl = coreGraphApiModuleUrl;
export const graphCanvasFor = coreGraphCanvasFor;
export const readGraphJsonScript = coreReadGraphJsonScript;
export const graphFallbackVariants = coreGraphFallbackVariants;
export const normalizeGraphData = coreNormalizeGraphData;
export const graphsFromManifest = coreGraphsFromManifest;
export const getGraphData = coreGetGraphData;
export const getGraphVariants = coreGetGraphVariants;
export const loadJson = coreLoadJson;
export const loadManifestGraphs = coreLoadManifestGraphs;
export const loadGraphs = coreLoadGraphs;

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
