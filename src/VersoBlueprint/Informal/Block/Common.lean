/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.ProvedStatus
import VersoBlueprint.Resolve

namespace Informal

open Verso Doc Elab
open Verso.Genre Manual
open Lean Elab

inductive NumberingMode where
  | sub
  | global
  | local
deriving Repr, Inhabited, BEq, FromJson, ToJson, Quote

def NumberingMode.parse? (raw : String) : Option NumberingMode :=
  match raw.trimAscii.toString.toLower with
  | "sub" | "chapter" | "section" | "subnumber" | "sub-number" => some .sub
  | "global" => some .global
  | "local" => some .local
  | _ => none

register_option verso.blueprint.numbering : String := {
  defValue := "sub"
  descr := "Numbering mode for blueprint informal blocks: `sub` (default; prefix with numbered part path), `global`, or `local`"
}

def numberingMode (opts : Lean.Options) : NumberingMode :=
  match NumberingMode.parse? (verso.blueprint.numbering.get opts) with
  | some mode => mode
  | none => .sub

def renderErrorMessage? : Data.ExternalDeclRender → Option String
  | .ok _ => none
  | .error error => some error.message

structure ExternalRenderFailure where
  decl : Data.ExternalRef
  message : String
deriving Repr, Inhabited

def externalRenderFailure? (decl : Data.ExternalRef) : Option ExternalRenderFailure := do
  if !decl.present then
    none
  else
    let message ← renderErrorMessage? decl.render
    some { decl, message }

def externalRenderFailures (decls : Array Data.ExternalRef) : Array ExternalRenderFailure :=
  decls.filterMap externalRenderFailure?

def externalRenderFailureCount (decls : Array Data.ExternalRef) : Nat :=
  (externalRenderFailures decls).size

def externalRenderFailureSummaryText (count : Nat) : String :=
  if count == 1 then
    "render failed for 1 declaration"
  else
    s!"render failed for {count} declarations"

def appendExternalRenderFailureSummary (title : String) (count : Nat) : String :=
  if count == 0 then
    title
  else
    s!"{title}; {externalRenderFailureSummaryText count}"

structure CodeDeclData where
  name : Name
  commandIndex : Nat := 0
  weight : Nat := 1
  provedStatus : Data.ProvedStatus := .proved
deriving Repr, Inhabited, FromJson, ToJson, Quote

def CodeDeclData.ofLiterateDef (d : Data.LiterateDef) : CodeDeclData :=
  {
    name := d.name
    commandIndex := d.commandIndex
    weight := max d.commandLines 1
    provedStatus := d.provedStatus
  }

def CodeDeclData.ofLiterateThm (d : Data.LiterateThm) : CodeDeclData :=
  {
    name := d.name
    commandIndex := d.commandIndex
    weight := max d.commandLines 1
    provedStatus := d.provedStatus
  }

structure InlineCodeData where
  label : Data.Label
  definedDefs : Array CodeDeclData := #[]
  definedTheorems : Array CodeDeclData := #[]
  foldProofs : Bool := true
deriving Repr, Inhabited, FromJson, ToJson, Quote

/--
Resolved block-level code semantics used by informal block rendering.

This unifies directive hints and inline code payloads (`InlineCodeData`)
for the HTML phase:
- `inline` takes precedence whenever code-block data exists,
- otherwise we fall back to optional external declaration hints.
-/
inductive BlockCodeData where
  /-- Inline/literate code block associated with this label. -/
  | inline (code : InlineCodeData)
  /-- External Lean declarations associated with this label. -/
  | external (decls : Array Data.ExternalRef)
deriving Repr, Inhabited, FromJson, ToJson, Quote

/-- Projection from environment-level `Data.CodeRef` into JSON-safe block payload hints. -/
def BlockCodeData.ofCodeRefHint (codeRef? : Option Data.CodeRef) : Option BlockCodeData :=
  match codeRef? with
  | some (.external decls) => some (.external decls)
  | _ => none

/-- Resolve inline precedence at render time by combining optional hint + inline payload. -/
def BlockCodeData.ofHintAndInline (hint? : Option BlockCodeData) (inline? : Option InlineCodeData)
    : Option BlockCodeData :=
  match inline? with
  | some code => some (.inline code)
  | Option.none => hint?

def BlockCodeData.inlineData? : BlockCodeData → Option InlineCodeData
  | .inline code => some code
  | _ => Option.none

def BlockCodeData.externalDecls : BlockCodeData → Array Data.ExternalRef
  | .external decls => decls
  | _ => #[]

structure BlockStatusMark where
  status : Data.ProvedStatus := .proved
  title : String
  symbolOverride? : Option String := none
deriving Repr, Inhabited

def BlockStatusMark.text (s : BlockStatusMark) : String :=
  match s.symbolOverride? with
  | some txt => txt
  | none =>
    match s.status with
    | .proved => "✓"
    | .missing => "✗"
    | .axiomLike => "⚠"
    | .containsSorry _ => "✗"

def BlockStatusMark.toHtml (s : BlockStatusMark) : Output.Html :=
  open Verso.Output.Html in
  {{ <span class="bp_status_mark" title={{s.title}}>{{.text true s.text}}</span> }}

def codeHoverListItem (body : Output.Html) : Output.Html :=
  open Verso.Output.Html in
  {{<li>{{body}}</li>}}

def codeHoverTextItem (text : String) : Output.Html :=
  open Verso.Output.Html in
  let body : Output.Html := .text true text
  codeHoverListItem body

def codeHoverEmptyItem (text : String) : Output.Html :=
  open Verso.Output.Html in
  {{<li class="bp_code_hover_none">{{.text true text}}</li>}}

def codeHoverCodeItem (text : String) : Output.Html :=
  open Verso.Output.Html in
  let body : Output.Html := {{<code>{{.text true text}}</code>}}
  codeHoverListItem body

def codeHoverSection (title : String) (items : Array Output.Html) : Output.Html :=
  open Verso.Output.Html in
  {{
    <div class="bp_code_hover_section">
      <span class="bp_code_hover_label">{{.text true title}}</span>
      <ul class="bp_code_hover_list">
        {{.seq items}}
      </ul>
    </div>
  }}

structure BlockData where
  kind : Data.InProgressKind := .proof
  /-- Optional code hint used for statement blocks (`.proof` always ignores this). -/
  codeData : Option BlockCodeData := none
  label : Data.Label
  parent : Option Data.Parent := none
  count : Nat
  numberingMode : NumberingMode := .sub
  /--
  Top-level rendered part prefix assigned during traversal (for example `3` or `A`).

  This is stored as `String` rather than `Manual.Numbering` because it is a
  render-facing cache: the upstream part numbering may be numeric or alphabetic,
  and all downstream consumers need here is the final display prefix that should
  appear in cross-page references and HTML labels.
  -/
  partPrefix : Option String := none
  /-- Document-order global index assigned during traversal. -/
  globalCount : Option Nat := none
  /-- Statement-side `{uses ...}` dependencies declared for this labeled block. -/
  statementDeps : Array Data.Label := #[]
  /-- Proof-side `{uses ...}` dependencies declared for this labeled block. -/
  proofDeps : Array Data.Label := #[]
  owner : Option Data.AuthorId := none
  ownerDisplayName : Option String := none
  ownerUrl : Option String := none
  ownerImageUrl : Option String := none
  tags : Array String := #[]
  effort : Option String := none
  priority : Option String := none
  prUrl : Option String := none
deriving FromJson, ToJson, Quote

structure CodePanelHeader where
  caption : String
  number? : Option String := none
deriving Repr, Inhabited

def codePanelHeader (data : BlockData) (numberText : String) : CodePanelHeader :=
  match data.kind with
  | .proof => { caption := "Lean code for proof" }
  | .statement nodeKind =>
    {
      caption := s!"Lean code for {nodeKind}"
      number? := some numberText
    }

def fallbackCodePanelHeader : CodePanelHeader := {
  caption := "Lean code"
}

register_option verso.blueprint.foldProofs : Bool := {
  defValue := true
  descr := "Enable proof folding in VersoBlueprint Lean code blocks (hide text after `by` behind a toggle)"
}

def provedStatusHasSorry (status : Data.ProvedStatus) : Bool :=
  status.isIncomplete

def provedStatusLocationText (status : Data.ProvedStatus) : String :=
  status.sorryLocationText

def provedStatusContainsSorry (status : Data.ProvedStatus) : Bool :=
  status.containsExplicitSorry

def provedStatusSummaryText (status : Data.ProvedStatus) : String :=
  match status with
  | .missing => "missing declaration"
  | .axiomLike => "axiom-like (no body)"
  | .containsSorry _ => s!"sorry {provedStatusLocationText status}"
  | .proved => "unknown"

def externalDeclHasGap (decl : Data.ExternalRef) : Bool :=
  decl.present && provedStatusHasSorry decl.provedStatus

def externalCodeEntryTitle (found total missing withGaps : Nat) : String :=
  if missing > 0 then
    s!"Lean declarations ({found}/{total} present)"
  else if withGaps > 0 then
    s!"Lean declarations (all present: {found}/{total}; incomplete: {withGaps})"
  else
    s!"Lean declarations (all present: {found}/{total})"

def mkCodePanel
    (header : CodePanelHeader) (summaryTitle : String)
    (progressBar body : Output.Html)
    (attrs : Array (String × String) := #[]) : Output.Html :=
  open Verso.Output.Html in
  {{
    <div class="bp_wrapper bp_code_panel_wrapper">
      <details class="bp_code_block bp_code_panel" {{attrs}}>
        <summary class="bp_heading lemma_thmheading" title={{summaryTitle}}>
          <span class="bp_caption lemma_thmcaption bp_code_summary_text">{{.text true header.caption}}</span>
          {{if let some number := header.number? then
              {{<span class="bp_label lemma_thmlabel bp_code_summary_label">{{.text true number}}</span>}}
            else
              .empty}}
          {{progressBar}}
        </summary>
        {{body}}
      </details>
    </div>
  }}

end Informal
