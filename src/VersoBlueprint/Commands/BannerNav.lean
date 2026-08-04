/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean

/-!
Styling for the fixed-banner Back / Home controls.

The controls' DOM is injected at runtime by `Commands/banner-nav.mjs` into the
site banner's `.header-logo-wrapper` slot; this module only carries their
stylesheet. The CSS rides the global `blueprintHtmlAssets` `extraCss` channel
(the same channel as the dark-mode, copy-button, and command-palette styling) so
the controls are themed on every page. Colors reuse the existing `--bp-color-*`
design tokens (no new color is introduced), so light + dark come for free; no
CDN / network dependency.

Note: the core banner hides `.header-logo-wrapper` below 700px
(`@media (max-width: 700px)` in verso `Html/Style.lean`), so these controls are
a desktop affordance and are hidden on very narrow viewports, matching the rest
of the banner logo slot.
-/

namespace Informal.BannerNav

/-- Stylesheet for the banner Back / Home icon buttons. -/
def css : String := r##"
.bp-banner-nav {
  display: inline-flex;
  align-items: center;
  gap: var(--bp-space-1);
}

.bp-banner-nav-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.9rem;
  height: 1.9rem;
  padding: 0;
  border: 1px solid transparent;
  border-radius: var(--bp-radius-sm);
  background: transparent;
  color: var(--bp-color-text-muted);
  cursor: pointer;
  text-decoration: none;
  -webkit-appearance: none;
  appearance: none;
  transition: background-color var(--bp-duration-fast) var(--bp-ease),
    border-color var(--bp-duration-fast) var(--bp-ease),
    color var(--bp-duration-fast) var(--bp-ease);
}

.bp-banner-nav-btn:hover {
  background: var(--bp-color-surface-subtle);
  border-color: var(--bp-color-border);
  color: var(--bp-color-text-strong);
}

.bp-banner-nav-btn:focus-visible {
  outline: 2px solid var(--bp-color-accent);
  outline-offset: 2px;
  color: var(--bp-color-text-strong);
}

.bp-banner-nav-btn svg {
  display: block;
}

@media (prefers-reduced-motion: reduce) {
  .bp-banner-nav-btn {
    transition: none;
  }
}
"##

end Informal.BannerNav
