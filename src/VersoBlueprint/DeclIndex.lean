/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Std.Data.HashSet
import VersoBlueprint.NodePage
import VersoBlueprint.NodeRoute
import VersoBlueprint.NodeCard
import VersoBlueprint.DeclRegistry

/-!
Declaration-catalog pages: `Definitions`, `Theorems`, an alphabetical `Index`, and
a `Modules` source-tree, each covering **every** in-project declaration (wired or
not) from the all-declarations registry (`DeclRegistry`).

`emitBlueprintDeclIndexPages` is the `ExtraStep` that reads the compressed registry
JSON carried through traversal state (`TraversalIndex.DeclRegistry.raw?`, populated
at elaboration time when `verso.blueprint.graph.includeAllDecls` is on), parses it,
and renders four standalone pages via the shared `NodePage.emitStaticBlueprintPage`
chrome — no environment access is needed at generation time.

Every row is selection-bus wired the same way node cards are (Wave 4): it carries
`data-bp-decl` plus a slim inline `<script class="bp-decl-meta">` identity payload
(via `NodeCard.declMetaJson`), so a click / focus updates the site-wide metadata
rail (see `Commands/metadata-rail.mjs`, whose delegated selection handler matches
`.bp_decl_row`). Every row links somewhere: wired declarations to their node page,
unwired ones to their own `decl/{slug}/` page (`DeclPage`). Names display as the
registry's prefix-stripped `shortName` with the fully-qualified name on hover.

If the registry is absent (the flag is off, or no authored declaration has a
resolvable project source) the step emits nothing and changes nothing — the same
opt-in discipline as the all-declarations graph.
-/

namespace Informal.DeclIndex

open Lean
open Verso Verso.Output Verso.Doc
open Verso.Genre Manual
open Verso.Output.Html
open Informal.DeclRegistry (Entry Registry)

/-! ## Shared styling (inlined once per catalog page body) -/

/-- Stylesheet for the catalog pages. Design tokens only (`--bp-space-*`,
`--bp-radius-*`, `--bp-fs-*`, `--bp-color-*`), so light + dark and AA contrast come
for free from the four scheme blocks in `Commands/Common.lean`. -/
def catalogCss : String := r##"
.bp_decl_catalog { }

.bp_decl_catalog_intro {
  margin: 0 0 var(--bp-space-4);
  color: var(--bp-color-text-muted);
}

.bp_decl_catalog_intro strong { color: var(--bp-color-text-strong); font-weight: 700; }

/* ---- A-Z jump bar (alphabetical index) ------------------------------------ */
.bp_decl_letterbar {
  position: sticky;
  top: calc(var(--verso-header-height, 3rem) + var(--bp-space-1));
  z-index: 5;
  display: flex;
  flex-wrap: wrap;
  gap: var(--bp-space-1);
  margin: 0 0 var(--bp-space-4);
  padding: var(--bp-space-2);
  background: var(--bp-color-surface);
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-md);
}

.bp_decl_letterbar a {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 1.5rem;
  height: 1.5rem;
  padding: 0 var(--bp-space-1);
  border-radius: var(--bp-radius-sm);
  color: var(--bp-color-link);
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-caption, 0.78rem);
  font-weight: 700;
  text-decoration: none;
}

.bp_decl_letterbar a:hover { background: var(--bp-color-surface-subtle); }
.bp_decl_letterbar a:focus-visible { outline: 2px solid var(--bp-color-accent); outline-offset: 1px; }

/* ---- Module group + letter section headings ------------------------------- */
.bp_decl_module_group { margin: 0 0 var(--bp-space-5); }

.bp_decl_module_head {
  display: flex;
  align-items: baseline;
  gap: var(--bp-space-2);
  margin: 0 0 var(--bp-space-2);
  padding-bottom: var(--bp-space-1);
  border-bottom: 1px solid var(--bp-color-border-soft);
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-control, 0.82rem);
  font-weight: 700;
  color: var(--bp-color-text-strong);
  letter-spacing: 0;
}

.bp_decl_letter_head {
  scroll-margin-top: calc(var(--verso-header-height, 3rem) + 3rem);
  margin: var(--bp-space-4) 0 var(--bp-space-2);
  font-size: 1.1rem;
  color: var(--bp-color-text-strong);
}

.bp_decl_module_count {
  display: inline-flex;
  align-items: center;
  padding: 0.05rem 0.45rem;
  border-radius: var(--bp-radius-pill);
  background: var(--bp-color-surface-subtle);
  border: 1px solid var(--bp-color-border);
  color: var(--bp-color-text-muted);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 600;
}

/* ---- Row list ------------------------------------------------------------- */
.bp_decl_list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
}

.bp_decl_row {
  display: flex;
  align-items: baseline;
  gap: var(--bp-space-2) var(--bp-space-3);
  padding: var(--bp-space-2);
  border-radius: var(--bp-radius-sm);
  border-bottom: 1px solid var(--bp-color-border-soft);
}

.bp_decl_row:last-child { border-bottom: 0; }
.bp_decl_row:hover { background: var(--bp-color-surface-subtle); }

.bp_decl_row_kind {
  flex: 0 0 auto;
  display: inline-flex;
  align-items: center;
  min-width: 2.5rem;
  justify-content: center;
  padding: 0.05rem 0.4rem;
  border-radius: var(--bp-radius-sm);
  border: 1px solid var(--bp-color-border);
  background: var(--bp-color-surface-subtle);
  color: var(--bp-color-text-muted);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.bp_decl_row_kind[data-kind="Definition"] {
  color: var(--bp-color-accent);
  border-color: var(--bp-color-accent);
  background: transparent;
}

.bp_decl_row_name {
  flex: 0 1 auto;
  min-width: 0;
  max-width: 24rem;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-control, 0.82rem);
  font-weight: 600;
  color: var(--bp-color-link);
  text-decoration: none;
}

a.bp_decl_row_name:hover { text-decoration: underline; }

/* The unwired-row select control is a real button; strip the native chrome so it
   reads like the wired link but stays keyboard-operable. */
button.bp_decl_row_name {
  border: 0;
  background: transparent;
  padding: 0;
  cursor: pointer;
  color: var(--bp-color-text-strong);
  text-align: left;
  -webkit-appearance: none;
  appearance: none;
}

button.bp_decl_row_name:hover { color: var(--bp-color-text); text-decoration: underline; }
.bp_decl_row_name:focus-visible { outline: 2px solid var(--bp-color-accent); outline-offset: 2px; border-radius: 2px; }

.bp_decl_row_sig {
  flex: 1 1 auto;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-small, 0.8rem);
  color: var(--bp-color-text-muted);
}

.bp_decl_row_module {
  flex: 0 0 auto;
  margin-left: auto;
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-badge, 0.72rem);
  color: var(--bp-color-text-subtle);
  white-space: nowrap;
}

.bp_decl_row_status {
  flex: 0 0 auto;
  display: inline-flex;
  align-items: center;
  padding: 0.05rem 0.45rem;
  border-radius: var(--bp-radius-pill);
  border: 1px solid var(--bp-color-border);
  background: var(--bp-color-surface-subtle);
  color: var(--bp-color-text-muted);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.03em;
  white-space: nowrap;
}

.bp_decl_row_status[data-status="proved"] {
  color: var(--bp-color-status-success-text);
  border-color: var(--bp-color-status-warning-border-soft);
}

.bp_decl_row_status[data-status="containsSorry"],
.bp_decl_row_status[data-status="missing"],
.bp_decl_row_status[data-status="axiomLike"] {
  color: var(--bp-color-status-warning-text);
  border-color: var(--bp-color-status-warning-border-soft);
}

.bp_decl_row_open {
  flex: 0 0 auto;
  display: inline-flex;
  align-items: center;
  color: var(--bp-color-text-subtle);
  text-decoration: none;
  padding: 0 0.1rem;
}

.bp_decl_row_open:hover { color: var(--bp-color-accent); }

/* ---- Module tree ---------------------------------------------------------- */
.bp_mod_tree { margin: 0; }

details.bp_mod_node {
  margin: 0;
  border-left: 1px solid var(--bp-color-border-soft);
  padding-left: var(--bp-space-3);
}

details.bp_mod_node > .bp_mod_children { margin-top: var(--bp-space-1); }

.bp_mod_summary {
  display: flex;
  align-items: baseline;
  gap: var(--bp-space-2);
  padding: var(--bp-space-1) var(--bp-space-2);
  cursor: pointer;
  border-radius: var(--bp-radius-sm);
  list-style: none;
}

.bp_mod_summary::-webkit-details-marker { display: none; }
.bp_mod_summary:hover { background: var(--bp-color-surface-subtle); }
.bp_mod_summary:focus-visible { outline: 2px solid var(--bp-color-accent); outline-offset: 1px; }

.bp_mod_summary::before {
  content: "▸";
  flex: 0 0 auto;
  color: var(--bp-color-text-faint);
  transition: transform var(--bp-duration-fast, 0.12s) var(--bp-ease, ease);
}

details.bp_mod_node[open] > .bp_mod_summary::before { transform: rotate(90deg); }

@media (prefers-reduced-motion: reduce) {
  .bp_mod_summary::before { transition: none; }
}

.bp_mod_name {
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-control, 0.82rem);
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_mod_count {
  display: inline-flex;
  align-items: center;
  padding: 0.05rem 0.4rem;
  border-radius: var(--bp-radius-pill);
  background: var(--bp-color-surface-subtle);
  border: 1px solid var(--bp-color-border);
  color: var(--bp-color-text-muted);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 600;
}

.bp_mod_decls { padding-left: var(--bp-space-2); }

/* ---- Narrow viewports: drop the secondary columns ------------------------- */
@media (max-width: 700px) {
  .bp_decl_row_sig,
  .bp_decl_row_module { display: none; }
  .bp_decl_row_name { max-width: none; }
}
"##

/-! ## Row + section rendering -/

/-- Two-letter kind abbreviation for the leading badge. -/
private def kindShort (kind : String) : String :=
  if kind == "Definition" then "def" else "thm"

/-- Compact status label for the trailing badge. Complete definitions read
"Formalized"; complete theorem-likes read "Proved". -/
private def statusLabel (kind status : String) : String :=
  if kind == "Definition" && status == "proved" then "Formalized"
  else match status with
    | "proved" => "Proved"
    | "containsSorry" => "Sorry"
    | "missing" => "Missing"
    | "axiomLike" => "Axiom"
    | other => other

/-- Short display name for a registry row (falls back to the FQ name for
registries predating the `shortName` field). -/
private def displayName (e : Entry) : String :=
  if e.shortName.isEmpty then e.name else e.shortName

/-- Slim `</script>`-safe rail identity payload for a registry row, in the exact
shape the metadata rail expects (see `NodeCard.declMetaJson`). -/
private def rowMeta (e : Entry) : String :=
  let shortName? := if e.shortName.isEmpty || e.shortName == e.name then none else some e.shortName
  Informal.NodeCard.declMetaJson e.name e.kind e.status e.moduleName ""
    (e.range?.map (·.pos.line)) (e.range?.map (·.endPos.line)) e.nodeHref?
    (shortName := shortName?) (declHref := e.declHref?)

/--
One catalog/index row: a selection-bus-wired list item. The declaration name is the
row's single interactive control — a link to the declaration's canonical page (node
page for wired declarations, `decl/{slug}/` page for unwired ones; a plain select
button only for legacy registries with neither href) — so the row is
keyboard-operable with no nested interactives. Displays the short name with the
fully-qualified name as the hover `title`. The whole row is rail-selectable via the
delegated handler in `metadata-rail.mjs` (it matches `.bp_decl_row[data-bp-decl]`
and reads the inline `bp-decl-meta` payload). `showSig` includes the truncated
signature column.
-/
private def declRow (showSig : Bool) (e : Entry) : Html :=
  let metaJson := rowMeta e
  let href? := e.nodeHref? <|> e.declHref?
  let openTitle := if e.nodeHref?.isSome then "Open node page" else "Open declaration page"
  let nameNode : Html :=
    match href? with
    | some href =>
      {{ <a class="bp_decl_row_name" href={{href}} title={{e.name}}>{{.text true (displayName e)}}</a> }}
    | none =>
      {{ <button type="button" class="bp_decl_row_name" title={{e.name}}>{{.text true (displayName e)}}</button> }}
  let sigNode : Html :=
    if showSig && !e.signatureText.isEmpty then
      {{ <code class="bp_decl_row_sig" title={{e.signatureText}}>{{.text true e.signatureText}}</code> }}
    else .empty
  let openLink : Html :=
    match href? with
    | some href =>
      {{ <a class="bp_decl_row_open" href={{href}} title={{openTitle}}
            aria-label={{s!"{openTitle} for {e.name}"}}>"↗"</a> }}
    | none => .empty
  {{
    <li class="bp_decl_row" "data-bp-decl"={{e.name}}>
      <script type="application/json" class="bp-decl-meta" "data-bp-decl"={{e.name}}>{{.text false metaJson}}</script>
      <span class="bp_decl_row_kind" "data-kind"={{e.kind}}>{{.text true (kindShort e.kind)}}</span>
      {{nameNode}}
      {{sigNode}}
      <span class="bp_decl_row_module">{{.text true e.moduleName}}</span>
      <span class="bp_decl_row_status" "data-status"={{e.status}}>{{.text true (statusLabel e.kind e.status)}}</span>
      {{openLink}}
    </li>
  }}

/-! ## Sorting + grouping -/

/-- Unqualified base name (final dotted segment) for alphabetical grouping. -/
private def baseName (fq : String) : String :=
  ((fq.splitOn ".").getLast?).getD fq

/-- First-letter bucket for the alphabetical index (`A`..`Z`, else `#`). -/
private def letterOf (fq : String) : String :=
  match (baseName fq).toList with
  | c :: _ => if c.isAlpha then String.singleton c.toUpper else "#"
  | [] => "#"

/-- Source line of a declaration (1-based), or `0` when its range is unknown. -/
private def sourceLine (e : Entry) : Nat := (e.range?.map (·.pos.line)).getD 0

/-- Entries in source order within a module (by first line, name as tiebreak). -/
private def bySource (es : Array Entry) : Array Entry :=
  es.qsort fun a b =>
    let la := sourceLine a
    let lb := sourceLine b
    if la == lb then a.name < b.name else la < lb

/-- Entries alphabetical by unqualified name (full name as tiebreak). -/
private def byName (es : Array Entry) : Array Entry :=
  es.qsort fun a b =>
    let ka := (baseName a.name).toLower
    let kb := (baseName b.name).toLower
    if ka == kb then a.name < b.name else ka < kb

/-- Distinct module names present, alphabetically. -/
private def modulesSorted (es : Array Entry) : Array String :=
  let names := es.foldl (init := (#[] : Array String)) fun acc e =>
    if acc.contains e.moduleName then acc else acc.push e.moduleName
  names.qsort (· < ·)

/-! ## Definitions / Theorems pages (grouped by module, source order) -/

private def moduleSection (modName : String) (es : Array Entry) : Html :=
  {{
    <section class="bp_decl_module_group">
      <h2 class="bp_decl_module_head">
        {{.text true modName}}
        <span class="bp_decl_module_count">{{.text true (toString es.size)}}</span>
      </h2>
      <ul class="bp_decl_list">{{(bySource es).map (declRow true)}}</ul>
    </section>
  }}

/-- Body shared by the Definitions and Theorems pages: rows grouped by module,
each module in source order. -/
private def catalogBody (title intro : String) (entries : Array Entry) : Html :=
  let sections := (modulesSorted entries).map fun m =>
    moduleSection m (entries.filter (·.moduleName == m))
  {{
    <div class="bp_decl_catalog bp_pm_page">
      <style>{{.text false catalogCss}}</style>
      <header class="bp_node_page_header">
        <h1>{{.text true title}}</h1>
        <p class="bp_decl_catalog_intro">
          <strong>{{.text true (toString entries.size)}}</strong>{{.text true s!" {intro}"}}
        </p>
      </header>
      {{if entries.isEmpty then
          {{<p class="bp_decl_catalog_intro">"No declarations."</p>}}
        else .seq sections}}
    </div>
  }}

/-! ## Alphabetical index page -/

private def indexBody (entries : Array Entry) : Html :=
  let sorted := byName entries
  -- Distinct first letters, in sorted order (matches the sorted rows).
  let letters := sorted.foldl (init := (#[] : Array String)) fun acc e =>
    let l := letterOf e.name
    if acc.contains l then acc else acc.push l
  -- Fragment links must include the page's own route: a bare `#letter-X` resolves
  -- against the page `<base href>` (the site root) and would jump off-page.
  let jumpBar : Html :=
    {{ <nav class="bp_decl_letterbar" aria-label="Jump to letter">
        {{letters.map fun l =>
            {{ <a href={{s!"{Informal.NodeRoute.declIndexHref}#letter-{l}"}}>{{.text true l}}</a> }}}}
      </nav> }}
  let sections := letters.map fun l =>
    let rows := (sorted.filter (fun e => letterOf e.name == l)).map (declRow false)
    {{
      <section class="bp_decl_module_group">
        <h2 class="bp_decl_letter_head" id={{s!"letter-{l}"}}>{{.text true l}}</h2>
        <ul class="bp_decl_list">{{rows}}</ul>
      </section>
    }}
  {{
    <div class="bp_decl_catalog bp_pm_page">
      <style>{{.text false catalogCss}}</style>
      <header class="bp_node_page_header">
        <h1>"Index"</h1>
        <p class="bp_decl_catalog_intro">
          <strong>{{.text true (toString entries.size)}}</strong>
          " declarations, alphabetical. Wired declarations link to their blueprint node; every row is selectable in the properties rail."
        </p>
      </header>
      {{if entries.isEmpty then .empty else jumpBar}}
      {{.seq sections}}
    </div>
  }}

/-! ## Module-tree page -/

/-- A node of the module source tree: its own path segment, the full dotted module
name, the declarations defined directly in it, and its child modules. -/
inductive ModNode where
  | node (segment fullName : String) (decls : Array Entry) (children : Array ModNode)

instance : Inhabited ModNode := ⟨.node "" "" #[] #[]⟩

private def ModNode.segment : ModNode → String | .node s _ _ _ => s
private def ModNode.decls : ModNode → Array Entry | .node _ _ d _ => d
private def ModNode.children : ModNode → Array ModNode | .node _ _ _ c => c

/-- Insert a module's declarations at the tree path `segs` (dotted-name segments),
creating intermediate nodes as needed. -/
private partial def insertModule (forest : Array ModNode) (segs : List String)
    (parentPrefix : String) (decls : Array Entry) : Array ModNode :=
  match segs with
  | [] => forest
  | seg :: rest =>
    let full := if parentPrefix.isEmpty then seg else parentPrefix ++ "." ++ seg
    match forest.findIdx? (fun n => n.segment == seg) with
    | some i =>
      match forest[i]! with
      | .node s fn ds cs =>
        let updated :=
          if rest.isEmpty then ModNode.node s fn (ds ++ decls) cs
          else ModNode.node s fn ds (insertModule cs rest full decls)
        forest.set! i updated
    | none =>
      let child :=
        if rest.isEmpty then ModNode.node seg full decls #[]
        else ModNode.node seg full #[] (insertModule #[] rest full decls)
      forest.push child

/-- Total declarations in a module subtree (own + descendants). -/
private partial def subtreeCount : ModNode → Nat
  | .node _ _ ds cs => ds.size + cs.foldl (fun acc c => acc + subtreeCount c) 0

private partial def renderModNode (n : ModNode) : Html :=
  let sortedChildren := n.children.qsort (fun a b => a.segment < b.segment)
  let childHtml := sortedChildren.map renderModNode
  let declRows := (bySource n.decls).map (declRow false)
  {{
    <details class="bp_mod_node" open="open">
      <summary class="bp_mod_summary">
        <span class="bp_mod_name">{{.text true n.segment}}</span>
        <span class="bp_mod_count">{{.text true (toString (subtreeCount n))}}</span>
      </summary>
      {{if n.decls.isEmpty then .empty
        else {{ <ul class="bp_decl_list bp_mod_decls">{{declRows}}</ul> }}}}
      {{if sortedChildren.isEmpty then .empty
        else {{ <div class="bp_mod_children">{{childHtml}}</div> }}}}
    </details>
  }}

private def modulesBody (entries : Array Entry) : Html :=
  let forest := (modulesSorted entries).foldl (init := (#[] : Array ModNode)) fun f m =>
    let decls := entries.filter (·.moduleName == m)
    insertModule f (m.splitOn ".") "" decls
  let roots := (forest.qsort (fun a b => a.segment < b.segment)).map renderModNode
  {{
    <div class="bp_decl_catalog bp_pm_page">
      <style>{{.text false catalogCss}}</style>
      <header class="bp_node_page_header">
        <h1>"Modules"</h1>
        <p class="bp_decl_catalog_intro">
          <strong>{{.text true (toString entries.size)}}</strong>
          {{.text true s!" declarations across {(modulesSorted entries).size} modules. Expand a module to browse its declarations."}}
        </p>
      </header>
      {{if entries.isEmpty then
          {{<p class="bp_decl_catalog_intro">"No modules."</p>}}
        else {{ <div class="bp_mod_tree">{{roots}}</div> }}}}
    </div>
  }}

/-! ## The ExtraStep -/

/--
`ExtraStep` that emits the four declaration-catalog pages (`defs/`, `theorems/`,
`decl-index/`, `modules/`) from the all-declarations registry carried in traversal
state.

Self-contained: it reads only the compressed registry JSON via
`TraversalIndex.DeclRegistry.raw?`, so it is order-independent relative to the
preview-data / node-page steps. Single-page mode is skipped. When no registry was
stored (the `includeAllDecls` flag is off) it emits nothing — consumers without the
flag see no new pages and no behavior change.
-/
def emitBlueprintDeclIndexPages : ExtraStep :=
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
            s!"Blueprint declaration index: could not parse decl-registry.json ({e}); \
               skipping the defs/theorems/decl-index/modules pages."
        | .ok registry =>
          let entries := registry.decls
          let defs := entries.filter (·.kind == "Definition")
          let thms := entries.filter (·.kind != "Definition")
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            Informal.NodeRoute.defsPath "Definitions"
            (catalogBody "Definitions"
              "definitions, grouped by module (source order). Wired declarations link to their node page." defs)
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            Informal.NodeRoute.theoremsPath "Theorems"
            (catalogBody "Theorems"
              "theorems and lemmas, grouped by module (source order). Wired declarations link to their node page." thms)
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            Informal.NodeRoute.declIndexPath "Index" (indexBody entries)
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            Informal.NodeRoute.modulesPath "Modules" (modulesBody entries)

end Informal.DeclIndex
