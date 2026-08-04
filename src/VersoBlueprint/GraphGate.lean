/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.GraphApi
import VersoBlueprint.GraphChecks
import VersoBlueprint.NodeRoute
import VersoBlueprint.TraversalIndex

/-!
# `uses`-graph build gate, run *before* any HTML is written

Three structural checks over the master dependency graph:

* **No phantom nodes.** A `uses` label that resolves to nothing becomes an
  `unknownRef` node in the graph rather than an error — and because the
  connectivity check counts nodes, a typo can *help* the graph pass. Forward
  references make this uncheckable at elaboration (a label may legitimately be
  defined in a later chapter), so it is checked here, once, over the finished
  graph.
* **Acyclicity** — unconditional. A dependency cycle admits no reading order.
* **Weak connectivity** — gated by `verso.blueprint.trust.requireConnected`
  (default true, read from the traversal-cached trust payload); a deliberately
  multi-topic blueprint sets it false and the result is reported without gating.

The gate runs between traversal and emission (`PreviewManifest.emitBlueprintHtml`,
both the `.immediately` and `.resumeFrom` paths), so a failing build leaves **no**
rendered site on disk. It previously ran as an `ExtraStep`, i.e. after the HTML was
already written — a gate whose failure still shipped the artifact it was gating.

The trust payload is read as raw JSON so this module stays below the
`Commands.TrustStrip` layer (which itself renders the check results).
-/

namespace Informal.GraphGate

open Lean
open Verso.Genre Manual

/-- `verso.blueprint.trust.requireConnected` as cached in the traversal-time trust
payload; `true` (the option's default) when no payload was stored. -/
private def requireConnected (state : TraverseState) : Bool :=
  match Informal.TraversalIndex.TrustData.raw? state with
  | some j => ((j.getObjValAs? Bool "requireConnected").toOption).getD true
  | none => true

/-- Friendly display text for a graph node label in a gate failure message:
enriched node title, else the short display label, else the de-escaped raw label. -/
private def nodeText (master : Informal.Graph.GraphData) (label : Name) : String :=
  match master.nodes.find? (·.label == label) with
  | some node =>
    let t := node.title.trimAscii.toString
    if !t.isEmpty then t
    else if !node.displayLabel.isEmpty then node.displayLabel
    else Informal.NodeRoute.stripNameEscapes label.toString
  | none => Informal.NodeRoute.stripNameEscapes label.toString

/-- Labels of nodes the graph invented because a `uses` reference did not resolve.
`supporting` nodes are excluded for the same reason the structural checks exclude
them: they are machine-derived, not author-written. -/
private def phantomLabels (master : Informal.Graph.GraphData) : Array Name :=
  (master.nodes.filter fun n => n.warnings.unknownRef && !n.supporting).map (·.label)

/--
Run the structural `uses`-graph gate over a finished traversal state.

Throws `IO.userError` on a violation, before the caller emits anything. Skipped in
single-page mode and for an empty graph (a document with no rendered
`{blueprint_graph}` block has no `uses` graph to check).
-/
def run (mode : Mode) (state : TraverseState) : IO Unit := do
  match mode with
  | .single => pure ()
  | .multi =>
    let master := Informal.GraphApi.masterGraph state
    let checks := Informal.GraphChecks.run master
    if checks.graphEmpty then return ()
    -- 1. Phantom nodes: an unresolved `uses` label is an authoring error, not a node.
    let phantoms := phantomLabels master
    unless phantoms.isEmpty do
      let names := String.intercalate ", "
        (phantoms.map (Informal.NodeRoute.stripNameEscapes ·.toString)).toList
      throw <| IO.userError s!"Showcase uses-graph check FAILED (unresolved references): \
        {phantoms.size} `uses` label(s) do not name any blueprint node: {names}. \
        Each one silently became a placeholder node in the dependency graph. Fix the \
        spelling, or remove the edge."
    -- 2. Acyclicity: unconditional.
    unless checks.acyclic.ok do
      let cyc := String.intercalate " → " (checks.acyclic.cycle.map (nodeText master)).toList
      throw <| IO.userError s!"Showcase uses-graph check FAILED (acyclicity): a dependency \
        cycle was detected among: {cyc}. Remove the cyclic `uses` edges."
    -- 3. Connectivity: gated by the consumer's `requireConnected` setting.
    unless checks.connected.ok || !(requireConnected state) do
      let strag := String.intercalate ", " (checks.connected.stragglers.map (nodeText master)).toList
      throw <| IO.userError s!"Showcase uses-graph check FAILED (connectivity): the `uses` \
        graph has {checks.connected.componentCount} disconnected components. Nodes outside the \
        main component: {strag}. Connect them to the main development, or set \
        verso.blueprint.trust.requireConnected := false for a deliberately multi-topic blueprint."

end Informal.GraphGate
