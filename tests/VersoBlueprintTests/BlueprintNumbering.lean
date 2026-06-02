/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoBlueprint.Informal.Block.Store
import VersoManual

namespace Verso.VersoBlueprintTests.BlueprintNumbering

open Lean
open Informal
open Verso.Genre Manual

private def emptyState : TraverseState :=
  TraverseState.initialize default

/-- info: true -/
#guard_msgs in
#eval
  let base : BlockData := {
    kind := .statement .definition
    label := `bp.numbering.base
    count := 4
  }
  let localBlock := { base with numberingMode := .local }
  let subBlock := { base with numberingMode := .sub, partPrefix := some "3" }
  let globalBlock := { base with numberingMode := .global, globalCount := some 17 }
  localBlock.displayNumber emptyState == "4" &&
  subBlock.displayNumber emptyState == "3.4" &&
  globalBlock.displayNumber emptyState == "17" &&
  subBlock.displayTitle emptyState == "Definition 3.4"

/-- info: true -/
#guard_msgs in
#eval
  let base : BlockData := {
    kind := .statement .theorem
    label := `bp.numbering.sectionSub
    count := 2
  }
  let subBlock := { base with numberingMode := .sub, partPrefix := some "1.3" }
  subBlock.displayNumber emptyState == "1.3.2" &&
  subBlock.displayTitle emptyState == "Theorem 1.3.2"

/-- info: true -/
#guard_msgs in
#eval
  let stored : BlockData := {
    kind := .statement .lemma
    label := `bp.numbering.storedSub
    count := 9
    numberingMode := .sub
    partPrefix := some "1.3"
  }
  let state :=
    Informal.TraversalIndex.Nodes.saveData
      (TraverseState.initialize default)
      stored.label
      (toJson stored.toStoredData)
  let renderData := { stored with count := 120 }
  renderData.displayNumber state == "1.3.9" &&
  renderData.displayTitle state == "Lemma 1.3.9"

/-- info: true -/
#guard_msgs in
#eval
  let (first, state) := reserveSectionBlockNumber emptyState "1.3"
  let (second, state) := reserveSectionBlockNumber state "1.3"
  let (other, _) := reserveSectionBlockNumber state "1.4"
  first == 1 &&
  second == 2 &&
  other == 1

/-- info: true -/
#guard_msgs in
#eval
  let stored : BlockData := {
    kind := .statement .theorem
    label := `bp.numbering.stored
    count := 5
    numberingMode := .global
    partPrefix := some "2"
    globalCount := some 11
  }
  let state :=
    Informal.TraversalIndex.Nodes.saveData
      (TraverseState.initialize default)
      stored.label
      (toJson stored.toStoredData)
  let proofRef : BlockData := {
    kind := .proof
    label := stored.label
    count := stored.count
  }
  proofRef.displayNumber state == "11" &&
  proofRef.displayTitle state == "Proof 11"

end Verso.VersoBlueprintTests.BlueprintNumbering
