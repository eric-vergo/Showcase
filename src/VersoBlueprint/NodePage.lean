/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Std.Data.HashSet
import VersoBlueprint.Commands.Graph
import VersoBlueprint.GraphApi
import VersoBlueprint.NodeRoute
import VersoBlueprint.PreviewManifest
import VersoBlueprint.PreviewManifest.BlockRender

/-!
Dedicated per-node pages and the shared static-page emitter.

`emitStaticBlueprintPage` is the genre-owned helper that writes a single
standalone HTML page (`<path>/index.html`) reusing the full Blueprint page chrome
(sidebar ToC, head assets, dark-mode/KaTeX/graph runtime) without going through
the normal multi-page emit loop. It is the shared seam reused by the Wave 3 PM
pages (worklist / owners / tags); its signature is therefore fixed.

`emitBlueprintNodePages` is the `ExtraStep` that renders one page per informal
node: the statement, the inline proof, the uses/usedBy/group panels, the Lean
code, a static localized dependency graph (all ancestors + all descendants), and
a back-link to the chapter where the node is defined.
-/

namespace Informal.NodePage

open Lean
open Verso Verso.Output Verso.Doc
open Verso.Genre Manual
open Verso.Code.Hover (State)
open Informal.PreviewManifest (Entry)

/--
Emit one standalone Blueprint HTML page at `<outDir>/<path…>/index.html`,
reusing the same page chrome (sidebar ToC, global head assets, nav) as the
regular multi-page output.

The minimal emit context is rebuilt exactly like core `emitFindHtml` /
`emitSearchResultsHtml`: `definitionIds := state.definitionIds {}`, the sidebar
`toc` is rebuilt from the document's parts, and link targets use an empty
`AllRemotes` (acceptable because the generated site is offline / self-contained).
Absolute links are then made `<base>`-relative via `relativizeLinks`, and the
page's own `<base href>` is derived from `path` by the core `page` renderer.

Signature is fixed by the cross-cluster contract (Wave 3 PM pages call this).
-/
def emitStaticBlueprintPage
    (mode : Verso.Genre.Manual.Mode) (cfg : Verso.Genre.Manual.Config)
    (state : TraverseState)
    (text : Part Manual) (path : Verso.Multi.Path) (title : String)
    (contents : Output.Html) : IO Unit := do
  let extensionImpls : ExtensionImpls := extension_impls%
  let logger ← Verso.Logger.new
  let remotes : Verso.Multi.AllRemotes := {}
  let opts : Html.Options := {}
  let ctxt : Manual.TraverseContext := {}
  let definitionIds := state.definitionIds ctxt
  let linkTargets := state.localTargets ++ remotes.remoteTargets
  -- Rebuild the sidebar ToC in the full Manual HTML-emit monad stack.
  let tocAction :
      StateT (State Output.Html)
        (ReaderT Verso.Multi.AllRemotes (ReaderT ExtensionImpls (Verso.BuildLogT IO)))
        (List Html.Toc) :=
    text.subParts.toList.mapM fun p =>
      Verso.Genre.Manual.toc cfg.htmlDepth opts (ctxt.inPart p) state definitionIds linkTargets p
  let (sidebarToc, _) ←
    tocAction.run {} |>.run remotes |>.run extensionImpls |>.run logger
  let bookTitle : Output.Html := .text true text.titleString
  let rendered :=
    relativizeLinks <|
      page sidebarToc path title bookTitle contents state cfg #[] (showNavButtons := false)
  let outDir := cfg.destination.join (match mode with | .single => "html-single" | .multi => "html-multi")
  let dir := path.foldl (init := outDir) (fun d c => d.join c)
  IO.FS.createDirAll dir
  IO.FS.writeFile (dir.join "index.html") (Html.doctype ++ rendered.asString)

/--
Re-point an entry's uses/usedBy/group relation links to the related nodes' own
pages (node→node navigation), when those nodes have a page. This only rewrites
the copy used to render *this* node page; the global manifest (and therefore the
chapter-page panels and slides) keeps its chapter-anchor hrefs.
-/
private def repointEntryRelations (state : TraverseState) (entry : Entry) : Entry :=
  let repoint := fun (rel : Informal.PreviewManifest.RelatedEntry) =>
    if Informal.NodeRoute.hasNodePage state rel.label then
      { rel with href := some (Informal.NodeRoute.nodePageHref rel.label) }
    else rel
  { entry with
    uses := entry.uses.map repoint
    usedBy := entry.usedBy.map repoint
    group := entry.group.map (fun g => { g with entries := g.entries.map repoint }) }

open Verso.Output.Html in
/-- Assemble the body of a single node page from manifest + rendered-HTML cache. -/
private def renderNodePageBody
    (state : TraverseState)
    (master : Informal.Graph.GraphData)
    (htmlIndex : Informal.PreviewManifest.HtmlCache.Index)
    (manifestIndex : Informal.PreviewManifest.Index)
    (entry0 : Entry) : Output.Html :=
  let entry := repointEntryRelations state entry0
  -- Statement block (with uses/usedBy/group panels + Lean-code panel).
  let stmtHtml := (htmlIndex.findHtml? entry.key).getD ""
  let codeHtmls := entry.leanCodePreviewKeys.filterMap htmlIndex.findHtml?
  let statementBlock :=
    Informal.PreviewManifest.BlockRender.renderWithRenderedContent {} entry
      (Informal.PreviewManifest.BlockRender.RenderedContent.ofHtmlStrings stmtHtml codeHtmls)
  -- Proof block, rendered inline on the same page when a proof facet exists.
  let proofKey := Informal.PreviewCache.proofKey entry.label
  let proofBlock : Output.Html :=
    match manifestIndex.findEntry? proofKey with
    | some proofEntry0 =>
      let proofEntry := repointEntryRelations state proofEntry0
      let proofHtml := (htmlIndex.findHtml? proofKey).getD ""
      let proofCode := proofEntry.leanCodePreviewKeys.filterMap htmlIndex.findHtml?
      Informal.PreviewManifest.BlockRender.renderWithRenderedContent {} proofEntry
        (Informal.PreviewManifest.BlockRender.RenderedContent.ofHtmlStrings proofHtml proofCode)
    | none => .empty
  -- Localized dependency graph: this node ∪ all ancestors ∪ all descendants.
  let labelSet : Lean.NameSet :=
    let base := (master.ancestors entry.label).insert entry.label
    (master.descendants entry.label).toList.foldl (·.insert ·) base
  let sub := master.restrictTo labelSet
  let slug := Informal.NodeRoute.nodePageSlug entry.label
  let localVariant : Informal.Graph.GraphRenderVariant := {
    key := "local"
    label := "Local dependencies"
    dot := sub.toDotWith
  }
  let graphHtml : Output.Html :=
    if sub.nodes.isEmpty then .empty
    else
      Informal.Commands.renderGraphFullwidth sub #[localVariant] {} s!"bp-node-graph-{slug}"
        (static := true)
  -- "Defined in" back-link to the chapter anchor (state.domains is unmodified, so
  -- these resolvers still return the original chapter href, not the node page).
  let backHref? :=
    Informal.TraversalIndex.TraversalPreviews.hrefFor? state entry.label .statement
      <|> Informal.TraversalIndex.Nodes.href? state entry.label
  let backLink : Output.Html :=
    match backHref? with
    | some href => {{
        <p class="bp_node_page_backlink">
          <a href={{href}}>"View in chapter context"</a>
        </p>
      }}
    | none => .empty
  let parentContext : Output.Html :=
    match entry.parentTitle with
    | some pt => {{ <p class="bp_node_page_group">"Part of: " {{.text true pt}}</p> }}
    | none => .empty
  {{
    <div class="bp_node_page">
      <header class="bp_node_page_header">
        <h1>{{.text true entry.title}}</h1>
        {{parentContext}}
        {{backLink}}
      </header>
      <section class="bp_node_page_statement">{{statementBlock}}</section>
      <section class="bp_node_page_proof">{{proofBlock}}</section>
      <section class="bp_node_page_graph">
        <h2>"Local dependency graph"</h2>
        {{graphHtml}}
      </section>
    </div>
  }}

/--
`ExtraStep` that emits a dedicated page per informal node (statement facet) into
`node/<slug>/index.html` for the multi-page output.

It recomputes its inputs from `state` via `buildPreviewDataFiles` (the rendered
HTML cache + manifest entries) and `GraphApi.masterGraph` (the dependency
universe), so it is self-contained and order-independent relative to
`emitBlueprintPreviewData`. Single-page mode is skipped.
-/
def emitBlueprintNodePages (extensionImpls : ExtensionImpls) : ExtraStep :=
  fun mode cfg state _text => do
    match mode with
    | .single => pure ()
    | .multi =>
      let text := _text
      let logger : Verso.Logger IO ← read
      let logError := fun msg => logger.reportError msg
      let files ← Informal.PreviewManifest.buildPreviewDataFiles extensionImpls logError state
      let htmlIndex := files.htmlCache.index
      let manifestIndex := files.manifest.index
      let master := Informal.GraphApi.masterGraph state
      let mut usedSlugs : Std.HashSet String := {}
      for entry in files.manifest.blockStatementEntries do
        let slug := Informal.NodeRoute.nodePageSlug entry.label
        if usedSlugs.contains slug then
          logError <|
            s!"Blueprint node pages: slug collision for {entry.label} (slug {slug}); " ++
            "node page may overwrite another node's page"
        usedSlugs := usedSlugs.insert slug
        let body := renderNodePageBody state master htmlIndex manifestIndex entry
        emitStaticBlueprintPage mode cfg state text
          (Informal.NodeRoute.nodePagePath entry.label) entry.title body

end Informal.NodePage
