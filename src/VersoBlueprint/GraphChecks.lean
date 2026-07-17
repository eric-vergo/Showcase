/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Graph

/-!
# Automated `uses`-graph checks

Two generic, project-independent structural checks over a blueprint's dependency
(`uses`) graph, computed purely from a finalized `Graph.GraphData` (the master
graph unioned over every rendered graph block):

* **Acyclicity** — the directed dependency graph has no cycle. A cycle would mean
  a set of nodes each (transitively) depending on itself, which no topological
  reading order can satisfy. On failure the check reports the concrete node labels
  of one detected cycle.
* **Weak connectivity** — the graph is a single weakly-connected component: every
  node is reachable from every other when edge direction is ignored. A blueprint
  that splits into disconnected islands has orphaned material not tied to the main
  development. On failure the check reports the node labels outside the largest
  component (the *stragglers*).

Everything here is pure (`GraphData → …`), takes no environment, and hard-codes
nothing project-specific, so it is reusable by any consumer. The trust tooling
(`Commands/TrustStrip`, `Commands/TrustPages`) surfaces the verdicts as badges /
evidence pages and fails the site build when either check fails.
-/

namespace Informal.GraphChecks

open Lean
open Informal.Graph

/-- Verdict of the acyclicity check. -/
structure AcyclicityResult where
  ok : Bool := true
  /-- Node labels of one detected directed cycle (in traversal order), empty when
  acyclic. -/
  cycle : Array Name := #[]
  nodeCount : Nat := 0
  edgeCount : Nat := 0
deriving Inhabited, Repr

/-- Verdict of the weak-connectivity check. -/
structure ConnectivityResult where
  ok : Bool := true
  nodeCount : Nat := 0
  /-- Number of weakly-connected components. -/
  componentCount : Nat := 0
  /-- Size of the largest component (treated as the canonical "main" component
  anchoring the featured results). -/
  mainComponentSize : Nat := 0
  /-- Node labels outside the main (largest) component. -/
  stragglers : Array Name := #[]
deriving Inhabited, Repr

/-- Build the `label → index` map and directed adjacency (`adj[i]` = indices `i`
depends-toward, i.e. the edge targets) over the authored blueprint node set. Edges
whose endpoints are not both present as nodes are dropped (dangling external refs).

`supporting` nodes — unannotated project declarations surfaced only on the rendered
all-declarations graph under `includeAllDecls` — are excluded: the checks concern the
author-written `uses` graph, so an unwired helper declaration must not count as a
straggler or a cycle participant. -/
private def indexGraph (data : GraphData) : Array Name × Array (Array Nat) × Nat := Id.run do
  let labels := (data.nodes.filter (!·.supporting)).map (·.label)
  let n := labels.size
  let mut idx : Std.HashMap Name Nat := {}
  for i in [0:n] do
    idx := idx.insert (labels[i]!) i
  let mut adj : Array (Array Nat) := Array.replicate n #[]
  let mut edgeCount := 0
  for e in data.edges do
    match idx.get? e.source, idx.get? e.target with
    | some s, some t =>
      if !(adj[s]!).contains t then
        adj := adj.modify s (·.push t)
        edgeCount := edgeCount + 1
    | _, _ => pure ()
  return (labels, adj, edgeCount)

/-- First directed cycle in `adj` (as node indices, from the re-entry point to the
top of the DFS stack), or `none` when the graph is acyclic. Iterative white/gray/
black DFS with an explicit `(node, nextNeighbor)` frame stack. -/
private def findDirectedCycle (adj : Array (Array Nat)) : Option (Array Nat) := Id.run do
  let n := adj.size
  let mut color : Array Nat := Array.replicate n 0 -- 0 white, 1 gray, 2 black
  let mut result : Option (Array Nat) := none
  for root in [0:n] do
    if result.isNone && color[root]! == 0 then
      color := color.set! root 1
      let mut stack : Array (Nat × Nat) := #[(root, 0)]
      while result.isNone && !stack.isEmpty do
        let top := stack.size - 1
        let (u, k) := stack[top]!
        if k < (adj[u]!).size then
          stack := stack.set! top (u, k + 1)
          let v := (adj[u]!)[k]!
          if color[v]! == 0 then
            color := color.set! v 1
            stack := stack.push (v, 0)
          else if color[v]! == 1 then
            -- `v` is on the current DFS stack → cycle from `v` to the top.
            let onStack := stack.map (·.1)
            match onStack.findIdx? (· == v) with
            | some i => result := some (onStack.extract i onStack.size)
            | none => result := some #[v]
        else
          color := color.set! u 2
          stack := stack.pop
  return result

/-- Weakly-connected components over the undirected version of `adj`, returned as a
component id per node index (ids are `0 …` in first-seen order). -/
private def weakComponents (adj : Array (Array Nat)) : Array Nat × Nat := Id.run do
  let n := adj.size
  -- Symmetric adjacency.
  let mut undir : Array (Array Nat) := Array.replicate n #[]
  for u in [0:n] do
    for v in adj[u]! do
      if !(undir[u]!).contains v then undir := undir.modify u (·.push v)
      if !(undir[v]!).contains u then undir := undir.modify v (·.push u)
  let mut comp : Array Nat := Array.replicate n 0
  let mut seen : Array Bool := Array.replicate n false
  let mut nextId := 0
  for start in [0:n] do
    if !seen[start]! then
      -- BFS this component.
      let mut queue : Array Nat := #[start]
      seen := seen.set! start true
      comp := comp.set! start nextId
      let mut qi := 0
      while qi < queue.size do
        let u := queue[qi]!
        qi := qi + 1
        for v in undir[u]! do
          if !seen[v]! then
            seen := seen.set! v true
            comp := comp.set! v nextId
            queue := queue.push v
      nextId := nextId + 1
  return (comp, nextId)

/-- Run the acyclicity check over the master graph. -/
def checkAcyclic (data : GraphData) : AcyclicityResult :=
  let (labels, adj, edgeCount) := indexGraph data
  match findDirectedCycle adj with
  | some idxs =>
    { ok := false, cycle := idxs.map (labels[·]!), nodeCount := labels.size, edgeCount }
  | none => { ok := true, nodeCount := labels.size, edgeCount }

/-- Run the weak-connectivity check over the master graph. A graph with 0 or 1
nodes is vacuously connected. -/
def checkConnected (data : GraphData) : ConnectivityResult :=
  let (labels, adj, _) := indexGraph data
  let n := labels.size
  if n ≤ 1 then
    { ok := true, nodeCount := n, componentCount := n, mainComponentSize := n }
  else
    let (comp, count) := weakComponents adj
    -- Largest component id = the canonical main component.
    let sizes : Array Nat := Id.run do
      let mut s : Array Nat := Array.replicate count 0
      for c in comp do s := s.modify c (· + 1)
      return s
    let mainId := (Array.range count).foldl (init := 0) fun best c =>
      if sizes[c]! > sizes[best]! then c else best
    let mainSize := if count == 0 then 0 else sizes[mainId]!
    let stragglers : Array Name := Id.run do
      let mut out : Array Name := #[]
      for i in [0:n] do
        if comp[i]! != mainId then out := out.push (labels[i]!)
      return out
    { ok := count ≤ 1, nodeCount := n, componentCount := count,
      mainComponentSize := mainSize, stragglers }

/-- Combined verdict: both structural checks over one master graph. -/
structure Results where
  acyclic : AcyclicityResult := {}
  connected : ConnectivityResult := {}
deriving Inhabited, Repr

/-- Whether the graph is empty (no nodes) — the checks are then vacuous and no
badge/gate should fire. -/
def Results.graphEmpty (r : Results) : Bool := r.acyclic.nodeCount == 0

def run (data : GraphData) : Results :=
  { acyclic := checkAcyclic data, connected := checkConnected data }

/-- Whether every structural check passed (used to gate the site build). -/
def Results.allOk (r : Results) : Bool := r.acyclic.ok && r.connected.ok

end Informal.GraphChecks
