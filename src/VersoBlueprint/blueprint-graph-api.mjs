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

/**
 * Graph-only Blueprint browser API.
 *
 * This module is emitted as `-verso-data/api/graph.mjs` in generated sites. It
 * exposes URL helpers and graph data readers without loading the preview
 * runtime.
 *
 * @module blueprint-graph-api
 */

/** @import { BlueprintDataApiOptions, BlueprintGraphData, BlueprintGraphVariant } from "./blueprint-api-types.mjs" */

/** Graph API schema/runtime version. */
export const version = coreVersion;
const moduleUrl = import.meta.url;

/**
 * Resolve a generated data filename under `-verso-data/`.
 *
 * @param {string} filename Generated data filename.
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export const dataUrl = (filename, baseUrl = moduleUrl) => coreDataUrl(filename, baseUrl);

/**
 * Resolve the generated graph API module URL.
 *
 * @param {string} [baseUrl] Base URL. Defaults to this module URL.
 * @returns {string}
 */
export const graphApiModuleUrl = (baseUrl = moduleUrl) => coreGraphApiModuleUrl(baseUrl);
/** Find the graph canvas associated with a root node. */
export const graphCanvasFor = coreGraphCanvasFor;
/** Read and parse an embedded graph JSON script from a graph page. */
export const readGraphJsonScript = coreReadGraphJsonScript;
/** Read the DOT fallback graph variants embedded in a graph page. */
export const graphFallbackVariants = coreGraphFallbackVariants;
/** Normalize raw graph JSON into the stable graph payload shape. */
export const normalizeGraphData = coreNormalizeGraphData;
/** Extract graph variants from a parsed Blueprint manifest. */
export const graphsFromManifest = coreGraphsFromManifest;
/** Read embedded graph data from the current graph page or supplied root. */
export const getGraphData = coreGetGraphData;
/** Read embedded graph variants from the current graph page or supplied root. */
export const getGraphVariants = coreGetGraphVariants;
/** Load and parse JSON using `fetch` or `options.fetchJson`. */
export const loadJson = coreLoadJson;

/**
 * Load graph variants from a manifest URL.
 *
 * @param {string} [url] Manifest URL. Defaults to this module's generated-data manifest.
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintGraphData[]>}
 */
export const loadManifestGraphs = (url, options) => {
  const manifestUrl =
    typeof url === "string" && url.trim()
      ? url
      : coreDataUrl("blueprint-manifest.json", moduleUrl);
  return coreLoadManifestGraphs(manifestUrl, options);
};

/**
 * Load graph variants from this generated site's default manifest.
 *
 * @param {BlueprintDataApiOptions} [options] Optional per-call load overrides.
 * @returns {Promise<BlueprintGraphData[]>}
 */
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
