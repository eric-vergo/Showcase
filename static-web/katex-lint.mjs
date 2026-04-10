import katex from "../.lake/packages/verso/vendored-js/katex/katex.mjs";

function sanitizeMessage(message) {
  return String(message ?? "")
    .replace(/\u0332/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function readPayload() {
  const raw = process.argv[2] ?? "";
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

const payload = readPayload();
if (!payload || typeof payload.source !== "string") {
  process.exit(1);
}

const texPrelude =
  typeof payload.texPrelude === "string" ? payload.texPrelude.trim() : "";
const source = payload.source;
const displayMode = payload.mode === "display";
const combinedInput = texPrelude ? `${texPrelude}\n${source}` : source;
const sourceOffset = texPrelude ? texPrelude.length + 1 : 0;

function toCodepointIndex(input, utf16Index) {
  return Array.from(input.slice(0, utf16Index)).length;
}

function toCodepointLength(input, utf16Start, utf16Length) {
  return Array.from(input.slice(utf16Start, utf16Start + utf16Length)).length;
}

function renderError(
  error,
  input,
  { sourceText = null, sourceOffsetUtf16 = 0, inPrelude = null } = {}
) {
  const positionUtf16 =
    typeof error === "object" &&
    error !== null &&
    typeof error.position === "number"
      ? error.position
      : null;
  const lengthUtf16 =
    typeof error === "object" &&
    error !== null &&
    typeof error.length === "number"
      ? error.length
      : null;
  const resolvedPrelude =
    typeof inPrelude === "boolean"
      ? inPrelude
      : typeof positionUtf16 === "number" && positionUtf16 < sourceOffsetUtf16;
  const position =
    typeof positionUtf16 === "number"
      ? toCodepointIndex(input, positionUtf16)
      : null;
  const length =
    typeof positionUtf16 === "number" && typeof lengthUtf16 === "number"
      ? toCodepointLength(input, positionUtf16, lengthUtf16)
      : null;
  const sourcePosition =
    sourceText !== null &&
    !resolvedPrelude &&
    typeof positionUtf16 === "number"
      ? toCodepointIndex(sourceText, Math.max(positionUtf16 - sourceOffsetUtf16, 0))
      : null;
  const sourceLength =
    sourceText !== null &&
    !resolvedPrelude &&
    typeof positionUtf16 === "number" &&
    typeof lengthUtf16 === "number"
      ? toCodepointLength(
          sourceText,
          Math.max(positionUtf16 - sourceOffsetUtf16, 0),
          lengthUtf16
        )
      : null;
  const message = sanitizeMessage(
    typeof error === "object" &&
      error !== null &&
      typeof error.rawMessage === "string"
      ? error.rawMessage
      : error instanceof Error
        ? error.message
        : String(error)
  );
  return {
    ok: false,
    message,
    position,
    length,
    sourcePosition,
    sourceLength,
    inPrelude: resolvedPrelude,
  };
}

if (texPrelude) {
  try {
    katex.renderToString(texPrelude, { throwOnError: true, displayMode: false });
  } catch (error) {
    process.stdout.write(
      JSON.stringify(renderError(error, texPrelude, { inPrelude: true }))
    );
    process.exit(0);
  }
}

try {
  katex.renderToString(combinedInput, { throwOnError: true, displayMode });
  process.stdout.write(JSON.stringify({ ok: true }));
} catch (error) {
  process.stdout.write(
    JSON.stringify(
      renderError(error, combinedInput, {
        sourceText: source,
        sourceOffsetUtf16: sourceOffset,
      })
    )
  );
}
