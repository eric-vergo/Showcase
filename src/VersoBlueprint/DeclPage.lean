/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Std.Data.HashMap
import Std.Data.HashSet
import VersoBlueprint.NodePage
import VersoBlueprint.NodeRoute
import VersoBlueprint.NodeCard
import VersoBlueprint.DeclRegistry
import VersoBlueprint.Informal.CodeSummary

/-!
Per-declaration pages: one standalone page (`decl/<slug>/index.html`) for every
**unwired** registry declaration, so every row in the catalog pages and every
supporting node on the all-declarations graph links somewhere. Wired
declarations' canonical page stays their node page — no duplicate pages.

Each page reuses the node-page chrome and card family: a breadcrumb
(Book › Modules › module › shortName), the standard two-column `NodeCard` with the
declaration's docstring (or a quiet placeholder when it has none) on the informal
statement side and the highlighted signature + captured `:= …` proof/value body on
the formal side, and a localized dependency graph synthesized from the registry's
`statementDeps`/`proofDeps`/`usedBy` edges (quietly absent for `private`
declarations — which stay out of every graph — and for empty neighborhoods). Source
link / uses / used-by are intentionally NOT on the page: the always-open properties
rail owns them (the card's `bp-decl-meta` payload selects the declaration on load);
the docstring is shown in both, which is intentional so the page is self-contained.

`emitBlueprintDeclPages` is the generation-time `ExtraStep` (registered in
`Main.lean` after the catalog pages): it reads the registry and the internal
proof/value bodies from the traversal store (`TraversalIndex.DeclRegistry`), so
no environment is needed at generation time, and emits nothing when the registry
is absent (the `includeAllDecls` flag is off) — the same opt-in discipline as
the catalog pages. It also writes `-verso-data/decl-search.json` (mirroring the
node-search index) so the command palette finds the new pages.
-/

namespace Informal.DeclPage

open Lean
open Verso Verso.Output Verso.Doc
open Verso.Genre Manual
open Verso.Output.Html
open Informal.DeclRegistry (Entry Registry Body Bodies)

/-- Extra styling for decl pages: the muted fully-qualified-name subtitle under
the clean card header. Design tokens only, so light + dark come for free. -/
def declPageCss : String := r##"
.bp_decl_page_fq {
  margin-top: var(--bp-space-1);
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-caption, 0.78rem);
  font-style: normal;
  font-weight: 400;
  color: var(--bp-color-text-muted);
  overflow-wrap: anywhere;
}

/* Quiet provenance marker for the informal-statement cell: notes that the shown
   prose is derived from the declaration's docstring. A restrained hairline chip in
   the status-dot register (small, muted); tokens only, so both themes come for
   free. */
.bp_decl_provenance {
  display: inline-flex;
  align-items: center;
  margin-top: var(--bp-space-3);
  padding: 0.05rem var(--bp-space-2);
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-pill);
  font-size: var(--bp-fs-badge, 0.72rem);
  line-height: 1.5;
  color: var(--bp-color-text-faint);
}
"##

/-- Short display name for a registry entry (falls back to the FQ name). -/
private def displayShort (e : Entry) : String :=
  if e.shortName.isEmpty then e.name else e.shortName

/-- Hover/tooltip text for a registry status tag (mirrors the status-dot aria
vocabulary; the tag itself drives the dot color via CSS). Complete definitions
read "Formalized"; complete theorem-likes read "Proved". -/
private def statusTitle (kind status : String) : String :=
  if kind == "Definition" && status == "proved" then "Formalized"
  else match status with
    | "proved" => "Proved"
    | "containsSorry" => "Contains sorry"
    | "axiomLike" => "Axiom-like"
    | "missing" => "Missing declaration"
    | other => other

/-- Registry kind string → blueprint node kind (defaults to `theorem`). -/
private def nodeKindOf (kind : String) : Informal.Data.NodeKind :=
  match kind with
  | "Definition" => .definition
  | "Proposition" => .proposition
  | "Lemma" => .lemma
  | "Corollary" => .corollary
  | _ => .theorem

/-- Clean decl-page card header: kind caption + short name + status dot, with the
fully-qualified name as a muted subtitle (only when it differs) and on `title`. -/
private def cardHeader (e : Entry) : Html :=
  let short := displayShort e
  let fqSubtitle : Html :=
    if short == e.name then .empty
    else {{ <div class="bp_decl_page_fq" title={{e.name}}>{{.text true e.name}}</div> }}
  {{
    <div class="bp_heading bp_decl_page_heading">
      <div class="bp_heading_title_row bp_heading_title_row_statement">
        <span class="bp_caption" title={{e.name}}>{{.text true e.kind}}</span>
        <span class="bp_label">{{.text true short}}</span>
        {{Informal.CodeSummary.statusDotHtmlOfTag e.status (statusTitle e.kind e.status)
            (kind? := some (nodeKindOf e.kind))}}
      </div>
      {{fqSubtitle}}
    </div>
  }}

/-- The formal statement cell: the registry's highlighted signature markup when
available (for `private` declarations this is the syntactic type highlight — the
`_private.…` mangling never reaches the page), degrading to an escaped `<pre>`
of the pretty-printed type. -/
private def signatureCell (e : Entry) : Html :=
  let marker := Informal.NodeCard.tierMarker e.sigTier?
  match e.signatureHtml? with
  | some inner =>
    {{ <pre class="bp_external_decl_signature signature hl lean block">{{marker}}{{Html.text false inner}}</pre> }}
  | none =>
    {{ <pre class="bp_external_decl_signature signature">{{marker}}{{Html.text true e.signatureText}}</pre> }}

/-- Quiet provenance marker shown under the informal-statement prose: notes that
it is derived from the declaration's docstring. -/
private def provenanceMarker (source label : String) : Html :=
  {{ <div class="bp_decl_provenance" "data-source"={{source}}>{{.text true label}}</div> }}

/-- Informal-statement cell for a decl page: the declaration's docstring (rendered
to markdown + math HTML in the registry, raw HTML disabled) wrapped as prose with a
quiet provenance marker, else `.empty` so the card falls through to the quiet "No
informal statement yet." placeholder. Wired only to the statement facet — the
informal *proof* is never synthesized (there is no informal-proof source for a bare
declaration), so proof rows keep their placeholder. The docstring is also shown in
the properties rail; the duplication is intentional so each decl page is
self-contained. -/
private def informalStmtCell (e : Entry) : Html :=
  match e.docstringHtml? with
  | some html =>
    Html.seq #[
      {{ <div class="bp_content bp_decl_docstring">{{Html.text false html}}</div> }},
      provenanceMarker "docstring" "From docstring"
    ]
  | none => .empty

/-- Build the two-column card parts for one unwired registry declaration: the
docstring (when present) or a quiet placeholder on the informal side, signature +
captured proof/value body on the formal side, and the slim `bp-decl-meta` payload
(short name + own decl-page href) so the properties rail selects the declaration on
page load. -/
private def declCardParts (bodies : Std.HashMap String Body)
    (e : Entry) (slug : String) :
    Informal.NodeCard.Parts :=
  let short := displayShort e
  let isDefinition := e.kind == "Definition"
  let formalBody : Html :=
    match bodies.get? e.name with
    | some b =>
      Informal.NodeCard.formalSourceBody #[(b.html?, b.text?, e.proofTier?)]
        (assignPrefix := isDefinition)
    | none => .empty
  let shortName? := if short == e.name then none else some short
  let metaJson := Informal.NodeCard.declMetaJson e.name e.kind e.status e.moduleName
    s!"{e.kind} {short}" (e.range?.map (·.pos.line)) (e.range?.map (·.endPos.line))
    none (shortName := shortName?) (declHref := e.declHref?)
  {
    cardId := s!"bp-card-decl-{slug}"
    isTheoremLike := !isDefinition
    header := cardHeader e
    informalStmt := informalStmtCell e
    formalStmt := signatureCell e
    formalBody
    declName? := some e.name
    declMetaJson? := some metaJson
  }

/--
Synthesize the project declaration graph from registry edges (the render-time
all-decls graph never reaches generation time, so this is rebuilt from
`statementDeps`/`proofDeps`). Nodes are the **public** entries only (`private`
declarations stay out of every graph); each links to its canonical page (node
page when wired, decl page otherwise) and reuses the muted supporting visual.
-/
private def registryGraph (entries : Array Entry) : Informal.Graph.GraphData := Id.run do
  let pub := entries.filter (fun e => !e.isPrivate)
  let names : Std.HashSet String := pub.foldl (fun s e => s.insert e.name) {}
  let autoRefs := fun (deps : Array String) =>
    deps.foldl (init := (#[] : Array Informal.Data.UseRef)) fun acc d =>
      if names.contains d && !acc.any (fun u => (u.label : Name) == d.toName) then
        acc.push { label := (d.toName : Informal.Data.Label), origin := .automatic }
      else acc
  let nodes := pub.map fun e =>
    let node := Informal.Graph.mkSupportingNodeData (nodeKindOf e.kind) e.name.toName
      (autoRefs e.statementDeps) (autoRefs e.proofDeps)
    { node with
        href := e.nodeHref? <|> e.declHref?
        title := displayShort e }
  let data : Informal.Graph.GraphData := { key := "decl-local", nodes }
  return { data with edges := Informal.Graph.edgesForGraph data.toGraph }

open Verso.Output.Html in
/-- Assemble the body of one decl page: breadcrumb + copy-link topbar, the
two-column card, and the localized dependency graph (ancestors ∪ self ∪
descendants over the registry graph; quietly absent for private declarations
and single-node neighborhoods — the same section structure as node pages). -/
private def renderDeclPageBody (master : Informal.Graph.GraphData)
    (bodies : Std.HashMap String Body)
    (bookTitle : String) (e : Entry) (slug : String) :
    Output.Html :=
  let short := displayShort e
  let card := Informal.NodeCard.render (declCardParts bodies e slug) {}
  let graphSection : Output.Html :=
    if e.isPrivate then .empty
    else
      let nm := e.name.toName
      let descendantSet := master.descendants nm
      let labelSet : Lean.NameSet :=
        let base := (master.ancestors nm).insert nm
        descendantSet.toList.foldl (·.insert ·) base
      let sub := master.restrictTo labelSet
      if sub.nodes.size ≤ 1 then .empty
      else
        let localVariant : Informal.Graph.GraphRenderVariant := {
          key := "local"
          label := "Local dependencies"
          dot := sub.toDotWith
        }
        {{
          <section class="bp_node_page_graph">
            <h2>"Local dependency graph"</h2>
            {{Informal.Commands.renderGraphFullwidth sub #[localVariant] {}
                s!"bp-decl-graph-{slug}" (static := true) (zoomControls := true)}}
          </section>
        }}
  let sep : Output.Html := {{ <span class="bp_node_breadcrumb_sep">"›"</span> }}
  let bookCrumb : Output.Html :=
    if bookTitle.isEmpty then .empty
    else {{ <a href="">{{.text true bookTitle}}</a> }}
  let breadcrumb : Output.Html :=
    {{
      <nav class="bp_node_breadcrumb" aria-label="Breadcrumb">
        {{bookCrumb}}
        {{sep}}
        <a href={{Informal.NodeRoute.modulesHref}}>"Modules"</a>
        {{sep}}
        <span>{{.text true e.moduleName}}</span>
        {{sep}}
        <span class="bp_node_breadcrumb_current">{{.text true short}}</span>
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
    <div class="bp_node_page bp_decl_page">
      <header class="bp_node_page_header">
        <style>{{.text false (Informal.NodePage.nodeBreadcrumbCss ++ declPageCss)}}</style>
        <div class="bp_node_page_topbar">
          {{breadcrumb}}
          {{copyLink}}
        </div>
      </header>
      <section class="bp_node_page_statement bp_node_page_card2">{{card}}</section>
      {{graphSection}}
    </div>
  }}

/-- One palette search record per decl page (mirrors the node-search shape:
`{label, display, kind, chapter, href, text}` with the module as the "chapter"
and the truncated type signature as the searchable text). -/
private def declSearchRecord (e : Entry) (pfx : String) : Json :=
  Json.mkObj [
    ("label", Json.str e.name),
    ("display", Json.str (displayShort e)),
    ("kind", Json.str e.kind),
    ("chapter", Json.str (Informal.NodeCard.shortModuleName pfx e.moduleName)),
    ("href", Json.str (Informal.NodeRoute.declPageHref e.name)),
    ("text", Json.str ((e.signatureText.take 300).toString))
  ]

/-- Write the offline decl-search index into the output `-verso-data` dir. -/
private def writeDeclSearchIndex (mode : Manual.Mode) (cfg : Manual.Config)
    (records : Array Json) : IO Unit := do
  let outDir := cfg.destination.join
    (match mode with | .single => "html-single" | .multi => "html-multi")
  let dataDir := outDir.join "-verso-data"
  IO.FS.createDirAll dataDir
  IO.FS.writeFile (dataDir.join "decl-search.json") ((Json.arr records).compress ++ "\n")

/--
`ExtraStep` that emits one page per **unwired** registry declaration into
`decl/<slug>/index.html`, plus the `decl-search.json` palette index.

Self-contained: it reads only the traversal-store registry / bodies / prefix (no
environment at generation time), so it is order-independent relative to the
preview-data / node-page / catalog steps. Single-page mode is skipped; when no
registry was stored (the `includeAllDecls` flag is off) it emits nothing —
consumers without the flag see no new pages and no change.
-/
def emitBlueprintDeclPages : ExtraStep :=
  fun mode cfg state text => do
    match mode with
    | .single => pure ()
    | .multi =>
      let logger : Verso.Logger IO ← read
      match Informal.TraversalIndex.DeclRegistry.raw? state with
      | none => pure ()
      | some raw =>
        match (do let j ← Json.parse raw; (FromJson.fromJson? j : Except String Registry)) with
        | .error e =>
          logger.reportWarning
            s!"Showcase decl pages: could not parse decl-registry.json ({e}); \
               skipping the decl/ pages."
        | .ok registry =>
          -- Internal proof/value bodies (may be absent; pages degrade to the
          -- quiet formal-proof placeholder).
          let bodies : Std.HashMap String Body :=
            match Informal.TraversalIndex.DeclRegistry.bodiesRaw? state with
            | none => {}
            | some bodiesRaw =>
              match (do
                  let j ← Json.parse bodiesRaw
                  (FromJson.fromJson? j : Except String Bodies)) with
              | .error _ => {}
              | .ok bs => bs.bodies.foldl (fun m b => m.insert b.name b) {}
          let entries := registry.decls
          let master := registryGraph entries
          let mut usedSlugs : Std.HashSet String := {}
          let mut searchRecords : Array Json := #[]
          for e in entries do
            -- Wired declarations keep their node page as the canonical page.
            if e.declHref?.isNone then continue
            let slug := Informal.NodeRoute.declPageSlug e.name
            if usedSlugs.contains slug then
              logger.reportError <|
                s!"Showcase decl pages: slug collision for {e.name} (slug {slug}); " ++
                "decl page may overwrite another declaration's page"
            usedSlugs := usedSlugs.insert slug
            let body := renderDeclPageBody master bodies text.titleString e slug
            Informal.NodePage.emitStaticBlueprintPage mode cfg state text
              (Informal.NodeRoute.declPagePath e.name) (displayShort e) body
            searchRecords := searchRecords.push (declSearchRecord e registry.namePrefix)
          writeDeclSearchIndex mode cfg searchRecords

end Informal.DeclPage
