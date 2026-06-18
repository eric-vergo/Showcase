(function () {
  window.VersoBlueprint.render.bindTemplatePreviewRoots({
    rootSelector: ".bp_code_summary_preview_root",
    rootBoundAttr: "data-bp-code-summary-preview-bound",
    panelSelector: ".bp_code_summary_preview_panel",
    templateSelector: "template.bp_code_summary_preview_tpl[data-bp-preview-id]",
    triggerSelector: ".bp_code_summary_preview_wrap_active[data-bp-preview-id]",
    keyAttr: "data-bp-preview-id",
    titleAttr: "data-bp-preview-title",
    titleSelector: ".bp_code_summary_preview_title",
    bodySelector: ".bp_code_summary_preview_body",
    closeSelector: ".bp_code_summary_preview_close",
    triggerBoundAttr: "data-bp-code-summary-trigger-bound",
    defaults: { mode: "hover", placement: "anchored" },
    once: true
  });
})();
