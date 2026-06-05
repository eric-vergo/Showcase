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
import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.Informal.Block.Render
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.Block.Traversal
import VersoBlueprint.Informal.CodeSummary
import VersoBlueprint.Informal.ExternalCode
import VersoBlueprint.LabelNameParsing
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

/-- Configuration for directives / code-blocks. Q: should we allow non-labelled informal objects? -/
structure Config where
  label : Data.Label
  labelSyntax : Syntax := Syntax.missing
  lean : Option String := none
  parent : Option Data.Parent := none
  priority : Option String := none
  owner : Option Data.AuthorId := none
  tags : Array String := #[]
  effort : Option String := none
  prUrl : Option String := none
  externalCode : Array Data.ExternalRef := #[]
  invalidExternalCode : Array String := #[]
--  hide : Bool := false

section
variable [Monad m] [MonadInfoTree m] [MonadLiftT CoreM m] [MonadEnv m] [MonadError m] [MonadFileMap m]

private def normalizePriority? (raw : String) : Option String :=
  match raw.trimAscii.toString.toLower with
  | "high" => some "high"
  | "medium" => some "medium"
  | "low" => some "low"
  | _ => none

private def normalizeEffort? (raw : String) : Option String :=
  match raw.trimAscii.toString.toLower with
  | "small" | "s" => some "small"
  | "medium" | "m" => some "medium"
  | "large" | "l" => some "large"
  | _ => none

private def normalizeTags (raw : String) : Array String :=
  raw.splitOn ","
    |>.toArray
    |>.map (fun tag => tag.trimAscii.toString.toLower)
    |>.filter (fun tag => !tag.isEmpty)
    |>.foldl (init := #[]) fun acc tag => if acc.contains tag then acc else acc.push tag

def Config.parse  : ArgParse m Config :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) lean parent priority owner tags effort prUrl =>
    let (externalCode, invalidExternalCode) := ExternalCode.parseExternalCodeList lean
    {
      label := LabelNameParsing.parse labelArg.val
      labelSyntax := labelArg.syntax
      lean := lean
      parent := parent.map LabelNameParsing.parse
      priority := priority
      owner := owner.map LabelNameParsing.parse
      tags := normalizeTags (tags.getD "")
      effort := effort
      prUrl := prUrl.map (·.trimAscii.toString)
      externalCode := externalCode
      invalidExternalCode := invalidExternalCode
    }) <$> .positional `label (.withSyntax .string) <*> .named `lean .string true
        <*> .named `parent .string true <*> .named `priority .string true <*> .named `owner .string true
        <*> .named `tags .string true <*> .named `effort .string true <*> .named `pr_url .string true

instance : FromArgs Config m where
  fromArgs := Config.parse

end

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
          match Resolve.resolveRenderedExternalDeclHref? s data.label decl with
          | some href => some href
          | none => Resolve.resolveInlineLeanDeclHref? s decl
        let getDeclAnchorAttrs (decl : Data.ExternalRef) : Array (String × String) :=
          let attrsFor (declName : Name) : Array (String × String) :=
            let key := Resolve.externalRenderedDeclTargetKey data.label declName
            match Informal.TraversalIndex.ExternalDeclAnchors.object? s key with
            | none => #[]
            | some obj =>
              match obj.ids.toArray[0]? with
              | some targetId => s.htmlId targetId
              | none => #[]
          -- Targets are keyed by canonical declaration name; fallback to the written name keeps
          -- links stable if older cached objects were keyed before canonicalization.
          let canonicalAttrs := attrsFor decl.canonical
          if canonicalAttrs.isEmpty then attrsFor decl.written else canonicalAttrs
        let cdata := {
          codeHref
          source := codeSource
        }
        let panelSummary := CodeSummary.renderPanelIndicator data.label cdata getDeclHref
        let headingParts? : Option CodeSummary.RenderParts :=
          match data.kind with
          | .statement _ => some <| CodeSummary.renderParts data cdata getDeclHref
          | .proof => none
        let externalParts? : Option ExternalCode.RenderParts :=
          match data.kind, codeSource with
          | .statement _, some (.external decls) =>
            if decls.isEmpty then
              none
            else
              let panelHeader := codePanelHeader data (data.displayNumber s)
              some <| ExternalCode.renderParts
                panelHeader
                panelSummary.summaryTitle
                panelSummary.indicator
                decls
                getDeclHref
                getDeclAnchorAttrs
                (folded := data.foldCodeBlock)
          | _, _ => none
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
    let label := cfg.label
    let envKind : Data.InProgressKind :=
      if isProof then .proof else .statement kind
    let resolvedExternalCode ← ExternalCode.resolveExternalCodeList label cfg.labelSyntax kind cfg.externalCode
    let hasExternalRaw := !resolvedExternalCode.isEmpty
    if !cfg.invalidExternalCode.isEmpty then
      logWarningAt cfg.labelSyntax m!"Label {label}: ignoring malformed names in '(lean := ...)' ({String.intercalate ", " cfg.invalidExternalCode.toList})"
    if isProof && hasExternalRaw then
      logErrorAt cfg.labelSyntax m!"Label {label} cannot use '(lean := ...)' in a proof block"
    let priority : Option String ←
      match cfg.priority with
      | none => pure none
      | some raw =>
        match normalizePriority? raw with
        | some normalized =>
          if isProof then
            logErrorAt cfg.labelSyntax m!"Label {label} cannot use '(priority := ...)' in a proof block"
            pure none
          else
            pure (some normalized)
        | none =>
          logErrorAt cfg.labelSyntax m!"Label {label} has invalid '(priority := \"{raw}\")'; expected one of \"high\", \"medium\", \"low\""
          pure none
    let owner : Option Data.AuthorId ←
      match cfg.owner with
      | none => pure none
      | some owner =>
        if isProof then
          logErrorAt cfg.labelSyntax m!"Label {label} cannot use '(owner := ...)' in a proof block"
          pure none
        else if (← Environment.getAuthor? owner).isNone then
          logErrorAt cfg.labelSyntax m!"Label {label} references unknown owner '{owner}'; declare it first with ':::author'"
          pure none
        else
          pure (some owner)
    let effort : Option String ←
      match cfg.effort with
      | none => pure none
      | some raw =>
        match normalizeEffort? raw with
        | some normalized =>
          if isProof then
            logErrorAt cfg.labelSyntax m!"Label {label} cannot use '(effort := ...)' in a proof block"
            pure none
          else
            pure (some normalized)
        | none =>
          logErrorAt cfg.labelSyntax m!"Label {label} has invalid '(effort := \"{raw}\")'; expected one of \"small\", \"medium\", \"large\""
          pure none
    let tags : Array String :=
      if isProof && !cfg.tags.isEmpty then
        #[]
      else
        cfg.tags
    if isProof && !cfg.tags.isEmpty then
      logErrorAt cfg.labelSyntax m!"Label {label} cannot use '(tags := ...)' in a proof block"
    let prUrl : Option String :=
      if isProof then
        none
      else
        match cfg.prUrl with
        | some url =>
          let url := url.trimAscii.toString
          if url.isEmpty then
            none
          else if url.startsWith "http://" || url.startsWith "https://" then
            some url
          else
            none
        | none => none
    if isProof && cfg.prUrl.isSome then
      logErrorAt cfg.labelSyntax m!"Label {label} cannot use '(pr_url := ...)' in a proof block"
    if !isProof then
      if let some url := cfg.prUrl then
        let url := url.trimAscii.toString
        if !url.isEmpty && !(url.startsWith "http://" || url.startsWith "https://") then
          logErrorAt cfg.labelSyntax m!"Label {label} has invalid '(pr_url := \"{url}\")'; expected an http(s) URL"
    let hasExternal := hasExternalRaw && !isProof
    let codeHint : Option Data.CodeRef :=
      if isProof then
        none
      else if hasExternal then
        some (.external resolvedExternalCode)
      else
        none
    let accepted ← Environment.push label envKind codeHint cfg.parent priority owner tags effort prUrl
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
              logErrorAt cfg.labelSyntax m!"Internal error: missing node '{label}' after environment registration"
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
