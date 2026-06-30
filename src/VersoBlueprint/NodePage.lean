/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Std.Data.HashSet
import VersoBlueprint.Commands.Graph
import VersoBlueprint.CopyButton
import VersoBlueprint.GraphApi
import VersoBlueprint.GraphMetrics
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
Inline styling for the per-node metrics line.

Emitted once inside each node page body (node pages carry no dedicated CSS file).
Colors come from the `--bp-color-*` design tokens, with light literal fallbacks,
so the line themes correctly in dark mode.
-/
def nodeMetricsCss : String := r##"
.bp_node_metrics {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem 0.6rem;
  align-items: center;
  margin: 0.5rem 0 0;
  font-size: var(--bp-fs-small, 0.875rem);
}

.bp_node_metric {
  display: inline-flex;
  align-items: baseline;
  gap: 0.35rem;
  padding: 0.1rem 0.55rem;
  color: var(--bp-color-text-muted, #4d5e6d);
  background: var(--bp-color-surface-muted, #f1f4f7);
  border: 1px solid var(--bp-color-border, #dbe2ea);
  border-radius: var(--bp-radius-pill, 999px);
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  font-size: var(--bp-fs-badge, 0.72rem);
}

.bp_node_metric_value {
  font-weight: 700;
  color: var(--bp-color-text, #15212b);
}

.bp_node_metric_critical {
  color: var(--bp-color-status-mathlib, #6a4fba);
  background: var(--bp-color-status-mathlib-surface, rgba(106, 79, 186, 0.12));
  border-color: var(--bp-color-status-mathlib, #6a4fba);
  font-weight: 700;
}
"##

/--
Inline styling for the per-node downstream-impact panel.

Emitted once inside each node page body that has downstream dependents (node pages
carry no dedicated CSS file). Colors come from the `--bp-color-*` design tokens so
the panel themes correctly in light and dark mode.
-/
def nodeDownstreamCss : String := r##"
.bp_node_downstream_count {
  margin: 0 0 0.5rem;
  color: var(--bp-color-text-muted, #4d5e6d);
  font-size: var(--bp-fs-small, 0.875rem);
}

.bp_node_downstream_list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem 0.6rem;
}

.bp_node_downstream_list li {
  margin: 0;
}

.bp_node_downstream_list a {
  display: inline-block;
  padding: 0.15rem 0.6rem;
  color: var(--bp-color-text, #15212b);
  background: var(--bp-color-surface-muted, #f1f4f7);
  border: 1px solid var(--bp-color-border, #dbe2ea);
  border-radius: var(--bp-radius-pill, 999px);
  text-decoration: none;
  font-size: var(--bp-fs-small, 0.875rem);
  transition: border-color var(--bp-duration-fast, 0.12s) ease;
}

.bp_node_downstream_list a:hover {
  border-color: var(--bp-color-accent, #1c5fb8);
}
"##

/--
Inline styling for the per-node "view source / open in editor" action row.

Emitted once inside each node page header (node pages carry no dedicated CSS
file). Colors come from the `--bp-color-*` design tokens with light literal
fallbacks so the links theme correctly in dark mode.
-/
def nodeSourceCss : String := r##"
.bp_node_page_source {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem 0.6rem;
  align-items: center;
  margin: 0.5rem 0 0;
  font-size: var(--bp-fs-small, 0.875rem);
}

.bp_node_source_link {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  padding: 0.15rem 0.6rem;
  color: var(--bp-color-text, #15212b);
  background: var(--bp-color-surface-muted, #f1f4f7);
  border: 1px solid var(--bp-color-border, #dbe2ea);
  border-radius: var(--bp-radius-pill, 999px);
  text-decoration: none;
  transition: border-color var(--bp-duration-fast, 0.12s) ease;
}

.bp_node_source_link:hover {
  border-color: var(--bp-color-accent, #1c5fb8);
}
"##

/--
Inline styling for the node-page breadcrumb trail (Book › Chapter › node) and the
header action row that holds it alongside the copy-permalink button.

Emitted once inside each node page header. Colors / fonts come from the
`--bp-color-*` and `--font-mono-ui` design tokens, with light literal fallbacks,
so the trail themes correctly in dark mode.
-/
def nodeBreadcrumbCss : String := r##"
.bp_node_page_topbar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem 0.9rem;
  align-items: center;
  justify-content: space-between;
  margin: 0 0 0.6rem;
}

.bp_node_breadcrumb {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.1rem 0.35rem;
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-caption, 0.78rem);
  letter-spacing: 0.02em;
  color: var(--bp-color-text-muted, #4d5e6d);
}

.bp_node_breadcrumb a {
  color: var(--bp-color-accent, #1c5fb8);
  text-decoration: none;
}

.bp_node_breadcrumb a:hover {
  text-decoration: underline;
}

.bp_node_breadcrumb_sep {
  color: var(--bp-color-text-faint, #5f6f7e);
}

.bp_node_breadcrumb_current {
  color: var(--bp-color-text, #15212b);
  font-weight: 600;
}

.bp_node_page_group {
  color: var(--bp-color-text-muted, #4d5e6d);
  font-size: var(--bp-fs-small, 0.875rem);
  margin: 0.25rem 0 0;
}

.bp_node_page h2 {
  font-size: 1.15rem;
  font-weight: 600;
}

.bp_node_page > section {
  margin-top: var(--bp-space-5, 1.5rem);
}
"##

/--
Pick the primary external Lean declaration for an informal node from its
manifest `codeData`, preferring a declaration that is present in the environment
and carries a resolved source link, then any present declaration, then the first.
Returns `none` for nodes with no external code association (e.g. literate-only or
purely informal nodes).
-/
private def primaryExternalDecl? (entry : Entry) : Option Informal.Data.ExternalRef := do
  let codeData ← entry.codeData
  let decls := codeData.externalDecls
  (decls.find? (fun d => d.present && d.sourceHref?.isSome))
    <|> (decls.find? (·.present))
    <|> decls[0]?

open Verso.Output.Html in
/--
Render the node-header source action row: a "View source" link (GitHub blob URL
with the declaration line range, from the snapshotted `sourceHref?`) and an
"Open in editor" link built from a configurable editor URL template (default
`vscode://file{path}:{line}`) when the declaration's local source path is known.

All build-time string assembly; degrades gracefully to `.empty` when the node
has no external decl or no source information. The editor template is threaded
in from `emitBlueprintNodePages` (env-configurable, empty disables the link).
-/
private def renderNodeSource (editorTemplate : String) (entry : Entry) : Output.Html :=
  match primaryExternalDecl? entry with
  | none => .empty
  | some decl =>
    let viewSrc : Output.Html :=
      match decl.sourceHref? with
      | some href =>
        {{ <a class="bp_node_source_link" href={{href}} target="_blank" rel="noopener noreferrer">"View source"</a> }}
      | none => .empty
    let openEd : Output.Html :=
      match decl.provenance.sourcePath? with
      | some path =>
        if editorTemplate.isEmpty then .empty
        else
          let line := match decl.range? with | some r => toString r.pos.line | none => "1"
          let url := (editorTemplate.replace "{path}" path).replace "{line}" line
          {{ <a class="bp_node_source_link" href={{url}}>"Open in editor"</a> }}
      | none => .empty
    if decl.sourceHref?.isNone && decl.provenance.sourcePath?.isNone then .empty
    else
      {{
        <div class="bp_node_page_source">
          <style>{{.text false nodeSourceCss}}</style>
          {{viewSrc}}
          {{openEd}}
        </div>
      }}

open Verso.Output.Html in
/--
Render the per-node metrics line (depth / height / fan-in / fan-out and a
critical-path badge) from the computed `NodeMetrics`, with the inline stylesheet.
-/
private def renderNodeMetrics (metrics? : Option Informal.GraphMetrics.NodeMetrics) : Output.Html :=
  match metrics? with
  | none => .empty
  | some m =>
    let metric (name : String) (value : Nat) : Output.Html := {{
        <span class="bp_node_metric">
          {{.text true name}}" "<span class="bp_node_metric_value">{{.text true (toString value)}}</span>
        </span>
      }}
    let criticalBadge : Output.Html :=
      if m.onCriticalPath then
        {{ <span class="bp_node_metric bp_node_metric_critical">"On critical path"</span> }}
      else .empty
    {{
      <div class="bp_node_metrics" role="group" aria-label="Graph metrics">
        <style>{{.text false nodeMetricsCss}}</style>
        {{metric "Depth" m.depth}}
        {{metric "Height" m.height}}
        {{metric "Fan-in" m.fanIn}}
        {{metric "Fan-out" m.fanOut}}
        {{criticalBadge}}
      </div>
    }}

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
  -- Match the chapter-page render config: also surface Lean const → blueprint-node
  -- cross-links in code rendered on the static (node / worklist / owner / tag) pages.
  let linkTargets :=
    state.localTargets ++ remotes.remoteTargets ++ Informal.NodeRoute.blueprintNodeTargets state
  -- Rebuild the sidebar ToC in the full Manual HTML-emit monad stack.
  let tocAction :
      StateT (State Output.Html)
        (ReaderT Verso.Multi.AllRemotes (ReaderT ExtensionImpls (Verso.BuildLogT IO)))
        (List Html.Toc) :=
    text.subParts.toList.mapM fun p =>
      Verso.Genre.Manual.toc cfg.htmlDepth opts (ctxt.inPart p) state definitionIds linkTargets p
  let (sidebarToc, _) ←
    tocAction.run {} |>.run remotes |>.run extensionImpls |>.run logger
  -- Match the chapter-page header band exactly: core `emitContent` shows the
  -- book's `shortTitle` as the header/ToC title when present, falling back to the
  -- full title. Mirror that here so the static (node / worklist / owner / tag /
  -- audit / mathlib-candidates) pages carry the *same* header title, not the raw
  -- full title.
  let bookTitle : Output.Html :=
    match text.metadata.bind (·.shortTitle) with
    | some short => .text true short
    | none => .text true text.titleString
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
    (metrics? : Option Informal.GraphMetrics.NodeMetrics)
    (htmlIndex : Informal.PreviewManifest.HtmlCache.Index)
    (manifestIndex : Informal.PreviewManifest.Index)
    (editorTemplate : String)
    (bookTitle : String)
    (entry0 : Entry) : Output.Html :=
  let entry := repointEntryRelations state entry0
  -- Statement block (with uses/usedBy/group panels + Lean-code panel).
  let stmtHtml := (htmlIndex.findHtml? entry.key).getD ""
  -- Deduplicate the Lean-code preview fragments by rendered HTML (mirrors the
  -- chapter/graft path `HtmlCache.Index.codeHtmlBodies`). A raw
  -- `leanCodePreviewKeys.filterMap findHtml?` can list the same rendered code
  -- twice when several preview keys resolve to one fragment, which made the
  -- "Lean code for …" panel render the code block twice on node pages.
  let codeHtmls := htmlIndex.codeHtmlBodies entry
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
      let proofCode := htmlIndex.codeHtmlBodies proofEntry
      Informal.PreviewManifest.BlockRender.renderWithRenderedContent {} proofEntry
        (Informal.PreviewManifest.BlockRender.RenderedContent.ofHtmlStrings proofHtml proofCode)
    | none => .empty
  -- Downstream-impact panel: the entries that (transitively) depend on this one,
  -- restricted to those with their own node page so every item is clickable.
  let descendantSet := master.descendants entry.label
  let downstreamLabels :=
    descendantSet.toList.filter (fun l => Informal.NodeRoute.hasNodePage state l)
  let downstreamPanel : Output.Html :=
    if downstreamLabels.isEmpty then .empty
    else
      let titleOf := fun (l : Name) =>
        match master.nodes.find? (fun n => n.label == l) with
        | some n => if n.title.isEmpty then l.toString else n.title
        | none => l.toString
      let items := downstreamLabels.toArray.map fun l =>
        {{ <li><a href={{Informal.NodeRoute.nodePageHref l}}>{{.text true (titleOf l)}}</a></li> }}
      {{
        <section class="bp_node_page_downstream">
          <style>{{.text false nodeDownstreamCss}}</style>
          <h2>"Downstream impact"</h2>
          <p class="bp_node_downstream_count">
            {{.text true s!"{downstreamLabels.length} entries depend on this."}}
          </p>
          <ul class="bp_node_downstream_list">{{items}}</ul>
        </section>
      }}
  -- Localized dependency graph: this node ∪ all ancestors ∪ all descendants.
  let labelSet : Lean.NameSet :=
    let base := (master.ancestors entry.label).insert entry.label
    descendantSet.toList.foldl (·.insert ·) base
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
  let parentContext : Output.Html :=
    match entry.parentTitle with
    | some pt => {{ <p class="bp_node_page_group">"Part of: " {{.text true pt}}</p> }}
    | none => .empty
  -- Breadcrumb trail: Book › Chapter › this node. The chapter name is derived
  -- from the chapter slug in the entry's in-chapter href, and the chapter crumb
  -- links to the precise statement anchor (folding in "View in chapter context").
  let sep : Output.Html := {{ <span class="bp_node_breadcrumb_sep">"›"</span> }}
  let bookCrumb : Output.Html :=
    if bookTitle.isEmpty then .empty
    else {{ <a href="">{{.text true bookTitle}}</a> }}
  let chapterName : String :=
    match entry.href with
    | some href => ((href.splitOn "/").headD "").replace "-" " "
    | none => ""
  let chapterCrumb : Output.Html :=
    if chapterName.isEmpty then .empty
    else
      match backHref? with
      | some href => {{ {{sep}} <a href={{href}}>{{.text true chapterName}}</a> }}
      | none => {{ {{sep}} <span>{{.text true chapterName}}</span> }}
  let breadcrumb : Output.Html :=
    {{
      <nav class="bp_node_breadcrumb" aria-label="Breadcrumb">
        {{bookCrumb}}
        {{chapterCrumb}}
        {{sep}}
        <span class="bp_node_breadcrumb_current">{{.text true entry.title}}</span>
      </nav>
    }}
  let copyLink : Output.Html :=
    {{
      <button type="button" class="bp-permalink-button" data-bp-permalink=""
          data-bp-label="Copy link" aria-label="Copy a link to this page">
        "Copy link"
      </button>
    }}
  {{
    <div class="bp_node_page">
      <header class="bp_node_page_header">
        <style>{{.text false nodeBreadcrumbCss}}</style>
        <div class="bp_node_page_topbar">
          {{breadcrumb}}
          {{copyLink}}
        </div>
        <h1>{{.text true entry.title}}</h1>
        {{parentContext}}
        {{renderNodeSource editorTemplate entry}}
        {{renderNodeMetrics metrics?}}
      </header>
      <section class="bp_node_page_statement">{{statementBlock}}</section>
      <section class="bp_node_page_proof">{{proofBlock}}</section>
      {{downstreamPanel}}
      <section class="bp_node_page_graph">
        <h2>"Local dependency graph"</h2>
        {{graphHtml}}
      </section>
    </div>
  }}

/-! ## Offline full-text statement search index -/

/--
Decode the small set of HTML entities the cached statement fragments actually
emit (Verso escapes `<`, `>`, `&`, `"`, and numeric `&#39;`/`&#x27;` for quotes).
Kept intentionally small: this feeds a plain-text search index, not a renderer.
-/
private def decodeHtmlEntities (s : String) : String :=
  s.replace "&lt;" "<"
    |>.replace "&gt;" ">"
    |>.replace "&quot;" "\""
    |>.replace "&#39;" "'"
    |>.replace "&#x27;" "'"
    |>.replace "&nbsp;" " "
    |>.replace "&amp;" "&"

/--
Strip HTML tags from a cached statement fragment and normalize whitespace to a
compact, readable plain-text string for the search index. Math is authored as
raw TeX inside `<code class="bp_math">` (rendered client-side by KaTeX), so the
stripped text keeps the searchable TeX source. Truncates to keep the index slim.
-/
private def htmlToSearchText (html : String) : String := Id.run do
  let mut out := ""
  let mut depth : Nat := 0
  let mut pendingSpace := false
  let mut count : Nat := 0
  let mut truncated := false
  for c in html.toList do
    if c == '<' then
      depth := depth + 1
    else if c == '>' then
      if depth > 0 then depth := depth - 1
    else if depth == 0 then
      if c == ' ' || c == '\n' || c == '\t' || c == '\r' then
        -- Collapse runs of whitespace; never start the string with a space.
        if !out.isEmpty then pendingSpace := true
      else
        -- Keep the index small: cap each entry's body text.
        if count ≥ 600 then
          truncated := true
          break
        if pendingSpace then
          out := out.push ' '
          count := count + 1
          pendingSpace := false
        out := out.push c
        count := count + 1
  let decoded := decodeHtmlEntities out
  if truncated then decoded ++ "…" else decoded

/--
Human-readable chapter name for a node's search entry, derived from the chapter
slug embedded in the manifest entry's in-chapter `href`
(e.g. `The-Noperthedron/#…` → `The Noperthedron`). Degrades to the empty string.
-/
private def chapterNameOf (entry : Entry) : String :=
  match entry.href with
  | none => ""
  | some href =>
    let slug := (href.splitOn "/").headD ""
    slug.replace "-" " "

/--
Build one slim search record per node page: `{label, display, kind, chapter,
href, text}` where `text` is the plain-text informal statement. Same-origin,
self-contained; consumed lazily by `Commands/command-palette.mjs`.
-/
private def nodeSearchRecord (htmlIndex : Informal.PreviewManifest.HtmlCache.Index)
    (entry : Entry) : Json :=
  let stmtHtml := (htmlIndex.findHtml? entry.key).getD ""
  let text := htmlToSearchText stmtHtml
  let kind := match entry.kind with | some k => toString k | none => ""
  Json.mkObj [
    ("label", Json.str entry.label.toString),
    ("display", Json.str entry.title),
    ("kind", Json.str kind),
    ("chapter", Json.str (chapterNameOf entry)),
    ("href", Json.str (Informal.NodeRoute.nodePageHref entry.label)),
    ("text", Json.str text)
  ]

/-- Write the offline node-search index into the output `-verso-data` dir. -/
private def writeNodeSearchIndex (mode : Manual.Mode) (cfg : Manual.Config)
    (records : Array Json) : IO Unit := do
  let outDir := cfg.destination.join
    (match mode with | .single => "html-single" | .multi => "html-multi")
  let dataDir := outDir.join "-verso-data"
  IO.FS.createDirAll dataDir
  IO.FS.writeFile (dataDir.join "node-search.json") ((Json.arr records).compress ++ "\n")

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
      -- Compute graph metrics once for the whole master graph; node pages look
      -- up their own metrics by label (Feature 4).
      let metrics := Informal.GraphMetrics.computeGraphMetrics master
      -- Editor URL template for the node-header "Open in editor" link. Configured
      -- via the `BLUEPRINT_EDITOR_URL_TEMPLATE` env var (`{path}`/`{line}`
      -- placeholders); defaults to a VS Code deep link; set empty to disable.
      let editorTemplate := (← IO.getEnv "BLUEPRINT_EDITOR_URL_TEMPLATE").getD "vscode://file{path}:{line}"
      let mut usedSlugs : Std.HashSet String := {}
      let mut searchRecords : Array Json := #[]
      for entry in files.manifest.blockStatementEntries do
        let slug := Informal.NodeRoute.nodePageSlug entry.label
        if usedSlugs.contains slug then
          logError <|
            s!"Blueprint node pages: slug collision for {entry.label} (slug {slug}); " ++
            "node page may overwrite another node's page"
        usedSlugs := usedSlugs.insert slug
        let body :=
          renderNodePageBody state master (metrics.find? entry.label) htmlIndex manifestIndex
            editorTemplate text.titleString entry
        emitStaticBlueprintPage mode cfg state text
          (Informal.NodeRoute.nodePagePath entry.label) entry.title body
        searchRecords := searchRecords.push (nodeSearchRecord htmlIndex entry)
      -- Emit the slim offline full-text statement search index (one entry per
      -- node page) alongside the pages themselves.
      writeNodeSearchIndex mode cfg searchRecords

end Informal.NodePage
