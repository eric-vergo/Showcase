import * as graphRuntimeCoreModule from "./graph-runtime-core.mjs";
import {
  getGraphData as coreGetGraphData,
  getGraphVariants as coreGetGraphVariants
} from "../blueprint-graph-core.mjs";
import { startProofToggle } from "./proof-toggle.mjs";
import { installSelectionBus } from "./selection-bus.mjs";

const {
  debounce,
  normalizeGraphOptions,
  graphPackAttr,
  graphOptionsKey,
  graphLayoutMode,
  readPreviewBehaviorDefaults,
  layoutGraphCanvas,
  load,
  graphNodeLabel,
  graphNodeId,
  ensureGraphBlockState,
  rememberGraphLayoutMeasurements,
  resizeRenderedGraphToCanvas,
  resetGraphvizForVariant,
  makeGroupPanelPositioner
} = graphRuntimeCoreModule;

function collectPreviewTemplates(previewUtils, rootNode) {
  return previewUtils.collectPreviewTemplates(
    rootNode || document,
    "template.bp_graph_preview_tpl[data-bp-preview-label]"
  );
}

// Per-label card metadata (node-page href + display title) read from the inline
// card templates, keyed the same way as `collectPreviewTemplates` (by
// `data-bp-preview-label`). Powers the modal's "Open node page" link and title.
function collectCardMeta(rootNode) {
  const meta = new Map();
  const scope = rootNode || document;
  scope
    .querySelectorAll("template.bp_graph_preview_tpl[data-bp-preview-label]")
    .forEach(function (tpl) {
      const label = (tpl.getAttribute("data-bp-preview-label") || "").trim();
      if (!label) return;
      meta.set(label, {
        href: (tpl.getAttribute("data-bp-node-href") || "").trim(),
        title: (tpl.getAttribute("data-bp-node-title") || label).trim()
      });
    });
  return meta;
}

// Map a graph node to its declaration, for the metadata rail selection bus.
// Blueprint nodes carry a blueprint label (`«thm:…»`); the inline card templates
// map that label to the card's `data-bp-decl` (and its slim inline record for
// offline first paint). Supporting nodes have no template — their node label *is*
// the declaration name (see `mkSupportingNodeData`), used verbatim.
function collectGraphDeclMeta(rootNode) {
  const labelToDecl = new Map(); // blueprint node label -> declaration name
  const metaByDecl = new Map(); // declaration name -> slim inline record
  const scope = rootNode || document;
  scope
    .querySelectorAll("template.bp_graph_preview_tpl[data-bp-preview-label]")
    .forEach(function (tpl) {
      const label = (tpl.getAttribute("data-bp-preview-label") || "").trim();
      const content = tpl.content;
      if (!content) return;
      const card = content.querySelector(".bp_card2[data-bp-decl]");
      if (!card) return;
      const decl = (card.getAttribute("data-bp-decl") || "").trim();
      if (!decl) return;
      if (label) labelToDecl.set(label, decl);
      const metaNode = content.querySelector(".bp-decl-meta[data-bp-decl]");
      if (metaNode) {
        try {
          const rec = JSON.parse(metaNode.textContent || "null");
          if (rec && typeof rec === "object") metaByDecl.set(decl, rec);
        } catch (_e) {
          /* ignore malformed payloads */
        }
      }
    });
  return { labelToDecl: labelToDecl, metaByDecl: metaByDecl };
}

// Make every graph node (blueprint AND supporting) select its declaration on the
// shared selection bus, so a click populates the metadata rail. Blueprint nodes
// additionally open the Wave-2 modal (bound per node in `attachPreviewHandlers`);
// supporting nodes now get rail metadata instead of the empty peek. Delegation is
// capture-phase on the stable block so it fires before the modal handler's
// `stopPropagation`, and reads a `data-bp-decl` stamped here before the preview
// pass strips node `<title>`s.
function attachSelectionHandlers(graphBlock, graphContainer, labelToDecl, metaByDecl) {
  const svg = graphContainer.select("svg").node();
  if (!svg || !(svg instanceof SVGElement)) return;
  svg.querySelectorAll("g.node").forEach(function (node) {
    const label = graphNodeLabel(node);
    if (!label) return;
    const decl = labelToDecl.get(label) || label;
    node.setAttribute("data-bp-decl", decl);
    if (!node.style.cursor) node.style.cursor = "pointer";
    if (!node.hasAttribute("tabindex")) node.setAttribute("tabindex", "0");
    if (!node.hasAttribute("role")) node.setAttribute("role", "button");
  });
  // Latest inline records for offline first paint (templates are static, but keep
  // the reference fresh across re-renders).
  graphBlock.__bpMetaByDecl = metaByDecl;
  if (graphBlock.__bpSelectionBound === true) return;
  graphBlock.__bpSelectionBound = true;
  const selectFromNode = function (node) {
    if (!(node instanceof Element)) return;
    const decl = (node.getAttribute("data-bp-decl") || "").trim();
    if (!decl) return;
    const bus = window.VersoBlueprint && window.VersoBlueprint.selection;
    if (!bus || typeof bus.set !== "function") return;
    const records = graphBlock.__bpMetaByDecl;
    bus.set({
      declName: decl,
      source: "graph",
      meta: records && records.get ? records.get(decl) || null : null
    });
  };
  graphBlock.addEventListener("click", function (ev) {
    const node = ev.target && ev.target.closest ? ev.target.closest("g.node") : null;
    if (node) selectFromNode(node);
  }, true);
  graphBlock.addEventListener("keydown", function (ev) {
    if (ev.key !== "Enter" && ev.key !== " ") return;
    const node = ev.target && ev.target.closest ? ev.target.closest("g.node") : null;
    if (node) selectFromNode(node);
  }, true);
}

// Centered modal dialog showing a graph node's full two-column card on click.
// Content comes from the inline `<template class="bp_graph_preview_tpl">` cards
// embedded at build time (offline-correct: no fetch). KaTeX and the per-card
// proof toggle are (re)hydrated on the injected fragment. One overlay per page
// (graph pages carry a single graph block; reused if already present).
function ensureGraphModal(previewUtils) {
  const existing = document.querySelector(".bp_graph_modal_overlay");
  if (existing && existing.__bpGraphModal) return existing.__bpGraphModal;

  const overlay = document.createElement("div");
  overlay.className = "bp_graph_modal_overlay";
  overlay.hidden = true;

  const dialog = document.createElement("div");
  dialog.className = "bp_graph_modal_dialog";
  dialog.setAttribute("role", "dialog");
  dialog.setAttribute("aria-modal", "true");
  dialog.setAttribute("aria-label", "Node preview");
  dialog.setAttribute("tabindex", "-1");
  dialog.innerHTML =
    '<div class="bp_graph_modal_header">' +
      '<div class="bp_graph_modal_title"></div>' +
      '<button type="button" class="bp_graph_modal_close" aria-label="Close preview">Close</button>' +
    "</div>" +
    '<div class="bp_graph_modal_body"></div>' +
    '<div class="bp_graph_modal_footer">' +
      '<a class="bp_graph_modal_open" href="#">Open node page</a>' +
    "</div>";
  overlay.appendChild(dialog);
  document.body.appendChild(overlay);

  const titleEl = dialog.querySelector(".bp_graph_modal_title");
  const bodyEl = dialog.querySelector(".bp_graph_modal_body");
  const closeBtn = dialog.querySelector(".bp_graph_modal_close");
  const openLink = dialog.querySelector(".bp_graph_modal_open");
  let lastFocused = null;

  const close = function () {
    if (overlay.hidden) return;
    overlay.hidden = true;
    bodyEl.replaceChildren();
    document.removeEventListener("keydown", onKeydown, true);
    if (lastFocused && typeof lastFocused.focus === "function") {
      try { lastFocused.focus(); } catch (_e) { /* ignore */ }
    }
    lastFocused = null;
  };

  const onKeydown = function (ev) {
    if (overlay.hidden) return;
    if (ev.key === "Escape") { ev.preventDefault(); close(); return; }
    if (ev.key !== "Tab") return;
    // Basic focus trap: keep Tab within the dialog.
    const focusables = dialog.querySelectorAll(
      'a[href],button:not([disabled]),input,select,textarea,[tabindex]:not([tabindex="-1"])'
    );
    if (focusables.length === 0) { ev.preventDefault(); dialog.focus(); return; }
    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    const active = document.activeElement;
    if (ev.shiftKey && (active === first || active === dialog)) {
      ev.preventDefault();
      last.focus();
    } else if (!ev.shiftKey && active === last) {
      ev.preventDefault();
      first.focus();
    }
  };

  const open = function (payload) {
    lastFocused = document.activeElement;
    titleEl.textContent = (payload && payload.title) || "";
    bodyEl.innerHTML = (payload && payload.html) || "";
    // Typeset KaTeX + run registered hydrators on the injected card fragment.
    try {
      if (previewUtils && typeof previewUtils.hydrate === "function") {
        previewUtils.hydrate(bodyEl);
      }
    } catch (_e) { /* ignore */ }
    // Rebind the per-card proof toggle (proof-toggle.mjs binds on load only).
    try { startProofToggle(bodyEl); } catch (_e) { /* ignore */ }
    if (payload && payload.href) {
      openLink.setAttribute("href", payload.href);
      openLink.hidden = false;
    } else {
      openLink.removeAttribute("href");
      openLink.hidden = true;
    }
    // Always start at the top of the card (the body is a reused, scrollable
    // element, so a prior open's scroll position would otherwise persist).
    bodyEl.scrollTop = 0;
    overlay.hidden = false;
    document.addEventListener("keydown", onKeydown, true);
    (closeBtn || dialog).focus();
  };

  overlay.addEventListener("mousedown", function (ev) {
    if (ev.target === overlay) close();
  });
  closeBtn.addEventListener("click", function (ev) {
    ev.preventDefault();
    close();
  });

  const modal = {
    overlay: overlay,
    open: open,
    close: close,
    isOpen: function () { return !overlay.hidden; }
  };
  overlay.__bpGraphModal = modal;
  return modal;
}

function readPublicGraphData(root) {
  return coreGetGraphData(root);
}

function readPublicGraphVariants(root) {
  const variants = coreGetGraphVariants(root);
  if (Array.isArray(variants) && variants.length > 0) {
    return variants;
  }
  return [];
}

// STY-GRAPH-11: condense a per-subgraph variant label (often a full sentence)
// into a scannable fragment for the View <optgroup>. Mirrors the Lean-side
// `shortenVariantLabel`; only used by the client-side fallback that rebuilds the
// selector when SSR markup is absent. Cosmetic — option values are unchanged.
function shortenVariantLabel(label, maxLen) {
  const limit = typeof maxLen === "number" ? maxLen : 42;
  const firstSeg = function (sep, s) {
    const idx = s.indexOf(sep);
    return (idx >= 0 ? s.slice(0, idx) : s).trim();
  };
  let clause = String(label == null ? "" : label).trim();
  clause = firstSeg(".", clause);
  clause = firstSeg(";", clause);
  clause = firstSeg(":", clause);
  clause = firstSeg(" — ", clause);
  if (!clause) clause = String(label == null ? "" : label).trim();
  if (clause.length <= limit) return clause;
  const words = clause.slice(0, limit).split(" ");
  if (words.length > 1) words.pop();
  return words.join(" ").trim() + "…";
}

function dotWithGraphAttribute(dot, name, value) {
  const source = String(dot || "");
  if (!source) return "";
  const attrPattern = new RegExp("(^\\s*" + name + "\\s*=\\s*)([^;]+)(\\s*;)", "mi");
  if (attrPattern.test(source)) {
    return source.replace(attrPattern, "$1" + value + "$3");
  }
  const openBrace = source.indexOf("{");
  if (openBrace < 0) return source;
  return source.slice(0, openBrace + 1) + "\n    " + name + "=" + value + ";" + source.slice(openBrace + 1);
}

function dotWithGraphOptions(dot, options) {
  const source = String(dot || "").trim();
  if (!source) return "";
  const normalized = normalizeGraphOptions(options);
  let updated = dotWithGraphAttribute(source, "rankdir", normalized.direction);
  updated = dotWithGraphAttribute(updated, "pack", graphPackAttr(normalized.pack));
  return updated;
}

function dotForVariantOptions(variant, options) {
  if (!variant || typeof variant !== "object") return "";
  const normalized = normalizeGraphOptions(options);
  // "Show all edges" selects the unreduced DOT when this variant has one; otherwise
  // (nothing was reduced) `dotFull` is absent and the reduced `dot` is already full.
  const source = normalized.allEdges && variant.dotFull ? variant.dotFull : variant.dot;
  return dotWithGraphOptions(source, options);
}

function attachPreviewHandlers(previewUtils, graphBlock, graphContainer, previewMap, previewController, previewKeyByNodeId, graphModal, cardMeta) {
  if (!previewController) return;
  const graphState = ensureGraphBlockState(graphBlock);
  const previewKeys =
    previewKeyByNodeId instanceof Map ? previewKeyByNodeId : new Map();
  const meta = cardMeta instanceof Map ? cardMeta : new Map();
  const svg = graphContainer.select("svg").node();
  if (!svg || !(svg instanceof SVGElement)) {
    previewController.hide();
    return;
  }
  if (!previewController.title || !previewController.body || (previewMap.size === 0 && previewKeys.size === 0)) {
    previewController.hide();
    return;
  }
  // Click / keyboard on a node opens the centered modal with the node's full
  // card (from the inline templates in `previewMap`). Returns true when it
  // opened, so the caller can suppress the docked-panel click activation.
  const openModalForNode = function (node) {
    if (!graphModal || !(node instanceof Element)) return false;
    const label = (node.getAttribute("data-bp-node-label") || graphNodeLabel(node) || "").trim();
    if (!label) return false;
    const html = previewMap.get(label) || "";
    if (!html) return false;
    const nodeMeta = meta.get(label) || {};
    graphModal.open({ html: html, href: nodeMeta.href || "", title: nodeMeta.title || label });
    return true;
  };
  const show = async function (label, anchorNode) {
    const requestToken = ++graphState.previewRequestToken;
    const nodeId = anchorNode instanceof Element ? graphNodeId(anchorNode) : "";
    const previewKey = nodeId ? (previewKeys.get(nodeId) || "") : "";
    let html = previewMap.get(label) || "";
    if (!html && previewKey) {
      const resolved = await previewUtils.resolvePreviewHtml(previewKey);
      html = resolved.html || "";
    }
    if (requestToken !== graphState.previewRequestToken) return;
    if (!html) return;
    graphState.previewActiveNode = anchorNode instanceof Element ? anchorNode : null;
    previewController.show(label, html, graphState.previewActiveNode);
  };
  const canPreviewNode = function (node) {
    if (!(node instanceof Element)) return false;
    const label = graphNodeLabel(node);
    const nodeId = graphNodeId(node);
    const previewKey = nodeId ? (previewKeys.get(nodeId) || "") : "";
    return !!label && (previewMap.has(label) || !!previewKey);
  };
  svg.querySelectorAll("g.node").forEach(function (node) {
    if (!canPreviewNode(node)) return;
    node.style.cursor = "pointer";
    node.setAttribute("tabindex", "0");
    // Stash the stable node label (the SVG <title> == the DOT node name == the
    // template's `data-bp-preview-label`) BEFORE removing the title below, so
    // later lookups do not fall back to the visible <text> (which is the display
    // label and would not match).
    const stableLabel = graphNodeLabel(node);
    if (stableLabel) node.setAttribute("data-bp-node-label", stableLabel);
    const titleNode = node.querySelector("title");
    if (titleNode) titleNode.remove();
    [node].concat(Array.from(node.querySelectorAll("*"))).forEach(function (el) {
      if (!(el instanceof Element)) return;
      if (el.hasAttribute("title")) el.removeAttribute("title");
      if (el.hasAttribute("xlink:title")) el.removeAttribute("xlink:title");
      if (el.removeAttributeNS) {
        el.removeAttributeNS("http://www.w3.org/1999/xlink", "title");
      }
    });
    // Click / Enter / Space -> centered modal with the full card. Bound per node
    // (nodes are recreated on each render); guarded against double-binding.
    if (graphModal && node.__bpModalBound !== true) {
      node.__bpModalBound = true;
      node.addEventListener("click", function (ev) {
        if (openModalForNode(node)) {
          ev.preventDefault();
          ev.stopPropagation();
        }
      });
      node.addEventListener("keydown", function (ev) {
        if (ev.key !== "Enter" && ev.key !== " ") return;
        if (openModalForNode(node)) {
          ev.preventDefault();
          ev.stopPropagation();
        }
      });
    }
  });
  const showFromNode = function (node) {
    if (!(node instanceof Element) || !canPreviewNode(node)) return false;
    if (graphState.previewActiveNode === node && !previewController.panel.hidden) {
      previewController.position(node);
      return true;
    }
    const label = graphNodeLabel(node);
    if (label) show(label, node);
    return !!label;
  };
  previewController.bindTriggers({
    eventRoot: svg,
    eventRootBoundAttr: "data-bp-preview-bound",
    triggerSelector: "g.node",
    filterTrigger: canPreviewNode,
    show: showFromNode,
    hide: function () { previewController.hide(); },
    getActiveTrigger: function () { return graphState.previewActiveNode; },
    // When a modal exists, click/keyboard open the centered full-card modal
    // (bound per node above); the docked panel is then hover-only. Without a
    // modal (e.g. a consumer graph with no inline card templates), keep the
    // legacy click-to-pin docked-panel behavior.
    activateOnClick: !graphModal,
    activateOnKeydown: !graphModal,
    enterRequiresHover: true,
    bindEscape: false,
    bindWindow: false
  });
}

function attachVariantSelectors(graphContainer, variantsByKey, activeVariant, onSelect, onHover, onHoverLeave) {
  if (!activeVariant) return;
  const mapNodeTargets = function (entries) {
    const out = new Map();
    if (!Array.isArray(entries)) return out;
    entries.forEach(function (entry) {
      if (!Array.isArray(entry) || entry.length !== 2) return;
      const nodeId = String(entry[0] || "").trim();
      const nextKey = String(entry[1] || "").trim();
      if (!nodeId || !nextKey || !variantsByKey.has(nextKey)) return;
      out.set(nodeId, nextKey);
    });
    return out;
  };
  const selectVariantByNodeId = mapNodeTargets(activeVariant.selectOnNodeId);
  const hoverVariantByNodeId = mapNodeTargets(activeVariant.hoverOnNodeId);
  const svg = graphContainer.select("svg").node();
  if (!svg) return;
  const readVariantState = function () {
    const state = svg.__bpVariantState;
    if (state && state.selectVariantByNodeId instanceof Map && state.hoverVariantByNodeId instanceof Map) {
      return state;
    }
    return {
      selectVariantByNodeId: new Map(),
      hoverVariantByNodeId: new Map(),
      lastHoverNodeId: ""
    };
  };
  svg.__bpVariantState = {
    selectVariantByNodeId: selectVariantByNodeId,
    hoverVariantByNodeId: hoverVariantByNodeId,
    lastHoverNodeId: ""
  };

  const nodeSelectKey = function (node) {
    const id = graphNodeId(node);
    if (!id) return "";
    const state = readVariantState();
    return state.selectVariantByNodeId.get(id) || "";
  };
  const activateFromTarget = function (target, ev) {
    if (!(target instanceof Element)) return;
    const node = target.closest("g.node");
    if (!node) return;
    const nextKey = nodeSelectKey(node);
    if (!nextKey) return;
    if (ev) {
      ev.preventDefault();
      ev.stopPropagation();
    }
    onSelect(nextKey);
  };
  const hoverFromTarget = function (target) {
    if (!(target instanceof Element)) return;
    const node = target.closest("g.node");
    if (!node) return;
    const id = graphNodeId(node);
    if (!id) return;
    const state = readVariantState();
    const nextKey = state.hoverVariantByNodeId.get(id) || "";
    if (!nextKey || id === state.lastHoverNodeId) return;
    state.lastHoverNodeId = id;
    onHover(id, nextKey, node);
  };

  svg.querySelectorAll("g.node").forEach(function (node) {
    const selectKey = nodeSelectKey(node);
    const id = graphNodeId(node);
    const state = readVariantState();
    const hoverKey = id ? (state.hoverVariantByNodeId.get(id) || "") : "";
    if (!selectKey && !hoverKey) return;
    node.style.cursor = "pointer";
    node.setAttribute("tabindex", "0");
  });
  if (svg.getAttribute("data-bp-variant-bound") === "1") return;
  svg.setAttribute("data-bp-variant-bound", "1");
  svg.addEventListener("click", function (ev) {
    activateFromTarget(ev.target, ev);
  });
  svg.addEventListener("keydown", function (ev) {
    if (ev.key !== "Enter" && ev.key !== " ") return;
    activateFromTarget(ev.target, ev);
  });
  svg.addEventListener("mouseover", function (ev) {
    hoverFromTarget(ev.target);
  });
  svg.addEventListener("mouseleave", function () {
    const state = readVariantState();
    state.lastHoverNodeId = "";
    if (typeof onHoverLeave === "function") onHoverLeave();
  });
}

function syncLegend(graphBlock, activeKey) {
  const fullLegend = graphBlock.querySelector('.bp_graph_legend[data-bp-legend-kind="full"]');
  const groupLegend = graphBlock.querySelector('.bp_graph_legend[data-bp-legend-kind="group"]');
  const showGroupLegend = activeKey === "group";
  if (fullLegend) fullLegend.hidden = showGroupLegend;
  if (groupLegend) groupLegend.hidden = !showGroupLegend;
}

function bindGraphPopover(previewUtils, graphBlock, buttonSelector, panelSelector, closeSelector, boundAttr) {
  const triggerButton = graphBlock.querySelector(buttonSelector);
  const popoverPanel = graphBlock.querySelector(panelSelector);
  const popoverClose = popoverPanel
    ? popoverPanel.querySelector(closeSelector)
    : null;
  return previewUtils.bindAnchoredPopover({
    root: graphBlock,
    trigger: triggerButton,
    panel: popoverPanel,
    close: popoverClose,
    boundAttr: boundAttr,
    offset: 8
  });
}

function bindLegendPopover(previewUtils, graphBlock) {
  return bindGraphPopover(
    previewUtils,
    graphBlock,
    ".bp_graph_legend_button",
    ".bp_graph_legend_popover",
    ".bp_graph_legend_popover_close",
    "data-bp-legend-bound"
  );
}

function bindOptionsPopover(previewUtils, graphBlock) {
  return bindGraphPopover(
    previewUtils,
    graphBlock,
    ".bp_graph_options_button",
    ".bp_graph_options_popover",
    ".bp_graph_options_popover_close",
    "data-bp-options-bound"
  );
}

export function initGraphBlock(previewUtils, graphBlock, options) {
      const opts = options && typeof options === "object" ? options : {};
      if (!(graphBlock instanceof Element)) return;
      const graphRoot = graphBlock.querySelector(".bp_graph_canvas");
      if (!graphRoot) return;
      // Static graphs (e.g. node-page localized graphs) opt out of variant
      // switching and the node-card modal; still rendered client-side by d3.
      const isStatic = graphRoot.getAttribute("data-bp-graph-static") === "true";
      // Zoom + pan are enabled on interactive graphs and on any static embed that
      // opts in via `data-bp-graph-zoom="true"` (the local node/decl graphs, which
      // ship a compact −/+/Fit cluster). Variant selectors + the modal stay gated
      // on `!isStatic`.
      const zoomEnabled =
        graphRoot.getAttribute("data-bp-graph-zoom") === "true" || !isStatic;
      if (opts.layout) {
        const layoutMode = graphLayoutMode(graphRoot, opts);
        graphBlock.setAttribute("data-bp-graph-layout", layoutMode);
        graphRoot.setAttribute("data-bp-graph-layout", layoutMode);
      }
      const graphContainer = d3.select(graphRoot);
      if (graphContainer.empty()) return;
      const graphState = ensureGraphBlockState(graphBlock);
      const existingController =
        graphState.controller && graphState.controller.__bpGraphController
          ? graphState.controller
          : (
            graphBlock.__bpGraphController &&
              graphBlock.__bpGraphController.__bpGraphController
              ? graphBlock.__bpGraphController
              : null
          );
      if (existingController) return existingController;
      const graphApiData = readPublicGraphData(graphBlock);
      if (graphApiData) {
        graphState.graphData = graphApiData;
        graphBlock.__bpGraphData = graphApiData;
      }
      const selector = graphBlock.querySelector(".bp_graph_view_select");
      const statusSelector = graphBlock.querySelector(".bp_graph_status_select");
      const directionSelector = graphBlock.querySelector(".bp_graph_direction_select");
      const packInput = graphBlock.querySelector(".bp_graph_pack_input");
      const allEdgesInput = graphBlock.querySelector(".bp_graph_all_edges_input");
      const previewModeSelector = graphBlock.querySelector(".bp_graph_preview_mode_select");
      const previewPlacementSelector = graphBlock.querySelector(".bp_graph_preview_placement_select");
      const previewMap = collectPreviewTemplates(previewUtils, graphBlock);
      // Per-node card metadata + the shared click-activated modal. Interactive
      // canvases with inline card templates only; static node-page graphs and
      // template-less consumer graphs keep the legacy docked preview behavior.
      const cardMeta = collectCardMeta(graphBlock);
      // Node -> declaration mapping + slim inline records for the selection bus.
      const graphDeclMeta = collectGraphDeclMeta(graphBlock);
      const graphModal =
        (!isStatic && previewMap.size > 0) ? ensureGraphModal(previewUtils) : null;
      const previewPanelNode = graphBlock.querySelector(".bp_graph_preview");
      const previewPanelBehavior = readPreviewBehaviorDefaults(previewPanelNode, "pinned", "docked");
      let previewController = null;
      previewController = previewUtils.createPreviewSurface({
        panel: previewPanelNode,
        titleSelector: ".bp_graph_preview_title",
        bodySelector: ".bp_graph_preview_body",
        closeSelector: ".bp_graph_preview_close",
        defaults: {
          mode: previewPanelBehavior.mode,
          placement: previewPanelBehavior.placement
        },
        onHide: function () {
          graphState.previewRequestToken += 1;
          graphState.previewActiveNode = null;
        }
      });
      graphState.previewController = previewController;
      const readPreviewMode = function () {
        if (previewModeSelector) return previewModeSelector.value;
        if (previewController && previewController.behavior) return previewController.behavior.mode;
        return previewPanelBehavior.mode || "pinned";
      };
      const readPreviewPlacement = function () {
        if (previewPlacementSelector) return previewPlacementSelector.value;
        if (previewController && previewController.behavior) return previewController.behavior.placement;
        return previewPanelBehavior.placement || "docked";
      };
      const setPreviewBehavior = function (nextMode, nextPlacement, options) {
        const opts = options && typeof options === "object" ? options : {};
        const behavior = previewController
          ? previewController.setBehavior({ mode: nextMode, placement: nextPlacement })
          : {
            mode: nextMode || previewPanelBehavior.mode || "pinned",
            placement: nextPlacement || previewPanelBehavior.placement || "docked"
          };
        const mode = behavior.mode;
        const placement = behavior.placement;
        if (previewPanelNode && !previewController) {
          previewPanelNode.setAttribute("data-bp-preview-mode", mode);
          previewPanelNode.setAttribute("data-bp-preview-placement", placement);
        }
        if (previewModeSelector) previewModeSelector.value = mode;
        if (previewPlacementSelector) previewPlacementSelector.value = placement;
        if (previewController) {
          if (!opts.keepOpen) previewController.hide();
        }
        return behavior;
      };
      setPreviewBehavior(
        previewModeSelector
          ? (previewModeSelector.getAttribute("data-bp-graph-default-preview-mode") || previewModeSelector.value)
          : (previewPanelBehavior.mode || "pinned"),
        previewPlacementSelector
          ? (previewPlacementSelector.getAttribute("data-bp-graph-default-preview-placement") || previewPlacementSelector.value)
          : (previewPanelBehavior.placement || "docked"),
        { keepOpen: true }
      );

      const rawVariants = readPublicGraphVariants(graphBlock);
      if (!Array.isArray(rawVariants) || rawVariants.length === 0) return;
      const variantsByKey = new Map();
      rawVariants.forEach(function (variant) {
        if (!variant || typeof variant !== "object") return;
        const key = String(variant.key || "").trim();
        const label = String(variant.label || key).trim();
        const dot = String(variant.dot || "").trim();
        // Unreduced DOT for the "Show all edges" toggle; absent when reduction
        // dropped nothing (then the reduced `dot` already shows every edge).
        const dotFull =
          typeof variant.dotFull === "string" && variant.dotFull.trim()
            ? variant.dotFull.trim()
            : "";
        const options = normalizeGraphOptions(
          variant.options && typeof variant.options === "object"
            ? variant.options
            : { direction: variant.direction, pack: variant.pack }
        );
        const selectOnNodeId = Array.isArray(variant.selectOnNodeId) ? variant.selectOnNodeId : [];
        const hoverOnNodeId = Array.isArray(variant.hoverOnNodeId) ? variant.hoverOnNodeId : [];
        const previewKeyByNodeId = Array.isArray(variant.previewKeyByNodeId) ? variant.previewKeyByNodeId : [];
        if (!key || !dot) return;
        variantsByKey.set(key, {
          key: key,
          label: label || key,
          dot: dot,
          dotFull: dotFull,
          options: options,
          selectOnNodeId: selectOnNodeId,
          hoverOnNodeId: hoverOnNodeId,
          previewKeyByNodeId: new Map(previewKeyByNodeId)
        });
      });
      const variants = Array.from(variantsByKey.values());
      if (variants.length === 0) return;
      graphBlock.__bpGraphVariants = variants;

      // STY-GRAPH-11: the SSR markup already renders primary views as top-level
      // options and per-subgraph (`parent:*`) variants inside an
      // <optgroup label="Subgraphs">. Only re-append client-side when that markup
      // is missing entirely (.options counts options nested in optgroups too, so
      // a populated selector — grouped or not — short-circuits here). When we do
      // rebuild, mirror the optgroup grouping and condensed subgraph labels.
      if (selector && selector.options.length === 0) {
        const makeOption = function (value, text) {
          const option = document.createElement("option");
          option.value = value;
          option.textContent = text;
          return option;
        };
        let subgroup = null;
        variants.forEach(function (variant) {
          if (String(variant.key).indexOf("parent:") === 0) {
            if (!subgroup) {
              subgroup = document.createElement("optgroup");
              subgroup.label = "Subgraphs";
              selector.appendChild(subgroup);
            }
            subgroup.appendChild(makeOption(variant.key, shortenVariantLabel(variant.label)));
          } else {
            selector.appendChild(makeOption(variant.key, variant.label));
          }
        });
      }

      let activeKey = variantsByKey.has("full") ? "full" : variants[0].key;
      if (selector && variantsByKey.has(selector.value)) {
        activeKey = selector.value;
      }
      if (selector) selector.value = activeKey;
      let activeOptions = normalizeGraphOptions({
        direction: directionSelector
          ? directionSelector.getAttribute("data-bp-graph-default-direction")
          : graphContainer.attr("data-bp-graph-direction"),
        pack: packInput
          ? packInput.getAttribute("data-bp-graph-default-pack")
          : graphContainer.attr("data-bp-graph-pack"),
        allEdges: allEdgesInput
          ? allEdgesInput.getAttribute("data-bp-graph-default-all-edges")
          : graphContainer.attr("data-bp-graph-all-edges")
      });
      if (directionSelector) directionSelector.value = activeOptions.direction;
      if (packInput) packInput.checked = activeOptions.pack;
      if (allEdgesInput) allEdgesInput.checked = activeOptions.allEdges;
      syncLegend(graphBlock, activeKey);
      const legendPopover = bindLegendPopover(previewUtils, graphBlock);
      const optionsPopover = bindOptionsPopover(previewUtils, graphBlock);

      const getActiveVariant = function () {
        const fallback = variantsByKey.get("full") || variants[0];
        return variantsByKey.get(activeKey) || fallback;
      };

      const getActiveOptions = function () {
        return normalizeGraphOptions(activeOptions);
      };

      const groupHoverPanel = graphBlock.querySelector(".bp_group_hover_preview");
      let groupHoverGraphviz = null;
      const groupHoverBehavior = readPreviewBehaviorDefaults(groupHoverPanel, "pinned", "docked");
      let groupHoverController = null;
      groupHoverController = previewUtils.createPreviewSurface({
        panel: groupHoverPanel,
        titleSelector: ".bp_group_hover_preview_title",
        bodySelector: ".bp_group_hover_preview_graph",
        closeSelector: ".bp_group_hover_preview_close",
        defaults: {
          mode: groupHoverBehavior.mode,
          placement: groupHoverBehavior.placement
        },
        renderBody: function (body, variant) {
          const width = Math.max(320, body.clientWidth || 0);
          const height = Math.max(220, body.clientHeight || 0);
          const container = d3.select(body);
          if (!groupHoverGraphviz) {
            groupHoverGraphviz = container.graphviz({ useWorker: false }).fit(true);
          }
          groupHoverGraphviz
            .width(width)
            .height(height)
            .renderDot(dotForVariantOptions(variant, getActiveOptions()));
        },
        positionPanel: makeGroupPanelPositioner(graphBlock, function () {
          return groupHoverController ? groupHoverController.behavior : groupHoverBehavior;
        }),
        onHide: function () {
          graphState.groupHoverAnchorNode = null;
          graphState.groupHoverShownKey = "";
          graphState.groupHoverShownNodeId = "";
        }
      });
      graphState.groupHoverController = groupHoverController;
      const groupHoverLifetime = groupHoverController
        ? groupHoverController.bindTriggers({
          panelBoundAttr: "data-bp-group-hover-bound",
          hide: function () {
            if (groupHoverController) groupHoverController.hide();
          },
          getActiveTrigger: function () { return graphState.groupHoverAnchorNode; },
          bindEscape: false,
          bindWindow: false
        })
        : {
          cancelHide: function () {},
          scheduleHide: function () {}
        };

      const lifecycleSurface = previewController || groupHoverController;
      if (!graphState.windowHandlersBound && lifecycleSurface) {
        graphState.windowHandlersBound = true;
        const repositionPanels = function () {
          if (legendPopover && legendPopover.isOpen()) {
            legendPopover.position();
          }
          if (optionsPopover && optionsPopover.isOpen()) {
            optionsPopover.position();
          }
          if (
            graphState.previewController &&
            graphState.previewController.behavior &&
            graphState.previewController.behavior.isAnchored &&
            graphState.previewActiveNode &&
            !graphState.previewController.panel.hidden
          ) {
            graphState.previewController.position(graphState.previewActiveNode);
          }
          if (
            graphState.groupHoverController &&
            graphState.groupHoverController.behavior &&
            graphState.groupHoverController.behavior.isAnchored &&
            graphState.groupHoverAnchorNode &&
            !graphState.groupHoverController.panel.hidden
          ) {
            graphState.groupHoverController.position(graphState.groupHoverAnchorNode);
          }
        };
        lifecycleSurface.bindDismissal({
          owner: graphBlock,
          boundAttr: "data-bp-graph-panel-dismiss-bound",
          closeButton: null,
          bindTrigger: false,
          bindOutside: false,
          bindEscape: true,
          isOpen: function () {
            return (
              (legendPopover && legendPopover.isOpen()) ||
              (optionsPopover && optionsPopover.isOpen()) ||
              (
                graphState.groupHoverController &&
                graphState.groupHoverController.panel &&
                !graphState.groupHoverController.panel.hidden
              ) ||
              (
                graphState.previewController &&
                graphState.previewController.panel &&
                !graphState.previewController.panel.hidden
              )
            );
          },
          close: function () {
            if (legendPopover) legendPopover.close();
            if (optionsPopover) optionsPopover.close();
            if (graphState.groupHoverController) graphState.groupHoverController.hide();
            if (graphState.previewController) graphState.previewController.hide();
          }
        });
        lifecycleSurface.bindRepositioner({
          owner: graphBlock,
          boundAttr: "data-bp-graph-panel-reposition-bound",
          reposition: repositionPanels
        });
      }

      const showGroupHoverPreview = function (nodeId, nextKey, anchorNode) {
        if (!groupHoverController) return;
        groupHoverLifetime.cancelHide();
        if (activeKey !== "group") {
          groupHoverController.hide();
          return;
        }
        const variant = variantsByKey.get(nextKey);
        if (!variant || !variant.dot || !nodeId) {
          groupHoverController.hide();
          return;
        }
        if (
          !groupHoverController.panel.hidden &&
          graphState.groupHoverShownKey === nextKey &&
          graphState.groupHoverShownNodeId === nodeId
        ) {
          groupHoverController.position(anchorNode);
          return;
        }
        graphState.groupHoverAnchorNode = anchorNode instanceof Element ? anchorNode : null;
        graphState.groupHoverShownKey = nextKey;
        graphState.groupHoverShownNodeId = nodeId;
        groupHoverController.show("Preview: " + variant.label, variant, graphState.groupHoverAnchorNode);
      };

      const switchVariant = function (nextKey) {
        if (!variantsByKey.has(nextKey) || nextKey === activeKey) return;
        activeKey = nextKey;
        if (selector) selector.value = nextKey;
        syncLegend(graphBlock, activeKey);
        renderGraph();
      };

      const switchGraphOptions = function (nextOptions) {
        const rawNextOptions = nextOptions && typeof nextOptions === "object" ? nextOptions : {};
        const normalized = normalizeGraphOptions({
          direction: Object.prototype.hasOwnProperty.call(rawNextOptions, "direction")
            ? rawNextOptions.direction
            : activeOptions.direction,
          pack: Object.prototype.hasOwnProperty.call(rawNextOptions, "pack")
            ? rawNextOptions.pack
            : activeOptions.pack,
          allEdges: Object.prototype.hasOwnProperty.call(rawNextOptions, "allEdges")
            ? rawNextOptions.allEdges
            : activeOptions.allEdges
        });
        if (graphOptionsKey(normalized) === graphOptionsKey(activeOptions)) return;
        activeOptions = normalized;
        if (directionSelector) directionSelector.value = normalized.direction;
        if (packInput) packInput.checked = normalized.pack;
        if (allEdgesInput) allEdgesInput.checked = normalized.allEdges;
        renderGraph();
      };

      const switchDirection = function (nextDirection) {
        switchGraphOptions({ direction: nextDirection });
      };

      const switchPack = function (nextPack) {
        switchGraphOptions({ pack: nextPack });
      };

      const switchAllEdges = function (nextAllEdges) {
        switchGraphOptions({ allEdges: nextAllEdges });
      };

      const scheduleRender = debounce(function () {
        renderGraph();
      }, 180);

      function renderGraph() {
        const activeVariant = getActiveVariant();
        const options = getActiveOptions();
        const optionsKey = graphOptionsKey(options);
        const dot = dotForVariantOptions(activeVariant, options);
        if (!activeVariant || !dot) return;
        graphState.renderToken += 1;
        const renderToken = graphState.renderToken;
        syncLegend(graphBlock, activeVariant.key);
        if (previewController) previewController.hide();
        if (groupHoverController) groupHoverController.hide();
        layoutGraphCanvas(graphRoot, graphState, opts);
        const width = graphRoot.clientWidth;
        const height = graphRoot.clientHeight;
        rememberGraphLayoutMeasurements(graphBlock, graphRoot, graphState);
        const finalizeRender = function () {
          if (graphState.renderToken !== renderToken) return;
          if (graphState.renderFinalizedToken === renderToken) return;
          graphState.renderFinalizedToken = renderToken;
          // Stamp decl selection on every node BEFORE the preview pass strips
          // `<title>`s, so both blueprint and supporting nodes feed the rail.
          attachSelectionHandlers(
            graphBlock,
            graphContainer,
            graphDeclMeta.labelToDecl,
            graphDeclMeta.metaByDecl
          );
          attachPreviewHandlers(
            previewUtils,
            graphBlock,
            graphContainer,
            previewMap,
            previewController,
            activeVariant.previewKeyByNodeId,
            graphModal,
            cardMeta
          );
          if (!isStatic) {
            attachVariantSelectors(
              graphContainer,
              variantsByKey,
              activeVariant,
              switchVariant,
              showGroupHoverPreview,
              groupHoverBehavior.isHover && groupHoverController
                ? function () { groupHoverLifetime.scheduleHide(); }
                : null
            );
          }
        };

        if (
          (graphState.renderedVariantKey &&
            graphState.renderedVariantKey !== activeVariant.key) ||
          (graphState.renderedOptionsKey &&
            graphState.renderedOptionsKey !== optionsKey)
        ) {
          resetGraphvizForVariant(graphRoot, graphState);
        }
        const gv = graphState.graphviz || graphContainer.graphviz({ useWorker: false });
        graphState.graphviz = gv;
        graphState.renderedVariantKey = activeVariant.key;
        graphState.renderedOptionsKey = optionsKey;
        graphRoot.setAttribute("data-bp-active-direction", options.direction);
        graphRoot.setAttribute("data-bp-active-pack", graphPackAttr(options.pack));
        gv
          .zoom(zoomEnabled)
          .width(width)
          .height(height)
          .fit(true)
          .on("end", function () {
            finalizeRender();
          });
        gv.renderDot(dot);
        setTimeout(function () {
          finalizeRender();
        }, 120);
      }

      if (selector) {
        selector.addEventListener("change", function () {
          switchVariant(selector.value);
        });
      }
      if (statusSelector) {
        // Status highlight/filter: toggle a data attribute on the canvas; CSS
        // dims nodes that do not match the selected status. Pure class toggling,
        // composes with all variants, no traversal or network.
        const applyStatusFilter = function (value) {
          if (!value || value === "all") {
            graphRoot.removeAttribute("data-bp-status-filter");
          } else {
            graphRoot.setAttribute("data-bp-status-filter", value);
          }
        };
        applyStatusFilter(statusSelector.value);
        statusSelector.addEventListener("change", function () {
          applyStatusFilter(statusSelector.value);
        });
      }
      if (directionSelector) {
        directionSelector.addEventListener("change", function () {
          switchDirection(directionSelector.value);
          if (optionsPopover) optionsPopover.close();
        });
      }
      if (packInput) {
        packInput.addEventListener("change", function () {
          switchPack(packInput.checked);
        });
      }
      if (allEdgesInput) {
        allEdgesInput.addEventListener("change", function () {
          switchAllEdges(allEdgesInput.checked);
        });
      }
      if (previewModeSelector) {
        previewModeSelector.addEventListener("change", function () {
          setPreviewBehavior(previewModeSelector.value, readPreviewPlacement());
        });
      }
      if (previewPlacementSelector) {
        previewPlacementSelector.addEventListener("change", function () {
          setPreviewBehavior(readPreviewMode(), previewPlacementSelector.value);
        });
      }

      // STY-GRAPH-12: visible zoom +/- and fit/reset affordances (scroll-zoom +
      // drag are otherwise undiscoverable). Wired whenever zoom is enabled — the
      // interactive canvas and any opted-in static embed (local node/decl graphs).
      // Static graphs without the cluster omit the buttons, so these queries no-op.
      if (zoomEnabled) {
        const zoomInBtn = graphBlock.querySelector(".bp_graph_zoom_in");
        const zoomOutBtn = graphBlock.querySelector(".bp_graph_zoom_out");
        const zoomFitBtn = graphBlock.querySelector(".bp_graph_zoom_fit");
        // Scale the rendered graph about its center by `factor`, driving the same
        // d3-zoom behavior d3-graphviz wired up for scroll/drag so button zoom and
        // gesture zoom stay in sync. Falls back to a manual transform if the
        // graphviz zoom accessors are unavailable in the vendored build.
        const applyZoomScale = function (factor) {
          const gv = graphState.graphviz;
          if (!gv) return;
          let zoomBehavior = null;
          let zoomSelection = null;
          try {
            if (typeof gv.zoomBehavior === "function") zoomBehavior = gv.zoomBehavior();
          } catch (_e) { zoomBehavior = null; }
          try {
            if (typeof gv.zoomSelection === "function") zoomSelection = gv.zoomSelection();
          } catch (_e) { zoomSelection = null; }
          if (zoomBehavior && zoomSelection && typeof zoomBehavior.scaleBy === "function") {
            zoomBehavior.scaleBy(zoomSelection.transition().duration(160), factor);
            return;
          }
          // Fallback: scale the <g> transform group directly via d3-zoom.
          const svg = graphContainer.select("svg");
          if (svg.empty() || typeof d3.zoom !== "function") return;
          const g = svg.select("g");
          if (g.empty()) return;
          const current = (typeof d3.zoomTransform === "function")
            ? d3.zoomTransform(svg.node())
            : { k: 1, x: 0, y: 0 };
          const nextK = (current.k || 1) * factor;
          if (typeof d3.zoomIdentity !== "undefined") {
            const t = d3.zoomIdentity.translate(current.x || 0, current.y || 0).scale(nextK);
            g.transition().duration(160).attr("transform", t.toString());
          }
        };
        const fitGraph = function () {
          const gv = graphState.graphviz;
          if (gv && typeof gv.resetZoom === "function") {
            try {
              gv.resetZoom(d3.transition ? d3.transition().duration(160) : undefined);
              return;
            } catch (_e) { /* fall through to a full re-render below */ }
          }
          // No resetZoom available: re-render the active variant, which is built
          // with `.fit(true)` and recenters the graph in the canvas.
          renderGraph();
        };
        if (zoomInBtn) {
          zoomInBtn.addEventListener("click", function () { applyZoomScale(1.2); });
        }
        if (zoomOutBtn) {
          zoomOutBtn.addEventListener("click", function () { applyZoomScale(0.8); });
        }
        if (zoomFitBtn) {
          zoomFitBtn.addEventListener("click", function () { fitGraph(); });
        }
      }

      const controller = {
        __bpGraphController: true,
        block: graphBlock,
        canvas: graphRoot,
        state: graphState,
        variants: variants,
        variantsByKey: variantsByKey,
        getActiveVariant: getActiveVariant,
        getActiveOptions: getActiveOptions,
        layout: function (layoutOptions) {
          layoutGraphCanvas(graphRoot, graphState, layoutOptions || opts);
          return controller;
        },
        render: function () {
          renderGraph();
          return controller;
        },
        scheduleRender: function () {
          scheduleRender();
          return controller;
        },
        setView: function (nextKey) {
          switchVariant(nextKey);
          return controller;
        },
        setVariant: function (nextKey) {
          switchVariant(nextKey);
          return controller;
        },
        setOptions: function (nextOptions) {
          switchGraphOptions(nextOptions);
          return controller;
        },
        setDirection: function (nextDirection) {
          switchDirection(nextDirection);
          return controller;
        },
        setPack: function (nextPack) {
          switchPack(nextPack);
          return controller;
        },
        setPreviewBehavior: function (nextMode, nextPlacement, behaviorOptions) {
          setPreviewBehavior(nextMode, nextPlacement, behaviorOptions);
          return controller;
        }
      };
      graphState.controller = controller;
      graphBlock.__bpGraphController = controller;

      renderGraph();
      if (!graphState.blockResizeBound) {
        graphState.blockResizeBound = true;
        // No window "resize" -> re-render coupling: the canvas height is fixed
        // (graph-runtime-core `layoutGraphCanvas`), so only *width* changes need a
        // reflow. Those are caught by the ResizeObserver on graphBlock / graphRoot
        // below (e.g. dragging the ToC or the properties rail), which keeps the
        // graph responsive without tying its height to the viewport.
        if (typeof ResizeObserver === "function") {
          const observer = new ResizeObserver(function (entries) {
            let shouldRender = false;
            entries.forEach(function (entry) {
              if (!entry || !entry.target || !entry.contentRect) return;
              const nextWidth = Math.round(entry.contentRect.width);
              const nextHeight = Math.round(entry.contentRect.height);
              if (entry.target === graphBlock) {
                if (Math.abs(nextWidth - graphState.lastBlockWidth) > 1) {
                  graphState.lastBlockWidth = nextWidth;
                  shouldRender = true;
                }
                return;
              }
              if (entry.target === graphRoot) {
                const widthChanged = Math.abs(nextWidth - graphState.lastCanvasWidth) > 1;
                const heightChanged = Math.abs(nextHeight - graphState.lastCanvasHeight) > 1;
                if (widthChanged) {
                  graphState.lastCanvasWidth = nextWidth;
                  graphState.lastCanvasHeight = nextHeight;
                  shouldRender = true;
                  return;
                }
                if (heightChanged) {
                  graphState.lastCanvasWidth = nextWidth;
                  graphState.lastCanvasHeight = nextHeight;
                  if (!resizeRenderedGraphToCanvas(graphRoot, graphState)) {
                    shouldRender = true;
                  }
                }
              }
            });
            if (shouldRender) scheduleRender();
          });
          observer.observe(graphBlock);
          observer.observe(graphRoot);
          graphState.resizeObserver = observer;
        }
      }
      return controller;
    }

// Vendored locally (see PreviewManifest.lean writeVendorLibraries -> -verso-data/lib/) so the
// dependency graph works offline / under a strict-CSP viewer with no CDN access. These are
// document-relative; every page's <base href> resolves to the site root, so this resolves to
// /-verso-data/lib/*.min.js (matching how katex is referenced at -verso-data/katex/...).
const defaultGraphRuntimeLibraryUrls = {
  d3: "-verso-data/lib/d3.min.js",
  graphviz: "-verso-data/lib/d3-graphviz.min.js"
};

let graphRuntimeLibrariesPromise = null;

function readGraphRuntimeLibraryUrls(options) {
  const opts = options && typeof options === "object" ? options : {};
  const libs = opts.libraries && typeof opts.libraries === "object" ? opts.libraries : {};
  return {
    d3: typeof libs.d3 === "string" && libs.d3.length > 0 ? libs.d3 : defaultGraphRuntimeLibraryUrls.d3,
    graphviz:
      typeof libs.graphviz === "string" && libs.graphviz.length > 0
        ? libs.graphviz
        : defaultGraphRuntimeLibraryUrls.graphviz
  };
}

function hasD3Library() {
  return !!(window.d3 && typeof window.d3.select === "function");
}

function hasGraphvizLibrary() {
  if (!hasD3Library()) return false;
  try {
    const probe = document.createElement("div");
    return typeof window.d3.select(probe).graphviz === "function";
  } catch (_err) {
    return false;
  }
}

export function ensureGraphRuntimeLibraries(options) {
  const urls = readGraphRuntimeLibraryUrls(options);
  if (hasGraphvizLibrary()) return Promise.resolve();
  if (!graphRuntimeLibrariesPromise) {
    graphRuntimeLibrariesPromise = Promise.resolve()
      .then(function () {
        if (hasD3Library()) return null;
        return load(urls.d3);
      })
      .then(function () {
        if (hasGraphvizLibrary()) return null;
        return load(urls.graphviz);
      })
      .catch(function (err) {
        graphRuntimeLibrariesPromise = null;
        throw err;
      });
  }
  return graphRuntimeLibrariesPromise;
}

function currentRenderApi() {
  const namespace =
    window.VersoBlueprint && typeof window.VersoBlueprint === "object"
      ? window.VersoBlueprint
      : null;
  const renderApi =
    namespace && namespace.render && typeof namespace.render === "object"
      ? namespace.render
      : null;
  return renderApi;
}

export function getGraphRenderApi(options) {
  const opts = options && typeof options === "object" ? options : {};
  if (opts.previewUtils && typeof opts.previewUtils === "object") {
    return Promise.resolve(opts.previewUtils);
  }
  const readyApi = currentRenderApi();
  if (readyApi) return Promise.resolve(readyApi);
  const namespace =
    window.VersoBlueprint && typeof window.VersoBlueprint === "object"
      ? window.VersoBlueprint
      : null;
  if (namespace && typeof namespace.onRenderReady === "function") {
    return new Promise(function (resolve) {
      namespace.onRenderReady(resolve);
    });
  }
  return Promise.reject(
    new Error("Blueprint graph rendering requires the Blueprint render API or options.previewUtils")
  );
}

function isGraphSearchRoot(root) {
  return (
    root instanceof Element ||
    root instanceof Document ||
    (typeof DocumentFragment !== "undefined" && root instanceof DocumentFragment)
  );
}

function graphBlocksIn(root) {
  const scope = isGraphSearchRoot(root) ? root : document;
  const blocks = [];
  if (scope instanceof Element && scope.matches(".bp_graph_fullwidth")) {
    blocks.push(scope);
  }
  if (typeof scope.querySelectorAll === "function") {
    scope.querySelectorAll(".bp_graph_fullwidth").forEach(function (block) {
      if (block instanceof Element && blocks.indexOf(block) < 0) {
        blocks.push(block);
      }
    });
  }
  return blocks;
}

function normalizeGraphRenderArgs(root, options) {
  if (isGraphSearchRoot(root)) {
    return {
      root: root,
      options: options && typeof options === "object" ? options : {}
    };
  }
  return {
    root: document,
    options: root && typeof root === "object" ? root : {}
  };
}

export async function renderGraphBlock(graphBlock, options) {
  const opts = options && typeof options === "object" ? options : {};
  const previewUtils = await getGraphRenderApi(opts);
  await ensureGraphRuntimeLibraries(opts);
  const controller = initGraphBlock(previewUtils, graphBlock, opts);
  if (opts.refresh && controller && typeof controller.render === "function") {
    controller.render();
  }
  return controller || null;
}

export async function renderGraphs(root, options) {
  const args = normalizeGraphRenderArgs(root, options);
  const blocks = graphBlocksIn(args.root);
  if (blocks.length === 0) return [];
  const previewUtils = await getGraphRenderApi(args.options);
  await ensureGraphRuntimeLibraries(args.options);
  return blocks
    .map(function (block) {
      const controller = initGraphBlock(previewUtils, block, args.options);
      if (args.options.refresh && controller && typeof controller.render === "function") {
        controller.render();
      }
      return controller || null;
    })
    .filter(function (controller) { return !!controller; });
}

export function installGraphRenderApi(previewUtils, options) {
  if (!previewUtils || typeof previewUtils !== "object") return {};
  const installed = {
    ensureGraphRuntimeLibraries: ensureGraphRuntimeLibraries,
    initGraphBlock: function (graphBlock, nextOptions) {
      return initGraphBlock(
        previewUtils,
        graphBlock,
        Object.assign({}, options || {}, nextOptions || {})
      );
    },
    renderGraphBlock: function (graphBlock, nextOptions) {
      return renderGraphBlock(
        graphBlock,
        Object.assign({}, options || {}, nextOptions || {}, { previewUtils: previewUtils })
      );
    },
    renderGraphs: function (root, nextOptions) {
      if (!isGraphSearchRoot(root) && root && typeof root === "object" && !nextOptions) {
        return renderGraphs(
          Object.assign({}, options || {}, root, { previewUtils: previewUtils })
        );
      }
      return renderGraphs(
        root,
        Object.assign({}, options || {}, nextOptions || {}, { previewUtils: previewUtils })
      );
    }
  };
  Object.assign(previewUtils, installed);
  return installed;
}

export function bindGraphs(previewUtils, options) {
    const opts = options && typeof options === "object" ? options : {};
    const root = isGraphSearchRoot(opts.root) ? opts.root : document;
    const graphBlocks = graphBlocksIn(root);
    if (graphBlocks.length === 0) return Promise.resolve([]);
    return ensureGraphRuntimeLibraries(opts)
      .then(function () {
        return graphBlocks
          .map(function (graphBlock) {
            return initGraphBlock(previewUtils, graphBlock, opts) || null;
          })
          .filter(function (controller) { return !!controller; });
      });
}

export function startGraphRuntime(previewUtils, options) {
  installGraphRenderApi(previewUtils, options);
  // Ensure the selection bus exists (idempotent with the metadata rail) so graph
  // node clicks can populate the rail regardless of boot order.
  installSelectionBus();
  if (document.readyState === "loading") {
    return new Promise(function (resolve, reject) {
      document.addEventListener("DOMContentLoaded", function () {
        bindGraphs(previewUtils, options).then(resolve, reject);
      }, { once: true });
    });
  } else {
    return bindGraphs(previewUtils, options);
  }
}

export const graphRuntime = {
  ensureGraphRuntimeLibraries,
  getGraphRenderApi,
  initGraphBlock,
  renderGraphBlock,
  renderGraphs,
  installGraphRenderApi,
  bindGraphs,
  startGraphRuntime
};

export default graphRuntime;
