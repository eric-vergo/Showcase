/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.FormalizationYaml
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.TraversalIndex

/-!
Dashboard trust strip.

A compact badge row surfaced with `blueprint_dashboard`: sorry count, axiom
hygiene, review status, and the statement-comparator verdict. It is fed by two
build options naming machine-readable artifacts, both read at elaboration time
(paths resolve against the build CWD, i.e. the consumer package root):

- `verso.blueprint.trust.formalizationYaml` — the project's
  `formalization.yaml` (v0.3); supplies the sorry/axioms/review badges.
- `verso.blueprint.trust.comparatorStatus` — a comparator-status JSON artifact
  (`{status, theorem_names, verified_at, note, ...}`); supplies the comparator
  badge.

Degrades gracefully: an unset option silently omits its badges; a *set* option
naming a missing or unparsable file is a build error (a configured trust signal
must not vanish silently). When the document also renders a
`blueprint_formalization` page, the strip links to it (resolved through the
`FormalizationPage` traversal store, never a guessed slug).
-/

namespace Informal.Commands

open Lean
open Verso Doc Html Genre Manual
open Verso.Output.Html

register_option verso.blueprint.trust.formalizationYaml : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the project's formalization.yaml; feeds the dashboard trust strip. Empty disables."
}

register_option verso.blueprint.trust.comparatorStatus : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to a comparator-status JSON artifact; feeds the dashboard trust strip's comparator badge. Empty disables."
}

register_option verso.blueprint.trust.comparatorConfig : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the comparator's configuration JSON; its contents are embedded verbatim (pretty-printed) on the comparator evidence page. Empty or missing ⇒ omitted (probe-and-degrade)."
}

register_option verso.blueprint.trust.challengeFile : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the comparator's Challenge Lean file; its contents are embedded verbatim on the comparator evidence page. Empty or missing ⇒ omitted (probe-and-degrade)."
}

/-- Comparator verdict extracted from the comparator-status artifact.

`runUrl`/`configJson`/`challengeSource` are empty-string sentinels (matching the
other fields; empty ⇒ absent): the optional CI-run URL (from the status
artifact's `run_url` field, absent today ⇒ empty) and the verbatim contents of
the comparator config JSON / Challenge Lean file (embedded on the evidence page,
read from the `verso.blueprint.trust.comparatorConfig` / `.challengeFile`
options at elaboration; probe-and-degrade to empty). -/
structure TrustComparator where
  status : String := ""
  verifiedAt : String := ""
  theoremNames : List String := []
  note : String := ""
  runUrl : String := ""
  configJson : String := ""
  challengeSource : String := ""
deriving Inhabited, FromJson, ToJson, Quote

/-- Trust-strip payload: only fields present in the configured artifacts are set. -/
structure TrustData where
  sorryCount : Option Nat := none
  axioms : List String := []
  reviewStatus : String := ""
  comparator : Option TrustComparator := none
deriving Inhabited, FromJson, ToJson, Quote

/-- Extract the trust-relevant fields from a parsed `formalization.yaml` document. -/
def TrustData.ofFormalizationJson (doc : Json) : TrustData :=
  let status := (doc.getObjVal? "status").toOption.getD Json.null
  let review := (doc.getObjVal? "review").toOption.getD Json.null
  {
    sorryCount := (status.getObjValAs? Nat "sorry_count").toOption
    axioms := (status.getObjValAs? (List String) "axioms").toOption.getD []
    reviewStatus := (review.getObjValAs? String "status").toOption.getD ""
  }

/-- Extract the comparator verdict from a comparator-status artifact (`verified_at` may be `null`).
`run_url` is optional (absent in older artifacts ⇒ empty). The embedded config /
Challenge sources are filled in later from their own options (`elabTrustData?`). -/
def TrustComparator.ofJson (j : Json) : TrustComparator :=
  {
    status := (j.getObjValAs? String "status").toOption.getD ""
    verifiedAt := (j.getObjValAs? String "verified_at").toOption.getD ""
    theoremNames := (j.getObjValAs? (List String) "theorem_names").toOption.getD []
    note := (j.getObjValAs? String "note").toOption.getD ""
    runUrl := (j.getObjValAs? String "run_url").toOption.getD ""
  }

/-- The axioms every kernel-checked Mathlib development is expected to use. -/
def standardAxioms : List String := ["propext", "Classical.choice", "Quot.sound"]

/-!
Evidence-page routes. Each configured badge links to a generated evidence page
under `trust/`; these root-relative hrefs (no leading slash) resolve against each
page's `<base href>`, matching the worklist/audit route convention. The paired
`Verso.Multi.Path`s are the multi-page output locations `TrustPages` writes to.
-/

def trustSorriesHref : String := "trust/sorries/"
def trustSorriesPath : Verso.Multi.Path := #["trust", "sorries"]
def trustAxiomsHref : String := "trust/axioms/"
def trustAxiomsPath : Verso.Multi.Path := #["trust", "axioms"]
def trustReviewHref : String := "trust/review/"
def trustReviewPath : Verso.Multi.Path := #["trust", "review"]
def trustComparatorHref : String := "trust/comparator/"
def trustComparatorPath : Verso.Multi.Path := #["trust", "comparator"]

/--
One trust badge. Reuses the dashboard's `.bp_summary_badge` classes (`variant`
is one of `""`/`success`/`warn`/`error`/`accent`); `title?` becomes a tooltip.
When `href?` is set the badge renders as an `<a>` linking to its evidence page;
otherwise it is a plain `<span>`.
-/
def trustBadgeHtml (text : String) (variant : String := "")
    (title? : Option String := Option.none) (href? : Option String := Option.none) :
    Output.Html :=
  let className :=
    if variant.isEmpty then "bp_summary_badge"
    else s!"bp_summary_badge bp_summary_badge_{variant}"
  let attrs := #[("class", className)]
  let attrs :=
    match title? with
    | Option.some t => attrs.push ("title", t)
    | Option.none => attrs
  match href? with
  | Option.some href => .tag "a" (attrs.push ("href", href)) (.text true text)
  | Option.none => .tag "span" attrs (.text true text)

def trustSorryBadge (n : Nat) : Output.Html :=
  trustBadgeHtml
    s!"{n} {if n == 1 then "sorry" else "sorries"}"
    (if n == 0 then "success" else "error")
    (href? := Option.some trustSorriesHref)

def trustAxiomsBadge (axioms : List String) : Output.Html :=
  if axioms.isEmpty then
    trustBadgeHtml "axioms: none recorded" (href? := Option.some trustAxiomsHref)
  else
    let nonstandard := axioms.filter (fun a => !standardAxioms.contains a)
    let title := s!"Axioms: {String.intercalate ", " axioms}"
    if nonstandard.isEmpty then
      trustBadgeHtml s!"axioms: standard {axioms.length}" "success" (Option.some title)
        (Option.some trustAxiomsHref)
    else
      trustBadgeHtml s!"axioms: {axioms.length} ({nonstandard.length} nonstandard)" "warn"
        (Option.some title) (Option.some trustAxiomsHref)

def trustReviewBadge (status : String) : Output.Html :=
  trustBadgeHtml s!"review: {status}" (href? := Option.some trustReviewHref)

def trustComparatorBadge (cmp : TrustComparator) : Output.Html :=
  let theoremsTitle :=
    if cmp.theoremNames.isEmpty then ""
    else s!"; theorems: {String.intercalate ", " cmp.theoremNames}"
  if cmp.status == "verified" then
    let when := if cmp.verifiedAt.isEmpty then "Independently verified" else s!"Verified at {cmp.verifiedAt}"
    trustBadgeHtml "comparator: verified" "success" (Option.some s!"{when}{theoremsTitle}")
      (Option.some trustComparatorHref)
  else if cmp.status == "configured" then
    let title := if cmp.note.isEmpty then s!"Comparator configured{theoremsTitle}" else cmp.note
    trustBadgeHtml "comparator: configured — not yet run" "warn" (Option.some title)
      (Option.some trustComparatorHref)
  else
    trustBadgeHtml s!"comparator: {cmp.status}" (href? := Option.some trustComparatorHref)

/--
The rendered strip: a labelled badge row. When the document emits a
formalization-metadata page, a blue `accent` badge linking to it is appended to
the row (it replaces the former trailing text link). Empty when no badge has data.
-/
def trustStripHtml (trust : TrustData) (detailsHref? : Option String := Option.none) :
    Output.Html :=
  let badges : Array Output.Html := Id.run do
    let mut out : Array Output.Html := #[]
    if let some n := trust.sorryCount then
      out := out.push (trustSorryBadge n)
    if !trust.axioms.isEmpty then
      out := out.push (trustAxiomsBadge trust.axioms)
    if !trust.reviewStatus.isEmpty then
      out := out.push (trustReviewBadge trust.reviewStatus)
    if let some cmp := trust.comparator then
      out := out.push (trustComparatorBadge cmp)
    return out
  if badges.isEmpty then
    .empty
  else
    -- Append the formalization-metadata badge only when the strip already carries a
    -- trust signal, preserving the "strip renders only with real trust data" rule.
    let badges : Array Output.Html :=
      match detailsHref? with
      | Option.some href =>
        badges.push <|
          trustBadgeHtml "formalization.yaml" "accent"
            (title? := Option.some "Project formalization.yaml metadata")
            (href? := Option.some href)
      | Option.none => badges
    {{
      <section class="bp_trust_strip" "aria-label"="Trust signals">
        <span class="bp_trust_strip_label">"Trust"</span>
        <div class="bp_summary_badge_row">{{badges}}</div>
      </section>
    }}

def trustStripCss := include_str "trust-strip.css"

def trustStripAssetBundle : BlueprintAssetBundle :=
  blueprintCssAssetBundle [trustStripCss]

open Verso Doc Elab Genre Manual in
block_extension Block.trustStrip (trust : TrustData) where
  data := toJson trust
  traverse _id data _contents := do
    -- Stash the trust payload so the generation-time `TrustPages` ExtraStep can
    -- emit one evidence page per configured badge. `data` is the block's already
    -- `toJson`ed `TrustData`.
    modify fun st => Informal.TraversalIndex.TrustData.saveData st data
    return none
  toTeX := none
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI _goB _id data _blocks => do
      let some trust ← Informal.ExtensionDecode.decode? (α := TrustData) data
          (fun err => s!"Malformed data in Block.trustStrip.toHtml ({err})")
        | pure .empty
      let st ← HtmlT.state
      pure (trustStripHtml trust (Informal.TraversalIndex.FormalizationPage.href? st))
  extraCss := trustStripAssetBundle.css
  extraJs := trustStripAssetBundle.js

open Verso Doc Elab in
/--
Read the artifacts named by the `verso.blueprint.trust.*` options into a
`TrustData` payload. `none` when both options are unset; a build error when a
set option names a missing or unparsable file. Reads happen at elaboration
time; relative paths resolve against the build CWD (the consumer package root).
-/
def elabTrustData? : PartElabM (Option TrustData) := do
  let opts ← Lean.getOptions
  let yamlPath : String :=
    opts.get verso.blueprint.trust.formalizationYaml.name
      verso.blueprint.trust.formalizationYaml.defValue
  let cmpPath : String :=
    opts.get verso.blueprint.trust.comparatorStatus.name
      verso.blueprint.trust.comparatorStatus.defValue
  if yamlPath.isEmpty && cmpPath.isEmpty then
    return Option.none
  let mut trust : TrustData := {}
  if !yamlPath.isEmpty then
    if !(← System.FilePath.pathExists yamlPath) then
      throwError "option 'verso.blueprint.trust.formalizationYaml' names a missing file (resolved against the build directory): {yamlPath}"
    match Informal.FormalizationYaml.parse (← IO.FS.readFile yamlPath) with
    | .error err => throwError "could not parse {yamlPath}: {err}"
    | .ok doc => trust := TrustData.ofFormalizationJson doc
  if !cmpPath.isEmpty then
    if !(← System.FilePath.pathExists cmpPath) then
      throwError "option 'verso.blueprint.trust.comparatorStatus' names a missing file (resolved against the build directory): {cmpPath}"
    match Json.parse (← IO.FS.readFile cmpPath) with
    | .error err => throwError "could not parse {cmpPath}: {err}"
    | .ok j => trust := { trust with comparator := Option.some (TrustComparator.ofJson j) }
  -- Embed the comparator's config JSON + Challenge Lean source verbatim on the
  -- evidence page. Unlike the two required options above, these degrade silently
  -- when their file is empty/missing (probe-and-degrade) and only attach when a
  -- comparator verdict exists.
  if let some cmp := trust.comparator then
    let cfgPath : String :=
      opts.get verso.blueprint.trust.comparatorConfig.name
        verso.blueprint.trust.comparatorConfig.defValue
    let chalPath : String :=
      opts.get verso.blueprint.trust.challengeFile.name
        verso.blueprint.trust.challengeFile.defValue
    let mut cmp := cmp
    if !cfgPath.isEmpty then
      if (← System.FilePath.pathExists cfgPath) then
        let raw ← IO.FS.readFile cfgPath
        -- Pretty-print when it parses as JSON; fall back to the raw file text.
        let pretty := match Json.parse raw with
          | .ok j => j.pretty
          | .error _ => raw
        cmp := { cmp with configJson := pretty }
    if !chalPath.isEmpty then
      if (← System.FilePath.pathExists chalPath) then
        cmp := { cmp with challengeSource := (← IO.FS.readFile chalPath) }
    trust := { trust with comparator := Option.some cmp }
  return Option.some trust

end Informal.Commands
