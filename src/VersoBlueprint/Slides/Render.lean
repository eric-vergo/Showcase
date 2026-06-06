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
import VersoBlueprint.Lib.HoverRender

namespace Informal.Slides

open Lean
open Verso.Output
open Verso.Output.Html

private def slideNodeMarkerAttr : String := "data-bp-blueprint-node"
private def slideNodeMarkerValue : String := "true"

private def blueprintSlideNodeMarkerAttrs : Array (String × String) :=
  #[(slideNodeMarkerAttr, slideNodeMarkerValue)]

public structure BlueprintSlideNode where
  label : String
  facet : String := "statement"
  key : String
  title? : Option String := none
  compact : Bool := false
  siteBase? : Option String := none
deriving Repr, BEq

private def attrValue? (attrs : Array (String × String)) (name : String) : Option String :=
  (attrs.find? fun attr => attr.1 == name).map (·.2)

private def BlueprintSlideNode.className (node : BlueprintSlideNode) : String :=
  if node.compact then
    "bp_slide_node bp_slide_node_compact"
  else
    "bp_slide_node"

def BlueprintSlideNode.toAttrs (node : BlueprintSlideNode) : Array (String × String) :=
  blueprintSlideNodeMarkerAttrs ++
    #[ ("class", node.className)
     , ("data-bp-label", node.label)
     , ("data-bp-facet", node.facet)
     , ("data-bp-preview-key", node.key)
     , ("data-bp-compact", if node.compact then "true" else "false")
     ] ++
    (node.title?.map (fun title => #[("data-bp-title", title)] ) |>.getD #[]) ++
    (node.siteBase?.map (fun siteBase => #[("data-bp-site-base", siteBase)] ) |>.getD #[])

def BlueprintSlideNode.fromAttrs? (attrs : Array (String × String)) : Option BlueprintSlideNode := do
  let marker ← attrValue? attrs slideNodeMarkerAttr
  guard (marker == slideNodeMarkerValue)
  let label ← attrValue? attrs "data-bp-label"
  let facet := attrValue? attrs "data-bp-facet" |>.getD "statement"
  let key := attrValue? attrs "data-bp-preview-key" |>.getD s!"{label}--{facet}"
  let title? := attrValue? attrs "data-bp-title"
  let compact := attrValue? attrs "data-bp-compact" == some "true"
  let siteBase? := attrValue? attrs "data-bp-site-base"
  some { label, facet, key, title?, compact, siteBase? }

def BlueprintSlideNode.renderedAttrs (node : BlueprintSlideNode) : Array (String × String) :=
  node.toAttrs ++ #[("data-bp-rendered", "static")]

def BlueprintSlideNode.fallbackText (node : BlueprintSlideNode) : String :=
  s!"Loading Blueprint node {node.label}..."

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

private def nameString (name : Name) : String :=
  name.toString

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
  let fallbackLabel := nameString entry.label
  let label := ((titleOverride? <|> entry.displayLabel).getD fallbackLabel).trimAscii.toString
  { caption, label }

private def codeEntries (ctx : RenderContext)
    (entry : Informal.PreviewManifest.Entry) : Array Informal.PreviewManifest.Entry :=
  ctx.index.codeEntries entry

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

private def renderGroupChip (entry : Informal.PreviewManifest.Entry) : Html :=
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
      s!"bp-slide-group-{nameString entry.label}"

private def renderCodeStatusChip (entry : Informal.PreviewManifest.Entry) (count : Nat) : Html :=
  let previewTitle := nameString entry.label
  Informal.CodeSummary.renderManifestCodeStatusChip
    count
    (Informal.HoverRender.previewId "bp-slide-code" previewTitle)
    previewTitle
    entry.leanCodePreviewKeys[0]?
    (previewRefClassExtra := "bp_slide_code_chip_preview")

private def renderUsesChip (entry : Informal.PreviewManifest.Entry) : Html :=
  if entry.uses.isEmpty then
    .empty
  else
    renderSlidePanel
      "uses"
      Informal.RelatedPanel.usesPanelConfig
      entry.uses
      Name.anonymous
      "bp-slide-uses"

private def renderUsedByChip (entry : Informal.PreviewManifest.Entry) : Html :=
  renderSlidePanel
    "used-by"
    (Informal.RelatedPanel.usedByPanelConfig)
    entry.usedBy
    Name.anonymous
    "bp-slide-used-by"

private def renderExtras (entry : Informal.PreviewManifest.Entry) (codeCount : Nat) : Html :=
  let group := renderGroupChip entry
  let uses := renderUsesChip entry
  let code := renderCodeStatusChip entry codeCount
  let usedBy := renderUsedByChip entry
  Informal.renderStatementHeaderExtras {
    group? := if group == .empty then none else some <| Informal.HeaderExtra.group group
    uses? := if uses == .empty then none else some <| Informal.HeaderExtra.uses uses
    code? := if code == .empty then none else some <| Informal.HeaderExtra.code code
    usedBy? := if usedBy == .empty then none else some <| Informal.HeaderExtra.usedBy usedBy
  }

private def renderCodePanel (entry : Informal.PreviewManifest.Entry)
    (codeEntries : Array Informal.PreviewManifest.Entry) (caption label : String) : Html :=
  if codeEntries.isEmpty then
    .empty
  else
    let codeHtml := codeEntries.map (fun codeEntry => trustedManifestHtml codeEntry.html)
    Informal.mkCodePanel
      { caption := s!"Lean code for {caption}", number? := some label }
      ("Lean code for " ++ nameString entry.label)
      (Informal.CodeSummary.renderCodeCountSummaryIndicator codeEntries.size)
      {{<div class="bp_slide_code_body">{{codeHtml}}</div>}}

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
  let codeEntries := if node.compact then #[] else codeEntries ctx entry
  let titleRow := Informal.renderBlockTitleRow style (nameString entry.label) title.label
    (if isProof then "Proof" else title.caption)
  let linkedTitleRow : Html :=
    match href with
    | some href =>
      .tag "a"
        #[ ("class", "bp_slide_node_heading_link")
         , ("data-bp-slide-link", "blueprint")
         , ("href", href)
         , ("target", "bp-slide-blueprint")
         , ("rel", "noopener")
         , ("title", "Open Blueprint node")
         ]
        titleRow
    | none => titleRow
  let heading : Html :=
    {{
      <div class={{"bp_heading bp_kind_" ++ style.kindCss ++ "_heading " ++ style.headingCss}}>
        {{linkedTitleRow}}
        {{ if isProof then .empty else renderExtras entry codeEntries.size }}
      </div>
    }}
  let wrapperClass := s!"bp_wrapper bp_kind_{style.kindCss}_wrapper {style.kindCss}_thmwrapper {style.wrapperCss}"
  let contentClass := s!"bp_content bp_kind_{style.kindCss}_content {style.contentCss}"
  {{
    <div class="bp_slide_node_blueprint">
      <div class={{wrapperClass}} title={{nameString entry.label}}>
        {{heading}}
        <div class={{contentClass}}>{{trustedManifestHtml entry.html}}</div>
      </div>
      {{renderCodePanel entry codeEntries title.caption title.label}}
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
