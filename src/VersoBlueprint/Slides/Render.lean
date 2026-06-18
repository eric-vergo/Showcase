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

private def slideNodeAttrs (node : Informal.Graft.BlueprintNode) : Array (String × String) :=
  renderedBlueprintNodeAttrs node

private def renderMissingNode (node : Informal.Graft.BlueprintNode) (title detail : String) : Html :=
  .tag "div" (slideNodeAttrs node) <|
    Informal.Graft.renderNotice "bp_slide_node_notice" "error" title detail

private def slideManifestRenderConfig : Informal.Graft.ManifestRenderConfig :=
  {
    blockRenderConfig := slideManifestBlockConfig
    nodeAttrs := slideNodeAttrs
    renderMissingNode := renderMissingNode
    manifestUnavailableDetail :=
      "Pass previewManifest? to slidesMainWithBlueprintPreviews so Blueprint slide nodes can be rendered during slide generation."
  }

public def renderBlueprintSlideNode
    (ctx : RenderContext)
    (node : Informal.Graft.BlueprintNode) : IO Html := do
  Informal.Graft.renderNodeFromManifestCache slideManifestRenderConfig ctx node

/--
Render a Blueprint slide node from the structured attributes carried by the
legacy `VersoSlides.BlockExt.wrap` carrier emitted by `blueprint_node`.

The Lean 4.31 slide path rewrites these carriers to
`VersoSlides.BlockExt.ofHtml` during Slides traversal; the 4.30 maintenance line
keeps the older HTML-renderer interception path.

Remove this helper once the 4.30 maintenance line is retired.
-/
public def renderBlueprintSlideNodeFromAttrs?
    (ctx : RenderContext)
    (attrs : Array (String × String)) : Option (IO Html) := do
  let node ← Informal.Graft.BlueprintNode.fromAttrs? attrs
  some (renderBlueprintSlideNode ctx node)

end Informal.Slides
