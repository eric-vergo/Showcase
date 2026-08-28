/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint.Commands.Common
import VersoBlueprint.Lib.HtmlId
import VersoBlueprint.Milestones.Audit
import VersoBlueprint.NodeRoute

/-!
Rendering for the proof-overview surface: a small hand-laid SVG plus one card per
milestone.

Two deliberate choices.

**Not Graphviz.** The overview is a *narrative* diagram: rows are dependency
depth and the order within a row is the order the author wrote the milestones in.
Graphviz owns placement, would drag the lazily-loaded d3-graphviz WASM layout onto
a page that otherwise needs no JavaScript at all, and renders dark mode there by
inverting the whole canvas. A dozen boxes on a grid do not need any of that.

**No new asset files.** The stylesheet is a Lean string on the existing
`extraCss` channel and the surface ships zero JavaScript, so there is no
`include_str` staleness trap to fall into and nothing to vendor. Every colour is
an existing `--bp-*` token, which is what makes both colour schemes correct by
construction.
-/

namespace Informal.Milestones

open Lean
open Verso
open Verso.Genre Manual
open Verso.Output.Html
open Informal.Commands (BlueprintAssetBundle inlinePreviewAssetBundle)

/-! ### Layout constants -/

/-- Width of one milestone box in the overview SVG. -/
def nodeW : Nat := 196
/-- Height of one milestone box. -/
def nodeH : Nat := 62
/-- Horizontal gap between two boxes on the same row. -/
def colGap : Nat := 26
/-- Vertical gap between rows. -/
def rowGap : Nat := 78
/-- Padding around the whole diagram. -/
def diagramPad : Nat := 18

/-- Placed box for one milestone: the top-left corner of its rectangle. -/
structure Placement where
  label : Data.Label
  x : Nat
  y : Nat
deriving Inhabited, Repr

/-- Width of a row holding `k` boxes. -/
private def rowWidth (k : Nat) : Nat :=
  if k == 0 then 0 else k * nodeW + (k - 1) * colGap

/--
Place every milestone: row index gives `y`, position within the row gives `x`,
and each row is centred in the widest row.

Rows are compacted to their index in ascending order, so a row number nothing
occupies leaves no gap.
-/
def placements (d : OverviewData) : Array Placement × Nat × Nat := Id.run do
  let rowIdx := d.rowIndices
  let widths := rowIdx.map fun r => rowWidth (d.rowMembers r).size
  let maxWidth := widths.foldl Nat.max 0
  let mut out : Array Placement := #[]
  for i in [0 : rowIdx.size] do
    let r := rowIdx[i]!
    let members := d.rowMembers r
    let x0 := diagramPad + (maxWidth - rowWidth members.size) / 2
    let y := diagramPad + i * (nodeH + rowGap)
    for j in [0 : members.size] do
      out := out.push { label := members[j]!.label, x := x0 + j * (nodeW + colGap), y }
  let width := maxWidth + 2 * diagramPad
  let height :=
    if rowIdx.isEmpty then 0
    else 2 * diagramPad + rowIdx.size * nodeH + (rowIdx.size - 1) * rowGap
  return (out, width, height)

/-! ### Text helpers -/

/-- Greedy word wrap to at most `maxLines` lines of about `width` characters, with
an ellipsis on the last kept line when text was dropped. -/
def wrapText (s : String) (width : Nat) (maxLines : Nat) : Array String := Id.run do
  let words := (s.splitOn " ").filter (fun w => !w.isEmpty)
  let mut lines : Array String := #[]
  let mut cur : String := ""
  for w in words do
    if cur.isEmpty then
      cur := w
    else if cur.length + 1 + w.length ≤ width then
      cur := cur ++ " " ++ w
    else
      lines := lines.push cur
      cur := w
  if !cur.isEmpty then
    lines := lines.push cur
  if maxLines == 0 || lines.size ≤ maxLines then
    return lines
  let kept := lines.extract 0 maxLines
  return kept.set! (maxLines - 1) (kept[maxLines - 1]! ++ "…")

/-- Integer percentage of `part` in `total`, saturating at 100 and 0 for an empty
total. Used for the three meter segments, which are laid out in one flex row. -/
def pct (part total : Nat) : Nat :=
  if total == 0 then 0 else min 100 (part * 100 / total)

/-! ### Stylesheet -/

/--
The overview stylesheet.

A Lean string on the site-wide `extraCss` channel rather than a `.css` file:
nothing here is shared with another surface, and an embedded asset would have to
be re-`include_str`ed (and would fall into the stale-asset trap on every edit).
Colours are `--bp-*` tokens only, so light and dark are correct by construction
rather than by a second block that has to be kept in sync.
-/
def overviewCss : String := r##"
.bp_overview {
  display: flex;
  flex-direction: column;
  gap: var(--bp-space-5);
}

.bp_overview_graph {
  overflow-x: auto;
  padding-block: var(--bp-space-2);
}

.bp_overview_svg {
  display: block;
  margin-inline: auto;
  max-width: 100%;
  height: auto;
}

.bp_overview_node_box {
  fill: var(--bp-color-surface);
  stroke: var(--bp-color-border);
  stroke-width: 1;
  transition:
    fill var(--bp-duration-base) var(--bp-ease),
    stroke var(--bp-duration-base) var(--bp-ease);
}

.bp_overview_node:hover .bp_overview_node_box,
.bp_overview_node:focus-visible .bp_overview_node_box {
  fill: var(--bp-color-focus-surface);
  stroke: var(--bp-color-focus-border);
}

.bp_overview_node:focus-visible {
  outline: none;
}

.bp_overview_node_label {
  fill: var(--bp-color-text-strong);
  font-size: 0.8125rem;
  font-weight: 600;
}

.bp_overview_node_order,
.bp_overview_node_paper {
  fill: var(--bp-color-text-faint);
  font-size: var(--bp-fs-badge);
  font-weight: 600;
}

.bp_overview_edge {
  fill: none;
  stroke: var(--bp-color-border-strong);
  stroke-width: 1.4;
}

.bp_overview_edge_asserted {
  stroke: var(--bp-color-accent-warning);
  stroke-dasharray: 5 4;
}

.bp_overview_arrow_head {
  fill: var(--bp-color-border-strong);
}

.bp_overview_arrow_head_asserted {
  fill: var(--bp-color-accent-warning);
}

.bp_overview_note {
  margin: 0;
  font-size: var(--bp-fs-caption);
  line-height: 1.55;
  color: var(--bp-color-text-muted);
}

.bp_overview_cards {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(22rem, 1fr));
  gap: var(--bp-space-4);
}

.bp_overview_card {
  display: flex;
  flex-direction: column;
  gap: var(--bp-space-3);
  padding: var(--bp-space-4);
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-lg);
  background: var(--bp-color-surface);
  scroll-margin-top: 5rem;
}

.bp_overview_card:target {
  border-color: var(--bp-color-focus-border);
  box-shadow: 0 0 0 3px var(--bp-color-target-ring);
}

.bp_overview_card_head {
  display: flex;
  align-items: baseline;
  gap: var(--bp-space-2);
  flex-wrap: wrap;
}

.bp_overview_card_order {
  font-size: var(--bp-fs-badge);
  font-weight: 700;
  color: var(--bp-color-text-faint);
  font-variant-numeric: tabular-nums;
}

.bp_overview_card_title {
  margin: 0;
  font-size: 1rem;
  font-weight: 650;
  color: var(--bp-color-text-strong);
}

.bp_overview_card_paper {
  margin-inline-start: auto;
  font-size: var(--bp-fs-badge);
  color: var(--bp-color-text-muted);
}

.bp_overview_meter {
  display: flex;
  height: 6px;
  border-radius: var(--bp-radius-pill);
  overflow: hidden;
  background: var(--bp-color-surface-muted);
}

.bp_overview_meter_seg {
  display: block;
  height: 100%;
}

.bp_overview_meter_closed {
  background: var(--bp-color-accent-success);
}

.bp_overview_meter_ready {
  background: var(--bp-color-status-ready);
}

.bp_overview_meter_open {
  background: var(--bp-color-border-strong);
}

.bp_overview_meter_label {
  margin: 0;
  font-size: var(--bp-fs-caption);
  color: var(--bp-color-text-muted);
}

.bp_overview_sketch > :first-child {
  margin-block-start: 0;
}

.bp_overview_sketch > :last-child {
  margin-block-end: 0;
}

.bp_overview_section_label {
  display: block;
  font-size: var(--bp-fs-badge);
  font-weight: 600;
  color: var(--bp-color-text-faint);
  margin-block-end: var(--bp-space-1);
}

.bp_overview_deps_list {
  display: flex;
  flex-wrap: wrap;
  gap: var(--bp-space-1);
  margin: 0;
  padding: 0;
  list-style: none;
}

.bp_overview_dep {
  display: inline-flex;
  align-items: center;
  gap: var(--bp-space-1);
  padding: 0.1rem var(--bp-space-2);
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-pill);
  font-size: var(--bp-fs-badge);
  color: var(--bp-color-link);
  text-decoration: none;
}

.bp_overview_dep:hover {
  border-color: var(--bp-color-border-strong);
}

.bp_overview_badge {
  display: inline-flex;
  align-items: center;
  padding: 0 var(--bp-space-1);
  border: 1px solid var(--bp-color-status-warning-border);
  border-radius: var(--bp-radius-pill);
  background: var(--bp-color-surface-warn);
  color: var(--bp-color-status-warning-text);
  font-size: var(--bp-fs-badge);
  font-weight: 600;
}

.bp_overview_members_list {
  display: flex;
  flex-wrap: wrap;
  gap: var(--bp-space-1) var(--bp-space-3);
  margin: 0;
  padding: 0;
  list-style: none;
  font-size: var(--bp-fs-caption);
}

.bp_overview_member_missing {
  color: var(--bp-color-status-error-text);
}

.bp_overview_members_more > summary {
  cursor: pointer;
  font-size: var(--bp-fs-caption);
  color: var(--bp-color-text-muted);
}

@media (prefers-reduced-motion: reduce) {
  .bp_overview_node_box {
    transition: none;
  }
}
"##

/-- Site-wide asset bundle for the overview surface: the design tokens, the inline
preview styles the sketch prose may use, and this module's stylesheet. No
JavaScript — the surface is entirely server-rendered. -/
def overviewAssetBundle : BlueprintAssetBundle :=
  inlinePreviewAssetBundle (cssExtras := [overviewCss])

/-! ### SVG -/

private def svgTag (name : String) (attrs : Array (String × String))
    (body : Output.Html := .seq #[]) : Output.Html :=
  .tag name attrs body

/-- Arrow-head marker definitions. Ids are prefixed with the block's own id so two
overview blocks on one page cannot collide. -/
private def arrowDefs (idBase : String) : Output.Html :=
  let marker (id cls : String) : Output.Html :=
    svgTag "marker"
      #[("id", id), ("viewBox", "0 0 10 10"), ("refX", "9"), ("refY", "5"),
        ("markerWidth", "6"), ("markerHeight", "6"), ("orient", "auto-start-reverse")]
      (svgTag "path" #[("class", cls), ("d", "M 0 0 L 10 5 L 0 10 z")])
  svgTag "defs" #[] (.seq #[
    marker s!"{idBase}-arrow" "bp_overview_arrow_head",
    marker s!"{idBase}-arrow-asserted" "bp_overview_arrow_head_asserted"])

/-- One milestone box: a link to the card below, its order chip, its wrapped title,
and the paper reference when the author gave one. -/
private def nodeSvg (m : OverviewMilestone) (p : Placement) : Output.Html :=
  let titleLines := wrapText m.title 26 2
  let lineTags := titleLines.mapIdx fun i line =>
    svgTag "text"
      #[("class", "bp_overview_node_label"),
        ("x", toString (p.x + 12)), ("y", toString (p.y + 34 + i * 16))]
      (.text true line)
  let paperTag : Output.Html :=
    if m.paper.isEmpty then .empty
    else
      svgTag "text"
        #[("class", "bp_overview_node_paper"), ("text-anchor", "end"),
          ("x", toString (p.x + nodeW - 12)), ("y", toString (p.y + 18))]
        (.text true m.paper)
  let tooltip :=
    let scope := s!"{m.memberClosed} of {m.memberTotal} member nodes formalized"
    if m.paper.isEmpty then s!"{m.title} — {scope}" else s!"{m.title} ({m.paper}) — {scope}"
  svgTag "a"
    #[("class", "bp_overview_node"), ("href", "#" ++ m.anchor),
      ("data-bp-milestone", displayLabel m.label)]
    (.seq (#[
      svgTag "title" #[] (.text true tooltip),
      svgTag "rect"
        #[("class", "bp_overview_node_box"),
          ("x", toString p.x), ("y", toString p.y),
          ("width", toString nodeW), ("height", toString nodeH),
          ("rx", "8"), ("ry", "8")],
      svgTag "text"
        #[("class", "bp_overview_node_order"),
          ("x", toString (p.x + 12)), ("y", toString (p.y + 18))]
        (.text true (toString m.order)),
      paperTag] ++ lineTags))

/-- One dependency edge, drawn top-to-bottom as a cubic curve. An edge no graph
witnessed is dashed and says so in its tooltip. -/
private def edgeSvg (idBase : String) (byLabel : Lean.NameMap Placement)
    (titleOf : Name → String) (e : EdgeVerdict) : Output.Html :=
  match byLabel.get? e.source, byLabel.get? e.target with
  | some sp, some tp =>
    let x1 := sp.x + nodeW / 2
    let y1 := sp.y + nodeH
    let x2 := tp.x + nodeW / 2
    let y2 := tp.y
    let dy := rowGap / 2
    let d := s!"M {x1} {y1} C {x1} {y1 + dy} {x2} {y2 - dy} {x2} {y2}"
    let asserted := e.isAsserted
    let cls :=
      if asserted then "bp_overview_edge bp_overview_edge_asserted" else "bp_overview_edge"
    let marker :=
      if asserted then s!"url(#{idBase}-arrow-asserted)" else s!"url(#{idBase}-arrow)"
    let tip :=
      s!"{titleOf e.target} depends on {titleOf e.source} — {e.tier.label}"
    svgTag "g" #[] (.seq #[
      svgTag "path" #[("class", cls), ("d", d), ("marker-end", marker)],
      svgTag "title" #[] (.text true tip)])
  | _, _ => .empty

/-- The overview diagram. Empty when there is nothing to draw. -/
def overviewSvg (d : OverviewData) (idBase : String) : Output.Html :=
  let (places, width, height) := placements d
  if places.isEmpty then .empty
  else
    let byLabel : Lean.NameMap Placement :=
      places.foldl (init := ({} : Lean.NameMap Placement)) fun acc p => acc.insert p.label p
    let titles : Lean.NameMap String :=
      d.milestones.foldl (init := ({} : Lean.NameMap String)) fun acc m =>
        acc.insert m.label m.title
    let titleOf := fun (n : Name) => (titles.get? n).getD (displayLabel n)
    let nodes := d.milestones.map fun m =>
      match byLabel.get? m.label with
      | some p => nodeSvg m p
      | none => .empty
    let edges := d.edges.map (edgeSvg idBase byLabel titleOf)
    {{
      <div class="bp_overview_graph">
        {{svgTag "svg"
            #[("class", "bp_overview_svg"),
              ("xmlns", "http://www.w3.org/2000/svg"),
              ("viewBox", s!"0 0 {width} {height}"),
              ("width", toString width), ("height", toString height),
              ("role", "img"),
              ("aria-label", s!"Milestone overview: {d.milestones.size} milestones, {d.edges.size} dependencies")]
            (.seq (#[arrowDefs idBase] ++ edges ++ nodes))}}
      </div>
    }}

/-! ### Cards -/

/-- Display title of a member node, resolved from the traversal node index; the
authored label when the document presents no such node. -/
private def memberTitle (st : TraverseState) (label : Name) : String :=
  match Informal.TraversalIndex.Nodes.data? st label with
  | some data =>
    let t := data.displayTitle st
    if t.isEmpty then displayLabel label else t
  | none => displayLabel label

/-- Link to a member node's canonical page, or `none` when the document presents
no such node (a case the build already reported as an error). -/
private def memberHref? (st : TraverseState) (label : Name) : Option String :=
  if Informal.NodeRoute.hasNodePage st label then
    some (Informal.NodeRoute.nodePageHref label)
  else
    Informal.TraversalIndex.Nodes.href? st label

private def memberItem (st : TraverseState) (ms : MemberStatus) : Output.Html :=
  let title := memberTitle st ms.label
  let body : Output.Html :=
    match memberHref? st ms.label with
    | some href => {{ <a href={{href}} title={{displayLabel ms.label}}>{{.text true title}}</a> }}
    | none =>
      {{ <span class="bp_overview_member_missing" title={{displayLabel ms.label}}>
           {{.text true title}}
         </span> }}
  {{ <li class="bp_overview_member">{{body}}</li> }}

/-- Members of one milestone: the first `maxMembersShown` inline, the rest behind a
fold. -/
private def membersHtml (st : TraverseState) (d : OverviewData) (m : OverviewMilestone) :
    Output.Html :=
  if m.members.isEmpty then .empty
  else
    let cap := if d.maxMembersShown == 0 then m.members.size else d.maxMembersShown
    let shown := m.members.extract 0 (min cap m.members.size)
    let rest := m.members.extract (min cap m.members.size) m.members.size
    let more : Output.Html :=
      if rest.isEmpty then .empty
      else {{
        <details class="bp_overview_members_more">
          <summary>{{.text true s!"{rest.size} more"}}</summary>
          <ul class="bp_overview_members_list">{{rest.map (memberItem st)}}</ul>
        </details> }}
    {{
      <div class="bp_overview_members">
        <span class="bp_overview_section_label">"Nodes"</span>
        <ul class="bp_overview_members_list">{{shown.map (memberItem st)}}</ul>
        {{more}}
      </div>
    }}

/-- The milestones this one is built on, as chips. An author-asserted edge carries a
badge saying so, right where the claim is made. -/
private def depsHtml (d : OverviewData) (m : OverviewMilestone) : Output.Html :=
  if m.uses.isEmpty then .empty
  else
    let anchors : Lean.NameMap String :=
      d.milestones.foldl (init := ({} : Lean.NameMap String)) fun acc x =>
        acc.insert x.label x.anchor
    let titles : Lean.NameMap String :=
      d.milestones.foldl (init := ({} : Lean.NameMap String)) fun acc x =>
        acc.insert x.label x.title
    let chip := fun (e : EdgeVerdict) =>
      let title := (titles.get? e.source).getD (displayLabel e.source)
      let assertedTip :=
        "No dependency path between these milestones' nodes was found in the declaration \
         graph; the edge rests on the author's reading of the proof."
      let badge : Output.Html :=
        if e.isAsserted then
          {{ <span class="bp_overview_badge" title={{assertedTip}}>"author-asserted"</span> }}
        else .empty
      let inner := {{ <span>{{.text true title}}</span>{{badge}} }}
      match anchors.get? e.source with
      | some a => {{ <li><a class="bp_overview_dep" href={{"#" ++ a}}>{{inner}}</a></li> }}
      | none => {{ <li><span class="bp_overview_dep">{{inner}}</span></li> }}
    {{
      <div class="bp_overview_deps">
        <span class="bp_overview_section_label">"Depends on"</span>
        <ul class="bp_overview_deps_list">{{m.uses.map chip}}</ul>
      </div>
    }}

/-- Three-segment progress meter over a milestone's member nodes. -/
private def meterHtml (m : OverviewMilestone) : Output.Html :=
  if m.memberTotal == 0 then .empty
  else
    let closedPct := pct m.memberClosed m.memberTotal
    let readyPct := pct m.memberReady m.memberTotal
    let openPct := 100 - min 100 (closedPct + readyPct)
    let seg : String → Nat → Output.Html := fun cls p =>
      if p == 0 then .empty
      else {{ <span class={{s!"bp_overview_meter_seg {cls}"}} "style"={{s!"width:{p}%"}}></span> }}
    {{
      <div class="bp_overview_progress">
        <div class="bp_overview_meter" role="presentation">
          {{seg "bp_overview_meter_closed" closedPct}}
          {{seg "bp_overview_meter_ready" readyPct}}
          {{seg "bp_overview_meter_open" openPct}}
        </div>
        <p class="bp_overview_meter_label">
          {{.text true s!"{m.memberClosed} / {m.memberTotal} formalized"}}
        </p>
      </div>
    }}

/-- One milestone card. `sketch` supplies the already-rendered sketch prose, which
the caller renders through the genre's own block renderer. -/
private def cardHtml (st : TraverseState) (d : OverviewData)
    (sketch : Data.Label → Output.Html) (m : OverviewMilestone) : Output.Html :=
  let paper : Output.Html :=
    if m.paper.isEmpty then .empty
    else if m.paperUrl.isEmpty then
      {{ <span class="bp_overview_card_paper">{{.text true m.paper}}</span> }}
    else
      {{ <a class="bp_overview_card_paper" href={{m.paperUrl}} target="_blank" rel="noopener">
           {{.text true m.paper}}
         </a> }}
  {{
    <section class="bp_overview_card" id={{m.anchor}}>
      <div class="bp_overview_card_head">
        <span class="bp_overview_card_order">{{.text true (toString m.order)}}</span>
        <h3 class="bp_overview_card_title">{{.text true m.title}}</h3>
        {{paper}}
      </div>
      {{meterHtml m}}
      <div class="bp_overview_sketch">{{sketch m.label}}</div>
      {{depsHtml d m}}
      {{membersHtml st d m}}
    </section>
  }}

/-! ### The audit sentence -/

/--
What the build established about this overview, in the overview's own words.

Deliberately a count of what happened rather than a verdict: an author-asserted
edge is a normal thing for a proof sketch to contain, and the sentence says what
it is instead of grading it.
-/
def auditNote (a : Audit) : String :=
  let edgeNoun := if a.edges == 1 then "edge" else "edges"
  let head :=
    s!"{a.milestones} milestones cover {a.coveredNodes} of this blueprint's {a.graphNodes} \
       nodes, with {a.edges} milestone {edgeNoun} between them: {a.witnessedPresented} \
       witnessed by a dependency path in the presented graph"
  let mid :=
    if a.projectDeclsConsulted then
      s!", {a.witnessedProjectDecls} witnessed only through project declarations this \
         blueprint does not present"
    else ""
  let tail := s!", {a.asserted} author-asserted."
  let caveat :=
    if a.asserted == 0 then ""
    else
      " An author-asserted edge is drawn dashed: no dependency path was found between the \
       two milestones' nodes, so the edge records the author's reading of the proof and \
       nothing checked it."
  head ++ mid ++ tail ++ caveat

/-! ### The whole surface -/

/-- The overview: diagram, the audit sentence, then one card per milestone. -/
def renderOverview (st : TraverseState) (d : OverviewData) (idBase : String)
    (sketch : Data.Label → Output.Html) : Output.Html :=
  if d.isEmpty then .empty
  else {{
    <div class="bp_overview">
      {{overviewSvg d idBase}}
      <p class="bp_overview_note">{{.text true (auditNote d.audit)}}</p>
      <div class="bp_overview_cards">
        {{d.milestones.map (cardHtml st d sketch)}}
      </div>
    </div>
  }}

end Informal.Milestones
