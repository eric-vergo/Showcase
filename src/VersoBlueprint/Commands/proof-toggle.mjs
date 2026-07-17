// Per-card proof toggle for the two-column node card (Informal.NodeCard).
//
// Two jobs:
//   1. Wire each `.bp_card2_proof_toggle` button: a click flips the single
//      source of truth `data-bp-proof-open` on the closest `.bp_card2`, updates
//      `aria-expanded`, and swaps the quiet action label ("[show]" <-> "[hide]"
//      in `.bp_card2_proof_action`; the "Proof" word is static). Keyboard
//      support is free (it is a real `<button>`). The CSS in NodeCard.lean
//      animates the proof row's height off that attribute, and the metadata
//      rail's footer bulk control calls the exported `setAllProofs`, so this
//      module and the rail coordinate purely through the DOM + this module's
//      exports.
//   2. Relocate the tactic tail (strict 2x2 grid): the whole theorem -- signature
//      plus tactic proof -- is a single highlighted code block on the statement
//      facet (`.bp_card2_formal_stmt details.bp_code_block code.hl.lean.block`).
//      We find the primary theorem's `by`, EXTRACT the tail after it, and MOVE it
//      into `.bp_card2_formal_proof`, re-wrapped in `<pre><code class="hl lean
//      block">` so the highlighting / monospace / horizontal-scroll survive (the
//      extracted nodes already carry their `.token`/`.hl` classes). The signature
//      (everything up to `:= by`) stays in the top-right cell; once relocated, the
//      tail's visibility is governed solely by the proof-row collapse -- there is
//      no separate per-`by` toggle on a card block.
//
// The by-finder / tail-extraction below is COPIED from `installProofHider`
// (ProofReveal.lean): the inline-head IIFE and this ES module run in separate
// scopes, so the logic cannot be imported and is duplicated here on purpose. Keep
// the two in sync. `installProofHider` skips any block inside a `.bp_card2`
// (`if (block.closest('.bp_card2')) return;`), so card blocks are owned only here.

const DECL_KEYWORDS = new Set(["theorem", "lemma", "corollary", "example"]);
const COMMAND_START_KEYWORDS = new Set([
  "theorem", "lemma", "corollary", "example", "def", "abbrev", "instance",
  "axiom", "constant", "opaque", "inductive", "structure", "class", "namespace",
  "section", "end", "open", "local", "attribute", "set_option", "variable",
  "variables", "notation", "infix", "infixl", "infixr", "prefix", "postfix",
  "macro", "syntax", "elab", "initialize", "mutual"
]);

function absIndexBeforeElement(rootNode, el) {
  const r = document.createRange();
  r.setStart(rootNode, 0);
  r.setEndBefore(el);
  return r.toString().length;
}

function locateTextPosition(rootNode, absIndex) {
  const walker = document.createTreeWalker(rootNode, NodeFilter.SHOW_TEXT);
  let seen = 0;
  while (true) {
    const node = walker.nextNode();
    if (!node) break;
    const len = node.nodeValue ? node.nodeValue.length : 0;
    if (absIndex <= seen + len) {
      return { node, offset: absIndex - seen };
    }
    seen += len;
  }
  return null;
}

function lineIndent(text, idx) {
  const lastNl = text.lastIndexOf("\n", Math.max(0, idx - 1));
  const lineStart = lastNl + 1;
  let i = lineStart;
  while (i < idx && text[i] === " ") i++;
  return i - lineStart;
}

function isFirstTokenOnLine(text, idx) {
  const lastNl = text.lastIndexOf("\n", Math.max(0, idx - 1));
  const lineStart = lastNl + 1;
  return /^[ \t]*$/.test(text.slice(lineStart, idx));
}

function isCommandStartText(tokText) {
  if (!tokText) return false;
  if (tokText[0] === "#") return true;
  return COMMAND_START_KEYWORDS.has(tokText);
}

// Find the primary declaration's `by` and the [start, end) text range of the
// tactic tail to relocate. Mirrors installProofHider's segment computation but
// returns only the FIRST decl's tail (the primary theorem); secondary decls in a
// multi-decl block keep their tail in place (intentional -- flagged for QA).
function findPrimaryTail(block) {
  const text = block.textContent || "";
  if (!text) return null;

  const tokenNodes = Array.from(block.querySelectorAll(".token"));
  const keywordNodes = Array.from(block.querySelectorAll(".keyword.token"));

  const allTokens = tokenNodes.map((el) => {
    const tokText = (el.textContent || "").trim();
    const start = absIndexBeforeElement(block, el);
    const end = start + (el.textContent || "").length;
    const firstOnLine = isFirstTokenOnLine(text, start);
    const indent = lineIndent(text, start);
    return { el, tokText, start, end, firstOnLine, indent };
  });

  const commandStarts = allTokens.filter((t) =>
    t.firstOnLine && isCommandStartText(t.tokText)
  );

  const keywordTokens = keywordNodes.map((el) => {
    const tokText = (el.textContent || "").trim();
    const start = absIndexBeforeElement(block, el);
    const end = start + (el.textContent || "").length;
    const indent = lineIndent(text, start);
    return { el, tokText, start, end, indent };
  });

  const declStarts = keywordTokens.filter((t) => DECL_KEYWORDS.has(t.tokText));
  if (declStarts.length === 0) return null;

  // Primary decl = the first one with a matching `by`.
  for (const decl of declStarts) {
    const boundary = commandStarts.find((c) =>
      c.start > decl.start && c.indent <= decl.indent
    );
    const segmentEnd = boundary ? boundary.start : text.length;
    if (segmentEnd <= decl.start) continue;
    const byTok = keywordTokens.find((t) =>
      t.tokText === "by" && t.start > decl.start && t.end <= segmentEnd
    );
    if (!byTok) continue;
    const hideStart = byTok.end;
    if (hideStart >= segmentEnd) continue;
    return { hideStart, hideEnd: segmentEnd };
  }
  return null;
}

// Extract the [hideStart, hideEnd) range from the statement code block and move
// it into `formalCell`, re-wrapped in `<pre><code class="hl lean block">`.
function relocateTail(block, formalCell, range) {
  const hideStartPos = locateTextPosition(block, range.hideStart);
  const hideEndPos = locateTextPosition(block, range.hideEnd);
  if (!hideStartPos || !hideEndPos) return false;

  const domRange = document.createRange();
  domRange.setStart(hideStartPos.node, hideStartPos.offset);
  domRange.setEnd(hideEndPos.node, hideEndPos.offset);
  const fragment = domRange.extractContents();
  if (!fragment.textContent || fragment.textContent.length === 0) return false;

  // Re-wrap in a Lean code container so the highlighted token spans keep their
  // monospace / scroll / formatting in the new cell.
  const pre = document.createElement("pre");
  const code = document.createElement("code");
  code.className = "hl lean block";
  // Trim a single leading newline left over right after `by` so the relocated
  // body starts cleanly at the first tactic line.
  const first = fragment.firstChild;
  if (first && first.nodeType === Node.TEXT_NODE && first.nodeValue &&
      first.nodeValue[0] === "\n") {
    first.nodeValue = first.nodeValue.replace(/^\n/, "");
  }
  code.appendChild(fragment);
  pre.appendChild(code);
  formalCell.replaceChildren(pre);
  return true;
}

function wireCardTail(card) {
  if (card.dataset.bpProofToggleTail === "1") return;
  card.dataset.bpProofToggleTail = "1";

  const formalCell = card.querySelector(".bp_card2_formal_proof");
  if (!formalCell) return;
  const block = card.querySelector(
    ".bp_card2_formal_stmt details.bp_code_block code.hl.lean.block"
  );
  if (!(block instanceof HTMLElement)) return;

  const range = findPrimaryTail(block);
  if (!range) return;
  relocateTail(block, formalCell, range);
}

// Sync one card's toggle button (aria-expanded + the "[show]"/"[hide]" action
// span) with the card's `data-bp-proof-open` source of truth.
export function syncToggleLabel(card) {
  if (!(card instanceof HTMLElement)) return;
  const toggle = card.querySelector(".bp_card2_proof_toggle");
  if (!(toggle instanceof HTMLElement)) return;
  const open = card.getAttribute("data-bp-proof-open") === "true";
  toggle.setAttribute("aria-expanded", open ? "true" : "false");
  const action = toggle.querySelector(".bp_card2_proof_action");
  if (action) action.textContent = open ? "[hide]" : "[show]";
}

// Bulk show/hide for every card on the page (the metadata-rail footer control).
// Sets the per-card `data-bp-proof-open` attribute and keeps each card's own
// toggle in sync. Not persisted: every load starts hidden, and per-card toggles
// override individually afterwards.
export function setAllProofs(open) {
  document.querySelectorAll(".bp_card2").forEach(function (card) {
    if (!(card instanceof HTMLElement)) return;
    card.setAttribute("data-bp-proof-open", open ? "true" : "false");
    syncToggleLabel(card);
  });
}

function wireCardToggle(card) {
  const toggle = card.querySelector(".bp_card2_proof_toggle");
  if (!(toggle instanceof HTMLElement)) return;
  if (toggle.dataset.bpProofToggleBound === "1") return;
  toggle.dataset.bpProofToggleBound = "1";

  toggle.addEventListener("click", function () {
    const open = card.getAttribute("data-bp-proof-open") !== "true";
    card.setAttribute("data-bp-proof-open", open ? "true" : "false");
    syncToggleLabel(card);
  });
}

export function startProofToggle(root = document) {
  const scope = root && root.querySelectorAll ? root : document;
  const cards = scope.querySelectorAll(".bp_card2");
  cards.forEach(function (card) {
    if (!(card instanceof HTMLElement)) return;
    wireCardTail(card);
    wireCardToggle(card);
  });
}

export default { startProofToggle, syncToggleLabel, setAllProofs };
