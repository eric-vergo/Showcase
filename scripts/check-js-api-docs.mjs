import { access, readdir, readFile } from "node:fs/promises";
import path from "node:path";

const docsDir = path.resolve("_out/jsdoc-api");
const failures = [];
const textCache = new Map();

function fail(message) {
  failures.push(message);
}

async function requireReadableFile(relativePath) {
  const absolutePath = path.join(docsDir, relativePath);
  try {
    await access(absolutePath);
  } catch {
    fail(`missing generated docs file: ${relativePath}`);
    return "";
  }
  const text = await readFile(absolutePath, "utf8");
  textCache.set(relativePath, text);
  return text;
}

function requireIncludes(relativePath, text, needle, description) {
  if (!text.includes(needle)) {
    fail(`${relativePath}: missing ${description}`);
  }
}

function requireMatches(relativePath, text, pattern, description) {
  if (!pattern.test(text)) {
    fail(`${relativePath}: missing ${description}`);
  }
}

async function listFiles(relativeDir = "") {
  const absoluteDir = path.join(docsDir, relativeDir);
  const entries = await readdir(absoluteDir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const relativePath = path.join(relativeDir, entry.name);
    if (entry.isDirectory()) {
      files.push(...await listFiles(relativePath));
    } else if (entry.isFile()) {
      files.push(relativePath);
    }
  }
  return files;
}

function localHrefTarget(currentFile, href) {
  if (
    href === "" ||
    href.startsWith("http://") ||
    href.startsWith("https://") ||
    href.startsWith("mailto:") ||
    href.startsWith("javascript:") ||
    href.startsWith("data:")
  ) {
    return null;
  }

  const [filePart, hashPart] = href.split("#", 2);
  const targetFile = filePart === ""
    ? currentFile
    : path.normalize(path.join(path.dirname(currentFile), filePart));
  if (targetFile.startsWith("..") || path.isAbsolute(targetFile)) {
    return { file: targetFile, hash: hashPart || "", invalidPath: true };
  }
  return { file: targetFile, hash: hashPart || "", invalidPath: false };
}

function htmlHasAnchor(html, rawHash) {
  if (!rawHash) return true;

  let hash = rawHash;
  try {
    hash = decodeURIComponent(rawHash);
  } catch {
    hash = rawHash;
  }

  return (
    html.includes(`id="${hash}"`) ||
    html.includes(`id='${hash}'`) ||
    html.includes(`name="${hash}"`) ||
    html.includes(`name='${hash}'`)
  );
}

async function checkLocalLinks() {
  const files = await listFiles();
  const allFiles = new Set(files);
  const htmlFiles = files.filter((file) => file.endsWith(".html"));
  const hrefPattern = /\bhref=(["'])(.*?)\1/g;

  for (const htmlFile of htmlFiles) {
    const html = textCache.get(htmlFile) || await requireReadableFile(htmlFile);
    for (const match of html.matchAll(hrefPattern)) {
      const href = match[2].replaceAll("&amp;", "&");
      const target = localHrefTarget(htmlFile, href);
      if (!target) continue;
      if (target.invalidPath || !allFiles.has(target.file)) {
        fail(`${htmlFile}: broken local link to ${href}`);
        continue;
      }
      if (target.hash) {
        const targetHtml = textCache.get(target.file) || await requireReadableFile(target.file);
        if (!htmlHasAnchor(targetHtml, target.hash)) {
          fail(`${htmlFile}: broken local anchor ${href}`);
        }
      }
    }
  }
}

const pages = {
  "index.html": await requireReadableFile("index.html"),
  "module-blueprint-api-types.html": await requireReadableFile("module-blueprint-api-types.html"),
  "module-blueprint-data-api.html": await requireReadableFile("module-blueprint-data-api.html"),
  "module-blueprint-graph-api.html": await requireReadableFile("module-blueprint-graph-api.html"),
  "module-blueprint-preview-api.html": await requireReadableFile("module-blueprint-preview-api.html"),
  "jsdoc-type-links.js": await requireReadableFile("jsdoc-type-links.js")
};

requireIncludes(
  "index.html",
  pages["index.html"],
  "Verso Blueprint JavaScript API",
  "landing-page title"
);
requireIncludes(
  "index.html",
  pages["index.html"],
  "module-blueprint-preview-api.html",
  "preview API guide link"
);
requireIncludes(
  "index.html",
  pages["index.html"],
  "module-blueprint-api-types.html",
  "shared API types guide link"
);

requireMatches(
  "module-blueprint-preview-api.html",
  pages["module-blueprint-preview-api.html"],
  /id="\.createPreview"[\s\S]*?&rarr; \{BlueprintPreviewApi\}/,
  "createPreview return type"
);
requireMatches(
  "module-blueprint-preview-api.html",
  pages["module-blueprint-preview-api.html"],
  /id="\.renderNode"[\s\S]*?&rarr; \{Promise\.&lt;BlueprintRenderNodeResult>\}/,
  "renderNode result type"
);
requireMatches(
  "module-blueprint-preview-api.html",
  pages["module-blueprint-preview-api.html"],
  /<script src="jsdoc-type-links\.js"><\/script>/,
  "typedef-linking script"
);

requireMatches(
  "module-blueprint-data-api.html",
  pages["module-blueprint-data-api.html"],
  /id="\.createPreviewData"[\s\S]*?&rarr; \{BlueprintDataApi\}/,
  "createPreviewData return type"
);
requireMatches(
  "module-blueprint-graph-api.html",
  pages["module-blueprint-graph-api.html"],
  /id="\.loadGraphs"[\s\S]*?Load graph variants from this generated site's default manifest\./,
  "loadGraphs documentation"
);

for (const typeName of [
  "BlueprintDataApi",
  "BlueprintPreviewApi",
  "BlueprintRenderNodeRequest",
  "BlueprintRenderNodeResult",
  "BlueprintExternalMarkupPreference"
]) {
  requireIncludes(
    "module-blueprint-api-types.html",
    pages["module-blueprint-api-types.html"],
    `id="~${typeName}"`,
    `${typeName} typedef anchor`
  );
  requireIncludes(
    "jsdoc-type-links.js",
    pages["jsdoc-type-links.js"],
    `"${typeName}"`,
    `${typeName} client-side link mapping`
  );
}

requireIncludes(
  "jsdoc-type-links.js",
  pages["jsdoc-type-links.js"],
  "module-blueprint-api-types.html#~",
  "typedef target prefix"
);

await checkLocalLinks();

if (failures.length > 0) {
  console.error("JavaScript API docs smoke check failed:");
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log("JavaScript API docs smoke check passed.");
