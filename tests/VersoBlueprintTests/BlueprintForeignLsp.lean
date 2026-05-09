/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support
import VersoBlueprintTests.BlueprintInformal.Shared

namespace Verso.VersoBlueprintTests.BlueprintForeignLsp

open Verso
open Verso.Genre.Manual
open Lean
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintInformal.Shared

private def manualImpls : ExtensionImpls := extension_impls%

set_option doc.verso true

private def syntheticRenderedRustAttachment : Data.ForeignAttachment := {
  language := .rust
  command := "rust-analyzer"
  root := "/tmp/vbp-foreign-render-test"
  syntheticUri := "file:///tmp/vbp-foreign-render-test/Foreign.rs"
  refs := #[
    {
      written := "foreign_step"
      status := .resolved
      sourceHref? := some "file:///tmp/vbp-foreign-render-test/Foreign.rs#L1"
      sourceSnippet? := some "pub fn foreign_step(n: u64) -> u64 {\n    n + 1\n}"
    }
  ]
}

private def syntheticRenderedRustBlockData : BlockData := {
  kind := .statement .definition
  label := Name.mkSimple "foreign.rendered.rust"
  count := 1
  foreignRefs := #[syntheticRenderedRustAttachment]
}

private def syntheticRenderedRustBlocks : Array (Doc.Block Genre.Manual) := #[
  Doc.Block.other (Block.informal syntheticRenderedRustBlockData) #[
    Doc.Block.para #[Doc.Inline.text "Foreign snippet rendering."]
  ]
]

private def renderSyntheticRenderedRustBlock : IO (String × TraverseState) := do
  let (blocks, st) ← Informal.traverseManualBlocks syntheticRenderedRustBlocks manualImpls
  let html ← Informal.renderManualBlocksHtmlWithState blocks manualImpls st
  pure (html.asString, st)

private def withoutAsciiWhitespace (s : String) : String :=
  String.ofList <| s.toList.filter fun c =>
    c != ' ' && c != '\n' && c != '\t' && c != '\r'

private def rustSnippetFormsSource : String :=
  String.intercalate "\n" [
    "#[inline]",
    "/// Crate visible.",
    "pub(crate) fn crate_visible(n: u64) -> u64 {",
    "    n + 1",
    "}",
    "",
    "pub async fn async_step(n: u64) -> u64 {",
    "    n + 2",
    "}",
    "",
    "pub const fn const_step(n: u64) -> u64 {",
    "    n + 3",
    "}",
    "",
    "pub const MAX_STEPS: u64 = 10_000;",
    "",
    "pub fn after_const() -> u64 {",
    "    MAX_STEPS",
    "}"
  ]

private def rustSnippetContains (ref : String) (targetLine : Nat) (needle : String) : Bool :=
  match ForeignLsp.Testing.rustSnippetOfSource? ref targetLine rustSnippetFormsSource with
  | some snippet => snippet.contains needle
  | none => false

private def rustSnippetOmits (ref : String) (targetLine : Nat) (needle : String) : Bool :=
  match ForeignLsp.Testing.rustSnippetOfSource? ref targetLine rustSnippetFormsSource with
  | some snippet => !snippet.contains needle
  | none => false

/-- info: true -/
#guard_msgs in
#eval
  match ForeignLsp.parseReferenceList .rocq "def1, def2,def1" with
  | .ok refs => refs == #["def1", "def2"]
  | .error _ => false

/-- info: true -/
#guard_msgs in
#eval
  let doc := ForeignLsp.syntheticDocument
    (System.FilePath.mk "/tmp/vbp-foreign-test")
    "/tmp/vbp-foreign-test/Blueprint.lean"
    .rocq
    "From Coq Require Import Init.Prelude."
    #["def1", "def2"]
  doc.preludeLastLine? == some 0 &&
    doc.uses.size == 2 &&
    (doc.uses[0]!).line < (doc.uses[1]!).line &&
    doc.text.contains "Check def1." &&
    doc.text.contains "Check def2."

/-- info: true -/
#guard_msgs in
#eval
  let doc := ForeignLsp.syntheticDocument
    (System.FilePath.mk "/tmp/vbp-foreign-test")
    "/tmp/vbp-foreign-test/Blueprint.lean"
    .rust
    "fn foreign_target() -> i32 { 1 }"
    #["foreign_target"]
  doc.uses.size == 1 &&
    doc.text.contains "#[allow(dead_code)] fn __verso_blueprint_lookup_0()" &&
    doc.text.contains "{ let _ = foreign_target; }" &&
    doc.uses[0]!.character > 0

/-- info: true -/
#guard_msgs in
#eval
  rustSnippetContains "crate_visible" 2 "pub(crate) fn crate_visible" &&
    rustSnippetContains "crate_visible" 2 "#[inline]" &&
    rustSnippetContains "crate_visible" 2 "/// Crate visible." &&
    rustSnippetContains "async_step" 6 "pub async fn async_step" &&
    rustSnippetContains "const_step" 10 "pub const fn const_step" &&
    rustSnippetContains "MAX_STEPS" 14 "pub const MAX_STEPS" &&
    rustSnippetOmits "MAX_STEPS" 14 "after_const"

/--
error: Label «foreign.empty»: 'rust' references must not be empty
-/
#guard_msgs in
#docs (Genre.Manual) foreignEmptyRejected "Foreign Empty Rejected" :=
:::::::
:::definition "foreign.empty" (rust := "")
Empty Rust references are rejected.
:::
:::::::

set_option verso.blueprint.foreignLsp.rust.command "__verso_blueprint_missing_rust_analyzer__"
set_option verso.blueprint.foreignLsp.timeoutMs 50

/--
warning: Label «foreign.missing.server»: Rust reference 'missing_symbol' unavailable: could not find LSP command '__verso_blueprint_missing_rust_analyzer__' on PATH
-/
#guard_msgs in
#docs (Genre.Manual) foreignMissingServerDoc "Foreign Missing Server Doc" :=
:::::::
:::definition "foreign.missing.server" (rust := "missing_symbol")
The missing server path still records a graceful warning snapshot.
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state ← currentState
    let some node := state.data.get? (Name.mkSimple "foreign.missing.server")
      | pure false
    match node.foreignRefs with
    | #[attachment] =>
      pure <|
        attachment.language == Data.ForeignLanguage.rust &&
        attachment.refs.size == 1 &&
        attachment.refs[0]!.written == "missing_symbol" &&
        attachment.refs[0]!.status == Data.ForeignLookupStatus.unavailable
    | _ => pure false

/-- info: true -/
#guard_msgs in
#eval! do
  let out ← renderManualDocHtmlString manualImpls foreignMissingServerDoc
  pure <|
    hasSubstr out "bp_foreign_lsp_badge" &&
    hasSubstr out "bp_foreign_lsp_badge_warning" &&
    hasSubstr out "Rust 0/1" &&
    hasSubstr out "missing_symbol unavailable" &&
    hasSubstr out "bp_foreign_rust_status_unavailable" &&
    hasSubstr out "Unavailable"

/-- info: true -/
#guard_msgs in
#eval! do
  let (out, st) ← renderSyntheticRenderedRustBlock
  pure <|
    hasExtraCss st ".bp_rust_kw" &&
    hasSubstr out "bp_rust_kw" &&
    hasSubstr out "bp_rust_ty" &&
    hasSubstr out "foreign_step" &&
    hasSubstr out "Rust 1/1" &&
    hasSubstr out "data-bp-foreign-rust-target=\"bp-foreign-rust-foreign-rendered-rust\"" &&
    hasSubstr out "id=\"bp-foreign-rust-foreign-rendered-rust\""

/-- info: true -/
#guard_msgs in
#eval! do
  let (out, _st) ← renderSyntheticRenderedRustBlock
  let compact := withoutAsciiWhitespace out
  pure <|
    hasSubstr compact
      "Foreignsnippetrendering.</p></div></div><divclass=\"bp_wrapperbp_code_panel_wrapper\"><detailsclass=\"bp_code_blockbp_code_panel\"" &&
    appearsBefore out
      "title=\"«foreign.rendered.rust»\""
      "class=\"bp_wrapper bp_code_panel_wrapper\""

end Verso.VersoBlueprintTests.BlueprintForeignLsp
