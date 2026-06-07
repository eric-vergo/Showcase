/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html
import VersoBlueprint.PreviewManifest
import VersoBlueprint.PreviewManifest.BlockRender
import VersoBlueprint.PreviewRender
import VersoBlueprint.Slides.Node

namespace Informal.Slides

open Lean
open Verso.Output
open Verso.Output.Html

public structure RenderContext where
  manifest? : Option Informal.PreviewManifest.File := none
  index : Informal.PreviewManifest.Index := {}
  manualImpls : Verso.Genre.Manual.ExtensionImpls
  traverseState : Verso.Genre.Manual.TraverseState :=
    Verso.Genre.Manual.TraverseState.initialize {}
  logError : String → IO Unit := fun _ => pure ()

def RenderContext.ofManifest?
    (manifest? : Option Informal.PreviewManifest.File)
    (manualImpls : Verso.Genre.Manual.ExtensionImpls := by exact extension_impls%)
    (logError : String → IO Unit := fun _ => pure ()) : RenderContext :=
  {
    manifest?
    index := manifest?.map (·.index) |>.getD {}
    manualImpls
    traverseState :=
      manifest?.bind (·.traverseState) |>.getD
        (Verso.Genre.Manual.TraverseState.initialize {})
    logError
  }

private def RenderContext.findEntry? (ctx : RenderContext) (key : String) :
    Option Informal.PreviewManifest.Entry :=
  ctx.index.findEntry? key

private def slideManifestBlockConfig : Informal.PreviewManifest.BlockRender.RenderConfig :=
  {
    wrapperClass := "bp_slide_node_blueprint"
    codeBodyClass := "bp_slide_code_body"
    titleRowAttrs? := fun entry =>
      entry.href.map fun href =>
        #[ ("class", "bp_slide_node_heading_link")
         , ("data-bp-slide-link", "blueprint")
         , ("href", href)
         , ("target", "bp-slide-blueprint")
         , ("rel", "noopener")
         , ("title", "Open Blueprint node")
         ]
    relationPanels := {
      wrapClass := fun kind => "bp_used_by_wrap bp_slide_" ++ kind.key ++ "_wrap"
      panelAttrs := fun kind => #[("data-bp-slide-panel", kind.key)]
      idPrefix := fun kind entry =>
        match kind with
        | .group => s!"bp-slide-group-{entry.label}"
        | .uses => "bp-slide-uses"
        | .usedBy => "bp-slide-used-by"
    }
  }

private def renderNotice (kind title detail : String) : Html :=
  {{
    <div class={{"bp_slide_node_notice bp_slide_node_notice_" ++ kind}}>
      <strong>{{Html.ofString title}}</strong><br/>
      {{Html.ofString detail}}
    </div>
  }}

private def renderMissingNode (node : BlueprintSlideNode) (title detail : String) : Html :=
  .tag "div" node.renderedAttrs (renderNotice "error" title detail)

private def renderEntryBody (ctx : RenderContext) (entry : Informal.PreviewManifest.Entry) :
    IO Html := do
  if entry.blocks.isEmpty then
    pure <| Informal.PreviewManifest.BlockRender.htmlFragment entry.html
  else
    Informal.renderManualBlocksHtmlWithState
      entry.blocks
      ctx.manualImpls
      ctx.traverseState
      (logError := ctx.logError)

private def renderLeanCodeEntry (ctx : RenderContext) (entry : Informal.PreviewManifest.Entry) :
    IO Html := do
  match entry.leanCode with
  | some leanCode =>
      Informal.LeanCodePreview.renderHtmlWithState
        leanCode
        ctx.manualImpls
        ctx.traverseState
        (logError := ctx.logError)
  | none =>
      pure <| Informal.PreviewManifest.BlockRender.htmlFragment entry.html

private def renderLeanCodeBodies
    (ctx : RenderContext) (node : BlueprintSlideNode) (entry : Informal.PreviewManifest.Entry) :
    IO (Array Html) := do
  if node.compact then
    pure #[]
  else
    (ctx.index.codeEntries entry).mapM (renderLeanCodeEntry ctx)

private def renderEntryContent
    (ctx : RenderContext) (node : BlueprintSlideNode) (entry : Informal.PreviewManifest.Entry) :
    IO Informal.PreviewManifest.BlockRender.RenderedContent := do
  let body ← renderEntryBody ctx entry
  let codeBodies ← renderLeanCodeBodies ctx node entry
  pure { body, codeBodies }

public def renderBlueprintSlideNode (ctx : RenderContext) (node : BlueprintSlideNode) : IO Html := do
  match ctx.manifest? with
  | none =>
    pure <| renderMissingNode node "Preview manifest unavailable"
      "Pass previewManifest? to slidesMainWithBlueprintPreviews so Blueprint slide nodes can be rendered during slide generation."
  | some _manifest =>
    match ctx.findEntry? node.key with
    | none =>
      pure <| renderMissingNode node "Blueprint node not found" node.key
    | some entry =>
      let content ← renderEntryContent ctx node entry
      pure <| .tag "div" node.renderedAttrs <|
        Informal.PreviewManifest.BlockRender.renderWithRenderedContent
          slideManifestBlockConfig
          entry
          content
          { titleOverride? := node.title?, compact := node.compact }

/--
Render a Blueprint slide node from the structured attributes carried by the
`VersoSlides.BlockExt.wrap` emitted by `blueprint_node`.
-/
public def renderBlueprintSlideNodeFromAttrs?
    (ctx : RenderContext)
    (attrs : Array (String × String)) : Option (IO Html) := do
  let node ← BlueprintSlideNode.fromAttrs? attrs
  some (renderBlueprintSlideNode ctx node)

def readBlueprintPreviewManifest (path : System.FilePath) :
    IO Informal.PreviewManifest.File :=
  Informal.PreviewManifest.readFile path

end Informal.Slides
