/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.PreviewManifest.RelatedPanel
import VersoBlueprintTests.BlueprintPreviewWiring.Shared

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.RelatedPanel

open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

private def samplePanelEntry : Informal.RelatedPanel.PanelEntry := {
  previewId := "preview"
  previewKey := "preview-key"
  previewTitle := "Target"
  label := Lean.Name.mkSimple "target"
}

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let entry : Informal.PreviewManifest.RelatedEntry := {
      label := Lean.Name.mkSimple "target"
      title := "Target"
      previewKey := "informal:target:statement"
      axes := #[.statement, .proof]
    }
    let badges := entry.badgesHtml.asString
    hasSubstr badges "bp_relation_badge_statement" &&
      hasSubstr badges "bp_relation_badge_proof" &&
      hasSubstr badges "title=\"Declared in the statement\"" &&
      hasSubstr badges "title=\"Declared in the proof\""

/-- info: true -/
#guard_msgs in
#eval
  show Bool from
    let source := Lean.Name.mkSimple "source"
    let statementCfg := Informal.RelatedPanel.statementUsesPanelConfig source
    let proofCfg := Informal.RelatedPanel.proofUsesPanelConfig source
    statementCfg.panelTitle 2 == "Statement uses 2" &&
      statementCfg.chipTitle 1 == "Statement dependencies used by source" &&
      statementCfg.singleTitle samplePanelEntry == "Statement dependency: Target" &&
      proofCfg.panelTitle 2 == "Proof uses 2" &&
      proofCfg.chipTitle 1 == "Proof dependencies used by source" &&
      proofCfg.singleTitle samplePanelEntry == "Proof dependency: Target"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls usedByPreviewDoc
    let relationJs? := findRelationPanelJs? st
    -- Header relation chips/panels are gone (clean-card 1D): used-by / uses /
    -- group information moved to the metadata rail, and the heading carries only
    -- the title row + status dot. Statement-side used-by markup therefore no
    -- longer renders anywhere on the page.
    pure (
      !hasSubstr out "used by 2" &&
      !hasSubstr out "bp_extra_slot" &&
      !hasSubstr out "class=\"bp_relation_wrap\"" &&
      !hasSubstr out "class=\"bp_relation_panel\"" &&
      !hasSubstr out "bp_uses_chip" &&
      hasSubstr out "class=\"bp_status_dot\"" &&
      hasSubstr out "data-status=\"proved\"" &&
      hasExtraCss st ".content-wrapper > section:has(.bp_relation_panel)" &&
      hasExtraCss st ".bp_preview_header_label" &&
      relationJs?.isNone &&
      !hasExtraJs st "window.VersoBlueprint.onRenderReady"
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls usedBySinglePreviewDoc
    -- Chips (uses / used-by counts, the L∃∀N status entry, empty relation
    -- chips) no longer render; the no-Lean statement carries the "informal"
    -- status dot instead. Inline `{uses}` prose references keep their preview
    -- wiring untouched.
    pure (
      !hasSubstr out "uses 1" &&
      !hasSubstr out "used by 1" &&
      !hasSubstr out "bp_code_link_status_absent" &&
      !hasSubstr out ">L∃∀N</span>" &&
      !hasSubstr out "bp_relation_chip" &&
      hasSubstr out "data-status=\"informal\"" &&
      hasSubstr out "title=\"No associated Lean declarations\"" &&
      hasSubstr out "class=\"bp_inline_preview_ref\"" &&
      hasSubstr out "data-bp-preview-id=\"bp-uses-"
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls usesPreviewDoc
    let relationJs? := findRelationPanelJs? st
    -- The statement heading's uses chip/panel is gone (1D), and the proof-cell
    -- "USES n" chip is gone too (Stage 2 — the metadata rail's Uses section owns
    -- dependency information), so no relation-panel markup renders anywhere on
    -- the page. The dependency labels still appear via their own directives.
    pure (
      !hasSubstr out "uses 2" &&
      !hasSubstr out "bp_extra_slot" &&
      !hasSubstr out "Statement uses 2" &&
      !hasSubstr out "Statement dependency previews" &&
      !hasSubstr out "class=\"bp_relation_chip\"" &&
      !hasSubstr out "class=\"bp_relation_panel\"" &&
      !hasSubstr out "Proof uses 2" &&
      !hasSubstr out "Proof dependency previews" &&
      !hasSubstr out "Hover a dependency to preview it." &&
      !hasSubstr out "class=\"bp_relation_preview_header_label bp_preview_header_label\"" &&
      !hasSubstr out "data-bp-relation-preview-id=\"bp-uses-" &&
      !hasSubstr out "data-bp-preview-header-label=" &&
      !hasSubstr out "data-bp-preview-header-href=" &&
      hasSubstr out "def:uses.hidden" &&
      hasSubstr out "def:uses.inline" &&
      hasSubstr out "def:uses.proof" &&
      hasSubstr out "def:uses.proof.extra" &&
      !hasSubstr out ">proof</span>" &&
      !hasSubstr out "bp_uses_chip" &&
      !hasSubstr out "bp_uses_origin_badge" &&
      !hasSubstr out "bp_uses_intent_badge" &&
      relationJs?.isNone
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls groupPreviewDoc
    let relationJs? := findRelationPanelJs? st
    -- The group chip/panel is gone with the other header extras (1D): group
    -- membership is metadata-rail territory now. Statements keep only the title
    -- row + status dot.
    pure (
      !hasSubstr out "bp_extra_slot" &&
      !hasSubstr out "Group member previews" &&
      !hasSubstr out "data-bp-relation-preview-id=\"bp-group-" &&
      !hasSubstr out "used by 1" &&
      hasSubstr out "class=\"bp_status_dot\"" &&
      relationJs?.isNone
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls missingGroupPreviewDoc
    -- The undeclared-group warning chip rendered in the heading is gone with the
    -- header extras; no group markup renders at all.
    pure (
      !hasSubstr out "bp_relation_chip_warn" &&
      !hasSubstr out "data-bp-preview-id=\"bp-group-" &&
      hasSubstr out "class=\"bp_status_dot\""
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
