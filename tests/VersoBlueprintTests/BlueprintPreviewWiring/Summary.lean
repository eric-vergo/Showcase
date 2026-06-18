/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintPreviewWiring.Shared

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.Summary

open Informal
open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls previewWiringDoc
    let summaryJs? := findExtraJsContaining? st "rootSelector: \".bp_summary\""
    let previewRuntimeJs? := findExtraJsContaining? st "const renderApi = {"
    let inlineJs? := findExtraJsContaining? st "function bindInlinePreview()"
    let mathJs? := findExtraJsContaining? st "window.bpTexPreludeTable"
    pure (
      !hasSubstr out "class=\"bp_summary_preview_store\"" &&
      !hasSubstr out "class=\"bp_summary_preview_tpl\"" &&
      !hasSubstr out "class=\"bp_label_preview_tpl\"" &&
      hasSubstr out "bp_summary_preview_panel" &&
      hasSubstr out "data-bp-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-preview-placement=\"anchored\"" &&
      hasSubstr out "bp_summary_preview_wrap_active" &&
      hasSubstr out "data-bp-preview-key=\"«def:preview.base»--statement\"" &&
      hasExtraCss st ".bp_inline_preview_panel[hidden]" &&
      hasExtraCss st ".bp_preview_header_label" &&
      hasExtraCss st ".bp_inline_preview_panel_footer" &&
      !hasSubstr out "data-bp-tex-prelude=\"" &&
      !hasSubstr out "bp_preview_tex_prelude" &&
      !hasSubstr out "verso-tex-prelude" &&
      match summaryJs?, previewRuntimeJs?, inlineJs?, mathJs? with
      | some summaryJs, some previewRuntimeJs, some inlineJs, some mathJs =>
        hasSubstr mathJs "\\\\newcommand{\\\\previewmacro}{\\\\mathsf{Preview}}" &&
        hasSubstr summaryJs "namespace.onRenderReady = function (fn) {" &&
        hasSubstr summaryJs "window.VersoBlueprint.onRenderReady(function (previewUtils) {" &&
        hasSubstr summaryJs "previewUtils.bindTemplatePreviewRoots({" &&
        hasSubstr summaryJs "rootBoundAttr: \"data-bp-summary-preview-bound\"" &&
        hasSubstr summaryJs "panelSelector: \".bp_summary_preview_panel\"" &&
        hasSubstr summaryJs "allowHtmlCache: true" &&
        hasSubstr summaryJs "templateSelector: \"template.bp_summary_preview_tpl[data-bp-preview-label]\"" &&
        hasSubstr summaryJs "triggerSelector: \".bp_summary_preview_wrap_active[data-bp-preview-label]\"" &&
        hasSubstr summaryJs "readTitle: function (_wrap, label) { return label; }" &&
        hasSubstr previewRuntimeJs "function bindTemplatePreviewRoots(options)" &&
        hasSubstr previewRuntimeJs "bindTemplatePreviewRoots: bindTemplatePreviewRoots" &&
        hasSubstr previewRuntimeJs "function onRenderReady(fn)" &&
        hasSubstr previewRuntimeJs "namespace.onRenderReady = onRenderReady" &&
        hasSubstr previewRuntimeJs "queuedRenderReadyCallbacks.forEach(function (fn) {" &&
        hasSubstr previewRuntimeJs "function positionAnchoredPanel(panel, anchor, margin, offset)" &&
        hasSubstr previewRuntimeJs "function shouldKeepOpen(nextTarget, trigger, panel)" &&
        hasSubstr previewRuntimeJs "function readPanelBehavior(panel, defaults)" &&
        hasSubstr previewRuntimeJs "function configureCloseButton(closeButton, onClose, behavior)" &&
        !hasSubstr previewRuntimeJs "function readBlueprintHtmlCacheEntryByLabel(label)" &&
        hasSubstr previewRuntimeJs "function statementPreviewKey(label)" &&
        hasSubstr previewRuntimeJs "function loadBlueprintHtmlCacheEntry(previewKey)" &&
        hasSubstr previewRuntimeJs "Blueprint HTML cache must be an object with an entries array" &&
        hasSubstr previewRuntimeJs "Blueprint HTML cache contains duplicate key " &&
        hasSubstr previewRuntimeJs "function runPreviewHydrators(root)" &&
        hasSubstr previewRuntimeJs "readHtml: readHtml" &&
        !hasSubstr previewRuntimeJs "readPreviewTemplate:" &&
        !hasSubstr previewRuntimeJs "hydratePreviewSubtree:" &&
        !hasSubstr previewRuntimeJs "renderMath:" &&
        hasSubstr previewRuntimeJs "escapeHtml: escapeHtml" &&
        hasSubstr previewRuntimeJs "function setPreviewHeaderLink(labelNode, sourceNode)" &&
        hasSubstr previewRuntimeJs "data-bp-preview-header-label" &&
        hasSubstr previewRuntimeJs "window.setTimeout(function () {" &&
        hasSubstr inlineJs "namespace.onRenderReady = function (fn) {" &&
        hasSubstr inlineJs "window.VersoBlueprint.onRenderReady(function () {" &&
        hasSubstr inlineJs "bp-inline-preview-child-panel" &&
        hasSubstr inlineJs "function cancelChildHide()" &&
        hasSubstr inlineJs "function showChildFromTrigger(trigger)" &&
        hasSubstr inlineJs "previewUtils.setPreviewHeaderLink(headerLabel, trigger)" &&
        hasSubstr inlineJs "function setPanelFooter(footerNode, trigger)" &&
        hasSubstr inlineJs "data-bp-preview-footer-html" &&
        hasSubstr inlineJs "triggerInsidePanel = panel.contains(trigger) || childPanel.contains(trigger)" &&
        hasSubstr inlineJs "behavior: makeBehavior(\"hover\", \"anchored\")" &&
        !hasSubstr inlineJs "typeof previewUtils.readPanelBehavior" &&
        !hasSubstr inlineJs "typeof previewUtils.previewDebug" &&
        !hasSubstr inlineJs "function onBlueprintRenderReady(fn)" &&
        !hasSubstr inlineJs ".replaceAll(\"&\", \"&amp;\")" &&
        !hasSubstr inlineJs "ensureInlinePreviewStore" &&
        !hasSubstr inlineJs "template.bp_inline_preview_tpl"
      | _, _, _, _ => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls leanCodeLinkPreviewDoc
    let inlineJs? := findExtraJsContaining? st "function bindInlinePreview()"
    let previewKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey `Nat.add
    pure (
      countSubstr out s!"data-bp-preview-key=\"{previewKey}\"" >= 1 &&
      !hasSubstr out s!"data-bp-preview-key=\"{previewKey}\" data-bp-preview-fallback-label=" &&
      hasSubstr out "class=\"bp_summary_decl_list\"" &&
      hasSubstr out "class=\"bp_inline_preview_ref\"" &&
      hasSubstr out "Nat.add</code>" &&
      !hasSubstr out "Lean code:" &&
      hasExtraCss st ".bp_inline_preview_panel" &&
      match inlineJs? with
      | some inlineJs =>
        hasSubstr inlineJs "const triggerSelector = \".bp_inline_preview_ref[data-bp-preview-id]\"" &&
        hasSubstr inlineJs "function fallbackInlinePreviewHtml(trigger, key, escapeHtml)"
      | none => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls shortExternalNamePreviewDoc
    let canonicalKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      `Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.ShortExternalPreview.openedSummaryDecl
    let shortKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      (Lean.Name.mkSimple "openedSummaryDecl")
    pure (
      hasSubstr out "<code>openedSummaryDecl</code>" &&
      hasSubstr out s!"data-bp-preview-key=\"{canonicalKey}\"" &&
      !hasSubstr out s!"data-bp-preview-key=\"{shortKey}\""
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls externalDocstringDedupDoc
    let previewKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      `Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.externalDocstringDedupDecl
    let previewObjects :=
      match Informal.TraversalIndex.LeanCodePreviews.domain? st with
      | some domain => domain.objects.toArray
      | none => #[]
    let previewData? := previewObjects[0]?.map fun (_key, obj) => obj.data.compress
    pure (
      countSubstr out s!"data-bp-preview-key=\"{previewKey}\"" >= 2 &&
      previewObjects.size == 1 &&
      match previewData? with
      | some previewData =>
        hasSubstr previewData "External declaration docstring dedup marker"
      | none => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls proofFallbackSummaryDoc
    let label := Lean.Name.mkSimple "thm:preview.proof_fallback"
    let proofKey := PreviewCache.key label .proof
    let statementKey := PreviewCache.key label .statement
    pure (
      hasSubstr out "bp_summary_preview_wrap_active" &&
      hasSubstr out s!"data-bp-preview-key=\"{proofKey}\"" &&
      !hasSubstr out s!"data-bp-preview-key=\"{statementKey}\""
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.Summary
