/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html
import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.Informal.Block.Render
import VersoBlueprint.Informal.CodeSummary
import VersoBlueprint.NodeCard
import VersoBlueprint.PreviewManifest
import VersoBlueprint.PreviewManifest.RelatedPanel

namespace Informal.PreviewManifest.BlockRender

open Lean
open Verso.Output
open Verso.Output.Html

/-- Re-inject already-rendered HTML fragments as HTML, not escaped text. -/
def htmlFragment (html : String) : Html :=
  .text false html

/-- Related-entry panel positions available in a preview-data-backed block header. -/
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

/-- Genre-specific presentation for preview-data-backed related-entry panels. -/
structure RelationPanelsConfig where
  wrapClass : RelationPanelKind → String :=
    fun kind => s!"bp_relation_wrap bp_preview_data_{kind.key}_wrap"
  panelAttrs : RelationPanelKind → Array (String × String) := fun _ => #[]
  singleMode : RelationPanelKind → Informal.RelatedPanel.PanelSingleMode := fun _ => .panel
  idPrefix : RelationPanelKind → Entry → String :=
    fun kind entry => s!"bp-preview-data-{kind.key}-{entry.label}"

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

/-- Genre-specific presentation knobs for rendering a preview-data-backed Blueprint block. -/
structure RenderConfig where
  wrapperClass : String := "bp_preview_data_node_blueprint"
  codeBodyClass : String := "bp_preview_data_code_body"
  titleRowAttrs? :
    Entry → Option (Array (String × String)) := fun _ => none
  relationPanels : RelationPanelsConfig := {}

/-- Per-node render options for a preview-data-backed Blueprint block. -/
structure RenderOptions where
  displayLabelOverride? : Option String := none
  compact : Bool := false
  showHeader : Bool := true

/--
Rendered content for a Blueprint block shell.

The shell renderer intentionally receives already-rendered HTML here: file-mode
consumers can populate it from a rendered-preview cache, while same-toolchain
consumers can first render stored Manual blocks through the regular Manual/VBP
path and then pass the result through this same assembly path.
-/
structure RenderedContent where
  body : Html
  codeBodies : Array Html := #[]

def RenderedContent.ofHtmlStrings (bodyHtml : String) (codeHtml : Array String := #[]) :
    RenderedContent :=
  {
    body := htmlFragment bodyHtml
    codeBodies := codeHtml.map htmlFragment
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

/--
Render a preview-manifest relation panel as a header extra.

Most relation kinds disappear when they have no entries; undeclared groups are
the exception, because their empty warning chip is the whole signal.
-/
private def renderRelatedPanelExtra?
    (cfg : RelationPanelsConfig)
    (kind : RelationPanelKind)
    (panelCfg : Informal.RelatedPanel.PanelConfig)
    (entries : Array RelatedEntry)
    (entry : Entry)
    (currentLabel : Name)
    (toExtra : Html → Informal.HeaderExtra)
    (showWhenEmpty : Bool := false) :
    Option Informal.HeaderExtra :=
  if entries.isEmpty && !showWhenEmpty then
    none
  else
    some <| toExtra <|
      renderRelatedPanel cfg kind panelCfg entries entry currentLabel

private def renderGroupExtra?
    (cfg : RelationPanelsConfig)
    (entry : Entry) :
    Option Informal.HeaderExtra :=
  match entry.group with
  | none => none
  | some group =>
    renderRelatedPanelExtra?
      cfg
      .group
      (Informal.RelatedPanel.groupPanelConfig group.label group.title group.declared)
      group.entries
      entry
      entry.label
      Informal.HeaderExtra.group
      (showWhenEmpty := !group.declared)

/-- Select the uses-panel wording from the manifest entry facet. -/
private def usesPanelConfigForEntry (entry : Entry) : Informal.RelatedPanel.PanelConfig :=
  match entry.blockKind with
  | .proof => Informal.RelatedPanel.proofUsesPanelConfig entry.label
  | .statement _ => Informal.RelatedPanel.statementUsesPanelConfig entry.label

private def renderUsesExtra?
    (cfg : RelationPanelsConfig)
    (entry : Entry) :
    Option Informal.HeaderExtra :=
  renderRelatedPanelExtra?
    cfg
    .uses
    (usesPanelConfigForEntry entry)
    entry.uses
    entry
    Name.anonymous
    Informal.HeaderExtra.uses

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
  renderRelatedPanelExtra?
    cfg
    .usedBy
    Informal.RelatedPanel.usedByPanelConfig
    entry.usedBy
    entry
    Name.anonymous
    Informal.HeaderExtra.usedBy

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

private def renderCodePanel
    (cfg : RenderConfig)
    (title : EntryHeading)
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
    let body := Html.tag "div" (Informal.htmlClassAttrs cfg.codeBodyClass) codeHtml
    Informal.mkCodePanel
      { caption := s!"Lean code for {title.caption}", number? := some title.label }
      panelSummary.summaryTitle
      panelSummary.indicator
      body

/-- Render a Blueprint block shell from semantic entry data and rendered content. -/
def renderWithRenderedContent
    (cfg : RenderConfig)
    (entry : Entry)
    (content : RenderedContent)
    (opts : RenderOptions := {}) :
    Html :=
    let blockData := entry.blockData
    let title := entry.heading opts.displayLabelOverride?
    let codePanel :=
      if opts.compact then
        .empty
      else
        renderCodePanel cfg title entry content.codeBodies
    Informal.renderInformalBlockModel {
      data := blockData
      context := Informal.InformalBlockRenderContext.forBlock blockData
        title.label
        (statementCaption? := some title.caption)
        (proofCaption? := some entry.title)
        (titleRowAttrs? := cfg.titleRowAttrs? entry)
        (headerExtras := renderHeaderExtras cfg.relationPanels entry blockData)
      content := #[content.body]
      companionPanels := #[codePanel]
      wrapperClass? := some cfg.wrapperClass
      showHeader := opts.showHeader
    }

/--
Build the heading band and prose body for one Blueprint entry as separate pieces.

This reuses the shared informal-block shell so the card heading matches the
single-column heading exactly: the returned `header` is the heading band and
`contentInner` is the `bp_content` body.
-/
private def renderShellParts
    (cfg : RenderConfig)
    (entry : Entry)
    (content : RenderedContent)
    (displayLabelOverride? : Option String := none) :
    Informal.InformalBlockShellParts :=
  let blockData := entry.blockData
  let title := entry.heading displayLabelOverride?
  Informal.renderInformalBlockHtmlParts
    blockData
    (Informal.InformalBlockRenderContext.forBlock blockData
      title.label
      (statementCaption? := some title.caption)
      (proofCaption? := some entry.title)
      (titleRowAttrs? := cfg.titleRowAttrs? entry)
      (headerExtras := renderHeaderExtras cfg.relationPanels entry blockData))
    #[content.body]

/-- Card id stem derived from a manifest entry label. -/
private def cardIdOf (entry : Entry) : String :=
  s!"bp-card-{entry.label}"

/--
Build the two-column node card parts for one statement entry, optionally folding
in a resolved proof facet.

This is additive: it reuses `renderHeaderExtras`, `entry.heading`, and
`renderCodePanel` (an empty `codeBodies` yields a blank right cell). The
single-column compositor `renderWithRenderedContent` is untouched.
-/
def renderCardParts
    (cfg : RenderConfig)
    (entry : Entry)
    (content : RenderedContent)
    (proof? : Option (Entry × RenderedContent))
    (opts : RenderOptions := {}) :
    Informal.NodeCard.Parts :=
  -- The graft `displayLabel := "Step"` override (and any other embedding surface
  -- that relabels a node) flows through `opts.displayLabelOverride?` onto the
  -- statement card's heading and Lean-panel caption, mirroring how
  -- `renderWithRenderedContent` applies it. The folded proof facet keeps its own
  -- label.
  let title := entry.heading opts.displayLabelOverride?
  let stmtParts := renderShellParts cfg entry content opts.displayLabelOverride?
  let formalStmt := renderCodePanel cfg title entry content.codeBodies
  let proofParts? : Option Informal.NodeCard.ProofParts :=
    proof?.map fun (pEntry, pContent) =>
      let pShell := renderShellParts cfg pEntry pContent
      let proofUses :=
        match renderUsesExtra? cfg.relationPanels pEntry with
        | some extra => extra.html
        | none => .empty
      {
        informalProof := pShell.contentInner
        -- The statement's single code block (signature in the top cell + the
        -- JS-relocated tactic tail in the proof cell) already covers the Lean
        -- proof, so the proof facet's own code panel is always either empty
        -- (external decls) or a duplicate of the statement's code (inline-authored
        -- theorems). Mirror the already-correct inline path (`Informal/Block.lean`)
        -- and never render it as a separate panel.
        formalProof := .empty
        proofUses
        cardId := cardIdOf entry
      }
  {
    cardId := cardIdOf entry
    header := stmtParts.header
    informalStmt := stmtParts.contentInner
    formalStmt
    proof? := proofParts?
  }

/--
Convenience compositor: render a statement entry directly to a two-column node
card. Thin wrapper over `renderCardParts` + `NodeCard.render`; no surface calls
it yet (the surfaces are wired in a later wave).
-/
def renderTwoColumnCard
    (cfg : RenderConfig)
    (entry : Entry)
    (content : RenderedContent)
    (proof? : Option (Entry × RenderedContent))
    (opts : RenderOptions := {})
    (cardOpts : Informal.NodeCard.Options := {}) :
    Html :=
  Informal.NodeCard.render (renderCardParts cfg entry content proof? opts) cardOpts

end Informal.PreviewManifest.BlockRender
