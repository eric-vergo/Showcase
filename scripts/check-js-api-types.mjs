import { access, readFile } from "node:fs/promises";
import path from "node:path";

const typesDir = path.resolve("dist/types/src/VersoBlueprint");
const failures = [];

function fail(message) {
  failures.push(message);
}

async function requireDeclaration(relativePath) {
  const absolutePath = path.join(typesDir, relativePath);
  try {
    await access(absolutePath);
  } catch {
    fail(`missing generated declaration file: ${relativePath}`);
    return "";
  }
  return readFile(absolutePath, "utf8");
}

function requireMatches(relativePath, text, pattern, description) {
  if (!pattern.test(text)) {
    fail(`${relativePath}: missing ${description}`);
  }
}

function rejectMatches(relativePath, text, pattern, description) {
  if (pattern.test(text)) {
    fail(`${relativePath}: found ${description}`);
  }
}

function requireTypeBlock(relativePath, text, typeName) {
  const pattern = new RegExp(`export type ${typeName} = \\{[\\s\\S]*?\\n\\};`);
  const match = text.match(pattern);
  if (!match) {
    fail(`${relativePath}: missing ${typeName} typedef`);
    return "";
  }
  return match[0];
}

const declarations = {
  "blueprint-api-types.d.mts": await requireDeclaration("blueprint-api-types.d.mts"),
  "blueprint-data-api.d.mts": await requireDeclaration("blueprint-data-api.d.mts"),
  "blueprint-graph-api.d.mts": await requireDeclaration("blueprint-graph-api.d.mts"),
  "blueprint-preview-api.d.mts": await requireDeclaration("blueprint-preview-api.d.mts")
};

for (const [relativePath, text] of Object.entries(declarations)) {
  rejectMatches(relativePath, text, /module:blueprint-api-types~/, "JSDoc longname leak");
  rejectMatches(relativePath, text, /(:|=>|<|,)\s*any\b/, "public API any type");
}

requireMatches(
  "blueprint-preview-api.d.mts",
  declarations["blueprint-preview-api.d.mts"],
  /export function createPreview\(options\?: BlueprintPreviewOptions\): BlueprintPreviewApi;/,
  "typed createPreview export"
);
requireMatches(
  "blueprint-preview-api.d.mts",
  declarations["blueprint-preview-api.d.mts"],
  /export function renderNode\(element: Element, request: string \| BlueprintRenderNodeRequest, options\?: BlueprintPreviewOptions\): Promise<BlueprintRenderNodeResult>;/,
  "typed module-level renderNode export"
);
requireMatches(
  "blueprint-preview-api.d.mts",
  declarations["blueprint-preview-api.d.mts"],
  /export function hydrate\(element: Element, options\?: BlueprintPreviewOptions\): Promise<boolean>;/,
  "async module-level hydrate export"
);

requireMatches(
  "blueprint-data-api.d.mts",
  declarations["blueprint-data-api.d.mts"],
  /export function createPreviewData\(options\?: BlueprintDataApiOptions\): BlueprintDataApi;/,
  "typed createPreviewData export"
);
requireMatches(
  "blueprint-data-api.d.mts",
  declarations["blueprint-data-api.d.mts"],
  /export function loadHtmlCacheEntry\(key: string, options\?: BlueprintDataApiOptions\): Promise<BlueprintHtmlCacheEntry \| null>;/,
  "typed data loadHtmlCacheEntry export"
);

requireMatches(
  "blueprint-graph-api.d.mts",
  declarations["blueprint-graph-api.d.mts"],
  /export function loadGraphs\(options\?: BlueprintDataApiOptions\): Promise<BlueprintGraphData\[]>;/,
  "typed graph loadGraphs export"
);
requireMatches(
  "blueprint-graph-api.d.mts",
  declarations["blueprint-graph-api.d.mts"],
  /export function renderGraphBlock\(graphBlock: Element, options\?: BlueprintGraphRenderOptions\): Promise<BlueprintGraphController \| null>;/,
  "typed graph renderGraphBlock export"
);

const graphApiNames = [
  "graphApiModuleUrl",
  "graphsFromManifest",
  "getGraphData",
  "getGraphVariants",
  "loadManifestGraphs",
  "loadGraphs",
  "normalizeGraphData"
];
const graphInternalApiNames = [
  "ensureGraphRuntimeLibraries",
  "getGraphRenderApi",
  "graphCanvasFor",
  "graphFallbackVariants",
  "graphsFromManifest",
  "initGraphBlock",
  "installGraphRenderApi",
  "loadJson",
  "normalizeGraphData",
  "readGraphJsonScript"
];

for (const apiName of graphApiNames) {
  rejectMatches(
    "blueprint-data-api.d.mts",
    declarations["blueprint-data-api.d.mts"],
    new RegExp(`export (?:function|const) ${apiName}\\b`),
    `${apiName} data API export`
  );
  rejectMatches(
    "blueprint-preview-api.d.mts",
    declarations["blueprint-preview-api.d.mts"],
    new RegExp(`export (?:function|const) ${apiName}\\b`),
    `${apiName} preview API export`
  );
}
for (const apiName of graphInternalApiNames) {
  rejectMatches(
    "blueprint-graph-api.d.mts",
    declarations["blueprint-graph-api.d.mts"],
    new RegExp(`export (?:function|const) ${apiName}\\b`),
    `${apiName} graph API export`
  );
}

const apiTypes = declarations["blueprint-api-types.d.mts"];
const dataApiType = requireTypeBlock(
  "blueprint-api-types.d.mts",
  apiTypes,
  "BlueprintDataApi"
);
const previewApiType = requireTypeBlock(
  "blueprint-api-types.d.mts",
  apiTypes,
  "BlueprintPreviewApi"
);
requireMatches(
  "blueprint-api-types.d.mts",
  dataApiType,
  /dataUrl: \(arg0: string\) => string;[\s\S]*?loadManifest: \(arg0: BlueprintDataApiOptions \| undefined\) => Promise<Map<string, BlueprintManifestEntry>>;[\s\S]*?loadHtmlCacheEntry: \(arg0: string, arg1: BlueprintDataApiOptions \| undefined\) => Promise<\(?BlueprintHtmlCacheEntry \| null\)?>;/,
  "BlueprintDataApi manifest/cache object shape"
);
requireMatches(
  "blueprint-api-types.d.mts",
  previewApiType,
  /dataUrl: \(arg0: string\) => string;[\s\S]*?resolvePreview: \(arg0: string, arg1: BlueprintDataApiOptions \| undefined\) => Promise<BlueprintPreviewResult>;[\s\S]*?renderNode: \(arg0: Element, arg1: \(string \| BlueprintRenderNodeRequest\), arg2: BlueprintPreviewOptions \| undefined\) => Promise<BlueprintRenderNodeResult>;[\s\S]*?hydrate: \(arg0: Element, arg1: BlueprintPreviewOptions \| undefined\) => boolean;/,
  "BlueprintPreviewApi render object shape"
);
for (const apiName of graphApiNames) {
  rejectMatches(
    "blueprint-api-types.d.mts",
    dataApiType,
    new RegExp(`\\b${apiName}:`),
    `${apiName} on BlueprintDataApi`
  );
  rejectMatches(
    "blueprint-api-types.d.mts",
    previewApiType,
    new RegExp(`\\b${apiName}:`),
    `${apiName} on BlueprintPreviewApi`
  );
}
requireMatches(
  "blueprint-api-types.d.mts",
  apiTypes,
  /export type BlueprintExternalMarkupRenderer = \(payload: BlueprintExternalMarkupPayload, target: Element\) => void \| string \| Node \| Promise<void \| string \| Node>;/,
  "external-markup renderer callback"
);

if (failures.length > 0) {
  console.error("JavaScript API declaration check failed:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("JavaScript API declaration check passed.");
