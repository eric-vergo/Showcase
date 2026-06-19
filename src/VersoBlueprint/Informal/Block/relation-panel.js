(function () {
  function previewExceptionHtml(previewUtils, fallbackDetail) {
    return previewUtils.previewMessageHtml({
      rootClass: "bp_relation_preview_message",
      titleClass: "bp_relation_preview_message_title",
      detailClass: "bp_relation_preview_message_detail",
      kind: "error",
      title: "Preview unavailable",
      detail: fallbackDetail || "The preview cache content could not be loaded."
    });
  }

  function setRelationBodyHtml(previewUtils, body, html) {
    previewUtils.renderHtmlInto(body, html, { hydrate: false, renderMath: false });
  }

  function bindRelationPanel(previewUtils, panel) {
    if (!(panel instanceof Element)) return;
    if (panel.getAttribute("data-bp-bound") === "1") return;
    panel.setAttribute("data-bp-bound", "1");

    const wrap = panel.closest(".bp_relation_wrap");
    const chip = wrap instanceof Element ? wrap.querySelector(".bp_relation_chip") : null;
    const title = panel.querySelector(".bp_relation_preview_title");
    const headerLabel = panel.querySelector(".bp_relation_preview_header_label");
    const body = panel.querySelector(".bp_relation_preview_body");
    if (!(title instanceof Element) || !(headerLabel instanceof Element) || !(body instanceof Element)) return;

    const defaultTitle = (title.textContent || "").trim() || "Relation preview";
    const initialLoadingHtml = (body.innerHTML || "").trim();
    const items = Array.from(panel.querySelectorAll(".bp_relation_item[data-bp-relation-preview-id]"));
    let activateRequestToken = 0;
    let relationLifecycle = null;

    function setExpanded(expanded) {
      if (chip instanceof Element) {
        chip.setAttribute("aria-expanded", expanded ? "true" : "false");
      }
    }

    function cancelClose() {
      if (relationLifecycle) relationLifecycle.cancelHide();
    }

    function activeItem() {
      return items.find(function (item) {
        return item instanceof Element && item.classList.contains("bp_relation_item_active");
      }) || items[0] || null;
    }

    function selectItem(item) {
      if (!(item instanceof Element)) return;
      const itemTitle = (item.getAttribute("data-bp-relation-preview-title") || "").trim() || defaultTitle;
      items.forEach(function (other) {
        if (other instanceof Element) {
          other.classList.toggle("bp_relation_item_active", other === item);
        }
      });
      title.textContent = itemTitle;
      previewUtils.setPreviewHeaderLink(headerLabel, item);
      setRelationBodyHtml(previewUtils, body, "");
    }

    function loadActivePreview() {
      const item = activeItem();
      if (item instanceof Element) {
        activate(item, { openWrap: false });
      }
    }

    function openWrap(options) {
      const opts = options && typeof options === "object" ? options : {};
      cancelClose();
      if (wrap instanceof Element) {
        wrap.classList.add("bp_relation_wrap_open");
      }
      setExpanded(true);
      if (opts.loadPreview !== false) {
        loadActivePreview();
      }
    }

    function closeWrap() {
      cancelClose();
      if (wrap instanceof Element) {
        wrap.classList.remove("bp_relation_wrap_open");
      }
      setExpanded(false);
    }

    function wrapIsOpen() {
      return wrap instanceof Element && wrap.classList.contains("bp_relation_wrap_open");
    }

    async function activate(item, options) {
      if (!(item instanceof Element)) return;
      const opts = options && typeof options === "object" ? options : {};
      const previewKey = (item.getAttribute("data-bp-relation-preview-key") || "").trim();
      const requestToken = ++activateRequestToken;
      selectItem(item);
      setRelationBodyHtml(previewUtils, body, initialLoadingHtml);
      if (opts.openWrap !== false) {
        openWrap({ loadPreview: false });
      }
      try {
        const result = await previewUtils.resolvePreview(previewKey);
        if (requestToken !== activateRequestToken) return;
        if (!result || !result.ok) {
          const diagnosticHtml = result && typeof result.diagnosticHtml === "string"
            ? result.diagnosticHtml
            : "";
          setRelationBodyHtml(
            previewUtils,
            body,
            diagnosticHtml || previewExceptionHtml(previewUtils, "The preview cache content could not be loaded.")
          );
          return;
        }
        previewUtils.renderHtmlInto(body, result.html);
      } catch (_err) {
        if (requestToken !== activateRequestToken) return;
        setRelationBodyHtml(previewUtils, body, previewExceptionHtml(
          previewUtils,
          "The preview cache content could not be loaded. Refresh the page, or rebuild the site if this persists."
        ));
      }
    }

    items.forEach(function (item) {
      if (!(item instanceof Element)) return;
      item.addEventListener("mouseenter", function () {
        activate(item);
      });
      item.addEventListener("focusin", function () {
        activate(item);
      });
    });
    const initialItem = items.find(function (item) {
      return item instanceof Element && item.classList.contains("bp_relation_item_active");
    }) || items[0];
    if (initialItem instanceof Element) {
      selectItem(initialItem);
    }

    if (wrap instanceof Element && chip instanceof Element) {
      setExpanded(wrap.classList.contains("bp_relation_wrap_open"));
      relationLifecycle = previewUtils.bindPreviewTriggers({
        triggerRoot: wrap,
        triggerSelector: ".bp_relation_chip",
        triggerBoundAttr: "data-bp-relation-chip-bound",
        panel: panel,
        panelBoundAttr: "data-bp-relation-panel-lifetime-bound",
        behavior: previewUtils.readPanelBehavior(null, { mode: "hover", placement: "anchored" }),
        show: function () { openWrap(); },
        hide: closeWrap,
        getActiveTrigger: function () { return chip; },
        shouldKeepOpen: function (_trigger, ev) {
          return previewUtils.shouldKeepOpen(ev && ev.relatedTarget, wrap, panel);
        },
        onPanelEnter: function () { openWrap(); },
        bindWindow: false
      });
      previewUtils.bindDismissHandlers({
        owner: wrap,
        root: wrap,
        trigger: chip,
        panel: panel,
        boundAttr: "data-bp-relation-dismiss-bound",
        isOpen: wrapIsOpen,
        close: closeWrap,
        toggle: function () {
          if (wrapIsOpen()) {
            closeWrap();
          } else {
            openWrap();
          }
        },
        stopPanelClick: true
      });
    }
  }

  function bindAllRelationPanels(previewUtils, root) {
    if (!(root instanceof Element || root instanceof Document)) return;
    root.querySelectorAll(".bp_relation_panel").forEach(function (panel) {
      bindRelationPanel(previewUtils, panel);
    });
  }

  window.VersoBlueprint.onRenderReady(function (previewUtils) {
    previewUtils.registerPreviewHydrator("relationPanel", function (root) {
      bindAllRelationPanels(previewUtils, root);
    });
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () {
        bindAllRelationPanels(previewUtils, document);
      });
    } else {
      bindAllRelationPanels(previewUtils, document);
    }
  });
})();
