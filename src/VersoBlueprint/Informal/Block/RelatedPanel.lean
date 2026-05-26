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

/-!
Rendering for the small relationship panels attached to informal blocks.

These panels answer local navigation questions: which group entries belong with
this block, which blocks this one uses, and which blocks use this one. The data
comes from traversal stores; this module keeps the HTML presentation separate
from the main block renderer.
-/

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

private def storedBlockByLabel? (ctx : Context) (label : Data.Label) : Option BlockData :=
  ctx.storedBlocks.find? (·.label == label)

private def groupRenderInfo?
    (ctx : Context) (data : BlockData) : Option GroupRenderInfo := do
  let parent ← data.parent
  match resolveStoredGroupData? ctx.state parent with
  | some groupData => some { label := parent, title := groupData.header, declared := true }
  | none => some { label := parent, title := parent.toString, declared := false }

private structure Entry where
  label : Data.Label
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
  panelMetaClass : String := "bp_relation_panel_meta"
  previewDefaultTitle : String := "Hover an entry"
  previewEmptyText : String := "Hover an entry to preview it."
  chipClass : String := "bp_relation_chip"
  emptyChipClass : String := "bp_relation_chip bp_relation_chip_empty"
  singleAsPanel : Bool := false

private structure UsedByEntry where
  source : BlockData
  inStatement : Bool := false
  inProof : Bool := false

private structure UsesEntry where
  label : Data.Label
  target? : Option BlockData := none
  inStatement : Bool := false
  inProof : Bool := false
  origins : Array Data.UseOrigin := #[]
  intents : Array Data.UseIntent := #[]

private def sortUsedByEntries (entries : Array UsedByEntry) : Array UsedByEntry :=
  entries.qsort fun a b =>
    BlockData.traversalOrderLess a.source b.source

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

private def pushUnique [DecidableEq α] (values : Array α) (value : α) : Array α :=
  if values.contains value then values else values.push value

private def mergeUsesEntry (existing : UsesEntry) (useRef : Data.UseRef) (isProof : Bool) :
    UsesEntry :=
  {
    existing with
      inStatement := existing.inStatement || !isProof
      inProof := existing.inProof || isProof
      origins := pushUnique existing.origins useRef.origin
      intents := pushUnique existing.intents useRef.intent
  }

private def addUsesEntry
    (ctx : Context) (acc : Array UsesEntry) (useRef : Data.UseRef) (isProof : Bool) :
    Array UsesEntry :=
  if acc.any (·.label == useRef.label) then
    acc.map fun entry =>
      if entry.label == useRef.label then
        mergeUsesEntry entry useRef isProof
      else
        entry
  else
    acc.push <| mergeUsesEntry {
      label := useRef.label
      target? := storedBlockByLabel? ctx useRef.label
    } useRef isProof

private def usesEntryLess (a b : UsesEntry) : Bool :=
  match a.target?, b.target? with
  | some aTarget, some bTarget => BlockData.traversalOrderLess aTarget bTarget
  | some _, none => true
  | none, some _ => false
  | none, none => a.label.toString < b.label.toString

private def collectUsesEntries
    (ctx : Context) (data : BlockData) : Array UsesEntry :=
  let source := (storedBlockByLabel? ctx data.label).getD data
  let entries :=
    source.statementUses.foldl (init := #[]) fun acc useRef =>
      addUsesEntry ctx acc useRef false
  source.proofUses.foldl (init := entries) fun acc useRef =>
    addUsesEntry ctx acc useRef true
  |>.qsort usesEntryLess

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

private def usesPreviewId (sourceLabel targetLabel : Data.Label) : String :=
  s!"bp-uses-{Informal.HoverRender.previewKey (toString sourceLabel)}-{Informal.HoverRender.previewKey (toString targetLabel)}"

private def groupPreviewId (targetLabel sourceLabel : Data.Label) : String :=
  s!"bp-group-{Informal.HoverRender.previewKey (toString targetLabel)}-{Informal.HoverRender.previewKey (toString sourceLabel)}"

private def previewLookupKey (source : BlockData) : String :=
  PreviewCache.key source.label (PreviewCache.Facet.ofInProgressKind source.kind)

private def usedByChipText (count : Nat) : String :=
  s!"used by {count}"

private def usesChipText (count : Nat) : String :=
  s!"uses {count}"

private def renderAxisBadges (inStatement inProof : Bool) : Output.Html :=
  open Verso.Output.Html in
  let statementBadge : Array Output.Html :=
    if inStatement then
      #[{{<span class="bp_relation_axis_badge">"statement"</span>}}]
    else
      #[]
  let proofBadge : Array Output.Html :=
    if inProof then
      #[{{<span class="bp_relation_axis_badge">"proof"</span>}}]
    else
      #[]
  .seq (statementBadge ++ proofBadge)

private def renderUsedByAxisBadges (entry : UsedByEntry) : Output.Html :=
  renderAxisBadges entry.inStatement entry.inProof

private def renderUseAxisBadges (entry : UsesEntry) : Output.Html :=
  renderAxisBadges entry.inStatement entry.inProof

private def renderUseMetadataBadges (entry : UsesEntry) : Output.Html :=
  open Verso.Output.Html in
  let originBadges :=
    entry.origins.filter (· != .manual) |>.map fun origin =>
      {{<span class="bp_relation_axis_badge bp_uses_origin_badge">{{.text true (toString origin)}}</span>}}
  let intentBadges :=
    entry.intents.filter (· != .regular) |>.map fun intent =>
      {{<span class="bp_relation_axis_badge bp_uses_intent_badge">{{.text true (toString intent)}}</span>}}
  .seq (originBadges ++ intentBadges)

private def mkBlockEntry {m}
    [Monad m]
    (ctx : Context)
    (source : BlockData) (previewId : String)
    (metaHtml : Output.Html := .empty) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m Entry := do
  let previewTitle := blockSummaryTitle ctx source
  let href := Informal.TraversalIndex.Nodes.href? ctx.state source.label
  pure {
    label := source.label
    previewId
    previewKey := previewLookupKey source
    previewTitle
    href
    metaHtml
  }

private def mkLabelEntry {m}
    [Monad m]
    (ctx : Context)
    (label : Data.Label) (previewId : String)
    (metaHtml : Output.Html := .empty) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m Entry := do
  let previewTitle := s!"{label}"
  pure {
    label
    previewId
    previewKey := PreviewCache.key label .statement
    previewTitle
    href := Informal.TraversalIndex.Nodes.href? ctx.state label
    metaHtml
  }

private def loadingBody (detail : String) : Output.Html :=
  open Verso.Output.Html in
  {{
    <div class="bp_relation_preview_message" "data-bp-preview-message"="loading">
      <div class="bp_relation_preview_message_title">"Loading preview"</div>
      <div class="bp_relation_preview_message_detail">{{.text true detail}}</div>
    </div>
  }}

private def renderPanel (cfg : Config) (entries : Array Entry) : Output.Html :=
  open Verso.Output.Html in
  let renderChip (chipClass : String) (chipTitle : String) (n : Nat) : Output.Html :=
    {{<span class={{chipClass}} title={{chipTitle}}>{{.text true (cfg.chipText n)}}</span>}}
  let renderEntriesPanel (entries : Array Entry) : Output.Html :=
    let renderRow (itemClass : String) (entry : Entry) : Output.Html :=
      let rowNode : Output.Html :=
        let titleNode := {{<span class="bp_relation_target_title">{{.text true entry.previewTitle}}</span>}}
        let metaNode := {{
          <span class="bp_relation_target_meta">
            {{entry.metaHtml}}
          </span>
        }}
        if let some href := entry.href then
          {{<a class="bp_relation_target" href={{href}}>{{titleNode}}{{metaNode}}</a>}}
        else
          {{<span class="bp_relation_target">{{titleNode}}{{metaNode}}</span>}}
      {{
        <li class={{itemClass}}
            "data-bp-relation-preview-id"={{entry.previewId}}
            "data-bp-relation-preview-key"={{entry.previewKey}}
            "data-bp-relation-preview-title"={{entry.previewTitle}}>
          {{rowNode}}
        </li>
      }}
    let (selectedEntry?, rows) :=
      entries.foldl (init := (none, #[])) fun (selectedEntry?, acc) entry =>
        match selectedEntry? with
        | none =>
          (some entry, acc.push (renderRow "bp_relation_item bp_relation_item_active" entry))
        | some selectedEntry =>
          (some selectedEntry, acc.push (renderRow "bp_relation_item" entry))
    let previewTitle :=
      match selectedEntry? with
      | some entry => entry.previewTitle
      | none => cfg.previewDefaultTitle
    let previewBody : Output.Html := loadingBody cfg.previewEmptyText
    {{
      <div class="bp_relation_wrap">
        <button type="button" class={{cfg.chipClass}} title={{cfg.chipTitle entries.size}} "aria-expanded"="false">
          {{.text true (cfg.chipText entries.size)}}
        </button>
        <div class="bp_relation_panel">
          <div class="bp_relation_panel_header">
            <div class="bp_relation_panel_title">{{.text true (cfg.panelTitle entries.size)}}</div>
            <div class={{cfg.panelMetaClass}}>{{.text true cfg.panelMeta}}</div>
          </div>
          <div class="bp_relation_panel_body">
            <ul class="bp_relation_list">
              {{rows}}
            </ul>
            <div class="bp_relation_preview_surface">
              <div class="bp_relation_preview_header">
                <div class="bp_relation_preview_label">"Preview"</div>
                <div class="bp_relation_preview_title">{{.text true previewTitle}}</div>
              </div>
              <div class="bp_relation_preview_body">
                {{previewBody}}
              </div>
            </div>
          </div>
        </div>
      </div>
    }}
  if entries.isEmpty then
    renderChip cfg.emptyChipClass (cfg.chipTitle 0) 0
  else if h : entries.size = 1 then
    if cfg.singleAsPanel then
      renderEntriesPanel entries
    else
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
        (previewFallbackLabel? := some s!"{entry.label}")
  else
    renderEntriesPanel entries

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
      mkBlockEntry ctx entry.source
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

/-- Render the forward-dependency header extra for a statement block. -/
def renderUsesExtra {m}
    [Monad m]
    (ctx : Context)
    (data : BlockData) :
    Verso.Doc.Html.HtmlT Verso.Genre.Manual m Output.Html := do
  match data.kind with
  | .proof => pure .empty
  | .statement _ =>
    let entries := collectUsesEntries ctx data
    let panelEntries ← entries.mapM fun entry => do
      let metaHtml := {{
        <code>s!"{entry.label}"</code>
        {{renderUseAxisBadges entry}}
        {{renderUseMetadataBadges entry}}
      }}
      match entry.target? with
      | some target =>
        mkBlockEntry ctx target
          (usesPreviewId data.label entry.label)
          (metaHtml := metaHtml)
      | none =>
        mkLabelEntry ctx entry.label
          (usesPreviewId data.label entry.label)
          (metaHtml := metaHtml)
    let cfg : Config := {
      chipText := usesChipText
      chipTitle := fun n =>
        if n == 0 then
          "No declared dependencies"
        else
          s!"Dependencies used by {data.label}"
      singleTitle := fun entry => s!"Dependency: {entry.previewTitle}"
      panelTitle := fun n => s!"Uses {n}"
      panelMeta := "Hover a dependency to preview it."
      previewDefaultTitle := "Hover a dependency"
      previewEmptyText := "Hover a dependency to preview it."
      chipClass := "bp_relation_chip bp_uses_chip"
      emptyChipClass := "bp_relation_chip bp_relation_chip_empty bp_uses_chip"
      singleAsPanel := true
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
      mkBlockEntry ctx source
        (groupPreviewId data.label source.label)
        (metaHtml := {{<code>s!"{source.label}"</code>}})
    let chipClass :=
      if group.declared then
        "bp_relation_chip"
      else
        "bp_relation_chip bp_relation_chip_warn"
    let emptyChipClass :=
      if group.declared then
        "bp_relation_chip bp_relation_chip_empty"
      else
        "bp_relation_chip bp_relation_chip_empty bp_relation_chip_warn"
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
      panelMetaClass := if group.declared then "bp_relation_panel_meta" else "bp_relation_panel_meta bp_relation_chip_warn"
      previewDefaultTitle := "Hover a group entry"
      previewEmptyText := "Hover a group entry to preview it."
      chipClass
      emptyChipClass
    }
    pure <| some (renderPanel cfg panelEntries)

end RelatedPanel
end Informal
