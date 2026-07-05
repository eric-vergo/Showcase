// Const-token short-name display.
//
// On DOM-ready, shortens the *visible* text of highlighted `.const.token`
// elements whose text begins with the configured project prefix + "." (the
// `verso.blueprint.declNamePrefix`, surfaced as the registry's `namePrefix`),
// keeping the fully-qualified name on the element's `title` for hover. This
// mirrors the server-side short-name treatment (NodeCard.shortDeclName /
// registry `shortName`) for the one surface that stays fully-qualified: inline
// Lean code tokens (verso core owns their markup; we do not touch it).
//
// Offline-first + self-contained: the prefix is read from
// `-verso-data/decl-registry.json` (same-origin, resolved against the page
// `<base href>`). When that fetch is blocked (file://) or the prefix is empty,
// this is a no-op and every token keeps its fully-qualified text. No external
// deps. Only the token's *first child text node* is rewritten, so a node/decl-
// page signature token — whose FQ name is a leading text node followed by a
// nested `<span class="hover-info">` popup — is shortened without disturbing the
// hover structure (chapter-page tokens are a lone text node and are handled by
// the same path). The pass is idempotent (a shortened token no longer starts
// with the prefix) and re-runs via a debounced MutationObserver so late-injected
// DOM (graph-modal cards cloned from <template>, dynamically-built panels) is
// shortened too.

function shortenConstTokens(prefix) {
  if (!prefix) return;
  const pre = prefix + ".";
  const tokens = document.querySelectorAll(".const.token");
  tokens.forEach(function (el) {
    // Rewrite only the token's first child when it is a text node, leaving any
    // sibling structure (e.g. a nested `<span class="hover-info">` popup on
    // node/decl-page signature tokens) untouched. Chapter-page tokens are a lone
    // text node and take the same path. Idempotent: once shortened, the text no
    // longer starts with the prefix, so a re-pass is a cheap no-op.
    const node = el.firstChild;
    if (!node || node.nodeType !== 3) return;
    const full = node.nodeValue;
    if (!full || full.indexOf(pre) !== 0 || full.length <= pre.length) return;
    node.nodeValue = full.slice(pre.length);
    if (!el.hasAttribute("title")) el.setAttribute("title", full);
  });
}

// Re-run the shorten pass when new DOM is injected (graph-modal cards, panels).
// Debounced so a burst of mutations coalesces into one pass; we only observe
// `childList` (never characterData/attributes), so our own nodeValue/title edits
// do not feed the observer back into itself. Page-lifetime; never disconnected.
let observedPrefix = "";
let rescanTimer = null;

function scheduleRescan() {
  if (rescanTimer !== null) return;
  rescanTimer = setTimeout(function () {
    rescanTimer = null;
    shortenConstTokens(observedPrefix);
  }, 150);
}

function observeMutations(prefix) {
  if (!prefix || typeof MutationObserver !== "function" || !document.body) return;
  observedPrefix = prefix;
  const observer = new MutationObserver(function (records) {
    for (let i = 0; i < records.length; i++) {
      if (records[i].addedNodes && records[i].addedNodes.length > 0) {
        scheduleRescan();
        return;
      }
    }
  });
  observer.observe(document.body, { childList: true, subtree: true });
}

function readNamePrefix() {
  if (typeof fetch !== "function") return Promise.resolve("");
  return fetch("-verso-data/decl-registry.json", { credentials: "same-origin" })
    .then(function (resp) {
      if (!resp.ok) throw new Error("decl-registry.json: " + resp.status);
      return resp.json();
    })
    .then(function (reg) {
      return reg && typeof reg.namePrefix === "string" ? reg.namePrefix : "";
    })
    .catch(function () {
      // Offline / file:// / missing artifact: leave tokens fully-qualified.
      return "";
    });
}

function install() {
  readNamePrefix().then(function (prefix) {
    shortenConstTokens(prefix);
    observeMutations(prefix);
  });
}

export function startConstTokens() {
  if (typeof document === "undefined") return;
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", install, { once: true });
  } else {
    install();
  }
}

export default { startConstTokens };
