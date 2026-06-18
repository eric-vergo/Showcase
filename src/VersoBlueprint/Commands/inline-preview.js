(function () {
  const triggerSelector = ".bp_inline_preview_ref[data-bp-preview-id]";

  function blueprintRender() {
    return window.VersoBlueprint.render;
  }

  function onBlueprintRenderReady(fn) {
    const namespace =
      window.VersoBlueprint && typeof window.VersoBlueprint === "object"
        ? window.VersoBlueprint
        : {};
    window.VersoBlueprint = namespace;
    if (namespace.render) {
      namespace.onRenderReady(fn);
      return;
    }
    if (!Array.isArray(namespace.renderReadyCallbacks)) {
      namespace.renderReadyCallbacks = [];
    }
    namespace.renderReadyCallbacks.push(fn);
  }

  function fallbackInlinePreviewHtml(trigger, key, escapeHtml) {
    if (!(trigger instanceof Element)) return "";
    const title = (trigger.getAttribute("data-bp-preview-title") || key || "").trim();
    const label = (trigger.getAttribute("data-bp-preview-fallback-label") || "").trim();
    const detail = (trigger.getAttribute("data-bp-preview-fallback-detail") || "").trim();
    const text = (trigger.textContent || "").trim();
    let html = '<div class="bp_code_hover" role="tooltip">';
    html += '<div class="bp_code_hover_title">' + escapeHtml(title || "Preview") + "</div>";
    if (text.length > 0) {
      html += '<div class="bp_code_hover_section"><span class="bp_code_hover_label">Reference</span><ul class="bp_code_hover_list"><li>' +
        escapeHtml(text) + "</li></ul></div>";
    }
    if (label.length > 0) {
      html += '<div class="bp_code_hover_section"><span class="bp_code_hover_label">Blueprint label</span><ul class="bp_code_hover_list"><li><code>' +
        escapeHtml(label) + "</code></li></ul></div>";
    }
    if (detail.length > 0) {
      html += '<div class="bp_code_hover_section"><span class="bp_code_hover_label">Detail</span><ul class="bp_code_hover_list"><li>' +
        escapeHtml(detail) + "</li></ul></div>";
    }
    html += "</div>";
    return html;
  }

  function makePanel(id, extraClass) {
    const panel = document.createElement("aside");
    panel.id = id;
    panel.className =
      "bp_inline_preview_panel" + (typeof extraClass === "string" && extraClass.length > 0 ? " " + extraClass : "");
    panel.setAttribute("data-bp-preview-mode", "hover");
    panel.setAttribute("data-bp-preview-placement", "anchored");
    panel.hidden = true;
    panel.innerHTML =
      '<div class="bp_inline_preview_panel_header">' +
      '<div class="bp_inline_preview_panel_heading bp_preview_header_heading">' +
      '<div class="bp_inline_preview_panel_title"></div>' +
      '<a class="bp_inline_preview_panel_label bp_preview_header_label" hidden></a>' +
      "</div>" +
      '<button type="button" class="bp_inline_preview_panel_close" aria-label="Close inline preview">Close</button>' +
      "</div>" +
      '<div class="bp_inline_preview_panel_body"></div>' +
      '<div class="bp_inline_preview_panel_footer" hidden></div>';
    document.body.appendChild(panel);
    return panel;
  }

  function getPanel(id, extraClass) {
    const existing = document.getElementById(id);
    if (existing instanceof Element) return existing;
    return makePanel(id, extraClass);
  }

  function bindInlinePreview() {
    if (!(document.body instanceof Element)) return;
    if (document.body.getAttribute("data-bp-inline-preview-bound") === "1") return;
    document.body.setAttribute("data-bp-inline-preview-bound", "1");

    const previewUtils = blueprintRender();
    const escapeHtml = previewUtils.escapeHtml;
    const previewDebug = previewUtils.previewDebug;
    const previewDebugLabel = previewUtils.previewDebugLabel;

    const panel = getPanel("bp-inline-preview-panel", "");
    const title = panel.querySelector(".bp_inline_preview_panel_title");
    const headerLabel = panel.querySelector(".bp_inline_preview_panel_label");
    const body = panel.querySelector(".bp_inline_preview_panel_body");
    const footer = panel.querySelector(".bp_inline_preview_panel_footer");
    const close = panel.querySelector(".bp_inline_preview_panel_close");
    const childPanel = getPanel("bp-inline-preview-child-panel", "bp_inline_preview_panel_child");
    const childTitle = childPanel.querySelector(".bp_inline_preview_panel_title");
    const childHeaderLabel = childPanel.querySelector(".bp_inline_preview_panel_label");
    const childBody = childPanel.querySelector(".bp_inline_preview_panel_body");
    const childFooter = childPanel.querySelector(".bp_inline_preview_panel_footer");
    const childClose = childPanel.querySelector(".bp_inline_preview_panel_close");
    if (
      !(title instanceof Element) || !(headerLabel instanceof Element) ||
      !(body instanceof Element) || !(footer instanceof Element) || !(close instanceof Element) ||
      !(childTitle instanceof Element) || !(childHeaderLabel instanceof Element) ||
      !(childBody instanceof Element) || !(childFooter instanceof Element) ||
      !(childClose instanceof Element)
    ) {
      return;
    }

    function makeBehavior(mode, placement) {
      return previewUtils.readPanelBehavior(null, { mode: mode, placement: placement });
    }

    let behavior = makeBehavior("hover", "anchored");
    let activeTrigger = null;
    let activeHost = null;
    let activePreviewKey = "";
    let hideTimer = null;
    let updatingPanel = false;
    let ignoreNextPanelExit = false;
    let showRequestToken = 0;
    let childActiveTrigger = null;
    let childPreviewKey = "";
    let childHideTimer = null;
    let childShowRequestToken = 0;
    const childBehavior = makeBehavior("hover", "anchored");

    function clearPanelSizeLock() {
      panel.style.width = "";
      panel.style.minHeight = "";
    }

    function lockPanelSizeToCurrentRect() {
      const rect = panel.getBoundingClientRect();
      if (!(rect.width > 0) || !(rect.height > 0)) return;
      panel.style.width = rect.width + "px";
      panel.style.minHeight = rect.height + "px";
    }

    function cancelHide() {
      if (hideTimer !== null) {
        clearTimeout(hideTimer);
        hideTimer = null;
      }
    }

    function cancelChildHide() {
      if (childHideTimer !== null) {
        clearTimeout(childHideTimer);
        childHideTimer = null;
      }
    }

    function setPanelFooter(footerNode, trigger) {
      if (!(footerNode instanceof Element)) return;
      const footerHtml =
        trigger instanceof Element
          ? (trigger.getAttribute("data-bp-preview-footer-html") || "").trim()
          : "";
      if (footerHtml.length > 0) {
        previewUtils.renderHtmlInto(footerNode, footerHtml);
        footerNode.hidden = false;
      } else {
        footerNode.innerHTML = "";
        footerNode.hidden = true;
      }
    }

    function readInlinePreviewHost(trigger) {
      if (!(trigger instanceof Element)) return null;
      const host = trigger.closest(".bp_relation_panel, .bp_graph_preview, .bp_group_hover_preview");
      if (!(host instanceof Element)) return null;
      if (panel.contains(host)) return null;
      let kind = "generic";
      if (host.matches(".bp_relation_panel")) {
        kind = "relation";
      } else if (host.matches(".bp_graph_preview")) {
        kind = "graph";
      } else if (host.matches(".bp_group_hover_preview")) {
        kind = "graph-group";
      }
      return {
        element: host,
        kind: kind,
        behavior: makeBehavior("hover", "anchored")
      };
    }

    function positionDockedPanel(hostInfo) {
      if (!hostInfo || !(hostInfo.element instanceof Element)) return;
      const margin = 12;
      const gap = 12;
      const hostRect = hostInfo.element.getBoundingClientRect();
      const panelRect = panel.getBoundingClientRect();
      const panelWidth = panelRect.width || Math.min(520, window.innerWidth - margin * 2);
      const panelHeight = panelRect.height || Math.min(420, window.innerHeight - margin * 2);
      let left = hostRect.right + gap;
      if (left + panelWidth > window.innerWidth - margin) {
        left = hostRect.left - panelWidth - gap;
      }
      left = Math.max(margin, Math.min(left, window.innerWidth - panelWidth - margin));
      let top = hostRect.top;
      if (top + panelHeight > window.innerHeight - margin) {
        top = window.innerHeight - panelHeight - margin;
      }
      top = Math.max(margin, top);
      panel.style.left = left + "px";
      panel.style.top = top + "px";
    }

    function applyBehavior(nextBehavior, hostInfo) {
      behavior = nextBehavior || makeBehavior("hover", "anchored");
      activeHost = hostInfo || null;
      panel.setAttribute("data-bp-preview-mode", behavior.mode);
      panel.setAttribute("data-bp-preview-placement", behavior.placement);
      if (activeHost && activeHost.kind) {
        panel.setAttribute("data-bp-inline-host", activeHost.kind);
      } else {
        panel.removeAttribute("data-bp-inline-host");
      }
      previewUtils.configureCloseButton(close, hidePanel, behavior);
    }

    function bindInlinePreviewTriggers(root) {
      if (!(root instanceof Element || root instanceof Document)) return;
      root.querySelectorAll(triggerSelector).forEach(function (trigger) {
        if (!(trigger instanceof Element)) return;
        if (trigger.getAttribute("data-bp-inline-bound") === "1") return;
        trigger.setAttribute("data-bp-inline-bound", "1");
        const triggerKey = (trigger.getAttribute("data-bp-preview-id") || "").trim();
        const triggerInsidePanel = panel.contains(trigger) || childPanel.contains(trigger);
        trigger.addEventListener("mouseenter", function () {
          if (triggerInsidePanel) {
            cancelHide();
            cancelChildHide();
            showChildFromTrigger(trigger);
          } else {
            cancelHide();
            showFromTrigger(trigger);
          }
        });
        trigger.addEventListener("focusin", function () {
          if (triggerInsidePanel) {
            cancelHide();
            cancelChildHide();
            showChildFromTrigger(trigger);
          } else {
            cancelHide();
            showFromTrigger(trigger);
          }
        });
        if (triggerInsidePanel) {
          trigger.addEventListener("mouseleave", function (ev) {
            if (childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
            if (previewUtils.shouldKeepOpen(ev.relatedTarget, trigger, childPanel)) return;
            scheduleChildHide();
          });
          trigger.addEventListener("focusout", function (ev) {
            if (childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
            if (previewUtils.shouldKeepOpen(ev.relatedTarget, trigger, childPanel)) return;
            scheduleChildHide();
          });
          return;
        }
        trigger.addEventListener("mouseleave", function (ev) {
          if (!behavior.isHover) return;
          if (!trigger.isConnected) return;
          if (triggerKey && activePreviewKey && triggerKey !== activePreviewKey) return;
          if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
          if (panel.matches(":hover") || panel.matches(":focus-within")) return;
          if (previewUtils.shouldKeepOpen(ev.relatedTarget, trigger, panel)) return;
          previewDebug("inline.trigger.mouseleave", {
            triggerKey: triggerKey,
            activePreviewKey: activePreviewKey,
            trigger: previewDebugLabel(trigger),
            relatedTarget: previewDebugLabel(ev.relatedTarget),
            panelHover: panel.matches(":hover"),
            panelFocus: panel.matches(":focus-within"),
            updatingPanel: updatingPanel
          });
          scheduleHide();
        });
        trigger.addEventListener("focusout", function (ev) {
          if (!behavior.isHover) return;
          if (!trigger.isConnected) return;
          if (triggerKey && activePreviewKey && triggerKey !== activePreviewKey) return;
          if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
          if (panel.matches(":hover") || panel.matches(":focus-within")) return;
          if (previewUtils.shouldKeepOpen(ev.relatedTarget, trigger, panel)) return;
          previewDebug("inline.trigger.focusout", {
            triggerKey: triggerKey,
            activePreviewKey: activePreviewKey,
            trigger: previewDebugLabel(trigger),
            relatedTarget: previewDebugLabel(ev.relatedTarget),
            panelHover: panel.matches(":hover"),
            panelFocus: panel.matches(":focus-within"),
            updatingPanel: updatingPanel
          });
          scheduleHide();
        });
      });
    }

    function refresh(root) {
      const scope = root instanceof Element || root instanceof Document ? root : document;
      bindInlinePreviewTriggers(scope);
    }

    function hidePanel() {
      cancelHide();
      showRequestToken += 1;
      hideChildPanel();
      previewDebug("inline.hide", {
        activePreviewKey: activePreviewKey,
        activeTrigger: previewDebugLabel(activeTrigger),
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within"),
        updatingPanel: updatingPanel
      });
      clearPanelSizeLock();
      previewUtils.hidePanelContent(panel, title, body);
      previewUtils.setPreviewHeaderLink(headerLabel, null);
      setPanelFooter(footer, null);
      activeTrigger = null;
      activeHost = null;
      activePreviewKey = "";
      applyBehavior(makeBehavior("hover", "anchored"), null);
    }

    function hideChildPanel() {
      cancelChildHide();
      childShowRequestToken += 1;
      previewUtils.hidePanelContent(childPanel, childTitle, childBody);
      previewUtils.setPreviewHeaderLink(childHeaderLabel, null);
      setPanelFooter(childFooter, null);
      childActiveTrigger = null;
      childPreviewKey = "";
    }

    function scheduleHide() {
      cancelHide();
      if (!behavior.isHover) {
        hidePanel();
        return;
      }
      hideTimer = window.setTimeout(function () {
        hideTimer = null;
        previewDebug("inline.scheduleHide.fire", {
          activePreviewKey: activePreviewKey,
          activeTrigger: previewDebugLabel(activeTrigger),
          panelHover: panel.matches(":hover"),
          panelFocus: panel.matches(":focus-within"),
          updatingPanel: updatingPanel
        });
        hidePanel();
      }, 180);
    }

    function scheduleChildHide() {
      cancelChildHide();
      childHideTimer = window.setTimeout(function () {
        childHideTimer = null;
        hideChildPanel();
      }, 180);
    }

    async function resolvePreviewHtml(key, trigger) {
      const previewLookupKey =
        trigger instanceof Element
          ? (trigger.getAttribute("data-bp-preview-key") || "").trim()
          : "";
      if (previewLookupKey) {
        const result = await previewUtils.resolvePreview(previewLookupKey);
        if (result && result.ok && result.html) return result.html;
      }
      return fallbackInlinePreviewHtml(trigger, key, escapeHtml);
    }

    async function showChildFromTrigger(trigger) {
      if (!(trigger instanceof Element)) return;
      const key = (trigger.getAttribute("data-bp-preview-id") || "").trim();
      if (!key) {
        hideChildPanel();
        return;
      }
      const requestToken = ++childShowRequestToken;
      const html = await resolvePreviewHtml(key, trigger);
      if (requestToken !== childShowRequestToken) return;
      if (!html) {
        hideChildPanel();
        return;
      }
      const heading = (trigger.getAttribute("data-bp-preview-title") || key).trim() || key;
      cancelHide();
      cancelChildHide();
      childPreviewKey = key;
      childActiveTrigger = trigger;
      previewUtils.setPreviewHeaderLink(childHeaderLabel, trigger);
      setPanelFooter(childFooter, trigger);
      previewUtils.showPanelContent(childPanel, childTitle, childBody, heading, html, childBehavior, trigger, 12, 10);
    }

    async function showFromTrigger(trigger) {
      if (!(trigger instanceof Element)) return;
      if (panel.contains(trigger) || childPanel.contains(trigger)) {
        showChildFromTrigger(trigger);
        return;
      }
      const key = (trigger.getAttribute("data-bp-preview-id") || "").trim();
      if (!key) {
        hidePanel();
        return;
      }
      const requestToken = ++showRequestToken;
      const html = await resolvePreviewHtml(key, trigger);
      if (requestToken !== showRequestToken) return;
      if (!html) {
        hidePanel();
        return;
      }
      const heading = (trigger.getAttribute("data-bp-preview-title") || key).trim() || key;
      activePreviewKey = key;
      const inPanel = panel.contains(trigger);
      const hostInfo = inPanel ? activeHost : readInlinePreviewHost(trigger);
      applyBehavior(hostInfo ? hostInfo.behavior : makeBehavior("hover", "anchored"), hostInfo);
      updatingPanel = inPanel;
      previewDebug("inline.show", {
        key: key,
        inPanel: inPanel,
        trigger: previewDebugLabel(trigger),
        host: activeHost ? activeHost.kind : "",
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within")
      });
      if (inPanel) {
        lockPanelSizeToCurrentRect();
        activeTrigger = null;
        ignoreNextPanelExit = true;
        title.textContent = heading;
        previewUtils.setPreviewHeaderLink(headerLabel, trigger);
        setPanelFooter(footer, trigger);
        previewUtils.renderHtmlInto(body, html);
        panel.hidden = false;
        if (behavior.isDocked && activeHost) {
          positionDockedPanel(activeHost);
        }
        window.setTimeout(function () {
          updatingPanel = false;
        }, 180);
      } else {
        hideChildPanel();
        clearPanelSizeLock();
        activeTrigger = trigger;
        previewUtils.setPreviewHeaderLink(headerLabel, trigger);
        setPanelFooter(footer, trigger);
        previewUtils.showPanelContent(panel, title, body, heading, html, behavior, trigger, 12, 10);
        if (behavior.isDocked && activeHost) {
          positionDockedPanel(activeHost);
        }
      }
    }
    applyBehavior(behavior, null);
    previewUtils.configureCloseButton(childClose, hideChildPanel, childBehavior);
    panel.addEventListener("mouseenter", function () {
      cancelHide();
    });
    panel.addEventListener("focusin", function () {
      cancelHide();
    });
    panel.addEventListener("mouseleave", function (ev) {
      if (!behavior.isHover) return;
      if (updatingPanel) return;
      if (ignoreNextPanelExit) {
        ignoreNextPanelExit = false;
        previewDebug("inline.panel.mouseleave.ignored", {
          activePreviewKey: activePreviewKey,
          relatedTarget: previewDebugLabel(ev.relatedTarget),
          panelHover: panel.matches(":hover"),
          panelFocus: panel.matches(":focus-within")
        });
        return;
      }
      if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
      if (previewUtils.pointerWithinPanel(panel, ev)) return;
      if (panel.matches(":hover") || panel.matches(":focus-within")) return;
      if (previewUtils.shouldKeepOpen(ev.relatedTarget, activeTrigger, panel)) return;
      previewDebug("inline.panel.mouseleave", {
        activePreviewKey: activePreviewKey,
        activeTrigger: previewDebugLabel(activeTrigger),
        relatedTarget: previewDebugLabel(ev.relatedTarget),
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within"),
        updatingPanel: updatingPanel
      });
      scheduleHide();
    });
    panel.addEventListener("focusout", function (ev) {
      if (!behavior.isHover) return;
      if (updatingPanel) return;
      if (ignoreNextPanelExit) {
        ignoreNextPanelExit = false;
        previewDebug("inline.panel.focusout.ignored", {
          activePreviewKey: activePreviewKey,
          relatedTarget: previewDebugLabel(ev.relatedTarget),
          panelHover: panel.matches(":hover"),
          panelFocus: panel.matches(":focus-within")
        });
        return;
      }
      if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
      if (panel.matches(":hover") || panel.matches(":focus-within")) return;
      if (previewUtils.shouldKeepOpen(ev.relatedTarget, activeTrigger, panel)) return;
      previewDebug("inline.panel.focusout", {
        activePreviewKey: activePreviewKey,
        activeTrigger: previewDebugLabel(activeTrigger),
        relatedTarget: previewDebugLabel(ev.relatedTarget),
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within"),
        updatingPanel: updatingPanel
      });
      scheduleHide();
    });
    document.addEventListener("keydown", function (ev) {
      if (ev.key === "Escape") {
        hidePanel();
      }
    });
    childPanel.addEventListener("mouseenter", function () {
      cancelHide();
      cancelChildHide();
    });
    childPanel.addEventListener("focusin", function () {
      cancelHide();
      cancelChildHide();
    });
    childPanel.addEventListener("mouseleave", function (ev) {
      if (previewUtils.pointerWithinPanel(childPanel, ev)) return;
      if (previewUtils.shouldKeepOpen(ev.relatedTarget, childActiveTrigger, childPanel)) return;
      scheduleChildHide();
    });
    childPanel.addEventListener("focusout", function (ev) {
      if (previewUtils.shouldKeepOpen(ev.relatedTarget, childActiveTrigger, childPanel)) return;
      scheduleChildHide();
    });
    window.addEventListener("resize", function () {
      if (behavior.isAnchored && activeTrigger && !panel.hidden) {
        previewUtils.positionAnchoredPanel(panel, activeTrigger, 12, 10);
      } else if (behavior.isDocked && activeHost && !panel.hidden) {
        positionDockedPanel(activeHost);
      }
      if (childActiveTrigger && !childPanel.hidden) {
        previewUtils.positionAnchoredPanel(childPanel, childActiveTrigger, 12, 10);
      }
    });
    window.addEventListener("scroll", function () {
      if (behavior.isAnchored && activeTrigger && !panel.hidden) {
        previewUtils.positionAnchoredPanel(panel, activeTrigger, 12, 10);
      } else if (behavior.isDocked && activeHost && !panel.hidden) {
        positionDockedPanel(activeHost);
      }
      if (childActiveTrigger && !childPanel.hidden) {
        previewUtils.positionAnchoredPanel(childPanel, childActiveTrigger, 12, 10);
      }
    }, true);

    previewUtils.registerPreviewHydrator("inline", refresh);

    refresh(document);
  }

  onBlueprintRenderReady(function () {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", bindInlinePreview);
    } else {
      bindInlinePreview();
    }
  });
})();
