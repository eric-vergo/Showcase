/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintPreviewWiring.Shared

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.RelatedPanel

open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls usedByPreviewDoc
    let relationJs? := findExtraJsContaining? st "function bindRelationPanel(panel)"
    pure (
      hasSubstr out "used by 2" &&
      !hasSubstr out "class=\"bp_extra_slot bp_extra_slot_group\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_uses\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      hasSubstr out "class=\"bp_relation_wrap\"" &&
      hasSubstr out "class=\"bp_relation_panel\"" &&
      hasSubstr out "class=\"bp_relation_item bp_relation_item_active\"" &&
      !hasSubstr out "class=\"bp_relation_preview_fallback_tpl\"" &&
      hasSubstr out "class=\"bp_relation_preview_message\"" &&
      hasSubstr out "Loading preview" &&
      !hasSubstr out "class=\"bp_relation_preview_empty\"" &&
      hasSubstr out "data-bp-relation-preview-id" &&
      hasSubstr out "data-bp-relation-preview-key" &&
      hasSubstr out ">statement</span>" &&
      hasSubstr out ">proof</span>" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_uses\"" "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_used_by\"" "class=\"bp_extra_slot bp_extra_slot_code\"" &&
      match relationJs? with
      | some relationJs =>
        hasSubstr relationJs "function bindRelationPanel(panel)" &&
        hasSubstr relationJs "function previewUnavailableHtml(previewUtils, previewKey, fallbackDetail)" &&
        hasSubstr relationJs "body.innerHTML = loadingPreviewHtml();" &&
        hasSubstr relationJs "previewUtils.loadSharedPreviewEntry(previewKey)" &&
        !hasSubstr relationJs "fallbackTemplates" &&
        hasSubstr relationJs "const initialItem = items.find(function (item) {" &&
        hasSubstr relationJs "item.classList.contains(\"bp_relation_item_active\")" &&
        hasSubstr relationJs "function loadActivePreview()" &&
        hasSubstr relationJs "selectItem(initialItem)" &&
        !hasSubstr relationJs "activate(initialItem, { openWrap: false })" &&
        hasSubstr relationJs "item.addEventListener(\"mouseenter\"" &&
        hasSubstr relationJs "item.addEventListener(\"focusin\""
      | none => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls usedBySinglePreviewDoc
    pure (
      hasSubstr out "uses 1" &&
      hasSubstr out "uses 0" &&
      hasSubstr out "used by 1" &&
      hasSubstr out "used by 0" &&
      hasSubstr out "bp_code_link_status_absent" &&
      hasSubstr out "bp_code_link_empty" &&
      hasSubstr out "No associated Lean declarations" &&
      hasSubstr out ">X</span>" &&
      hasSubstr out ">L∃∀N</span>" &&
      hasSubstr out "class=\"bp_relation_chip bp_relation_chip_empty\"" &&
      hasSubstr out "class=\"bp_inline_preview_ref\"" &&
      !hasSubstr out "class=\"bp_inline_preview_tpl\" data-bp-preview-id=\"bp-used-by-" &&
      hasSubstr out "data-bp-preview-id=\"bp-used-by-" &&
      hasSubstr out "data-bp-preview-key="
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls usesPreviewDoc
    let relationJs? := findExtraJsContaining? st "function bindRelationPanel(panel)"
    pure (
      hasSubstr out "uses 3" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_uses\"" &&
      hasSubstr out "class=\"bp_relation_chip bp_uses_chip\"" &&
      hasSubstr out "class=\"bp_relation_panel\"" &&
      hasSubstr out "Uses 3" &&
      hasSubstr out "Hover a dependency to preview it." &&
      hasSubstr out "data-bp-relation-preview-id=\"bp-uses-" &&
      hasSubstr out "def:uses.hidden" &&
      hasSubstr out "def:uses.inline" &&
      hasSubstr out "def:uses.proof" &&
      hasSubstr out ">statement</span>" &&
      hasSubstr out ">proof</span>" &&
      hasSubstr out ">automatic</span>" &&
      hasSubstr out ">technical</span>" &&
      hasSubstr out ">auxiliary</span>" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_uses\"" "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_used_by\"" "class=\"bp_extra_slot bp_extra_slot_code\"" &&
      match relationJs? with
      | some relationJs =>
        hasSubstr relationJs "function bindRelationPanel(panel)" &&
        hasSubstr relationJs "previewUtils.loadSharedPreviewEntry(previewKey)" &&
        hasSubstr relationJs "selectItem(initialItem)"
      | none => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls groupPreviewDoc
    let relationJs? := findExtraJsContaining? st "function bindRelationPanel(panel)"
    pure (
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_group\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_uses\"" &&
      hasSubstr out "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_group\"" "class=\"bp_extra_slot bp_extra_slot_uses\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_uses\"" "class=\"bp_extra_slot bp_extra_slot_used_by\"" &&
      appearsBefore out "class=\"bp_extra_slot bp_extra_slot_used_by\"" "class=\"bp_extra_slot bp_extra_slot_code\"" &&
      hasSubstr out "Hover another entry in this group to preview it." &&
      hasSubstr out "class=\"bp_relation_item bp_relation_item_active\"" &&
      hasSubstr out "class=\"bp_relation_preview_message\"" &&
      hasSubstr out "Loading preview" &&
      !hasSubstr out "class=\"bp_relation_preview_fallback_tpl\"" &&
      !hasSubstr out "class=\"bp_relation_preview_empty\"" &&
      hasSubstr out "data-bp-relation-preview-id=\"bp-group-" &&
      hasSubstr out "Preview group title." &&
      hasSubstr out "used by 1" &&
      match relationJs? with
      | some relationJs =>
        hasSubstr relationJs "function bindRelationPanel(panel)" &&
        hasSubstr relationJs "previewUtils.loadSharedPreviewEntry(previewKey)" &&
        hasSubstr relationJs "selectItem(initialItem)" &&
        !hasSubstr relationJs "activate(initialItem, { openWrap: false })"
      | none => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls missingGroupPreviewDoc
    pure (
      hasSubstr out "bp_relation_chip_warn" &&
      hasSubstr out "data-bp-preview-id=\"bp-group-" &&
      hasSubstr out "data-bp-preview-key=" &&
      hasSubstr out "grp:missing"
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls singleDeclaredGroupDoc
    pure (
      !hasSubstr out "class=\"bp_extra_slot bp_extra_slot_group\"" &&
      !hasSubstr out "bp_relation_chip_warn" &&
      !hasSubstr out "data-bp-relation-preview-id=\"bp-group-"
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.RelatedPanel
