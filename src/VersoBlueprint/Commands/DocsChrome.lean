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
(`Commands/top-nav.mjs`, appended as the trailing flex child of `<header>`).

Wide viewports: an inline row of category links on the right of the banner, the
active page marked with an accent underline (`aria-current="page"`). At `<=700px`
(where the core banner hides its logo slot and shows the burger) it folds into a
compact "Browse" dropdown so the tabs never collide with the title.
-/
def topNavCss : String := r##"
.bp-topnav {
  /* No `margin-left: auto`: the core banner's `.header-title-wrapper` is `flex: 1`
     and already consumes the free space, pushing the nav to the right. An auto
     margin here would instead fight the later-mounted search box (also right-
     aligned) and the two would overlap. */
  flex: 0 0 auto;
  position: relative;
  display: flex;
  align-items: center;
  padding: 0 var(--bp-space-3);
}

.bp-topnav-menu {
  display: flex;
  align-items: center;
  gap: var(--bp-space-1);
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
   The nav sits before the `flex: 1` title wrapper (so the search box can't
   overlay it); at <=700px the core banner hides its logo slot and floats the
   ToC burger over that same left region, so — matching the banner Back/Home
   controls and the logo slot — the tabs are a desktop/tablet affordance and are
   hidden here (the command palette + ToC cover navigation on phones). */
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
