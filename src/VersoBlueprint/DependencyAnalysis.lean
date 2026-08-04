/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Emilio J. Gallego Arias, Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean
import VersoBlueprint.Environment

/-!
LeanArchitect-style automatic dependency inference for Verso Blueprint.

LeanArchitect recursively expands untagged Lean constants until it reaches
blueprint nodes. Verso Blueprint uses a document-first variant: it scans direct
constants from compiled declarations and maps each associated Lean declaration
to its Blueprint labels.
-/

namespace Informal

open Lean

namespace DependencyAnalysis

register_option verso.blueprint.autoDeps : Bool := {
  defValue := false
  descr := "Enable automatic Blueprint dependency inference by default"
}

/--
Dependency labels inferred from a compiled Lean declaration.

The analysis is intentionally direct: it scans constants mentioned by the
declaration's type and body, but it does not recursively expand untagged helper
declarations. Untagged constants are implementation details unless authors tag
them with `@[blueprint]` or add a manual dependency edge.
-/
structure InferredDeps where
  statement : Array Data.Label := #[]
  proof : Array Data.Label := #[]
deriving Inhabited, Repr

structure InferredUseRefs where
  statement : Array Data.UseRef := #[]
  proof : Array Data.UseRef := #[]
deriving Inhabited, Repr

def enabled (opts : Options) (local? : Option Bool) : Bool :=
  local?.getD (verso.blueprint.autoDeps.get opts)

def pushLabelUnique (labels : Array Data.Label) (label : Data.Label) :
    Array Data.Label :=
  if labels.contains label then labels else labels.push label

def automaticUseRef (label : Data.Label) : Data.UseRef :=
  { label, origin := .automatic }

def sortLabels (labels : Array Data.Label) : Array Data.Label :=
  labels.qsort fun a b => a.toString < b.toString

def InferredDeps.merge (current incoming : InferredDeps) : InferredDeps :=
  {
    statement := incoming.statement.foldl pushLabelUnique current.statement
    proof := incoming.proof.foldl pushLabelUnique current.proof
  }

private def automaticUseRefs (labels : Array Data.Label) : Array Data.UseRef :=
  (sortLabels labels).foldl (init := #[]) fun acc label =>
    Data.UseRef.pushMergeByLabel acc (automaticUseRef label)

private def removeSelfLabel (currentLabel? : Option Data.Label) (labels : Array Data.Label) :
    Array Data.Label :=
  match currentLabel? with
  | none => labels
  | some currentLabel => labels.filter (· != currentLabel)

def InferredDeps.toUseRefs (deps : InferredDeps)
    (statementManual : Array Data.UseRef := #[]) (currentLabel? : Option Data.Label := none) :
    InferredUseRefs :=
  let statementLabels := removeSelfLabel currentLabel? deps.statement
  let proofLabels := removeSelfLabel currentLabel? deps.proof
  let statement := Data.UseRef.mergeByLabel (automaticUseRefs statementLabels) statementManual
  let statementLabels := Data.UseRef.labels statement
  let proofLabels := proofLabels.filter fun label => !statementLabels.contains label
  {
    statement
    proof := automaticUseRefs proofLabels
  }

private def directLabelsForExpr (root : Name) (expr : Expr) : CoreM (Array Data.Label) := do
  let root := root.eraseMacroScopes
  expr.getUsedConstants.foldlM (init := #[]) fun labels decl => do
    let decl := decl.eraseMacroScopes
    if decl == root then
      return labels
    else
      let declLabels ← Environment.labelsForLeanDecl decl
      return declLabels.foldl pushLabelUnique labels

private def directBodyLabels (root : Name) (info : ConstantInfo) : CoreM (Array Data.Label) := do
  match info with
  | .axiomInfo _ => return #[]
  | .defnInfo info => directLabelsForExpr root info.value
  | .thmInfo info => directLabelsForExpr root info.value
  | .opaqueInfo info => directLabelsForExpr root info.value
  | .quotInfo _ => return #[]
  | .ctorInfo info => directLabelsForExpr root info.type
  | .recInfo info => directLabelsForExpr root info.type
  | .inductInfo info =>
    info.ctors.foldlM (init := #[]) fun labels ctor => do
      match (← getEnv).find? ctor with
      | some (.ctorInfo ctorInfo) =>
        let ctorLabels ← directLabelsForExpr root ctorInfo.type
        return ctorLabels.foldl pushLabelUnique labels
      | _ => return labels

def infer (decl : Name) (info : ConstantInfo) : CoreM InferredDeps := do
  let decl := decl.eraseMacroScopes
  let statement ← directLabelsForExpr decl info.type
  let proof ← directBodyLabels decl info
  return { statement, proof }

def inferDecl? (decl : Name) : CoreM InferredDeps := do
  let decl := decl.eraseMacroScopes
  match (← getEnv).find? decl with
  | some info => infer decl info
  | none => pure {}

def inferDecls (decls : Array Name) : CoreM InferredDeps :=
  decls.foldlM (init := {}) fun acc decl => do
    return acc.merge (← inferDecl? decl)

def inferExternalRefs (refs : Array Data.ExternalRef) : CoreM InferredDeps :=
  inferDecls (refs.filter (·.present) |>.map (·.canonical))

private def payloadWithUseRefs
    (ref : Syntax) (useRefs : Array Data.UseRef) (current? : Option Data.InformalData) :
    Option Data.InformalData :=
  if useRefs.isEmpty then
    current?
  else
    match current? with
    | some payload =>
      some { payload with deps := Data.UseRef.mergeByLabel payload.deps useRefs }
    | none =>
      some { stx := ref, deps := useRefs }

/-! ## Authored-edge validation

With `autoDeps` off — the default, and what a hand-written blueprint wants — the
dependency graph's edges are entirely author-asserted, while the ground truth sits
right there in the compiled terms. Nothing previously compared the two.

This pass does, without changing the graph: for every node with associated Lean, it
diffs the authored `uses` edges against the constants the declarations actually
mention.

* An edge the code has but the author did not draw is a **build warning**: the
  reading order the graph presents omits a real dependency.
* An edge the author drew that the code does not exhibit is *not* an error — it is
  routinely how a blueprint records that a result depends on an earlier one
  mathematically even though the Lean proof reaches it by a different route. It is
  reported as an **informal-level edge** so the count is visible rather than assumed
  away.

Reporting only. The graph keeps the curated narrative the author wrote.
-/

/-- Divergence between the authored `uses` graph and the const-level dependencies of
the associated Lean declarations. -/
structure EdgeAudit where
  /-- Nodes with associated Lean declarations that were compared. -/
  nodesChecked : Nat := 0
  /-- `"node → dep"` edges the Lean terms exhibit but the author did not declare. -/
  inferredUndeclared : Array String := #[]
  /-- `"node → dep"` edges the author declared that the Lean terms do not exhibit —
  legitimate informal-level edges, reported for visibility. -/
  declaredNotInferred : Array String := #[]
deriving Inhabited, Repr, ToJson, FromJson, Quote

/--
Diff every blueprint node's authored `uses` edges against the const-level
dependencies inferred from its associated Lean declarations.

A no-op returning an empty audit when `autoDeps` is *on* (the edges are then
machine-derived by construction, so there is nothing to diff) or when no node has
associated Lean. Never fails: an unresolvable declaration simply contributes no
inferred edges.
-/
def auditAuthoredEdges (autoDepsEnabled : Bool) : CoreM EdgeAudit := do
  if autoDepsEnabled then return {}
  let st := Environment.informalExt.getState (← getEnv)
  let mut nodesChecked := 0
  let mut inferredUndeclared : Array String := #[]
  let mut declaredNotInferred : Array String := #[]
  for (label, node) in st.data.toList do
    let refs := node.externalRefs.filter (·.present)
    if refs.isEmpty then continue
    nodesChecked := nodesChecked + 1
    let authored : Array Data.Label :=
      (node.statement.map (·.dependencyLabels) |>.getD #[]) ++
      (node.proof.map (·.dependencyLabels) |>.getD #[])
    let inferred ← inferExternalRefs refs
    let inferredLabels := (inferred.statement ++ inferred.proof).filter (· != label)
    for dep in inferredLabels do
      unless authored.contains dep do
        let edge := s!"{label} → {dep}"
        unless inferredUndeclared.contains edge do
          inferredUndeclared := inferredUndeclared.push edge
    for dep in authored do
      unless inferredLabels.contains dep || dep == label do
        let edge := s!"{label} → {dep}"
        unless declaredNotInferred.contains edge do
          declaredNotInferred := declaredNotInferred.push edge
  return { nodesChecked, inferredUndeclared, declaredNotInferred }

def attachInferredUseRefs (label : Data.Label) (ref : Syntax) (useRefs : InferredUseRefs) :
    CoreM Unit := do
  if useRefs.statement.isEmpty && useRefs.proof.isEmpty then
    pure ()
  else
    Environment.modifyDataForLabel label fun data => do
      let data :=
        match data.get? label with
        | some node =>
          let statement := payloadWithUseRefs ref useRefs.statement node.statement
          let proof := payloadWithUseRefs ref useRefs.proof node.proof
          data.insert label { node with statement, proof }
        | none =>
          let statement := payloadWithUseRefs ref useRefs.statement none
          let proof := payloadWithUseRefs ref useRefs.proof none
          data.insert label { statement, proof }
      return data

end DependencyAnalysis

end Informal
