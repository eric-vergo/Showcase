/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html

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
Proof-row content for a node card.

The strict 2×2 grid pairs the informal proof prose (left) with the formal Lean
proof body (right). For external `(lean := …)` declarations the formal proof cell
is filled server-side with the captured proof source (`formalProof`). For
inline-authored theorems `formalProof` is empty and the runtime relocates the
tail of the *statement* facet's single highlighted code block into the cell
instead (`Commands/proof-toggle.mjs`).
-/
structure ProofParts where
  /-- Rendered informal proof prose (the proof facet's `bp_content` body). -/
  informalProof : Html
  /-- Formal Lean proof body for the right proof cell: the captured proof/value
  source of the statement's associated `(lean := …)` declaration. `.empty` for
  inline-authored theorems (the runtime relocates the statement's tactic tail
  here instead) and for nodes with no associated Lean. -/
  formalProof : Html := .empty
  /-- Proof-side uses panel for the proof facet, or `.empty`. -/
  proofUses : Html := .empty
  /-- Stable id stem for the card, used to wire the toggle to the proof region. -/
  cardId : String

/--
Rendered pieces of a single node card.

`informalStmt` is the statement's informal prose; `formalStmt` is its Lean code
panel (or `.empty`, which leaves the right cell blank). `proof?` is `none` for
nodes with no proof facet — in that case no toggle and no proof region render.
-/
structure Parts where
  /-- Stable id stem for the card. Drives `data-bp-card` (always set) and the
  proof region's `id`/`aria-controls` (as `{cardId}-proof`). Derive it from the
  node label/slug so every card has a deterministic DOM id. -/
  cardId : String
  /-- Full-width card header (title / number / status / extras). -/
  header : Html
  /-- Informal statement prose (left statement cell). -/
  informalStmt : Html
  /-- Formal Lean code panel for the statement (right statement cell), or `.empty`. -/
  formalStmt : Html
  /-- Proof content, when the node has a proof facet. -/
  proof? : Option ProofParts := none

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

/-- The statement-row grid (informal prose left, formal Lean right). -/
private def renderStatementGrid (parts : Parts) : Html :=
  {{
    <div class="bp_card2_grid">
      <div class="bp_card2_cell bp_card2_informal_stmt"> {{parts.informalStmt}} </div>
      <div class="bp_card2_cell bp_card2_formal_stmt"> {{parts.formalStmt}} </div>
    </div>
  }}

/--
The proof toggle button plus the animatable proof region, for a card that has a
proof facet. The informal proof prose (plus its uses panel) fills the left cell;
the formal Lean proof body (`proof.formalProof`, the captured proof source for
external `(lean := …)` decls) fills the right cell. When `formalProof` is empty
(inline-authored theorems), the right cell is emitted empty and the runtime
relocates the statement block's tactic tail into it.
-/
private def renderProofRegion (cardId : String) (proof : ProofParts) : Html :=
  let proofId := s!"{cardId}-proof"
  let informalProof :=
    Html.seq #[proof.informalProof, proof.proofUses]
  {{
    <button type="button" class="bp_card2_proof_toggle"
        "aria-expanded"="false" aria-controls={{proofId}}>
      "Show proof"
    </button>
    <div class="bp_card2_proof_anim" id={{proofId}}>
      <div class="bp_card2_grid bp_card2_proof_grid">
        <div class="bp_card2_cell bp_card2_informal_proof"> {{informalProof}} </div>
        <div class="bp_card2_cell bp_card2_formal_proof"> {{proof.formalProof}} </div>
      </div>
    </div>
  }}

/--
Render a two-column node card.

Emits the statement row always; the proof toggle and proof region only when
`parts.proof?` is `some`. The header is a plain `<div class="bp_card2_header">`.
-/
def render (parts : Parts) (opts : Options := {}) : Html :=
  let header :=
    if opts.showHeader then
      {{ <div class="bp_card2_header"> {{parts.header}} </div> }}
    else
      .empty
  let proofRegion :=
    match parts.proof? with
    | some proof => renderProofRegion parts.cardId proof
    | none => .empty
  {{
    <div class={{wrapperClass opts}} "data-bp-card"={{parts.cardId}}>
      {{header}}
      {{renderStatementGrid parts}}
      {{proofRegion}}
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

/* Hairline divider between the prose column and the Lean column. Suppressed
   when the formal cell is empty (no-Lean nodes get a blank right column, no
   stray rule) and when the layout stacks (handled in the responsive block). */
.bp_card2_formal_stmt:not(:empty),
.bp_card2_formal_proof:not(:empty) {
  border-inline-start: 1px solid var(--bp-color-card-divider);
  padding-inline-start: var(--bp-space-4);
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

  .bp_card2 {
    width: min(100cqw, 72rem);
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

  /* Stacked: the formal cell sits below the informal one, so the inline
     divider/inset would read as a stray left rule. Drop it. */
  .bp_card2_formal_stmt:not(:empty),
  .bp_card2_formal_proof:not(:empty) {
    border-inline-start: 0;
    padding-inline-start: 0;
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

/* ---- Proof toggle (restrained disclosure control) ------------------------ */
.bp_card2_proof_toggle {
  display: inline-flex;
  align-items: center;
  gap: var(--bp-space-1);
  margin-top: var(--bp-space-3);
  padding: var(--bp-space-1) var(--bp-space-2);
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-sm);
  background: var(--bp-color-surface);
  color: var(--bp-color-text-muted);
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-control, 0.82rem);
  font-weight: 600;
  letter-spacing: 0.02em;
  line-height: 1.2;
  cursor: pointer;
  transition: background-color var(--bp-duration-fast) var(--bp-ease),
    border-color var(--bp-duration-fast) var(--bp-ease),
    color var(--bp-duration-fast) var(--bp-ease);
}

/* Disclosure chevron, rotates when the proof opens. */
.bp_card2_proof_toggle::before {
  content: "";
  width: 0.42em;
  height: 0.42em;
  border-right: 1.5px solid currentColor;
  border-bottom: 1.5px solid currentColor;
  transform: rotate(-45deg);
  transition: transform var(--bp-duration-base) var(--bp-ease);
}

.bp_card2[data-bp-proof-open="true"] .bp_card2_proof_toggle::before {
  transform: rotate(45deg);
}

.bp_card2_proof_toggle:hover {
  border-color: var(--bp-color-border-strong);
  color: var(--bp-color-text-strong);
  background: var(--bp-color-surface-subtle);
}

.bp_card2_proof_toggle:focus-visible {
  outline: 2px solid var(--bp-color-accent);
  outline-offset: 2px;
}

@media (prefers-reduced-motion: reduce) {
  .bp_card2_proof_toggle::before {
    transition: none;
  }
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
"##

end Informal.NodeCard
