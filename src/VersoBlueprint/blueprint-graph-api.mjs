import {
  dataUrl as coreDataUrl,
  getGraphData as coreGetGraphData,
  getGraphVariants as coreGetGraphVariants,
  graphApiModuleUrl as coreGraphApiModuleUrl,
  graphCanvasFor as coreGraphCanvasFor,
  graphFallbackVariants as coreGraphFallbackVariants,
  graphsFromManifest as coreGraphsFromManifest,
  loadJson as coreLoadJson,
  loadManifestGraphs as coreLoadManifestGraphs,
  normalizeGraphData as coreNormalizeGraphData,
  readGraphJsonScript as coreReadGraphJsonScript,
  version as coreVersion
} from "./blueprint-graph-core.mjs";

export const version = coreVersion;
const moduleUrl = import.meta.url;
export const dataUrl = (filename, baseUrl = moduleUrl) => coreDataUrl(filename, baseUrl);
export const graphApiModuleUrl = (baseUrl = moduleUrl) => coreGraphApiModuleUrl(baseUrl);
export const graphCanvasFor = coreGraphCanvasFor;
export const readGraphJsonScript = coreReadGraphJsonScript;
export const graphFallbackVariants = coreGraphFallbackVariants;
export const normalizeGraphData = coreNormalizeGraphData;
export const graphsFromManifest = coreGraphsFromManifest;
export const getGraphData = coreGetGraphData;
export const getGraphVariants = coreGetGraphVariants;
export const loadJson = coreLoadJson;
export const loadManifestGraphs = (url, options) => {
  const manifestUrl =
    typeof url === "string" && url.trim()
      ? url
      : coreDataUrl("blueprint-manifest.json", moduleUrl);
  return coreLoadManifestGraphs(manifestUrl, options);
};
export const loadGraphs = (options) =>
  coreLoadManifestGraphs(coreDataUrl("blueprint-manifest.json", moduleUrl), options);

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
