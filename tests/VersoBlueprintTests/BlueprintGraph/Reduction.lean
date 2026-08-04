/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import VersoBlueprintTests.BlueprintGraph.Shared

namespace Verso.VersoBlueprintTests.BlueprintGraph.Reduction

open Lean
open Informal
open Informal.Graph
open Verso.VersoBlueprintTests.BlueprintGraph.Shared

/-- A dependency use-ref for `label` (manual/regular by default). -/
def useRef (label : Name) : Data.UseRef := { label }

/-- A minimal graph node carrying `deps`/`proofDeps` plus their in-sync use-refs
(the DOT emitter reads intent/origin off the merged use-refs). -/
def gnode (label : Name) (deps : Array Name := #[]) (proofDeps : Array Name := #[]) :
    GraphNode String :=
  { label
    deps
    proofDeps
    statementUses := deps.map useRef
    proofUses := proofDeps.map useRef
    fillcolor := "#ffffff" }

/-- A minimal `NodeData` for `GraphData`-level tests. `toGraphNode` derives the
drawn deps from `statementUses`/`proofUses`, so set those. -/
def dnode (label : Name) (deps : Array Name := #[]) (proofDeps : Array Name := #[]) :
    NodeData :=
  { label
    title := toString label
    displayLabel := toString label
    previewKey := toString label
    statementUses := deps.map useRef
    proofUses := proofDeps.map useRef
    visual := { fillcolor := "#ffffff" } }

/-- Does node `label` in `g` have exactly these statement deps (order-insensitive)? -/
def depsAre (g : Graph String) (label : Name) (expected : Array Name) : Bool :=
  hasNodeWith g label fun n =>
    n.deps.size == expected.size && expected.all (n.deps.contains ·)

def proofDepsAre (g : Graph String) (label : Name) (expected : Array Name) : Bool :=
  hasNodeWith g label fun n =>
    n.proofDeps.size == expected.size && expected.all (n.proofDeps.contains ·)

/-- The DOT edge line substring for a drawn `dep -> node` edge. -/
def edgeStr (dep node : Name) : String := s!"\"{dep}\" -> \"{node}\""

/-! ## Diamond: the long side of a diamond is redundant.

`d` depends on `a`, `b`, `c`; `b`,`c` depend on `a`. The direct `a → d` edge is
implied by `a → b → d`, so it is dropped; `b → d`, `c → d`, `a → b`, `a → c` stay. -/

def diamond : Graph String := #[
  gnode `a,
  gnode `b (deps := #[`a]),
  gnode `c (deps := #[`a]),
  gnode `d (deps := #[`a, `b, `c])
]

/-- info: true -/
#guard_msgs in
#eval
  let reduced := transitiveReduce diamond
  -- `a → d` dropped; the other four edges survive.
  depsAre reduced `d #[`b, `c] &&
  depsAre reduced `b #[`a] &&
  depsAre reduced `c #[`a] &&
  -- Reduction lives in the DOT layer: the drawn edge disappears there …
  (graphToDot diamond).contains (edgeStr `a `d) &&
  !(graphToDot (transitiveReduce diamond)).contains (edgeStr `a `d) &&
  (graphToDot (transitiveReduce diamond)).contains (edgeStr `a `b) &&
  (graphToDot (transitiveReduce diamond)).contains (edgeStr `b `d) &&
  -- … while the PUBLIC edge list (edgesForGraph) still reports every edge.
  (edgesForGraph diamond).any (fun e => e.source == `a && e.target == `d)

/-! ## Union semantics: a redundant path may mix statement and proof edges. -/

-- Direct edge is a statement dep; witness path uses a proof edge (`a →stmt b →proof d`).
def mixedDiamondStmt : Graph String := #[
  gnode `a,
  gnode `b (deps := #[`a]),
  gnode `d (deps := #[`a]) (proofDeps := #[`b])
]

-- Direct edge is a proof dep; witness path uses a statement edge (`a →stmt b →stmt d`).
def mixedDiamondProof : Graph String := #[
  gnode `a,
  gnode `b (deps := #[`a]),
  gnode `d (deps := #[`b]) (proofDeps := #[`a])
]

/-- info: true -/
#guard_msgs in
#eval
  let r1 := transitiveReduce mixedDiamondStmt
  let r2 := transitiveReduce mixedDiamondProof
  -- Statement `a → d` dropped, proof `b → d` kept.
  depsAre r1 `d #[] && proofDepsAre r1 `d #[`b] &&
  -- Proof `a → d` dropped, statement `b → d` kept.
  depsAre r2 `d #[`b] && proofDepsAre r2 `d #[]

/-! ## Both edge families of a redundant pair drop together, use-refs in sync. -/

def bothFamily : Graph String := #[
  gnode `a,
  gnode `b (deps := #[`a]),
  gnode `d (deps := #[`a, `b]) (proofDeps := #[`a])
]

/-- info: true -/
#guard_msgs in
#eval
  let reduced := transitiveReduce bothFamily
  -- `a → d` is redundant in both families ⇒ removed from statement AND proof deps …
  depsAre reduced `d #[`b] &&
  proofDepsAre reduced `d #[] &&
  -- … and from the parallel use-ref arrays that feed per-edge styling.
  hasNodeWith reduced `d (fun n =>
    n.statementUses.map (·.label) == #[(`b : Name)] &&
    n.proofUses.isEmpty)

/-! ## Unknown (out-of-graph) deps are never dropped: only known redundancies are. -/

def unknownDep : Graph String := #[
  gnode `a,
  gnode `b (deps := #[`a]),
  gnode `d (deps := #[`a, `b, `ext])
]

/-- info: true -/
#guard_msgs in
#eval
  let reduced := transitiveReduce unknownDep
  -- `a` (redundant) dropped; `b` and the unknown `ext` kept.
  hasNodeWith reduced `d fun n =>
    !n.deps.contains `a && n.deps.contains `b && n.deps.contains `ext

/-! ## Cycles terminate (the witness DFS seeds `d`, so it never re-enters it). -/

-- 2-cycle: neither edge is redundant (each source has one successor).
def twoCycle : Graph String := #[
  gnode `a (deps := #[`b]),
  gnode `b (deps := #[`a])
]

-- 3-cycle with a chord `a → c`, implied by `a → b → c`, so the chord drops.
def threeCycleChord : Graph String := #[
  gnode `a (deps := #[`c]),
  gnode `b (deps := #[`a]),
  gnode `c (deps := #[`a, `b])
]

/-- info: true -/
#guard_msgs in
#eval
  let tc := transitiveReduce twoCycle
  let cc := transitiveReduce threeCycleChord
  -- 2-cycle unchanged.
  depsAre tc `a #[`b] && depsAre tc `b #[`a] &&
  -- Chord `a → c` dropped; the cycle edges `a → b` (via b.deps) and `c → a` stay.
  depsAre cc `c #[`b] && depsAre cc `b #[`a] && depsAre cc `a #[`c]

/-! ## `mkGraphVariants`: reduced `dot` + `dotFull` only when edges were dropped. -/

def chain : Graph String := #[
  gnode `a,
  gnode `b (deps := #[`a]),
  gnode `c (deps := #[`b])
]

/-- info: true -/
#guard_msgs in
#eval
  match (mkGraphVariants diamond {} {}).find? (·.key == "full") with
  | none => false
  | some v =>
    -- Reduction dropped `a → d`, so `dotFull` is present and differs from `dot`.
    v.dotFull.isSome &&
    v.dot != v.dotFull.getD "" &&
    !v.dot.contains (edgeStr `a `d) &&
    (v.dotFull.getD "").contains (edgeStr `a `d)

/-- info: true -/
#guard_msgs in
#eval
  match (mkGraphVariants chain {} {}).find? (·.key == "full") with
  | none => false
  -- Nothing redundant in a linear chain ⇒ no `dotFull` payload.
  | some v => v.dotFull.isNone

/-! ## `GraphData.toDotWith`: reduced by default, full with `allEdges := true`. -/

def diamondData : GraphData :=
  { nodes := #[
      dnode `a,
      dnode `b (deps := #[`a]),
      dnode `c (deps := #[`a]),
      dnode `d (deps := #[`a, `b, `c])
    ] }

/-- info: true -/
#guard_msgs in
#eval
  !diamondData.toDotWith.contains (edgeStr `a `d) &&
  (diamondData.toDotWith (allEdges := true)).contains (edgeStr `a `d)

/-! ## Header carries the unconditional layout knobs on every graph. -/

/-- info: true -/
#guard_msgs in
#eval
  Informal.Graph.graphDotHeader.contains "newrank=true;" &&
  Informal.Graph.graphDotHeader.contains "concentrate=true;"

end Verso.VersoBlueprintTests.BlueprintGraph.Reduction
