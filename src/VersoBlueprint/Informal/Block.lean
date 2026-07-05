/-
Copyright (c) 2025 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias, David Thrane Christiansen
-/

-- XXX VersoManual is not module yet
-- module

-- Blueprint library extending the Verso `Manual` genre.

import Lean.Elab.InfoTree.Types

import VersoManual

import VersoBlueprint.Commands.Common
import VersoBlueprint.Data
import VersoBlueprint.Environment
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Informal.Block.Config
import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.Informal.Block.Render
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.Block.Traversal
import VersoBlueprint.Informal.CodeSummary
import VersoBlueprint.Informal.ExternalCode
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.NodeCard
import VersoBlueprint.NodeRoute
import VersoBlueprint.PreviewRender
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex
import VersoBlueprint.Profiling

set_option doc.verso true

open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse
open Verso.Output.Html
open Lean.Doc.Syntax
open Lean Elab

namespace Informal
open CodeSummary

/- "Informal" Verso objects:

  - An informal verso object is identified by a label, and lives in the `informal` Verso domain.
  - For IO (Informal Object), we associate a `Data` entry, which mainly captures other objects the IO depends on
  - Objects are declared via directives / code blocks
  - Dependencies are declared via the {uses ...}`...` role, which _must_ be inside a directive.

Elaboration, traversal, and rendering are standard, using {ref VersoManual} helpers for custom blocks and inlines.

-/

/- Informal custom blocks -/
block_extension Block.informal (data : BlockData) where
  -- for TOC
  -- localContentItem _ _ _ := none
  data := toJson data
  traverse id data _contents := do
    -- XXX: (maybe) lift the Except into the main monad error thread
    match ← ExtensionDecode.decode? (α := BlockData) data
        (fun err => s!"Malformed data ({err}): {data}") with
    | none =>
      pure none
    | some blockData =>
      let blockData := blockData.withTraversalNumberingContext (← read)
      registerTraversedBlockAssets id blockData _contents
      saveTraversedBlockData id blockData
      return none
  toTeX := none
  extraCss := Informal.Block.Assets.blockCssAssets
  extraJs := Informal.Block.Assets.blockJsAssets
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI goB id data blocks => do
      match ← ExtensionDecode.decode? (α := BlockData) data
          (fun err => s!"Malformed data ({err}): {data}") with
      | none =>
        pure .empty
      | some data =>
        let s ← HtmlT.state
        let ctxt ← HtmlT.context
        let data := data.withResolvedNumberingInContext s ctxt
        let attrs := s.htmlId id
        let codeData? : Option InlineCodeData ←
          pure <| Informal.TraversalIndex.InlineCode.data? s data.label
        let codeHint? :=
          match data.kind with
          | .proof => none
          | .statement _ => data.codeData
        let codeSource := BlockCodeData.ofHintAndInline codeHint? codeData?
        let externalDecls := codeHint?.map (·.externalDecls) |>.getD #[]
        let getDeclHref (decl : Name) : Option String :=
          Resolve.resolveInformalDeclHref? s data.label decl
        let getDeclAnchorAttrs (decl : Data.ExternalRef) : Array (String × String) :=
          Informal.TraversalIndex.ExternalDeclAnchors.htmlIdAttrs s data.label decl.canonical
        let externalParts? : Option ExternalCode.RenderParts ←
          match data.kind with
          | .statement _ =>
            if externalDecls.isEmpty then
              pure none
            else
              let externalCdata : CodeSummary.ComputedData := {
                source := some (.external externalDecls)
              }
              let externalSummaryTitle := CodeSummary.panelSummaryTitle data.label externalCdata
              let panelHeader := codePanelHeader data (data.displayIdentifier s)
              some <$> ExternalCode.renderPartsWithPageHovers
                panelHeader
                externalSummaryTitle
                externalDecls
                getDeclHref
                getDeclAnchorAttrs
                (folded := data.foldCodeBlock)
                -- Card surface (1F): suppress the per-decl name+status head row and
                -- footer status pill; the code reads bare and the rail owns identity.
                (includeStatusRows := false)
          | .proof => pure none
        let externalPanel := (externalParts?.map (·.externalCodePanel)).getD .empty
        let content := (← blocks.mapM goB)
        let foldInformalBlock :=
          match data.kind with
          | .proof => data.foldProofBlock
          | .statement _ => false
        -- Header chips (group / uses / used-by / L∃∀N) are gone (1D): the
        -- metadata rail owns that information now. The heading carries only the
        -- title row plus the status dot.
        let statusDot :=
          match data.kind with
          | .statement kind => CodeSummary.statusDotHtml codeSource (kind? := some kind)
          | .proof => Verso.Output.Html.empty
        match data.kind with
        | .statement _ =>
          -- Default the inline statement to the two-column node card: informal
          -- prose left, the statement's Lean code panel right, and the proof
          -- facet folded in (resolved from the traversal preview cache). The
          -- standalone `:::proof` card is suppressed below to avoid a double
          -- render of the proof prose.
          let stmtParts := renderInformalBlockHtmlParts data
            (InformalBlockRenderContext.forBlock data
              (data.displayIdentifier s)
              (proofCaption? := some (data.displayTitle s))
              (attrs := attrs)
              (statusDot := statusDot))
            content
          -- Bare card (1F): the informal statement cell carries the prose only —
          -- owner/tags/priority/effort/PR live in the properties rail now, not on
          -- the card, so the old `stmtParts.metadata` panel is dropped here.
          let informalStmt := stmtParts.contentInner
          -- Fold the proof facet's prose (if it exists) into the proof region.
          -- The informal proof cell carries the prose only — the old "USES n"
          -- chip is gone (the metadata rail's Uses section owns that data).
          let proofKey := Informal.PreviewCache.proofKey data.label
          let proof? : Option NodeCard.ProofParts ←
            match Informal.TraversalIndex.TraversalPreviews.entry? s proofKey with
            | none => pure none
            | some pEntry =>
              let informalProof := Verso.Output.Html.seq (← pEntry.blocks.mapM goB)
              pure <| some {
                informalProof
                cardId := s!"bp-card-{data.label}"
              }
          let isTheoremLike :=
            match data.kind with
            | .statement k => k.isTheoremLike
            | .proof => true
          -- Captured proof/value source of the statement's external `(lean := …)`
          -- refs (snapshotted in `ExternalRefSnapshot`). `render` routes it into
          -- the formal proof cell (theorems) or under the signature (definitions);
          -- empty for inline-authored theorems (runtime tactic-tail relocation).
          -- Definitions restore a leading `:=` so the value reads under the
          -- signature; theorem proof bodies keep the default (no prefix).
          let formalBody := NodeCard.formalSourceBody
            (externalDecls.filterMap fun ref =>
              if ref.present then some (ref.proofHtml?, ref.proofSource?) else none)
            (assignPrefix := !isTheoremLike)
          -- Primary decl name + slim identity metadata for the selection bus /
          -- metadata rail (matches the manifest card path in `BlockRender`): the
          -- first present (else first) `(lean := …)` ref, identity fields only.
          -- The short-name prefix comes from the traversal store (stashed by the
          -- graph block's traverse from `verso.blueprint.declNamePrefix`); the
          -- `shortName` key is emitted only when it actually shortens.
          let namePrefix := (Informal.TraversalIndex.DeclRegistry.namePrefix? s).getD ""
          let (cardDeclName?, cardDeclMetaJson?) :=
            match externalDecls.find? (·.present) <|> externalDecls[0]? with
            | some primaryRef =>
              let name := primaryRef.canonical.toString
              let moduleName := (primaryRef.provenance.moduleName?.map (·.toString)).getD ""
              let statusTag := match primaryRef.provedStatus with
                | .proved => "proved"
                | .missing => "missing"
                | .axiomLike => "axiomLike"
                | .containsSorry _ => "containsSorry"
              let kindStr := match data.kind with
                | .statement k => toString k
                | .proof => "theorem"
              let nodeHref := s!"node/{Informal.NodeRoute.nodePageSlugOfString (toString data.label)}/"
              let short := NodeCard.shortDeclName namePrefix name
              let shortName? := if short == name then none else some short
              (some name,
               some (NodeCard.declMetaJson name kindStr statusTag moduleName (data.displayTitle s)
                 (primaryRef.range?.map (·.pos.line)) (primaryRef.range?.map (·.endPos.line))
                 (some nodeHref) (shortName := shortName?)))
            | none => (none, none)
          let card := NodeCard.render {
            cardId := s!"bp-card-{data.label}"
            isTheoremLike
            declName? := cardDeclName?
            declMetaJson? := cardDeclMetaJson?
            header := stmtParts.header
            informalStmt
            formalStmt := externalPanel
            formalBody
            proof?
          } { showHeader := true }
          -- Preserve the block's anchor `id` (carried in `attrs`) so in-chapter
          -- links still resolve: the single-column shell put it on the wrapper,
          -- but the card builds its own wrapper, so wrap it in an id-bearing div.
          return Verso.Output.Html.tag "div"
            (#[("class", "bp_card2_anchor")] ++ attrs) card
        | .proof =>
          -- When a statement facet exists for this label, the proof prose has
          -- already been folded into the statement card above; suppress the
          -- standalone proof card so the proof renders exactly once. Orphan
          -- proofs (no statement facet) still render standalone as before.
          match resolveStoredNodeData? s data.label with
          | some stored =>
            match stored.kind with
            | .statement _ => return .empty
            | .proof =>
              return renderInformalBlockModel {
                data
                context := InformalBlockRenderContext.forBlock data
                  (data.displayIdentifier s)
                  (proofCaption? := some (data.displayTitle s))
                  (attrs := attrs)
                  (folded := foldInformalBlock)
                content
                companionPanels := #[externalPanel]
              }
          | none =>
            return renderInformalBlockModel {
              data
              context := InformalBlockRenderContext.forBlock data
                (data.displayIdentifier s)
                (proofCaption? := some (data.displayTitle s))
                (attrs := attrs)
                (folded := foldInformalBlock)
              content
              companionPanels := #[externalPanel]
            }

private def expanderImpl (kind : Data.NodeKind) (isProof : Bool := false) : DirectiveExpanderOf Config
  | cfg, contents => do
    let blockRef ← getRef
    let resolved ← cfg.resolveForDirective kind isProof
    let label := resolved.label
    let accepted ← Environment.push
      label resolved.envKind resolved.codeHint resolved.parent resolved.priority
      resolved.owner resolved.tags resolved.effort resolved.prUrl resolved.statementUses
    let contents ← contents.mapM elabBlock
    if !accepted then
      return ← ``(Block.concat #[$contents,*])
    let previewBlocks ← liftM <| Informal.evalElaboratedBlocks (contents.map (·.raw))
    Environment.setPreviewBlocks previewBlocks
    let count ← Environment.pop blockRef
    liftM <| DependencyAnalysis.attachInferredUseRefs label blockRef { proof := resolved.proofUses }
    let node? ← Environment.getNode? label
    let blockKind : Data.InProgressKind ←
      if isProof then
        pure .proof
      else
        let nodeKind ←
          match node? with
            | some node => pure node.kind
            | none =>
              logErrorAt resolved.labelSyntax m!"Internal error: missing node '{label}' after environment registration"
              pure kind
        pure <| .statement nodeKind
    let codeData :=
      match blockKind with
      | .proof => none
      | .statement _ =>
        let externalRefs := node?.map (·.externalRefs) |>.getD #[]
        BlockCodeData.ofExternalRefs externalRefs
    let statementPayload? := node?.bind (·.statement)
    let proofPayload? := node?.bind (·.proof)
    let statementUses := statementPayload?.map (·.deps) |>.getD #[]
    let proofUses := proofPayload?.map (·.deps) |>.getD #[]
    let owner := node?.bind (·.owner)
    let ownerInfo? ←
      match owner with
      | some owner => Environment.getAuthor? owner
      | none => pure none
    let opts ← getOptions
    let data : BlockData := {
      kind := blockKind
      codeData
      label
      foldProofBlock := verso.blueprint.foldProofBlocks.get opts
      foldCodeBlock := verso.blueprint.foldCodeBlocks.get opts
      parent := node?.bind (·.parent)
      count
      numberingMode := numberingMode opts
      subNumberingPrefix := subNumberingPrefix opts
      subNumberingCounter := subNumberingCounter opts
      statementUses
      proofUses
      owner
      ownerDisplayName := ownerInfo?.map (·.displayName)
      ownerUrl := ownerInfo?.bind (·.url)
      ownerImageUrl := ownerInfo?.bind (·.imageUrl)
      tags := node?.map (·.tags) |>.getD #[]
      effort := node?.bind (·.effort)
      priority := node?.bind (·.priority)
      prUrl := node?.bind (·.prUrl)
    }
    ``(Block.other (Block.informal $(quote data)) #[$contents,*])

private def directiveName (kind : Data.NodeKind) (isProof : Bool): String :=
  if isProof then "proof" else (toString kind).toLower

private def expander (kind : Data.NodeKind) (isProof : Bool := false) : DirectiveExpanderOf Config
  | cfg, contents => do
    let label := (directiveName kind isProof)
    Profile.withDocElab "directive" label <|
      (expanderImpl kind isProof) cfg contents

@[directive] def «definition» := expander .definition
@[directive] def «proposition» := expander .proposition
@[directive] def «lemma_» := expander .lemma
@[directive] def «theorem» := expander .theorem
@[directive] def «corollary» := expander .corollary
@[directive] def «proof» := expander .lemma (isProof := true)

end Informal
