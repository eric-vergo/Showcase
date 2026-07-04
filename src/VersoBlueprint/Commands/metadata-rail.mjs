// Site-wide "Properties & Dependencies" metadata rail.
//
// A fixed right `<aside>` injected on every page (no verso-core template edit —
// same asset-injection pattern as the banner nav / color-scheme switcher). It
// shows the properties + dependencies of whatever declaration is currently
// selected on the shared selection bus (`window.VersoBlueprint.selection`, see
// selection-bus.mjs), fed by node-card clicks, graph node clicks (graph.mjs), and
// the page's default selection.
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

const RAIL_ID = "bp-metadata-rail";
const TAB_ID = "bp-metadata-rail-tab";
const BODY_ID = "bp-metadata-rail-body";
const BACKDROP_CLASS = "bp-rail-backdrop";
const OPEN_KEY = "bp-rail-open";
const DOCK_BREAKPOINT = 1400; // px — matches the 87.5rem CSS breakpoint.
const SEE_ALSO_CAP = 8;
const DEP_CAP = 60; // guard against pathologically long used-by lists.

let bus = null;
let registryState = "idle"; // idle | loading | loaded | error
let registryPromise = null;
let registryByName = null; // Map<name, entry>
let registryByModule = null; // Map<module, name[]>
const inlineMeta = new Map(); // Map<name, slim record>

let railEl = null;
let tabEl = null;
let bodyEl = null;
let backdropEl = null;

const STATUS_LABELS = {
  proved: "Proved",
  missing: "Missing",
  axiomLike: "Axiom",
  containsSorry: "Sorry"
};

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
/* Open / collapse state (persisted)                                          */
/* -------------------------------------------------------------------------- */

function storedOpen() {
  try {
    const v = window.localStorage.getItem(OPEN_KEY);
    if (v === "true") return true;
    if (v === "false") return false;
  } catch (_e) {
    /* ignore storage errors */
  }
  return null;
}

function persistOpen(open) {
  try {
    window.localStorage.setItem(OPEN_KEY, open ? "true" : "false");
  } catch (_e) {
    /* ignore storage errors */
  }
}

function applyOpen(open, persist) {
  const root = document.documentElement;
  root.setAttribute("data-bp-rail-open", open ? "true" : "false");
  if (railEl) railEl.setAttribute("aria-hidden", open ? "false" : "true");
  if (tabEl) tabEl.setAttribute("aria-expanded", open ? "true" : "false");
  if (persist) persistOpen(open);
}

function initialOpen() {
  const s = storedOpen();
  if (s !== null) return s;
  // Default: docked-open on wide desktop, closed (drawer) below the breakpoint.
  try {
    return window.innerWidth >= DOCK_BREAKPOINT;
  } catch (_e) {
    return false;
  }
}

/* -------------------------------------------------------------------------- */
/* Rail shell                                                                 */
/* -------------------------------------------------------------------------- */

const ICON_CLOSE =
  '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" ' +
  'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ' +
  'focusable="false"><path d="M18 6L6 18"/><path d="M6 6l12 12"/></svg>';

function buildRail() {
  if (document.getElementById(RAIL_ID)) return;

  // Edge tab (opens the rail when collapsed).
  tabEl = el("button", {
    attrs: {
      id: TAB_ID,
      type: "button",
      "aria-controls": RAIL_ID,
      "aria-expanded": "false",
      title: "Show properties & dependencies"
    },
    text: "Properties"
  });
  tabEl.addEventListener("click", function () {
    applyOpen(true, true);
  });

  // Backdrop (drawer mode overlay). Visibility is CSS-driven (shown only when the
  // rail is open below the docked breakpoint); no `hidden` attribute so the media
  // query is the single source of truth.
  backdropEl = el("div", { class: BACKDROP_CLASS });
  backdropEl.addEventListener("click", function () {
    applyOpen(false, true);
  });

  const collapse = el("button", {
    class: "bp-rail-collapse",
    attrs: {
      type: "button",
      "aria-controls": BODY_ID,
      "aria-expanded": "true",
      title: "Collapse",
      "aria-label": "Collapse properties panel"
    }
  });
  collapse.innerHTML = ICON_CLOSE;
  collapse.addEventListener("click", function () {
    applyOpen(false, true);
  });

  const header = el("div", { class: "bp-rail-header" }, [
    el("span", { class: "bp-rail-title", text: "Properties & Dependencies" }),
    collapse
  ]);

  bodyEl = el("div", { class: "bp-rail-body", attrs: { id: BODY_ID } });

  railEl = el("aside", {
    attrs: {
      id: RAIL_ID,
      "aria-label": "Properties and dependencies",
      "aria-hidden": "true"
    }
  }, [header, bodyEl]);

  // Backdrop must be a sibling before the rail so the rail paints on top.
  document.body.appendChild(backdropEl);
  document.body.appendChild(tabEl);
  document.body.appendChild(railEl);

  document.addEventListener("keydown", function (ev) {
    if (ev.key !== "Escape") return;
    if (document.documentElement.getAttribute("data-bp-rail-open") !== "true") return;
    // In drawer mode, Escape closes; docked mode leaves it (it isn't modal).
    if (window.innerWidth < DOCK_BREAKPOINT) {
      applyOpen(false, true);
    }
  });

  applyOpen(initialOpen(), false);
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
    nodeHref: (reg && reg.nodeHref) || (inl && inl.nodeHref) || undefined
  };
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

function metaRow(key, value) {
  return el("div", { class: "bp-rail-meta-row" }, [
    el("span", { class: "bp-rail-meta-key", text: key }),
    el("span", { class: "bp-rail-meta-val", text: value })
  ]);
}

function depItem(name, axis) {
  const wired = isWired(name);
  const btn = el("button", {
    class: "bp-rail-dep",
    attrs: { type: "button", "data-wired": wired ? "true" : "false", title: name },
    text: name
  });
  btn.addEventListener("click", function () {
    select({ declName: name, source: "rail" });
  });
  const children = [btn];
  if (axis) {
    children.unshift(el("span", { class: "bp-rail-dep-axis", text: axis }));
  }
  if (wired) {
    const href = nodeHrefFor(name);
    if (href) {
      const link = el("a", {
        class: "bp-rail-dep-link",
        attrs: { href: href, title: "Open node page", "aria-label": "Open node page for " + name },
        text: "↗"
      });
      children.push(link);
    }
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
  const section = el("div", { class: "bp-rail-section" }, [sectionTitle(title), list]);
  if (items.length > shown.length) {
    section.appendChild(
      el("p", { class: "bp-rail-more", text: "+ " + (items.length - shown.length) + " more" })
    );
  }
  return section;
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
        text: STATUS_LABELS[vm.status] || vm.status
      })
    );
  }
  const identity = el("div", { class: "bp-rail-identity" }, [
    badges,
    el("div", { class: "bp-rail-name", text: vm.name })
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

  // --- Location -----------------------------------------------------------
  const loc = el("div", { class: "bp-rail-section" }, [sectionTitle("Source")]);
  if (vm.module) loc.appendChild(metaRow("Module", vm.module));
  if (vm.startLine != null) {
    const where = vm.sourcePath ? vm.sourcePath : "line";
    const span = vm.endLine != null && vm.endLine !== vm.startLine
      ? vm.startLine + "–" + vm.endLine
      : String(vm.startLine);
    loc.appendChild(metaRow(vm.sourcePath ? "File" : "Lines", vm.sourcePath ? where + ":" + span : span));
  }
  frag.appendChild(loc);

  // --- Signature ----------------------------------------------------------
  if (vm.signatureText) {
    frag.appendChild(
      el("div", { class: "bp-rail-section" }, [
        sectionTitle("Signature"),
        el("pre", { class: "bp-rail-sig", text: vm.signatureText })
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
            el("span", { class: "bp-rail-param-type", text: p.type })
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

  // --- Uses (statement + proof axes) --------------------------------------
  if (Array.isArray(vm.statementDeps) || Array.isArray(vm.proofDeps)) {
    const uses = [];
    (vm.statementDeps || []).forEach(function (n) { uses.push({ name: n, axis: "stmt" }); });
    (vm.proofDeps || []).forEach(function (n) {
      if (!(vm.statementDeps || []).includes(n)) uses.push({ name: n, axis: "proof" });
    });
    if (uses.length > 0) frag.appendChild(depSection("Uses", uses));
  } else {
    frag.appendChild(el("div", { class: "bp-rail-section" }, [sectionTitle("Uses"), pendingNote()]));
  }

  // --- Used By ------------------------------------------------------------
  if (Array.isArray(vm.usedBy)) {
    if (vm.usedBy.length > 0) {
      frag.appendChild(depSection("Used By", vm.usedBy.map(function (n) { return { name: n }; })));
    }
  } else {
    frag.appendChild(el("div", { class: "bp-rail-section" }, [sectionTitle("Used By"), pendingNote()]));
  }

  // --- See Also (same-module siblings) ------------------------------------
  if (registryByModule && vm.module) {
    const siblings = (registryByModule.get(vm.module) || []).filter(function (n) { return n !== vm.name; });
    if (siblings.length > 0) {
      frag.appendChild(depSection("See Also", siblings.map(function (n) { return { name: n }; }), SEE_ALSO_CAP));
    }
  }

  // --- Open node page -----------------------------------------------------
  if (vm.nodeHref) {
    const link = el("a", {
      class: "bp-rail-open-page",
      attrs: { href: vm.nodeHref },
      text: "Open node page →"
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
