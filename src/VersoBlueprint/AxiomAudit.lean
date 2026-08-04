/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Data
import VersoBlueprint.Environment
import VersoBlueprint.DeclRegistry
import VersoBlueprint.FormalizationYaml

/-!
# Build-time axiom audit

A blueprint site makes two kinds of claim about the formalization it presents: the
ones a checker produced (a comparator verdict, a kernel replay) and the ones a
human typed into `formalization.yaml`. This module makes the second kind
*falsifiable* at build time.

It runs `Lean.collectAxioms` — the same transitive closure `#print axioms` reports
— over three declaration sets, at elaboration, where the environment is available:

* every declaration a blueprint node wires with `(lean := …)`;
* every project declaration in the declaration registry's enumeration; and
* every declaration *named* in `formalization.yaml` (main results and the
  alignment table).

The results are then checked against the YAML's claims. A claim the environment
**contradicts** is a hard build error: a page asserting "0 sorries, standard axioms
only" over a development that carries `sorryAx` is worse than no page at all.
A declaration the audit finds *dirty* but the YAML never mentions is a build
**warning** plus a badge — unless `verso.blueprint.trust.requireAuditClean` is set,
which promotes it to an error for projects that want the stricter contract.

Over-claiming a defect (declaring more sorries or more axioms than exist) is only
ever a warning: it is stale bookkeeping, not a false assurance.

`sorryAx` in a closure is transitive evidence — a theorem whose own body has no
literal `sorry` but which invokes a sorried lemma reports it. Both snapshot layers
(`ExternalRefSnapshot`, `DeclRegistry`) already fold that into `provedStatus`, so
every existing roll-up inherits it; this module is the *reporting* layer.
-/

namespace Informal.AxiomAudit

open Lean

/-- The axioms every kernel-checked Mathlib development is expected to use. Anything
else in a closure is worth a reader's attention — not necessarily wrong, but not
covered by the usual "classical mathematics" understanding either. -/
def standardAxioms : List String := ["propext", "Classical.choice", "Quot.sound"]

/-- The members of `names` that are not one of the three standard axioms. -/
def nonstandardAxioms (names : List String) : List String :=
  names.filter (fun a => !standardAxioms.contains a)

/-- The `sorryAx` constant: its presence anywhere in a closure means the proof is
incomplete, transitively. -/
def sorryAxiom : String := "sorryAx"

/-- One declaration's audited axiom footprint. -/
structure DeclAxioms where
  /-- Fully-qualified declaration name, as displayed. -/
  name : String
  /-- Sorted transitive axiom closure. -/
  axioms : Array String := #[]
  /-- Whether the closure contains `sorryAx`. -/
  sorried : Bool := false
  /-- Closure members outside the three standard axioms, `sorryAx` excluded (it is
  reported through `sorried`). -/
  nonstandard : Array String := #[]
deriving Inhabited, Repr, ToJson, FromJson, Quote

/-- The audit's findings, carried into the trust payload so the trust-model page,
the audit page, and the dashboard strip all report the *same run's* evidence rather
than each recomputing (or restating the YAML). -/
structure Summary where
  /-- How many declarations had their axiom closure computed. -/
  checked : Nat := 0
  /-- Audited declarations whose closure contains `sorryAx`. -/
  sorried : Array String := #[]
  /-- Audited declarations using axioms beyond the standard three. -/
  nonstandard : Array DeclAxioms := #[]
  /-- Footprints of the declarations `formalization.yaml` names as main results —
  the audit's headline evidence. -/
  mainResults : Array DeclAxioms := #[]
  /-- The union of all axioms seen across the audited set, sorted. -/
  allAxioms : Array String := #[]
  /-- Stale-bookkeeping notes: the YAML over-claims a defect, or a declaration is
  dirty but unmentioned. Warnings, never errors on their own. -/
  warnings : Array String := #[]
  /-- Whether the audit found nothing to report (no sorries, no nonstandard axioms,
  no warnings). -/
  clean : Bool := true
  /-- Whether an audit actually ran (`false` ⇒ no declarations were in scope, so
  the surfaces must say "not audited" rather than "clean"). -/
  ran : Bool := false
deriving Inhabited, Repr, ToJson, FromJson, Quote

/-- Audit one declaration. Unknown names yield `none` so callers can report them as
unresolved rather than silently as clean. -/
def declAxioms? (name : Name) : CoreM (Option DeclAxioms) := do
  let env ← getEnv
  if (env.find? name).isNone then return none
  let axs := (← Lean.collectAxioms name).map toString
  let axs := axs.qsort (· < ·)
  let sorried := axs.contains sorryAxiom
  let nonstandard :=
    axs.filter fun a => a != sorryAxiom && !standardAxioms.contains a
  return some { name := name.toString, axioms := axs, sorried, nonstandard }

/-- Every declaration wired to a blueprint node through `(lean := …)` or
`@[blueprint]`, de-duplicated. -/
def blueprintRefNames : CoreM (Array Name) := do
  let st := Informal.Environment.informalExt.getState (← getEnv)
  let mut seen : NameSet := {}
  let mut out : Array Name := #[]
  for (_label, node) in st.data.toList do
    for ref in node.externalRefs do
      let n := ref.canonical.eraseMacroScopes
      unless seen.contains n do
        seen := seen.insert n
        out := out.push n
  return out

/-- Every project declaration the registry enumerates (public and `private`), or an
empty array when the project boundary is unresolvable (no authored `(lean := …)`
reference with local source). -/
def projectDeclNames : CoreM (Array Name) := do
  let roots ← Informal.DeclRegistry.projectModuleRoots
  if roots.isEmpty then return #[]
  return (← Informal.DeclRegistry.enumerateProjectDecls roots (includePrivate := true)).map (·.1)

/-! ## `formalization.yaml` claims -/

private def strOf? (j : Json) (key : String) : Option String :=
  match (j.getObjVal? key).toOption with
  | some (Json.str s) =>
    let t := Informal.FormalizationYaml.trim s
    if t.isEmpty then none else some t
  | _ => none

private def natOf? (j : Json) (key : String) : Option Nat :=
  (j.getObjValAs? Nat key).toOption

private def arrOf (j : Json) (key : String) : Array Json :=
  match (j.getObjVal? key).toOption with
  | some (Json.arr a) => a
  | _ => #[]

private def strArrOf (j : Json) (key : String) : Array String :=
  (arrOf j key).filterMap fun v =>
    match v with
    | Json.str s => some (Informal.FormalizationYaml.trim s)
    | _ => none

/-- Split a comma-separated declaration list (the alignment table's `lean:` field). -/
private def splitDeclList (csv : String) : Array String :=
  ((csv.splitOn ",").map Informal.FormalizationYaml.trim).filter (!·.isEmpty) |>.toArray

/-- One claim the YAML makes about a specific declaration. -/
private structure DeclClaim where
  /-- Where in the document the claim lives, for the error message. -/
  origin : String
  decl : String
  /-- Declared sorry count for this declaration, when the YAML states one. -/
  sorryCount? : Option Nat := none
  /-- Declared axiom list for this declaration, when the YAML states one. -/
  axioms? : Option (Array String) := none
  /-- Declared alignment status (`proved`, `stated`, …), when present. -/
  status? : Option String := none
  /-- Whether this claim came from `status.main_results` (headline evidence). -/
  isMainResult : Bool := false

/-- Every per-declaration claim in a parsed `formalization.yaml`. -/
private def declClaims (doc : Json) : Array DeclClaim := Id.run do
  let mut out : Array DeclClaim := #[]
  if let some status := (doc.getObjVal? "status").toOption then
    for r in arrOf status "main_results" do
      if let some decl := strOf? r "declaration" then
        out := out.push {
          origin := "status.main_results"
          decl
          sorryCount? := natOf? r "sorry_count"
          axioms? := if (r.getObjVal? "axioms").toOption.isSome then some (strArrOf r "axioms") else none
          isMainResult := true
        }
  if let some al := (doc.getObjVal? "alignment").toOption then
    for s in arrOf al "statements" do
      if let some csv := strOf? s "lean" then
        for decl in splitDeclList csv do
          out := out.push {
            origin := "alignment.statements"
            decl
            status? := strOf? s "status"
          }
  return out

/-! ## The audit -/

/-- Format a declaration's closure for an error/warning message. -/
private def fmtAxioms (a : Array String) : String :=
  if a.isEmpty then "(none)" else String.intercalate ", " a.toList

/--
Run the axiom audit.

`yaml?` is the parsed `formalization.yaml` (from
`verso.blueprint.trust.formalizationYaml`); when absent only the environment-side
findings are produced and no claim can be contradicted.

Throws on a contradiction between the YAML and the environment — including a decl
name the YAML asserts something about that does not resolve, since an unresolvable
name means the claim is not merely wrong but unverifiable. `requireAuditClean`
additionally promotes "dirty but unclaimed" findings to errors.
-/
def run (yaml? : Option Json) (requireAuditClean : Bool := false) : CoreM Summary := do
  -- 1. Environment side: blueprint-wired decls ∪ project decls.
  let mut seen : NameSet := {}
  let mut targets : Array Name := #[]
  for n in (← blueprintRefNames) ++ (← projectDeclNames) do
    unless seen.contains n do
      seen := seen.insert n
      targets := targets.push n
  let mut checked : Nat := 0
  let mut sorried : Array String := #[]
  let mut nonstandard : Array DeclAxioms := #[]
  -- Kept as strings, deliberately: `collectAxioms` names arrive as strings and are
  -- compared against strings typed into `formalization.yaml`. Round-tripping them
  -- through `Name.mkSimple` would make a dotted name a *single* component, which
  -- re-prints escaped (`«Classical.choice»`) and matches nothing.
  let mut allAxioms : Std.HashSet String := {}
  let mut audited : Std.HashMap String DeclAxioms := {}
  for n in targets do
    if let some d ← declAxioms? n then
      checked := checked + 1
      audited := audited.insert d.name d
      for a in d.axioms do allAxioms := allAxioms.insert a
      if d.sorried then sorried := sorried.push d.name
      if !d.nonstandard.isEmpty then nonstandard := nonstandard.push d
  -- 2. `formalization.yaml` side: audit every named declaration and check its claims.
  let mut mainResults : Array DeclAxioms := #[]
  let mut warnings : Array String := #[]
  let mut errors : Array String := #[]
  let mut claimedSorried : NameSet := {}
  if let some doc := yaml? then
    for claim in declClaims doc do
      let name := claim.decl.toName
      let some d ← declAxioms? name
        | errors := errors.push
            s!"`formalization.yaml` ({claim.origin}) names the declaration '{claim.decl}', \
               which does not exist in the environment this site was built from. A claim about \
               a declaration that is not there cannot be checked — fix the name, or remove the row."
          continue
      if claim.isMainResult then
        mainResults := mainResults.push d
        checked := checked
      if let some declared := claim.sorryCount? then
        if declared == 0 && d.sorried then
          claimedSorried := claimedSorried.insert name
          errors := errors.push
            s!"`formalization.yaml` ({claim.origin}) declares sorry_count 0 for '{claim.decl}', \
               but its axiom closure contains `sorryAx` (transitively). Axioms: {fmtAxioms d.axioms}."
        else if declared > 0 && !d.sorried then
          warnings := warnings.push
            s!"`formalization.yaml` ({claim.origin}) declares sorry_count {declared} for \
               '{claim.decl}', but its axiom closure is free of `sorryAx`. Stale bookkeeping."
      if let some declaredAxioms := claim.axioms? then
        let undeclared := d.axioms.filter fun a =>
          a != sorryAxiom && !declaredAxioms.contains a
        unless undeclared.isEmpty do
          errors := errors.push
            s!"`formalization.yaml` ({claim.origin}) lists the axioms of '{claim.decl}' as \
               {fmtAxioms declaredAxioms}, but its closure also contains \
               {fmtAxioms undeclared}."
        let overDeclared := declaredAxioms.filter (!d.axioms.contains ·)
        unless overDeclared.isEmpty do
          warnings := warnings.push
            s!"`formalization.yaml` ({claim.origin}) lists axioms for '{claim.decl}' that its \
               closure does not use: {fmtAxioms overDeclared}."
      if let some st := claim.status? then
        if (st == "proved" || st == "verified" || st == "complete") && d.sorried then
          claimedSorried := claimedSorried.insert name
          errors := errors.push
            s!"`formalization.yaml` ({claim.origin}) marks '{claim.decl}' as \"{st}\", but its \
               axiom closure contains `sorryAx` (transitively)."
    -- Project-wide `status.sorry_count`: only the over-claiming direction is an error.
    if let some status := (doc.getObjVal? "status").toOption then
      if let some declared := natOf? status "sorry_count" then
        if declared == 0 && !sorried.isEmpty then
          errors := errors.push
            s!"`formalization.yaml` declares status.sorry_count 0, but the axiom audit found \
               `sorryAx` in the closure of {sorried.size} audited declaration(s): \
               {fmtAxioms (sorried.extract 0 (min sorried.size 8))}."
      let declaredProjectAxioms := strArrOf status "axioms"
      unless declaredProjectAxioms.isEmpty do
        let all := allAxioms.toArray.qsort (· < ·)
        let undeclared := all.filter fun a => a != sorryAxiom && !declaredProjectAxioms.contains a
        unless undeclared.isEmpty do
          errors := errors.push
            s!"`formalization.yaml` declares status.axioms as \
               {fmtAxioms declaredProjectAxioms}, but the audit found additional axioms in the \
               development's closure: {fmtAxioms undeclared}."
  -- 3. Dirty-but-unclaimed declarations: warning by default, error under the strict option.
  let uncovered := sorried.filter fun n => !claimedSorried.contains n.toName
  unless uncovered.isEmpty do
    let msg :=
      s!"axiom audit: {uncovered.size} declaration(s) carry `sorryAx` in their transitive \
         closure and are not declared as incomplete anywhere in `formalization.yaml`: \
         {fmtAxioms (uncovered.extract 0 (min uncovered.size 12))}."
    if requireAuditClean then errors := errors.push msg else warnings := warnings.push msg
  unless nonstandard.isEmpty do
    let names := nonstandard.map (·.name)
    let msg :=
      s!"axiom audit: {nonstandard.size} declaration(s) depend on axioms beyond \
         {fmtAxioms standardAxioms.toArray}: \
         {fmtAxioms (names.extract 0 (min names.size 12))}."
    if requireAuditClean then errors := errors.push msg else warnings := warnings.push msg
  unless errors.isEmpty do
    throwError "showcase axiom audit FAILED:\n{String.intercalate "\n" errors.toList}"
  for w in warnings do
    logWarning w
  let allAxiomsArr := allAxioms.toArray.qsort (· < ·)
  return {
    checked
    sorried
    nonstandard
    mainResults
    allAxioms := allAxiomsArr
    warnings
    clean := sorried.isEmpty && nonstandard.isEmpty && warnings.isEmpty
    ran := checked > 0
  }

end Informal.AxiomAudit
