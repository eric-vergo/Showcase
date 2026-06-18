(function () {
  window.VersoBlueprint.onRenderReady(function (previewUtils) {
    previewUtils.bindTemplatePreviewRoots({
      rootSelector: ".bp_summary",
      rootBoundAttr: "data-bp-summary-preview-bound",
      panelSelector: ".bp_summary_preview_panel",
      allowHtmlCache: true,
      templateSelector: "template.bp_summary_preview_tpl[data-bp-preview-label]",
      triggerSelector: ".bp_summary_preview_wrap_active[data-bp-preview-label]",
      titleSelector: ".bp_summary_preview_panel_title",
      bodySelector: ".bp_summary_preview_panel_body",
      closeSelector: ".bp_summary_preview_panel_close",
      defaults: { mode: "hover", placement: "anchored" },
      readTitle: function (_wrap, label) { return label; }
    });
  });
})();
