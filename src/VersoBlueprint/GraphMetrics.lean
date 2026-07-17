/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Graph

/-!
Pure graph metrics over the master dependency `GraphData`.

Edges point from a dependency *source* to the dependent *target*
(`Informal.Graph.EdgeData`), so:

* `GraphData.forwardAdj` walks toward downstream dependents (descendants);
* `GraphData.reverseAdj` walks toward upstream dependencies (ancestors).

For each node we compute:

* `fanIn`  — in-degree: how many direct dependencies feed into the node
  (`|reverseAdj[label]|`);
* `fanOut` — out-degree: how many direct dependents the node feeds
  (`|forwardAdj[label]|`);
* `depth`  — longest dependency chain from a source (in-degree-0 node) *to* the
  node, counted in edges;
* `height` — longest chain from the node *to* a sink (out-degree-0 node);
* `onCriticalPath` — whether the node lies on the single longest chain chosen as
  the critical path.

`computeGraphMetrics` also returns that critical path (one longest chain in the
DAG). Depth/height are computed by memoized DFS with a cycle guard (a node
already on the current DFS stack contributes 0), so the functions stay total and
degrade gracefully on the rare cyclic input. `graph-metrics.json` is the
contract artifact consumed by the Wave 3 dashboard.
-/

namespace Informal.GraphMetrics

open Lean
open Informal.Graph

/-- Per-node graph metrics. -/
structure NodeMetrics where
  label : Name
  fanIn : Nat
  fanOut : Nat
  depth : Nat
  height : Nat
  onCriticalPath : Bool
deriving Inhabited, Repr, ToJson, FromJson

/--
Whole-graph metrics: the chosen critical path plus per-node metrics.

`schemaVersion` is bumped only for incompatible public-shape changes; consumers
(the dashboard) should branch on it.
-/
structure GraphMetrics where
  schemaVersion : Nat := 1
  criticalPath : Array Name := #[]
  nodes : Array NodeMetrics := #[]
deriving Inhabited, Repr, ToJson, FromJson

/--
Longest path (in edges) from a source to `label`, via the predecessor map.

Memoized in the `StateM (NameMap Nat)` state; `onStack` breaks cycles by treating
a back-edge as contributing 0.
-/
private partial def longestTo (adj : NameMap (Array Name)) (onStack : NameSet) (label : Name) :
    StateM (NameMap Nat) Nat := do
  match (← get).find? label with
  | some d => return d
  | none =>
    if onStack.contains label then
      return 0
    let onStack := onStack.insert label
    let preds := adj.getD label #[]
    let mut best := 0
    for p in preds do
      let dp ← longestTo adj onStack p
      if dp + 1 > best then
        best := dp + 1
    modify (·.insert label best)
    return best

/-- Run `longestTo` over every label, returning the filled memo table. -/
private def longestMap (adj : NameMap (Array Name)) (labels : Array Name) : NameMap Nat := Id.run do
  let mut memo : NameMap Nat := {}
  for l in labels do
    let (_, memo') := (longestTo adj {} l).run memo
    memo := memo'
  return memo

/--
Reconstruct one longest chain (source → … → end) from the depth memo.

Picks an endpoint of maximum depth, then walks predecessors choosing one whose
depth is exactly one less, until a source is reached. Ties are broken
deterministically by node/edge order.
-/
private def reconstructCriticalPath
    (reverseAdj : NameMap (Array Name)) (depthMemo : NameMap Nat) (labels : Array Name) :
    Array Name :=
  let endNode? : Option (Name × Nat) :=
    labels.foldl (init := none) fun best l =>
      let d := depthMemo.getD l 0
      match best with
      | none => some (l, d)
      | some (_, bd) => if d > bd then some (l, d) else best
  match endNode? with
  | none => #[]
  | some (endNode, _) =>
    Id.run do
      let mut path : Array Name := #[endNode]
      let mut current := endNode
      let mut fuel := labels.size
      while fuel > 0 do
        fuel := fuel - 1
        let cd := depthMemo.getD current 0
        if cd == 0 then
          break
        match (reverseAdj.getD current #[]).find? (fun p => depthMemo.getD p 0 + 1 == cd) with
        | some p =>
          path := path.push p
          current := p
        | none => break
      return path.reverse

/-- Compute the full set of graph metrics for `data`. -/
def computeGraphMetrics (data : Informal.Graph.GraphData) : GraphMetrics :=
  let forwardAdj := data.forwardAdj
  let reverseAdj := data.reverseAdj
  let labels := data.nodes.map (·.label)
  let depthMemo := longestMap reverseAdj labels
  let heightMemo := longestMap forwardAdj labels
  let criticalPath := reconstructCriticalPath reverseAdj depthMemo labels
  let criticalSet : NameSet := criticalPath.foldl (init := {}) (·.insert ·)
  let nodes := labels.map fun l => {
    label := l
    fanIn := (reverseAdj.getD l #[]).size
    fanOut := (forwardAdj.getD l #[]).size
    depth := depthMemo.getD l 0
    height := heightMemo.getD l 0
    onCriticalPath := criticalSet.contains l
  }
  { schemaVersion := 1, criticalPath, nodes }

/-- Look up the metrics for a single label (for per-node page rendering). -/
def GraphMetrics.find? (metrics : GraphMetrics) (label : Name) : Option NodeMetrics :=
  metrics.nodes.find? (·.label == label)

end Informal.GraphMetrics
