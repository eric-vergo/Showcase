(function () {
  function blueprintRender() {
    return window.VersoBlueprint && window.VersoBlueprint.render;
  }

  function bindSummaryPreview(root) {
    if (!(root instanceof Element)) return;
    if (root.getAttribute("data-bp-summary-preview-bound") === "1") return;
    root.setAttribute("data-bp-summary-preview-bound", "1");

    const previewUtils = blueprintRender();
    const panel = root.querySelector(".bp_summary_preview_panel");
    if (!panel || !previewUtils || typeof previewUtils.bindTemplatePreview !== "function") return;
    previewUtils.bindTemplatePreview({
      root: root,
      previewRoot: root,
      triggerRoot: root,
      panel: panel,
      allowHtmlCache: true,
      templateSelector: "template.bp_summary_preview_tpl[data-bp-preview-label]",
      triggerSelector: ".bp_summary_preview_wrap_active[data-bp-preview-label]",
      titleSelector: ".bp_summary_preview_panel_title",
      bodySelector: ".bp_summary_preview_panel_body",
      closeSelector: ".bp_summary_preview_panel_close",
      defaults: { mode: "hover", placement: "anchored" },
      readTitle: function (_wrap, label) { return label; }
    });
  }

  function init() {
    document.querySelectorAll(".bp_summary").forEach(bindSummaryPreview);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
