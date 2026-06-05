/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.Group
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.PreviewCache
import VersoBlueprint.TraversalIndex

namespace Informal
namespace RelatedPanel

open Verso
open Verso.Genre Manual
open Verso.Output.Html

private def resolveStoredGroupData?
    (state : Verso.Genre.Manual.TraverseState) (label : Data.Label) : Option GroupBlockData :=
  Informal.TraversalIndex.Groups.data? state label

private structure GroupRenderInfo where
  label : Data.Label
  title : String
  declared : Bool := false

/-- Render-time context shared by group and reverse-dependency header panels. -/
structure Context where
  state : Verso.Genre.Manual.TraverseState
  storedBlocks : Array BlockData

/-- Collect the traversal data needed to render related-block panels. -/
def Context.ofState (state : Verso.Genre.Manual.TraverseState) : Context := {
  state
  storedBlocks := collectStoredBlocks state
}

private def blockSummaryTitle (ctx : Context) (data : BlockData) : String :=
  data.displayTitle ctx.state

private def groupRenderInfo?
    (ctx : Context) (data : BlockData) : Option GroupRenderInfo := do
  let parent ← data.parent
  match resolveStoredGroupData? ctx.state parent with
  | some groupData => some { label := parent, title := groupData.header, declared := true }
  | none => some { label := parent, title := parent.toString, declared := false }

private structure Entry where
  source : BlockData
  previewId : String
  previewKey : String
  previewTitle : String
  href : Option String := none
  metaHtml : Output.Html := .empty

private structure Config where
  chipText : Nat → String
  chipTitle : Nat → String
  singleTitle : Entry → String
  panelTitle : Nat → String
  panelMeta : String
  panelMetaClass : String := "bp_used_by_panel_meta"
  previewDefaultTitle : String := "Hover an entry"
  previewEmptyText : String := "Hover an entry to preview it."
  chipClass : String := "bp_used_by_chip"
  emptyChipClass : String := "bp_used_by_chip bp_used_by_chip_empty"

private structure UsedByEntry where
  source : BlockData
  inStatement : Bool := false
  inProof : Bool := false

private def sortUsedByEntries (entries : Array UsedByEntry) : Array UsedByEntry :=
  entries.qsort fun a b =>
    let aNum := a.source.globalCount.getD a.source.count
    let bNum := b.source.globalCount.getD b.source.count
    aNum < bNum ||
      (aNum == bNum && a.source.label.toString < b.source.label.toString)

private def collectUsedByEntries
    (ctx : Context) (target : Data.Label) : Array UsedByEntry :=
  sortUsedByEntries <| ctx.storedBlocks.foldl (init := #[]) fun acc source =>
    if source.label == target then
      acc
    else
      let inStatement := source.statementDeps.contains target
      let inProof := source.proofDeps.contains target
      if !inStatement && !inProof then
        acc
      else
        acc.push { source, inStatement, inProof }

private def collectGroupEntries
    (ctx : Context) (target : BlockData) (group : GroupRenderInfo) :
    Array BlockData :=
  ctx.storedBlocks.foldl (init := #[]) fun acc source =>
    if source.label == target.label then
      acc
    else if source.parent == some group.label then
      match source.kind with
      | .statement _ => acc.push source
      | .proof => acc
    else
      acc

private def usedByPreviewId (targetLabel sourceLabel : Data.Label) : String :=
  s!"bp-used-by-{Informal.HoverRender.previewKey (toString targetLabel)}-{Informal.HoverRender.previewKey (toString sourceLabel)}"

private def groupPreviewId (targetLabel sourceLabel : Data.Label) : String :=
  s!"bp-group-{Informal.HoverRender.previewKey (toString targetLabel)}-{Informal.HoverRender.previewKey (toString sourceLabel)}"

private def previewLookupKey (source : BlockData) : String :=
  PreviewCache.key source.label (PreviewCache.Facet.ofInProgressKind source.kind)

private def usedByChipText (count : Nat) : String :=
  s!"used by {count}"

private def renderUsedByAxisBadges (entry : UsedByEntry) : Output.Html :=
  open Verso.Output.Html in
  let statementBadge : Array Output.Html :=
    if entry.inStatement then
      #[{{<span class="bp_used_by_axis_badge">"statement"</span>}}]
    else
      #[]
  let proofBadge : Array Output.Html :=
    if entry.inProof then
      #[{{<span class="bp_used_by_axis_badge">"proof"</span>}}]
    else
      #[]
  .seq (statementBadge ++ proofBadge)

private def mkEntry {m}
    [Monad m]
    (ctx : Context)
    (source : BlockData) (previewId : String)
    (metaHtml : Output.Html := .empty) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m Entry := do
  let previewTitle := blockSummaryTitle ctx source
  let href := Informal.TraversalIndex.Nodes.href? ctx.state source.label
  pure {
    source
    previewId
    previewKey := previewLookupKey source
    previewTitle
    href
    metaHtml
  }

private def loadingBody (detail : String) : Output.Html :=
  open Verso.Output.Html in
  {{
    <div class="bp_used_by_preview_message" "data-bp-preview-message"="loading">
      <div class="bp_used_by_preview_message_title">"Loading preview"</div>
      <div class="bp_used_by_preview_message_detail">{{.text true detail}}</div>
    </div>
  }}

private def renderPanel (cfg : Config) (entries : Array Entry) : Output.Html :=
  open Verso.Output.Html in
  let renderChip (chipClass : String) (chipTitle : String) (n : Nat) : Output.Html :=
    {{<span class={{chipClass}} title={{chipTitle}}>{{.text true (cfg.chipText n)}}</span>}}
  if entries.isEmpty then
    renderChip cfg.emptyChipClass (cfg.chipTitle 0) 0
  else if h : entries.size = 1 then
    let entry := entries[0]'(by simp [h])
    let chipNode : Output.Html :=
      if let some href := entry.href then
        {{<a class={{s!"{cfg.chipClass} bp_code_link"}} href={{href}} title={{cfg.singleTitle entry}}>
            {{.text true (cfg.chipText 1)}}
          </a>}}
      else
        renderChip cfg.chipClass (cfg.singleTitle entry) 1
    Informal.HoverRender.inlinePreviewNode
      chipNode entry.previewId entry.previewTitle
      (previewLookupKey? := some entry.previewKey)
      (previewFallbackLabel? := some s!"{entry.source.label}")
  else
    let renderRow (itemClass : String) (entry : Entry) : Output.Html :=
      let rowNode : Output.Html :=
        let titleNode := {{<span class="bp_used_by_target_title">{{.text true entry.previewTitle}}</span>}}
        let metaNode := {{
          <span class="bp_used_by_target_meta">
            {{entry.metaHtml}}
          </span>
        }}
        if let some href := entry.href then
          {{<a class="bp_used_by_target" href={{href}}>{{titleNode}}{{metaNode}}</a>}}
        else
          {{<span class="bp_used_by_target">{{titleNode}}{{metaNode}}</span>}}
      {{
        <li class={{itemClass}}
            "data-bp-used-preview-id"={{entry.previewId}}
            "data-bp-used-preview-key"={{entry.previewKey}}
            "data-bp-used-preview-title"={{entry.previewTitle}}>
          {{rowNode}}
        </li>
      }}
    let (selectedEntry?, rows) :=
      entries.foldl (init := (none, #[])) fun (selectedEntry?, acc) entry =>
        match selectedEntry? with
        | none =>
          (some entry, acc.push (renderRow "bp_used_by_item bp_used_by_item_active" entry))
        | some selectedEntry =>
          (some selectedEntry, acc.push (renderRow "bp_used_by_item" entry))
    let previewTitle :=
      match selectedEntry? with
      | some entry => entry.previewTitle
      | none => cfg.previewDefaultTitle
    let previewBody : Output.Html := loadingBody cfg.previewEmptyText
    {{
      <div class="bp_used_by_wrap">
        <button type="button" class={{cfg.chipClass}} title={{cfg.chipTitle entries.size}} "aria-expanded"="false">
          {{.text true (cfg.chipText entries.size)}}
        </button>
        <div class="bp_used_by_panel">
          <div class="bp_used_by_panel_header">
            <div class="bp_used_by_panel_title">{{.text true (cfg.panelTitle entries.size)}}</div>
            <div class={{cfg.panelMetaClass}}>{{.text true cfg.panelMeta}}</div>
          </div>
          <div class="bp_used_by_panel_body">
            <ul class="bp_used_by_list">
              {{rows}}
            </ul>
            <div class="bp_used_by_preview_surface">
              <div class="bp_used_by_preview_header">
                <div class="bp_used_by_preview_label">"Preview"</div>
                <div class="bp_used_by_preview_title">{{.text true previewTitle}}</div>
              </div>
              <div class="bp_used_by_preview_body">
                {{previewBody}}
              </div>
            </div>
          </div>
        </div>
      </div>
    }}

/-- Render the reverse-dependency header extra for a statement block. -/
def renderUsedByExtra {m}
    [Monad m]
    (ctx : Context)
    (data : BlockData) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m Output.Html := do
  match data.kind with
  | .proof => pure .empty
  | .statement _ =>
    let entries := collectUsedByEntries ctx data.label
    let panelEntries ← entries.mapM fun entry =>
      mkEntry ctx entry.source
        (usedByPreviewId data.label entry.source.label)
        (metaHtml := {{
          <code>s!"{entry.source.label}"</code>
          {{renderUsedByAxisBadges entry}}
        }})
    let cfg : Config := {
      chipText := usedByChipText
      chipTitle := fun n =>
        if n == 0 then
          "No reverse dependencies"
        else
          s!"Reverse dependencies for {data.label}"
      singleTitle := fun entry => s!"Reverse dependency: {entry.previewTitle}"
      panelTitle := fun n => s!"Used by {n}"
      panelMeta := "Hover a use site to preview it."
      previewDefaultTitle := "Hover a use site"
      previewEmptyText := "Hover a use site to preview it."
    }
    pure <| renderPanel cfg panelEntries

/-- Render the group-membership header extra, if the block belongs to a group. -/
def renderGroupExtra {m}
    [Monad m]
    (ctx : Context)
    (data : BlockData) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m (Option Output.Html) := do
  match data.kind, groupRenderInfo? ctx data with
  | .proof, _ => pure none
  | .statement _, none => pure none
  | .statement _, some group =>
    let siblings := collectGroupEntries ctx data group
    if group.declared && siblings.isEmpty then
      return none
    let panelEntries ← siblings.mapM fun source =>
      mkEntry ctx source
        (groupPreviewId data.label source.label)
        (metaHtml := {{<code>s!"{source.label}"</code>}})
    let chipClass :=
      if group.declared then
        "bp_used_by_chip"
      else
        "bp_used_by_chip bp_used_by_chip_warn"
    let emptyChipClass :=
      if group.declared then
        "bp_used_by_chip bp_used_by_chip_empty"
      else
        "bp_used_by_chip bp_used_by_chip_empty bp_used_by_chip_warn"
    let panelMeta :=
      if group.declared then
        "Hover another entry in this group to preview it."
      else
        s!"No :::group declaration was found for parent '{group.label}'; showing entries that share this parent label."
    let cfg : Config := {
      chipText := fun _ => "group"
      chipTitle := fun n =>
        if n == 0 then
          if group.declared then
            s!"Group: {group.title}. No other entries in this group."
          else
            s!"Parent group '{group.label}' is referenced here, but no :::group declaration was found."
        else if group.declared then
          s!"Other entries in group {group.title}"
        else
          s!"Undeclared group '{group.label}'"
      singleTitle := fun entry =>
        if group.declared then
          s!"Group member: {entry.previewTitle}"
        else
          s!"Undeclared group '{group.label}': {entry.previewTitle}"
      panelTitle := fun n => s!"Group: {group.title} ({n})"
      panelMeta
      panelMetaClass := if group.declared then "bp_used_by_panel_meta" else "bp_used_by_panel_meta bp_used_by_chip_warn"
      previewDefaultTitle := "Hover a group entry"
      previewEmptyText := "Hover a group entry to preview it."
      chipClass
      emptyChipClass
    }
    pure <| some (renderPanel cfg panelEntries)

end RelatedPanel
end Informal
