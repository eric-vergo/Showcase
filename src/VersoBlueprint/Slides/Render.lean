/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html
import VersoBlueprint.PreviewManifest
import VersoBlueprint.PreviewManifest.RelatedPanel
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.Informal.Block.Render
import VersoBlueprint.Informal.CodeSummary
import VersoBlueprint.Slides.Node

namespace Informal.Slides

open Lean
open Verso.Output
open Verso.Output.Html

public structure RenderContext where
  manifest? : Option Informal.PreviewManifest.File := none
  index : Informal.PreviewManifest.Index := {}

def RenderContext.ofManifest? (manifest? : Option Informal.PreviewManifest.File) : RenderContext :=
  { manifest? := manifest?, index := manifest?.map (·.index) |>.getD {} }

private def RenderContext.findEntry? (ctx : RenderContext) (key : String) :
    Option Informal.PreviewManifest.Entry :=
  ctx.index.findEntry? key

private def trustedManifestHtml (html : String) : Html :=
  .text false html

private structure SlideTitle where
  caption : String
  label : String

private def slideTitle (entry : Informal.PreviewManifest.Entry) (titleOverride? : Option String) :
    SlideTitle :=
  let kindText :=
    match entry.kind with
    | some kind => toString kind
    | none => "Blueprint"
  let caption := (entry.displayCaption.getD kindText).trimAscii.toString
  let fallbackLabel := entry.label.toString
  let label := ((titleOverride? <|> entry.displayLabel).getD fallbackLabel).trimAscii.toString
  { caption, label }

private def slidePanelConfig (kind : String)
    (cfg : Informal.RelatedPanel.PanelConfig) : Informal.RelatedPanel.PanelConfig :=
  { cfg with
    wrapClass := "bp_used_by_wrap bp_slide_" ++ kind ++ "_wrap"
    panelAttrs := #[("data-bp-slide-panel", kind)]
    singleMode := .panel
  }

private def renderSlidePanel (kind : String) (cfg : Informal.RelatedPanel.PanelConfig)
    (entries : Array Informal.PreviewManifest.RelatedEntry) (currentLabel : Name) (idPrefix : String)
    : Html :=
  let panelEntries := Informal.PreviewManifest.relatedPanelEntries entries currentLabel idPrefix
  Informal.RelatedPanel.renderPanel (slidePanelConfig kind cfg) panelEntries

private def renderExtras (entry : Informal.PreviewManifest.Entry)
    (codeEntries : Array Informal.PreviewManifest.Entry) (codeCount : Nat) :
    Informal.HeaderExtras :=
  let group : Html :=
    match entry.group with
    | none => .empty
    | some group =>
      if group.declared && group.entries.isEmpty then
        .empty
      else
        renderSlidePanel
          "group"
          (Informal.RelatedPanel.groupPanelConfig group.label group.title group.declared)
          group.entries
          entry.label
          s!"bp-slide-group-{entry.label}"
  let uses : Html :=
    if entry.uses.isEmpty then
      .empty
    else
      renderSlidePanel
        "uses"
        Informal.RelatedPanel.usesPanelConfig
        entry.uses
        Name.anonymous
        "bp-slide-uses"
  let previewTitle := entry.label.toString
  let codePreviewBody :=
    codeEntries.map (fun codeEntry => trustedManifestHtml codeEntry.html)
      |> Informal.CodeSummary.renderManifestCodePreviewBody
  let code : Html :=
    Informal.CodeSummary.renderManifestCodeStatusChip
      codeCount
      previewTitle
      codePreviewBody
  let usedBy :=
    renderSlidePanel
      "used-by"
      Informal.RelatedPanel.usedByPanelConfig
      entry.usedBy
      Name.anonymous
      "bp-slide-used-by"
  {
    group? := if group == .empty then none else some <| Informal.HeaderExtra.group group
    uses? := if uses == .empty then none else some <| Informal.HeaderExtra.uses uses
    code? := if code == .empty then none else some <| Informal.HeaderExtra.code code
    usedBy? := if usedBy == .empty then none else some <| Informal.HeaderExtra.usedBy usedBy
  }

private def renderNotice (kind title detail : String) : Html :=
  {{
    <div class={{"bp_slide_node_notice bp_slide_node_notice_" ++ kind}}>
      <strong>{{Html.ofString title}}</strong><br/>
      {{Html.ofString detail}}
    </div>
  }}

private def renderEntryShell (ctx : RenderContext)
    (entry : Informal.PreviewManifest.Entry) (node : BlueprintSlideNode) : Html :=
  let isProof := entry.facet == .proof
  let renderKind :=
    if isProof then
      Informal.Data.InProgressKind.proof
    else
      .statement (entry.kind.getD .theorem)
  let style := Informal.BlockKindRenderStyle.ofInProgressKind renderKind
  let title := slideTitle entry node.title?
  let href := entry.href
  let labelText := entry.label.toString
  let codeCount := if node.compact then 0 else ctx.index.codeEntryCount entry
  let codeEntries := if node.compact then #[] else ctx.index.codeEntries entry
  let codePanel : Html :=
    if codeEntries.isEmpty then
      .empty
    else
      let codeHtml := codeEntries.map (fun codeEntry => trustedManifestHtml codeEntry.html)
      Informal.CodeSummary.renderManifestCodePanel
        { caption := s!"Lean code for {title.caption}", number? := some title.label }
        ("Lean code for " ++ labelText)
        codeCount
        {{<div class="bp_slide_code_body">{{codeHtml}}</div>}}
  let titleRowAttrs? : Option (Array (String × String)) :=
    href.map fun href =>
      #[ ("class", "bp_slide_node_heading_link")
       , ("data-bp-slide-link", "blueprint")
       , ("href", href)
       , ("target", "bp-slide-blueprint")
       , ("rel", "noopener")
       , ("title", "Open Blueprint node")
       ]
  let blockShell :=
    Informal.renderInformalBlockShell
      {
        style
        labelText
        numberText := title.label
        captionText := if isProof then "Proof" else title.caption
        titleRowAttrs?
        headerExtras := if isProof then {} else renderExtras entry codeEntries codeCount
      }
      (trustedManifestHtml entry.html)
  {{
    <div class="bp_slide_node_blueprint">
      {{blockShell}}
      {{codePanel}}
    </div>
  }}

private def renderMissingNode (node : BlueprintSlideNode) (title detail : String) : Html :=
  .tag "div" node.renderedAttrs (renderNotice "error" title detail)

public def renderBlueprintSlideNode (ctx : RenderContext) (node : BlueprintSlideNode) : Html :=
  match ctx.manifest? with
  | none =>
    renderMissingNode node "Preview manifest unavailable"
      "Pass previewManifest? to slidesMainWithBlueprintPreviews so Blueprint slide nodes can be rendered during slide generation."
  | some _manifest =>
    match ctx.findEntry? node.key with
    | none =>
      renderMissingNode node "Blueprint node not found" node.key
    | some entry =>
      .tag "div" node.renderedAttrs (renderEntryShell ctx entry node)

/--
Render a Blueprint slide node from the structured attributes carried by the
`VersoSlides.BlockExt.wrap` emitted by `blueprint_node`.
-/
public def renderBlueprintSlideNodeFromAttrs?
    (ctx : RenderContext)
    (attrs : Array (String × String)) : Option Html := do
  let node ← BlueprintSlideNode.fromAttrs? attrs
  some (renderBlueprintSlideNode ctx node)

def readBlueprintPreviewManifest (path : System.FilePath) :
    IO Informal.PreviewManifest.File :=
  Informal.PreviewManifest.readFile path

end Informal.Slides
