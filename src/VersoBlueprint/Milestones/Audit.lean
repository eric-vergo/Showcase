/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint.Graph
import VersoBlueprint.Milestones.Data

/-!
Checking and assembly for the proof-overview layer.

Two things happen here, and they are deliberately separate from rendering:

* **Rows.** Each milestone's overview row is its longest-path depth over
  milestone edges, unless the author pinned one with `(row := n)`. A pin that
  would place a milestone at or above one of its dependencies is a violation, and
  so is a cycle: both are returned as errors so the elaborator can report them
  against the author's syntax.

* **Witnesses.** A milestone edge is a claim about the *mathematics*: "this
  waypoint rests on that one". The declaration graph can often corroborate it —
  some node of the dependent milestone transitively depends on some node of the
  milestone it uses. Two tiers are tried, the presented blueprint graph first and
  the wider project-declaration graph second, and an edge nothing corroborates is
  labelled `asserted` rather than rejected. A *shared* member is never a witness:
  overlapping membership says the two waypoints touch, not that one rests on the
  other.

The result is a pure value (`OverviewData`); the renderer never recomputes any of
it, so what the page shows and what the build checked cannot drift apart.
-/

namespace Informal.Milestones

open Lean
open Informal.Graph

/-! ### Rows -/

/--
Overview row for every milestone: the longest-path depth over milestone edges,
with author pins honored.

Returns the first violation as an error message rather than a partial layout: a
hand-laid overview whose pins contradict its dependencies is a defect the author
wants reported, not silently re-laid.
-/
def rows (ms : Array Milestone) : Except String (NameMap Nat) := Id.run do
  let known : NameSet := ms.foldl (init := ({} : NameSet)) fun acc m => acc.insert m.label
  let mut row : NameMap Nat :=
    ms.foldl (init := ({} : NameMap Nat)) fun acc m => acc.insert m.label (m.row?.getD 0)
  let mut settled := false
  for _round in [0 : ms.size + 1] do
    let mut changed := false
    for m in ms do
      let mut want := m.row?.getD 0
      for u in m.uses do
        if u != m.label && known.contains u then
          let ru := row.getD u 0
          if ru + 1 > want then
            want := ru + 1
      match m.row? with
      | some pinned =>
        if want > pinned then
          return .error
            s!"Milestone {displayLabel m.label} pins row {pinned}, but its dependencies place \
               it no higher than row {want}; a pinned row must be greater than every row it \
               depends on"
      | none =>
        if want > row.getD m.label 0 then
          row := row.insert m.label want
          changed := true
    if !changed then
      settled := true
      break
  if settled then
    return .ok row
  else
    return .error
      "Milestone dependencies contain a cycle; the proof overview cannot be laid out in rows"

/-! ### Witnesses -/

/--
Transitive dependencies of each given label in `g`, computed once per label.

The overview asks the same ancestor question for the same member many times (once
per incident edge), and each `GraphData.ancestors` call walks the reverse
adjacency from scratch.
-/
def ancestorIndex (g : GraphData) (labels : Array Name) : NameMap NameSet :=
  labels.foldl (init := ({} : NameMap NameSet)) fun acc l =>
    if acc.contains l then acc else acc.insert l (g.ancestors l)

/--
A dependency path from a member of `target` down to a member of `source`, if the
graph behind `anc` has one.

A member the two milestones share is explicitly *not* a witness: it says the
waypoints overlap, not that one is built on the other.
-/
def witness? (anc : NameMap NameSet) (target source : Milestone) :
    Option (Name × Name) :=
  target.members.findSome? fun a =>
    match anc.get? a with
    | none => none
    | some ancestorsOfA =>
      match source.members.find? (fun b => b != a && ancestorsOfA.contains b) with
      | some b => some ((a : Name), (b : Name))
      | none => none

/-! ### Assembled overview data -/

/-- One member node of a milestone, with the progress facts the meter needs.
Display titles and hrefs are resolved at render time from the traversal state, so
nothing here duplicates the node index. -/
structure MemberStatus where
  label : Data.Label
  /-- The node's proof is complete (locally formalized, or in Mathlib). -/
  closed : Bool := false
  /-- Not closed, but the node is ready to be worked on. -/
  ready : Bool := false
deriving Inhabited, Repr, ToJson, FromJson

/-- One milestone, laid out and audited, as the renderer consumes it. -/
structure OverviewMilestone where
  label : Data.Label
  /-- In-page anchor of this milestone's card (`ms-…`), unique within the page. -/
  anchor : String := ""
  title : String := ""
  paper : String := ""
  paperUrl : String := ""
  /-- Overview row (0 at the top). -/
  row : Nat := 0
  /-- Position within the row, in author order. -/
  column : Nat := 0
  /-- 1-based position in author order across the whole overview. -/
  order : Nat := 0
  members : Array MemberStatus := #[]
  /-- Members whose labels name no blueprint node. Reported as a build error; kept
  here so the card can still say what the author wrote. -/
  memberTotal : Nat := 0
  memberClosed : Nat := 0
  memberReady : Nat := 0
  /-- This milestone's declared dependencies, with their verdicts. -/
  uses : Array EdgeVerdict := #[]
deriving Inhabited, Repr, ToJson, FromJson

/-- Everything the `blueprint_overview` surface renders. Assembled at elaboration
(where the environment and the declaration graph exist) and carried to the
renderer as one flat JSON payload. -/
structure OverviewData where
  schemaVersion : Nat := 1
  /-- Page/section title. -/
  title : String := "Proof overview"
  milestones : Array OverviewMilestone := #[]
  /-- Every milestone edge, in author order of the declaring milestone. -/
  edges : Array EdgeVerdict := #[]
  audit : Audit := {}
  /-- Members listed before the fold on a card. -/
  maxMembersShown : Nat := 24
deriving Inhabited, Repr, ToJson, FromJson

/-- Rows actually used, in ascending order. -/
def OverviewData.rowIndices (d : OverviewData) : Array Nat :=
  let rows := d.milestones.foldl (init := (#[] : Array Nat)) fun acc m =>
    if acc.contains m.row then acc else acc.push m.row
  rows.qsort (· < ·)

/-- The milestones on one overview row, in author order. -/
def OverviewData.rowMembers (d : OverviewData) (row : Nat) : Array OverviewMilestone :=
  d.milestones.filter (·.row == row)

/-- Whether the overview carries anything at all. A document with no milestones
renders no overview surface. -/
def OverviewData.isEmpty (d : OverviewData) : Bool := d.milestones.isEmpty

/-- Tally a set of edge verdicts into the reported audit.

Pure and shared: the counts the overview prints, the counts the trust-model page
prints, and the counts a test checks all come from this one function. -/
def auditOf (milestoneCount graphNodes coveredNodes : Nat) (verdicts : Array EdgeVerdict)
    (projectDeclsConsulted : Bool) : Audit := {
  milestones := milestoneCount
  edges := verdicts.size
  graphNodes
  coveredNodes
  witnessedPresented := (verdicts.filter (·.tier == .presented)).size
  witnessedProjectDecls := (verdicts.filter (·.tier == .projectDecls)).size
  asserted := (verdicts.filter (·.isAsserted)).size
  projectDeclsConsulted
}

/-! ### Progress -/

/-- Progress facts for one member label, read from the presented graph. A label
with no node yields `none` — the caller reports that as a build error. -/
def memberStatus? (nodes : NameMap NodeData) (label : Name) : Option MemberStatus :=
  match nodes.get? label with
  | none => none
  | some n =>
    let closed :=
      n.statementStatus == .mathlib ||
        n.proofStatus == .formalized || n.proofStatus == .formalizedWithAncestors
    let ready :=
      !closed && (n.proofStatus == .ready || n.statementStatus == .ready ||
        n.statementStatus == .formalized)
    some { label, closed, ready }

/-- Index the presented graph's nodes by label. -/
def nodeIndex (g : GraphData) : NameMap NodeData :=
  g.nodes.foldl (init := ({} : NameMap NodeData)) fun acc n => acc.insert n.label n

end Informal.Milestones
