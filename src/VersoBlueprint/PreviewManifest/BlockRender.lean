/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Emilio J. Gallego Arias, Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
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
  /-- Configured project prefix (`verso.blueprint.declNamePrefix`, read from the
  traversal store by the calling surface) used to derive the card meta payload's
  `shortName`; empty ⇒ no shortening (byte-identical legacy output). -/
  declNamePrefix : String := ""

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

/-- Heading status dot (1D) for a manifest entry: statement entries derive it
from their code source (`informal` when there is none); proof entries carry no
dot. -/
private def statusDotOfEntry (entry : Entry) : Html :=
  match entry.blockKind with
  | .statement kind => Informal.CodeSummary.statusDotHtml entry.codeData (kind? := some kind)
  | .proof => .empty

private def renderCodePanel
    (cfg : RenderConfig)
    (title : EntryHeading)
    (entry : Entry)
    (codeBodies : Array Html)
    (namePrefix : String := "") :
    Html :=
  if codeBodies.isEmpty then
    .empty
  else
    let summaryTitle := Informal.CodeSummary.panelSummaryTitle
      entry.label
      { source := entry.codeData }
      namePrefix
    let codeHtml := .seq codeBodies
    let body := Html.tag "div" (Informal.htmlClassAttrs cfg.codeBodyClass) codeHtml
    Informal.mkCodePanel
      { caption := s!"Lean code for {title.caption}", number? := some title.label }
      summaryTitle
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
        renderCodePanel cfg title entry content.codeBodies opts.declNamePrefix
    Informal.renderInformalBlockModel {
      data := blockData
      context := Informal.InformalBlockRenderContext.forBlock blockData
        title.label
        (statementCaption? := some title.caption)
        (proofCaption? := some entry.title)
        (titleRowAttrs? := cfg.titleRowAttrs? entry)
        (statusDot := statusDotOfEntry entry)
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
      (statusDot := statusDotOfEntry entry))
    #[content.body]

/-- Card id stem derived from a manifest entry label. -/
private def cardIdOf (entry : Entry) : String :=
  s!"bp-card-{entry.label}"

/--
Captured formal body HTML for a two-column node card: the proof body for
theorem-like nodes or the `:= value` body for definitions.

Renders the captured proof/value source of the statement's associated Lean
declaration(s) (`Data.ExternalRef.proofSource?`, snapshotted from the source file
in `ExternalRefSnapshot`) as a Lean code block, so the body shows server-side for
both tactic-mode (`:= by …`) and term-mode (`:= term`) declarations. `render`
routes this into the formal proof cell (theorems) or under the signature
(definitions).

Empty when the statement has no external declaration or no captured source:
inline-authored theorems keep `formalStmt`'s single signature+tactic block and
rely on the runtime tactic-tail relocation (`Commands/proof-toggle.mjs`).
-/
private def formalBodyFromEntry (entry : Entry) : Html :=
  match entry.codeData with
  | some (.external refs) =>
    -- Prefer the syntactically-highlighted token markup; fall back to escaped raw
    -- source when highlighting was unavailable. Shared markup via `NodeCard`.
    -- Definitions restore a leading `:=` so the value reads under the signature.
    let isDefinition := !(entry.kind.getD .theorem).isTheoremLike
    Informal.NodeCard.formalSourceBody
      (refs.filterMap fun ref =>
        if ref.present then some (ref.proofHtml?, ref.proofSource?, ref.proofTier?) else none)
      (assignPrefix := isDefinition)
  | _ => .empty

/-- Registry-aligned status tag for one external reference's snapshot status. -/
private def provedStatusTag : Informal.Data.ProvedStatus → String
  | .proved => "proved"
  | .missing => "missing"
  | .axiomLike => "axiomLike"
  | .containsSorry _ => "containsSorry"

/--
Primary declaration name + slim identity metadata JSON for one statement entry's
node card, sourced from the entry's `(lean := …)` external reference(s).

Returns `(declName?, declMetaJson?)` for `NodeCard.Parts`: the canonical name of
the first present (else first) external decl, and the injection-safe identity
payload the metadata rail first-paints from offline. `(none, none)` for no-Lean
nodes (nothing to select). The heavier params / uses / used-by data comes from the
declaration registry at selection time. `namePrefix` (when configured) adds the
prefix-stripped `shortName` key — emitted only when it actually shortens, keeping
legacy output byte-identical.
-/
private def declMetaOfEntry (entry : Entry) (namePrefix : String) :
    Option String × Option String :=
  match entry.codeData with
  | some codeData =>
    let refs := codeData.externalDecls
    match refs.find? (·.present) <|> refs[0]? with
    | some primaryRef =>
      let name := primaryRef.canonical.toString
      let moduleName := (primaryRef.provenance.moduleName?.map (·.toString)).getD ""
      let startLine := primaryRef.range?.map (·.pos.line)
      let endLine := primaryRef.range?.map (·.endPos.line)
      let kind := toString (entry.kind.getD .theorem)
      let nodeHref := s!"node/{Informal.NodeRoute.nodePageSlug entry.label}/"
      let short := Informal.NodeCard.shortDeclName namePrefix name
      let shortName? := if short == name then none else some short
      let json := Informal.NodeCard.declMetaJson name kind (provedStatusTag primaryRef.provedStatus)
        moduleName entry.title startLine endLine (some nodeHref) (shortName := shortName?)
      (some name, some json)
    | none => (none, none)
  | none => (none, none)

/--
Build the two-column node card parts for one statement entry, optionally folding
in a resolved proof facet.

This is additive: it reuses `renderShellParts`, `entry.heading`, and
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
  let formalStmt := renderCodePanel cfg title entry content.codeBodies opts.declNamePrefix
  let isTheoremLike := (entry.kind.getD .theorem).isTheoremLike
  -- The informal proof cell carries the proof prose only — the old "USES n" chip
  -- is gone (the metadata rail's Uses section owns dependency information).
  let proofParts? : Option Informal.NodeCard.ProofParts :=
    proof?.map fun (pEntry, pContent) =>
      let pShell := renderShellParts cfg pEntry pContent
      {
        informalProof := pShell.contentInner
        cardId := cardIdOf entry
      }
  let (declName?, declMetaJson?) := declMetaOfEntry entry opts.declNamePrefix
  {
    cardId := cardIdOf entry
    isTheoremLike
    declName?
    declMetaJson?
    header := stmtParts.header
    informalStmt := stmtParts.contentInner
    formalStmt
    -- The captured proof/value source of the statement's associated Lean
    -- declaration (external `(lean := …)` refs). `render` routes it into the
    -- formal proof cell (theorems) or under the signature (definitions). Empty
    -- for inline-authored theorems (runtime tactic-tail relocation) and no-Lean
    -- nodes. See `formalBodyFromEntry`.
    formalBody := formalBodyFromEntry entry
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
