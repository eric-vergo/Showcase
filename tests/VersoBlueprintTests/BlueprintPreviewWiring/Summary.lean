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
    let removedTemplateBinderJs? := findRemovedTemplatePreviewBinderJs? st
    let inlineJs? := findInlinePreviewJs? st
    let mathJs? := findMathPreludeJs? st
    -- Re-baselined: the summary preview root runs in pinned/docked mode (its
    -- descriptor carries mode="pinned" placement="docked", not hover/anchored).
    pure (
      !hasSubstr out "class=\"bp_summary_preview_store\"" &&
      !hasSubstr out "class=\"bp_label_preview_tpl\"" &&
      hasSubstr out "bp_summary_preview_panel" &&
      hasSubstr out "data-bp-preview-mode=\"pinned\"" &&
      hasSubstr out "data-bp-preview-placement=\"docked\"" &&
      hasSubstr out "bp_summary_preview_wrap_active" &&
      hasSubstr out "data-bp-preview-key=\"«def:preview.base»--statement\"" &&
      hasExtraCss st ".bp_inline_preview_panel[hidden]" &&
      hasExtraCss st ".bp_preview_header_label" &&
      hasExtraCss st ".bp_inline_preview_panel_footer" &&
      !hasSubstr out "data-bp-tex-prelude=\"" &&
      !hasSubstr out "bp_preview_tex_prelude" &&
      !hasSubstr out "verso-tex-prelude" &&
      hasSubstr out "data-bp-template-preview-root=\"true\"" &&
      hasSubstr out "data-bp-template-preview-panel-selector=\".bp_summary_preview_panel\"" &&
      hasSubstr out
        "data-bp-template-preview-template-selector=\"template.bp_summary_preview_tpl[data-bp-preview-label]\"" &&
      hasSubstr out
        "data-bp-template-preview-trigger-selector=\".bp_summary_preview_wrap_active[data-bp-preview-label]\"" &&
      hasSubstr out "data-bp-template-preview-title-selector=\".bp_summary_preview_panel_title\"" &&
      hasSubstr out "data-bp-template-preview-body-selector=\".bp_summary_preview_panel_body\"" &&
      hasSubstr out "data-bp-template-preview-close-selector=\".bp_summary_preview_panel_close\"" &&
      hasSubstr out "data-bp-template-preview-mode=\"pinned\"" &&
      hasSubstr out "data-bp-template-preview-placement=\"docked\"" &&
      hasSubstr out "data-bp-template-preview-allow-html-cache=\"true\"" &&
      removedTemplateBinderJs?.isNone &&
      inlineJs?.isNone &&
      !hasExtraJs st "window.VersoBlueprint.onRenderReady" &&
      match mathJs? with
      | some mathJs =>
        hasSubstr mathJs "\\\\newcommand{\\\\previewmacro}{\\\\mathsf{Preview}}" &&
        !hasSubstr mathJs "window.VersoBlueprint.onRenderReady"
      | none => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls leanCodeLinkPreviewDoc
    let inlineJs? := findInlinePreviewJs? st
    let previewKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey `Nat.add
    pure (
      countSubstr out s!"data-bp-preview-key=\"{previewKey}\"" >= 1 &&
      !hasSubstr out s!"data-bp-preview-key=\"{previewKey}\" data-bp-preview-fallback-label=" &&
      hasSubstr out "class=\"bp_summary_decl_list\"" &&
      hasSubstr out "class=\"bp_inline_preview_ref\"" &&
      hasSubstr out "Nat.add</code>" &&
      !hasSubstr out "Lean code:" &&
      hasExtraCss st ".bp_inline_preview_panel" &&
      inlineJs?.isNone
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls shortExternalNamePreviewDoc
    let shortKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      (Lean.Name.mkSimple "openedSummaryDecl")
    -- The heading chip's declaration list (which carried the canonical-key
    -- preview link this test originally targeted) is gone (1D); the opened-name
    -- decl still renders via its bare external code panel, and no short-name
    -- preview key may appear anywhere.
    pure (
      hasSubstr out "openedSummaryDecl" &&
      !hasSubstr out s!"data-bp-preview-key=\"{shortKey}\""
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls externalDocstringDedupDoc
    let previewKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      `Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.externalDocstringDedupDecl
    let previewEntries := Informal.TraversalIndex.LeanCodePreviews.entries st
    let previewData? := previewEntries[0]?.bind fun
      | .ok stored => some (Lean.toJson stored.data).compress
      | .error _ => none
    pure (
      countSubstr out s!"data-bp-preview-key=\"{previewKey}\"" >= 2 &&
      previewEntries.size == 1 &&
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
    let proofKey := PreviewCache.proofKey label
    let statementKey := PreviewCache.statementKey label
    pure (
      hasSubstr out "bp_summary_preview_wrap_active" &&
      hasSubstr out s!"data-bp-preview-key=\"{proofKey}\"" &&
      !hasSubstr out s!"data-bp-preview-key=\"{statementKey}\""
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.Summary
