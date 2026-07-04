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

Layout model (two independent axes, both CSS-driven off a single
`:root[data-bp-rail-open]` attribute set by the runtime + persisted in
`localStorage`):

* **Docked vs. drawer** is purely viewport-driven. At `>= 87.5rem` (1400px) the
  rail docks along the right edge and reserves right margin on `<main>` so it
  never overlaps the 44rem content measure, marginalia (which live inside
  `<main>`'s box), or the graph's `100cqw` breakout (whose container shrinks with
  the reserved margin). Below that width it becomes an off-canvas drawer that
  overlays content with a backdrop, so narrow layouts are never crowded.
* **Open vs. collapsed** is the user's toggle (edge tab to open, header button to
  collapse), persisted across pages. When collapsed the rail slides off-screen and
  only the edge tab remains; the reserved `<main>` margin is released.

The rail sits above the fixed ToC (z 10-12) but below the graph node modal
(z 9500), so the Wave-2 modal always layers over it. It honors
`prefers-reduced-motion` and is fully keyboard operable (tab + collapse buttons
carry `aria-expanded`/`aria-controls`; every dependency item is a real button).
-/

namespace Informal.MetadataRail

/-- Stylesheet for the metadata rail, edge tab, and drawer backdrop. -/
def css : String := r##"
:root {
  --bp-rail-width: 20.5rem;
  --bp-rail-gap: var(--bp-space-4);
  --bp-rail-breakpoint: 87.5rem;
}

/* ---- Edge tab (resting affordance when the rail is closed) ---------------- */
#bp-metadata-rail-tab {
  position: fixed;
  top: 50%;
  right: 0;
  transform: translateY(-50%);
  z-index: 38;
  display: inline-flex;
  align-items: center;
  gap: var(--bp-space-1);
  margin: 0;
  padding: var(--bp-space-2) var(--bp-space-2);
  border: 1px solid var(--bp-color-border);
  border-right: 0;
  border-radius: var(--bp-radius-md) 0 0 var(--bp-radius-md);
  background: var(--bp-color-surface);
  color: var(--bp-color-text-muted);
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  cursor: pointer;
  writing-mode: vertical-rl;
  box-shadow: var(--bp-shadow-sm);
  transition: background-color var(--bp-duration-fast) var(--bp-ease),
    color var(--bp-duration-fast) var(--bp-ease),
    border-color var(--bp-duration-fast) var(--bp-ease);
}

#bp-metadata-rail-tab:hover {
  background: var(--bp-color-surface-subtle);
  color: var(--bp-color-text-strong);
  border-color: var(--bp-color-border-strong);
}

#bp-metadata-rail-tab:focus-visible {
  outline: 2px solid var(--bp-color-accent);
  outline-offset: 2px;
}

:root[data-bp-rail-open="true"] #bp-metadata-rail-tab {
  display: none;
}

/* ---- Rail shell ----------------------------------------------------------- */
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
  transform: translateX(100%);
  transition: transform var(--bp-duration-base) var(--bp-ease);
}

:root[data-bp-rail-open="true"] #bp-metadata-rail {
  transform: translateX(0);
}

@media (prefers-reduced-motion: reduce) {
  #bp-metadata-rail,
  #bp-metadata-rail-tab {
    transition: none;
  }
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

.bp-rail-collapse {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.6rem;
  height: 1.6rem;
  padding: 0;
  border: 1px solid transparent;
  border-radius: var(--bp-radius-sm);
  background: transparent;
  color: var(--bp-color-text-muted);
  cursor: pointer;
  transition: background-color var(--bp-duration-fast) var(--bp-ease),
    color var(--bp-duration-fast) var(--bp-ease),
    border-color var(--bp-duration-fast) var(--bp-ease);
}

.bp-rail-collapse:hover {
  background: var(--bp-color-surface-subtle);
  border-color: var(--bp-color-border);
  color: var(--bp-color-text-strong);
}

.bp-rail-collapse:focus-visible {
  outline: 2px solid var(--bp-color-accent);
  outline-offset: 2px;
}

.bp-rail-collapse svg { display: block; }

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

/* ---- Open node page CTA + offline note ------------------------------------ */
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

/* ---- Backdrop (drawer mode only) ------------------------------------------ */
.bp-rail-backdrop {
  position: fixed;
  inset: var(--verso-header-height, 3rem) 0 0 0;
  z-index: 39;
  /* Matches the Wave-2 graph modal scrim (a dark overlay in both themes; not a
     themed surface color, so no scheme blocks needed). */
  background: rgba(15, 23, 42, 0.5);
  border: 0;
  padding: 0;
  margin: 0;
  display: none;
}

/* ---- Docked layout: reserve right margin so nothing overlaps -------------- */
@media (min-width: 87.5rem) {
  :root[data-bp-rail-open="true"] .with-toc > main {
    margin-right: calc(var(--bp-rail-width) + var(--bp-rail-gap));
  }
}

/* ---- Drawer layout: overlay + backdrop below the docked breakpoint -------- */
@media (max-width: 87.4375rem) {
  #bp-metadata-rail {
    box-shadow: var(--bp-shadow-lg);
  }

  :root[data-bp-rail-open="true"] .bp-rail-backdrop {
    display: block;
  }
}

/* The rail is a desktop/tablet affordance; on phones the drawer would eat the
   whole viewport, so hide it entirely and fall back to the in-page cards. */
@media (max-width: 700px) {
  #bp-metadata-rail,
  #bp-metadata-rail-tab,
  .bp-rail-backdrop {
    display: none !important;
  }
}

@media print {
  #bp-metadata-rail,
  #bp-metadata-rail-tab,
  .bp-rail-backdrop {
    display: none !important;
  }
}
"##

end Informal.MetadataRail
