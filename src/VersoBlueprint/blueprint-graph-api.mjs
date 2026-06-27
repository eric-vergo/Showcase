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

/** @import { BlueprintDataApiOptions, BlueprintGraphController, BlueprintGraphData, BlueprintGraphRenderOptions, BlueprintGraphVariant } from "./blueprint-api-types.mjs" */

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

let graphRuntimeModulePromise = null;

function graphRuntimeModuleUrl() {
  return new URL("./Commands/graph.mjs", moduleUrl).href;
}

function loadGraphRuntimeModule() {
  if (!graphRuntimeModulePromise) {
    graphRuntimeModulePromise = import(graphRuntimeModuleUrl()).catch(function (err) {
      graphRuntimeModulePromise = null;
      throw err;
    });
  }
  return graphRuntimeModulePromise;
}

/**
 * Load the graph runtime's D3 and Graphviz dependencies.
 *
 * The interactive graph renderer is imported only when a render helper is used;
 * data-only calls such as `loadGraphs()` do not load the renderer.
 *
 * @param {BlueprintGraphRenderOptions} [options] Runtime dependency overrides.
 * @returns {Promise<unknown>}
 */
export async function ensureGraphRuntimeLibraries(options) {
  const runtime = await loadGraphRuntimeModule();
  return runtime.ensureGraphRuntimeLibraries(options);
}

/**
 * Resolve the render-capable preview API used by graph rendering helpers.
 *
 * @param {BlueprintGraphRenderOptions} [options] Render API lookup options.
 * @returns {Promise<Record<string, unknown>>}
 */
export async function getGraphRenderApi(options) {
  const runtime = await loadGraphRuntimeModule();
  return runtime.getGraphRenderApi(options);
}

/**
 * Initialize one already-loaded graph block with an explicit preview API.
 *
 * @param {Record<string, unknown>} previewUtils Render-capable Blueprint preview API.
 * @param {Element} graphBlock Standard `.bp_graph_fullwidth` graph block.
 * @param {BlueprintGraphRenderOptions} [options] Graph render options.
 * @returns {Promise<BlueprintGraphController | null>}
 */
export async function initGraphBlock(previewUtils, graphBlock, options) {
  const runtime = await loadGraphRuntimeModule();
  return runtime.initGraphBlock(previewUtils, graphBlock, options);
}

/**
 * Install graph rendering helpers onto a preview API object.
 *
 * @param {Record<string, unknown>} previewUtils Render-capable Blueprint preview API.
 * @param {BlueprintGraphRenderOptions} [options] Graph render defaults.
 * @returns {Promise<Record<string, unknown>>}
 */
export async function installGraphRenderApi(previewUtils, options) {
  const runtime = await loadGraphRuntimeModule();
  return runtime.installGraphRenderApi(previewUtils, options);
}

/**
 * Render one standard `.bp_graph_fullwidth` graph block.
 *
 * @param {Element} graphBlock Standard graph block.
 * @param {BlueprintGraphRenderOptions} [options] Graph render options.
 * @returns {Promise<BlueprintGraphController | null>}
 */
export async function renderGraphBlock(graphBlock, options) {
  const runtime = await loadGraphRuntimeModule();
  return runtime.renderGraphBlock(graphBlock, options);
}

/**
 * Render every standard graph block under a document, element, or fragment.
 *
 * @param {ParentNode | Element | Document | DocumentFragment} [root] Search root.
 * @param {BlueprintGraphRenderOptions} [options] Graph render options.
 * @returns {Promise<BlueprintGraphController[]>}
 */
export async function renderGraphs(root, options) {
  const runtime = await loadGraphRuntimeModule();
  return runtime.renderGraphs(root, options);
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
  loadGraphs,
  ensureGraphRuntimeLibraries,
  getGraphRenderApi,
  initGraphBlock,
  installGraphRenderApi,
  renderGraphBlock,
  renderGraphs
};

export default graphApi;
