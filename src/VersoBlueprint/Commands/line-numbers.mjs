// Line-number gutter for the card signature / proof / value Lean code blocks.
//
// Highlighted Lean blocks are a flat stream of token `<span>`s with newlines living
// in `.inter-text` whitespace spans (structural line breaks) and, separately, inside
// `.hover-info` docstring popovers (which must NOT count as code-line breaks). This
// module walks each targeted container's TOP-LEVEL children, splits the stream into
// logical lines at those structural newlines only, wraps each line in a
// `<span class="bp_code_line">`, and adds `.bp-line-numbered` to the container. A CSS
// counter then renders the gutter (Commands/DocsChrome.lean).
//
// Copy safety: the line numbers are `::before` counters (never in `textContent`), and
// the split keeps every original token node plus a literal "\n" between line spans, so
// the container's `textContent` — what the copy button reads — stays byte-identical.
//
// Runs AFTER proof-toggle.mjs (which may relocate a tactic tail); the relocated block
// is a plain `code.hl.lean.block` that this module does not target, so numbering never
// interferes with the relocation. Numbering is 1-based per block (each block is an
// independently captured fragment, so a shared absolute source line is not available).

const SELECTOR =
  "pre.bp_external_decl_signature, .bp_card2_proof_source > code.hl.lean.block";

function isInterText(node) {
  return (
    node.nodeType === Node.ELEMENT_NODE &&
    node.classList &&
    node.classList.contains("inter-text")
  );
}

function numberLines(container) {
  if (!(container instanceof HTMLElement)) return;
  if (container.dataset.bpLineNumbers === "1") return;
  const kids = Array.prototype.slice.call(container.childNodes);
  if (kids.length === 0) return;

  const lines = [[]];
  function cur() {
    return lines[lines.length - 1];
  }

  for (let k = 0; k < kids.length; k++) {
    const node = kids[k];
    let text = null;
    if (node.nodeType === Node.TEXT_NODE) {
      text = node.nodeValue || "";
    } else if (isInterText(node)) {
      // Whitespace container: this is where structural line breaks live.
      text = node.textContent || "";
    }
    if (text !== null) {
      if (text.indexOf("\n") === -1) {
        if (text.length > 0) cur().push(document.createTextNode(text));
      } else {
        const parts = text.split("\n");
        for (let i = 0; i < parts.length; i++) {
          if (i > 0) lines.push([]);
          if (parts[i].length > 0) cur().push(document.createTextNode(parts[i]));
        }
      }
    } else {
      // Atomic token element (its `.hover-info` docstring may contain newlines that
      // must not split code lines): keep the whole node on the current line.
      cur().push(node);
    }
  }

  // Drop a single trailing empty line (a source file's terminal newline).
  if (lines.length > 1 && lines[lines.length - 1].length === 0) lines.pop();
  if (lines.length <= 1 && lines[0].length === 0) return;

  container.textContent = "";
  for (let i = 0; i < lines.length; i++) {
    const span = document.createElement("span");
    span.className = "bp_code_line";
    lines[i].forEach(function (n) {
      span.appendChild(n);
    });
    container.appendChild(span);
    // Keep the real newline between lines so copy-to-clipboard is byte-identical.
    if (i < lines.length - 1) {
      container.appendChild(document.createTextNode("\n"));
    }
  }
  container.classList.add("bp-line-numbered");
  container.dataset.bpLineNumbers = "1";
}

export function startLineNumbers(root = document) {
  if (typeof document === "undefined") return;
  const scope = root && root.querySelectorAll ? root : document;
  scope.querySelectorAll(SELECTOR).forEach(function (el) {
    try {
      numberLines(el);
    } catch (_e) {
      /* never let one odd block break the page */
    }
  });
}

export function bootLineNumbers() {
  if (typeof document === "undefined") return;
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      startLineNumbers(document);
    }, { once: true });
  } else {
    startLineNumbers(document);
  }
}

export default { startLineNumbers, bootLineNumbers };
