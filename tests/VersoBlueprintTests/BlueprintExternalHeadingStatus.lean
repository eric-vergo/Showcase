/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintExternalHeadingStatus

open Lean
open Informal
open Informal.Data
open Verso.VersoBlueprintTests.Blueprint.Support

private def inlineProofGapStatus : Data.ProvedStatus :=
  .containsSorry #[{ location := .proof, refs? := some 1 }]

private def missingExternalRef (name : Lean.Name) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := false
      kind := .definition
  }

private def proofGapExternalRef (name : Lean.Name) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := true
      kind := .theorem
      provedStatus := .containsSorry #[{ location := .proof, refs? := some 1 }]
  }

private def renderFailedExternalRef (name : Lean.Name) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := true
      kind := .theorem
      render := .error (.exception name "synthetic render failure")
  }

/-- info: true -/
#guard_msgs in
#eval!
  let data : BlockData := {
    kind := .statement .theorem
    codeData := some (.external #[proofGapExternalRef `Ext.thm.proof_only])
    label := `status.theorem.external
    count := 1
  }
  let cdata : CodeSummary.ComputedData := {
    source := data.codeData
  }
  match (CodeSummary.renderParts data cdata (fun _ => none)).statusMark with
  | some mark =>
    match mark.status with
    | .containsSorry info =>
      !info.isEmpty &&
      info.any (·.location == Data.SorryWhere.proof) &&
      !info.any (·.location == Data.SorryWhere.statement) &&
      hasSubstr mark.title "Statement: completed" &&
      hasSubstr mark.title "Proof: with sorries"
    | _ => false
  | none => false

/-- info: true -/
#guard_msgs in
#eval!
  let ref : Data.ExternalRef := {
    (proofGapExternalRef `Ext.def.proof_only) with
      kind := .definition
  }
  let data : BlockData := {
    kind := .statement .definition
    codeData := some (.external #[ref])
    label := `status.definition.external
    count := 1
  }
  let cdata : CodeSummary.ComputedData := {
    source := data.codeData
  }
  match (CodeSummary.renderParts data cdata (fun _ => none)).statusMark with
  | some mark =>
    match mark.status with
    | .containsSorry info =>
      !info.isEmpty &&
      info.any (·.location == Data.SorryWhere.proof) &&
      !info.any (·.location == Data.SorryWhere.statement) &&
      hasSubstr mark.title "Statement: completed" &&
      hasSubstr mark.title "Proof: with sorries"
    | _ => false
  | none => false

/-- info: true -/
#guard_msgs in
#eval!
  let codeData : InlineCodeData := {
    label := `status.inline.panel
    definedDefs := #[{ name := `inlineDef, provedStatus := .proved }]
    definedTheorems := #[{ name := `inlineThm, provedStatus := inlineProofGapStatus }]
  }
  let headingData : BlockData := {
    kind := .statement .definition
    codeData := some (.inline codeData)
    label := `status.inline.panel
    count := 1
  }
  let headingHtml := (CodeSummary.renderParts headingData { source := some (.inline codeData) } (fun _ => none)).codeEntry.asString
  let summaryTitle := CodeSummary.panelSummaryTitle
    `status.inline.panel
    { source := some (.inline codeData) }
  hasSubstr summaryTitle "status.inline.panel" &&
  hasSubstr summaryTitle "inlineThm [sorry in proof]" &&
  hasSubstr headingHtml "L∃∀N" &&
  hasSubstr headingHtml "class=\"bp_code_decl_item\"" &&
  hasSubstr headingHtml "Associated Lean declarations"

/-- info: true -/
#guard_msgs in
#eval!
  let decls := #[
    proofGapExternalRef `Ext.external.proof_gap,
    missingExternalRef `Ext.external.missing
  ]
  let summaryTitle := CodeSummary.panelSummaryTitle
    `status.external.panel
    { source := some (.external decls) }
  let headingData : BlockData := {
    kind := .statement .theorem
    codeData := some (.external decls)
    label := `status.external.panel
    count := 1
  }
  let headingHtml := (CodeSummary.renderParts headingData { source := some (.external decls) } (fun _ => none)).codeEntry.asString
  hasSubstr summaryTitle "Lean declarations (1/2 present)" &&
  hasSubstr headingHtml "L∃∀N" &&
  hasSubstr headingHtml "class=\"bp_code_decl_item\""

/-- info: true -/
#guard_msgs in
#eval!
  let decls := #[renderFailedExternalRef `Ext.external.render_fail]
  let headingData : BlockData := {
    kind := .statement .theorem
    codeData := some (.external decls)
    label := `status.external.render_fail
    count := 1
  }
  let cdata : CodeSummary.ComputedData := {
    source := headingData.codeData
  }
  let rendered := CodeSummary.renderParts headingData cdata (fun _ => none)
  let panelSummaryTitle := CodeSummary.panelSummaryTitle `status.external.render_fail cdata
  match rendered.statusMark with
  | some mark =>
    mark.status == ProvedStatus.proved &&
    hasSubstr rendered.codeEntry.asString "bp_code_link_status_proved" &&
    hasSubstr rendered.codeEntry.asString "bp_code_render_warning_badge" &&
    appearsBefore rendered.codeEntry.asString "bp_code_render_warning_badge" "bp_code_status_symbol" &&
    hasSubstr rendered.codeEntry.asString "render failed for 1 declaration" &&
    hasSubstr rendered.codeEntry.asString "Render diagnostics" &&
    hasSubstr rendered.codeEntry.asString "synthetic render failure" &&
    hasSubstr panelSummaryTitle "render failed for 1 declaration"
  | none => false

/-- info: true -/
#guard_msgs in
#eval!
  let decls := #[renderFailedExternalRef `Ext.external.panel_render_fail]
  let parts := ExternalCode.renderParts
    { caption := "Code for theorem", number? := some "1" }
    "Lean declarations (all present: 1/1)"
    decls
    (fun _ => none)
  let html := parts.externalCodePanel.asString
  hasSubstr html "Ext.external.panel_render_fail" &&
    hasSubstr html "bp_external_decl_error" &&
    hasSubstr html "render failed" &&
    hasSubstr html "Render failed: Ext.external.panel_render_fail: synthetic render failure"

end Verso.VersoBlueprintTests.BlueprintExternalHeadingStatus
