/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html
import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.Informal.Block.Render
import VersoBlueprint.Informal.CodeSummary
import VersoBlueprint.PreviewManifest
import VersoBlueprint.PreviewManifest.RelatedPanel

namespace Informal.PreviewManifest.BlockRender

open Lean
open Verso.Output
open Verso.Output.Html

/--
Manifest entries store HTML that was already rendered by Verso during
generation. Re-inject it as HTML, not escaped text, when another genre consumes
the manifest.
-/
def htmlFragment (html : String) : Html :=
  .text false html

/-- Related-entry panel positions available in a manifest-backed block header. -/
inductive RelationPanelKind where
  | group
  | uses
  | usedBy
deriving Repr, Inhabited, BEq

namespace RelationPanelKind

def key : RelationPanelKind → String
  | .group => "group"
  | .uses => "uses"
  | .usedBy => "used-by"

end RelationPanelKind

/-- Genre-specific presentation for manifest-backed related-entry panels. -/
structure RelationPanelsConfig where
  wrapClass : RelationPanelKind → String :=
    fun kind => s!"bp_used_by_wrap bp_manifest_{kind.key}_wrap"
  panelAttrs : RelationPanelKind → Array (String × String) := fun _ => #[]
  singleMode : RelationPanelKind → Informal.RelatedPanel.PanelSingleMode := fun _ => .panel
  idPrefix : RelationPanelKind → Entry → String :=
    fun kind entry => s!"bp-manifest-{kind.key}-{entry.label}"

private def RelationPanelsConfig.apply
    (cfg : RelationPanelsConfig)
    (kind : RelationPanelKind)
    (panelCfg : Informal.RelatedPanel.PanelConfig) :
    Informal.RelatedPanel.PanelConfig :=
  { panelCfg with
    wrapClass := cfg.wrapClass kind
    panelAttrs := cfg.panelAttrs kind
    singleMode := cfg.singleMode kind
  }

/-- Genre-specific presentation knobs for rendering a manifest-backed Blueprint block. -/
structure RenderConfig where
  wrapperClass : String := "bp_manifest_node_blueprint"
  codeBodyClass : String := "bp_manifest_code_body"
  titleRowAttrs? :
    Entry → Option (Array (String × String)) := fun _ => none
  relationPanels : RelationPanelsConfig := {}

/-- Per-node render options for a manifest-backed Blueprint block. -/
structure RenderOptions where
  titleOverride? : Option String := none
  compact : Bool := false

private structure EntryTitle where
  caption : String
  label : String

private def entryTitle
    (entry : Entry)
    (titleOverride? : Option String) :
    EntryTitle :=
  let kindText :=
    match entry.kind with
    | some kind => toString kind
    | none => "Blueprint"
  let caption := (entry.displayCaption.getD kindText).trimAscii.toString
  let fallbackLabel := entry.label.toString
  let label := ((titleOverride? <|> entry.displayLabel).getD fallbackLabel).trimAscii.toString
  { caption, label }

private def entryBlockKind (entry : Entry) : Informal.Data.InProgressKind :=
  if entry.facet == .proof then
    .proof
  else
    .statement (entry.kind.getD .theorem)

private def entryBlockData (entry : Entry) : Informal.BlockData :=
  {
    kind := entryBlockKind entry
    codeData := entry.codeData
    label := entry.label
    parent := entry.parent
    count := 0
    statementDeps := entry.statementDeps
    proofDeps := entry.proofDeps
    ownerDisplayName := entry.ownerDisplayName
    tags := entry.tags
    effort := entry.effort
    priority := entry.priority
  }

private def renderRelatedPanel
    (cfg : RelationPanelsConfig)
    (kind : RelationPanelKind)
    (panelCfg : Informal.RelatedPanel.PanelConfig)
    (entries : Array RelatedEntry)
    (entry : Entry)
    (currentLabel : Name) :
    Html :=
  let panelEntries :=
    Informal.PreviewManifest.relatedPanelEntries entries currentLabel (cfg.idPrefix kind entry)
  Informal.RelatedPanel.renderPanel (cfg.apply kind panelCfg) panelEntries

private def renderGroupExtra?
    (cfg : RelationPanelsConfig)
    (entry : Entry) :
    Option Informal.HeaderExtra :=
  match entry.group with
  | none => none
  | some group =>
      if group.declared && group.entries.isEmpty then
        none
      else
        some <| Informal.HeaderExtra.group <|
          renderRelatedPanel
            cfg
            .group
            (Informal.RelatedPanel.groupPanelConfig group.label group.title group.declared)
            group.entries
            entry
            entry.label

private def renderUsesExtra?
    (cfg : RelationPanelsConfig)
    (entry : Entry) :
    Option Informal.HeaderExtra :=
  if entry.uses.isEmpty then
    none
  else
    some <| Informal.HeaderExtra.uses <|
      renderRelatedPanel
        cfg
        .uses
        Informal.RelatedPanel.usesPanelConfig
        entry.uses
        entry
        Name.anonymous

private def renderCodeExtra? (entry : Entry) (blockData : Informal.BlockData) :
    Option Informal.HeaderExtra :=
  entry.codeData.map fun codeData =>
    let parts := Informal.CodeSummary.renderParts
      blockData
      { source := some codeData }
      (fun _ => none)
    Informal.HeaderExtra.code parts.codeEntry

private def renderUsedByExtra?
    (cfg : RelationPanelsConfig)
    (entry : Entry) :
    Option Informal.HeaderExtra :=
  if entry.usedBy.isEmpty then
    none
  else
    some <| Informal.HeaderExtra.usedBy <|
      renderRelatedPanel
        cfg
        .usedBy
        Informal.RelatedPanel.usedByPanelConfig
        entry.usedBy
        entry
        Name.anonymous

private def renderHeaderExtras
    (cfg : RelationPanelsConfig)
    (entry : Entry)
    (blockData : Informal.BlockData) :
    Informal.HeaderExtras :=
  {
    group? := renderGroupExtra? cfg entry
    uses? := renderUsesExtra? cfg entry
    code? := renderCodeExtra? entry blockData
    usedBy? := renderUsedByExtra? cfg entry
  }

private def attrsForClass (className : String) : Array (String × String) :=
  if className.isEmpty then #[] else #[("class", className)]

private def renderCodePanel
    (cfg : RenderConfig)
    (title : EntryTitle)
    (entry : Entry)
    (codeBodies : Array Html) :
    Html :=
  if codeBodies.isEmpty then
    .empty
  else
    let panelSummary := Informal.CodeSummary.renderPanelIndicator
      entry.label
      { source := entry.codeData }
      (fun _ => none)
    let codeHtml := .seq codeBodies
    let body := Html.tag "div" (attrsForClass cfg.codeBodyClass) codeHtml
    Informal.mkCodePanel
      { caption := s!"Lean code for {title.caption}", number? := some title.label }
      panelSummary.summaryTitle
      panelSummary.indicator
      body

/--
Render a Blueprint block from a preview-manifest entry using the shared block
shell. Consumers supply only genre-specific wrappers and per-node options.
-/
def renderWithContent
    (cfg : RenderConfig)
    (entry : Entry)
    (opts : RenderOptions := {}) :
    Html → Array Html → Html :=
  fun bodyHtml codeBodies =>
    let blockData := entryBlockData entry
    let title := entryTitle entry opts.titleOverride?
    let blockShell :=
      Informal.renderInformalBlockHtml
        blockData
        {
          numberText := title.label
          captionText? :=
            match blockData.kind with
            | .proof => some entry.title
            | .statement _ => some title.caption
          titleRowAttrs? := cfg.titleRowAttrs? entry
          headerExtras :=
            match blockData.kind with
            | .proof => {}
            | .statement _ =>
              renderHeaderExtras cfg.relationPanels entry blockData
        }
        #[bodyHtml]
    let codePanel :=
      if opts.compact then
        .empty
      else
        renderCodePanel cfg title entry codeBodies
    Html.tag "div" (attrsForClass cfg.wrapperClass) (.seq #[blockShell, codePanel])

def render
    (index : Index)
    (cfg : RenderConfig)
    (entry : Entry)
    (opts : RenderOptions := {}) :
    Html :=
  let codeEntries := if opts.compact then #[] else index.codeEntries entry
  renderWithContent cfg entry opts
    (htmlFragment entry.html)
    (codeEntries.map (fun codeEntry => htmlFragment codeEntry.html))

end Informal.PreviewManifest.BlockRender
