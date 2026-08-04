/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean

/-!
Site-wide "docs navigation" chrome styling (Wave 5): the top-nav category strip
and the per-page declaration outline.

Both DOMs are injected at runtime by ES modules (`Commands/top-nav.mjs`,
`Commands/page-outline.mjs`) — no verso-core template edit — and only their
stylesheets ride here. The CSS rides the global `blueprintHtmlAssets` `extraCss`
channel (the same channel as the banner nav, metadata rail, and copy button) so
it is present on every page, and it reuses the existing `--bp-*` / `--verso-*`
design tokens exclusively, so light + dark and AA contrast come for free with no
CDN / network dependency.
-/

namespace Informal.DocsChrome

/-! ## Top-nav category strip -/

/--
Styling for the top-nav strip injected into the fixed site banner
(`Commands/top-nav.mjs`, appended inside the banner's `.header-logo-wrapper`).

The three category tabs sit beside the Home logo in the banner's first cell, the
active page marked with an accent underline (`aria-current="page"`). The
`.header-logo-wrapper:has(.bp-topnav)` rule below turns that cell into a flex row so
the logo and tabs lay out horizontally (guarded to `>700px` so it never overrides
the core banner's `<=700px` hide of the logo slot). At `<=700px` the core banner
hides the logo slot and the tabs with it, showing the ToC burger instead.
-/
def topNavCss : String := r##"
/* Lay the logo + tabs out as a horizontal row inside the banner's first cell. The
   `:has()` guard scopes this to the wrapper that actually holds our nav, and the
   min-width media query keeps it from re-showing the logo slot the core banner hides
   at <=700px (that `display: none` is lower specificity than this rule). */
@media (min-width: 701px) {
  .header-logo-wrapper:has(.bp-topnav) {
    display: flex;
    align-items: center;
    gap: var(--bp-space-3);
    min-width: 0;
  }
}

.bp-topnav {
  /* Shrinkable (min-width: 0) so a wide "Project management" label never forces the
     logo cell to overflow; the tabs stay on one line and clip gracefully instead. */
  flex: 0 1 auto;
  min-width: 0;
  position: relative;
  display: flex;
  align-items: center;
}

.bp-topnav-menu {
  display: flex;
  align-items: center;
  gap: var(--bp-space-1);
  min-width: 0;
}

.bp-topnav-link {
  display: inline-flex;
  align-items: center;
  height: 1.9rem;
  padding: 0 var(--bp-space-2);
  border: 1px solid transparent;
  border-radius: var(--bp-radius-sm);
  color: var(--bp-color-text-muted);
  font-size: var(--bp-fs-control, 0.82rem);
  font-weight: 600;
  text-decoration: none;
  white-space: nowrap;
  transition: background-color var(--bp-duration-fast, 0.12s) var(--bp-ease, ease),
    color var(--bp-duration-fast, 0.12s) var(--bp-ease, ease),
    border-color var(--bp-duration-fast, 0.12s) var(--bp-ease, ease);
}

.bp-topnav-link:hover {
  background: var(--bp-color-surface-subtle);
  color: var(--bp-color-text-strong);
  border-color: var(--bp-color-border);
}

.bp-topnav-link:focus-visible { outline: 2px solid var(--bp-color-accent); outline-offset: 2px; }

.bp-topnav-link[aria-current="page"] {
  color: var(--bp-color-accent);
  box-shadow: inset 0 -2px 0 var(--bp-color-accent);
}

@media (prefers-reduced-motion: reduce) {
  .bp-topnav-link { transition: none; }
}

/* ---- Narrow: hide (the burger owns the left of the banner here) ------------
   The nav lives inside `.header-logo-wrapper`, which the core banner sets to
   `display: none` at <=700px (there the header reverts from grid to flex and the
   ToC burger floats over that same left region), so the tabs already vanish with
   the logo slot. This explicit `display: none` is a belt-and-suspenders guard —
   matching the banner Back/Home controls, the tabs are a desktop/tablet affordance
   (the command palette + ToC cover navigation on phones). */
@media (max-width: 700px) {
  .bp-topnav { display: none; }
}

@media print {
  .bp-topnav { display: none !important; }
}
"##

/-! ## Per-page declaration outline -/

/--
Styling for the "On this page" declaration outline injected below the sidebar ToC
by `Commands/page-outline.mjs` on chapter / node pages that carry node cards.

It lives inside `nav#toc` (the fixed left sidebar), so it reuses the ToC's own
scroll region rather than fighting the fixed layout, and is themed with the `--bp-*`
tokens so it follows dark mode.
-/
def pageOutlineCss : String := r##"
.bp-page-outline {
  margin: var(--bp-space-4) 0 var(--bp-space-4);
  padding-top: var(--bp-space-3);
  border-top: 1px solid var(--bp-color-border-soft);
}

/* Separator above the non-chapter (unnumbered) ToC tail — Dependency Graph,
   Showcase Summary, Formalization Metadata, Bibliography — mirroring the
   "On this page" outline separator above. Verso core's split-toc
   (`Toc.localHtml` / `splitTocElem`) emits the numbered chapter rows
   (`tr.numbered`) contiguously, then the unnumbered tail (`tr.unnumbered`); we
   assume that ordering and draw the rule on the first unnumbered row that
   directly follows a numbered one. */
#toc .split-toc.book table tr.numbered + tr.unnumbered td {
  border-top: 1px solid var(--bp-color-border-soft);
  padding-top: var(--bp-space-3);
}

.bp-page-outline-title {
  margin: 0 0 var(--bp-space-2);
  padding: 0 var(--bp-space-2);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--bp-color-text-subtle);
}

.bp-page-outline-list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.bp-page-outline-list li { margin: 0; }

.bp-page-outline-list a {
  display: block;
  padding: 0.2rem var(--bp-space-2);
  border-left: 2px solid transparent;
  color: var(--bp-color-text-muted);
  font-size: var(--bp-fs-caption, 0.78rem);
  line-height: 1.4;
  text-decoration: none;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.bp-page-outline-list a:hover {
  color: var(--bp-color-text-strong);
  border-left-color: var(--bp-color-border-strong);
}

.bp-page-outline-list a.bp-outline-active {
  color: var(--bp-color-accent);
  border-left-color: var(--bp-color-accent);
}

.bp-page-outline-kind {
  display: inline-block;
  width: 2.2rem;
  color: var(--bp-color-text-faint);
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-badge, 0.72rem);
  text-transform: uppercase;
}

@media print {
  .bp-page-outline { display: none !important; }
}
"##

end Informal.DocsChrome
