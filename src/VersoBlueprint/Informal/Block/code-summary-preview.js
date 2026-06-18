(function () {
  function blueprintRender() {
    return window.VersoBlueprint && window.VersoBlueprint.render;
  }

  function bindCodeSummaryPreview(root) {
    if (!(root instanceof Element)) return;
    if (root.getAttribute("data-bp-code-summary-preview-bound") === "1") return;
    root.setAttribute("data-bp-code-summary-preview-bound", "1");

    const previewUtils = blueprintRender();
    const panel = root.querySelector(".bp_code_summary_preview_panel");
    if (!panel || !previewUtils || typeof previewUtils.bindTemplatePreview !== "function") return;
    previewUtils.bindTemplatePreview({
      root: root,
      previewRoot: root,
      triggerRoot: root,
      panel: panel,
      templateSelector: "template.bp_code_summary_preview_tpl[data-bp-preview-id]",
      triggerSelector: ".bp_code_summary_preview_wrap_active[data-bp-preview-id]",
      keyAttr: "data-bp-preview-id",
      titleAttr: "data-bp-preview-title",
      titleSelector: ".bp_code_summary_preview_title",
      bodySelector: ".bp_code_summary_preview_body",
      closeSelector: ".bp_code_summary_preview_close",
      triggerBoundAttr: "data-bp-code-summary-trigger-bound",
      defaults: { mode: "hover", placement: "anchored" }
    });
  }

  function init() {
    document.querySelectorAll(".bp_code_summary_preview_root").forEach(bindCodeSummaryPreview);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, { once: true });
  } else {
    init();
  }
})();
