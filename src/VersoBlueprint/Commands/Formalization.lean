/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Commands.TrustStrip
import VersoBlueprint.FormalizationYaml
import VersoBlueprint.Informal.LeanCodeLink
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.NodeRoute
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

/-!
`blueprint_formalization` — a standalone "Formalization Metadata" page rendered
from a project's `formalization.yaml` (v0.3 standard,
https://github.com/mathlib-initiative/formalization.yaml).

Usage: `{blueprint_formalization "relative/path/to/formalization.yaml"}`.

The YAML file is read and parsed at elaboration time (the path resolves against
the build CWD, i.e. the consumer package root) via the restricted-subset parser
in `VersoBlueprint.FormalizationYaml`; the parsed document travels in the block
payload as compressed JSON. At render time, declaration names in the status and
alignment sections cross-link to their blueprint node pages (via the
`declNodeLabels` index, falling back to the inline Lean declaration anchors),
so the metadata page participates in the site's navigation. Absent optional
sections are omitted. The page follows the `blueprint_bibliography` pattern:
its own numberless part, emitted wherever the command appears.
-/

namespace Informal.Commands

open Lean Elab Command
open Verso Doc Html Genre Manual
open Verso.Output.Html

/--
Block payload for `Block.formalization`: the parsed `formalization.yaml`
document as compressed JSON text (`Json` itself has no `Quote` instance, so the
part command quotes the serialized form).
-/
structure FormalizationData where
  jsonText : String := "null"
deriving Inhabited, FromJson, ToJson, Quote

/-- The parsed document carried by the payload. -/
def FormalizationData.doc (d : FormalizationData) : Json :=
  (Json.parse d.jsonText).toOption.getD Json.null

def formalizationCss := include_str "formalization.css"

private def formalizationSummaryCss := include_str "summary.css"

/--
The formalization page reuses the summary badge classes for its status chips,
so its bundle carries `summary.css` too (site CSS is a de-duplicating set, so
this is free when a summary/dashboard block is also present).
-/
def formalizationAssetBundle : BlueprintAssetBundle :=
  blueprintCssAssetBundle [formalizationSummaryCss, formalizationCss]

private def formalizationStandardUrl : String :=
  "https://github.com/mathlib-initiative/formalization.yaml"

/-! ### Json field access (tolerant: the schema is open) -/

private def objVal? (j : Json) (key : String) : Option Json :=
  (j.getObjVal? key).toOption

private def strField? (j : Json) (key : String) : Option String :=
  match objVal? j key with
  | Option.some (Json.str s) =>
    if (Informal.FormalizationYaml.trim s).isEmpty then Option.none else Option.some s
  | Option.some (Json.num n) => Option.some (toString n)
  | Option.some (Json.bool b) => Option.some (toString b)
  | _ => Option.none

private def natField? (j : Json) (key : String) : Option Nat :=
  (j.getObjValAs? Nat key).toOption

private def arrField (j : Json) (key : String) : Array Json :=
  match objVal? j key with
  | Option.some (Json.arr a) => a
  | _ => #[]

private def strArrField (j : Json) (key : String) : Array String :=
  arrField j key |>.filterMap fun v =>
    match v with
    | Json.str s => Option.some s
    | Json.num n => Option.some (toString n)
    | _ => Option.none

private def joined? (values : Array String) : Option String :=
  if values.isEmpty then Option.none else Option.some (String.intercalate ", " values.toList)

/-! ### Rendering -/

private def fieldRow (label : String) (value : Output.Html) : Output.Html :=
  {{
    <div class="bp_formalization_field">
      <span class="bp_formalization_field_label">{{.text true label}}</span>
      <span class="bp_formalization_field_value">{{value}}</span>
    </div>
  }}

private def textFieldRow (label : String) (value? : Option String) : Output.Html :=
  match value? with
  | Option.some v => fieldRow label (.text true v)
  | Option.none => .empty

private def codeFieldRow (label : String) (value? : Option String) : Output.Html :=
  match value? with
  | Option.some v => fieldRow label {{ <code>{{.text true v}}</code> }}
  | Option.none => .empty

private def proseFieldRow (label : String) (value? : Option String) : Output.Html :=
  match value? with
  | Option.some v =>
    fieldRow label {{ <span class="bp_formalization_prose">{{.text true v}}</span> }}
  | Option.none => .empty

private def proseParagraph (value? : Option String) : Output.Html :=
  match value? with
  | Option.some v => {{ <p class="bp_formalization_prose">{{.text true v}}</p> }}
  | Option.none => .empty

/-- Source ids that are URLs become links; everything else stays text. -/
private def linkOrText (v : String) : Output.Html :=
  if v.startsWith "http://" || v.startsWith "https://" then
    {{ <a href={{v}}>{{.text true v}}</a> }}
  else
    .text true v

private def badgeRow (badges : Array Output.Html) : Output.Html :=
  if badges.isEmpty then .empty
  else {{ <div class="bp_summary_badge_row bp_formalization_badges">{{badges}}</div> }}

private def sectionHtml (title : String) (body : Array Output.Html) : Output.Html :=
  {{
    <section class="bp_formalization_section">
      <h2>{{.text true title}}</h2>
      {{body}}
    </section>
  }}

/--
Render one declaration name as a link: preferably to the blueprint node page
that formalizes it, else to its inline Lean declaration anchor, else plain
code text. The page ships no preview runtime, so decl spans carry no inert
hover-preview hook (`withPreview := false`, as on the audit page).
-/
private def declLinkHtml (st : TraverseState) (declMap : Lean.NameMap (Array Lean.Name))
    (declStr : String) : Output.Html :=
  let declStr := Informal.FormalizationYaml.trim declStr
  let declName := declStr.toName
  let node : Output.Html := {{ <code>{{.text true declStr}}</code> }}
  let nodeHref? :=
    (declMap.getD declName #[]).findSome? fun label =>
      if Informal.NodeRoute.hasNodePage st label then
        Option.some (Informal.NodeRoute.nodePageHref label)
      else Option.none
  let href? :=
    match nodeHref? with
    | Option.some href => Option.some href
    | Option.none => Informal.Resolve.resolveInlineLeanDeclHref? st declName
  match href? with
  | Option.some href =>
    Informal.LeanCodeLink.renderResolved declName node (href? := Option.some href)
      (linkTitle? := Option.some s!"Showcase entry for {declStr}")
      (withPreview := false)
  | Option.none => node

/-- Render a comma-separated declaration list, linking each name. -/
private def declListHtml (st : TraverseState) (declMap : Lean.NameMap (Array Lean.Name))
    (csv : String) : Output.Html :=
  let decls := (csv.splitOn ",").map Informal.FormalizationYaml.trim
    |>.filter (fun s => !s.isEmpty)
  let nodes := decls.map (declLinkHtml st declMap)
  .seq (nodes.intersperse {{ <span>", "</span> }}).toArray

private def alignmentStatusBadge (status : String) : Output.Html :=
  if status == "proved" || status == "verified" || status == "complete" then
    trustBadgeHtml status "success"
  else if (status.splitOn "sorry").length > 1 then
    trustBadgeHtml status "error"
  else if status == "stated" || status == "in-progress" || status == "partial" || status == "wip" then
    trustBadgeHtml status "warn"
  else
    trustBadgeHtml status

private def projectSection (doc : Json) : Output.Html :=
  match objVal? doc "project" with
  | Option.none => .empty
  | Option.some p =>
    sectionHtml "Project" #[{{
      <div class="bp_formalization_fields">
        {{textFieldRow "Name" (strField? p "name")}}
        {{textFieldRow "Authors" (joined? (strArrField p "authors"))}}
        {{textFieldRow "License" (strField? p "license")}}
      </div>
    }}]

private def sourcesSection (doc : Json) : Output.Html :=
  let srcs := arrField doc "sources"
  if srcs.isEmpty then .empty
  else
    let items := srcs.map fun s =>
      let idRow :=
        match strField? s "id" with
        | Option.some id => fieldRow "Id" (linkOrText id)
        | Option.none => .empty
      {{
        <li class="bp_formalization_item">
          <div class="bp_formalization_item_title">
            {{.text true ((strField? s "title").getD "Untitled source")}}
          </div>
          <div class="bp_formalization_fields">
            {{textFieldRow "Authors" (joined? (strArrField s "authors"))}}
            {{idRow}}
            {{textFieldRow "Type" (strField? s "type")}}
            {{textFieldRow "License" (strField? s "license")}}
            {{textFieldRow "Author contacted" (strField? s "author_contacted")}}
            {{textFieldRow "Prior work" (strField? s "prior_work")}}
          </div>
        </li>
      }}
    sectionHtml "Sources" #[{{ <ul class="bp_formalization_list">{{items}}</ul> }}]

/-! Plain (non-linking) status badges for the formalization-metadata page. They mirror
the `formalization.yaml`-declared sorry/axiom/review figures; unlike the former trust
strip badges they carry no href (the standalone trust-evidence pages were removed). -/

/-- A sorry-count badge (green at zero, red otherwise). -/
private def sorryBadge (n : Nat) : Output.Html :=
  trustBadgeHtml s!"{n} {if n == 1 then "sorry" else "sorries"}" (if n == 0 then "success" else "error")

/-- An axioms badge: green when only the standard axioms are declared, amber when the
declared set includes nonstandard axioms. -/
private def axiomsBadge (axioms : List String) : Output.Html :=
  if axioms.isEmpty then
    trustBadgeHtml "axioms: none recorded"
  else
    let nonstandard := nonstandardAxioms axioms
    let title := s!"Axioms: {String.intercalate ", " axioms}"
    if nonstandard.isEmpty then
      trustBadgeHtml s!"axioms: standard {axioms.length}" "success" (Option.some title)
    else
      trustBadgeHtml s!"axioms: {axioms.length} ({nonstandard.length} nonstandard)" "warn"
        (Option.some title)

/-- A review-status badge. -/
private def reviewBadge (status : String) : Output.Html :=
  trustBadgeHtml s!"review: {status}"

private def statusSection (st : TraverseState) (declMap : Lean.NameMap (Array Lean.Name))
    (doc : Json) : Output.Html :=
  match objVal? doc "status" with
  | Option.none => .empty
  | Option.some stj =>
    let badges : Array Output.Html := Id.run do
      let mut out : Array Output.Html := #[]
      if let some n := natField? stj "sorry_count" then
        out := out.push (sorryBadge n)
      if let some n := natField? stj "sorry_in_definitions" then
        out := out.push
          (trustBadgeHtml s!"sorries in definitions: {n}" (if n == 0 then "success" else "error"))
      let axs := strArrField stj "axioms"
      if !axs.isEmpty then
        out := out.push (axiomsBadge axs.toList)
      return out
    let resultItems := arrField stj "main_results" |>.map fun r =>
      let rBadges : Array Output.Html := Id.run do
        let mut out : Array Output.Html := #[]
        if let some n := natField? r "sorry_count" then
          out := out.push (sorryBadge n)
        let axs := strArrField r "axioms"
        if !axs.isEmpty then
          out := out.push (axiomsBadge axs.toList)
        return out
      let litDepsRow :=
        match objVal? r "literature_dependencies" with
        | Option.some _ =>
          let deps := strArrField r "literature_dependencies"
          textFieldRow "Literature dependencies"
            (Option.some (if deps.isEmpty then "none" else String.intercalate ", " deps.toList))
        | Option.none => .empty
      {{
        <li class="bp_formalization_item">
          <div class="bp_formalization_item_title">
            {{declLinkHtml st declMap ((strField? r "declaration").getD "")}}
          </div>
          <div class="bp_formalization_fields">
            {{codeFieldRow "File" (strField? r "file")}}
            {{codeFieldRow "Comparator config" (strField? r "comparator_config")}}
            {{litDepsRow}}
          </div>
          {{badgeRow rBadges}}
        </li>
      }}
    let mainResults : Array Output.Html :=
      if resultItems.isEmpty then #[]
      else #[
        {{ <h3 class="bp_formalization_subtitle">"Main results"</h3> }},
        {{ <ul class="bp_formalization_list">{{resultItems}}</ul> }}
      ]
    sectionHtml "Status"
      (#[proseParagraph (strField? stj "scope"), badgeRow badges] ++ mainResults)

private def automationSection (doc : Json) : Output.Html :=
  match objVal? doc "automation" with
  | Option.none => .empty
  | Option.some a =>
    let methodItems := arrField a "methods" |>.map fun mj =>
      let cost := (objVal? mj "cost").getD Json.null
      {{
        <li class="bp_formalization_item">
          <div class="bp_formalization_item_title">
            {{.text true ((strField? mj "method").getD "method")}}
          </div>
          <div class="bp_formalization_fields">
            {{textFieldRow "Framework" (strField? mj "framework")}}
            {{textFieldRow "Models" (joined? (strArrField mj "models"))}}
            {{textFieldRow "Wall time" (strField? cost "wall_time")}}
            {{textFieldRow "Spend" (strField? cost "spend_usd")}}
            {{textFieldRow "Hardware" (strField? cost "hardware")}}
            {{proseFieldRow "Tool setup" (strField? mj "tool_setup")}}
            {{proseFieldRow "Prompting notes" (strField? mj "prompting_notes")}}
          </div>
        </li>
      }}
    let methods : Array Output.Html :=
      if methodItems.isEmpty then #[]
      else #[{{ <ul class="bp_formalization_list">{{methodItems}}</ul> }}]
    let footer : Output.Html := {{
      <div class="bp_formalization_fields">
        {{textFieldRow "Total spend" (strField? a "spend_usd")}}
        {{proseFieldRow "Notes" (strField? a "notes")}}
      </div>
    }}
    sectionHtml "Automation" (methods.push footer)

private def fidelitySection (doc : Json) : Output.Html :=
  match objVal? doc "fidelity" with
  | Option.none => .empty
  | Option.some f => sectionHtml "Fidelity" #[proseParagraph (strField? f "divergences")]

private def reviewSection (doc : Json) : Output.Html :=
  match objVal? doc "review" with
  | Option.none => .empty
  | Option.some r =>
    let statusBadge :=
      match strField? r "status" with
      | Option.some s => badgeRow #[reviewBadge s]
      | Option.none => .empty
    let reviewers :=
      match objVal? r "reviewers" with
      | Option.some _ =>
        let names := strArrField r "reviewers"
        textFieldRow "Reviewers"
          (Option.some (if names.isEmpty then "none recorded" else String.intercalate ", " names.toList))
      | Option.none => .empty
    sectionHtml "Review" #[
      statusBadge,
      {{ <div class="bp_formalization_fields">{{reviewers}}</div> }},
      proseParagraph (strField? r "notes")
    ]

private def alignmentSection (st : TraverseState) (declMap : Lean.NameMap (Array Lean.Name))
    (doc : Json) : Output.Html :=
  match objVal? doc "alignment" with
  | Option.none => .empty
  | Option.some al =>
    let rows := arrField al "statements" |>.map fun s =>
      let noteHtml : Output.Html :=
        match strField? s "note" with
        | Option.some n => {{ <div class="bp_formalization_note">{{.text true n}}</div> }}
        | Option.none => .empty
      let statusHtml : Output.Html :=
        match strField? s "status" with
        | Option.some v => alignmentStatusBadge v
        | Option.none => .empty
      {{
        <tr>
          <td>{{.text true ((strField? s "source").getD "")}}{{noteHtml}}</td>
          <td>{{declListHtml st declMap ((strField? s "lean").getD "")}}</td>
          <td><code>{{.text true ((strField? s "module").getD "")}}</code></td>
          <td>{{statusHtml}}</td>
        </tr>
      }}
    let table : Output.Html :=
      if rows.isEmpty then .empty
      else {{
        <div class="bp_formalization_table_wrap">
          <table class="bp_formalization_table">
            <thead><tr><th>"Source"</th><th>"Lean"</th><th>"Module"</th><th>"Status"</th></tr></thead>
            <tbody>{{rows}}</tbody>
          </table>
        </div>
      }}
    sectionHtml "Alignment" #[
      {{ <div class="bp_formalization_fields">{{codeFieldRow "Namespace" (strField? al "namespace")}}</div> }},
      table
    ]

private def acknowledgementsSection (doc : Json) : Output.Html :=
  match strField? doc "acknowledgements" with
  | Option.none => .empty
  | Option.some ack => sectionHtml "Acknowledgements" #[proseParagraph (Option.some ack)]

/-- Render the whole formalization-metadata document. -/
def renderFormalization (st : TraverseState) (doc : Json) : Output.Html :=
  let declMap := Informal.NodeRoute.declNodeLabels st
  let versionSuffix :=
    match strField? doc "version" with
    | Option.some v => s!" standard ({v})."
    | Option.none => " standard."
  {{
    <div class="bp_formalization">
      <p class="bp_formalization_lead">
        "Machine-readable formalization metadata following the "
        <a href={{formalizationStandardUrl}}>"formalization.yaml"</a>
        {{.text true versionSuffix}}
      </p>
      {{projectSection doc}}
      {{sourcesSection doc}}
      {{statusSection st declMap doc}}
      {{automationSection doc}}
      {{fidelitySection doc}}
      {{reviewSection doc}}
      {{alignmentSection st declMap doc}}
      {{acknowledgementsSection doc}}
    </div>
  }}

open Verso Doc Elab Genre Manual in
block_extension Block.formalization (data : FormalizationData) where
  data := toJson data
  traverse id _data _contents := do
    let path ← (·.path) <$> read
    let _ ← Verso.Genre.Manual.externalTag id path "--bp-formalization"
    modify fun st => Informal.TraversalIndex.FormalizationPage.saveId st id
    return none
  toTeX := none
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI _goB _id data _blocks => do
      let some data ← Informal.ExtensionDecode.decode? (α := FormalizationData) data
          (fun err => s!"Malformed data in Block.formalization.toHtml ({err})")
        | pure .empty
      let st ← HtmlT.state
      pure (renderFormalization st data.doc)
  extraCss := formalizationAssetBundle.css
  extraJs := formalizationAssetBundle.js

open Verso.ArgParse in
structure BlueprintFormalizationConfig where
  path : StrLit

open Verso.ArgParse in
instance : FromArgs BlueprintFormalizationConfig Verso.Doc.Elab.PartElabM where
  fromArgs := BlueprintFormalizationConfig.mk <$> .positional' `path

open Verso Doc Elab Syntax in
def mkFormalizationPart (stx : Syntax) (endPos : String.Pos.Raw) (data : FormalizationData) :
    PartElabM FinishedPart := do
  let titlePreview := "Formalization Metadata"
  let titleInlines ← `(inline | "Formalization Metadata")
  let expandedTitle ← #[titleInlines].mapM (elabInline ·)
  let metadata : Option (TSyntax `term) := some (← `(term| { number := false }))
  let block ← ``(Verso.Doc.Block.other
    (Informal.Commands.Block.formalization (FormalizationData.mk $(quote data.jsonText))) #[])
  let subParts := #[]
  pure <| FinishedPart.mk stx stx expandedTitle titlePreview metadata #[block] subParts endPos

open Verso Doc Elab Syntax PartElabM in
@[part_command Lean.Doc.Syntax.command]
public meta def blueprintFormalizationCmd : PartCommand
  | stx@`(block|command{blueprint_formalization $args*}) => do
    let cfg ← Verso.ArgParse.parseThe BlueprintFormalizationConfig (← parseArgs args)
    let path := cfg.path.getString
    -- Elaboration-time read; the path resolves against the build CWD (the
    -- consumer package root), matching the lakefile path-dep convention.
    if !(← System.FilePath.pathExists path) then
      throwErrorAt cfg.path "blueprint_formalization: no such file (resolved against the build directory): {path}"
    match Informal.FormalizationYaml.parse (← IO.FS.readFile path) with
    | .error err => throwErrorAt cfg.path "blueprint_formalization: {path}: {err}"
    | .ok json =>
      if verso.blueprint.debug.commands.get (← Lean.getOptions) then
        logInfo m!"Blueprint formalization metadata from {path}"
      let endPos := stx.getTailPos?.get!
      closePartsUntil 1 endPos
      addPart (← mkFormalizationPart stx endPos { jsonText := json.compress })
  | _ => (Lean.Elab.throwUnsupportedSyntax : PartElabM Unit)

end Informal.Commands
