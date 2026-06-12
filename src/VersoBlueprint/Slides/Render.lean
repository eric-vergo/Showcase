/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html
import VersoBlueprint.Graft.Render
import VersoBlueprint.PreviewManifest.BlockRender
import VersoBlueprint.Slides.Node

namespace Informal.Slides

open Verso.Output
open Verso.Output.Html

public abbrev RenderContext := Informal.Graft.RenderContext

namespace RenderContext

public def ofPreviewData?
    (manifest? : Option Informal.PreviewManifest.File)
    (htmlCache? : Option Informal.PreviewManifest.HtmlCache.File := none)
    (logError : String → IO Unit := fun _ => pure ()) : RenderContext :=
  Informal.Graft.RenderContext.ofPreviewData? manifest? htmlCache? logError

end RenderContext

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

private def slideManifestRenderConfig : Informal.Graft.ManifestRenderConfig :=
  {
    blockRenderConfig := slideManifestBlockConfig
    renderMissingNode := renderMissingNode
    manifestUnavailableDetail :=
      "Pass previewManifest? to slidesMainWithBlueprintPreviews so Blueprint slide nodes can be rendered during slide generation."
  }

public def renderBlueprintSlideNode (ctx : RenderContext) (node : BlueprintSlideNode) : IO Html := do
  Informal.Graft.renderNodeFromManifestCache slideManifestRenderConfig ctx node

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
  Informal.Graft.readBlueprintManifest path

def readBlueprintHtmlCache (path : System.FilePath) :
    IO Informal.PreviewManifest.HtmlCache.File :=
  Informal.Graft.readBlueprintHtmlCache path

end Informal.Slides
