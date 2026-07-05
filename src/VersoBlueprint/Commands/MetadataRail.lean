/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean

/-!
Styling for the site-wide "Properties & Dependencies" metadata rail.

The rail's DOM is injected at runtime by `Commands/metadata-rail.mjs` (the
established asset-injection pattern used by the banner nav and color-scheme
switcher — no verso-core template edit); this module only carries its stylesheet.
The CSS rides the global `blueprintHtmlAssets` `extraCss` channel so the rail is
themed on every page, and reuses the existing `--bp-*` design tokens exclusively
(no new color is introduced), so light + dark come for free with AA contrast in
both; no CDN / network dependency.

Layout model: the rail is **always present, open, and docked** to the right edge
on every page (no drawer, edge tab, collapse toggle, breakpoint, or persisted
open-state). It is fixed along the right edge (appended to `<body>`), reserving
right margin on `<main>` — gated on the `body.bp-rail-present` class the runtime
sets once the rail is injected — so it never overlaps the 44rem content measure,
marginalia (which live inside `<main>`'s box), or the graph's `100cqw` breakout
(whose container shrinks with the reserved margin), and pages without a rail get
no dead margin.

Its **width is user-resizable**: a drag handle (`.bp-rail-resize-handle`,
mirroring verso-core's ToC handle) writes `--bp-rail-user-width` (px, persisted
to `localStorage["bp-rail-width"]`); CSS clamps it to
`clamp(14rem, …, min(32rem, 100vw - var(--verso-toc-effective-width) - 20rem))`,
so the rail stays visible at every viewport while always leaving the content
column at least ~20rem beyond the left ToC.

The rail sits above the fixed ToC (z 10-12) but below the graph node modal
(z 9500), so the Wave-2 modal always layers over it. It honors
`prefers-reduced-motion` and every dependency item is a real button.

The pinned footer (`.bp-rail-footer`) carries the absorbed page-level controls
(the old floating widget): an Auto | Light | Dark theme radiogroup driving
`window.VersoBlueprint.colorScheme`, a three-`A` text-size radiogroup driving
`window.VersoBlueprint.textSize`, and — when the page has node cards — a bulk
"Proofs: show all / hide all" pair driving proof-toggle.mjs `setAllProofs`.

Stage-2 data sections: the registry v2 fields feed a **Docstring** section
(build-generated HTML — the markdown pipeline has raw HTML disabled, so
`innerHTML` injection is safe), a **View source** link in the Source section,
and a **Metrics** section (fan-in/fan-out computed client-side from the
dependency arrays; depth/height from the registry). Docstring prose is styled
below (`.bp-rail-docstring`) with overflow-safe scrolling for wide math/code.
-/

namespace Informal.MetadataRail

/-- Stylesheet for the always-open metadata rail (docked + inline variants). -/
def css : String := r##"
:root {
  /* User-resizable (drag handle writes --bp-rail-user-width in px; see
     metadata-rail.mjs), clamped so the rail stays a sane width and always leaves
     the content column at least ~20rem *beyond* the left ToC. The upper bound
     subtracts the ToC's effective width (--verso-toc-effective-width, a :root var
     in verso core; the 0rem fallback covers pages/viewports where the ToC
     collapses) so a tablet-width viewport with the ToC open doesn't crush the
     content column. When that upper bound falls below the 14rem lower bound
     (very narrow viewport) CSS clamp() resolves min-wins and pins the rail at
     14rem. The rail is visible at every viewport. */
  --bp-rail-width: clamp(14rem, var(--bp-rail-user-width, 20.5rem), min(32rem, 100vw - var(--verso-toc-effective-width, 0rem) - 20rem));
  --bp-rail-gap: var(--bp-space-4);
}

/* ---- Rail shell ----------------------------------------------------------- */
/* The rail is always present, open, and docked to the right edge on every page
   (no drawer / edge tab / collapse / breakpoint), appended to <body>. Its width
   is user-resizable (drag handle below) and CSS-clamped so the content column
   keeps a minimum width at every viewport. */
#bp-metadata-rail {
  position: fixed;
  top: var(--verso-header-height, 3rem);
  right: 0;
  bottom: 0;
  width: var(--bp-rail-width);
  max-width: 92vw;
  z-index: 40;
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  background: var(--bp-color-surface);
  border-left: 1px solid var(--bp-color-border);
  color: var(--bp-color-text);
}

/* ---- Width drag handle (mirrors verso-core .toc-resize-handle) ------------- */
/* Sits at the rail's left edge; the grab area extends a few px into the content
   margin, the hairline divider (::after) sits on the rail's border. */
.bp-rail-resize-handle {
  position: fixed;
  top: var(--verso-header-height, 3rem);
  right: var(--bp-rail-width);
  width: 6px;
  height: calc(100dvh - var(--verso-header-height, 3rem));
  z-index: 41;
  cursor: col-resize;
  touch-action: none;
}

.bp-rail-resize-handle::after {
  content: "";
  position: absolute;
  top: 0;
  right: 0;
  width: 1px;
  height: 100%;
  background: var(--bp-color-border);
  transition: background var(--bp-duration-fast, 0.12s) var(--bp-ease, ease);
}

.bp-rail-resize-handle:hover::after,
.bp-rail-resize-handle.dragging::after,
.bp-rail-resize-handle:focus-visible::after {
  background: var(--bp-color-accent);
}

.bp-rail-resize-handle:focus-visible {
  outline: 2px solid var(--bp-color-accent);
  outline-offset: -2px;
}

@media (prefers-reduced-motion: reduce) {
  .bp-rail-resize-handle::after { transition: none; }
}

/* ---- Header --------------------------------------------------------------- */
.bp-rail-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--bp-space-2);
  padding: var(--bp-space-3) var(--bp-space-4);
  border-bottom: 1px solid var(--bp-color-border-soft);
  flex: 0 0 auto;
}

.bp-rail-title {
  font-size: var(--bp-fs-caption, 0.78rem);
  font-weight: 700;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: var(--bp-color-text-strong);
}

/* ---- Body ----------------------------------------------------------------- */
.bp-rail-body {
  flex: 1 1 auto;
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: var(--bp-space-4);
}

.bp-rail-empty {
  color: var(--bp-color-text-subtle);
  font-size: var(--bp-fs-caption, 0.78rem);
  font-style: italic;
  line-height: 1.6;
}

/* ---- Selected-decl identity ---------------------------------------------- */
.bp-rail-identity {
  display: flex;
  flex-direction: column;
  gap: var(--bp-space-2);
  padding-bottom: var(--bp-space-3);
  border-bottom: 1px solid var(--bp-color-border-soft);
}

.bp-rail-badges {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--bp-space-2);
}

.bp-rail-kind,
.bp-rail-status {
  display: inline-flex;
  align-items: center;
  padding: 0.1rem 0.5rem;
  border-radius: var(--bp-radius-pill);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 600;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  white-space: nowrap;
}

.bp-rail-kind {
  background: var(--bp-color-surface-subtle);
  color: var(--bp-color-text-muted);
  border: 1px solid var(--bp-color-border);
}

.bp-rail-status {
  border: 1px solid var(--bp-color-border);
  background: var(--bp-color-surface-subtle);
  color: var(--bp-color-text-muted);
}

.bp-rail-status[data-status="proved"] {
  color: var(--bp-color-status-success-text, var(--bp-color-accent-success));
  border-color: var(--bp-color-status-warning-border-soft);
  background: var(--bp-color-status-ready-surface, var(--bp-color-surface-subtle));
}

.bp-rail-status[data-status="containsSorry"],
.bp-rail-status[data-status="missing"] {
  color: var(--bp-color-status-warning-text, var(--bp-color-accent-warning));
  border-color: var(--bp-color-status-warning-border-soft);
  background: var(--bp-color-status-blocked-surface, var(--bp-color-surface-warn));
}

.bp-rail-name {
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-control, 0.82rem);
  font-weight: 600;
  color: var(--bp-color-text-strong);
  overflow-wrap: anywhere;
  line-height: 1.4;
}

.bp-rail-node-title {
  font-size: var(--bp-fs-caption, 0.78rem);
  color: var(--bp-color-text-muted);
  line-height: 1.4;
}

/* ---- Sections ------------------------------------------------------------- */
.bp-rail-section {
  padding: var(--bp-space-3) 0;
  border-bottom: 1px solid var(--bp-color-border-soft);
}

.bp-rail-section:last-child {
  border-bottom: 0;
}

.bp-rail-section-title {
  margin: 0 0 var(--bp-space-2);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--bp-color-text-subtle);
}

.bp-rail-meta-row {
  display: flex;
  gap: var(--bp-space-2);
  align-items: baseline;
  font-size: var(--bp-fs-caption, 0.78rem);
  line-height: 1.5;
}

.bp-rail-meta-row + .bp-rail-meta-row {
  margin-top: var(--bp-space-1);
}

.bp-rail-meta-key {
  flex: 0 0 auto;
  min-width: 4.2rem;
  color: var(--bp-color-text-subtle);
}

.bp-rail-meta-val {
  color: var(--bp-color-text);
  overflow-wrap: anywhere;
}

.bp-rail-sig {
  margin: 0;
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-small, 0.8rem);
  color: var(--bp-color-text);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  line-height: 1.5;
}

/* ---- Parameters table ----------------------------------------------------- */
.bp-rail-params {
  display: flex;
  flex-direction: column;
  gap: var(--bp-space-1);
}

.bp-rail-param {
  display: flex;
  gap: var(--bp-space-2);
  align-items: baseline;
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-small, 0.8rem);
  line-height: 1.5;
}

.bp-rail-param-name {
  color: var(--bp-color-text-strong);
  overflow-wrap: anywhere;
}

.bp-rail-param-sep {
  color: var(--bp-color-text-faint);
}

.bp-rail-param-type {
  color: var(--bp-color-text-muted);
  overflow-wrap: anywhere;
}

.bp-rail-param[data-binder="instImplicit"] .bp-rail-param-name,
.bp-rail-param[data-binder="implicit"] .bp-rail-param-name,
.bp-rail-param[data-binder="strictImplicit"] .bp-rail-param-name {
  color: var(--bp-color-text-muted);
  font-style: italic;
}

/* ---- Dependency lists ----------------------------------------------------- */
.bp-rail-deps {
  display: flex;
  flex-direction: column;
  gap: var(--bp-space-1);
}

.bp-rail-dep-item {
  display: flex;
  align-items: center;
  gap: var(--bp-space-1);
}

.bp-rail-dep {
  flex: 1 1 auto;
  min-width: 0;
  text-align: left;
  padding: 0.2rem 0.4rem;
  border: 1px solid transparent;
  border-radius: var(--bp-radius-sm);
  background: transparent;
  color: var(--bp-color-link);
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-small, 0.8rem);
  cursor: pointer;
  overflow-wrap: anywhere;
  transition: background-color var(--bp-duration-fast) var(--bp-ease),
    color var(--bp-duration-fast) var(--bp-ease);
}

.bp-rail-dep[data-wired="false"] {
  color: var(--bp-color-text-muted);
}

.bp-rail-dep:hover {
  background: var(--bp-color-surface-subtle);
  color: var(--bp-color-text-strong);
}

.bp-rail-dep:focus-visible {
  outline: 2px solid var(--bp-color-accent);
  outline-offset: 1px;
}

.bp-rail-dep-axis {
  flex: 0 0 auto;
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-badge, 0.72rem);
  color: var(--bp-color-text-faint);
  text-transform: lowercase;
}

.bp-rail-dep-link {
  flex: 0 0 auto;
  display: inline-flex;
  align-items: center;
  color: var(--bp-color-text-subtle);
  text-decoration: none;
  padding: 0 0.15rem;
}

.bp-rail-dep-link:hover {
  color: var(--bp-color-accent);
}

.bp-rail-more {
  margin-top: var(--bp-space-1);
  font-size: var(--bp-fs-badge, 0.72rem);
  color: var(--bp-color-text-faint);
}

/* ---- Docstring (registry v2) ----------------------------------------------- */
.bp-rail-docstring {
  font-size: var(--bp-fs-caption, 0.78rem);
  line-height: 1.55;
  color: var(--bp-color-text);
  overflow-x: auto; /* wide inline math / code scrolls inside the rail */
}

.bp-rail-docstring p {
  margin: 0 0 var(--bp-space-2);
}

.bp-rail-docstring p:last-child {
  margin-bottom: 0;
}

.bp-rail-docstring pre {
  margin: var(--bp-space-2) 0;
  padding: var(--bp-space-2);
  background: var(--bp-color-surface-subtle);
  border-radius: var(--bp-radius-sm);
  overflow-x: auto;
  font-size: var(--bp-fs-small, 0.8rem);
}

.bp-rail-docstring code {
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: 0.95em;
  overflow-wrap: anywhere;
}

.bp-rail-docstring ul,
.bp-rail-docstring ol {
  margin: 0 0 var(--bp-space-2);
  padding-left: var(--bp-space-5);
}

/* ---- Open node/declaration page CTA + source link + offline note ----------- */
.bp-rail-open-page {
  display: inline-flex;
  align-items: center;
  gap: var(--bp-space-1);
  margin-top: var(--bp-space-2);
  color: var(--bp-color-link);
  font-size: var(--bp-fs-caption, 0.78rem);
  font-weight: 600;
  text-decoration: none;
}

.bp-rail-open-page:hover {
  text-decoration: underline;
}

.bp-rail-note {
  color: var(--bp-color-text-faint);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-style: italic;
  line-height: 1.5;
}

/* ---- Pinned footer (absorbed theme + proofs controls) ---------------------- */
.bp-rail-footer {
  flex: 0 0 auto;
  display: flex;
  flex-direction: column;
  gap: var(--bp-space-2);
  padding: var(--bp-space-3) var(--bp-space-4);
  border-top: 1px solid var(--bp-color-border-soft);
}

.bp-rail-footer-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: var(--bp-space-2);
}

.bp-rail-footer-label {
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--bp-color-text-subtle);
}

.bp-rail-theme {
  display: inline-flex;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-sm);
  overflow: hidden;
}

.bp-rail-theme-option {
  padding: 0.2rem 0.5rem;
  border: 0;
  background: transparent;
  color: var(--bp-color-text-muted);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 600;
  cursor: pointer;
  transition: background-color var(--bp-duration-fast) var(--bp-ease),
    color var(--bp-duration-fast) var(--bp-ease);
}

.bp-rail-theme-option + .bp-rail-theme-option {
  border-left: 1px solid var(--bp-color-border);
}

.bp-rail-theme-option:hover {
  background: var(--bp-color-surface-subtle);
  color: var(--bp-color-text-strong);
}

.bp-rail-theme-option[aria-checked="true"] {
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-strong);
}

.bp-rail-theme-option:focus-visible {
  outline: 2px solid var(--bp-color-accent);
  outline-offset: -2px;
}

/* ---- Text-size control (H): three segmented "A" buttons -------------------- */
.bp-rail-textsize {
  display: inline-flex;
  align-items: stretch;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-sm);
  overflow: hidden;
}

.bp-rail-textsize-option {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 1.9rem;
  padding: 0.2rem 0.4rem;
  border: 0;
  background: transparent;
  color: var(--bp-color-text-muted);
  font-weight: 600;
  line-height: 1;
  cursor: pointer;
  transition: background-color var(--bp-duration-fast) var(--bp-ease),
    color var(--bp-duration-fast) var(--bp-ease);
}

/* The glyph "A" renders at three sizes so the control reads as small/medium/large
   at a glance; the accessible name carries the size word. */
.bp-rail-textsize-option[data-size="small"] { font-size: 0.7rem; }
.bp-rail-textsize-option[data-size="medium"] { font-size: 0.85rem; }
.bp-rail-textsize-option[data-size="large"] { font-size: 1.05rem; }

.bp-rail-textsize-option + .bp-rail-textsize-option {
  border-left: 1px solid var(--bp-color-border);
}

.bp-rail-textsize-option:hover {
  background: var(--bp-color-surface-subtle);
  color: var(--bp-color-text-strong);
}

.bp-rail-textsize-option[aria-checked="true"] {
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-strong);
}

.bp-rail-textsize-option:focus-visible {
  outline: 2px solid var(--bp-color-accent);
  outline-offset: -2px;
}

.bp-rail-proofs {
  display: inline-flex;
  gap: var(--bp-space-1);
}

.bp-rail-proof-action {
  padding: 0.2rem 0.4rem;
  border: 1px solid transparent;
  border-radius: var(--bp-radius-sm);
  background: transparent;
  color: var(--bp-color-link);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 600;
  cursor: pointer;
  transition: background-color var(--bp-duration-fast) var(--bp-ease),
    color var(--bp-duration-fast) var(--bp-ease);
}

.bp-rail-proof-action:hover {
  background: var(--bp-color-surface-subtle);
  color: var(--bp-color-text-strong);
}

.bp-rail-proof-action:focus-visible {
  outline: 2px solid var(--bp-color-accent);
  outline-offset: 1px;
}

@media (prefers-reduced-motion: reduce) {
  .bp-rail-theme-option,
  .bp-rail-textsize-option,
  .bp-rail-proof-action {
    transition: none;
  }
}

/* ---- Docked layout: reserve right margin so nothing overlaps -------------- */
/* The rail is always docked, so the reservation is unconditional — but gated on
   `body.bp-rail-present` (set by metadata-rail.mjs once the rail is injected) so
   a page without a rail never gets a dead right margin. */
body.bp-rail-present .with-toc > main {
  margin-right: calc(var(--bp-rail-width) + var(--bp-rail-gap));
}

@media print {
  #bp-metadata-rail,
  .bp-rail-resize-handle {
    display: none !important;
  }
  body.bp-rail-present .with-toc > main {
    margin-right: 0;
  }
}
"##

end Informal.MetadataRail
