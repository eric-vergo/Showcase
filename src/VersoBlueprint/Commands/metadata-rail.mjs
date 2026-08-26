// Site-wide "Properties & Dependencies" metadata rail.
//
// A fixed right `<aside>` injected on every page (no verso-core template edit —
// same asset-injection pattern as the banner nav). It shows the properties +
// dependencies of whatever declaration is currently selected on the shared
// selection bus (`window.VersoBlueprint.selection`, see selection-bus.mjs), fed
// by node-card clicks, graph node clicks (graph.mjs), and the page's default
// selection. A pinned footer carries the absorbed page-level controls: the
// theme (Auto | Light | Dark, via `window.VersoBlueprint.colorScheme`) and the
// bulk proof show/hide (via proof-toggle.mjs `setAllProofs`).
//
// Data sourcing (offline-first):
//   * Each node card embeds a slim identity record inline
//     (`<script class="bp-decl-meta">`, see NodeCard.declMetaJson). These are the
//     current page's decls; the rail first-paints identity + location + the node
//     link from them with no network — so node-page default selection and card
//     clicks work under file://.
//   * The full per-decl data (parameters, uses / used-by, see-also, signature)
//     lives in `-verso-data/decl-registry.json`, fetched lazily on first
//     selection (resolved against the page `<base href>`, the site root). When the
//     fetch is blocked (file://) those sections degrade to a quiet
//     "unavailable offline" note rather than erroring.

import { installSelectionBus } from "./selection-bus.mjs";
import { setAllProofs } from "./proof-toggle.mjs";

const RAIL_ID = "bp-metadata-rail";
const BODY_ID = "bp-metadata-rail-body";
// The rail is *always* docked along the right edge on every page (no drawer /
// edge tab / collapse / breakpoint). Its width is user-resizable via a drag
// handle (buildResizeHandle); CSS clamps the stored width so the content column
// keeps a minimum width at every viewport (see MetadataRail.lean).
const RAIL_WIDTH_STORAGE_KEY = "bp-rail-width";
// Width clamp bounds (px), mirroring the clamp() for --bp-rail-user-width in
// MetadataRail.lean (14rem / 32rem at the default 16px root). Keep in sync.
const RAIL_MIN_WIDTH = 224;
const RAIL_MAX_WIDTH = 512;
const RAIL_KEY_STEP = 16;
const RAIL_KEY_STEP_LARGE = 64;
const SEE_ALSO_CAP = 8;
const DEP_CAP = 60; // guard against pathologically long used-by lists.

let bus = null;
let registryState = "idle"; // idle | loading | loaded | error
let registryPromise = null;
let registryByName = null; // Map<name, entry>
let registryByModule = null; // Map<module, name[]>
let registryNamePrefix = ""; // registry v2 top-level namePrefix (short names)
const inlineMeta = new Map(); // Map<name, slim record>

let railEl = null;
let bodyEl = null;
let handleEl = null; // the width drag handle.

const STATUS_LABELS = {
  proved: "Proved",
  missing: "Missing",
  axiomLike: "Axiom",
  containsSorry: "Sorry"
};

// Complete definitions read "Formalized" (they have no proof to prove); complete
// theorem-likes read "Proved". Kind-aware, mirroring the server-side wording.
function statusLabelFor(kind, status) {
  if (status === "proved" && kind === "Definition") return "Formalized";
  return STATUS_LABELS[status] || status;
}

/* -------------------------------------------------------------------------- */
/* Small DOM helper                                                           */
/* -------------------------------------------------------------------------- */

function el(tag, opts, children) {
  const node = document.createElement(tag);
  const o = opts || {};
  if (o.class) node.className = o.class;
  if (o.text != null) node.textContent = String(o.text);
  if (o.attrs) {
    Object.keys(o.attrs).forEach(function (k) {
      if (o.attrs[k] != null) node.setAttribute(k, String(o.attrs[k]));
    });
  }
  if (Array.isArray(children)) {
    children.forEach(function (c) {
      if (c) node.appendChild(c);
    });
  }
  return node;
}

/* -------------------------------------------------------------------------- */
/* Tooltip primitive (themed, keyboard + hover, escapes the rail's overflow)  */
/* -------------------------------------------------------------------------- */

// A single shared bubble reused by every trigger. `.bp-rail-body` is
// `overflow-y: auto`, so a tooltip anchored inside it would be clipped; the bubble
// is therefore `position: fixed` (see MetadataRail.lean) and positioned from the
// trigger's viewport rect, flipping above/below to stay on screen. The bubble is
// only referenced by `aria-describedby` while shown, so screen readers announce the
// gloss on focus and nothing stale when hidden.
const TOOLTIP_ID = "bp-rail-tooltip";
let tooltipEl = null;
let tooltipTrigger = null;
let tooltipDismissBound = false;

function ensureTooltipEl() {
  if (tooltipEl) return tooltipEl;
  tooltipEl = el("div", {
    class: "bp-rail-tooltip",
    attrs: { id: TOOLTIP_ID, role: "tooltip", "aria-hidden": "true" }
  });
  document.body.appendChild(tooltipEl);
  return tooltipEl;
}

function positionTooltip(trigger) {
  const bubble = tooltipEl;
  if (!bubble) return;
  const r = trigger.getBoundingClientRect();
  const margin = 8;
  const bw = bubble.offsetWidth;
  const bh = bubble.offsetHeight;
  // Horizontal: align the bubble's left with the trigger, clamped into the viewport.
  let left = Math.max(margin, Math.min(r.left, window.innerWidth - bw - margin));
  // Vertical: prefer above the trigger; flip below when there isn't room.
  let top = r.top - bh - margin;
  if (top < margin) top = r.bottom + margin;
  bubble.style.left = left + "px";
  bubble.style.top = top + "px";
}

function onTooltipDismiss() {
  hideTooltip();
}

function showTooltip(trigger, text) {
  ensureTooltipEl();
  tooltipEl.textContent = text;
  tooltipTrigger = trigger;
  trigger.setAttribute("aria-describedby", TOOLTIP_ID);
  tooltipEl.setAttribute("aria-hidden", "false");
  tooltipEl.classList.add("bp-rail-tooltip-visible");
  positionTooltip(trigger);
  if (!tooltipDismissBound) {
    // A fixed bubble drifts from the trigger when the rail body / page scrolls, so
    // dismiss on any scroll (capture: catches the rail body's own scroll) or resize.
    window.addEventListener("scroll", onTooltipDismiss, true);
    window.addEventListener("resize", onTooltipDismiss);
    tooltipDismissBound = true;
  }
}

function hideTooltip() {
  if (tooltipDismissBound) {
    window.removeEventListener("scroll", onTooltipDismiss, true);
    window.removeEventListener("resize", onTooltipDismiss);
    tooltipDismissBound = false;
  }
  if (tooltipTrigger) {
    tooltipTrigger.removeAttribute("aria-describedby");
    tooltipTrigger = null;
  }
  if (!tooltipEl) return;
  tooltipEl.classList.remove("bp-rail-tooltip-visible");
  tooltipEl.setAttribute("aria-hidden", "true");
}

// Attach a hover/focus tooltip carrying `text` to `trigger`. The trigger is made
// keyboard-focusable when it isn't already, so the gloss is reachable without a
// pointer. Idempotent per element via a `data-bp-tip` guard.
function attachTooltip(trigger, text) {
  if (!trigger || trigger.getAttribute("data-bp-tip") === "1") return;
  trigger.setAttribute("data-bp-tip", "1");
  if (!trigger.hasAttribute("tabindex")) trigger.setAttribute("tabindex", "0");
  trigger.addEventListener("mouseenter", function () { showTooltip(trigger, text); });
  trigger.addEventListener("mouseleave", hideTooltip);
  trigger.addEventListener("focus", function () { showTooltip(trigger, text); });
  trigger.addEventListener("blur", hideTooltip);
  trigger.addEventListener("keydown", function (ev) {
    if (ev.key === "Escape") hideTooltip();
  });
}

/* -------------------------------------------------------------------------- */
/* Rail shell                                                                 */
/* -------------------------------------------------------------------------- */

// Pinned footer: the absorbed page-level controls (theme + text size + bulk proof
// visibility). The aside is a fixed flex column, so a `flex: 0 0 auto` footer
// pins below the scrollable body naturally. Theme drives the page-global
// `window.VersoBlueprint.colorScheme` API published by the pre-paint applier
// (ColorScheme.lean); the proofs row calls proof-toggle.mjs's `setAllProofs`
// and only renders when the page has proof toggles (same condition as the
// retired floating widget; not persisted).
function buildFooter() {
  const footer = el("div", { class: "bp-rail-footer" });

  const ns = window.VersoBlueprint || {};
  const schemeApi = ns.colorScheme || null;
  if (schemeApi && typeof schemeApi.get === "function" && typeof schemeApi.set === "function") {
    const group = el("div", {
      class: "bp-rail-theme",
      attrs: { role: "radiogroup", "aria-label": "Color scheme" }
    });
    function syncChecked() {
      const current = schemeApi.get();
      group.querySelectorAll(".bp-rail-theme-option").forEach(function (b) {
        b.setAttribute("aria-checked", b.getAttribute("data-scheme") === current ? "true" : "false");
      });
    }
    [["auto", "Auto"], ["light", "Light"], ["dark", "Dark"]].forEach(function (pair) {
      const btn = el("button", {
        class: "bp-rail-theme-option",
        attrs: {
          type: "button",
          role: "radio",
          "aria-checked": "false",
          "data-scheme": pair[0]
        },
        text: pair[1]
      });
      btn.addEventListener("click", function () {
        schemeApi.set(pair[0]);
        syncChecked();
      });
      group.appendChild(btn);
    });
    // Keep the segmented control honest if the scheme changes elsewhere
    // (the applier fires this event on every apply).
    window.addEventListener("bp-color-scheme-change", syncChecked);
    syncChecked();
    footer.appendChild(el("div", { class: "bp-rail-footer-row" }, [
      el("span", { class: "bp-rail-footer-label", text: "Theme" }),
      group
    ]));
  }

  // Text size: three "A" buttons (small / medium / large) driving the pre-paint
  // text-size applier (TextSize.lean → window.VersoBlueprint.textSize). The visible
  // glyph is "A" at three CSS sizes; the accessible name carries the size word.
  const textApi = ns.textSize || null;
  if (textApi && typeof textApi.get === "function" && typeof textApi.set === "function") {
    const tgroup = el("div", {
      class: "bp-rail-textsize",
      attrs: { role: "radiogroup", "aria-label": "Text size" }
    });
    function syncTextChecked() {
      const current = textApi.get();
      tgroup.querySelectorAll(".bp-rail-textsize-option").forEach(function (b) {
        b.setAttribute("aria-checked", b.getAttribute("data-size") === current ? "true" : "false");
      });
    }
    [["small", "Small text"], ["medium", "Medium text"], ["large", "Large text"]].forEach(function (t) {
      const btn = el("button", {
        class: "bp-rail-textsize-option",
        attrs: {
          type: "button",
          role: "radio",
          "aria-checked": "false",
          "aria-label": t[1],
          "data-size": t[0]
        },
        text: "A"
      });
      btn.addEventListener("click", function () {
        textApi.set(t[0]);
        syncTextChecked();
      });
      tgroup.appendChild(btn);
    });
    window.addEventListener("bp-text-size-change", syncTextChecked);
    syncTextChecked();
    footer.appendChild(el("div", { class: "bp-rail-footer-row" }, [
      el("span", { class: "bp-rail-footer-label", text: "Text" }),
      tgroup
    ]));
  }

  if (document.querySelector(".bp_card2_proof_toggle")) {
    const showBtn = el("button", {
      class: "bp-rail-proof-action",
      attrs: { type: "button" },
      text: "show all"
    });
    showBtn.addEventListener("click", function () { setAllProofs(true); });
    const hideBtn = el("button", {
      class: "bp-rail-proof-action",
      attrs: { type: "button" },
      text: "hide all"
    });
    hideBtn.addEventListener("click", function () { setAllProofs(false); });
    footer.appendChild(el("div", { class: "bp-rail-footer-row" }, [
      el("span", { class: "bp-rail-footer-label", text: "Proofs" }),
      el("div", { class: "bp-rail-proofs" }, [showBtn, hideBtn])
    ]));
  }

  return footer.childNodes.length > 0 ? footer : null;
}

/* -------------------------------------------------------------------------- */
/* Width resize handle (mirrors verso-core toc-resize.js)                     */
/* -------------------------------------------------------------------------- */

function railWidth() {
  return railEl ? railEl.getBoundingClientRect().width : RAIL_MIN_WIDTH;
}

function syncHandleAria() {
  if (!handleEl) return;
  const width = Math.round(railWidth());
  handleEl.setAttribute("aria-valuenow", String(width));
  handleEl.setAttribute("aria-valuetext", width + " pixels");
}

// Record a preferred rail width in --bp-rail-user-width. The stylesheet clamps
// it to the viewport, so this only bounds the stored value to the absolute
// [MIN, MAX] range.
function setRailWidth(width, persist) {
  const next = Math.round(Math.max(RAIL_MIN_WIDTH, Math.min(RAIL_MAX_WIDTH, width)));
  document.documentElement.style.setProperty("--bp-rail-user-width", next + "px");
  syncHandleAria();
  if (persist) {
    try {
      localStorage.setItem(RAIL_WIDTH_STORAGE_KEY, String(next));
    } catch (_e) {
      /* storage may be disabled; the width still applies for this session */
    }
  }
}

// A vertical drag handle at the rail's left edge (pointer capture + keyboard),
// mirroring verso-core's toc-resize.js. The rail is fixed to the right, so
// dragging left widens it. Restores the saved width on load and persists on
// drop / keyboard change. Appended to <body> like the rail itself.
function buildResizeHandle() {
  if (document.querySelector(".bp-rail-resize-handle")) return;
  const handle = el("div", {
    class: "bp-rail-resize-handle",
    attrs: {
      role: "separator",
      "aria-orientation": "vertical",
      "aria-label": "Resize properties panel",
      "aria-valuemin": String(RAIL_MIN_WIDTH),
      "aria-valuemax": String(RAIL_MAX_WIDTH),
      tabindex: "0"
    }
  });
  handleEl = handle;

  // Restore any saved width (CSS falls back to the default when unset).
  let saved = NaN;
  try {
    const v = localStorage.getItem(RAIL_WIDTH_STORAGE_KEY);
    if (v !== null) saved = Number(v);
  } catch (_e) {
    /* leave the default width in place */
  }
  if (Number.isFinite(saved)) setRailWidth(saved, false);
  else syncHandleAria();

  let activePointer = null;
  let startX = 0;
  let startWidth = 0;

  handle.addEventListener("pointerdown", function (ev) {
    activePointer = ev.pointerId;
    startX = ev.clientX;
    startWidth = railWidth();
    handle.setPointerCapture(ev.pointerId);
    handle.classList.add("dragging");
    document.body.style.userSelect = "none";
    document.body.style.cursor = "col-resize";
    ev.preventDefault();
  });
  handle.addEventListener("pointermove", function (ev) {
    if (activePointer !== ev.pointerId) return;
    // Rail is on the right edge: dragging left (smaller clientX) widens it.
    setRailWidth(startWidth - (ev.clientX - startX), false);
  });
  function endDrag(ev) {
    if (activePointer !== ev.pointerId) return;
    activePointer = null;
    handle.releasePointerCapture(ev.pointerId);
    handle.classList.remove("dragging");
    document.body.style.userSelect = "";
    document.body.style.cursor = "";
    setRailWidth(railWidth(), true);
  }
  handle.addEventListener("pointerup", endDrag);
  handle.addEventListener("pointercancel", endDrag);

  handle.addEventListener("keydown", function (ev) {
    const step = ev.shiftKey ? RAIL_KEY_STEP_LARGE : RAIL_KEY_STEP;
    switch (ev.key) {
      case "ArrowLeft": setRailWidth(railWidth() + step, true); ev.preventDefault(); break;
      case "ArrowRight": setRailWidth(railWidth() - step, true); ev.preventDefault(); break;
      case "Home": setRailWidth(RAIL_MIN_WIDTH, true); ev.preventDefault(); break;
      case "End": setRailWidth(RAIL_MAX_WIDTH, true); ev.preventDefault(); break;
    }
  });

  window.addEventListener("resize", syncHandleAria);
  document.body.appendChild(handle);
}

function buildRail() {
  if (document.getElementById(RAIL_ID)) return;

  const header = el("div", { class: "bp-rail-header" }, [
    el("span", { class: "bp-rail-title", text: "Properties & Dependencies" })
  ]);

  bodyEl = el("div", { class: "bp-rail-body", attrs: { id: BODY_ID } });

  const footer = buildFooter();

  // Always present and open on every page; `aria-hidden` stays "false".
  railEl = el("aside", {
    attrs: {
      id: RAIL_ID,
      "aria-label": "Properties and dependencies",
      "aria-hidden": "false"
    }
  }, [header, bodyEl, footer]);

  document.body.appendChild(railEl);
  // Gate the <main> right-margin reservation on the rail actually being present
  // (see MetadataRail.lean): pages without an injected rail get no dead margin.
  document.body.classList.add("bp-rail-present");
  buildResizeHandle();

  renderEmpty();
}

/* -------------------------------------------------------------------------- */
/* Inline slim records + declaration registry                                 */
/* -------------------------------------------------------------------------- */

function collectInlineMeta() {
  document.querySelectorAll(".bp-decl-meta[data-bp-decl]").forEach(function (node) {
    const name = (node.getAttribute("data-bp-decl") || "").trim();
    if (!name || inlineMeta.has(name)) return;
    try {
      const rec = JSON.parse(node.textContent || "null");
      if (rec && typeof rec === "object") inlineMeta.set(name, rec);
    } catch (_e) {
      /* ignore malformed payloads */
    }
  });
}

function indexRegistry(registry) {
  registryByName = new Map();
  registryByModule = new Map();
  registryNamePrefix = (registry && typeof registry.namePrefix === "string")
    ? registry.namePrefix
    : "";
  const decls = registry && Array.isArray(registry.decls) ? registry.decls : [];
  decls.forEach(function (entry) {
    if (!entry || !entry.name) return;
    registryByName.set(entry.name, entry);
    const mod = entry.moduleName || "";
    if (!registryByModule.has(mod)) registryByModule.set(mod, []);
    registryByModule.get(mod).push(entry.name);
  });
}

function ensureRegistry() {
  if (registryPromise) return registryPromise;
  registryState = "loading";
  registryPromise = fetch("-verso-data/decl-registry.json", {
    credentials: "same-origin"
  })
    .then(function (resp) {
      if (!resp.ok) throw new Error("decl-registry.json: " + resp.status);
      return resp.json();
    })
    .then(function (registry) {
      indexRegistry(registry);
      registryState = "loaded";
      return registryByName;
    })
    .catch(function (_err) {
      // Offline / file:// / missing artifact: degrade gracefully; the rail keeps
      // whatever inline identity it has and notes that the rest is unavailable.
      registryState = "error";
      return null;
    });
  return registryPromise;
}

/* -------------------------------------------------------------------------- */
/* View model (registry ∪ inline)                                             */
/* -------------------------------------------------------------------------- */

function viewModel(name, hintMeta) {
  const reg = registryByName ? registryByName.get(name) : null;
  const inl = inlineMeta.get(name) || (hintMeta && hintMeta.name === name ? hintMeta : null);
  if (!reg && !inl) {
    return { name: name, fromRegistry: false, known: false };
  }
  const startLine = reg && reg.range ? reg.range.pos.line : inl ? inl.startLine : undefined;
  const endLine = reg && reg.range ? reg.range.endPos.line : inl ? inl.endLine : undefined;
  return {
    name: name,
    known: true,
    fromRegistry: !!reg,
    kind: (reg && reg.kind) || (inl && inl.kind) || "",
    status: (reg && reg.status) || (inl && inl.status) || "",
    module: (reg && reg.moduleName) || (inl && inl.module) || "",
    sourcePath: reg ? reg.sourcePath : undefined,
    startLine: startLine,
    endLine: endLine,
    title: (inl && inl.title) || "",
    signatureText: reg ? reg.signatureText : undefined,
    params: reg ? reg.params || [] : undefined,
    statementDeps: reg ? reg.statementDeps || [] : undefined,
    proofDeps: reg ? reg.proofDeps || [] : undefined,
    usedBy: reg ? reg.usedBy || [] : undefined,
    authored: reg ? !!reg.authored : inl ? true : false,
    nodeHref: (reg && reg.nodeHref) || (inl && inl.nodeHref) || undefined,
    // Registry v2 fields (Stage 2): short display name, own decl-page href for
    // unwired decls, rendered docstring, source link, longest-path metrics.
    shortName: (reg && reg.shortName) || (inl && inl.shortName) || "",
    declHref: (reg && reg.declHref) || (inl && inl.declHref) || undefined,
    docstringHtml: reg ? reg.docstringHtml : undefined,
    sourceHref: reg ? reg.sourceHref : undefined,
    depth: reg && reg.depth != null ? reg.depth : undefined,
    height: reg && reg.height != null ? reg.height : undefined,
    // Registry v3: the caveat scan. `undefined` is the NOT-SCANNED state — a v2
    // registry, or a build with verso.blueprint.trust.statementCaveats off — and is
    // deliberately distinct from a scan that ran and matched nothing.
    scan: reg && reg.scan && typeof reg.scan === "object" ? reg.scan : undefined
  };
}

/** Short display name for a declaration (registry shortName, else the registry
 * namePrefix stripped, else an inline-meta shortName, else the FQ name). */
function shortNameFor(name) {
  const reg = registryByName ? registryByName.get(name) : null;
  if (reg && reg.shortName) return reg.shortName;
  if (
    registryNamePrefix &&
    name.length > registryNamePrefix.length + 1 &&
    name.indexOf(registryNamePrefix + ".") === 0
  ) {
    return name.slice(registryNamePrefix.length + 1);
  }
  const inl = inlineMeta.get(name);
  if (inl && inl.shortName) return inl.shortName;
  return name;
}

/** Prefix-strip a module path the same way shortNameFor does a decl name
 * (mirrors the server-side NodeCard.shortModuleName; identity when there's no
 * registry prefix). Display-only. */
function shortModuleFor(module) {
  if (
    registryNamePrefix &&
    module &&
    module.length > registryNamePrefix.length + 1 &&
    module.indexOf(registryNamePrefix + ".") === 0
  ) {
    return module.slice(registryNamePrefix.length + 1);
  }
  return module;
}

/** Strip the registry prefix from pretty-printed signature / type text for
 * display: drop `<prefix>.` only where it begins a qualified name — preceded by
 * start-of-string or a non-identifier, non-dot character — so `Nat.Primes` and
 * names that merely contain the prefix as a substring are left intact. The
 * registry data itself is never mutated. Identity when there's no prefix. */
function stripPrefixInText(s) {
  if (!registryNamePrefix || !s) return s;
  const esc = registryNamePrefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp("(^|[^A-Za-z0-9_.\\u00A0-\\uFFFF])" + esc + "\\.", "g");
  return s.replace(re, "$1");
}

function isWired(name) {
  const reg = registryByName ? registryByName.get(name) : null;
  if (reg) return !!reg.authored;
  return inlineMeta.has(name);
}

function nodeHrefFor(name) {
  const reg = registryByName ? registryByName.get(name) : null;
  if (reg && reg.nodeHref) return reg.nodeHref;
  const inl = inlineMeta.get(name);
  if (inl && inl.nodeHref) return inl.nodeHref;
  return null;
}

// True when `href` resolves to the page currently being viewed. Used to suppress
// the "Open node/declaration page" CTA when the rail's selection IS this page
// (e.g. the default selection on a node/decl page targets itself). Normalizes a
// trailing `index.html` and slash so a directory href matches its index.
function isCurrentPage(href) {
  if (!href) return false;
  try {
    const target = new URL(href, document.baseURI);
    const norm = function (p) {
      return p.replace(/index\.html?$/i, "").replace(/\/+$/, "");
    };
    return norm(target.pathname) === norm(window.location.pathname);
  } catch (_err) {
    return false;
  }
}

/* -------------------------------------------------------------------------- */
/* Rendering                                                                  */
/* -------------------------------------------------------------------------- */

function renderEmpty() {
  if (!bodyEl) return;
  bodyEl.replaceChildren(
    el("p", {
      class: "bp-rail-empty",
      text: "Select a declaration — click a node card or a graph node — to see its properties and dependencies here."
    })
  );
}

function sectionTitle(text) {
  return el("h2", { class: "bp-rail-section-title", text: text });
}

// A collapsed-by-default disclosure section for the dependency lists (Uses /
// Used By / See Also, plus their loading/offline fallbacks). Emits a native
// `<details>` (collapsed — no `open` attribute) whose `<summary>` reuses the
// `.bp-rail-section-title` typography; the disclosure triangle + focus style are
// drawn by MetadataRail.lean (`.bp-rail-collapsible`). Keeping the whole set of
// dependency sections as `<details>` (even in the fallback branches) keeps the
// rail structure stable across load states.
function collapsibleSection(title, children) {
  const summary = el("summary", { class: "bp-rail-section-title", text: title });
  const kids = Array.isArray(children) ? children : [children];
  return el("details", { class: "bp-rail-section bp-rail-collapsible" }, [summary].concat(kids));
}

function metaRow(key, value, title) {
  const val = el("span", { class: "bp-rail-meta-val", text: value });
  if (title && title !== value) val.setAttribute("title", title);
  return el("div", { class: "bp-rail-meta-row" }, [
    el("span", { class: "bp-rail-meta-key", text: key }),
    val
  ]);
}

// A metric row whose key carries a dotted-underline "help" affordance and reveals a
// themed gloss tooltip on hover / keyboard focus (see attachTooltip).
function metricRow(key, value, gloss) {
  const keyEl = el("span", { class: "bp-rail-meta-key bp-rail-metric-key", text: key });
  attachTooltip(keyEl, gloss);
  return el("div", { class: "bp-rail-meta-row" }, [
    keyEl,
    el("span", { class: "bp-rail-meta-val", text: value })
  ]);
}

function depItem(name, axis) {
  const wired = isWired(name);
  // The dependency name is itself the link to its canonical page: the node page
  // when wired, the decl page otherwise (the same target the old trailing arrow
  // used). The short display name is the link text; the fully-qualified name stays
  // on the hover title. When no href resolves (should not happen — every dep
  // reference currently resolves — but defensively), fall back to a plain,
  // non-navigating span so the row still reads.
  const reg = registryByName ? registryByName.get(name) : null;
  const href = wired ? nodeHrefFor(name) : (reg && reg.declHref) || null;
  const label = shortNameFor(name);
  const dep = href
    ? el("a", {
        class: "bp-rail-dep",
        attrs: { href: href, "data-wired": wired ? "true" : "false", title: name },
        text: label
      })
    : el("span", {
        class: "bp-rail-dep",
        attrs: { "data-wired": wired ? "true" : "false", title: name },
        text: label
      });
  const children = [dep];
  if (axis) {
    children.unshift(el("span", { class: "bp-rail-dep-axis", text: axis }));
  }
  return el("div", { class: "bp-rail-dep-item" }, children);
}

function depSection(title, items, cap) {
  // items: [{name, axis?}]
  const list = el("div", { class: "bp-rail-deps" });
  const shown = items.slice(0, cap || DEP_CAP);
  shown.forEach(function (it) {
    list.appendChild(depItem(it.name, it.axis));
  });
  const children = [list];
  if (items.length > shown.length) {
    children.push(
      el("p", { class: "bp-rail-more", text: "+ " + (items.length - shown.length) + " more" })
    );
  }
  return collapsibleSection(title, children);
}

/* -------------------------------------------------------------------------- */
/* Known caveat patterns (registry v3)                                        */
/* -------------------------------------------------------------------------- */

// The three guard sentences, verbatim from CaveatsRender.guardCopy. Kept in step
// with the Lean copy by hand: the same fact must not be worded two ways depending
// on which surface a reader is looking at. None of them says "guarded".
function guardSentence(m) {
  const guard = m && m.guard;
  if (guard === "candidate-present") {
    return "A guard-shaped hypothesis occurs; this presence scan did not relate it to the flagged operand.";
  }
  if (guard === "not-detected") {
    const base =
      "No hypothesis of the guarding shape was detected. This is a presence check: the statement may be guarded another way, or may not need a guard.";
    return m.guardHint ? base + " A guard would look like: " + m.guardHint : base;
  }
  return "No guard shape is recorded for this symbol, so nothing was looked for.";
}

// A scan report as a collapsed rail section. Branches explicitly on every state
// the report can be in; the caller has already established that a report exists,
// because "no report" is not one of these states and renders nothing at all.
function caveatsSection(scan) {
  const status = scan.status || "";
  const hits = Array.isArray(scan.matches) ? scan.matches : [];
  const version = scan.tableVersion || "unversioned";
  const digest = scan.tableDigest || "unknown";
  const children = [];
  if (status === "unavailable" || status === "disabled") {
    children.push(
      el("p", {
        class: "bp-rail-note",
        text:
          status === "disabled"
            ? "The caveat scan is switched off for this site, so no symbols were looked for."
            : "No caveat scan is available here" + (scan.reason ? ": " + scan.reason : "") + "."
      })
    );
  } else if (hits.length === 0) {
    children.push(
      el("p", {
        class: "bp-rail-note",
        text:
          "No matches in the configured partial table (version " + version + ", digest " + digest +
          "); this is not evidence that no total-function caveat applies."
      })
    );
  } else {
    const list = el("div", { class: "bp-rail-caveats" });
    hits.forEach(function (m) {
      const chip = el("span", {
        class: "bp-rail-caveat",
        attrs: { "data-guard": m.guard || "", tabindex: "0" },
        text: m.symbol || ""
      });
      attachTooltip(chip, (m.behavior ? m.behavior + " " : "") + guardSentence(m));
      list.appendChild(chip);
    });
    children.push(list);
    if (status === "partial") {
      children.push(
        el("p", {
          class: "bp-rail-note",
          text: "The scan stopped at this site's configured cap, so this is a lower bound."
        })
      );
    }
    children.push(
      el("p", {
        class: "bp-rail-note",
        text:
          "Caveats to check, not findings of error. The table is partial (version " + version +
          ", digest " + digest + "): a symbol it does not list is a symbol nobody looked for."
      })
    );
  }
  if (scan.coverage) {
    children.push(el("p", { class: "bp-rail-note", text: "Scanned: " + scan.coverage + "." }));
  }
  return collapsibleSection("Known caveat patterns", children);
}

function pendingNote() {
  if (registryState === "loading" || registryState === "idle") {
    return el("p", { class: "bp-rail-note", text: "Loading dependency data…" });
  }
  return el("p", { class: "bp-rail-note", text: "Dependency data unavailable offline (serve over http)." });
}

function renderRail(name, hintMeta) {
  if (!bodyEl) return;
  const vm = viewModel(name, hintMeta);
  const frag = document.createDocumentFragment();

  // --- Identity -----------------------------------------------------------
  const badges = el("div", { class: "bp-rail-badges" });
  if (vm.kind) badges.appendChild(el("span", { class: "bp-rail-kind", text: vm.kind }));
  if (vm.status) {
    badges.appendChild(
      el("span", {
        class: "bp-rail-status",
        attrs: { "data-status": vm.status },
        text: statusLabelFor(vm.kind, vm.status)
      })
    );
  }
  // Identity shows the short name; the fully-qualified name stays on `title`
  // (and on the decl page itself).
  const displayName = (vm.shortName || shortNameFor(name)) || vm.name;
  const identity = el("div", { class: "bp-rail-identity" }, [
    badges,
    el("div", { class: "bp-rail-name", attrs: { title: vm.name }, text: displayName })
  ]);
  if (vm.title) {
    identity.appendChild(el("div", { class: "bp-rail-node-title", text: vm.title }));
  }
  frag.appendChild(identity);

  if (!vm.known) {
    // Nothing inline and registry not (yet) loaded for this name.
    const sect = el("div", { class: "bp-rail-section" }, [pendingNote()]);
    frag.appendChild(sect);
    bodyEl.replaceChildren(frag);
    return;
  }

  // --- Docstring (registry v2; build-generated HTML, raw HTML disabled) ----
  if (vm.docstringHtml) {
    const doc = el("div", { class: "bp-rail-docstring" });
    doc.innerHTML = vm.docstringHtml;
    frag.appendChild(el("div", { class: "bp-rail-section" }, [sectionTitle("Docstring"), doc]));
  }

  // --- Location -----------------------------------------------------------
  const loc = el("div", { class: "bp-rail-section" }, [sectionTitle("Source")]);
  if (vm.module) loc.appendChild(metaRow("Module", shortModuleFor(vm.module), vm.module));
  if (vm.startLine != null) {
    const where = vm.sourcePath ? vm.sourcePath : "line";
    const span = vm.endLine != null && vm.endLine !== vm.startLine
      ? vm.startLine + "–" + vm.endLine
      : String(vm.startLine);
    loc.appendChild(metaRow(vm.sourcePath ? "File" : "Lines", vm.sourcePath ? where + ":" + span : span));
  }
  if (vm.sourceHref) {
    loc.appendChild(
      el("a", {
        class: "bp-rail-open-page bp-rail-source-link",
        attrs: { href: vm.sourceHref, target: "_blank", rel: "noopener" },
        text: "View source"
      })
    );
  }
  frag.appendChild(loc);

  // --- Signature ----------------------------------------------------------
  if (vm.signatureText) {
    frag.appendChild(
      el("div", { class: "bp-rail-section" }, [
        sectionTitle("Signature"),
        el("pre", { class: "bp-rail-sig", text: stripPrefixInText(vm.signatureText) })
      ])
    );
  }

  // --- Parameters ---------------------------------------------------------
  if (Array.isArray(vm.params)) {
    if (vm.params.length > 0) {
      const table = el("div", { class: "bp-rail-params" });
      vm.params.forEach(function (p) {
        table.appendChild(
          el("div", {
            class: "bp-rail-param",
            attrs: { "data-binder": p.binderInfo || "default" }
          }, [
            el("span", { class: "bp-rail-param-name", text: p.name }),
            el("span", { class: "bp-rail-param-sep", text: ":" }),
            el("span", { class: "bp-rail-param-type", text: stripPrefixInText(p.type) })
          ])
        );
      });
      frag.appendChild(
        el("div", { class: "bp-rail-section" }, [sectionTitle("Parameters"), table])
      );
    }
  } else {
    frag.appendChild(el("div", { class: "bp-rail-section" }, [sectionTitle("Parameters"), pendingNote()]));
  }

  // --- Known caveat patterns (registry v3) --------------------------------
  // Rendered only when the entry carries a scan. An entry with no `scan` was not
  // scanned, which is not the same as a scan that found nothing, and a section
  // saying "nothing found" on a page that never looked would be the one thing
  // this surface must not do.
  if (vm.scan && vm.scan.status) {
    frag.appendChild(caveatsSection(vm.scan));
  }

  // --- Metrics (fan-in/out client-side; depth/height from the registry) ----
  // A collapsed disclosure (like Uses / Used By); each metric label carries a
  // hover/focus tooltip glossing its exact meaning (code-verified semantics).
  const hasDeps = Array.isArray(vm.statementDeps) || Array.isArray(vm.proofDeps);
  if (hasDeps || Array.isArray(vm.usedBy) || vm.depth != null || vm.height != null) {
    const metricRows = [];
    if (hasDeps) {
      const outSet = new Set();
      (vm.statementDeps || []).forEach(function (n) { outSet.add(n); });
      (vm.proofDeps || []).forEach(function (n) { outSet.add(n); });
      metricRows.push(metricRow("Fan-out", String(outSet.size),
        "Distinct project declarations this one directly references, in its statement or proof."));
    }
    if (Array.isArray(vm.usedBy)) {
      metricRows.push(metricRow("Fan-in", String(vm.usedBy.length),
        "Distinct project declarations that directly reference this one."));
    }
    if (vm.depth != null) metricRows.push(metricRow("Depth", String(vm.depth),
      "Length in edges of the longest dependency chain below this declaration; 0 = no project dependencies."));
    if (vm.height != null) metricRows.push(metricRow("Height", String(vm.height),
      "Length in edges of the longest chain of dependents above this declaration; 0 = nothing builds on it."));
    frag.appendChild(collapsibleSection("Metrics", metricRows));
  }

  // --- Uses (statement + proof axes) --------------------------------------
  if (Array.isArray(vm.statementDeps) || Array.isArray(vm.proofDeps)) {
    const uses = [];
    (vm.statementDeps || []).forEach(function (n) { uses.push({ name: n, axis: "stmt" }); });
    (vm.proofDeps || []).forEach(function (n) {
      if (!(vm.statementDeps || []).includes(n)) uses.push({ name: n, axis: "proof" });
    });
    if (uses.length > 0) frag.appendChild(depSection("Uses", uses));
  } else {
    frag.appendChild(collapsibleSection("Uses", pendingNote()));
  }

  // --- Used By ------------------------------------------------------------
  if (Array.isArray(vm.usedBy)) {
    if (vm.usedBy.length > 0) {
      frag.appendChild(depSection("Used By", vm.usedBy.map(function (n) { return { name: n }; })));
    }
  } else {
    frag.appendChild(collapsibleSection("Used By", pendingNote()));
  }

  // --- See Also (same-module siblings) ------------------------------------
  if (registryByModule && vm.module) {
    const siblings = (registryByModule.get(vm.module) || []).filter(function (n) { return n !== vm.name; });
    if (siblings.length > 0) {
      frag.appendChild(depSection("See Also", siblings.map(function (n) { return { name: n }; }), SEE_ALSO_CAP));
    }
  }

  // --- Open node / declaration page ----------------------------------------
  // Every registry decl has exactly one canonical page: the node page when
  // wired, its own decl page otherwise. Suppress the CTA when that page is the
  // one already being viewed (the target would be a no-op self-link).
  const pageHref = vm.nodeHref || vm.declHref;
  if (pageHref && !isCurrentPage(pageHref)) {
    const link = el("a", {
      class: "bp-rail-open-page",
      attrs: { href: pageHref },
      text: vm.nodeHref ? "Open node page" : "Open declaration page"
    });
    frag.appendChild(el("div", { class: "bp-rail-section" }, [link]));
  }

  bodyEl.replaceChildren(frag);
}

/* -------------------------------------------------------------------------- */
/* Selection glue                                                             */
/* -------------------------------------------------------------------------- */

function select(selection) {
  if (bus) bus.set(selection);
}

function onSelection(selection) {
  if (!selection || !selection.declName) {
    renderEmpty();
    return;
  }
  const name = selection.declName;
  const hint = selection.meta || null;
  // A new selection starts from the top of the panel.
  if (bodyEl) bodyEl.scrollTop = 0;
  // First paint from whatever is available now (inline / already-loaded registry).
  renderRail(name, hint);
  // Then ensure the full registry and re-render if this is still the selection.
  if (registryState !== "loaded") {
    ensureRegistry().then(function () {
      const cur = bus ? bus.get() : null;
      if (cur && cur.declName === name) renderRail(name, hint);
    });
  }
}

function wireCards() {
  // Delegated: any click / keyboard focus inside a node card OR a catalog/index row
  // selects its decl. Passive (never preventDefault) so links / toggles / row links
  // still work.
  function fromEvent(ev) {
    const target = ev.target;
    if (!target || typeof target.closest !== "function") return;
    const card = target.closest(".bp_card2[data-bp-decl], .bp_decl_row[data-bp-decl]");
    if (!card) return;
    const name = (card.getAttribute("data-bp-decl") || "").trim();
    if (!name) return;
    let meta = null;
    const metaNode = card.querySelector(".bp-decl-meta[data-bp-decl]");
    if (metaNode) {
      try { meta = JSON.parse(metaNode.textContent || "null"); } catch (_e) { meta = null; }
    }
    select({ declName: name, source: "card", meta: meta });
  }
  document.addEventListener("click", fromEvent);
  document.addEventListener("focusin", fromEvent);
}

function selectPageDefault() {
  // Node page -> the page's single card; chapter -> first card;
  // graph / dashboard / index (no live cards) -> none (empty state).
  const card = document.querySelector('.bp_card2[data-bp-decl]:not([data-bp-decl=""])');
  if (!card) return;
  const name = (card.getAttribute("data-bp-decl") || "").trim();
  if (!name) return;
  let meta = null;
  const metaNode = card.querySelector(".bp-decl-meta[data-bp-decl]");
  if (metaNode) {
    try { meta = JSON.parse(metaNode.textContent || "null"); } catch (_e) { meta = null; }
  }
  select({ declName: name, source: "load", meta: meta });
}

/* -------------------------------------------------------------------------- */
/* Boot                                                                       */
/* -------------------------------------------------------------------------- */

function install() {
  if (typeof document === "undefined") return;
  bus = installSelectionBus();
  buildRail();
  collectInlineMeta();
  wireCards();
  bus.subscribe(onSelection);
  // Respect any selection pushed before we subscribed; otherwise default the page.
  if (bus.get()) {
    onSelection(bus.get());
  } else {
    selectPageDefault();
  }
}

export function startMetadataRail() {
  if (typeof document === "undefined") return;
  // Ensure the bus exists even before the DOM is ready (graph.mjs may push early).
  bus = installSelectionBus();
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", install, { once: true });
  } else {
    install();
  }
}

export default { startMetadataRail };
