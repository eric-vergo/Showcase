(function () {
  const triggerSelector = ".bp_inline_preview_ref[data-bp-preview-id]";

  // Fallback markup is only for explicit fallback attributes on non-cache
  // inline references. Manifest-backed previews should resolve through
  // previewUtils.resolvePreview and should not rely on this path.
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

  function getPanel(previewUtils, id, extraClass) {
    const existing = document.getElementById(id);
    if (existing instanceof Element) return existing;
    return previewUtils.createPreviewPanel({
      id: id,
      rootClass: "bp_inline_preview_panel",
      extraClass: extraClass,
      mode: "hover",
      placement: "anchored",
      headerClass: "bp_inline_preview_panel_header",
      headingClass: "bp_inline_preview_panel_heading bp_preview_header_heading",
      titleClass: "bp_inline_preview_panel_title",
      headerLabelClass: "bp_inline_preview_panel_label bp_preview_header_label",
      closeClass: "bp_inline_preview_panel_close",
      closeLabel: "Close inline preview",
      bodyClass: "bp_inline_preview_panel_body",
      footerClass: "bp_inline_preview_panel_footer"
    });
  }

  function bindInlinePreview(previewUtils) {
    if (!(document.body instanceof Element)) return;
    if (document.body.getAttribute("data-bp-inline-preview-bound") === "1") return;
    document.body.setAttribute("data-bp-inline-preview-bound", "1");

    const escapeHtml = previewUtils.escapeHtml;
    const previewDebug = previewUtils.previewDebug;
    const previewDebugLabel = previewUtils.previewDebugLabel;

    const panel = getPanel(previewUtils, "bp-inline-preview-panel", "");
    const title = panel.querySelector(".bp_inline_preview_panel_title");
    const headerLabel = panel.querySelector(".bp_inline_preview_panel_label");
    const body = panel.querySelector(".bp_inline_preview_panel_body");
    const footer = panel.querySelector(".bp_inline_preview_panel_footer");
    const close = panel.querySelector(".bp_inline_preview_panel_close");
    const childPanel = getPanel(previewUtils, "bp-inline-preview-child-panel", "bp_inline_preview_panel_child");
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
    let updatingPanel = false;
    let ignoreNextPanelExit = false;
    let showRequestToken = 0;
    let childActiveTrigger = null;
    let childShowRequestToken = 0;
    let mainLifecycle = null;
    let childLifecycle = null;
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
      if (mainLifecycle) mainLifecycle.cancelHide();
    }

    function cancelChildHide() {
      if (childLifecycle) childLifecycle.cancelHide();
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
        footerNode.replaceChildren();
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

    function triggerInsideInlinePanel(trigger) {
      return trigger instanceof Element && (panel.contains(trigger) || childPanel.contains(trigger));
    }

    function bindInlinePreviewTriggers(root) {
      if (mainLifecycle) mainLifecycle.refresh(root);
      if (childLifecycle) childLifecycle.refresh(root);
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
    }

    function scheduleHide() {
      if (mainLifecycle) mainLifecycle.scheduleHide();
    }

    function scheduleChildHide() {
      if (childLifecycle) childLifecycle.scheduleHide();
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

    function mainTriggerLeaveHandled(trigger, ev) {
      if (!trigger.isConnected) return true;
      const triggerKey = (trigger.getAttribute("data-bp-preview-id") || "").trim();
      if (triggerKey && activePreviewKey && triggerKey !== activePreviewKey) return true;
      if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return true;
      if (panel.matches(":hover") || panel.matches(":focus-within")) return true;
      previewDebug("inline.trigger.leave", {
        triggerKey: triggerKey,
        activePreviewKey: activePreviewKey,
        trigger: previewDebugLabel(trigger),
        relatedTarget: previewDebugLabel(ev.relatedTarget),
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within"),
        updatingPanel: updatingPanel
      });
      return false;
    }

    function mainPanelLeaveHandled(_panel, ev) {
      if (updatingPanel) return true;
      if (ignoreNextPanelExit) {
        ignoreNextPanelExit = false;
        previewDebug("inline.panel.leave.ignored", {
          activePreviewKey: activePreviewKey,
          relatedTarget: previewDebugLabel(ev.relatedTarget),
          panelHover: panel.matches(":hover"),
          panelFocus: panel.matches(":focus-within")
        });
        return true;
      }
      if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return true;
      if (previewUtils.pointerWithinPanel(panel, ev)) return true;
      if (panel.matches(":hover") || panel.matches(":focus-within")) return true;
      previewDebug("inline.panel.leave", {
        activePreviewKey: activePreviewKey,
        activeTrigger: previewDebugLabel(activeTrigger),
        relatedTarget: previewDebugLabel(ev.relatedTarget),
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within"),
        updatingPanel: updatingPanel
      });
      return false;
    }

    function childTriggerLeaveHandled(_trigger, _ev) {
      return childPanel.matches(":hover") || childPanel.matches(":focus-within");
    }

    function childPanelLeaveHandled(_panel, ev) {
      return previewUtils.pointerWithinPanel(childPanel, ev);
    }

    applyBehavior(behavior, null);
    previewUtils.configureCloseButton(childClose, hideChildPanel, childBehavior);
    mainLifecycle = previewUtils.bindPreviewTriggers({
      triggerRoot: document,
      triggerSelector: triggerSelector,
      triggerBoundAttr: "data-bp-inline-main-bound",
      panel: panel,
      getBehavior: function () { return behavior; },
      filterTrigger: function (trigger) { return !triggerInsideInlinePanel(trigger); },
      show: showFromTrigger,
      hide: hidePanel,
      position: function (anchor) { previewUtils.positionAnchoredPanel(panel, anchor, 12, 10); },
      getActiveTrigger: function () { return activeTrigger; },
      onLeave: mainTriggerLeaveHandled,
      onPanelLeave: mainPanelLeaveHandled,
      bindWindow: false
    });
    childLifecycle = previewUtils.bindPreviewTriggers({
      triggerRoot: document,
      triggerSelector: triggerSelector,
      triggerBoundAttr: "data-bp-inline-child-bound",
      panel: childPanel,
      behavior: childBehavior,
      filterTrigger: triggerInsideInlinePanel,
      show: showChildFromTrigger,
      hide: hideChildPanel,
      position: function (anchor) { previewUtils.positionAnchoredPanel(childPanel, anchor, 12, 10); },
      getActiveTrigger: function () { return childActiveTrigger; },
      onLeave: childTriggerLeaveHandled,
      onPanelLeave: childPanelLeaveHandled,
      bindEscape: false,
      bindWindow: false
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

  window.VersoBlueprint.onRenderReady(function (previewUtils) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () {
        bindInlinePreview(previewUtils);
      });
    } else {
      bindInlinePreview(previewUtils);
    }
  });
})();
