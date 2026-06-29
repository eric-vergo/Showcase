/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean

/-!
Styling for the command palette (Ctrl/Cmd-K fuzzy jump-to-node overlay).

The palette overlay DOM is created at runtime by `Commands/command-palette.mjs`;
this module only carries its stylesheet. The CSS rides the global
`blueprintHtmlAssets` `extraCss` channel (the same channel as the dark-mode and
copy-button styling) so the palette is themed on every page, including node
pages. Colors come from the `--bp-color-*` design tokens (with light literal
fallbacks) so the overlay follows the dark-mode color scheme; no CDN / network
dependency.
-/

namespace Informal.CommandPalette

/-- Stylesheet for the command palette overlay, input, and results list. -/
def css : String := r##"
.bp-cmdk-overlay {
  position: fixed;
  inset: 0;
  z-index: 9000;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding-top: 12vh;
  background: rgba(15, 23, 42, 0.45);
  -webkit-backdrop-filter: blur(2px);
  backdrop-filter: blur(2px);
}

.bp-cmdk-overlay[hidden] {
  display: none;
}

.bp-cmdk-panel {
  width: min(40rem, 92vw);
  max-height: 70vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(--bp-color-surface, #ffffff);
  color: var(--bp-color-text, #111827);
  border: 1px solid var(--bp-color-border, #cbd5e1);
  border-radius: var(--bp-radius-2xl, 0.7rem);
  box-shadow: var(--bp-shadow-lg, 0 12px 28px rgba(15, 23, 42, 0.18));
}

.bp-cmdk-input {
  box-sizing: border-box;
  width: 100%;
  padding: 0.85rem 1rem;
  font-size: 1rem;
  font-family: inherit;
  color: var(--bp-color-text, #111827);
  background: var(--bp-color-surface, #ffffff);
  border: 0;
  border-bottom: 1px solid var(--bp-color-border-soft, #e2e8f0);
  outline: none;
}

.bp-cmdk-input::placeholder {
  color: var(--bp-color-text-faint, #64748b);
}

.bp-cmdk-input:focus-visible {
  box-shadow: inset 0 0 0 2px var(--bp-color-focus-border, #93c5fd);
}

.bp-cmdk-results {
  margin: 0;
  padding: 0.35rem;
  list-style: none;
  overflow-y: auto;
}

.bp-cmdk-item {
  display: flex;
  align-items: baseline;
  gap: 0.6rem;
  padding: 0.5rem 0.7rem;
  border-radius: var(--bp-radius-md, 0.45rem);
  cursor: pointer;
}

.bp-cmdk-item-active {
  background: var(--bp-color-selection-surface-soft, rgba(59, 130, 246, 0.14));
  box-shadow: inset 0 0 0 1px var(--bp-color-focus-border, #93c5fd);
}

.bp-cmdk-item-label {
  font-weight: 600;
  color: var(--bp-color-text, #111827);
}

.bp-cmdk-item-detail {
  margin-left: auto;
  font-size: 0.8rem;
  color: var(--bp-color-text-faint, #64748b);
}

.bp-cmdk-empty {
  padding: 0.85rem 0.9rem;
  color: var(--bp-color-text-faint, #64748b);
  font-style: italic;
}

.bp-cmdk-hint {
  padding: 0.5rem 0.9rem;
  font-size: 0.75rem;
  color: var(--bp-color-text-faint, #64748b);
  border-top: 1px solid var(--bp-color-border-soft, #e2e8f0);
  background: var(--bp-color-surface-muted, #f8fafc);
}
"##

end Informal.CommandPalette
