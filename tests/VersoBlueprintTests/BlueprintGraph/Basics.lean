/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintGraph.Shared

namespace Verso.VersoBlueprintTests.BlueprintGraph.Basics

open Lean
open Informal
open Informal.Data
open Informal.Environment
open Informal.Graph
open Verso.VersoBlueprintTests.BlueprintGraph.Shared

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let env ← getEnv
    let some axiomInfo := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Shared.external_axiom_decl
      | return false
    let some defInfo := env.find? `Verso.VersoBlueprintTests.BlueprintGraph.Shared.external_def_decl
      | return false
    let axiomStatus := ConstantInfo.blueprintProvedStatus axiomInfo (allowOpaque := true)
    let defStatus := ConstantInfo.blueprintProvedStatus defInfo (allowOpaque := true)
    pure (
      axiomStatus == .axiomLike &&
      defStatus == .proved
    )

/-- info: true -/
#guard_msgs in
#eval
  let status : Data.ProvedStatus :=
    .containsSorry #[{ location := .statement, refs? := some 2 }, { location := .proof, refs? := some 3 }]
  Data.NodeKind.definition.isTheoremLike = false &&
  Data.NodeKind.proposition.isTheoremLike &&
  Data.NodeKind.theorem.isTheoremLike &&
  status.sorryLocationText = "in statement and proof" &&
  status.statusLabel = "contains sorry" &&
  status.sorryRefCounts = (2, 3)

def nestedPopState : Environment.State :=
  {
    data := (mkState [(`outer, { kind := .definition, statement := some (mkInformal #[]) })]).data
    stack := [
      { label := `inner, kind := .statement .lemma },
      { label := `outer, kind := .statement .definition }
    ]
  }

/-- info: true -/
#guard_msgs in
#eval
  match nestedPopState.popNested? with
  | none => false
  | some st =>
    let labels : Array String := st.data.toArray.map (fun (entry : Name × Node) => toString entry.1)
    st.stack.length == 1 &&
    (match st.stack.head? with | some frame => toString frame.label == "outer" | none => false) &&
    st.data.size == nestedPopState.data.size &&
    labels.contains "outer" &&
    !labels.contains "inner"

end Verso.VersoBlueprintTests.BlueprintGraph.Basics
