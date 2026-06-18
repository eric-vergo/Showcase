(function () {
  function blueprintRender() {
    return window.VersoBlueprint.render;
  }

  function escapeHtml(text) {
    return blueprintRender().escapeHtml(text);
  }

  function previewMessageHtml(kind, title, detail) {
    const safeKind = String(kind || "info").trim() || "info";
    let html =
      '<div class="bp_relation_preview_message" data-bp-preview-message="' +
      escapeHtml(safeKind) +
      '">';
    html +=
      '<div class="bp_relation_preview_message_title">' +
      escapeHtml(title || "Preview unavailable") +
      "</div>";
    if (detail) {
      html +=
        '<div class="bp_relation_preview_message_detail">' +
        escapeHtml(detail) +
        "</div>";
    }
    html += "</div>";
    return html;
  }

  function loadingPreviewHtml() {
    return previewMessageHtml(
      "loading",
      "Loading preview",
      "Reading this preview from the Blueprint HTML cache."
    );
  }

  function readCacheStatus(previewUtils) {
    return previewUtils.readHtmlCacheStatus();
  }

  function previewUnavailableHtml(previewUtils, previewKey, fallbackDetail) {
    const status = readCacheStatus(previewUtils);
    if (!previewKey) {
      return previewMessageHtml(
        "error",
        "Preview unavailable",
        "This entry did not provide a preview cache key."
      );
    }
    if (status && status.state === "error") {
      return previewMessageHtml(
        "error",
        "Preview HTML cache unavailable",
        "Rebuild the site or refresh after the current build finishes."
      );
    }
    if (status && status.state === "ready") {
      return previewMessageHtml(
        "error",
        "Preview entry not found",
        "The Blueprint HTML cache loaded, but it does not contain this entry yet. Rebuild the Blueprint output to resync generated data."
      );
    }
    return previewMessageHtml(
      "error",
      "Preview unavailable",
      fallbackDetail || "The preview cache content could not be loaded."
    );
  }

  function setRelationBodyHtml(previewUtils, body, html) {
    previewUtils.renderHtmlInto(body, html, { hydrate: false, renderMath: false });
  }

  function bindRelationPanel(panel) {
    if (!(panel instanceof Element)) return;
    if (panel.getAttribute("data-bp-bound") === "1") return;
    panel.setAttribute("data-bp-bound", "1");

    const previewUtils = blueprintRender();
    const wrap = panel.closest(".bp_relation_wrap");
    const chip = wrap instanceof Element ? wrap.querySelector(".bp_relation_chip") : null;
    const title = panel.querySelector(".bp_relation_preview_title");
    const headerLabel = panel.querySelector(".bp_relation_preview_header_label");
    const body = panel.querySelector(".bp_relation_preview_body");
    if (!(title instanceof Element) || !(headerLabel instanceof Element) || !(body instanceof Element)) return;

    const defaultTitle = (title.textContent || "").trim() || "Relation preview";
    const items = Array.from(panel.querySelectorAll(".bp_relation_item[data-bp-relation-preview-id]"));
    let closeTimer = null;
    let activateRequestToken = 0;

    function setExpanded(expanded) {
      if (chip instanceof Element) {
        chip.setAttribute("aria-expanded", expanded ? "true" : "false");
      }
    }

    function cancelClose() {
      if (closeTimer !== null) {
        clearTimeout(closeTimer);
        closeTimer = null;
      }
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

    function scheduleClose() {
      cancelClose();
      closeTimer = window.setTimeout(function () {
        closeTimer = null;
        if (wrap instanceof Element) {
          wrap.classList.remove("bp_relation_wrap_open");
        }
        setExpanded(false);
      }, 180);
    }

    async function activate(item, options) {
      if (!(item instanceof Element)) return;
      const opts = options && typeof options === "object" ? options : {};
      const previewKey = (item.getAttribute("data-bp-relation-preview-key") || "").trim();
      const requestToken = ++activateRequestToken;
      selectItem(item);
      setRelationBodyHtml(previewUtils, body, loadingPreviewHtml());
      if (opts.openWrap !== false) {
        openWrap({ loadPreview: false });
      }
      if (!previewKey) {
        setRelationBodyHtml(previewUtils, body, previewUnavailableHtml(previewUtils, previewKey, ""));
        return;
      }
      try {
        const result = await previewUtils.renderPreviewInto(body, previewKey, { diagnostics: false });
        if (requestToken !== activateRequestToken) return;
        if (!result || !result.ok) {
          setRelationBodyHtml(previewUtils, body, previewUnavailableHtml(previewUtils, previewKey, ""));
          return;
        }
      } catch (_err) {
        if (requestToken !== activateRequestToken) return;
        setRelationBodyHtml(previewUtils, body, previewUnavailableHtml(
          previewUtils,
          previewKey,
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
      const previewAwareClose = function (ev) {
        if (previewUtils.shouldKeepOpen(ev.relatedTarget, wrap, panel)) return;
        scheduleClose();
      };
      chip.addEventListener("mouseenter", openWrap);
      chip.addEventListener("focusin", openWrap);
      chip.addEventListener("mouseleave", previewAwareClose);
      chip.addEventListener("focusout", previewAwareClose);
      panel.addEventListener("mouseenter", openWrap);
      panel.addEventListener("focusin", openWrap);
      panel.addEventListener("mouseleave", previewAwareClose);
      panel.addEventListener("focusout", previewAwareClose);
      chip.addEventListener("click", function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        cancelClose();
        wrap.classList.toggle("bp_relation_wrap_open");
        const expanded = wrap.classList.contains("bp_relation_wrap_open");
        setExpanded(expanded);
        if (expanded) {
          loadActivePreview();
        }
      });
      panel.addEventListener("click", function (ev) {
        ev.stopPropagation();
      });
      document.addEventListener("click", function (ev) {
        if (!(ev.target instanceof Element)) {
          closeWrap();
          return;
        }
        if (!wrap.contains(ev.target)) {
          closeWrap();
        }
      });
      document.addEventListener("keydown", function (ev) {
        if (ev.key === "Escape") {
          closeWrap();
        }
      });
    }
  }

  function bindAllRelationPanels(root) {
    if (!(root instanceof Element || root instanceof Document)) return;
    root.querySelectorAll(".bp_relation_panel").forEach(bindRelationPanel);
  }

  window.VersoBlueprint.onRenderReady(function (previewUtils) {
    previewUtils.registerPreviewHydrator("relationPanel", bindAllRelationPanels);
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () {
        bindAllRelationPanels(document);
      });
    } else {
      bindAllRelationPanels(document);
    }
  });
})();
