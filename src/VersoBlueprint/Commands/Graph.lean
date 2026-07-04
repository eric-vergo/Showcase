/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Environment
import VersoBlueprint.Graph
import VersoBlueprint.GraphApi
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.Lib.HtmlId
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.PreviewCache
import VersoBlueprint.PreviewManifest
import VersoBlueprint.PreviewManifest.BlockRender
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.Informal.ExternalCode
import VersoBlueprint.Lib.PreviewSource
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex
import VersoBlueprint.DeclRegistry

namespace Informal.Commands

open Lean Elab Command
open Informal Data Environment
open Informal.Graph

register_option verso.blueprint.graph.includeAllDecls : Bool := {
  defValue := false
  descr := "Feature the whole project declaration graph: include every in-workspace declaration in the project's namespace(s) as subordinate \"supporting\" nodes, with edges from the real Lean const-level dependencies. Off by default (blueprint-annotated nodes only)."
}

register_option verso.blueprint.graph.defaultDirection : String := {
  defValue := "TB"
  descr := "Default direction for `blueprint_graph` when `(direction := ...)` is omitted (LR, RL, TB, BT)"
}

register_option verso.blueprint.graph.defaultPack : Bool := {
  defValue := false
  descr := "Default Graphviz component packing for `blueprint_graph` when `(pack := ...)` is omitted"
}

register_option verso.blueprint.graph.defaultPreviewMode : String := {
  defValue := "pinned"
  descr := "Default preview behavior for `blueprint_graph` when `(preview := ...)` is omitted (`pinned` or `hover`)"
}

register_option verso.blueprint.graph.defaultPreviewPlacement : String := {
  defValue := "docked"
  descr := "Default preview panel placement for `blueprint_graph` when `(previewPlacement := ...)` is omitted (`docked` or `anchored`)"
}

structure GraphBlockData where
  semanticGraphData : Informal.Graph.GraphData := {}
  /-- Render-only graph data for this block: the full project-declaration graph
  (blueprint nodes + supporting nodes + const-level edges). Used for the rendered
  Dependency-Graph SVG/JSON only; `none` falls back to `semanticGraphData`. Kept
  out of the traversal cache so the master graph / metrics / node pages see only
  the authored blueprint nodes. -/
  renderGraphData? : Option Informal.Graph.GraphData := none
  /-- Compressed all-declarations registry JSON, built at elaboration time when
  `verso.blueprint.graph.includeAllDecls` is on. Carried through block data so the
  `Block.graph.traverse` hook can stash it in the traversal state, from where
  `PreviewManifest.emitBlueprintPreviewData` writes `-verso-data/decl-registry.json`.
  `none` on consumers without the flag (no registry emitted). -/
  declRegistryJson? : Option String := none
  /-- Compressed **internal** proof/value-bodies JSON (`DeclRegistry.Bodies`),
  built alongside the registry. Stashed in the traversal state for the decl-page
  emitter (`DeclPage`) only — it is never written into the public data dir, so
  the heavy bodies can't balloon `decl-registry.json`. -/
  declBodiesJson? : Option String := none
  /-- The configured `verso.blueprint.declNamePrefix`, captured at elaboration
  time (where `Lean.Options` exist) and stashed in the traversal state so the
  render-time card paths and generation-time page emitters can shorten display
  names. `none` when unset (no shortening anywhere). -/
  declNamePrefix? : Option String := none
  options : GraphOptions := {}
  previewMode : Informal.HoverRender.PreviewMode := .pinned
  previewPlacement : Informal.HoverRender.PreviewPlacement := .docked
deriving Inhabited, FromJson, ToJson, Quote

def parseGraphPreviewMode? (s : String) : Option Informal.HoverRender.PreviewMode :=
  match s.trimAscii.toString.toLower with
  | "hover" => some .hover
  | "pinned" => some .pinned
  | _ => none

def parseGraphPreviewPlacement? (s : String) : Option Informal.HoverRender.PreviewPlacement :=
  match s.trimAscii.toString.toLower with
  | "docked" => some .docked
  | "anchored" => some .anchored
  | _ => none

-- Keep this module rebuilt when the embedded graph assets change.
-- This module owns the embedded graph CSS/JS boundary, so adjacent edits here
-- should land whenever graph runtime assets are intentionally refreshed.
def graphCss := include_str "graph.css"

def fallbackGraphControlId (id : Verso.Multi.InternalId) (suffix : String) : String :=
  s!"{Informal.HtmlId.prefixed "bp-graph" (toString id)}{suffix}"

/--
STY-GRAPH-11: condense a per-subgraph variant label (often a full descriptive
sentence) into a scannable fragment for the grouped View `<optgroup>`.

Keeps the first clause (cut at the first sentence/clause boundary), strips a
trailing period, and word-truncates anything still longer than `maxLen` with an
ellipsis. Purely cosmetic — the underlying `<option value>` (the variant key) is
unchanged, so selection behavior is identical.
-/
def shortenVariantLabel (label : String) (maxLen : Nat := 42) : String :=
  -- Cut at the first clause boundary so a leading sentence becomes the label.
  -- `splitOn` returns the whole string as the sole element when the separator is
  -- absent, so the `head` is always safe.
  let firstSeg (sep : String) (s : String) : String :=
    (s.splitOn sep).headD s |>.trimAscii.toString
  let label := label.trimAscii.toString
  let firstClause := firstSeg "." label
  let firstClause := firstSeg ";" firstClause
  let firstClause := firstSeg ":" firstClause
  let firstClause := firstSeg " — " firstClause
  let firstClause := if firstClause.isEmpty then label else firstClause
  if firstClause.length <= maxLen then
    firstClause
  else
    -- Word-truncate at the last whole word inside `maxLen`, then add an ellipsis.
    let truncated := (firstClause.take maxLen).toString
    let words := truncated.splitOn " "
    let kept :=
      match words.reverse with
      | _last :: rest@(_ :: _) => " ".intercalate rest.reverse
      | _ => truncated
    kept.trimAscii.toString ++ "…"

def graphAssetBundle : BlueprintAssetBundle :=
  previewPanelAssetBundle (cssExtras := [graphCss])

section GraphCardTemplates
open Verso Doc Genre Manual
open Verso.Output.Html

/-- Render stored Manual blocks (a cached preview's `.blocks`) to HTML via `goB`. -/
private def renderGraphCardBlocks {m} [Monad m]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Verso.Output.Html)
    (blocks : Array (Doc.Block Verso.Genre.Manual)) :
    Doc.Html.HtmlT Verso.Genre.Manual m Verso.Output.Html := do
  Verso.Output.Html.seq <$> blocks.mapM goB

/-- Render one Lean-code preview body for a card cell, or `none` when the preview
key is missing/malformed. Skipped silently: the graph modal is a secondary
surface and the same previews are already reported on their primary pages. -/
private def renderGraphCardLeanCodeBody? {m} [Monad m]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Verso.Output.Html)
    (state : TraverseState) (key : String) :
    Doc.Html.HtmlT Verso.Genre.Manual m (Option Verso.Output.Html) := do
  match Informal.TraversalIndex.LeanCodePreviews.decodedEntry? state key with
  | some (.ok stored) =>
    match stored.data.source with
    | .inlineBlocks blocks => some <$> renderGraphCardBlocks goB blocks
    | .externalDecl decl => pure <| some <| Informal.ExternalCode.renderPreviewHtml #[decl]
  | _ => pure none

/-- Collect the deduplicated Lean-code panel bodies for a manifest entry (mirrors
the graft / node-page code-panel assembly). -/
private def renderGraphCardLeanCodeBodies {m} [Monad m]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Verso.Output.Html)
    (state : TraverseState) (entry : Informal.PreviewManifest.Entry) :
    Doc.Html.HtmlT Verso.Genre.Manual m (Array Verso.Output.Html) := do
  let mut bodies : Array Verso.Output.Html := #[]
  for key in entry.leanCodePreviewKeys do
    match ← renderGraphCardLeanCodeBody? goB state key with
    | some body =>
      let html := body.asString
      if !html.trimAscii.isEmpty && !bodies.any (fun existing => existing.asString == html) then
        bodies := bodies.push body
    | Option.none => pure ()
  pure bodies

/-- Look up a statement/proof facet by cache key and render its `(entry, content)`
for the two-column card, or `none` when absent / empty. -/
private def renderGraphCardFacet? {m} [Monad m]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Verso.Output.Html)
    (state : TraverseState) (key : String) :
    Doc.Html.HtmlT Verso.Genre.Manual m
      (Option (Informal.PreviewManifest.Entry ×
        Informal.PreviewManifest.BlockRender.RenderedContent)) := do
  match Informal.PreviewManifest.findTraversalBlockEntry? state key with
  | some (preview, entry) =>
    if preview.blocks.isEmpty then
      pure none
    else
      let body ← renderGraphCardBlocks goB preview.blocks
      let codeBodies ← renderGraphCardLeanCodeBodies goB state entry
      pure <| some (entry, { body, codeBodies })
  | Option.none => pure none

/-- Build the inline `<template>` carrying one graph node's full two-column card
(statement facet + folded proof facet), keyed by the node's label so the runtime
resolves it from a clicked SVG node. `none` for supporting nodes and nodes
without a cached statement facet. Uses the default `RenderConfig`, matching the
node-page card (`NodePage.renderNodePageBody`). -/
private def renderGraphNodeCardTemplate? {m} [Monad m]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Verso.Output.Html)
    (state : TraverseState) (node : Informal.Graph.NodeData) :
    Doc.Html.HtmlT Verso.Genre.Manual m (Option Verso.Output.Html) := do
  if node.supporting then
    return none
  match ← renderGraphCardFacet? goB state (Informal.PreviewCache.statementKey node.label) with
  | Option.none => return none
  | some (entry, content) =>
    let proof? ← renderGraphCardFacet? goB state (Informal.PreviewCache.proofKey node.label)
    -- Same short-name prefix as the node-page cards, so the modal card's slim
    -- meta payload matches (see `RenderOptions.declNamePrefix`).
    let namePrefix := (Informal.TraversalIndex.DeclRegistry.namePrefix? state).getD ""
    let card := Informal.PreviewManifest.BlockRender.renderTwoColumnCard {} entry content proof?
      { declNamePrefix := namePrefix }
    let attrs : Array (String × String) := Id.run do
      let mut a := #[
        ("class", "bp_graph_preview_tpl"),
        ("data-bp-preview-label", toString node.label),
        ("data-bp-node-title", if node.title.isEmpty then node.displayLabel else node.title)
      ]
      if let some href := node.href then
        a := a.push ("data-bp-node-href", href)
      pure a
    return some (Verso.Output.Html.tag "template" attrs card)

/-- Render every graph node's inline card template for embedding on the graph
page (empty for nodes without a card, e.g. supporting nodes). -/
private def renderGraphNodeCardTemplates {m} [Monad m]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Verso.Output.Html)
    (state : TraverseState) (nodes : Array Informal.Graph.NodeData) :
    Doc.Html.HtmlT Verso.Genre.Manual m Verso.Output.Html := do
  let templates ← nodes.mapM (renderGraphNodeCardTemplate? goB state)
  pure <| Verso.Output.Html.seq (templates.filterMap id)

end GraphCardTemplates

open Verso Verso.Output.Html in
/--
Render the fullwidth graph surface (canvas markup plus the three embedded
`<script>` payloads).

When `static` is `false` (the interactive default used by `Block.graph`) the
legend, controls, options popover, and preview panels are included and the output
is byte-identical to the historical inline markup. When `static` is `true` only
the canvas (carrying `data-bp-graph-static="true"`) and its payloads are emitted;
`graph.mjs` reads that attribute to skip zoom/variant interactivity.

`idBase` is the resolved HTML id base for the block; control element ids are
`idBase ++ "--<suffix>"`.
-/
def renderGraphFullwidth
    (publicGraphData : Informal.Graph.GraphData)
    (variants : Array Informal.Graph.GraphRenderVariant)
    (options : Informal.Graph.GraphOptions)
    (idBase : String)
    (static : Bool := false)
    (previewMode : Informal.HoverRender.PreviewMode := .pinned)
    (previewPlacement : Informal.HoverRender.PreviewPlacement := .docked)
    (previewTemplates : Verso.Output.Html := .empty) :
    Verso.Output.Html :=
  -- Escape `</script>`-style breakouts in author-supplied strings (owner/tag/
  -- chapter/titles) before embedding the JSON verbatim in `<script>` payloads.
  let publicGraphDataJson : String :=
    escapeJsonForScriptEmbed (Lean.Json.compress (toJson publicGraphData))
  let hasGroupVariant := variants.any (fun variant => variant.key == groupVariantKey)
  let graphVariantJson : String :=
    escapeJsonForScriptEmbed (Lean.Json.compress (toJson variants))
  -- STY-GRAPH-11: surface the three primary views (Full / Essential / Group) as
  -- top-level options and tuck the per-subgraph `parent:*` variants into a
  -- labelled <optgroup> with condensed labels so the dropdown stays scannable.
  let isParentVariant := fun (variant : Informal.Graph.GraphRenderVariant) =>
    variant.key.startsWith "parent:"
  let primaryOptions : Array Output.Html :=
    (variants.filter (fun variant => !isParentVariant variant)).map fun variant => {{
      <option value={{variant.key}}>{{variant.label}}</option>
    }}
  let subgraphOptions : Array Output.Html :=
    (variants.filter isParentVariant).map fun variant => {{
      <option value={{variant.key}}>{{shortenVariantLabel variant.label}}</option>
    }}
  let graphVariantOptions : Array Output.Html :=
    if subgraphOptions.isEmpty then
      primaryOptions
    else
      primaryOptions.push {{
        <optgroup label="Subgraphs">
          {{subgraphOptions}}
        </optgroup>
      }}
  let includeMathlibLegend :=
    publicGraphData.nodes.any (fun node => node.visual.color == Informal.Graph.statementBorderMathlibColor)
  let includeSupportingLegend :=
    publicGraphData.nodes.any (·.supporting)
  let renderLegend (kind : String) (groups : Array Informal.Graph.LegendGroup)
      (note? : Option String := none) (hidden : Bool := false) : Output.Html :=
    let legendGroupHtml : Array Output.Html :=
      groups.map fun group =>
        let summaryHtml : Output.Html :=
          match group.summary? with
          | some summary => {{
              <p class="bp_graph_legend_group_summary">
                {{.text false summary}}
              </p>
            }}
          | Option.none => .empty
        let itemHtml : Array Output.Html :=
          group.items.map fun item =>
            match item.swatch?, item.edgeSwatch? with
            | some swatch, _ => {{
                <span class="bp_graph_legend_item">
                  <span class="bp_graph_legend_swatch" "style"={{swatch.inlineStyle}}></span>
                  {{.text false item.label}}
                </span>
              }}
            | Option.none, some edgeSwatch => {{
                <span class="bp_graph_legend_item">
                  <span class="bp_graph_legend_edge_swatch" aria-hidden="true" "style"={{edgeSwatch.inlineStyle}}></span>
                  {{.text false item.label}}
                </span>
              }}
            | Option.none, Option.none => {{
                <span class="bp_graph_legend_item">
                  {{.text false item.label}}
                </span>
              }}
        {{
          <section class="bp_graph_legend_group">
            <div class="bp_graph_legend_group_header">
              <span class="bp_graph_legend_group_title">{{.text false group.title}}</span>
              {{summaryHtml}}
            </div>
            <div class="bp_graph_legend_items">
              {{itemHtml}}
            </div>
          </section>
        }}
    let noteHtml : Output.Html :=
      match note? with
      | some note => {{
          <p class="bp_graph_legend_note">
            {{.text false note}}
          </p>
        }}
      | Option.none => .empty
    if hidden then
      {{
        <div class="bp_graph_legend" "data-bp-legend-kind"={{kind}} hidden>
          {{noteHtml}}
          {{legendGroupHtml}}
        </div>
      }}
    else
      {{
        <div class="bp_graph_legend" "data-bp-legend-kind"={{kind}}>
          {{noteHtml}}
          {{legendGroupHtml}}
        </div>
      }}
  let fullLegendHtml :=
    renderLegend "full" (Informal.Graph.graphLegendGroups includeMathlibLegend includeSupportingLegend)
      (note? := some Informal.Graph.graphLegendFullViewNote)
  let groupLegendHtml : Output.Html :=
    if hasGroupVariant then
      renderLegend "group" Informal.Graph.groupGraphLegendGroups
        (note? := some Informal.Graph.graphLegendGroupViewNote) (hidden := true)
    else
      .empty
  let graphViewSelectId : String := idBase ++ "--view"
  let graphStatusSelectId : String := idBase ++ "--status"
  let graphDirectionSelectId : String := idBase ++ "--direction"
  let graphPackInputId : String := idBase ++ "--pack"
  let graphPreviewModeSelectId : String := idBase ++ "--preview-mode"
  let graphPreviewPlacementSelectId : String := idBase ++ "--preview-placement"
  let graphLegendPanelId : String := idBase ++ "--legend"
  let graphOptionsPanelId : String := idBase ++ "--options"
  let graphDirectionOptions : Array Output.Html :=
    allGraphDirections.map fun direction =>
      if direction == options.direction then
        {{ <option value={{direction.rankdir}} selected>{{direction.rankdir}}</option> }}
      else
        {{ <option value={{direction.rankdir}}>{{direction.rankdir}}</option> }}
  let graphPackChecked : Array (String × String) :=
    if options.pack then #[("checked", "checked")] else #[]
  let graphPackDefault : String := if options.pack then "true" else "false"
  let previewModeDefault : String := previewMode.dataValue
  let graphPreviewModeOptions : Array Output.Html := #[
    if previewMode == .pinned then
      {{ <option value="pinned" selected>"Click to pin"</option> }}
    else
      {{ <option value="pinned">"Click to pin"</option> }},
    if previewMode == .hover then
      {{ <option value="hover" selected>"Hover"</option> }}
    else
      {{ <option value="hover">"Hover"</option> }}
  ]
  let previewPlacementDefault : String := previewPlacement.dataValue
  let graphPreviewPlacementOptions : Array Output.Html := #[
    if previewPlacement == .docked then
      {{ <option value="docked" selected>"Docked"</option> }}
    else
      {{ <option value="docked">"Docked"</option> }},
    if previewPlacement == .anchored then
      {{ <option value="anchored" selected>"Near node"</option> }}
    else
      {{ <option value="anchored">"Near node"</option> }}
  ]
  let fallbackDot : String :=
    match variants[0]? with
    | some variant => variant.dot
    | Option.none => publicGraphData.toDotWith options
  let previewPanel :=
    Informal.HoverRender.graphPreviewPanel previewMode previewPlacement
  let groupHoverPanel := Informal.HoverRender.graphGroupPreviewPanel
  let staticCanvasAttrs : Array (String × String) :=
    if static then #[("data-bp-graph-static", "true")] else #[]
  let controlsHtml : Output.Html :=
    if static then .empty else {{
      <div class="bp_graph_controls">
        <div class="bp_graph_controls_primary">
          <button
            type="button"
            class="bp_graph_controls_button bp_graph_legend_button"
            aria-haspopup="dialog"
            aria-expanded="false"
            aria-controls={{graphLegendPanelId}}
          >
            "Legend"
          </button>
          <label class="bp_graph_controls_label" for={{graphViewSelectId}}>"View"</label>
          <select id={{graphViewSelectId}} class="bp_graph_controls_select bp_graph_view_select">
            {{graphVariantOptions}}
          </select>
        </div>
        <div class="bp_graph_controls_actions">
          <div class="bp_graph_zoom_controls" role="group" aria-label="Zoom">
            <button
              type="button"
              class="bp_graph_controls_button bp_graph_zoom_button bp_graph_zoom_out"
              aria-label="Zoom out"
            >
              <span aria-hidden="true">"−"</span>
            </button>
            <button
              type="button"
              class="bp_graph_controls_button bp_graph_zoom_button bp_graph_zoom_in"
              aria-label="Zoom in"
            >
              <span aria-hidden="true">"+"</span>
            </button>
            <button
              type="button"
              class="bp_graph_controls_button bp_graph_zoom_button bp_graph_zoom_fit"
              aria-label="Fit graph to view"
            >
              "Fit"
            </button>
          </div>
          <button
            type="button"
            class="bp_graph_controls_button bp_graph_options_button"
            aria-haspopup="dialog"
            aria-expanded="false"
            aria-controls={{graphOptionsPanelId}}
          >
            "Graph options"
          </button>
        </div>
      </div>
    }}
  let legendPopoverHtml : Output.Html :=
    if static then .empty else {{
      <div id={{graphLegendPanelId}} class="bp_graph_legend_popover" hidden>
        <div class="bp_graph_legend_popover_header">
          <span class="bp_graph_legend_popover_title">"Legend"</span>
          <button type="button" class="bp_graph_legend_popover_close" aria-label="Close legend">"Close"</button>
        </div>
        <div class="bp_graph_legend_popover_body">
          {{fullLegendHtml}}
          {{groupLegendHtml}}
        </div>
      </div>
    }}
  let optionsPopoverHtml : Output.Html :=
    if static then .empty else {{
      <div id={{graphOptionsPanelId}} class="bp_graph_options_popover" hidden>
        <div class="bp_graph_options_popover_header">
          <span class="bp_graph_options_popover_title">"Graph options"</span>
          <button type="button" class="bp_graph_options_popover_close" aria-label="Close graph options">"Close"</button>
        </div>
        <div class="bp_graph_options_popover_body">
          <label class="bp_graph_controls_label" for={{graphDirectionSelectId}}>"Direction"</label>
          <select
            id={{graphDirectionSelectId}}
            class="bp_graph_controls_select bp_graph_direction_select"
            data-bp-graph-default-direction={{options.direction.rankdir}}
          >
            {{graphDirectionOptions}}
          </select>
          <label class="bp_graph_option_toggle" for={{graphPackInputId}}>
            <input
              id={{graphPackInputId}}
              type="checkbox"
              class="bp_graph_pack_input"
              data-bp-graph-default-pack={{graphPackDefault}}
              {{graphPackChecked}}/>
            <span>"Pack disconnected components"</span>
          </label>
          <label class="bp_graph_controls_label" for={{graphStatusSelectId}}>"Status"</label>
          <select
            id={{graphStatusSelectId}}
            class="bp_graph_controls_select bp_graph_status_select"
          >
            <option value="all">"All statuses"</option>
            <option value="ready">"Ready to formalize"</option>
            <option value="blocked">"Blocked"</option>
            <option value="formalized">"Formalized"</option>
            <option value="mathlib">"In Mathlib"</option>
          </select>
          <label class="bp_graph_controls_label" for={{graphPreviewModeSelectId}}>"Preview"</label>
          <select
            id={{graphPreviewModeSelectId}}
            class="bp_graph_controls_select bp_graph_preview_mode_select"
            data-bp-graph-default-preview-mode={{previewModeDefault}}
          >
            {{graphPreviewModeOptions}}
          </select>
          <label class="bp_graph_controls_label" for={{graphPreviewPlacementSelectId}}>"Position"</label>
          <select
            id={{graphPreviewPlacementSelectId}}
            class="bp_graph_controls_select bp_graph_preview_placement_select"
            data-bp-graph-default-preview-placement={{previewPlacementDefault}}
          >
            {{graphPreviewPlacementOptions}}
          </select>
        </div>
      </div>
    }}
  let previewPanelHtml : Output.Html := if static then .empty else previewPanel
  let groupHoverPanelHtml : Output.Html := if static then .empty else groupHoverPanel
  -- Inline per-node full-card templates for the click-activated modal. Interactive
  -- canvases only (static node-page graphs keep the lightweight statement peek and
  -- pass no templates). `<template>` content is inert, so this ships offline with
  -- no fetch; `graph.mjs collectPreviewTemplates` reads it as the preview source.
  let previewTemplatesHtml : Output.Html :=
    if static then .empty else {{
      <div class="bp_graph_preview_templates" hidden>
        {{previewTemplates}}
      </div>
    }}
  {{
    <div class="bp_graph_fullwidth">
      {{controlsHtml}}
      {{legendPopoverHtml}}
      {{optionsPopoverHtml}}
      <div
        class="bp_graph_canvas"
        "data-bp-graph-direction"={{options.direction.rankdir}}
        "data-bp-graph-pack"={{graphPackDefault}}
        {{staticCanvasAttrs}}
      >
        <script type="application/json" class="bp-graph-data">
          {{.text false s!"{publicGraphDataJson}"}}
        </script>
        <script type="application/json" class="bp-graph-variants">
          {{.text false s!"{graphVariantJson}"}}
        </script>
        <script type="text/plain" class="dot-source">
          {{.text false s!"{fallbackDot}"}}
        </script>
      </div>
      {{previewPanelHtml}}
      {{groupHoverPanelHtml}}
      {{previewTemplatesHtml}}
    </div>
  }}

open Verso Doc Elab Genre Manual in
block_extension Block.graph (graphData : GraphBlockData) where
  -- for TOC
  -- localContentItem _ _ _ := none
  data := toJson graphData
  traverse id data _contents := do
      match ← Informal.ExtensionDecode.decode? (α := GraphBlockData) data
          (fun _ => "Malformed data in Block.graph.traverse") with
      | some graphData =>
        modify fun state =>
          let state := Informal.GraphApi.saveData state id graphData.semanticGraphData
          let state :=
            match graphData.declRegistryJson? with
            | some json => Informal.TraversalIndex.DeclRegistry.saveRaw state json
            | Option.none => state
          let state :=
            match graphData.declBodiesJson? with
            | some json => Informal.TraversalIndex.DeclRegistry.saveBodies state json
            | Option.none => state
          match graphData.declNamePrefix? with
          | some pfx => Informal.TraversalIndex.DeclRegistry.savePrefix state pfx
          | Option.none => state
      | Option.none =>
        pure ()
      return none
  toTeX := none
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI goB id data _blocks => do
      let graphData : GraphBlockData ←
        match ← Informal.ExtensionDecode.decode? (α := GraphBlockData) data
            (fun err => s!"Malformed data in Block.graph.toHtml ({err})") with
        | some graphData => pure graphData
        | Option.none => pure { semanticGraphData := {}, options := {} }
      let s ← HtmlT.state
      -- Render the full project-declaration graph when present (blueprint +
      -- supporting nodes); the traversal cache still holds only the blueprint
      -- semantic graph, so the master graph and metrics are unaffected.
      let renderData := graphData.renderGraphData?.getD graphData.semanticGraphData
      let publicGraphData := Informal.GraphApi.finalDataForBlock s id renderData
      let graphVariants := publicGraphData.renderVariants graphData.options
      let graphHtmlAttrs := s.htmlId id
      let idBase : String :=
        match graphHtmlAttrs.findSome? fun
            | ("id", value) => some value
            | _ => Option.none with
        | some value => value
        | Option.none => Informal.HtmlId.prefixed "bp-graph" (toString id)
      -- Full two-column node cards, embedded as inline templates for the
      -- click-activated modal (offline-correct; resolved by label at runtime).
      let previewTemplates ← renderGraphNodeCardTemplates goB s publicGraphData.nodes
      return renderGraphFullwidth publicGraphData graphVariants graphData.options idBase
        (static := false)
        (previewMode := graphData.previewMode)
        (previewPlacement := graphData.previewPlacement)
        (previewTemplates := previewTemplates)
  extraCss := graphAssetBundle.css
  extraJs := graphAssetBundle.js

def buildAll : CoreM Informal.Graph.GraphData := do
  reportImportedConflicts
  let env ← getEnv
  let state := informalExt.getState env
  let inMathlib ← Informal.Graph.mkInMathlibPredicate
  let external : Informal.Graph.ExternalCodeStatus := { inMathlib }
  let roots : Array Name := state.data.toArray.map (·.1)
  let groupTitles := state.groups.toArray
  let semanticGraphData :=
    Informal.Graph.buildDataWithExternal state roots external (groupTitles := groupTitles)
  return semanticGraphData

/--
Augment the blueprint dependency graph with every in-workspace declaration in the
project's own module(s), as subordinate "supporting" nodes with edges from the
actual Lean const-level dependency structure.

Opt-in via `verso.blueprint.graph.includeAllDecls` (off by default → returns `base`,
so existing consumers and tests keep the blueprint-only graph). Project modules are
inferred from the authored `(lean := …)` declarations whose snapshot provenance is
in the workspace (so Mathlib/core/dependency declarations are excluded). Every
non-internal definition/theorem/inductive in those modules becomes a graph node:
authored declarations keep their blueprint node and gain const-derived edges,
un-annotated declarations are added as muted supporting nodes. Const dependencies
are split into statement (type) and proof (value) axes and merged as
automatically-inferred use-refs (manual author edges win on conflict).

This is used only for the rendered Dependency-Graph block; it never enters the
traversal-cached semantic graph, so master-graph metrics and node pages are
unaffected. -/
def buildProjectDeclGraph (base : Informal.Graph.GraphData) : CoreM Informal.Graph.GraphData := do
  if !verso.blueprint.graph.includeAllDecls.get (← getOptions) then
    return base
  let env ← getEnv
  let state := informalExt.getState env
  -- Project module roots + declaration enumeration are shared with the declaration
  -- registry (`DeclRegistry`). The graph keeps `private` helpers out (the default
  -- `includePrivate := false`) to stay readable; the registry tracks them too. The
  -- root harvest accepts authored `(lean := …)` decls whose source is inside the
  -- project — the consumer's own package or a sibling package — which is why the
  -- sibling-package showcase now gains supporting nodes.
  let projectModuleRoots ← Informal.DeclRegistry.projectModuleRoots
  if projectModuleRoots.isEmpty then
    return base
  let projectDeclsFull ← Informal.DeclRegistry.enumerateProjectDecls projectModuleRoots
  let projectDecls : Array (Name × ConstantInfo) := projectDeclsFull.map fun (n, ci, _) => (n, ci)
  let projectDeclSet : NameSet :=
    projectDeclsFull.foldl (init := ({} : NameSet)) fun acc (n, _, _) => acc.insert n
  let leanNameLabels := state.leanNameLabels
  -- Graph key(s) for a declaration: its blueprint label(s) if authored, else the
  -- declaration name itself (a supporting node), else empty (external).
  let graphKeysOf : Name → Array Name := fun name =>
    match leanNameLabels.get? name with
    | some labels => if labels.isEmpty then #[name] else labels.map (fun l => (l : Name))
    | none => if projectDeclSet.contains name then #[name] else #[]
  let isAuthored : Name → Bool := fun name =>
    match leanNameLabels.get? name with
    | some labels => !labels.isEmpty
    | none => false
  let pushUniq := fun (xs ys : Array Name) =>
    ys.foldl (fun acc y => if acc.contains y then acc else acc.push y) xs
  -- Accumulate const-derived statement/proof dep keys per target graph key.
  let mut stmtDepsByKey : Lean.NameMap (Array Name) := {}
  let mut proofDepsByKey : Lean.NameMap (Array Name) := {}
  for (decl, cinfo) in projectDecls do
    let targetKeys := graphKeysOf decl
    if targetKeys.isEmpty then continue
    let (typeDeps, valueDeps) := Informal.Graph.projectConstDeps projectDeclSet decl cinfo
    let mapKeys := fun (deps : Array Name) =>
      deps.foldl (init := (#[] : Array Name)) fun acc dep => pushUniq acc (graphKeysOf dep)
    let stmtKeys := mapKeys typeDeps
    let proofKeys := (mapKeys valueDeps).filter (fun k => !stmtKeys.contains k)
    for tk in targetKeys do
      let sKeys := stmtKeys.filter (· != tk)
      let pKeys := proofKeys.filter (· != tk)
      if !sKeys.isEmpty then
        stmtDepsByKey := stmtDepsByKey.insert tk (pushUniq (stmtDepsByKey.getD tk #[]) sKeys)
      if !pKeys.isEmpty then
        proofDepsByKey := proofDepsByKey.insert tk (pushUniq (proofDepsByKey.getD tk #[]) pKeys)
  -- Merge const deps into authored nodes; build supporting nodes for the rest.
  let autoRefs := fun (keys : Array Name) =>
    keys.map (fun k => ({ label := (k : Data.Label), origin := .automatic } : Data.UseRef))
  let baseLabels : NameSet := base.nodes.foldl (init := ({} : NameSet)) fun acc n => acc.insert n.label
  let mergedNodes := base.nodes.map fun node =>
    { node with
      statementUses :=
        Data.UseRef.mergeByLabel node.statementUses (autoRefs (stmtDepsByKey.getD node.label #[]))
      proofUses :=
        Data.UseRef.mergeByLabel node.proofUses (autoRefs (proofDepsByKey.getD node.label #[])) }
  let mut supportingNodes : Array Informal.Graph.NodeData := #[]
  for (decl, cinfo) in projectDecls do
    if isAuthored decl then continue
    if baseLabels.contains decl then continue
    let kind := (Informal.Data.ConstantInfo.blueprintNodeKind? cinfo).getD Data.NodeKind.definition
    -- Supporting nodes are exactly the unwired public project declarations, which
    -- all have a `decl/{slug}/` page (see `DeclPage`); linking them costs no
    -- runtime change (the graph runtime already follows node hrefs).
    let node := Informal.Graph.mkSupportingNodeData kind decl
      (autoRefs (stmtDepsByKey.getD decl #[])) (autoRefs (proofDepsByKey.getD decl #[]))
    supportingNodes := supportingNodes.push
      { node with href := some (Informal.NodeRoute.declPageHref decl.toString) }
  let augmented : Informal.Graph.GraphData := { base with nodes := mergedNodes ++ supportingNodes }
  return { augmented with edges := Informal.Graph.edgesForGraph augmented.toGraph }

open Verso.ArgParse

instance : FromArgVal GraphDirection Verso.Doc.Elab.PartElabM where
  fromArgVal := {
    description := doc!"graph direction (`LR`, `RL`, `TB`, or `BT`)"
    signature := CanMatch.Ident ∪ CanMatch.String
    get := fun
      | .name id =>
        match GraphDirection.parse? id.getId.toString with
        | some d => pure d
        | none => throwErrorAt id "Expected one of `LR`, `RL`, `TB`, `BT`"
      | .str s =>
        match GraphDirection.parse? s.getString with
        | some d => pure d
        | none => throwErrorAt s "Expected one of \"lr\", \"rl\", \"tb\", \"bt\""
      | other =>
        throwError "Expected a direction identifier or string, got {toMessageData other}"
  }

instance : FromArgVal Informal.HoverRender.PreviewMode Verso.Doc.Elab.PartElabM where
  fromArgVal := {
    description := doc!"graph preview mode (`pinned` or `hover`)"
    signature := CanMatch.Ident ∪ CanMatch.String
    get := fun
      | .name id =>
        match parseGraphPreviewMode? id.getId.toString with
        | some mode => pure mode
        | none => throwErrorAt id "Expected `pinned` or `hover`"
      | .str s =>
        match parseGraphPreviewMode? s.getString with
        | some mode => pure mode
        | none => throwErrorAt s "Expected \"pinned\" or \"hover\""
      | other =>
        throwError "Expected a preview mode identifier or string, got {toMessageData other}"
  }

instance : FromArgVal Informal.HoverRender.PreviewPlacement Verso.Doc.Elab.PartElabM where
  fromArgVal := {
    description := doc!"graph preview placement (`docked` or `anchored`)"
    signature := CanMatch.Ident ∪ CanMatch.String
    get := fun
      | .name id =>
        match parseGraphPreviewPlacement? id.getId.toString with
        | some placement => pure placement
        | none => throwErrorAt id "Expected `docked` or `anchored`"
      | .str s =>
        match parseGraphPreviewPlacement? s.getString with
        | some placement => pure placement
        | none => throwErrorAt s "Expected \"docked\" or \"anchored\""
      | other =>
        throwError "Expected a preview placement identifier or string, got {toMessageData other}"
  }

structure BlueprintGraphConfig where
  direction : Option GraphDirection := none
  pack : Option Bool := none
  preview : Option Informal.HoverRender.PreviewMode := none
  previewPlacement : Option Informal.HoverRender.PreviewPlacement := none

instance : FromArgs BlueprintGraphConfig Verso.Doc.Elab.PartElabM where
  fromArgs :=
    BlueprintGraphConfig.mk <$>
      .named' `direction true <*>
      .named' `pack true <*>
      .named' `preview true <*>
      .named' `previewPlacement true

def parseGraphDirection (cfg : BlueprintGraphConfig) : Verso.Doc.Elab.PartElabM GraphDirection := do
  match cfg.direction with
  | none =>
    let configured :=
      (← getOptions).get
        verso.blueprint.graph.defaultDirection.name
        verso.blueprint.graph.defaultDirection.defValue
    match GraphDirection.parse? configured with
    | some direction => pure direction
    | none =>
      logWarning m!"Invalid value '{configured}' for option 'verso.blueprint.graph.defaultDirection'; expected LR, RL, TB, or BT. Falling back to TB."
      pure .TB
  | some direction => pure direction

def parseGraphOptions (cfg : BlueprintGraphConfig) : Verso.Doc.Elab.PartElabM GraphOptions := do
  let direction ← parseGraphDirection cfg
  let pack :=
    cfg.pack.getD <|
      (← getOptions).get
        verso.blueprint.graph.defaultPack.name
        verso.blueprint.graph.defaultPack.defValue
  pure { direction, pack }

def parseGraphPreviewMode
    (cfg : BlueprintGraphConfig) : Verso.Doc.Elab.PartElabM Informal.HoverRender.PreviewMode := do
  match cfg.preview with
  | none =>
    let configured :=
      (← getOptions).get
        verso.blueprint.graph.defaultPreviewMode.name
        verso.blueprint.graph.defaultPreviewMode.defValue
    match parseGraphPreviewMode? configured with
    | some mode => pure mode
    | none =>
      logWarning m!"Invalid value '{configured}' for option 'verso.blueprint.graph.defaultPreviewMode'; expected pinned or hover. Falling back to pinned."
      pure .pinned
  | some mode => pure mode

def parseGraphPreviewPlacement
    (cfg : BlueprintGraphConfig) : Verso.Doc.Elab.PartElabM Informal.HoverRender.PreviewPlacement := do
  match cfg.previewPlacement with
  | none =>
    let configured :=
      (← getOptions).get
        verso.blueprint.graph.defaultPreviewPlacement.name
        verso.blueprint.graph.defaultPreviewPlacement.defValue
    match parseGraphPreviewPlacement? configured with
    | some placement => pure placement
    | none =>
      logWarning m!"Invalid value '{configured}' for option 'verso.blueprint.graph.defaultPreviewPlacement'; expected docked or anchored. Falling back to docked."
      pure .docked
  | some placement => pure placement

open Verso Doc Elab Syntax in
def mkGraphPart (stx : Syntax) (endPos : String.Pos.Raw) (options : GraphOptions := {})
    (previewMode : Informal.HoverRender.PreviewMode := .pinned)
    (previewPlacement : Informal.HoverRender.PreviewPlacement := .docked) :
    PartElabM FinishedPart := do
  let titlePreview := "Dependency Graph"
  let titleInlines ← `(inline | "Dependency Graph")
  let expandedTitle ← #[titleInlines].mapM (elabInline ·)
  let metadata : Option (TSyntax `term) := some (← `(term| { number := false }))
  let semanticGraphData ← buildAll
  let renderGraphData ← buildProjectDeclGraph semanticGraphData
  let renderGraphData? : Option Informal.Graph.GraphData :=
    if renderGraphData.nodes.size > semanticGraphData.nodes.size then some renderGraphData else none
  -- Build the all-declarations registry (public JSON) + the internal proof/value
  -- bodies under the same opt-in as the all-decls graph (`includeAllDecls`);
  -- serialized here at elaboration time (env available). The registry is emitted
  -- as `-verso-data/decl-registry.json` at generation time; the bodies stay in
  -- the traversal store for the decl-page emitter only.
  let (declRegistryJson?, declBodiesJson?) ← do
    if verso.blueprint.graph.includeAllDecls.get (← Lean.getOptions) then
      let (registry, bodies) ← Informal.DeclRegistry.buildDeclRegistry
      if registry.decls.isEmpty then pure (none, none)
      else pure (some (toJson registry).compress, some (toJson bodies).compress)
    else
      pure (none, none)
  -- The short-name prefix rides the same block-data channel (captured here, where
  -- `Lean.Options` exist) but is independent of `includeAllDecls`.
  let declNamePrefix? :=
    let pfx := Informal.DeclRegistry.configuredNamePrefix (← Lean.getOptions)
    if pfx.isEmpty then none else some pfx
  if verso.blueprint.debug.commands.get (← Lean.getOptions) then
    logInfo m!"Adding {semanticGraphData.nodes.size} blueprint graph nodes (rendered graph: {renderGraphData.nodes.size} nodes, {renderGraphData.edges.size} edges)"
  let graphData : GraphBlockData :=
    { semanticGraphData, renderGraphData?, declRegistryJson?, declBodiesJson?, declNamePrefix?,
      options, previewMode, previewPlacement }
  let block ← ``(Verso.Doc.Block.other (Informal.Commands.Block.graph $(quote graphData)) #[])
  let subParts := #[]
  pure <| FinishedPart.mk stx stx expandedTitle titlePreview metadata #[block] subParts endPos

open Verso Doc Elab Syntax PartElabM in
@[part_command Lean.Doc.Syntax.command]
public meta def depGraph : PartCommand
  | stx@`(block|command{blueprint_graph $args*}) => do
    let cfg ← Verso.ArgParse.parseThe BlueprintGraphConfig (← parseArgs args)
    let options ← parseGraphOptions cfg
    let previewMode ← parseGraphPreviewMode cfg
    let previewPlacement ← parseGraphPreviewPlacement cfg
    let endPos := stx.getTailPos?.get!
    closePartsUntil 1 endPos
    addPart (← mkGraphPart stx endPos options previewMode previewPlacement)
  | _ => (Lean.Elab.throwUnsupportedSyntax : PartElabM Unit)

end Informal.Commands
