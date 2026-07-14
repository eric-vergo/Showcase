/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Environment
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Lib.HtmlId
import VersoBlueprint.PreviewCache
import VersoBlueprint.ProvedStatus

namespace Informal.Graph

open Lean
open Informal Data Environment

/-!
See `doc/DESIGN_RATIONALE.md` for the human-readable graph
status/completion and warning/color mapping rationale.
-/

/-- Upstream-aligned statement-track status (node border). -/
inductive StatementStatus where
  | blocked
  | ready
  | formalized
  | mathlib
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

/-- Upstream-aligned background status (proof-track for theorem-like nodes). -/
inductive ProofStatus where
  | none
  | ready
  | incomplete
  | formalized
  | formalizedWithAncestors
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

structure WarningFlags where
  unknownRef : Bool := false
  leanOnlyNoStatement : Bool := false
  missingExternalDecl : Bool := false
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

structure GraphNode (Ref : Type) where
  label : Name
  displayLabel? : Option String := none
  deps : Array Name
  proofDeps : Array Name := #[]
  parent? : Option Name := none
  shape : String := "box"
  style : String := "filled"
  fillcolor : String
  color : String := "#6b7280"
  penwidth : String := "1.8"
  fontcolor : String := "#111827"
  peripheries : Nat := 1
  gradientangle? : Option String := none
  tooltip? : Option String := none
  ref? : Option Ref := none
  /-- Optional CSS class emitted on the rendered DOT node (e.g. status highlight). -/
  cssClass? : Option String := none
  /-- Statement dependency use-refs carrying per-edge origin/intent metadata. -/
  statementUses : Array Data.UseRef := #[]
  /-- Proof dependency use-refs carrying per-edge origin/intent metadata. -/
  proofUses : Array Data.UseRef := #[]
deriving Inhabited, Repr, ToJson, FromJson

instance [Quote Ref] : Quote (GraphNode Ref) where
  quote n := Syntax.mkCApp ``GraphNode.mk
    #[
      quote n.label, quote n.displayLabel?, quote n.deps, quote n.proofDeps, quote n.parent?, quote n.shape,
      quote n.style, quote n.fillcolor, quote n.color, quote n.penwidth, quote n.fontcolor, quote n.peripheries,
      quote n.gradientangle?, quote n.tooltip?, quote n.ref?, quote n.cssClass?, quote n.statementUses, quote n.proofUses
    ]

abbrev Graph (Ref : Type) := Array (GraphNode Ref)

def GraphNode.displayLabel (node : GraphNode Ref) : String :=
  node.displayLabel?.getD (toString node.label)

/-- Graphviz rank direction used by rendered Blueprint graph layouts. -/
inductive GraphDirection where
  | LR
  | RL
  | TB
  | BT
deriving Inhabited, Repr, BEq, FromJson, ToJson, Quote

/-- DOT `rankdir` token corresponding to a graph direction. -/
def GraphDirection.rankdir : GraphDirection → String
  | .LR => "LR"
  | .RL => "RL"
  | .TB => "TB"
  | .BT => "BT"

/-- Parse user-facing direction aliases accepted by `blueprint_graph`. -/
def GraphDirection.parse? (s : String) : Option GraphDirection :=
  match s.toLower with
  | "lr" | "left-right" | "horizontal" => some .LR
  | "rl" | "right-left" => some .RL
  | "tb" | "top-bottom" | "vertical" => some .TB
  | "bt" | "bottom-top" => some .BT
  | _ => none

/--
Options that affect Graphviz layout for rendered Blueprint graphs.

These options are stored in graph block payloads and serialized with render
variants, so keep changes compatible with existing generated sites.
-/
structure GraphOptions where
  /-- Graphviz rank direction. -/
  direction : GraphDirection := .TB
  /--
  Ask Graphviz to compact disconnected graph components before d3-graphviz fits
  the SVG into the canvas.
  -/
  pack : Bool := false
  /--
  Show every drawn dependency edge, including the transitively-redundant ones the
  default view removes. Selects the unreduced `dotFull` render variant when one
  exists; layout is recomputed because the redundant edges change the graph shape.
  -/
  allEdges : Bool := false
deriving Inhabited, BEq, FromJson, ToJson, Quote

private def graphPackAttr (pack : Bool) : String :=
  if pack then "true" else "false"

/--
DOT rendering style knobs shared by page graphs and compact widget graphs.

This is a rendering implementation detail, not part of the public graph-data
schema. It lets all DOT emitters share one header template while preserving
surface-specific sizing.
-/
structure GraphDotStyle where
  /-- Node font size used in the DOT header. -/
  nodeFontSize : String := "10"
  /-- Node margin used in the DOT header. -/
  nodeMargin : String := "0.08,0.04"
  /-- Default node stroke width used in the DOT header. -/
  nodePenwidth : String := "1.8"
  /-- Default edge arrow size used in the DOT header. -/
  edgeArrowsize : String := "0.6"
  /-- Default edge stroke width used in the DOT header. -/
  edgePenwidth : String := "1"
  /-- Whether to emit the Graphviz `pack` attribute. -/
  includePack : Bool := true
deriving Inhabited, BEq

/-- Smaller DOT styling for embedded graph panels. -/
def GraphDotStyle.compact : GraphDotStyle := {
  nodeFontSize := "9"
  nodeMargin := "0.05,0.03"
  nodePenwidth := "1.4"
  edgeArrowsize := "0.5"
  edgePenwidth := "0.9"
  includePack := false
}

/--
One rendered graph view.

The bundled renderer uses variants for the full graph, the synthetic group
overview, and per-group subgraphs. The `selectOnNodeId` and `hoverOnNodeId`
arrays describe variant transitions keyed by SVG node id, and
`previewKeyByNodeId` maps SVG nodes to preview-cache keys.
-/
structure GraphRenderVariant where
  /-- Stable key used by the graph view selector and variant links. -/
  key : String
  /-- Human-readable view label. -/
  label : String
  /-- DOT source for this view (transitively reduced). -/
  dot : String
  /-- Unreduced DOT source with every drawn edge, for the "Show all edges" toggle.
  Present only when transitive reduction actually dropped edges; the derived ToJson
  omits it (`none`) otherwise, so unreduced variants carry no extra payload. -/
  dotFull : Option String := none
  /-- Initial layout options used to build the DOT source. -/
  options : GraphOptions := {}
  /-- Node ids that switch to another variant when selected. -/
  selectOnNodeId : Array (String × String) := #[]
  /-- Node ids that preview another variant on hover. -/
  hoverOnNodeId : Array (String × String) := #[]
  /-- Node ids that open Blueprint preview-cache entries. -/
  previewKeyByNodeId : Array (String × String) := #[]
deriving Inhabited, ToJson

/-- Direction order used by the bundled graph controls. -/
def allGraphDirections : Array GraphDirection := #[.TB, .LR, .RL, .BT]

/--
Stable visual metadata for a graph node.

This mirrors the render-facing DOT attributes without exposing the generic
`GraphNode Ref` type in cached/public JSON schemas.
-/
structure NodeVisual where
  shape : String := "box"
  style : String := "filled"
  fillcolor : String
  color : String := "#6b7280"
  penwidth : String := "1.8"
  fontcolor : String := "#111827"
  peripheries : Nat := 1
  gradientangle? : Option String := none
  tooltip? : Option String := none
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

def NodeVisual.ofGraphNode (node : GraphNode Ref) : NodeVisual := {
  shape := node.shape
  style := node.style
  fillcolor := node.fillcolor
  color := node.color
  penwidth := node.penwidth
  fontcolor := node.fontcolor
  peripheries := node.peripheries
  gradientangle? := node.gradientangle?
  tooltip? := node.tooltip?
}

/-- Axis represented by a dependency edge in the public graph API. -/
inductive EdgeAxis where
  | statement
  | proof
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

/-- Public dependency edge data. Edges point from dependency source to dependent target. -/
structure EdgeData where
  source : Name
  target : Name
  axes : Array EdgeAxis := #[]
  /-- Whether this edge was user-authored (`manual`) or introduced by automation. -/
  origin : Data.UseOrigin := .manual
  /-- Semantic classification of this dependency edge (regular/auxiliary/technical). -/
  intent : Data.UseIntent := .regular
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

/-- Public group/parent metadata for graph consumers. -/
structure GroupData where
  label : Name
  title : String
  /-- Compact cluster label (typically the chapter name derived from a member's
  in-chapter href). Empty when no short form is known; renderers then fall back to
  `title`. Kept distinct from `title` so a long descriptive `title` can still be
  surfaced as a cluster tooltip. -/
  shortTitle : String := ""
  declared : Bool := false
  children : Array Name := #[]
deriving Inhabited, Repr, DecidableEq, ToJson, FromJson, Quote

/-- Cluster display title: the compact `shortTitle` when set, else the full `title`. -/
def GroupData.displayTitle (group : GroupData) : String :=
  if group.shortTitle.isEmpty then group.title else group.shortTitle

/--
Stable per-node graph data for Lean, manifest, and browser consumers.

Use `statementStatus`, `proofStatus`, and `warnings` for semantics. `visual`
is provided only for renderers that want to reuse Blueprint's current graph
styling without reverse-engineering colors into statuses.
-/
structure NodeData where
  label : Name
  title : String
  displayLabel : String
  kind : Option Data.NodeKind := none
  parent : Option Name := none
  href : Option String := none
  previewKey : String
  statementUses : Array Data.UseRef := #[]
  proofUses : Array Data.UseRef := #[]
  statementStatus : StatementStatus := .blocked
  proofStatus : ProofStatus := .none
  warnings : WarningFlags := {}
  visual : NodeVisual
  /-- Whether this is a subordinate "supporting" node: a project declaration
  surfaced on the dependency graph without an authored blueprint node. Renders
  with the muted supporting visual, adds the `bp-node-supporting` DOT class, and
  surfaces a supporting legend entry. Never `true` in the semantic master graph
  (supporting nodes live only on the rendered Dependency-Graph block). -/
  supporting : Bool := false
deriving Inhabited, Repr, ToJson, FromJson, Quote

/--
Stable graph data shared by Lean, generated manifests, and browser runtime code.

`schemaVersion` is bumped only for incompatible public-shape changes.
-/
structure GraphData where
  schemaVersion : Nat := 1
  key : String := "graph"
  nodes : Array NodeData := #[]
  edges : Array EdgeData := #[]
  groups : Array GroupData := #[]
deriving Inhabited, Repr, ToJson, FromJson, Quote

/-- Stable status CSS class emitted on DOT nodes, used by the status highlight/filter. -/
def statusCssClass : StatementStatus → String
  | .blocked => "bp-status-blocked"
  | .ready => "bp-status-ready"
  | .formalized => "bp-status-formalized"
  | .mathlib => "bp-status-mathlib"

/-- Visible DOT node label: the node's display title ("Definition raceKernel",
"Lemma exists_one_lt_tsum_primes_rpow_gt") when present, falling back to the raw
blueprint label slug. Keeps the rendered graph node text in sync with the tooltips,
`data-bp-node-title`, and the click-through modal card — all of which key off
`NodeData.title` — instead of surfacing the internal `«def:chi»`-style slug. -/
def NodeData.graphLabel (node : NodeData) : String :=
  if node.title.trimAscii.toString.isEmpty then node.displayLabel else node.title

def NodeData.toGraphNode (node : NodeData) : GraphNode String := {
  label := node.label
  displayLabel? := some node.graphLabel
  deps := node.statementUses.map (fun useRef => (useRef.label : Name))
  proofDeps := node.proofUses.map (fun useRef => (useRef.label : Name))
  parent? := node.parent
  shape := node.visual.shape
  style := node.visual.style
  fillcolor := node.visual.fillcolor
  color := node.visual.color
  penwidth := node.visual.penwidth
  fontcolor := node.visual.fontcolor
  peripheries := node.visual.peripheries
  gradientangle? := node.visual.gradientangle?
  tooltip? := node.visual.tooltip?
  ref? := node.href
  cssClass? := some <|
    if node.supporting then s!"{statusCssClass node.statementStatus} bp-node-supporting"
    else statusCssClass node.statementStatus
  statementUses := node.statementUses
  proofUses := node.proofUses
}

def GraphData.toGraph (data : GraphData) : Graph String :=
  data.nodes.map NodeData.toGraphNode

def GraphData.groupTitleMap (data : GraphData) : Lean.NameMap String :=
  data.groups.foldl (init := ({} : Lean.NameMap String)) fun acc group =>
    acc.insert group.label group.title

/-- Cluster display titles (compact `shortTitle` where present, else `title`). Used
as the rendered DOT cluster label. -/
def GraphData.groupDisplayTitleMap (data : GraphData) : Lean.NameMap String :=
  data.groups.foldl (init := ({} : Lean.NameMap String)) fun acc group =>
    acc.insert group.label group.displayTitle

/-- Cluster tooltips: the long `title`, emitted only when a distinct nonempty
`shortTitle` actually abbreviates the cluster label (so the tooltip surfaces the
full sentence the short label stands in for). No entry when nothing was shortened. -/
def GraphData.groupClusterTooltipMap (data : GraphData) : Lean.NameMap String :=
  data.groups.foldl (init := ({} : Lean.NameMap String)) fun acc group =>
    if !group.shortTitle.isEmpty && !group.title.isEmpty && group.shortTitle != group.title then
      acc.insert group.label group.title
    else acc

structure LegendSwatch where
  background : String := "#ffffff"
  borderColor : String := "#6b7280"
  borderWidth : Nat := 1
  borderStyle : String := "solid"
  borderRadius : String := "0.2rem"
deriving Inhabited, Repr, ToJson, FromJson

/-- STY-GRAPH-05 (#32a): a horizontal-rule sample mirroring DOT edge styling so
the Edges legend exemplifies each line variant the way node groups show fill/
border swatches. `borderStyle` is a CSS `border-top-style` (`solid`/`dashed`/
`dotted`); `borderWidth` is in px and tracks the DOT `penwidth`. -/
structure EdgeLegendSwatch where
  color : String := "#6b7280"
  borderStyle : String := "solid"
  borderWidth : String := "1.6"
deriving Inhabited, Repr, ToJson, FromJson

structure LegendItem where
  label : String
  swatch? : Option LegendSwatch := none
  edgeSwatch? : Option EdgeLegendSwatch := none
deriving Inhabited, Repr, ToJson, FromJson

structure LegendGroup where
  key : String
  title : String
  summary? : Option String := none
  items : Array LegendItem
deriving Inhabited, Repr, ToJson, FromJson

def LegendSwatch.inlineStyle (swatch : LegendSwatch) : String :=
  String.intercalate "; " [
    s!"background: {swatch.background}",
    s!"border-color: {swatch.borderColor}",
    s!"border-width: {swatch.borderWidth}px",
    s!"border-style: {swatch.borderStyle}",
    s!"border-radius: {swatch.borderRadius}"
  ]

/-- STY-GRAPH-05 (#32a): inline style for an edge line-style sample, drawn as a
top border on a short fixed-width span (see `.bp_graph_legend_edge_swatch`). -/
def EdgeLegendSwatch.inlineStyle (swatch : EdgeLegendSwatch) : String :=
  String.intercalate "; " [
    s!"border-top-color: {swatch.color}",
    s!"border-top-width: {swatch.borderWidth}px",
    s!"border-top-style: {swatch.borderStyle}"
  ]

def statementBorderBlockedColor : String := "#b86b2e"
def statementBorderReadyColor : String := "#1c5fb8"
def statementBorderFormalizedColor : String := "#1c8c57"
def statementBorderMathlibColor : String := "#6a4fba"

def proofBackgroundNeutralColor : String := "#f4f6f8"
def proofBackgroundReadyColor : String := "#dbe8f7"
def proofBackgroundIncompleteColor : String := "#f5e6d2"
def proofBackgroundFormalizedColor : String := "#d7ede0"
-- STY-GRAPH-02 (#32b): this fill carries a white label (`proofStatusFontColor
-- .formalizedWithAncestors`) on ~62/79 nodes. The previous `#1c8c57` computed
-- white-on-fill ≈4.25:1 (below AA 4.5:1); darkened to `#1a8351` which computes
-- ≈4.76:1. Kept distinct from the lighter `statementBorderFormalizedColor`
-- (#1c8c57) border so the green stays semantic. The `--bp-color-accent-success`
-- token is intentionally left at #1c8c57 (different, non-white-text context).
def proofBackgroundFormalizedAncColor : String := "#1a8351"

def definitionBackgroundColor : String := "#ffffff"

/-- Supporting (un-annotated project) node colors. Muted grey fill + hairline
border + slate label, tuned — like every other baked graph-node color — for the
theme-invariant light graph canvas (see `graph.css`), so supporting nodes read as
subordinate to the authored blueprint nodes in both light and dark. -/
def supportingFillColor : String := "#eef1f5"
def supportingBorderColor : String := "#c3ccd6"
def supportingFontColor : String := "#586170"

def unresolvedFillColor : String := "#fee2e2"
def unresolvedBorderColor : String := "#b91c1c"
def unresolvedFontColor : String := "#7f1d1d"

def statementStatusBlockedText : String := "blocked"
def statementStatusReadyText : String := "ready to formalize"
def statementStatusFormalizedText : String := "formalized"
def statementStatusMathlibText : String := "in Mathlib"

def proofStatusNoneText : String := "not ready"
def proofStatusReadyText : String := "ready to formalize"
def proofStatusIncompleteText : String := "Lean code incomplete"
def proofStatusFormalizedText : String := "locally formalized"
def proofStatusFormalizedAncestorsText : String := "locally formalized + dependencies complete"

def warningLeanOnlyText : String := "Lean code present but informal statement is missing"
def warningMissingExternalText : String := "Associated Lean declaration is missing from the current environment"
def warningHiddenInGroupViewText : String := "Warning markers are not shown individually in Group View"
def edgeMixedText : String := "Thicker solid/dashed: statement + proof deps"
def groupEdgeMixedText : String := "Thicker solid: statement + proof deps"

/-- Edge color/style tokens keyed by dependency intent and origin. -/
def edgeAuxiliaryColor : String := "#94a3b8"
def edgeTechnicalColor : String := "#94a3b8"
/-- Distinct hue for automatically-inferred (non-manual) dependency edges.

In the all-declarations graph these inferred const-dependency edges vastly
outnumber the authored ones, so they use a lighter violet (and a thinner stroke,
via `edgeStyleAttrs`) to recede into a supporting layer without disappearing. -/
def edgeAutomaticColor : String := "#9a86d1"
/-- Thin stroke for the de-emphasized automatically-inferred edges (see
`edgeAutomaticColor`); overrides the base statement/proof penwidth so the inferred
const-dep mesh stays legible but never dominates the authored spine. -/
def edgeAutomaticPenwidth : String := "0.6"
/-- STY-GRAPH-14 (#32d): darker slate-grey for the dense proof-only (dotted,
    regular-intent) edges so they keep contrast at fit-zoom without matching the
    heavier dashed statement edges. Slightly darker than the default `#6b7280`. -/
def edgeProofOnlyColor : String := "#576070"

def edgeAuxiliaryText : String := "Dashed (slate): auxiliary dependency"
def edgeTechnicalText : String := "Dotted (slate): technical dependency"
def edgeAutomaticText : String := "Purple: automatically inferred dependency"
def graphLegendFullViewNote : String :=
  "Shape shows declaration kind, border shows statement status, fill shows proof status, and edge style separates statement from proof dependencies."

private def legendItem (label : String) (swatch? : Option LegendSwatch := none) : LegendItem :=
  { label, swatch? }

/-- STY-GRAPH-05 (#32a): build an Edges legend item carrying a line-style sample
mirroring the DOT edge styling (color/weight/dash pattern). -/
private def edgeLegendItem (label : String) (swatch : EdgeLegendSwatch) : LegendItem :=
  { label, edgeSwatch? := some swatch }

def graphLegendGroups (includeMathlib : Bool := false) (includeSupporting : Bool := false) :
    Array LegendGroup :=
  let statementItems :=
    #[
      legendItem "Blocked" (some { borderColor := statementBorderBlockedColor }),
      legendItem "Ready to formalize" (some { borderColor := statementBorderReadyColor }),
      legendItem "Formalized" (some { borderColor := statementBorderFormalizedColor })
    ]
  let statementItems :=
    if includeMathlib then
      statementItems.push (legendItem "In Mathlib" (some { borderColor := statementBorderMathlibColor }))
    else
      statementItems
  let supportingGroup : Array LegendGroup :=
    if includeSupporting then
      #[{
        key := "supporting"
        title := "Supporting Declarations"
        summary? := some "Muted nodes are project declarations without an authored blueprint node, shown with their real Lean dependencies."
        items := #[
          legendItem "Supporting declaration"
            (some { background := supportingFillColor, borderColor := supportingBorderColor })
        ]
      }]
    else
      #[]
  supportingGroup ++ #[
    {
      key := "shape"
      title := "Shapes"
      summary? := some "Node outline shows whether the item is definition-like or theorem-like."
      items := #[
        legendItem "Definition" (some { borderRadius := "0.2rem" }),
        legendItem "Theorem / lemma / corollary" (some { borderRadius := "999px" })
      ]
    },
    {
      key := "statement"
      title := "Statement Border"
      summary? := some "Border color tracks whether the statement is blocked, ready, or already formalized."
      items := statementItems
    },
    {
      key := "proof"
      title := "Proof Status"
      summary? := some "Fill color tracks proof readiness independently from statement progress."
      items := #[
        legendItem proofStatusNoneText (some { background := proofBackgroundNeutralColor }),
        legendItem proofStatusReadyText (some { background := proofBackgroundReadyColor }),
        legendItem proofStatusIncompleteText (some { background := proofBackgroundIncompleteColor }),
        legendItem proofStatusFormalizedText (some { background := proofBackgroundFormalizedColor }),
        legendItem proofStatusFormalizedAncestorsText
          (some { background := proofBackgroundFormalizedAncColor, borderColor := statementBorderMathlibColor })
      ]
    },
    {
      key := "warning"
      title := "Warning Markers"
      summary? := some "Border treatments flag missing references, missing declarations, or Lean-only nodes without an informal statement."
      items := #[
        legendItem "Unknown reference"
          (some { background := unresolvedFillColor, borderColor := unresolvedBorderColor }),
        legendItem "Lean code, informal statement missing"
          (some {
            background := definitionBackgroundColor
            borderStyle := "dashed"
          }),
        legendItem "Missing external Lean declaration"
          (some {
            background := definitionBackgroundColor
            borderStyle := "dotted"
          })
      ]
    },
    {
      key := "edge"
      title := "Edges"
      summary? := some "Line style distinguishes statement dependencies from proof-only dependencies; intent and origin add further styling."
      items := #[
        edgeLegendItem "Solid: statement deps from theorem-like sources"
          { borderStyle := "solid", borderWidth := "1.6" },
        edgeLegendItem "Dashed: statement deps from box-shaped sources"
          { borderStyle := "dashed", borderWidth := "2" },
        edgeLegendItem "Dotted: proof-only deps"
          { color := edgeProofOnlyColor, borderStyle := "dotted", borderWidth := "1.8" },
        edgeLegendItem edgeMixedText
          { borderStyle := "solid", borderWidth := "2.6" },
        edgeLegendItem edgeAuxiliaryText
          { color := edgeAuxiliaryColor, borderStyle := "dashed", borderWidth := "2" },
        edgeLegendItem edgeTechnicalText
          { color := edgeTechnicalColor, borderStyle := "dotted", borderWidth := "1.8" },
        edgeLegendItem edgeAutomaticText
          { color := edgeAutomaticColor, borderStyle := "solid", borderWidth := "1" }
      ]
    }
  ]

def graphLegendGroupViewNote : String :=
  "Group View uses tab-shaped aggregate group nodes; labels use group titles, colors are averaged over child nodes, and individual warning markers are hidden."

def groupGraphLegendGroups : Array LegendGroup :=
  #[
    {
      key := "group-view"
      title := "Group View"
      summary? := some "Group nodes summarize children instead of showing each declaration separately."
      items := #[
        legendItem "Tab nodes summarize grouped children",
        legendItem "Border/fill colors average child node status colors",
        legendItem warningHiddenInGroupViewText
      ]
    },
    {
      key := "group-edge"
      title := "Edges"
      summary? := some "Grouped edges compress many child edges into one aggregate connection."
      items := #[
        edgeLegendItem "Solid: at least one statement dep"
          { borderStyle := "solid", borderWidth := "1.6" },
        edgeLegendItem "Dotted: proof-only deps"
          { color := edgeProofOnlyColor, borderStyle := "dotted", borderWidth := "1.8" },
        edgeLegendItem groupEdgeMixedText
          { borderStyle := "solid", borderWidth := "2.6" }
      ]
    }
  ]

def statementUses (node : Data.Node) : Array Data.UseRef :=
  (node.statement.map (·.deps)).getD #[]

def proofUses (node : Data.Node) : Array Data.UseRef :=
  (node.proof.map (·.deps)).getD #[]

def statementDeps (node : Data.Node) : Array Name :=
  (statementUses node).map (fun useRef => (useRef.label : Name))

def proofDeps (node : Data.Node) : Array Name :=
  (proofUses node).map (fun useRef => (useRef.label : Name))

def allDeps (node : Data.Node) : Array Name :=
  statementDeps node ++ proofDeps node

structure ExternalCodeStatus where
  isMissing : Name → Bool := fun _ => false
  provedStatus : Name → Data.ProvedStatus := fun _ => .proved
  /--
  Whether a resolved declaration lives in Mathlib. Defaults to `false` so every
  existing `{}` call site keeps its previous behavior and the predicate degrades
  gracefully when Mathlib membership cannot be determined.
  -/
  inMathlib : Name → Bool := fun _ => false

structure CodeHealth where
  hasAssociatedCode : Bool := false
  totalDecls : Nat := 0
  presentDecls : Nat := 0
  missingDecls : Nat := 0
  statementAxisCount : Nat := 0
  proofAxisCount : Nat := 0
  statementBlockCount : Nat := 0
  proofBlockCount : Nat := 0
  anyGapCount : Nat := 0
  hasAxiomLike : Bool := false
deriving Inhabited, Repr

private def statusGapIncrements (status : Data.ProvedStatus) : Nat × Nat × Nat :=
  match status.hasTypeGap, status.hasProofGap with
  | false, false => (0, 0, 0)
  | true, false => (1, 0, 1)
  | false, true => (0, 1, 1)
  | true, true => (1, 1, 1)

private def CodeHealth.bump (health : CodeHealth) (kind : Data.NodeKind) (status : Data.ProvedStatus) : CodeHealth :=
  let (statementAxisInc, proofAxisInc, anyInc) := statusGapIncrements status
  let statementBlockInc := if status.blocksStatementCompletion kind then 1 else 0
  let proofBlockInc := if status.blocksProofCompletion then 1 else 0
  {
    health with
      statementAxisCount := health.statementAxisCount + statementAxisInc
      proofAxisCount := health.proofAxisCount + proofAxisInc
      statementBlockCount := health.statementBlockCount + statementBlockInc
      proofBlockCount := health.proofBlockCount + proofBlockInc
      anyGapCount := health.anyGapCount + anyInc
      hasAxiomLike := health.hasAxiomLike || status.isAxiomLike
  }

private def CodeHealth.merge (left right : CodeHealth) : CodeHealth :=
  {
    hasAssociatedCode := left.hasAssociatedCode || right.hasAssociatedCode
    totalDecls := left.totalDecls + right.totalDecls
    presentDecls := left.presentDecls + right.presentDecls
    missingDecls := left.missingDecls + right.missingDecls
    statementAxisCount := left.statementAxisCount + right.statementAxisCount
    proofAxisCount := left.proofAxisCount + right.proofAxisCount
    statementBlockCount := left.statementBlockCount + right.statementBlockCount
    proofBlockCount := left.proofBlockCount + right.proofBlockCount
    anyGapCount := left.anyGapCount + right.anyGapCount
    hasAxiomLike := left.hasAxiomLike || right.hasAxiomLike
  }

private def codeHealthOfInlineDecls (kind : Data.NodeKind) (statuses : Array Data.ProvedStatus) : CodeHealth :=
  statuses.foldl
      (init := { hasAssociatedCode := true, totalDecls := statuses.size, presentDecls := statuses.size })
      fun health status => health.bump kind status

def codeHealthOfExternalDecls (kind : Data.NodeKind) (external : ExternalCodeStatus) (decls : Array Data.ExternalRef) : CodeHealth :=
  decls.foldl
      (init := { hasAssociatedCode := true, totalDecls := decls.size })
      fun health decl =>
    let missing := !decl.present || external.isMissing decl.canonical
    if missing then
      { health with missingDecls := health.missingDecls + 1 }
    else
      let status := Data.ProvedStatus.mergeConservative decl.provedStatus (external.provedStatus decl.canonical)
      let health := health.bump kind status
      { health with presentDecls := health.presentDecls + 1 }

private def codeHealthOfOneCodeRef (kind : Data.NodeKind) (external : ExternalCodeStatus)
    (codeRef : Data.CodeRef) : CodeHealth :=
  match codeRef with
  | .external decls => codeHealthOfExternalDecls kind external decls
  | .literate code =>
    let statuses :=
      (code.definedDefs.map (·.provedStatus)) ++ (code.definedTheorems.map (·.provedStatus))
    codeHealthOfInlineDecls kind statuses

def codeHealthOfLeanCode (kind : Data.NodeKind) (external : ExternalCodeStatus)
    (leanCode : Array Data.CodeRef) : CodeHealth :=
  leanCode.foldl (init := {}) fun health codeRef =>
    health.merge (codeHealthOfOneCodeRef kind external codeRef)

def codeHealthOfBlockSource (kind : Data.NodeKind) (external : ExternalCodeStatus)
    (source? : Option Informal.BlockCodeData) : CodeHealth :=
  match source? with
  | none => {}
  | some (.external decls) => codeHealthOfExternalDecls kind external decls
  | some (.inline codeData) =>
    let statuses :=
      (codeData.definedDefs.map (·.provedStatus)) ++ (codeData.definedTheorems.map (·.provedStatus))
    codeHealthOfInlineDecls kind statuses

def nodeCodeHealth (external : ExternalCodeStatus) (node : Data.Node) : CodeHealth :=
  codeHealthOfLeanCode node.kind external node.leanCode

def CodeHealth.hasMissingExternalDecls (health : CodeHealth) : Bool :=
  health.missingDecls > 0

def CodeHealth.hasStatementGaps (health : CodeHealth) : Bool :=
  health.statementBlockCount > 0

def CodeHealth.hasProofGaps (health : CodeHealth) : Bool :=
  health.proofBlockCount > 0

def CodeHealth.hasAnyGaps (health : CodeHealth) : Bool :=
  health.anyGapCount > 0

def CodeHealth.localStatementFormalized (health : CodeHealth) : Bool :=
  health.hasAssociatedCode && !health.hasMissingExternalDecls && !health.hasStatementGaps

def CodeHealth.localProofFormalized (health : CodeHealth) : Bool :=
  health.hasAssociatedCode && !health.hasMissingExternalDecls && !health.hasAnyGaps

def CodeHealth.incompleteAssociatedCode (health : CodeHealth) : Bool :=
  health.hasAssociatedCode && !health.hasMissingExternalDecls && health.hasAnyGaps

def CodeHealth.localFormalized (health : CodeHealth) (kind : Data.NodeKind) : Bool :=
  if kind.isTheoremLike then
    health.localProofFormalized
  else if kind == Data.NodeKind.definition then
    health.localStatementFormalized
  else
    false

def nodeExternalDecls (node : Data.Node) : Array Data.ExternalRef :=
  node.externalRefs

def nodeHasAssociatedCode (node : Data.Node) : Bool :=
  node.hasAssociatedCode

def externalDeclMissing (external : ExternalCodeStatus) (decl : Data.ExternalRef) : Bool :=
  !decl.present || external.isMissing decl.canonical

def externalDeclProvedStatus (external : ExternalCodeStatus) (decl : Data.ExternalRef) : Data.ProvedStatus :=
  Data.ProvedStatus.mergeConservative decl.provedStatus (external.provedStatus decl.canonical)

def nodeHasMissingExternalDecls (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).hasMissingExternalDecls

def nodeHasStatementSorries (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).hasStatementGaps

def nodeHasProofSorries (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).hasProofGaps

def nodeHasSorries (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).hasAnyGaps

def nodeLocalStatementFormalized (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).localStatementFormalized

def nodeLocalProofFormalized (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).localProofFormalized

def nodeLocalFormalized (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  (nodeCodeHealth external node).localFormalized node.kind

def eraseDups (xs : Array Name) : Array Name :=
  xs.foldl (init := #[]) fun acc x => if acc.contains x then acc else acc.push x

/--
Whether a node is considered formalized in Mathlib.

Consults `ExternalCodeStatus.inMathlib` over the node's resolved external
declarations rather than the Blueprint environment state. A node counts as in
Mathlib only when it has external declarations and every one of them resolves to
a Mathlib module, so the default `inMathlib := fun _ => false` predicate keeps
every node dark (graceful degradation when there is no Mathlib dependency).
-/
def nodeInMathlib (external : ExternalCodeStatus) (node : Data.Node) : Bool :=
  let decls := nodeExternalDecls node
  !decls.isEmpty && decls.all (fun decl => external.inMathlib decl.canonical)

/--
Build a Mathlib-membership predicate from the current `CoreM` environment.

For each declaration name, looks up its defining module via
`Environment.getModuleIdxFor?` and tests whether that module name has the
`` `Mathlib `` prefix. Declarations that are not imported resolve to `false`.
-/
def mkInMathlibPredicate : Lean.CoreM (Name → Bool) := do
  let env ← Lean.getEnv
  let moduleNames := env.header.moduleNames
  return fun declName =>
    match env.getModuleIdxFor? declName with
    | none => false
    | some idx =>
      match moduleNames[idx.toNat]? with
      | none => false
      | some moduleName => (`Mathlib).isPrefixOf moduleName

inductive DepTraversal where
  | statement
  | proof
  | both
deriving Inhabited, Repr

def depsForTraversal (mode : DepTraversal) (node : Data.Node) : Array Name :=
  match mode with
  | .statement => statementDeps node
  | .proof => proofDeps node
  | .both => allDeps node

partial def depsClosureComplete (external : ExternalCodeStatus) (state : Environment.State) (mode : DepTraversal)
    (roots : Array Name) (visited : NameSet := {}) : Bool :=
  roots.all fun dep =>
    if visited.contains dep then
      true
    else
      match state.data.get? dep with
      | none => false
      | some node =>
        if !nodeLocalFormalized external node then
          false
        else
          let visited := visited.insert dep
          depsClosureComplete external state mode (depsForTraversal mode node) visited

def nodeAncestorsFormalized (external : ExternalCodeStatus) (state : Environment.State) (node : Data.Node) : Bool :=
  depsClosureComplete external state .both (allDeps node)

def statementStatus (external : ExternalCodeStatus) (state : Environment.State) (_label : Name)
    (node : Data.Node) : StatementStatus :=
  if nodeInMathlib external node then
    .mathlib
  else if nodeLocalStatementFormalized external node then
    .formalized
  else if depsClosureComplete external state .statement (statementDeps node) then
    .ready
  else
    .blocked

def proofStatus (external : ExternalCodeStatus) (state : Environment.State) (_label : Name)
    (node : Data.Node) : ProofStatus :=
  let health := nodeCodeHealth external node
  if !node.kind.isTheoremLike then
    if health.localStatementFormalized then
      if nodeAncestorsFormalized external state node then .formalizedWithAncestors else .formalized
    else if health.incompleteAssociatedCode then
      .incomplete
    else if depsClosureComplete external state .statement (statementDeps node) then
      .ready
    else
      .none
  else if health.localProofFormalized then
    if nodeAncestorsFormalized external state node then .formalizedWithAncestors else .formalized
  else if health.incompleteAssociatedCode then
    .incomplete
  else
    let stmtDepsDone := depsClosureComplete external state .statement (statementDeps node)
    let proofDepsDone := depsClosureComplete external state .proof (proofDeps node)
    if stmtDepsDone && proofDepsDone then .ready else .none

def nodeWarnings (external : ExternalCodeStatus) (_state : Environment.State) (_label : Name)
    (node : Data.Node) : WarningFlags :=
  let health := nodeCodeHealth external node
  {
    unknownRef := false
    leanOnlyNoStatement := health.hasAssociatedCode && node.statement.isNone
    missingExternalDecl := health.hasAssociatedCode && health.hasMissingExternalDecls
  }

def statementStatusBorderColor : StatementStatus → String
  | .blocked => statementBorderBlockedColor
  | .ready => statementBorderReadyColor
  | .formalized => statementBorderFormalizedColor
  | .mathlib => statementBorderMathlibColor

def proofStatusFillColor (kind : Data.NodeKind) : ProofStatus → String
  | .none =>
    if kind.isTheoremLike then proofBackgroundNeutralColor else definitionBackgroundColor
  | .ready => proofBackgroundReadyColor
  | .incomplete => proofBackgroundIncompleteColor
  | .formalized => proofBackgroundFormalizedColor
  | .formalizedWithAncestors => proofBackgroundFormalizedAncColor

def proofStatusFontColor : ProofStatus → String
  | .formalizedWithAncestors => "#ffffff"
  | _ => "#111827"

def kindShape (kind : Data.NodeKind) : String :=
  if kind.isTheoremLike then "ellipse" else "box"

def StatementStatus.toText : StatementStatus → String
  | .blocked => statementStatusBlockedText
  | .ready => statementStatusReadyText
  | .formalized => statementStatusFormalizedText
  | .mathlib => statementStatusMathlibText

def ProofStatus.toText : ProofStatus → String
  | .none => proofStatusNoneText
  | .ready => proofStatusReadyText
  | .incomplete => proofStatusIncompleteText
  | .formalized => proofStatusFormalizedText
  | .formalizedWithAncestors => proofStatusFormalizedAncestorsText

def warningTooltipParts (warnings : WarningFlags) : List String :=
  (if warnings.leanOnlyNoStatement then [warningLeanOnlyText] else []) ++
  (if warnings.missingExternalDecl then [warningMissingExternalText] else [])

private def styleTokensForWarnings (warnings : WarningFlags) : Array String :=
  let tokens : Array String := #["filled"]
  let tokens :=
    if warnings.leanOnlyNoStatement then tokens.push "dashed" else tokens
  let tokens :=
    if warnings.missingExternalDecl then tokens.push "dotted" else tokens
  tokens

def mkStyledNode (kind : Data.NodeKind) (label : Name) (deps proofDeps : Array Name)
    (parent? : Option Name)
    (statement : StatementStatus) (proof : ProofStatus) (warnings : WarningFlags)
    (ref? : Option Ref)
    (stmtUseRefs proofUseRefs : Array Data.UseRef := #[]) : GraphNode Ref :=
  if warnings.unknownRef then
    {
      label
      deps
      proofDeps
      parent?
      shape := "box"
      style := "filled"
      fillcolor := unresolvedFillColor
      color := unresolvedBorderColor
      penwidth := "2.2"
      fontcolor := unresolvedFontColor
      peripheries := 1
      gradientangle? := none
      tooltip? := some s!"Unknown reference: {label}"
      ref?
      cssClass? := some (statusCssClass statement)
      statementUses := stmtUseRefs
      proofUses := proofUseRefs
    }
  else
    let shape := kindShape kind
    let baseFill := proofStatusFillColor kind proof
    let styleTokens := styleTokensForWarnings warnings
    let style := String.intercalate "," styleTokens.toList
    let tooltipParts :=
      [s!"Statement: {statement.toText}", s!"Proof: {proof.toText}"] ++ warningTooltipParts warnings
    let tooltip? :=
      if tooltipParts.isEmpty then none else some (String.intercalate " | " tooltipParts)
    {
      label
      deps
      proofDeps
      parent?
      shape
      style
      fillcolor := baseFill
      color := statementStatusBorderColor statement
      penwidth := "2.2"
      fontcolor := proofStatusFontColor proof
      peripheries := 1
      gradientangle? := none
      tooltip?
      ref?
      cssClass? := some (statusCssClass statement)
      statementUses := stmtUseRefs
      proofUses := proofUseRefs
    }

def expandLabels (state : Environment.State) (roots : Array Name) : Array Name :=
  Id.run <| do
    let mut queue : Array Name := eraseDups roots
    let mut enqueued : NameSet := queue.foldl (init := {}) fun acc label => acc.insert label
    let mut seen : NameSet := {}
    let mut idx : Nat := 0
    while idx < queue.size do
      let label := queue[idx]!
      idx := idx + 1
      if seen.contains label then
        continue
      seen := seen.insert label
      match state.data.get? label with
      | none => pure ()
      | some node =>
        for dep in allDeps node do
          if !enqueued.contains dep then
            queue := queue.push dep
            enqueued := enqueued.insert dep
    return queue

def mkNode (external : ExternalCodeStatus) (state : Environment.State)
    (resolveRef? : Name → Option Ref) (label : Name) : GraphNode Ref :=
  match state.data.get? label with
  | some node =>
    let deps := statementDeps node
    let nodeProofDeps := proofDeps node
    let statement := statementStatus external state label node
    let proof := proofStatus external state label node
    let warnings := nodeWarnings external state label node
    let ref? := resolveRef? label
    mkStyledNode node.kind label deps nodeProofDeps node.parent statement proof warnings ref?
      (statementUses node) (proofUses node)
  | none =>
    let unresolvedWarnings : WarningFlags := { unknownRef := true }
    mkStyledNode Data.NodeKind.definition label #[] #[] none .blocked .none unresolvedWarnings none

def build (state : Environment.State) (roots : Array Name) (resolveRef? : Name → Option Ref := fun _ => none) :
    Graph Ref :=
  let labels := expandLabels state roots
  let external : ExternalCodeStatus := {}
  labels.map (mkNode external state resolveRef?)

def buildWithExternal (state : Environment.State) (roots : Array Name)
    (external : ExternalCodeStatus) (resolveRef? : Name → Option Ref := fun _ => none) : Graph Ref :=
  let labels := expandLabels state roots
  labels.map (mkNode external state resolveRef?)

private def edgeAxes (isStatement isProof : Bool) : Array EdgeAxis :=
  let axes := #[]
  let axes := if isStatement then axes.push .statement else axes
  if isProof then axes.push .proof else axes

def edgesForNode (node : GraphNode Ref) : Array EdgeData :=
  let stmtDeps := eraseDups node.deps
  let proofDeps := eraseDups node.proofDeps
  let deps := proofDeps.foldl (init := stmtDeps) fun deps dep =>
    if deps.contains dep then deps else deps.push dep
  -- Merge the statement and proof use-refs by label so each edge carries the
  -- intended origin/intent (a manual ref wins over an automatic duplicate).
  let mergedUses : Array Data.UseRef :=
    Data.UseRef.mergeByLabel node.statementUses node.proofUses
  let useRefFor (dep : Name) : Option Data.UseRef :=
    mergedUses.find? (fun useRef => (useRef.label : Name) == dep)
  deps.map fun dep =>
    let useRef? := useRefFor dep
    {
      source := dep
      target := node.label
      axes := edgeAxes (stmtDeps.contains dep) (proofDeps.contains dep)
      origin := (useRef?.map (·.origin)).getD .manual
      intent := (useRef?.map (·.intent)).getD .regular
    }

def edgesForGraph (graph : Graph Ref) : Array EdgeData :=
  let known : NameSet := graph.foldl (init := {}) fun acc node => acc.insert node.label
  graph.foldl (init := #[]) fun edges node =>
    edges ++ (edgesForNode node).filter (fun edge => known.contains edge.source)

def graphParentChildren (graph : Graph Ref) : Lean.NameMap (Array Name) :=
  graph.foldl (init := ({} : Lean.NameMap (Array Name))) fun acc node =>
    match node.parent? with
    | none => acc
    | some parent =>
      let children := acc.getD parent #[]
      acc.insert parent (children.push node.label)

def graphNodeParents (graph : Graph Ref) : Lean.NameMap Name :=
  graph.foldl (init := ({} : Lean.NameMap Name)) fun acc node =>
    match node.parent? with
    | none => acc
    | some parent => acc.insert node.label parent

private def groupTitleMap (groupTitles : Array (Name × String)) : Lean.NameMap String :=
  groupTitles.foldl (init := ({} : Lean.NameMap String)) fun acc (group, title) =>
    acc.insert group title

def groupTitle (groupTitles : Lean.NameMap String) (parent : Name) : String :=
  let title := (groupTitles.getD parent parent.toString).trimAscii.toString
  if title.isEmpty then parent.toString else title

def groupDataForGraph (graph : Graph Ref) (groupTitles : Array (Name × String) := #[]) :
    Array GroupData :=
  let titleMap := groupTitleMap groupTitles
  graphParentChildren graph |>.toArray
    |>.map (fun (parent, children) => {
      label := parent
      title := groupTitle titleMap parent
      declared := titleMap.contains parent
      children
    })
    |>.qsort (fun a b => a.title < b.title)

private def nodeTitle (resolveTitle? : Name → Option String) (label : Name) : String :=
  match resolveTitle? label with
  | some title =>
    let title := title.trimAscii.toString
    if title.isEmpty then label.toString else title
  | none => label.toString

def nodeDataWithExternal
    (external : ExternalCodeStatus)
    (state : Environment.State)
    (resolveHref? : Name → Option String)
    (resolveTitle? : Name → Option String)
    (graphNode : GraphNode String) : NodeData :=
  let label := graphNode.label
  match state.data.get? label with
  | some node =>
    let statement := statementStatus external state label node
    let proof := proofStatus external state label node
    let warnings := nodeWarnings external state label node
    {
      label
      title := nodeTitle resolveTitle? label
      displayLabel := graphNode.displayLabel
      kind := some node.kind
      parent := node.parent
      href := resolveHref? label
      previewKey := PreviewCache.statementKey label
      statementUses := statementUses node
      proofUses := proofUses node
      statementStatus := statement
      proofStatus := proof
      warnings
      visual := NodeVisual.ofGraphNode graphNode
    }
  | none =>
    {
      label
      title := nodeTitle resolveTitle? label
      displayLabel := graphNode.displayLabel
      kind := none
      parent := none
      href := resolveHref? label
      previewKey := PreviewCache.statementKey label
      statementUses := #[]
      proofUses := #[]
      statementStatus := .blocked
      proofStatus := .none
      warnings := { unknownRef := true }
      visual := NodeVisual.ofGraphNode graphNode
    }

def buildDataWithExternal
    (state : Environment.State)
    (roots : Array Name)
    (external : ExternalCodeStatus)
    (resolveHref? : Name → Option String := fun _ => none)
    (resolveTitle? : Name → Option String := fun _ => none)
    (groupTitles : Array (Name × String) := #[]) : GraphData :=
  let graph := buildWithExternal state roots external resolveHref?
  {
    nodes := graph.map (nodeDataWithExternal external state resolveHref? resolveTitle?)
    edges := edgesForGraph graph
    groups := groupDataForGraph graph groupTitles
  }

def buildData
    (state : Environment.State)
    (roots : Array Name)
    (resolveHref? : Name → Option String := fun _ => none)
    (resolveTitle? : Name → Option String := fun _ => none)
    (groupTitles : Array (Name × String) := #[]) : GraphData :=
  buildDataWithExternal state roots {} resolveHref? resolveTitle? groupTitles

/--
In-namespace const-level dependencies of a declaration, split into statement deps
(constants in its type) and proof deps (constants in its value), restricted to
`projectDeclSet` and excluding the declaration itself. Proof deps drop any label
already present as a statement dep. This is the real Lean dependency structure the
supporting-node graph is built from. -/
def projectConstDeps (projectDeclSet : NameSet) (root : Name) (info : ConstantInfo) :
    Array Name × Array Name :=
  let keep := fun (consts : Array Name) =>
    consts.foldl (init := (#[] : Array Name)) fun acc c =>
      let c := c.eraseMacroScopes
      if c != root && projectDeclSet.contains c && !acc.contains c then acc.push c else acc
  let typeDeps := keep info.type.getUsedConstants
  let valueConsts : Array Name :=
    match info with
    | .defnInfo i => i.value.getUsedConstants
    | .thmInfo i => i.value.getUsedConstants
    | .opaqueInfo i => i.value.getUsedConstants
    | _ => #[]
  let valueDeps := (keep valueConsts).filter (fun c => !typeDeps.contains c)
  (typeDeps, valueDeps)

/-- Short display label for a supporting node: the declaration's last name
component (namespace stripped), falling back to the full name. -/
private def supportingDisplayLabel (label : Name) : String :=
  match label.components.getLast? with
  | some c => c.toString
  | none => label.toString

/--
Build a subordinate "supporting" graph node for an un-annotated project
declaration.

Supporting nodes carry the muted supporting visual, mark themselves via
`supporting := true`, and count as formalized (they are real Lean declarations).
`statementUses`/`proofUses` are supplied by the caller from the declaration's
in-namespace const dependencies (`projectConstDeps`). -/
def mkSupportingNodeData (kind : Data.NodeKind) (label : Name)
    (statementUses proofUses : Array Data.UseRef) : NodeData :=
  {
    label
    title := supportingDisplayLabel label
    displayLabel := supportingDisplayLabel label
    kind := some kind
    parent := none
    href := none
    previewKey := PreviewCache.statementKey label
    statementUses
    proofUses
    statementStatus := .formalized
    proofStatus := .none
    warnings := {}
    visual := {
      shape := kindShape kind
      style := "filled"
      fillcolor := supportingFillColor
      color := supportingBorderColor
      penwidth := "1.1"
      fontcolor := supportingFontColor
      peripheries := 1
      gradientangle? := none
      tooltip? := some s!"Supporting declaration: {label}"
    }
    supporting := true
  }

def escapeDotString (s : String) : String :=
  let s := s.replace "\\" "\\\\"
  let s := s.replace "\"" "\\\""
  let s := s.replace "\n" "\\n"
  s.replace "\r" ""

def dotIndent (n : Nat) : String := String.ofList (List.replicate n ' ')

/--
Extra DOT edge attributes derived from a dependency edge's intent/origin.

Returns `#[]` for the default (`regular` intent, `manual` origin) so existing
graph output is byte-identical when no richer metadata is present. Non-regular
intent adds a style + slate color.

`supporting` is `true` when the edge touches a muted "supporting" node (present
only in the all-declarations graph). STY-GRAPH-14: the lighter-violet + thinner
de-emphasis is applied *only* to those edges, so the dense inferred supporting
mesh recedes while authored blueprint↔blueprint edges keep their base
statement/proof styling (e.g. the darkened `edgeProofOnlyColor` dotted edges).
Automatic-origin edges between two authored nodes are therefore left untouched.
-/
def edgeStyleAttrs (origin : Data.UseOrigin) (intent : Data.UseIntent)
    (supporting : Bool) : Array String :=
  let attrs : Array String :=
    match intent with
    | .regular => #[]
    | .auxiliary => #["style=dashed", s!"color=\"{edgeAuxiliaryColor}\""]
    | .technical => #["style=dotted", s!"color=\"{edgeTechnicalColor}\""]
  match origin with
  | .manual => attrs
  | .automatic =>
    if supporting then
      -- De-emphasize the inferred supporting mesh: recolor to the lighter violet
      -- and thin the stroke. `dedupEdgeAttrs` collapses these against any base
      -- color/penwidth so each edge emits exactly one of each (violet/0.6 win).
      (attrs.push s!"color=\"{edgeAutomaticColor}\"").push s!"penwidth={edgeAutomaticPenwidth}"
    else attrs

/-- Collapse DOT edge attributes to a single occurrence per key, keeping the LAST
value (matching Graphviz precedence, where a later attribute wins). First-appearance
order is preserved and lists with no duplicate keys are returned byte-identically,
so edges carrying no override are unaffected. Prevents the `color=…, color=…` /
`penwidth=…, penwidth=…` duplicates that arise when an override attribute is
appended after a base attribute of the same key. -/
def dedupEdgeAttrs (attrs : Array String) : Array String :=
  let keyOf : String → String := fun a => (a.splitOn "=").headD a
  attrs.foldr (init := (#[] : Array String)) fun a acc =>
    if acc.any (fun b => keyOf b == keyOf a) then acc else #[a] ++ acc

/-- Build a DOT edge line, layering intent/origin styling after the base attrs.
`supporting` marks an edge touching a supporting node (see `edgeStyleAttrs`);
`dedupEdgeAttrs` ensures the layered attributes never emit a duplicate key. -/
def edgeLineWithStyle (src tgt : Name) (baseAttrs : Array String)
    (origin : Data.UseOrigin) (intent : Data.UseIntent) (supporting : Bool) : String :=
  let attrs := dedupEdgeAttrs (baseAttrs ++ edgeStyleAttrs origin intent supporting)
  if attrs.isEmpty then
    s!"  \"{src}\" -> \"{tgt}\";"
  else
    s!"  \"{src}\" -> \"{tgt}\" [{String.intercalate ", " attrs.toList}];"

def graphNodeSvgId (label : Name) : String :=
  Informal.HtmlId.prefixed "bp-node" (toString label)

partial def emitGroupClusterLines (nodeDefs : NameMap String) (groupMembers : NameMap (Array Name))
    (groupChildren : NameMap (Array Name)) (groupIds : NameMap Nat)
    (groupLabel? : Name → Option String) (groupTooltip? : Name → Option String)
    (group : Name) (level fuel : Nat)
    (visited : NameSet) : Array String × NameSet :=
  if fuel == 0 || visited.contains group then
    (#[], visited)
  else
    let visited := visited.insert group
    let pad := dotIndent level
    let pad2 := dotIndent (level + 2)
    let clusterName := s!"cluster_{groupIds.getD group 0}"
    let groupLabel :=
      match groupLabel? group with
      | some label =>
        let label := label.trimAscii.toString
        if label.isEmpty then toString group else label
      | none => toString group
    let openLine := pad ++ s!"subgraph \"{escapeDotString clusterName}\" " ++ "{"
    let clusterMeta : Array String :=
      let base : Array String := #[
        s!"{pad2}label=\"{escapeDotString groupLabel}\";",
        s!"{pad2}style=\"rounded,dashed\";",
        s!"{pad2}color=\"#cbd5e1\";",
        s!"{pad2}penwidth=1.2;"
      ]
      -- Surface the full descriptive title on hover when the label was abbreviated.
      match groupTooltip? group with
      | some tip =>
        let tip := tip.trimAscii.toString
        if tip.isEmpty then base
        else base.push s!"{pad2}tooltip=\"{escapeDotString tip}\";"
      | none => base
    let memberLines := (groupMembers.getD group #[]).foldl (init := (#[] : Array String)) fun acc label =>
      match nodeDefs.get? label with
      | some line => acc.push s!"{pad2}{line}"
      | none => acc
    let (childLines, visited) :=
      (groupChildren.getD group #[]).foldl (init := ((#[] : Array String), visited)) fun (acc, visited) child =>
        let (lines, visited) := emitGroupClusterLines nodeDefs groupMembers groupChildren groupIds groupLabel? groupTooltip? child (level + 2) (fuel - 1) visited
        (acc ++ lines, visited)
    let closeLine := pad ++ "}"
    ((#[openLine] ++ clusterMeta ++ memberLines ++ childLines).push closeLine, visited)

def Graph.toDot (g : Graph Ref) (header : String)
    (groupLabel? : Option (Name → Option String) := none)
    (groupTooltip? : Option (Name → Option String) := none)
    (refAttrs? : Option (Ref → Option String) := none) : String :=
  let known : NameSet := g.foldl (init := {}) fun acc node => acc.insert node.label
  let defLike : NameSet := g.foldl (init := {}) fun acc node =>
    if node.shape == "box" then acc.insert node.label else acc
  -- Labels of the muted "supporting" nodes (all-declarations graph only), detected
  -- via the `bp-node-supporting` marker class the same way node sizing is (below).
  -- STY-GRAPH-14: only edges touching one of these get the de-emphasized violet.
  let supportingSet : NameSet := g.foldl (init := {}) fun acc node =>
    if (node.cssClass?.getD "" |>.splitOn " ").contains "bp-node-supporting" then
      acc.insert node.label
    else acc
  let nodeByLabel : NameMap (GraphNode Ref) :=
    g.foldl (init := ({} : NameMap (GraphNode Ref))) fun acc node => acc.insert node.label node
  let (nodeDefs, groupMembers, edges) :=
    g.foldl
      (init := (({} : NameMap String), ({} : NameMap (Array Name)), (#[] : Array String)))
      fun (nodeDefs, groupMembers, edges) node =>
        let attrs :=
          let base : Array String := #[
            s!"id=\"{escapeDotString (graphNodeSvgId node.label)}\"",
            s!"label=\"{escapeDotString node.displayLabel}\"",
            s!"shape=\"{escapeDotString node.shape}\"",
            s!"style=\"{escapeDotString node.style}\"",
            s!"fillcolor=\"{escapeDotString node.fillcolor}\"",
            s!"color=\"{escapeDotString node.color}\"",
            s!"penwidth=\"{escapeDotString node.penwidth}\"",
            s!"fontcolor=\"{escapeDotString node.fontcolor}\"",
            s!"peripheries={node.peripheries}"
          ]
          let base :=
            match node.gradientangle? with
            | some gradientangle => base.push s!"gradientangle={gradientangle}"
            | none => base
          let base :=
            match node.tooltip? with
            | some tooltip => base.push s!"tooltip=\"{escapeDotString tooltip}\""
            | none => base
          let base :=
            match node.cssClass? with
            | some cls => base.push s!"class=\"{escapeDotString cls}\""
            | none => base
          -- STY-GRAPH: shrink the muted "supporting" nodes (present only in the
          -- all-declarations graph) so the authored nodes read as the primary
          -- layer and the wide supporting ranks take far less horizontal room —
          -- the main lever against the flat, very-wide fit-zoom band. Sizes are
          -- minimums (`fixedsize` defaults false), so long labels still expand.
          let base :=
            if (node.cssClass?.getD "" |>.splitOn " ").contains "bp-node-supporting" then
              base ++ #["fontsize=7", "width=0.3", "height=0.2", "margin=\"0.03,0.02\""]
            else base
          match node.ref?, refAttrs? with
          | some ref, some mkAttrs =>
            match mkAttrs ref with
            | some extra => (String.intercalate ", " base.toList) ++ ", " ++ extra
            | none => String.intercalate ", " base.toList
          | _, _ => String.intercalate ", " base.toList
        let nodeDefs := nodeDefs.insert node.label s!"\"{node.label}\" [{attrs}];"
        let groupMembers :=
          match node.parent? with
          | none => groupMembers
          | some parent =>
            let members := groupMembers.getD parent #[]
            groupMembers.insert parent (members.push node.label)
        let stmtDeps := eraseDups node.deps
        let proofDeps := eraseDups node.proofDeps
        let stmtDepSet : NameSet :=
          stmtDeps.foldl (init := ({} : NameSet)) fun acc dep => acc.insert dep
        let proofDepSet : NameSet :=
          proofDeps.foldl (init := ({} : NameSet)) fun acc dep => acc.insert dep
        -- Per-edge intent/origin from the dependent node's merged use-refs.
        let mergedUses : Array Data.UseRef :=
          Data.UseRef.mergeByLabel node.statementUses node.proofUses
        let intentOriginFor (dep : Name) : Data.UseOrigin × Data.UseIntent :=
          match mergedUses.find? (fun useRef => (useRef.label : Name) == dep) with
          | some useRef => (useRef.origin, useRef.intent)
          | none => (.manual, .regular)
        let edges := stmtDeps.foldl (init := edges) fun edges dep =>
          if known.contains dep then
            let mixed := proofDepSet.contains dep
            let baseAttrs : Array String :=
              if defLike.contains dep then
                -- STY-GRAPH-09 (#32c): give dashed statement-from-box edges a
                -- heavier stroke than the dotted proof-only edges below
                -- (1.0pt) so the two patterns are easier to tell apart.
                if mixed then #["style=dashed", "penwidth=1.7"]
                else #["style=dashed", "penwidth=1.4"]
              else if mixed then #["penwidth=1.7"]
              else #[]
            let (origin, intent) := intentOriginFor dep
            let touchesSupporting :=
              supportingSet.contains dep || supportingSet.contains node.label
            edges.push (edgeLineWithStyle dep node.label baseAttrs origin intent touchesSupporting)
          else
            edges
        let edges := proofDeps.foldl (init := edges) fun edges dep =>
          if known.contains dep && !stmtDepSet.contains dep then
            let (origin, intent) := intentOriginFor dep
            let touchesSupporting :=
              supportingSet.contains dep || supportingSet.contains node.label
            -- STY-GRAPH-09 (#32c): finer dotted stroke (proof-only) reads as
            -- clearly dotted versus the heavier dashed statement edges above.
            -- STY-GRAPH-14 (#32d): with hundreds of these in a dense fan-in the
            -- 1.0pt default-grey (#6b7280) dotted edges read as low-contrast
            -- noise at fit-zoom. Nudge to 1.2pt in a darker slate-grey so they
            -- stay legible while remaining lighter/finer than the dashed
            -- statement edges (1.4-1.7pt). Auxiliary/technical intents win their
            -- own hue via `edgeStyleAttrs`; the automatic supporting-mesh
            -- de-emphasis applies only when `touchesSupporting`, so authored
            -- blueprint↔blueprint proof edges keep this darker slate. `edgeLineWithStyle`
            -- dedups so each edge still emits exactly one color/penwidth.
            edges.push (edgeLineWithStyle dep node.label
              #["style=dotted", "penwidth=1.2", s!"color=\"{edgeProofOnlyColor}\""]
              origin intent touchesSupporting)
          else
            edges
        (nodeDefs, groupMembers, edges)
  let groupMembers :=
    groupMembers.foldl (init := ({} : NameMap (Array Name))) fun acc parent members =>
      if members.size > 1 then
        acc.insert parent members
      else
        acc
  let groupedLabels : NameSet :=
    groupMembers.foldl (init := ({} : NameSet)) fun acc _parent members =>
      members.foldl (init := acc) fun acc label => acc.insert label
  let groups : Array Name := groupMembers.toArray.map (·.1)
  let groupSet : NameSet := groups.foldl (init := ({} : NameSet)) fun acc group => acc.insert group
  let groupParent : NameMap Name :=
    groups.foldl (init := ({} : NameMap Name)) fun acc group =>
      match nodeByLabel.get? group with
      | some node =>
        match node.parent? with
        | some parent =>
          if groupSet.contains parent then
            acc.insert group parent
          else
            acc
        | none => acc
      | none => acc
  let groupChildren : NameMap (Array Name) :=
    groupParent.toArray.foldl (init := ({} : NameMap (Array Name))) fun acc (child, parent) =>
      let children := acc.getD parent #[]
      if children.contains child then
        acc
      else
        acc.insert parent (children.push child)
  let (groupIds, _nextId) :=
    groups.foldl (init := (({} : NameMap Nat), 0)) fun (acc, i) group =>
      (acc.insert group i, i + 1)
  let rootGroups :=
    let roots := groups.filter (fun group => !(groupParent.contains group))
    if roots.isEmpty then groups else roots
  let groupLabel? := groupLabel?.getD (fun _ => none)
  let groupTooltip? := groupTooltip?.getD (fun _ => none)
  let (clusterLines, visitedGroups) :=
    rootGroups.foldl (init := ((#[] : Array String), ({} : NameSet))) fun (acc, visited) group =>
      let (lines, visited) := emitGroupClusterLines nodeDefs groupMembers groupChildren groupIds groupLabel? groupTooltip? group 2 (groups.size + 1) visited
      (acc ++ lines, visited)
  let (clusterLines, _visitedGroups) :=
    groups.foldl (init := (clusterLines, visitedGroups)) fun (acc, visited) group =>
      if visited.contains group then
        (acc, visited)
      else
        let (lines, visited) := emitGroupClusterLines nodeDefs groupMembers groupChildren groupIds groupLabel? groupTooltip? group 2 (groups.size + 1) visited
        (acc ++ lines, visited)
  let ungroupedNodeLines :=
    g.foldl (init := (#[] : Array String)) fun acc node =>
      if groupedLabels.contains node.label then
        acc
      else
        match nodeDefs.get? node.label with
        | some line => acc.push s!"  {line}"
        | none => acc
  let lines := #[header] ++ ungroupedNodeLines ++ clusterLines ++ edges
  let lines := lines.push "}"
  lines.foldl (init := "") fun acc line =>
    if acc.isEmpty then line else acc ++ "\n" ++ line

/-- Cycle-guarded reachability closure over an adjacency map. -/
private partial def reachableClosure (adj : Lean.NameMap (Array Name)) :
    List Name → Lean.NameSet → Lean.NameSet
  | [], visited => visited
  | n :: rest, visited =>
    if visited.contains n then
      reachableClosure adj rest visited
    else
      let visited := visited.insert n
      reachableClosure adj ((adj.getD n #[]).toList ++ rest) visited

/-- Total drawn-edge count (statement + proof deps) of a graph. Used to tell whether
`transitiveReduce` actually removed any edges (it only ever removes). -/
private def graphEdgeCount (g : Graph Ref) : Nat :=
  g.foldl (init := 0) fun acc node => acc + node.deps.size + node.proofDeps.size

/--
Union-semantics transitive reduction of the *drawn* dependency edges.

Builds one union adjacency from `deps ∪ proofDeps` (source dependency → dependent),
restricted to known node labels and excluding self-deps, then drops edge `d → b`
whenever `b` is reachable from some *other* dependent `c` of `d` — i.e. there is a
path `d → c → … → b` of length ≥ 2 in the union graph. A redundant pair loses both
its statement and proof edge families together: `Graph.toDot` derives per-edge
intent/origin from the merged use-refs, so `deps`, `proofDeps`, `statementUses`, and
`proofUses` are filtered in sync. `Array.filter` preserves order, keeping the DOT
deterministic.

Redundancy is decided against the union graph exactly as passed in, so apply this
LAST — after any restriction/aggregation/intent-filtering — or a path through nodes
outside the current subgraph could delete an edge that is essential within it.

The reachability witness for `d → b` seeds the DFS visited-set with `d`, so the
witness path can never re-enter `d`. That both preserves the length-≥2 guarantee and
makes the search cycle-safe, so exotic dependency cycles terminate (they simply see
fewer edges dropped rather than producing a non-DAG). Cost is O(E·(V+E)); build-time
only, at ≤~200 nodes. -/
def transitiveReduce (graph : Graph Ref) : Graph Ref :=
  let known : Lean.NameSet := graph.foldl (init := {}) fun acc node => acc.insert node.label
  -- Union adjacency: dependency source → dependents.
  let adj : Lean.NameMap (Array Name) :=
    graph.foldl (init := ({} : Lean.NameMap (Array Name))) fun acc node =>
      (eraseDups (node.deps ++ node.proofDeps)).foldl (init := acc) fun acc dep =>
        if known.contains dep && dep != node.label then
          let cur := acc.getD dep #[]
          if cur.contains node.label then acc else acc.insert dep (cur.push node.label)
        else acc
  -- For each source `d`, the dependents made redundant by a length-≥2 path.
  let redundant : Lean.NameMap Lean.NameSet :=
    adj.foldl (init := ({} : Lean.NameMap Lean.NameSet)) fun acc d succs =>
      -- Memoize the reachable set from each successor (visited seeded with `d`).
      let closures : Lean.NameMap Lean.NameSet :=
        succs.foldl (init := ({} : Lean.NameMap Lean.NameSet)) fun cAcc c =>
          if cAcc.contains c then cAcc
          else cAcc.insert c (reachableClosure adj [c] (({} : Lean.NameSet).insert d))
      let redSet : Lean.NameSet :=
        succs.foldl (init := ({} : Lean.NameSet)) fun rAcc b =>
          if succs.any (fun c => c != b && (closures.getD c {}).contains b) then rAcc.insert b
          else rAcc
      acc.insert d redSet
  graph.map fun node =>
    let isRedundant (dep : Name) : Bool := (redundant.getD dep {}).contains node.label
    { node with
      deps := node.deps.filter (fun dep => !isRedundant dep)
      proofDeps := node.proofDeps.filter (fun dep => !isRedundant dep)
      statementUses := node.statementUses.filter (fun u => !isRedundant (u.label : Name))
      proofUses := node.proofUses.filter (fun u => !isRedundant (u.label : Name)) }

/-- Node count at or above which a graph is treated as "dense" and gets the
breathe-out spacing (tighter `nodesep`, looser `ranksep`; see `graphDotHeader`).
`newrank`/`concentrate` apply to every graph regardless. The all-declarations
Full/Essential graphs (~100+ nodes) cross this; per-node, group, and parent
sub-graphs stay well below it, so their spacing is unchanged. -/
def graphDenseNodeThreshold : Nat := 48

/-- Common DOT header for rendered Blueprint graphs.

`pack=true` keeps disconnected graph components compact before d3-graphviz fits
the SVG into the canvas.

`newrank=true` and `concentrate=true` are emitted unconditionally: `newrank` lets
Graphviz rank nodes across cluster boundaries (chapter clusters no longer distort
the global layering) and `concentrate` merges shared edge trunks into a single
segment. Paired with the transitive reduction of the drawn edges (`transitiveReduce`),
these turn the former hairball into a legible layered graph. Accepted trade-off:
`concentrate` can merge trunk segments of differently-styled edges.

When `dense := true` (large all-declarations graphs), the spacing is loosened to
fight the flat, very-wide fit-zoom band: horizontal `nodesep` is tightened and
`ranksep` is opened up for vertical breathing. Together with the shrunken supporting
nodes (`Graph.toDot`) and de-emphasized inferred edges this roughly halves the width
and the aspect ratio. Small graphs keep the original spacing byte-for-byte. -/
def graphDotHeader (options : GraphOptions := {}) (style : GraphDotStyle := {})
    (dense : Bool := false) : String :=
  let nodesep := if dense then "0.18" else "0.35"
  let ranksep := if dense then "0.8" else "0.45"
  "strict digraph \"\" {\n" ++
  s!"    rankdir={options.direction.rankdir};\n" ++
  -- STY-GRAPH-01 (#32a): emit a transparent SVG background so the canvas
  -- container's CSS "figure card" surface shows through instead of a baked-in
  -- white block. Node fills + edge strokes are baked light-tuned, so the card is
  -- a deliberate (theme-invariant) light surface; see `.bp_graph_canvas` in
  -- graph.css.
  "    bgcolor=\"transparent\";\n" ++
  (if style.includePack then s!"    pack={graphPackAttr options.pack};\n" else "") ++
  "    splines=true;\n" ++
  "    newrank=true;\n" ++
  "    concentrate=true;\n" ++
  s!"    nodesep={nodesep};\n" ++
  s!"    ranksep={ranksep};\n" ++
  s!"    node [shape=box, style=\"rounded,filled\", fontname=\"Helvetica\", fontsize={style.nodeFontSize}, margin=\"{style.nodeMargin}\", color=\"#6b7280\", penwidth={style.nodePenwidth}];\n" ++
  s!"    edge [color=\"#6b7280\", arrowhead=vee, arrowsize={style.edgeArrowsize}, penwidth={style.edgePenwidth}];\n" ++
  "    graph [fontname=\"Helvetica\"];\n" ++
  "  "

/--
Render a graph to DOT using the shared Blueprint graph header.

Use `graphToDot` for the usual page-graph case where refs are href strings.
`graphToDotWith` is for renderers such as widgets that need a different ref
type or compact DOT styling.
-/
def graphToDotWith (g : Graph Ref) (options : GraphOptions := {}) (style : GraphDotStyle := {})
    (resolveGroupTitle : Name → Option String := fun _ => none)
    (resolveGroupTooltip : Name → Option String := fun _ => none)
    (refAttrs? : Option (Ref → Option String) := none) : String :=
  Graph.toDot g (graphDotHeader options style (dense := g.size ≥ graphDenseNodeThreshold))
    (groupLabel? := some resolveGroupTitle)
    (groupTooltip? := some resolveGroupTooltip)
    (refAttrs? := refAttrs?)

/-- Render a page graph with string refs interpreted as same-page hrefs. -/
def graphToDot (g : Graph String) (options : GraphOptions := {})
    (resolveGroupTitle : Name → Option String := fun _ => none)
    (resolveGroupTooltip : Name → Option String := fun _ => none) : String :=
  graphToDotWith g options {} (resolveGroupTitle := resolveGroupTitle)
    (resolveGroupTooltip := resolveGroupTooltip)
    (refAttrs? := some fun href => some s!"URL=\"{href}\", target=\"_self\"")

/-- Render finalized graph data to DOT using its href and group-title fields.

Drops transitively-redundant edges by default (`allEdges := false`); pass
`allEdges := true` for the unreduced graph. This covers the static node/decl/widget
graphs and the `dot-source` fallback with no call-site changes — they render reduced
and carry no "show all edges" toggle. -/
def GraphData.toDotWith (data : GraphData) (options : GraphOptions := {})
    (style : GraphDotStyle := {}) (allEdges : Bool := false) : String :=
  let g := if allEdges then data.toGraph else transitiveReduce data.toGraph
  graphToDotWith g options style
    (resolveGroupTitle := fun group => data.groupDisplayTitleMap.get? group)
    (resolveGroupTooltip := fun group => data.groupClusterTooltipMap.get? group)
    (refAttrs? := some fun href => some s!"URL=\"{href}\", target=\"_self\"")

/-- Stable key for the synthetic group overview variant. -/
def groupVariantKey : String := "group"
/-- Stable key for the precomputed "essential dependencies" variant. -/
def essentialVariantKey : String := "essential"
private def parentVariantKey (parent : Name) : String := s!"parent:{parent}"

private partial def wrapGraphLabelWords (words : List String) (lineWidth maxLines : Nat)
    (current : String) (lines : Array String) : Array String :=
  match words with
  | [] =>
    if current.isEmpty then lines else lines.push current
  | word :: rest =>
    if lines.size + 1 == maxLines then
      let finalLine :=
        if current.isEmpty then
          String.intercalate " " (word :: rest)
        else
          String.intercalate " " (current :: word :: rest)
      lines.push finalLine
    else
      let candidate := if current.isEmpty then word else current ++ " " ++ word
      if !current.isEmpty && candidate.length > lineWidth then
        wrapGraphLabelWords words lineWidth maxLines "" (lines.push current)
      else
        wrapGraphLabelWords rest lineWidth maxLines candidate lines

private def wrapGraphLabel (title : String) (lineWidth : Nat := 26) (maxLines : Nat := 3) : String :=
  let words :=
    (title.splitOn " ").foldr (init := ([] : List String)) fun word acc =>
      let word := word.trimAscii.toString
      if word.isEmpty then acc else word :: acc
  match words with
  | [] => title.trimAscii.toString
  | _ =>
    let lines := wrapGraphLabelWords words lineWidth maxLines "" #[]
    String.intercalate "\n" lines.toList

private def hexNibble? (c : Char) : Option Nat :=
  match c with
  | '0' => some 0
  | '1' => some 1
  | '2' => some 2
  | '3' => some 3
  | '4' => some 4
  | '5' => some 5
  | '6' => some 6
  | '7' => some 7
  | '8' => some 8
  | '9' => some 9
  | 'a' | 'A' => some 10
  | 'b' | 'B' => some 11
  | 'c' | 'C' => some 12
  | 'd' | 'D' => some 13
  | 'e' | 'E' => some 14
  | 'f' | 'F' => some 15
  | _ => none

private def parseHexByte? (c1 c2 : Char) : Option Nat := do
  let hi ← hexNibble? c1
  let lo ← hexNibble? c2
  return hi * 16 + lo

private def parseHexColor? (s : String) : Option (Nat × Nat × Nat) := do
  let chars :=
    match s.trimAscii.toString.toList with
    | '#' :: rest => rest
    | xs => xs
  match chars with
  | r1 :: r2 :: g1 :: g2 :: b1 :: b2 :: [] =>
    return (← parseHexByte? r1 r2, ← parseHexByte? g1 g2, ← parseHexByte? b1 b2)
  | _ => none

private def hexChar (n : Nat) : Char :=
  if n < 10 then
    Char.ofNat ('0'.toNat + n)
  else
    Char.ofNat ('a'.toNat + (n - 10))

private def byteToHex (n : Nat) : String :=
  let n := n % 256
  let hi := n / 16
  let lo := n % 16
  String.ofList [hexChar hi, hexChar lo]

private def rgbToHex (r g b : Nat) : String :=
  "#" ++ byteToHex r ++ byteToHex g ++ byteToHex b

private def primaryColorToken (s : String) : String :=
  match s.splitOn ":" with
  | token :: _ => token.trimAscii.toString
  | [] => s.trimAscii.toString

private def averageHexColor (colors : Array (Nat × Nat × Nat)) (fallback : String) : String :=
  if colors.isEmpty then
    fallback
  else
    let (sumR, sumG, sumB) := colors.foldl (init := (0, 0, 0)) fun (r, g, b) (r', g', b') =>
      (r + r', g + g', b + b')
    let n := colors.size
    rgbToHex (sumR / n) (sumG / n) (sumB / n)

private def mixedNodeColor (nodes : Array (GraphNode String)) (colorOf : GraphNode String → String)
    (fallback : String) : String :=
  let colors := nodes.foldl (init := (#[] : Array (Nat × Nat × Nat))) fun acc node =>
    match parseHexColor? (primaryColorToken (colorOf node)) with
    | some rgb => acc.push rgb
    | none => acc
  averageHexColor colors fallback

private def fontColorForFill (fillColor : String) : String :=
  match parseHexColor? fillColor with
  | some (r, g, b) =>
    -- Relative luminance approximation, keeps labels readable on dark mixes.
    if (299 * r + 587 * g + 114 * b) < 140000 then "#f8fafc" else "#0f172a"
  | none => "#0f172a"

private def nodeHasAncestorParent (parentMap : Lean.NameMap Name) (label ancestor : Name) : Bool :=
  Id.run <| do
    let mut current := label
    let mut seen : Lean.NameSet := {}
    let mut fuel := parentMap.toArray.size + 1
    while fuel > 0 do
      fuel := fuel - 1
      match parentMap.get? current with
      | none => return false
      | some parent =>
        if parent == ancestor then
          return true
        if seen.contains parent then
          return false
        seen := seen.insert parent
        current := parent
    return false

private def subgraphForParent (graph : Graph Ref) (parent : Name) : Graph Ref :=
  let parentMap := graphNodeParents graph
  graph.filter fun node =>
    node.label == parent || nodeHasAncestorParent parentMap node.label parent

/--
Build the synthetic group overview graph used by graph view variants.

Each parent with multiple children becomes one aggregate node whose colors are
derived from its children and whose edges summarize cross-group dependencies.
-/
def mkParentOverviewGraph (graph : Graph String) (parents : Array Name)
    (groupTitles : Lean.NameMap String) (shortTitles : Lean.NameMap String := {}) : Graph String :=
  let parentChildren := graphParentChildren graph
  let nodeByLabel : Lean.NameMap (GraphNode String) :=
    graph.foldl (init := ({} : Lean.NameMap (GraphNode String))) fun acc node =>
      acc.insert node.label node
  let parentSet : Lean.NameSet :=
    parents.foldl (init := ({} : Lean.NameSet)) fun acc parent => acc.insert parent
  let parentMap := graphNodeParents graph
  let addParentDep (acc : Lean.NameMap (Array Name)) (target source : Name) : Lean.NameMap (Array Name) :=
    let deps := acc.getD target #[]
    if deps.contains source then
      acc
    else
      acc.insert target (deps.push source)
  let collectParentDeps (depsOf : GraphNode String → Array Name) :=
    graph.foldl (init := ({} : Lean.NameMap (Array Name))) fun acc node =>
      match node.parent? with
      | none => acc
      | some target =>
        if !parentSet.contains target then
          acc
        else
          (depsOf node).foldl (init := acc) fun acc dep =>
            match parentMap.get? dep with
            | some source =>
              if parentSet.contains source && source != target then
                addParentDep acc target source
              else
                acc
            | none => acc
  let parentStatementDeps := collectParentDeps (·.deps)
  let parentProofDeps := collectParentDeps (·.proofDeps)
  parents.map fun parent =>
    let childNodes :=
      (parentChildren.getD parent #[]).foldl (init := (#[] : Array (GraphNode String))) fun acc child =>
        match nodeByLabel.get? child with
        | some node => acc.push node
        | none => acc
    let mixedFillColor := mixedNodeColor childNodes (·.fillcolor) "#e2e8f0"
    let mixedBorderColor := mixedNodeColor childNodes (·.color) "#475569"
    let title := groupTitle groupTitles parent
    -- Aggregate node label = compact short title (wrapped); the long `title` stays
    -- on the tooltip below.
    let shortTitle :=
      match shortTitles.get? parent with
      | some s => let s := s.trimAscii.toString; if s.isEmpty then title else s
      | none => title
    {
      label := parent
      displayLabel? := some (wrapGraphLabel shortTitle)
      deps := parentStatementDeps.getD parent #[]
      proofDeps := parentProofDeps.getD parent #[]
      shape := "tab"
      style := "filled"
      fillcolor := mixedFillColor
      color := mixedBorderColor
      penwidth := "2.4"
      fontcolor := fontColorForFill mixedFillColor
      tooltip? := some s!"Group View: {title} ({childNodes.size} nodes)"
      ref? := none
    }

/--
Drop auxiliary and technical dependencies, keeping only `regular`-intent edges.

Each node's `deps`/`proofDeps` and `statementUses`/`proofUses` are filtered to the
regular use-refs, so the rendered DOT shows only the essential dependency spine.
-/
def essentialGraph (graph : Graph Ref) : Graph Ref :=
  graph.map fun node =>
    let keepRef (useRef : Data.UseRef) : Bool :=
      match useRef.intent with
      | .regular => true
      | _ => false
    let stmtRefs := node.statementUses.filter keepRef
    let proofRefs := node.proofUses.filter keepRef
    { node with
      deps := stmtRefs.map (fun useRef => (useRef.label : Name))
      proofDeps := proofRefs.map (fun useRef => (useRef.label : Name))
      statementUses := stmtRefs
      proofUses := proofRefs }

/--
Build the render variants for the bundled graph UI.

All graphs produce a full graph variant plus a precomputed "essential
dependencies" variant (auxiliary/technical edges dropped). Grouped graphs
additionally produce a synthetic group overview and one focused subgraph per
parent group.
-/
def mkGraphVariants (graph : Graph String) (options : GraphOptions)
    (groupTitles : Lean.NameMap String)
    (previewKeyForLabel : Name → String := PreviewCache.statementKey)
    (groupShortTitles : Lean.NameMap String := {})
    (groupTooltips : Lean.NameMap String := {}) :
    Array GraphRenderVariant :=
  let previewKeyByNodeId (graph : Graph String) : Array (String × String) :=
    graph.map fun node =>
      (graphNodeSvgId node.label, previewKeyForLabel node.label)
  -- Cluster label = compact display title (short where known, else long); the long
  -- title rides `resolveGroupTooltip` as a cluster hover, emitted only when it
  -- actually differs (see `groupClusterTooltipMap`).
  let resolveGroupDisplay : Name → Option String := fun group =>
    match groupShortTitles.get? group with
    | some t => some t
    | none => groupTitles.get? group
  let resolveGroupTooltip : Name → Option String := fun group => groupTooltips.get? group
  -- Each variant bakes the transitively-reduced DOT as `dot` and — only when
  -- reduction actually dropped edges — the unreduced DOT as `dotFull`, for the
  -- "Show all edges" toggle. Layout must be recomputed per variant (CSS hiding can't
  -- restore the removed edges), so both strings are full DOT sources.
  let dotPair (g : Graph String) (gt gtt : Name → Option String) : String × Option String :=
    let reduced := transitiveReduce g
    let reducedDot := graphToDot reduced options gt gtt
    if graphEdgeCount reduced < graphEdgeCount g then
      (reducedDot, some (graphToDot g options gt gtt))
    else
      (reducedDot, none)
  let essential := essentialGraph graph
  let (fullDot, fullDotFull?) := dotPair graph resolveGroupDisplay resolveGroupTooltip
  let fullVariant : GraphRenderVariant := {
    key := "full"
    label := "Full Graph"
    dot := fullDot
    dotFull := fullDotFull?
    options
    selectOnNodeId := #[]
    hoverOnNodeId := #[]
    previewKeyByNodeId := previewKeyByNodeId graph
  }
  let (essentialDot, essentialDotFull?) := dotPair essential resolveGroupDisplay resolveGroupTooltip
  let essentialVariant : GraphRenderVariant := {
    key := essentialVariantKey
    label := "Essential dependencies"
    dot := essentialDot
    dotFull := essentialDotFull?
    options
    selectOnNodeId := #[]
    hoverOnNodeId := #[]
    previewKeyByNodeId := previewKeyByNodeId essential
  }
  let parentChildren := graphParentChildren graph
  let parents :=
    parentChildren.toArray
      |>.filter (fun (_, children) => children.size > 1)
      |>.map (·.1)
      |>.qsort (fun a b => groupTitle groupTitles a < groupTitle groupTitles b)
  if parents.isEmpty then
    #[fullVariant, essentialVariant]
  else
    let parentVariantRefs := parents.map (fun parent => (graphNodeSvgId parent, parentVariantKey parent))
    let (groupDot, groupDotFull?) :=
      dotPair (mkParentOverviewGraph graph parents groupTitles groupShortTitles)
        (fun _ => none) (fun _ => none)
    let groupVariant : GraphRenderVariant := {
      key := groupVariantKey
      label := "Group View"
      dot := groupDot
      dotFull := groupDotFull?
      options
      selectOnNodeId := parentVariantRefs
      hoverOnNodeId := parentVariantRefs
      previewKeyByNodeId := #[]
    }
    let parentVariants := parents.map fun parent =>
      let parentSubgraph := subgraphForParent graph parent
      let title := groupTitle groupTitles parent
      let (parentDot, parentDotFull?) := dotPair parentSubgraph resolveGroupDisplay resolveGroupTooltip
      {
        key := parentVariantKey parent
        label := title
        dot := parentDot
        dotFull := parentDotFull?
        options
        selectOnNodeId := #[]
        hoverOnNodeId := #[]
        previewKeyByNodeId := previewKeyByNodeId parentSubgraph
      }
    #[fullVariant, essentialVariant, groupVariant] ++ parentVariants

/--
Forward adjacency (dependency → dependents) derived from `GraphData.edges`.

Edges point from a dependency source to the dependent target, so following the
forward map walks toward downstream descendants.
-/
def GraphData.forwardAdj (data : GraphData) : Lean.NameMap (Array Name) :=
  data.edges.foldl (init := ({} : Lean.NameMap (Array Name))) fun acc edge =>
    let cur := acc.getD edge.source #[]
    if cur.contains edge.target then acc
    else acc.insert edge.source (cur.push edge.target)

/--
Reverse adjacency (dependent → dependencies) derived from `GraphData.edges`.

Following the reverse map walks toward upstream ancestors.
-/
def GraphData.reverseAdj (data : GraphData) : Lean.NameMap (Array Name) :=
  data.edges.foldl (init := ({} : Lean.NameMap (Array Name))) fun acc edge =>
    let cur := acc.getD edge.target #[]
    if cur.contains edge.source then acc
    else acc.insert edge.target (cur.push edge.source)

/--
All ancestors (transitive dependencies) of `label` via the reverse adjacency.

The start node is not included unless it participates in a dependency cycle. The
traversal is cycle-guarded with a visited set.
-/
def GraphData.ancestors (data : GraphData) (label : Name) : Lean.NameSet :=
  reachableClosure data.reverseAdj (data.reverseAdj.getD label #[]).toList {}

/--
All descendants (transitive dependents) of `label` via the forward adjacency.

The start node is not included unless it participates in a dependency cycle. The
traversal is cycle-guarded with a visited set.
-/
def GraphData.descendants (data : GraphData) (label : Name) : Lean.NameSet :=
  reachableClosure data.forwardAdj (data.forwardAdj.getD label #[]).toList {}

/--
Restrict graph data to the given label set.

Mirrors `subgraphForParent`: nodes are filtered to the set, edges are kept only
when both endpoints are in the set, and each group's `children` are filtered to
the set.
-/
def GraphData.restrictTo (data : GraphData) (labels : Lean.NameSet) : GraphData :=
  { data with
    nodes := data.nodes.filter (fun node => labels.contains node.label)
    edges := data.edges.filter (fun edge => labels.contains edge.source && labels.contains edge.target)
    groups := data.groups.map (fun group =>
      { group with children := group.children.filter (fun child => labels.contains child) }) }

/-- Build the bundled renderer's DOT variants from finalized public graph data. -/
def GraphData.renderVariants (data : GraphData) (options : GraphOptions) : Array GraphRenderVariant :=
  let previewKeyForLabel label :=
    match data.nodes.find? (fun node => node.label == label) with
    | some node => node.previewKey
    | none => PreviewCache.statementKey label
  mkGraphVariants data.toGraph options data.groupTitleMap previewKeyForLabel
    (groupShortTitles := data.groupDisplayTitleMap)
    (groupTooltips := data.groupClusterTooltipMap)

end Informal.Graph
