/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoSlides
import Verso.Doc.Elab
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.PreviewManifest.BlockRender
import VersoBlueprint.Slides.Node
import VersoBlueprint.TraversalIndex

set_option doc.verso true

namespace Informal.Graft

open Lean
open Verso Doc Elab
open Verso.Genre Manual
open Verso.Output
open Verso.Output.Html

def css : String := r##"
.bp_graft_node {
  display: block;
  margin: 0.75rem 0;
}

.bp_graft_node_compact .bp_code_panel_wrapper {
  display: none;
}

.bp_graft_node_notice {
  margin: 0.75rem 0;
  padding: 0.6rem 0.75rem;
  border: 1px solid var(--bp-color-status-error-border-soft);
  border-radius: var(--bp-radius-md);
  background: var(--bp-color-surface-warn);
  color: var(--bp-color-status-error-strong);
  font-size: 0.9rem;
  line-height: 1.4;
}

.bp_graft_side_by_side {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(22rem, 100%), 1fr));
  gap: 0.9rem;
  align-items: start;
  margin: 0.9rem 0;
}

.bp_graft_side_by_side > * {
  min-width: 0;
}

.bp_graft_side_by_side .bp_wrapper,
.bp_graft_side_by_side .bp_graft_node {
  margin-top: 0;
  margin-bottom: 0;
}

.bp_graft_side_by_side .bp_heading {
  align-items: flex-start;
}

.bp_graft_side_by_side .bp_extras {
  margin-left: 0;
}
"##

def cssAssets : List String := [css]

private def renderNotice (kind title detail : String) : Html :=
  {{
    <div class={{"bp_graft_node_notice bp_graft_node_notice_" ++ kind}}>
      <strong>{{Html.ofString title}}</strong><br/>
      {{Html.ofString detail}}
    </div>
  }}

private def replaceClassAttr (attrs : Array (String × String)) (className : String) :
    Array (String × String) :=
  Id.run do
    let mut out := #[]
    let mut found := false
    for attr in attrs do
      if attr.1 == "class" then
        out := out.push ("class", className)
        found := true
      else
        out := out.push attr
    if found then
      out
    else
      out.push ("class", className)

private def manualNodeClass (node : Informal.Slides.BlueprintSlideNode) : String :=
  if node.compact then
    "bp_graft_node bp_graft_node_compact"
  else
    "bp_graft_node"

private def manualNodeAttrs (node : Informal.Slides.BlueprintSlideNode) :
    Array (String × String) :=
  replaceClassAttr node.renderedAttrs (manualNodeClass node)

private def manualBlockRenderConfig : Informal.PreviewManifest.BlockRender.RenderConfig :=
  {
    wrapperClass := "bp_graft_node_blueprint"
    codeBodyClass := "bp_graft_code_body"
    relationPanels := {
      wrapClass := fun kind => "bp_relation_wrap bp_graft_" ++ kind.key ++ "_wrap"
      idPrefix := fun kind entry =>
        match kind with
        | .group => s!"bp-graft-group-{entry.label}"
        | .uses => "bp-graft-uses"
        | .usedBy => "bp-graft-used-by"
    }
  }

private def pushDistinctHtml (bodies : Array Html) (body : Html) : Array Html :=
  let html := body.asString
  if bodies.any (fun existing => existing.asString == html) then
    bodies
  else
    bodies.push body

private def renderManualBlocks
    [Monad m]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Html)
    (blocks : Array (Doc.Block Verso.Genre.Manual)) :
    Doc.Html.HtmlT Verso.Genre.Manual m Html := do
  Html.seq <$> blocks.mapM goB

private def renderLeanCodePreviewBody?
    [Monad m]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Html)
    (state : TraverseState)
    (key : String) :
    Doc.Html.HtmlT Verso.Genre.Manual m (Option Html) := do
  match Informal.TraversalIndex.LeanCodePreviews.object? state key with
  | none =>
      Doc.Html.HtmlT.logError s!"Blueprint graft: missing Lean-code preview {key}"
      pure none
  | some obj =>
      match fromJson? (α := Informal.LeanCodePreview.Entry) obj.data with
      | .error err =>
          Doc.Html.HtmlT.logError s!"Blueprint graft: malformed Lean-code preview {key}: {err}"
          pure none
      | .ok entry =>
          match entry.source with
          | .inlineBlocks blocks => some <$> renderManualBlocks goB blocks
          | .externalDecl decl => pure <| some <| Informal.ExternalCode.renderPreviewHtml #[decl]

private def renderLeanCodeBodies
    [Monad m]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Html)
    (state : TraverseState)
    (entry : Informal.PreviewManifest.Entry) :
    Doc.Html.HtmlT Verso.Genre.Manual m (Array Html) := do
  let mut bodies := #[]
  for key in entry.leanCodePreviewKeys do
    match ← renderLeanCodePreviewBody? goB state key with
    | none => pure ()
    | some body =>
        if body.asString.trimAscii.isEmpty then
          pure ()
        else
          bodies := pushDistinctHtml bodies body
  pure bodies

private def renderManualGraftNode
    [Monad m]
    (goB : Doc.Block Verso.Genre.Manual → Doc.Html.HtmlT Verso.Genre.Manual m Html)
    (cfg : Informal.Slides.BlueprintNodeConfig) :
    Doc.Html.HtmlT Verso.Genre.Manual m Html := do
  let node := cfg.toSlideNode
  let state ← Doc.Html.HtmlT.state
  match Informal.PreviewManifest.findTraversalBlockEntry? state node.key with
  | none =>
      pure <| Html.tag "div" (manualNodeAttrs node) <|
        renderNotice "error" "Blueprint node not found" node.key
  | some (preview, entry) =>
      if preview.blocks.isEmpty then
        pure <| Html.tag "div" (manualNodeAttrs node) <|
          renderNotice "error" "Blueprint node has no cached content" node.key
      else
        let body ← renderManualBlocks goB preview.blocks
        let codeBodies ←
          if node.compact then
            pure #[]
          else
            renderLeanCodeBodies goB state entry
        let content : Informal.PreviewManifest.BlockRender.RenderedContent := {
          body
          codeBodies
        }
        pure <| Html.tag "div" (manualNodeAttrs node) <|
          Informal.PreviewManifest.BlockRender.renderWithRenderedContent
            manualBlockRenderConfig
            entry
            content
            {
              displayLabelOverride? := node.displayLabel?
              compact := node.compact
              showHeader := node.showHeader
            }

open Verso Doc Elab Genre Manual in
block_extension Block.blueprintGraftNode (cfg : Informal.Slides.BlueprintNodeConfig) where
  data := toJson cfg
  traverse _ _ _ := pure none
  toTeX := none
  extraCss := Informal.Block.Assets.blockCssAssets ++ Informal.Graft.cssAssets
  extraJs := Informal.Block.Assets.blockJsAssets
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI goB _id data _blocks => do
      match fromJson? (α := Informal.Slides.BlueprintNodeConfig) data with
      | .error err =>
          HtmlT.logError s!"Malformed Blueprint graft node data ({err}): {data}"
          pure .empty
      | .ok cfg => renderManualGraftNode goB cfg

open Verso Doc Elab Genre Manual in
block_extension Block.blueprintGraftSideBySide where
  traverse _ _ _ := pure none
  toTeX := none
  extraCss := Informal.Block.Assets.blockCssAssets ++ Informal.Graft.cssAssets
  extraJs := Informal.Block.Assets.blockJsAssets
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI goB _id _data blocks => do
      let content ← blocks.mapM goB
      pure <| Html.tag "div" #[("class", "bp_graft_side_by_side")] (Html.seq content)

private meta def currentGenreIs (genreTerm : Term) : DocElabM Bool := do
  let current := (← readThe DocElabContext).genre
  let expected ← Lean.Elab.Term.elabTerm genreTerm (some (.const ``Verso.Doc.Genre []))
  Lean.Meta.isDefEq current expected

private meta def inManualGenre : DocElabM Bool := do
  currentGenreIs (← `(Verso.Genre.Manual))

private meta def inSlidesGenre : DocElabM Bool := do
  currentGenreIs (← `(VersoSlides.Slides))

def sideBySideAttrs : Array (String × String) :=
  #[("class", "bp_graft_side_by_side bp_slide_graft_side_by_side")]

public meta def blueprintNodeBlock (cfg : Informal.Slides.BlueprintNodeConfig) :
    DocElabM Term := do
  if ← inManualGenre then
    ``(Verso.Doc.Block.other
        (Informal.Graft.Block.blueprintGraftNode $(quote cfg))
        #[])
  else if ← inSlidesGenre then
    Informal.Slides.blueprintNodeBlock cfg
  else
    throwError "Blueprint graft nodes are only available in Manual and Slides documents"

public meta def blueprintSideBySide : DirectiveExpanderOf Unit
  | (), stxs => do
      let contents ← stxs.mapM elabBlock
      if ← inManualGenre then
        ``(Verso.Doc.Block.other
            Informal.Graft.Block.blueprintGraftSideBySide
            #[$contents,*])
      else if ← inSlidesGenre then
        ``(Verso.Doc.Block.other
            (VersoSlides.BlockExt.wrap $(quote sideBySideAttrs))
            #[$contents,*])
      else
        throwError "Blueprint side-by-side grafts are only available in Manual and Slides documents"

end Informal.Graft

open Verso Doc Elab

/--
Render a Blueprint preview node by label in either a Manual document or a Slides
deck.
-/
@[block_command]
public meta def blueprint_node : BlockCommandOf Informal.Slides.BlueprintNodeConfig
  | cfg => Informal.Graft.blueprintNodeBlock cfg

/--
Lay out Blueprint graft nodes side by side. Child blocks are ordinary
`{blueprint_node ...}` commands and keep their own options.
-/
@[directive]
public meta def blueprint_side_by_side : DirectiveExpanderOf Unit :=
  Informal.Graft.blueprintSideBySide
