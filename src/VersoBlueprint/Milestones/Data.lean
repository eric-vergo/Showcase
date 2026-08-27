/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Opus 5 (Claude Code)
-/

import Lean
import VersoBlueprint.Data

/-!
Semantic data for the proof-overview ("milestones") layer.

A milestone is a hand-authored waypoint in a proof: a title, an informal sketch,
a paper reference, the blueprint nodes it is made of, and the milestones it
depends on. The overview surface renders them as a compact graph plus cards.

This module is deliberately the *lowest* one in the layer: it is imported by
`VersoBlueprint.Environment` (which owns the registry), so it must not import
`VersoBlueprint.Graph` — `Graph` imports `Environment`, and the cycle
`Environment → Milestones.Data → Graph → Environment` would not resolve. Anything
that needs the dependency graph belongs in `Milestones.Audit`.
-/

namespace Informal.Milestones

open Lean

/--
One authored milestone, as registered by a `:::milestone` directive.

`declOrder` is the position of the directive in load order. It is load-bearing:
the overview lays each row out in *author* order rather than in any derived
order, so a hand-laid proof narrative reads the way it was written. Imported
milestones are renumbered in `addImportedFn` so the order stays total across
modules.
-/
structure Milestone where
  /-- The milestone's own label (e.g. `ms:period-family`). -/
  label : Data.Label
  /-- Display title. Empty ⇒ the label is displayed instead. -/
  title : String := ""
  /-- Paper reference as the author wrote it (e.g. `§3`). Empty ⇒ omitted. -/
  paper : String := ""
  /-- URL of the paper the reference points into. Empty ⇒ the reference is plain text. -/
  paperUrl : String := ""
  /-- Author-pinned overview row. `none` ⇒ the row is the longest-path depth over
  milestone edges. An explicit row that would place a milestone at or above one of
  its dependencies is a build error, so a hand-laid layout stays checkable. -/
  row? : Option Nat := none
  /-- Blueprint node labels this milestone is made of. -/
  members : Array Data.Label := #[]
  /-- Milestones this one depends on. -/
  uses : Array Data.Label := #[]
  /-- Position of the declaring directive in load order. -/
  declOrder : Nat := 0
deriving Inhabited, Repr, ToJson, FromJson

/--
How a milestone edge was established.

The three tiers are ordered by how much the *machine* contributed, and they are
never collapsed: a reader must be able to tell an edge the declaration graph
witnesses from one the author asserted.
-/
inductive WitnessTier where
  /-- Some member of the dependent milestone transitively depends, in the
  *presented* blueprint graph, on some member of the milestone it uses. -/
  | presented
  /-- Same, but the witness only exists in the wider project-declaration graph
  (`verso.blueprint.graph.includeAllDecls`), through declarations this blueprint
  does not present as nodes. -/
  | projectDecls
  /-- No witness was found. The edge stands on the author's word alone. -/
  | asserted
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson

/-- Short label for a tier, used in badges and in the trust-model counts. -/
def WitnessTier.label : WitnessTier → String
  | .presented => "witnessed"
  | .projectDecls => "witnessed via project declarations"
  | .asserted => "author-asserted"

/-- One milestone edge together with the verdict the build reached about it. -/
structure EdgeVerdict where
  /-- The milestone that is depended upon (the upstream end). -/
  source : Data.Label
  /-- The milestone that declared the `uses` (the downstream end). -/
  target : Data.Label
  /-- What established the edge. -/
  tier : WitnessTier := .asserted
  /-- Member of `target` at which the witnessing dependency path starts.
  `none` for an asserted edge. -/
  witnessFrom : Option Data.Label := none
  /-- Member of `source` at which the witnessing dependency path ends.
  `none` for an asserted edge. -/
  witnessTo : Option Data.Label := none
deriving Inhabited, Repr, ToJson, FromJson

/-- Whether this edge rests on the author's word rather than on the graph. -/
def EdgeVerdict.isAsserted (e : EdgeVerdict) : Bool := e.tier == .asserted

/--
What the milestone layer established for this build.

Reported on the overview page and, in one sentence, on the "Trust model" page.
Every field is a count of something the build actually did; there is no field
that could be read as a mathematical claim.
-/
structure Audit where
  /-- Milestones declared. -/
  milestones : Nat := 0
  /-- Milestone edges declared. -/
  edges : Nat := 0
  /-- Blueprint nodes in the presented graph. -/
  graphNodes : Nat := 0
  /-- Distinct blueprint nodes named as members of some milestone. -/
  coveredNodes : Nat := 0
  /-- Edges witnessed in the presented blueprint graph. -/
  witnessedPresented : Nat := 0
  /-- Edges witnessed only in the project-declaration graph. -/
  witnessedProjectDecls : Nat := 0
  /-- Edges no graph witnessed. -/
  asserted : Nat := 0
  /-- Whether the project-declaration tier was consulted at all. `false` ⇒ either
  every edge was witnessed in the presented graph, or the tier is not available
  (`verso.blueprint.graph.includeAllDecls` /
  `verso.blueprint.overview.witnessViaProjectDecls` off). -/
  projectDeclsConsulted : Bool := false
deriving Inhabited, Repr, ToJson, FromJson

/--
Elaboration-time payload of a `:::milestone` block.

Small and `Quote`-able on purpose: the sketch prose travels as the block's own
*contents*, and the traversal hook stashes those under `SketchData`. Quoting the
elaborated blocks into the syntax tree is neither possible nor wanted.
-/
structure MilestoneBlockData where
  label : Data.Label
  title : String := ""
  declOrder : Nat := 0
deriving Inhabited, Repr, ToJson, FromJson, Quote

/--
The sketch prose of one milestone, captured during traversal.

`:::milestone` renders nothing where it is written, so the blocks have to reach
the overview surface some other way; the traversal store is that way. This is
kept in a *runtime-cache* store rather than a semantic domain precisely because
the prose must not end up in the public `xref.json`.
-/
structure SketchData where
  label : Data.Label
  title : String := ""
  declOrder : Nat := 0
  contents : Array (Verso.Doc.Block Verso.Genre.Manual) := #[]
deriving Inhabited, ToJson, FromJson

/--
A blueprint label as the author wrote it.

`Name.toString` wraps components that are not Lean identifiers in guillemets, so
a label like `ms:period-family` prints as `«ms:period-family»`. Diagnostics and
rendered chips should show what the author typed.
-/
def displayLabel (label : Data.Label) : String :=
  (label : Name).toString.foldl (init := "") fun acc c =>
    if c == '«' || c == '»' || c == '‹' || c == '›' then acc else acc.push c

/--
Stable in-page anchor for a milestone card (`ms:period-family` → `ms-period-family`).

Deliberately local rather than reusing `NodeRoute.nodePageSlugOfString`: this
module sits below `Environment`, and `NodeRoute` sits far above it. The `ms-`
prefix is not doubled when the author's own label already begins with it, which is
the common convention. Distinct labels can in principle sluggify alike; the
overview builder disambiguates with a numeric suffix, exactly as the
declaration-page emitter does.
-/
def anchorSlug (label : Data.Label) : String :=
  let cleaned := (displayLabel label).foldl (init := "") fun acc c =>
    if c.isAlphanum then acc.push c.toLower
    else if acc.isEmpty || acc.back == '-' then acc
    else acc.push '-'
  let trimmed :=
    if !cleaned.isEmpty && cleaned.back == '-' then cleaned.dropRight 1 else cleaned
  if trimmed.isEmpty then "ms-milestone"
  else if trimmed.startsWith "ms-" then trimmed
  else "ms-" ++ trimmed

/-- Display title of a milestone: its `title` when set, else the authored label. -/
def Milestone.displayTitle (m : Milestone) : String :=
  if m.title.isEmpty then displayLabel m.label else m.title

end Informal.Milestones
