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
    match fromJson? (α := BlockData) data with
    | .error err =>
      logError s!"Malformed data ({err}): {data}"
      pure none
    | .ok blockData =>
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
      match fromJson? (α := BlockData) data with
      | .error err =>
        HtmlT.logError s!"Malformed data ({err}): {data}"
        pure .empty
      | .ok data =>
        let s ← HtmlT.state
        let ctxt ← HtmlT.context
        let data := data.withResolvedNumberingInContext s ctxt
        let relatedPanelContext := RelatedPanel.Context.ofState s
        let attrs := s.htmlId id
        let codeHref : Option String :=
          match Informal.TraversalIndex.InlineCode.object? s data.label with
          | some obj =>
            match obj.ids.toArray[0]? with
            | some codeId => s.externalTags[codeId]? |>.map (·.relativeLink)
            | none => none
          | none => none
        let codeData? : Option InlineCodeData ←
          pure <| Informal.TraversalIndex.InlineCode.data? s data.label
        let codeHint? :=
          match data.kind with
          | .proof => none
          | .statement _ => data.codeData
        let codeSource := BlockCodeData.ofHintAndInline codeHint? codeData?
        let getDeclHref (decl : Name) : Option String :=
          Resolve.resolveInformalDeclHref? s data.label decl
        let getDeclAnchorAttrs (decl : Data.ExternalRef) : Array (String × String) :=
          Informal.TraversalIndex.ExternalDeclAnchors.refHtmlIdAttrs s data.label decl
        let cdata := {
          codeHref
          source := codeSource
        }
        let panelSummary := CodeSummary.renderPanelIndicator data.label cdata getDeclHref
        let headingParts? : Option CodeSummary.RenderParts :=
          match data.kind with
          | .statement _ => some <| CodeSummary.renderParts data cdata getDeclHref
          | .proof => none
        let externalParts? : Option ExternalCode.RenderParts ←
          match data.kind, codeSource with
          | .statement _, some (.external decls) =>
            if decls.isEmpty then
              pure none
            else
              let panelHeader := codePanelHeader data (data.displayNumber s)
              some <$> ExternalCode.renderPartsWithPageHovers
                panelHeader
                panelSummary.summaryTitle
                panelSummary.indicator
                decls
                getDeclHref
                getDeclAnchorAttrs
                (folded := data.foldCodeBlock)
          | _, _ => pure none
        let externalPanel := (externalParts?.map (·.externalCodePanel)).getD .empty
        let content := (← blocks.mapM goB)
        let codeEntry := (headingParts?.map (·.codeEntry)).getD .empty
        let groupEntry ← RelatedPanel.renderGroupExtra relatedPanelContext data
        let usedByEntry ← RelatedPanel.renderUsedByExtra relatedPanelContext data
        let foldInformalBlock :=
          match data.kind with
          | .proof => data.foldProofBlock
          | .statement _ => false
        let informalBlock :=
          renderInformalBlockHtml data {
            numberText := data.displayNumber s
            captionText? :=
              match data.kind with
              | .proof => some (data.displayTitle s)
              | .statement _ => none
            attrs
            headerExtras := {
              group? := groupEntry.map HeaderExtra.group
              code? := some <| HeaderExtra.code codeEntry
              usedBy? := some <| HeaderExtra.usedBy usedByEntry
            }
            folded := foldInformalBlock
          } content
        return .seq #[informalBlock, externalPanel]

private def expanderImpl (kind : Data.NodeKind) (isProof : Bool := false) : DirectiveExpanderOf Config
  | cfg, contents => do
    let blockRef ← getRef
    let resolved ← cfg.resolveForDirective kind isProof
    let label := resolved.label
    let accepted ← Environment.push
      label resolved.envKind resolved.codeHint resolved.parent resolved.priority
      resolved.owner resolved.tags resolved.effort resolved.prUrl
    let contents ← contents.mapM elabBlock
    if !accepted then
      return ← ``(Block.concat #[$contents,*])
    let previewBlocks ← liftM <| Informal.evalElaboratedBlocks (contents.map (·.raw))
    Environment.setPreviewBlocks previewBlocks
    let count ← Environment.pop blockRef
    let node? ← Environment.getNode? label
    let nodeCodeRef? := node?.bind (·.code)
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
      | .statement _ => BlockCodeData.ofCodeRefHint nodeCodeRef?
    let statementDeps := node?.bind (·.statement.map (·.deps)) |>.getD #[]
    let proofDeps := node?.bind (·.proof.map (·.deps)) |>.getD #[]
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
      statementDeps
      proofDeps
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
@[directive] def «lemma_» := expander .lemma
@[directive] def «theorem» := expander .theorem
@[directive] def «corollary» := expander .corollary
@[directive] def «proof» := expander .lemma (isProof := true)

end Informal
