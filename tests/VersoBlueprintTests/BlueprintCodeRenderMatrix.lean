/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintCodeRenderMatrix

open Lean
open Informal
open Informal.Data
open Verso.VersoBlueprintTests.Blueprint.Support

private def provedExternalRef (name : Lean.Name) (kind : Data.NodeKind := .definition) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := true
      kind
  }

private def sorryExternalRef (name : Lean.Name) (kind : Data.NodeKind := .theorem) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := true
      kind
      provedStatus := .containsSorry #[{ location := .proof, refs? := some 1 }]
  }

private def axiomExternalRef (name : Lean.Name) (kind : Data.NodeKind := .theorem) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := true
      kind
      provedStatus := .axiomLike
  }

private def missingExternalRef (name : Lean.Name) (kind : Data.NodeKind := .definition) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := false
      kind
  }

private def renderFailedExternalRef (name : Lean.Name) (kind : Data.NodeKind := .theorem) : Data.ExternalRef :=
  {
    (Data.ExternalRef.ofName name) with
      present := true
      kind
      render := .error (.exception name "synthetic render failure")
  }

private def statementData (label : Name) (kind : Data.NodeKind) (source : Option BlockCodeData) : BlockData :=
  {
    kind := .statement kind
    codeData := source
    label
    count := 1
  }

private def inlineCode (declStatus : Data.ProvedStatus) : InlineCodeData :=
  {
    label := `inline.status
    definedDefs := #[{ name := `Inline.status, provedStatus := declStatus }]
  }

private def codeEntryHtml (label : Name) (kind : Data.NodeKind) (source : Option BlockCodeData) : String :=
  let data := statementData label kind source
  (CodeSummary.renderParts data { source } (fun _ => none)).codeEntry.asString

private def statusDotHtml (source : Option BlockCodeData) : String :=
  (CodeSummary.statusDotHtml source).asString

/-- info: true -/
#guard_msgs in
#eval!
  let inlineProvedHtml := codeEntryHtml `inline.proved .definition (some (.inline (inlineCode .proved)))
  let inlineSorryHtml := codeEntryHtml `inline.sorry .definition (some (.inline (inlineCode (.containsSorry #[{ location := .proof, refs? := some 1 }]))))
  let inlineAxiomHtml := codeEntryHtml `inline.axiom .definition (some (.inline (inlineCode .axiomLike)))
  hasSubstr inlineProvedHtml "bp_code_link_status_proved" &&
    hasSubstr inlineSorryHtml "bp_code_link_status_warning" &&
    hasSubstr inlineAxiomHtml "bp_code_link_status_axiom" &&
    hasSubstr (codeEntryHtml `inline.absent .definition none) "bp_code_link_status_absent"

/-- info: true -/
#guard_msgs in
#eval!
  hasSubstr
      (codeEntryHtml `external.missing .definition (some (.external #[missingExternalRef `Ext.missing])))
      "bp_code_link_status_missing"

/-- info: true -/
#guard_msgs in
#eval!
  hasSubstr
      (codeEntryHtml `external.axiom .theorem (some (.external #[axiomExternalRef `Ext.axiom])))
      "bp_code_link_status_axiom"

/-- info: true -/
#guard_msgs in
#eval!
  let externalRenderFailHtml := codeEntryHtml `external.render_fail .theorem (some (.external #[renderFailedExternalRef `Ext.renderFail]))
  hasSubstr externalRenderFailHtml "bp_code_link_status_proved" &&
    hasSubstr externalRenderFailHtml "bp_code_render_warning_badge" &&
    appearsBefore externalRenderFailHtml "bp_code_render_warning_badge" "bp_code_status_symbol"

/-- info: true -/
#guard_msgs in
#eval!
  -- Header status dot (1D): one `data-status` per registry-aligned tag, plus
  -- `informal` for a no-Lean block; the dot always carries `role`/`aria-label`.
  let dotProved := statusDotHtml (some (.external #[provedExternalRef `Ext.ok .definition]))
  let dotSorry := statusDotHtml (some (.external #[sorryExternalRef `Ext.sorry .theorem]))
  let dotMissing := statusDotHtml (some (.external #[missingExternalRef `Ext.missing .definition]))
  let dotAxiom := statusDotHtml (some (.external #[axiomExternalRef `Ext.axiom .theorem]))
  let dotInformal := statusDotHtml none
  hasSubstr dotProved "data-status=\"proved\"" &&
    hasSubstr dotSorry "data-status=\"containsSorry\"" &&
    hasSubstr dotMissing "data-status=\"missing\"" &&
    hasSubstr dotAxiom "data-status=\"axiomLike\"" &&
    hasSubstr dotInformal "data-status=\"informal\"" &&
    hasSubstr dotProved "class=\"bp_status_dot\"" &&
    hasSubstr dotProved "role=\"img\"" &&
    hasSubstr dotProved "aria-label=\"Lean status: proved\""

end Verso.VersoBlueprintTests.BlueprintCodeRenderMatrix
