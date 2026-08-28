/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintGraph.Shared

namespace Verso.VersoBlueprintTests.BlueprintGraph.Groups

open Lean
open Informal.Graph
open Verso.VersoBlueprintTests.BlueprintGraph.Shared

def groupedGraphInput : Informal.Graph.Graph String := #[
  {
    label := `ga_stmt
    deps := #[`gb_source]
    proofDeps := #[]
    parent? := some `group_alpha
    shape := "ellipse"
    fillcolor := proofBackgroundFormalizedColor
    color := statementBorderFormalizedColor
    fontcolor := "#111827"
  },
  {
    label := `ga_proof
    deps := #[]
    proofDeps := #[`gb_source]
    parent? := some `group_alpha
    shape := "ellipse"
    fillcolor := proofBackgroundReadyColor
    color := statementBorderReadyColor
    fontcolor := "#111827"
  },
  {
    label := `gb_source
    deps := #[]
    proofDeps := #[]
    parent? := some `group_beta
    shape := "box"
    fillcolor := proofBackgroundFormalizedAncColor
    color := statementBorderFormalizedColor
    fontcolor := "#ffffff"
  },
  {
    label := `gb_aux
    deps := #[]
    proofDeps := #[]
    parent? := some `group_beta
    shape := "ellipse"
    fillcolor := proofBackgroundFormalizedColor
    color := statementBorderFormalizedColor
    fontcolor := "#111827"
  }
]

def groupedGraphTitles : Array (Name × String) := #[
  (`group_alpha, "Readable Alpha Group Title"),
  (`group_beta, "Readable Beta Source Group")
]

def groupedGraphTitleMap : Lean.NameMap String :=
  groupedGraphTitles.foldl (init := ({} : Lean.NameMap String)) fun acc (group, title) =>
    acc.insert group title

def groupedOverview : Informal.Graph.Graph String :=
  Informal.Graph.mkParentOverviewGraph groupedGraphInput #[`group_alpha, `group_beta] groupedGraphTitleMap

def groupedGraphData : Informal.Graph.GraphData :=
  {
    nodes := #[]
    edges := Informal.Graph.edgesForGraph groupedGraphInput
    groups := Informal.Graph.groupDataForGraph groupedGraphInput groupedGraphTitles
  }

def groupedVariants : Array Informal.Graph.GraphRenderVariant :=
  Informal.Graph.mkGraphVariants
    groupedGraphInput
    { direction := .TB, pack := true }
    groupedGraphTitleMap

/-- info: true -/
#guard_msgs in
#eval
  hasNodeWith groupedOverview `group_alpha (fun n =>
    n.shape == "tab" &&
    n.displayLabel? == some "Readable Alpha Group Title" &&
    n.deps.contains `group_beta &&
    n.proofDeps.contains `group_beta &&
    n.tooltip?.getD "" == "Group View: Readable Alpha Group Title (2 nodes)")

/-- info: true -/
#guard_msgs in
#eval
  graphNodeSvgId `group_alpha == "bp-node-group-005Falpha" &&
  match groupedVariants.find? (·.key == Informal.Graph.groupVariantKey) with
  | none => false
  | some variant =>
    let expectedId := graphNodeSvgId `group_alpha
    let expectedLabel := escapeDotString "Readable Alpha Group Title"
    let expectedVariantKey := s!"parent:{`group_alpha}"
    variant.selectOnNodeId.contains (expectedId, expectedVariantKey) &&
    variant.hoverOnNodeId.contains (expectedId, expectedVariantKey) &&
    variant.dot.contains s!"id=\"{expectedId}\"" &&
    variant.dot.contains s!"label=\"{expectedLabel}\"" &&
    !variant.dot.contains "label=\"group_alpha\""

/-- info: true -/
#guard_msgs in
#eval
  Informal.Graph.graphDotHeader |>.contains "pack=false;"

/-- info: true -/
#guard_msgs in
#eval
  Informal.Graph.graphDotHeader { direction := .TB, pack := true } |>.contains "pack=true;"

/-- info: true -/
#guard_msgs in
#eval
  groupedGraphData.edges.any (fun edge =>
    edge.source == `gb_source &&
    edge.target == `ga_stmt &&
    edge.axes == #[Informal.Graph.EdgeAxis.statement]) &&
  match groupedGraphData.groups.find? (·.label == `group_alpha) with
  | none => false
  | some group =>
    group.title == "Readable Alpha Group Title" &&
    group.declared &&
    group.children.contains `ga_stmt &&
    group.children.contains `ga_proof

/-! ## Scale cap (b): `maxFlatVariantNodes` skips the whole-graph variants above the cap. -/

-- Forced-low cap (1 < 4 nodes): the two whole-graph variants (`full`/`essential`) are
-- NOT generated, and the group overview leads so it becomes the default selected variant
-- (`graph.mjs` picks `variants[0]` when there is no `full` variant). The grouped fixture
-- has two group parents to fall back to.
/-- info: (true, "group") -/
#guard_msgs in
#eval
  let capped := Informal.Graph.mkGraphVariants groupedGraphInput
    { direction := .TB, pack := true } groupedGraphTitleMap
    (maxFlatVariantNodes := 1)
  (capped.all (fun v => v.key != "full" && v.key != Informal.Graph.essentialVariantKey),
   (capped[0]?.map (·.key)).getD "")

-- Below the cap (default 0 = unlimited) the flat variants are still present and lead.
/-- info: (true, true) -/
#guard_msgs in
#eval
  (groupedVariants.any (·.key == "full"),
   groupedVariants.any (·.key == Informal.Graph.essentialVariantKey))

/-! ## (d) `boundedNeighborhood`: radius-k neighborhood vs the full closure. -/

def chainNeighborhoodData : Informal.Graph.GraphData :=
  {
    nodes := #[]
    edges := #[
      { source := `n_a, target := `n_b },
      { source := `n_b, target := `n_c },
      { source := `n_c, target := `n_d }]
    groups := #[]
  }

-- Radius 1 from `n_b` reaches only its immediate neighbors in both directions
-- (`n_a`, `n_c`), not `n_d`; radius 0 returns the full ancestor ∪ self ∪ descendant
-- closure (all four).
/-- info: (true, true) -/
#guard_msgs in
#eval
  let r1 := chainNeighborhoodData.boundedNeighborhood `n_b 1
  let r0 := chainNeighborhoodData.boundedNeighborhood `n_b 0
  (r1.contains `n_a && r1.contains `n_b && r1.contains `n_c && !r1.contains `n_d,
   r0.contains `n_a && r0.contains `n_b && r0.contains `n_c && r0.contains `n_d)

/-! ## (e) `cappedNeighborhood`: the same neighborhood, bounded by node count. -/

def starNeighborhoodData : Informal.Graph.GraphData :=
  {
    nodes := #[]
    edges := #[
      { source := `hub, target := `t1 },
      { source := `hub, target := `t2 },
      { source := `hub, target := `t3 },
      { source := `hub, target := `t4 },
      { source := `hub, target := `t5 }]
    groups := #[]
  }

-- A 3-node cap over `hub`'s six-node radius-1 neighborhood keeps the focus declaration
-- plus two neighbors, and reports the other three as omitted — the omitted count is over
-- everything within the radius, not over where the walk stopped. `0` ⇒ no cap at all,
-- which must be exactly `boundedNeighborhood` with nothing omitted.
/-- info: (3, true, 3, 6, 0) -/
#guard_msgs in
#eval
  let (kept, omitted) := starNeighborhoodData.cappedNeighborhood `hub 1 3
  let (uncapped, uncappedOmitted) := starNeighborhoodData.cappedNeighborhood `hub 1 0
  (kept.toList.length, kept.contains `hub, omitted,
   uncapped.toList.length, uncappedOmitted)

end Verso.VersoBlueprintTests.BlueprintGraph.Groups
