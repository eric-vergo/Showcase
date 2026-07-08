/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html
import Lean.Data.Json

/-!
Two-column "node card" renderer (informal prose left ↔ formal Lean right) with a
single per-card proof toggle that hides the proof by default.

This module is the renderer **foundation** only: it owns the card HTML skeleton
and exposes a `css` placeholder. The real card CSS (grid / breakout / collapse
animation / reduced-motion) and the surface wiring land in later waves; nothing
calls `render` yet.

Discipline (see CLAUDE.md):
* the card header is a plain `<div class="bp_card2_header">`, never a bare
  `<header>` — a content `<header>` re-triggers the fixed site-banner CSS.
* SubVerso classification / Verso presentation split is unaffected here.
-/

namespace Informal.NodeCard

open Verso.Output
open Verso.Output.Html

/--
Informal proof-row content for a node card.

The strict 2×2 grid pairs the informal proof prose (left) with the formal Lean
proof body (right). This structure carries only the *informal* (left) side: the
proof facet's prose. (The old proof-cell "USES n" chip is gone — the metadata
rail's Uses section owns that information.) The *formal* proof body is a property
of the statement's associated declaration, so it lives on `Parts.formalBody`
(routed into the right proof cell by `render`), not here.

For theorem-like nodes with no proof facet at all, `Parts.proof?` is `none` and
`render` synthesizes a quiet placeholder in the informal proof cell — the proof
region is always present for theorem-like cards.
-/
structure ProofParts where
  /-- Rendered informal proof prose (the proof facet's `bp_content` body). -/
  informalProof : Html
  /-- Stable id stem for the card, used to wire the toggle to the proof region. -/
  cardId : String

/--
Rendered pieces of a single node card.

`informalStmt` is the statement's informal prose; `formalStmt` is its Lean
signature panel (or `.empty`). `formalBody` is the captured `:= …` source of the
statement's associated declaration — the *proof body* for theorem-like nodes and
the *value* for definitions.

Layout is driven by `isTheoremLike`:
* **Theorem-like** cards always render the full 2×2 grid — informal statement,
  formal statement, informal proof, formal proof — with a quiet placeholder
  synthesized for any unavailable part. `formalBody` fills the formal proof cell;
  `proof?` fills the informal proof cell (placeholder when `none`). The proof
  region is always present (toggle + hidden-by-default collapse).
* **Definitions** always render a 1×2 grid (informal / formal) with no proof
  region. The formal cell shows the signature (`formalStmt`) followed by the
  value body (`formalBody`).
-/
structure Parts where
  /-- Stable id stem for the card. Drives `data-bp-card` (always set) and the
  proof region's `id`/`aria-controls` (as `{cardId}-proof`). Derive it from the
  node label/slug so every card has a deterministic DOM id. -/
  cardId : String
  /-- Whether this node is theorem-like (theorem/lemma/proposition/corollary).
  `true` selects the 2×2 statement+proof layout; `false` (definition) selects the
  1×2 signature+value layout with no proof region. -/
  isTheoremLike : Bool := true
  /-- Full-width card header (title / number / status / extras). -/
  header : Html
  /-- Informal statement prose (left statement cell). -/
  informalStmt : Html
  /-- Formal Lean signature panel for the statement (right statement cell), or
  `.empty`. -/
  formalStmt : Html
  /-- Captured `:= …` source of the statement's associated `(lean := …)`
  declaration: the proof body for theorem-like nodes (routed into the formal
  proof cell) or the value for definitions (rendered under the signature).
  `.empty` for inline-authored theorems (the runtime relocates the statement's
  tactic tail instead) and for nodes with no associated Lean. -/
  formalBody : Html := .empty
  /-- Informal proof content, when the node has a proof facet. -/
  proof? : Option ProofParts := none
  /-- Primary (canonical) declaration name this card formalizes, surfaced as
  `data-bp-card`'s sibling `data-bp-decl` so the selection bus / metadata rail can
  identify the decl on card click/focus. `none` for no-Lean nodes. -/
  declName? : Option String := none
  /-- Slim identity-only metadata JSON (see `declMetaJson`) embedded inline as a
  `<script class="bp-decl-meta">` so the metadata rail can first-paint the current
  page's decls without a network fetch (offline / `file://`). `none` ⇒ no script. -/
  declMetaJson? : Option String := none

/-- Presentation knobs for `render`. -/
structure Options where
  /-- Compact callers fall back to the single-column renderer; the card path
  assumes non-compact. -/
  compact : Bool := false
  /-- Whether to emit the card header band. -/
  showHeader : Bool := true
  /-- Extra class(es) appended to the card wrapper. -/
  wrapperClass : String := ""

/-- HTML class string for the card wrapper, folding in any caller-supplied class. -/
private def wrapperClass (opts : Options) : String :=
  if opts.wrapperClass.isEmpty then
    "bp_card2"
  else
    s!"bp_card2 {opts.wrapperClass}"

/--
Render captured formal proof/value source into a card cell — one highlighted Lean
code block per associated declaration, in source order.

Each item is the `(proofHtml?, proofSource?)` pair snapshotted for one `(lean := …)`
reference (see `Data.ExternalRef`): the syntactically-highlighted token markup is
preferred, falling back to escaped raw source when highlighting was unavailable.
`.empty` when there are no items (inline-authored theorems and no-Lean nodes).

Kept Data-free (plain `String` pairs) so this foundational module stays
independent of the blueprint data model; callers map their external refs to pairs.

`assignPrefix` restores a leading `:=` token in front of each body so a
definition's captured *value* reads as `:= value` directly under its signature
(the top-level `:=` is dropped by the source slice, and it cannot be re-parsed as
part of the value `term`, so it is emitted as a bare `built-in delim` token). Set
by definition callers only; theorem *proof* bodies keep the default (no prefix).
-/
def formalSourceBody (items : Array (Option String × Option String))
    (assignPrefix : Bool := false) : Html :=
  let assignTok : Html :=
    if assignPrefix then {{ <span class="built-in delim token">":= "</span> }} else .empty
  let bodies : Array Html := items.filterMap fun (proofHtml?, proofSource?) =>
    match proofHtml? with
    | some html =>
      some {{ <pre class="bp_card2_proof_source"><code class="hl lean block">{{assignTok}}{{Html.text false html}}</code></pre> }}
    | none =>
      proofSource?.map fun src =>
        {{ <pre class="bp_card2_proof_source"><code class="hl lean block">{{assignTok}}{{Html.text true src}}</code></pre> }}
  if bodies.isEmpty then .empty else .seq bodies

/-- Does this HTML render as nothing but whitespace? Used to decide whether a card
cell is unavailable and should show a quiet placeholder instead. A present tag is
never blank (it carries structure even when its text is empty). -/
private partial def htmlIsBlank : Html → Bool
  | .text _ s => s.all Char.isWhitespace
  | .tag .. => false
  | .seq xs => xs.all htmlIsBlank

/-- A quiet, muted placeholder for an unavailable card cell. -/
private def placeholderCell (text : String) : Html :=
  {{ <div class="bp_card2_placeholder">{{Html.ofString text}}</div> }}

/-- `content` if it renders anything, else a quiet placeholder with `text`. -/
private def orPlaceholder (content : Html) (text : String) : Html :=
  if htmlIsBlank content then placeholderCell text else content

/-- A statement/proof-row grid pairing an informal (left) and formal (right) cell.
`extraClass` distinguishes the proof grid so its collapse animation can target it. -/
private def cardGrid (informalCellClass formalCellClass extraClass : String)
    (informalCell formalCell : Html) : Html :=
  {{
    <div class={{s!"bp_card2_grid{extraClass}"}}>
      <div class={{s!"bp_card2_cell {informalCellClass}"}}> {{informalCell}} </div>
      <div class={{s!"bp_card2_cell {formalCellClass}"}}> {{formalCell}} </div>
    </div>
  }}

/--
Short display name for a declaration: strips the configured project prefix
(`verso.blueprint.declNamePrefix`, e.g. `A362583`) plus its trailing dot when it
matches, else the name unchanged. The single source of truth for name shortening
— catalog rows, the metadata rail, the page outline, and the search records all
derive their short names from this (the fully-qualified name is preserved on
decl pages and in hover `title`s). Pure/deterministic; an empty prefix or an
exact prefix==name match is the identity.
-/
def shortDeclName (pfx name : String) : String :=
  if pfx.isEmpty then name
  else
    let pre := pfx ++ "."
    if name.startsWith pre && name.length > pre.length then
      (name.drop pre.length).toString
    else name

/--
Short display name for a *module* path: the same prefix-stripping as
`shortDeclName`, applied to a dotted module name (e.g. `A362583.BoundedHolo` →
`BoundedHolo`). Kept as a distinct helper for the catalog module headers /
search "chapter" field, but delegates to `shortDeclName` so the stripping rule
stays single-sourced. Identity on an empty prefix or a non-matching name.
-/
def shortModuleName (pfx name : String) : String := shortDeclName pfx name

/--
Build the slim identity-only metadata JSON embedded inline per card for the
metadata rail's offline first paint (`Parts.declMetaJson?`).

Kept to injection-safe *identity* fields only — name, kind, status, module,
numbered title, source line span, root-relative node href, and (when configured)
the prefix-stripped `shortName` / unwired-decl-page `declHref` — with no type or
signature text (so the payload can never contain a stray `</script>` and stays
small). The heavier data (parameters, uses / used-by, see-also) is fetched from
`-verso-data/decl-registry.json` at selection time; under `file://` those
sections degrade to a quiet "unavailable offline" note.

The optional `shortName` / `declHref` keys are emitted only when set, so legacy
callers (and consumers without a configured prefix) get byte-identical output.

`<` is escaped to `<` in the emitted JSON so embedding it verbatim in a
raw-text `<script>` element can never terminate the script early.
-/
def declMetaJson (name kind status moduleName title : String)
    (startLine endLine : Option Nat) (nodeHref : Option String)
    (shortName : Option String := none) (declHref : Option String := none) : String :=
  open Lean in
  let base : List (String × Json) :=
    [ ("name", Json.str name)
    , ("kind", Json.str kind)
    , ("status", Json.str status)
    , ("module", Json.str moduleName)
    , ("title", Json.str title) ]
  let range : List (String × Json) :=
    match startLine, endLine with
    | some s, some e => [("startLine", Lean.toJson s), ("endLine", Lean.toJson e)]
    | _, _ => []
  let href : List (String × Json) :=
    match nodeHref with
    | some h => [("nodeHref", Json.str h)]
    | none => []
  let short : List (String × Json) :=
    match shortName with
    | some s => [("shortName", Json.str s)]
    | none => []
  let declPage : List (String × Json) :=
    match declHref with
    | some h => [("declHref", Json.str h)]
    | none => []
  ((Json.mkObj (base ++ range ++ href ++ short ++ declPage)).compress).replace "<" "\\u003c"

/-- Inline per-card metadata `<script>` for the rail's offline first paint, or
`.empty`. The JSON is `</script>`-safe (see `declMetaJson`) so it is injected raw. -/
private def metaScriptOf (parts : Parts) : Html :=
  match parts.declMetaJson? with
  | some json =>
    {{ <script type="application/json" class="bp-decl-meta"
        "data-bp-decl"={{parts.declName?.getD ""}}>{{Html.text false json}}</script> }}
  | none => .empty

/-- The always-present proof toggle button plus the animatable proof region. The
informal proof (left) and formal proof (right) cells are pre-resolved by `render`
(each already carrying a placeholder when its part is unavailable). -/
private def renderProofRegion (cardId : String) (informalProof formalProof : Html) : Html :=
  let proofId := s!"{cardId}-proof"
  {{
    <button type="button" class="bp_card2_proof_toggle"
        "aria-expanded"="false" aria-controls={{proofId}}>
      <span class="bp_card2_proof_word">"Proof"</span>
      <span class="bp_card2_proof_action">"[show]"</span>
    </button>
    <div class="bp_card2_proof_anim" id={{proofId}}>
      {{cardGrid "bp_card2_informal_proof" "bp_card2_formal_proof" " bp_card2_proof_grid"
          informalProof formalProof}}
    </div>
  }}

/--
Render a two-column node card.

Theorem-like nodes (`parts.isTheoremLike`) always render the full 2×2 grid —
informal/formal statement and informal/formal proof — with the proof toggle and
hidden-by-default proof region always present; any unavailable part becomes a
quiet placeholder. Definitions render a 1×2 grid whose formal cell shows the
signature followed by the `:= value` body, and no proof region. The header is a
plain `<div class="bp_card2_header">`.
-/
def render (parts : Parts) (opts : Options := {}) : Html :=
  let header :=
    if opts.showHeader then
      {{ <div class="bp_card2_header"> {{parts.header}} </div> }}
    else
      .empty
  let informalStmtCell := orPlaceholder parts.informalStmt "No informal statement yet."
  if parts.isTheoremLike then
    -- Always the full 2×2: statement row + proof row, placeholders for gaps.
    let formalStmtCell := orPlaceholder parts.formalStmt "Formal statement not available."
    let informalProof :=
      match parts.proof? with
      | some proof =>
        orPlaceholder proof.informalProof "No informal proof yet."
      | none => placeholderCell "No informal proof yet."
    -- The formal proof cell holds the captured proof source; when empty it shows a
    -- placeholder, which the runtime tactic-tail relocation (`proof-toggle.mjs`)
    -- replaces wholesale via `replaceChildren` for inline-authored theorems.
    let formalProof := orPlaceholder parts.formalBody "Formal proof not available."
    -- `.bp_card2_body` wraps the statement grid, the proof toggle, and the
    -- collapsible proof grid so the single `.bp_card2_divider` line can span all
    -- of them (statement through proof) and GROW as the proof region expands —
    -- one continuous divider, never two segments. (Definitions have no proof
    -- region, so they keep the simpler per-cell border; see `css`.)
    {{
      <div class={{wrapperClass opts}} "data-bp-card"={{parts.cardId}}
          "data-bp-decl"={{parts.declName?.getD ""}}>
        {{metaScriptOf parts}}
        {{header}}
        <div class="bp_card2_body">
          <div class="bp_card2_divider" aria-hidden="true"></div>
          {{cardGrid "bp_card2_informal_stmt" "bp_card2_formal_stmt" "" informalStmtCell formalStmtCell}}
          {{renderProofRegion parts.cardId informalProof formalProof}}
        </div>
      </div>
    }}
  else
    -- Definition: 1×2, formal cell = signature followed by the `:= value` body.
    let formalDefCell :=
      if htmlIsBlank parts.formalStmt && htmlIsBlank parts.formalBody then
        placeholderCell "Formal definition not available."
      else
        Html.seq #[parts.formalStmt, parts.formalBody]
    {{
      <div class={{wrapperClass opts}} "data-bp-card"={{parts.cardId}}
          "data-bp-decl"={{parts.declName?.getD ""}}>
        {{metaScriptOf parts}}
        {{header}}
        {{cardGrid "bp_card2_informal_stmt" "bp_card2_formal_stmt" "" informalStmtCell formalDefCell}}
      </div>
    }}

/--
Card CSS: the two-column grid, the wide breakout, the collapsible proof row, the
toggle control, and the relocated tactic-tail styling.

Design tokens only (`--bp-space-*`, `--bp-radius-*`, `--bp-duration-*`,
`--bp-ease`, `--bp-color-*`). The proof row is hidden by the *absence* of
`data-bp-proof-open="true"` on `.bp_card2` (pure CSS, no flash, no JS): the
collapse animates `grid-template-rows` between `0fr` and `1fr`. Light + dark come
for free from the `--bp-color-*` tokens (the only new color,
`--bp-color-card-divider`, has all four scheme blocks in `Commands/Common.lean`).
-/
def css : String := r##"
/* ---- Card + header ------------------------------------------------------- */
.bp_card2 {
  margin: var(--bp-space-5) 0;
}

.bp_card2_header {
  display: block;
  margin-bottom: var(--bp-space-3);
}

/* ---- Statement / proof grids (identical template so columns align) ------- */
.bp_card2_grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  gap: var(--bp-space-4);
  align-items: start;
}

.bp_card2_cell {
  min-width: 0;
}

/* Column inset so the prose and Lean columns clear the vertical divider. The
   line itself is drawn either by the per-definition border below or, for
   theorem-like cards, by the single spanning `.bp_card2_divider`. Suppressed
   when the layout stacks (handled in the responsive block). */
.bp_card2_formal_stmt:not(:empty),
.bp_card2_formal_proof:not(:empty) {
  padding-inline-start: var(--bp-space-4);
}

/* Definitions (1x2, no proof region) keep a simple per-cell hairline: their
   formal cell is a direct child of `.bp_card2` — theorem-like cards wrap their
   grids in `.bp_card2_body` and use the spanning divider instead, so this
   `.bp_card2 > .bp_card2_grid > …` selector matches definitions only. */
.bp_card2 > .bp_card2_grid > .bp_card2_formal_stmt:not(:empty) {
  border-inline-start: 1px solid var(--bp-color-card-divider);
}

/* Theorem-like cards: ONE continuous vertical divider, statement through proof.
   `.bp_card2_body` wraps the statement grid, the proof toggle, and the
   (collapsible) proof grid; the absolutely-positioned line spans the wrapper's
   full height, so it GROWS with the expanding proof region and never breaks into
   two segments. Positioned at the column boundary (col-2 start = 50% + half the
   grid gap), matching both grids' `bp_card2_formal_*` cell edge. */
.bp_card2_body {
  position: relative;
}

.bp_card2_divider {
  position: absolute;
  top: 0;
  bottom: 0;
  left: calc(50% + var(--bp-space-4) / 2);
  width: 1px;
  background: var(--bp-color-card-divider);
  pointer-events: none;
}

/* ---- Wide breakout (reuses the .bp_graph_fullwidth container-query trick) - */
@supports (width: 100cqw) {
  main > .content-wrapper:has(.bp_card2) {
    container-type: inline-size;
    max-width: none;
  }

  main > .content-wrapper:has(.bp_card2) > section {
    max-width: none;
  }

  /* Node-page cards live in a `<section>` nested inside `.bp_node_page`, which the
     `> section` breakout selector above doesn't reach; let that inner section grow
     so the card doesn't rely on overflowing its invisible section box. */
  main > .content-wrapper .bp_node_page section {
    max-width: none;
  }

  .bp_card2 {
    width: min(100cqw, 110rem);
    margin-inline: auto;
  }
}

/* Never break out when a card is itself a tile inside the side-by-side graft
   grid -- that grid already owns its track width. */
.bp_graft_side_by_side .bp_card2 {
  width: auto;
  max-width: none;
  margin-inline: 0;
}

/* ---- Responsive stack ---------------------------------------------------- */
@media (max-width: 60rem) {
  .bp_card2_grid {
    grid-template-columns: 1fr;
  }

  .bp_card2 {
    width: 100%;
  }

  /* Stacked: the formal cell sits below the informal one, so any vertical
     divider/inset would read as a stray left rule. Drop them all. */
  .bp_card2 > .bp_card2_grid > .bp_card2_formal_stmt:not(:empty) {
    border-inline-start: 0;
  }

  .bp_card2_formal_stmt:not(:empty),
  .bp_card2_formal_proof:not(:empty) {
    padding-inline-start: 0;
  }

  .bp_card2_divider {
    display: none;
  }
}

/* ---- Collapsible proof row ----------------------------------------------- */
.bp_card2_proof_anim {
  display: grid;
  grid-template-rows: 0fr;
  transition: grid-template-rows var(--bp-duration-slow) var(--bp-ease);
}

.bp_card2_proof_anim > * {
  overflow: hidden;
  min-height: 0;
}

.bp_card2[data-bp-proof-open="true"] .bp_card2_proof_anim {
  grid-template-rows: 1fr;
}

/* Give the revealed proof row a little breathing room from the statement. */
.bp_card2[data-bp-proof-open="true"] .bp_card2_proof_grid {
  padding-top: var(--bp-space-3);
}

@media (prefers-reduced-motion: reduce) {
  .bp_card2_proof_anim,
  .bp_card2_proof_toggle {
    transition: none;
  }
}

/* ---- Proof toggle (quiet italic "Proof [show]" disclosure) ---------------- */
.bp_card2_proof_toggle {
  display: inline-flex;
  align-items: baseline;
  gap: var(--bp-space-1);
  margin-top: var(--bp-space-3);
  padding: 0;
  border: 0;
  background: transparent;
  color: var(--bp-color-text-muted);
  font-family: var(--font-prose, inherit);
  font-size: var(--bp-fs-small, 0.875rem);
  font-style: italic;
  line-height: 1.4;
  cursor: pointer;
  transition: color var(--bp-duration-fast) var(--bp-ease);
}

.bp_card2_proof_word {
  font-weight: 600;
}

.bp_card2_proof_action {
  color: var(--bp-color-link);
}

.bp_card2_proof_toggle:hover .bp_card2_proof_action {
  text-decoration: underline;
  text-underline-offset: 0.14em;
}

.bp_card2_proof_toggle:focus-visible {
  outline: 2px solid var(--bp-color-accent);
  outline-offset: 2px;
}

/* ---- Prose measure: fill the narrower card column ------------------------ */
.bp_card2_informal_stmt .bp_content p,
.bp_card2_informal_stmt .bp_content li,
.bp_card2_informal_stmt .bp_content dd,
.bp_card2_informal_stmt .bp_content dt,
.bp_card2_informal_stmt .bp_content blockquote,
.bp_card2_informal_proof .bp_content p,
.bp_card2_informal_proof .bp_content li,
.bp_card2_informal_proof .bp_content dd,
.bp_card2_informal_proof .bp_content dt,
.bp_card2_informal_proof .bp_content blockquote {
  max-width: none;
}

/* ---- Relocated tactic tail ----------------------------------------------- */
/* The runtime (Commands/proof-toggle.mjs) extracts the statement's tactic tail
   and re-wraps it in `<pre><code class="hl lean block">` inside this cell. Match
   the statement code panel so the two right-hand cells read as one code column:
   monospace, horizontal scroll, no bleed. */
.bp_card2_formal_proof > pre {
  margin: 0;
  overflow-x: auto;
}

.bp_card2_formal_proof > pre > code.hl.lean.block {
  display: block;
  overflow-x: auto;
}

/* ---- Definition formal cell: signature + `:= value` as ONE code block ------ */
/* A definition's formal cell stacks the highlighted signature and the captured
   `:= value` body. Inside the card, collapse the external-decl scaffold's top
   offsets and inter-block margins and unify the two <pre>s' type/background so
   they read as a single contiguous Lean block that top-aligns with the informal
   column. Scoped to `.bp_card2_formal_stmt` so the external-decl scaffold used
   elsewhere (hover previews, standalone decl rows) is unchanged. */

/* Kill the scaffold's leading offsets so the signature top-aligns with the prose. */
.bp_card2_formal_stmt > .bp_code_panel_wrapper,
.bp_card2_formal_stmt .bp_external_decl_list,
.bp_card2_formal_stmt .bp_external_decl_rendered {
  margin-top: 0;
}

/* Signature <pre> — the scaffold path (`.bp_external_decl_rendered …`) and the
   bare decl-page path (`> pre.bp_external_decl_signature`) — shares the body's
   type ramp and drops its top padding so it butts against the value below. */
.bp_card2_formal_stmt .bp_external_decl_signature,
.bp_card2_formal_stmt > pre.bp_external_decl_signature {
  margin: 0;
  padding: 0 var(--bp-space-1);
  background: transparent;
  font-size: var(--bp-fs-control, 0.82rem);
  line-height: 1.5;
}

/* The captured `:= value` body sits flush under the signature: no gap, same
   type/padding/background, so the two <pre>s read as one block. */
.bp_card2_formal_stmt > .bp_card2_proof_source {
  margin: 0;
  padding: 0 var(--bp-space-1);
  background: transparent;
  overflow-x: auto;
  font-size: var(--bp-fs-control, 0.82rem);
  line-height: 1.5;
}

.bp_card2_formal_stmt > .bp_card2_proof_source > code.hl.lean.block {
  display: block;
  overflow-x: auto;
}

/* ---- Quiet placeholder for an unavailable card cell ---------------------- */
/* Muted, restrained "not yet" copy shown when a statement, proof, or value part
   is unavailable, so every theorem-like card reads as a complete 2x2 and every
   definition as a complete 1x2. Token-based, so light + dark come for free; the
   `:not(:empty)` column divider treats it as real content (it is a real cell). */
.bp_card2_placeholder {
  margin: 0;
  padding: var(--bp-space-1) 0;
  color: var(--bp-color-text-subtle);
  font-size: var(--bp-fs-caption, 0.78rem);
  font-style: italic;
  line-height: 1.5;
}
"##

end Informal.NodeCard
