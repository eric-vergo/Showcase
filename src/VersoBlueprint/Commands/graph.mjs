import * as graphRuntimeCoreModule from "./graph-runtime-core.mjs";

const {
  debounce,
  normalizeGraphOptions,
  graphPackAttr,
  graphOptionsKey,
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

function readPublicGraphData(previewUtils, root) {
  if (previewUtils && typeof previewUtils.getGraphData === "function") {
    return previewUtils.getGraphData(root);
  }
  return null;
}

function readPublicGraphVariants(previewUtils, root) {
  let variants = [];
  if (previewUtils && typeof previewUtils.getGraphVariants === "function") {
    variants = previewUtils.getGraphVariants(root);
  }
  if (Array.isArray(variants) && variants.length > 0) {
    return variants;
  }
  return [];
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
  return dotWithGraphOptions(variant.dot, options);
}

function attachPreviewHandlers(previewUtils, graphBlock, graphContainer, previewMap, previewController, previewKeyByNodeId) {
  if (!previewController) return;
  const graphState = ensureGraphBlockState(graphBlock);
  const previewKeys =
    previewKeyByNodeId instanceof Map ? previewKeyByNodeId : new Map();
  const svg = graphContainer.select("svg").node();
  if (!svg || !(svg instanceof SVGElement)) {
    previewController.hide();
    return;
  }
  if (!previewController.title || !previewController.body || (previewMap.size === 0 && previewKeys.size === 0)) {
    previewController.hide();
    return;
  }
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
    activateOnClick: true,
    activateOnKeydown: true,
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

export function bindGraphs(previewUtils) {
    const graphBlocks = Array.from(document.querySelectorAll(".bp_graph_fullwidth"));
    if (graphBlocks.length === 0) return;
    Promise.resolve()
    .then(function () { return load("https://cdn.jsdelivr.net/npm/d3@7.9.0/dist/d3.min.js"); })
    .then(function () { return load("https://cdn.jsdelivr.net/npm/d3-graphviz@5.6.0/build/d3-graphviz.min.js"); })
    .then(function () {
    function initGraphBlock(graphBlock) {
      if (!(graphBlock instanceof Element)) return;
      const graphRoot = graphBlock.querySelector(".bp_graph_canvas");
      if (!graphRoot) return;
      const graphContainer = d3.select(graphRoot);
      if (graphContainer.empty()) return;
      const graphState = ensureGraphBlockState(graphBlock);
      const graphApiData = readPublicGraphData(previewUtils, graphBlock);
      if (graphApiData) {
        graphState.graphData = graphApiData;
        graphBlock.__bpGraphData = graphApiData;
      }
      const selector = graphBlock.querySelector(".bp_graph_view_select");
      const directionSelector = graphBlock.querySelector(".bp_graph_direction_select");
      const packInput = graphBlock.querySelector(".bp_graph_pack_input");
      const previewModeSelector = graphBlock.querySelector(".bp_graph_preview_mode_select");
      const previewPlacementSelector = graphBlock.querySelector(".bp_graph_preview_placement_select");
      const previewMap = collectPreviewTemplates(previewUtils, graphBlock);
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

      const rawVariants = readPublicGraphVariants(previewUtils, graphBlock);
      if (!Array.isArray(rawVariants) || rawVariants.length === 0) return;
      const variantsByKey = new Map();
      rawVariants.forEach(function (variant) {
        if (!variant || typeof variant !== "object") return;
        const key = String(variant.key || "").trim();
        const label = String(variant.label || key).trim();
        const dot = String(variant.dot || "").trim();
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
          options: options,
          selectOnNodeId: selectOnNodeId,
          hoverOnNodeId: hoverOnNodeId,
          previewKeyByNodeId: new Map(previewKeyByNodeId)
        });
      });
      const variants = Array.from(variantsByKey.values());
      if (variants.length === 0) return;
      graphBlock.__bpGraphVariants = variants;

      if (selector && selector.options.length === 0) {
        variants.forEach(function (variant) {
          const option = document.createElement("option");
          option.value = variant.key;
          option.textContent = variant.label;
          selector.appendChild(option);
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
          : graphContainer.attr("data-bp-graph-pack")
      });
      if (directionSelector) directionSelector.value = activeOptions.direction;
      if (packInput) packInput.checked = activeOptions.pack;
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
            groupHoverGraphviz = container.graphviz().fit(true);
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
            : activeOptions.pack
        });
        if (graphOptionsKey(normalized) === graphOptionsKey(activeOptions)) return;
        activeOptions = normalized;
        if (directionSelector) directionSelector.value = normalized.direction;
        if (packInput) packInput.checked = normalized.pack;
        renderGraph();
      };

      const switchDirection = function (nextDirection) {
        switchGraphOptions({ direction: nextDirection });
      };

      const switchPack = function (nextPack) {
        switchGraphOptions({ pack: nextPack });
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
        layoutGraphCanvas(graphRoot, graphState);
        const width = graphRoot.clientWidth;
        const height = graphRoot.clientHeight;
        rememberGraphLayoutMeasurements(graphBlock, graphRoot, graphState);
        const finalizeRender = function () {
          if (graphState.renderToken !== renderToken) return;
          if (graphState.renderFinalizedToken === renderToken) return;
          graphState.renderFinalizedToken = renderToken;
          attachPreviewHandlers(
            previewUtils,
            graphBlock,
            graphContainer,
            previewMap,
            previewController,
            activeVariant.previewKeyByNodeId
          );
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
        };

        if (
          (graphState.renderedVariantKey &&
            graphState.renderedVariantKey !== activeVariant.key) ||
          (graphState.renderedOptionsKey &&
            graphState.renderedOptionsKey !== optionsKey)
        ) {
          resetGraphvizForVariant(graphRoot, graphState);
        }
        const gv = graphState.graphviz || graphContainer.graphviz();
        graphState.graphviz = gv;
        graphState.renderedVariantKey = activeVariant.key;
        graphState.renderedOptionsKey = optionsKey;
        graphRoot.setAttribute("data-bp-active-direction", options.direction);
        graphRoot.setAttribute("data-bp-active-pack", graphPackAttr(options.pack));
        gv
          .zoom(true)
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

      renderGraph();
      if (!graphState.blockResizeBound) {
        graphState.blockResizeBound = true;
        window.addEventListener("resize", scheduleRender);
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
    }

    graphBlocks.forEach(initGraphBlock);
    });
}

export function startGraphRuntime(previewUtils) {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      bindGraphs(previewUtils);
    }, { once: true });
  } else {
    bindGraphs(previewUtils);
  }
}

export const graphRuntime = {
  bindGraphs,
  startGraphRuntime
};

export default graphRuntime;
