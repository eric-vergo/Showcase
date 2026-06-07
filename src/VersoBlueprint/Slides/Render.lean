/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html
import VersoBlueprint.PreviewManifest
import VersoBlueprint.PreviewManifest.BlockRender
import VersoBlueprint.Slides.Node

namespace Informal.Slides

open Lean
open Verso.Output
open Verso.Output.Html

public structure RenderContext where
  manifest? : Option Informal.PreviewManifest.File := none
  index : Informal.PreviewManifest.Index := {}
  htmlCacheIndex : Informal.PreviewManifest.HtmlCache.Index := {}
  logError : String → IO Unit := fun _ => pure ()

def RenderContext.ofPreviewData?
    (manifest? : Option Informal.PreviewManifest.File)
    (htmlCache? : Option Informal.PreviewManifest.HtmlCache.File := none)
    (logError : String → IO Unit := fun _ => pure ()) : RenderContext :=
  let htmlCache := htmlCache?.getD {}
  {
    manifest?
    index := manifest?.map (·.index) |>.getD {}
    htmlCacheIndex := htmlCache.index
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
      wrapClass := fun kind => "bp_relation_wrap bp_slide_" ++ kind.key ++ "_wrap"
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

private def renderLeanCodeBodies
    (ctx : RenderContext) (node : BlueprintSlideNode) (entry : Informal.PreviewManifest.Entry) :
    Array Html :=
  if node.compact then
    #[]
  else
    (ctx.htmlCacheIndex.codeHtmlBodies entry).map
      Informal.PreviewManifest.BlockRender.htmlFragment

private def renderEntryContent
    (ctx : RenderContext) (node : BlueprintSlideNode) (entry : Informal.PreviewManifest.Entry) :
    IO (Option Informal.PreviewManifest.BlockRender.RenderedContent) := do
  match ctx.htmlCacheIndex.findHtml? entry.key with
  | none =>
      ctx.logError s!"Blueprint HTML cache: missing rendered body for {entry.key}"
      pure none
  | some bodyHtml =>
      pure <| some {
        body := Informal.PreviewManifest.BlockRender.htmlFragment bodyHtml
        codeBodies := renderLeanCodeBodies ctx node entry
      }

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
      match ← renderEntryContent ctx node entry with
      | none =>
          pure <| renderMissingNode node "Blueprint HTML cache entry not found" entry.key
      | some content =>
          pure <| .tag "div" node.renderedAttrs <|
            Informal.PreviewManifest.BlockRender.renderWithRenderedContent
              slideManifestBlockConfig
              entry
              content
              { displayLabelOverride? := node.displayLabel?, compact := node.compact }

/--
Render a Blueprint slide node from the structured attributes carried by the
`VersoSlides.BlockExt.wrap` emitted by `blueprint_node`.
-/
public def renderBlueprintSlideNodeFromAttrs?
    (ctx : RenderContext)
    (attrs : Array (String × String)) : Option (IO Html) := do
  let node ← BlueprintSlideNode.fromAttrs? attrs
  some (renderBlueprintSlideNode ctx node)

def readBlueprintManifest (path : System.FilePath) :
    IO Informal.PreviewManifest.File :=
  Informal.PreviewManifest.readFile path

def readBlueprintHtmlCache (path : System.FilePath) :
    IO Informal.PreviewManifest.HtmlCache.File :=
  Informal.PreviewManifest.HtmlCache.readFile path

end Informal.Slides
