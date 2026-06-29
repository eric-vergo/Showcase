/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean.Data.Options

namespace Informal.Commands

open Lean

register_option verso.blueprint.debug.commands : Bool := {
  defValue := false
  descr := "Emit debug info logs for blueprint graph, summary, and bibliography commands"
}

/--
Escape `&`, `<`, and `>` as JSON `\uXXXX` escapes so a compressed JSON document is
safe to embed verbatim inside an HTML `<script type="application/json">` element.

The escapes are valid JSON and decode to the identical characters, so consumers
parse byte-identical data; they only prevent an author-supplied `</script>`,
`<!--`, or `<![CDATA[` inside a JSON *string value* from terminating (or
re-opening) the script element early. In a compressed JSON document `&`/`<`/`>`
only ever occur inside string literals, so the structural JSON is untouched.
-/
def escapeJsonForScriptEmbed (json : String) : String :=
  json
    |>.replace "&" "\\u0026"
    |>.replace "<" "\\u003c"
    |>.replace ">" "\\u003e"

def blueprintTokensCss : String := r##"
:root {
  --bp-color-surface: #ffffff;
  --bp-color-surface-muted: #f1f4f7;
  --bp-color-surface-subtle: #f7f9fb;
  --bp-color-surface-modern: #f5f8fc;
  --bp-color-surface-warn: #fbf2e9;
  --bp-color-surface-warn-soft: #f5e4d2;
  --bp-color-surface-note: #fbf6ea;
  --bp-color-border: #dbe2ea;
  --bp-color-border-soft: #e6ebf1;
  --bp-color-border-muted: #dbe2ea;
  --bp-color-border-panel: #dbe2ea;
  --bp-color-border-strong: #b4c0cc;
  --bp-color-text-strong: #15212b;
  --bp-color-text: #15212b;
  --bp-color-text-muted: #4d5e6d;
  --bp-color-text-subtle: #5a6b7a;
  --bp-color-text-faint: #7e8d9b;
  --bp-color-accent-success: #1c8c57;
  --bp-color-accent-warning: #b86b2e;
  --bp-color-accent-danger: #dc2626;
  --bp-color-accent-info: #6a4fba;
  --bp-color-status-success-text: #156b43;
  --bp-color-status-warning-text: #8f4e1e;
  --bp-color-status-warning-strong: #7a4419;
  --bp-color-status-warning-border: #d9a878;
  --bp-color-status-warning-border-soft: #e8c9a8;
  --bp-color-status-error-text: #b42318;
  --bp-color-status-error-strong: #8f1d1d;
  --bp-color-status-error-border-soft: #f2c4c4;
  --bp-color-status-note-border: #e3c36b;
  --bp-color-status-note-text: #8f4e1e;
  --bp-color-focus-border: #7fb0e8;
  --bp-color-focus-surface: #eaf1fb;
  --bp-color-focus-ring: rgba(28, 95, 184, 0.18);
  --bp-color-selection: rgba(28, 95, 184, 0.16);
  --bp-color-selection-ring: rgba(28, 95, 184, 0.22);
  --bp-color-selection-surface-strong: rgba(28, 95, 184, 0.28);
  --bp-color-selection-surface-soft: rgba(28, 95, 184, 0.14);
  --bp-color-selection-surface-faint: rgba(28, 95, 184, 0.1);
  --bp-color-selection-shadow-strong: rgba(28, 95, 184, 0.3);
  --bp-color-selection-shadow-soft: rgba(28, 95, 184, 0.24);
  --bp-color-selection-shadow-faint: rgba(28, 95, 184, 0.16);
  --bp-color-target-ring: rgba(28, 95, 184, 0.22);
  --bp-color-target-surface: rgba(28, 95, 184, 0.12);
  --bp-color-target-ring-strong: rgba(28, 95, 184, 0.3);
  --bp-color-modern-border: #d6deea;
  --bp-color-modern-surface-alt: #f5f9ff;
  --bp-color-modern-caption: #e0ecff;
  --bp-color-bold-surface-glow-1: rgba(184, 107, 46, 0.2);
  --bp-color-bold-surface-glow-2: rgba(28, 140, 87, 0.2);
  --bp-color-bold-link: #8f4e1e;
  --bp-color-bold-label: #b86b2e;
  --bp-color-biblio-border: #d6ccff;
  --bp-color-biblio-surface: #faf7ff;
  --bp-color-biblio-border-soft: #e9ddff;
  --bp-color-biblio-surface-soft: #fdfbff;
  --bp-color-biblio-link: #574099;
  --bp-color-status-blocked: #b86b2e;
  --bp-color-status-ready: #1c5fb8;
  --bp-color-status-formalized: #1c8c57;
  --bp-color-status-mathlib: #6a4fba;
  --bp-color-status-blocked-surface: rgba(184, 107, 46, 0.12);
  --bp-color-status-ready-surface: rgba(28, 95, 184, 0.12);
  --bp-color-status-formalized-surface: rgba(28, 140, 87, 0.12);
  --bp-color-status-mathlib-surface: rgba(106, 79, 186, 0.12);
  --bp-color-accent: #1c5fb8;
  --bp-color-on-accent: #ffffff;
  --bp-color-link: #1c5fb8;
  --bp-radius-sm: 5px;
  --bp-radius-md: 8px;
  --bp-radius-lg: 10px;
  --bp-radius-xl: 12px;
  --bp-radius-2xl: 14px;
  --bp-radius-3xl: 18px;
  --bp-radius-pill: 999px;
  --bp-shadow-sm: 0 1px 2px rgba(21, 33, 43, 0.05);
  --bp-shadow-md: 0 4px 16px -6px rgba(21, 33, 43, 0.12);
  --bp-shadow-lg: 0 12px 28px -8px rgba(21, 33, 43, 0.16);
  --bp-shadow-modern: 0 4px 16px -6px rgba(21, 33, 43, 0.1);
  --bp-shadow-bold: 0 7px 0 var(--bp-color-text-strong);
  --bp-shadow-bold-lg: 0 9px 0 var(--bp-color-text-strong);
}

/*
  Dark color scheme for the blueprint design tokens. Purely additive: the :root
  block above keeps the original light palette, so light mode is unchanged. The
  dual `@media (prefers-color-scheme: dark)` + `[data-bp-color-scheme="dark"]`
  form mirrors the core verso-vars.css convention; the explicit
  `[data-bp-color-scheme="light"]` block restores the light palette so a forced
  light choice overrides an OS dark preference. Keep the two dark lists in sync.
*/
@media (prefers-color-scheme: dark) {
  :root {
    --bp-color-surface: #15212e;
    --bp-color-surface-muted: #1b2836;
    --bp-color-surface-subtle: #18242f;
    --bp-color-surface-modern: #17273a;
    --bp-color-surface-warn: #2c2212;
    --bp-color-surface-warn-soft: #3a2c12;
    --bp-color-surface-note: #2c2710;
    --bp-color-border: #22303f;
    --bp-color-border-soft: #1e2b38;
    --bp-color-border-muted: #22303f;
    --bp-color-border-panel: #243340;
    --bp-color-border-strong: #3a4b5c;
    --bp-color-text-strong: #eaf2fb;
    --bp-color-text: #dbe7f2;
    --bp-color-text-muted: #93a4b5;
    --bp-color-text-subtle: #93a4b5;
    --bp-color-text-faint: #75879a;
    --bp-color-accent-success: #36c485;
    --bp-color-accent-warning: #e2974e;
    --bp-color-accent-danger: #f87171;
    --bp-color-accent-info: #a88bf5;
    --bp-color-status-success-text: #6fdcab;
    --bp-color-status-warning-text: #f0b888;
    --bp-color-status-warning-strong: #f0b888;
    --bp-color-status-warning-border: #5e4a22;
    --bp-color-status-warning-border-soft: #4a3a1a;
    --bp-color-status-error-text: #fca5a5;
    --bp-color-status-error-strong: #fecaca;
    --bp-color-status-error-border-soft: #6b2230;
    --bp-color-status-note-border: #5e4a22;
    --bp-color-status-note-text: #f0b888;
    --bp-color-focus-border: #5aa0ff;
    --bp-color-focus-surface: #15273d;
    --bp-color-focus-ring: rgba(90, 160, 255, 0.22);
    --bp-color-selection: rgba(90, 160, 255, 0.26);
    --bp-color-selection-ring: rgba(90, 160, 255, 0.3);
    --bp-color-selection-surface-strong: rgba(90, 160, 255, 0.36);
    --bp-color-selection-surface-soft: rgba(90, 160, 255, 0.2);
    --bp-color-selection-surface-faint: rgba(90, 160, 255, 0.14);
    --bp-color-selection-shadow-strong: rgba(90, 160, 255, 0.4);
    --bp-color-selection-shadow-soft: rgba(90, 160, 255, 0.32);
    --bp-color-selection-shadow-faint: rgba(90, 160, 255, 0.22);
    --bp-color-target-ring: rgba(90, 160, 255, 0.3);
    --bp-color-target-surface: rgba(90, 160, 255, 0.2);
    --bp-color-target-ring-strong: rgba(90, 160, 255, 0.38);
    --bp-color-modern-border: #243340;
    --bp-color-modern-surface-alt: #17273a;
    --bp-color-modern-caption: #21344e;
    --bp-color-bold-surface-glow-1: rgba(226, 151, 78, 0.16);
    --bp-color-bold-surface-glow-2: rgba(54, 196, 133, 0.16);
    --bp-color-bold-link: #f0b888;
    --bp-color-bold-label: #e2974e;
    --bp-color-biblio-border: #3a2f63;
    --bp-color-biblio-surface: #1e1838;
    --bp-color-biblio-border-soft: #322a55;
    --bp-color-biblio-surface-soft: #1b1633;
    --bp-color-biblio-link: #c4b5fd;
    --bp-color-status-blocked: #e2974e;
    --bp-color-status-ready: #5aa0ff;
    --bp-color-status-formalized: #36c485;
    --bp-color-status-mathlib: #a88bf5;
    --bp-color-status-blocked-surface: rgba(226, 151, 78, 0.18);
    --bp-color-status-ready-surface: rgba(90, 160, 255, 0.18);
    --bp-color-status-formalized-surface: rgba(54, 196, 133, 0.18);
    --bp-color-status-mathlib-surface: rgba(168, 139, 245, 0.18);
    --bp-color-accent: #5aa0ff;
    --bp-color-on-accent: #0e1722;
    --bp-color-link: #5aa0ff;
    --bp-shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.4);
    --bp-shadow-md: 0 6px 20px -6px rgba(0, 0, 0, 0.55);
    --bp-shadow-lg: 0 14px 30px -8px rgba(0, 0, 0, 0.6);
    --bp-shadow-modern: 0 6px 20px -6px rgba(0, 0, 0, 0.5);
  }
}

:root[data-bp-color-scheme="dark"] {
  --bp-color-surface: #15212e;
  --bp-color-surface-muted: #1b2836;
  --bp-color-surface-subtle: #18242f;
  --bp-color-surface-modern: #17273a;
  --bp-color-surface-warn: #2c2212;
  --bp-color-surface-warn-soft: #3a2c12;
  --bp-color-surface-note: #2c2710;
  --bp-color-border: #22303f;
  --bp-color-border-soft: #1e2b38;
  --bp-color-border-muted: #22303f;
  --bp-color-border-panel: #243340;
  --bp-color-border-strong: #3a4b5c;
  --bp-color-text-strong: #eaf2fb;
  --bp-color-text: #dbe7f2;
  --bp-color-text-muted: #93a4b5;
  --bp-color-text-subtle: #93a4b5;
  --bp-color-text-faint: #75879a;
  --bp-color-accent-success: #36c485;
  --bp-color-accent-warning: #e2974e;
  --bp-color-accent-danger: #f87171;
  --bp-color-accent-info: #a88bf5;
  --bp-color-status-success-text: #6fdcab;
  --bp-color-status-warning-text: #f0b888;
  --bp-color-status-warning-strong: #f0b888;
  --bp-color-status-warning-border: #5e4a22;
  --bp-color-status-warning-border-soft: #4a3a1a;
  --bp-color-status-error-text: #fca5a5;
  --bp-color-status-error-strong: #fecaca;
  --bp-color-status-error-border-soft: #6b2230;
  --bp-color-status-note-border: #5e4a22;
  --bp-color-status-note-text: #f0b888;
  --bp-color-focus-border: #5aa0ff;
  --bp-color-focus-surface: #15273d;
  --bp-color-focus-ring: rgba(90, 160, 255, 0.22);
  --bp-color-selection: rgba(90, 160, 255, 0.26);
  --bp-color-selection-ring: rgba(90, 160, 255, 0.3);
  --bp-color-selection-surface-strong: rgba(90, 160, 255, 0.36);
  --bp-color-selection-surface-soft: rgba(90, 160, 255, 0.2);
  --bp-color-selection-surface-faint: rgba(90, 160, 255, 0.14);
  --bp-color-selection-shadow-strong: rgba(90, 160, 255, 0.4);
  --bp-color-selection-shadow-soft: rgba(90, 160, 255, 0.32);
  --bp-color-selection-shadow-faint: rgba(90, 160, 255, 0.22);
  --bp-color-target-ring: rgba(90, 160, 255, 0.3);
  --bp-color-target-surface: rgba(90, 160, 255, 0.2);
  --bp-color-target-ring-strong: rgba(90, 160, 255, 0.38);
  --bp-color-modern-border: #243340;
  --bp-color-modern-surface-alt: #17273a;
  --bp-color-modern-caption: #21344e;
  --bp-color-bold-surface-glow-1: rgba(226, 151, 78, 0.16);
  --bp-color-bold-surface-glow-2: rgba(54, 196, 133, 0.16);
  --bp-color-bold-link: #f0b888;
  --bp-color-bold-label: #e2974e;
  --bp-color-biblio-border: #3a2f63;
  --bp-color-biblio-surface: #1e1838;
  --bp-color-biblio-border-soft: #322a55;
  --bp-color-biblio-surface-soft: #1b1633;
  --bp-color-biblio-link: #c4b5fd;
  --bp-color-status-blocked: #e2974e;
  --bp-color-status-ready: #5aa0ff;
  --bp-color-status-formalized: #36c485;
  --bp-color-status-mathlib: #a88bf5;
  --bp-color-status-blocked-surface: rgba(226, 151, 78, 0.18);
  --bp-color-status-ready-surface: rgba(90, 160, 255, 0.18);
  --bp-color-status-formalized-surface: rgba(54, 196, 133, 0.18);
  --bp-color-status-mathlib-surface: rgba(168, 139, 245, 0.18);
  --bp-color-accent: #5aa0ff;
  --bp-color-on-accent: #0e1722;
  --bp-color-link: #5aa0ff;
  --bp-shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.4);
  --bp-shadow-md: 0 6px 20px -6px rgba(0, 0, 0, 0.55);
  --bp-shadow-lg: 0 14px 30px -8px rgba(0, 0, 0, 0.6);
  --bp-shadow-modern: 0 6px 20px -6px rgba(0, 0, 0, 0.5);
}

:root[data-bp-color-scheme="light"] {
  --bp-color-surface: #ffffff;
  --bp-color-surface-muted: #f1f4f7;
  --bp-color-surface-subtle: #f7f9fb;
  --bp-color-surface-modern: #f5f8fc;
  --bp-color-surface-warn: #fbf2e9;
  --bp-color-surface-warn-soft: #f5e4d2;
  --bp-color-surface-note: #fbf6ea;
  --bp-color-border: #dbe2ea;
  --bp-color-border-soft: #e6ebf1;
  --bp-color-border-muted: #dbe2ea;
  --bp-color-border-panel: #dbe2ea;
  --bp-color-border-strong: #b4c0cc;
  --bp-color-text-strong: #15212b;
  --bp-color-text: #15212b;
  --bp-color-text-muted: #4d5e6d;
  --bp-color-text-subtle: #5a6b7a;
  --bp-color-text-faint: #7e8d9b;
  --bp-color-accent-success: #1c8c57;
  --bp-color-accent-warning: #b86b2e;
  --bp-color-accent-danger: #dc2626;
  --bp-color-accent-info: #6a4fba;
  --bp-color-status-success-text: #156b43;
  --bp-color-status-warning-text: #8f4e1e;
  --bp-color-status-warning-strong: #7a4419;
  --bp-color-status-warning-border: #d9a878;
  --bp-color-status-warning-border-soft: #e8c9a8;
  --bp-color-status-error-text: #b42318;
  --bp-color-status-error-strong: #8f1d1d;
  --bp-color-status-error-border-soft: #f2c4c4;
  --bp-color-status-note-border: #e3c36b;
  --bp-color-status-note-text: #8f4e1e;
  --bp-color-focus-border: #7fb0e8;
  --bp-color-focus-surface: #eaf1fb;
  --bp-color-focus-ring: rgba(28, 95, 184, 0.18);
  --bp-color-selection: rgba(28, 95, 184, 0.16);
  --bp-color-selection-ring: rgba(28, 95, 184, 0.22);
  --bp-color-selection-surface-strong: rgba(28, 95, 184, 0.28);
  --bp-color-selection-surface-soft: rgba(28, 95, 184, 0.14);
  --bp-color-selection-surface-faint: rgba(28, 95, 184, 0.1);
  --bp-color-selection-shadow-strong: rgba(28, 95, 184, 0.3);
  --bp-color-selection-shadow-soft: rgba(28, 95, 184, 0.24);
  --bp-color-selection-shadow-faint: rgba(28, 95, 184, 0.16);
  --bp-color-target-ring: rgba(28, 95, 184, 0.22);
  --bp-color-target-surface: rgba(28, 95, 184, 0.12);
  --bp-color-target-ring-strong: rgba(28, 95, 184, 0.3);
  --bp-color-modern-border: #d6deea;
  --bp-color-modern-surface-alt: #f5f9ff;
  --bp-color-modern-caption: #e0ecff;
  --bp-color-bold-surface-glow-1: rgba(184, 107, 46, 0.2);
  --bp-color-bold-surface-glow-2: rgba(28, 140, 87, 0.2);
  --bp-color-bold-link: #8f4e1e;
  --bp-color-bold-label: #b86b2e;
  --bp-color-biblio-border: #d6ccff;
  --bp-color-biblio-surface: #faf7ff;
  --bp-color-biblio-border-soft: #e9ddff;
  --bp-color-biblio-surface-soft: #fdfbff;
  --bp-color-biblio-link: #574099;
  --bp-color-status-blocked: #b86b2e;
  --bp-color-status-ready: #1c5fb8;
  --bp-color-status-formalized: #1c8c57;
  --bp-color-status-mathlib: #6a4fba;
  --bp-color-status-blocked-surface: rgba(184, 107, 46, 0.12);
  --bp-color-status-ready-surface: rgba(28, 95, 184, 0.12);
  --bp-color-status-formalized-surface: rgba(28, 140, 87, 0.12);
  --bp-color-status-mathlib-surface: rgba(106, 79, 186, 0.12);
  --bp-color-accent: #1c5fb8;
  --bp-color-on-accent: #ffffff;
  --bp-color-link: #1c5fb8;
  --bp-radius-sm: 5px;
  --bp-radius-md: 8px;
  --bp-radius-lg: 10px;
  --bp-radius-xl: 12px;
  --bp-radius-2xl: 14px;
  --bp-radius-3xl: 18px;
  --bp-radius-pill: 999px;
  --bp-shadow-sm: 0 1px 2px rgba(21, 33, 43, 0.05);
  --bp-shadow-md: 0 4px 16px -6px rgba(21, 33, 43, 0.12);
  --bp-shadow-lg: 0 12px 28px -8px rgba(21, 33, 43, 0.16);
  --bp-shadow-modern: 0 4px 16px -6px rgba(21, 33, 43, 0.1);
}
"##

def previewPanelCss : String := r##"
.bp_preview_panel {
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-lg);
  background: var(--bp-color-surface);
  box-shadow: var(--bp-shadow-md);
  padding: 0.65rem 0.75rem;
}

.bp_preview_panel[hidden] {
  display: none !important;
}

.bp_preview_panel[data-bp-preview-placement="anchored"]::before {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  top: -0.85rem;
  height: 0.85rem;
}

.bp_preview_panel[data-bp-preview-placement="anchored"]::after {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  bottom: -0.85rem;
  height: 0.85rem;
}

.bp_preview_panel_header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  margin-bottom: 0.4rem;
}

.bp_preview_panel_title {
  font-weight: 700;
  color: var(--bp-color-text);
  min-width: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.bp_preview_panel_close {
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-sm);
  background: var(--bp-color-surface);
  color: var(--bp-color-text-strong);
  font-size: 0.72rem;
  font-weight: 600;
  line-height: 1;
  padding: 0.25rem 0.45rem;
  cursor: pointer;
}

.bp_preview_panel[data-bp-preview-mode="hover"] .bp_preview_panel_close {
  display: none;
}

.bp_preview_panel_body {
  border-left: 2px solid var(--bp-color-border-soft);
  overflow: auto;
}
"##

def previewHeaderCss : String := r##"
.bp_preview_header_heading {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 0.42rem;
  flex: 1 1 auto;
  min-width: 0;
}

.bp_preview_header_heading > *:first-child {
  min-width: 0;
}

.bp_preview_header_label {
  margin-left: auto;
  max-width: 100%;
  color: var(--bp-color-text-muted);
  font-family: var(--bp-font-mono, ui-monospace, SFMono-Regular, Menlo, Consolas, monospace);
  font-size: 0.72rem;
  font-weight: 600;
  overflow-wrap: anywhere;
  text-align: right;
  text-decoration: none;
}

.bp_preview_header_label[href]:hover {
  color: var(--bp-color-link);
  text-decoration: underline;
}

.bp_preview_header_label[hidden] {
  display: none;
}
"##

def inlinePreviewCss : String := r##"
.bp_inline_preview_ref {
  cursor: pointer;
}

.bp_inline_preview_panel {
  position: fixed;
  display: flex;
  flex-direction: column;
  z-index: 70;
  min-width: 18rem;
  max-width: min(34rem, 86vw);
  max-height: min(26rem, 80vh);
  overflow: hidden;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-md);
  background: var(--bp-color-surface);
  box-shadow: var(--bp-shadow-lg);
}

.bp_inline_preview_panel[hidden] {
  display: none !important;
}

.bp_inline_preview_panel_child {
  z-index: 71;
}

.bp_inline_preview_panel[hidden] {
  display: none;
}

.bp_inline_preview_panel[data-bp-preview-placement="anchored"]::before {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  top: -0.85rem;
  height: 0.85rem;
}

.bp_inline_preview_panel[data-bp-preview-placement="docked"] {
  top: 0.9rem;
  right: 0.9rem;
  left: auto;
}

.bp_inline_preview_panel_header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.6rem;
  padding: 0.4rem 0.55rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  background: var(--bp-color-surface-muted);
}

.bp_inline_preview_panel_title {
  font-size: 0.82rem;
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_inline_preview_panel_close {
  border: 1px solid var(--bp-color-border);
  border-radius: 0.3rem;
  background: var(--bp-color-surface);
  color: var(--bp-color-text-muted);
  font-size: 0.72rem;
  line-height: 1;
  padding: 0.2rem 0.35rem;
  cursor: pointer;
}

.bp_inline_preview_panel_body {
  padding: 0.5rem 0.6rem 0.55rem;
  min-height: 0;
  max-height: min(22rem, 70vh);
  overflow: auto;
  font-size: 0.8rem;
}

.bp_inline_preview_panel_footer {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.35rem;
  padding: 0.38rem 0.55rem 0.42rem;
  border-top: 1px solid var(--bp-color-border-soft);
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-subtle);
  font-size: 0.72rem;
}

.bp_inline_preview_panel_footer[hidden] {
  display: none;
}

.bp_inline_preview_panel_footer code {
  font-size: 0.72rem;
}

.bp_bibliography_hover_entry {
  border: 1px solid var(--bp-color-border-soft);
  border-radius: 0.4rem;
  padding: 0.35rem 0.45rem;
  background: var(--bp-color-surface-muted);
}

.bp_bibliography_hover_entry .citation {
  display: block;
  line-height: 1.35;
}

.bp_bibliography_hover_meta {
  margin-top: 0.42rem;
  display: flex;
  align-items: baseline;
  gap: 0.42rem;
  flex-wrap: wrap;
}

.bp_bibliography_hover_meta_label {
  font-size: 0.68rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--bp-color-text-faint);
}

.bp_bibliography_hover_meta_value {
  font-size: 0.76rem;
  font-weight: 600;
  color: var(--bp-color-text-strong);
}

.bp_code_hover_section {
  margin-top: 0.28rem;
}

.bp_code_hover_label {
  font-weight: 600;
  color: var(--bp-color-text-muted);
}

.bp_code_hover_list code {
  font-size: 0.76rem;
}

.bp_code_hover_none {
  color: var(--bp-color-text-faint);
  font-style: italic;
}

.bp_inline_preview_panel[data-bp-preview-mode="hover"] .bp_inline_preview_panel_close {
  display: none;
}
"##

/--
Logical Blueprint browser assets before choosing a physical output mode.

Manual renderers currently inline these lists through Verso `HtmlAssets`.
JavaScript startup is supplied by the generated ESM page runtime instead of
these command-local bundles.
-/
structure BlueprintAssetBundle where
  css : List String := []
  js : List String := []
deriving Inhabited

namespace BlueprintAssetBundle

def append (left right : BlueprintAssetBundle) : BlueprintAssetBundle :=
  { css := left.css ++ right.css
    js := left.js ++ right.js }

def withCss (assets : BlueprintAssetBundle) (extras : List String) : BlueprintAssetBundle :=
  { assets with css := assets.css ++ extras }

def withJs (assets : BlueprintAssetBundle) (before after : List String) : BlueprintAssetBundle :=
  { assets with js := before ++ assets.js ++ after }

end BlueprintAssetBundle

def blueprintCssAssetBundle (extras : List String := []) : BlueprintAssetBundle :=
  ({ css := [blueprintTokensCss] } : BlueprintAssetBundle).withCss extras

def previewPanelCssAssetBundle (extras : List String := []) : BlueprintAssetBundle :=
  (blueprintCssAssetBundle [previewPanelCss]).withCss extras

def inlinePreviewCssAssetBundle (extras : List String := []) : BlueprintAssetBundle :=
  (blueprintCssAssetBundle extras).withCss [previewHeaderCss, inlinePreviewCss]

def previewPanelInlinePreviewCssAssetBundle (extras : List String := []) : BlueprintAssetBundle :=
  (previewPanelCssAssetBundle extras).withCss [previewHeaderCss, inlinePreviewCss]

def previewPanelAssetBundle
    (cssExtras : List String := [])
    (jsBefore : List String := [])
    (jsAfter : List String := []) : BlueprintAssetBundle :=
  (previewPanelCssAssetBundle cssExtras).append
    ({ js := jsBefore ++ jsAfter } : BlueprintAssetBundle)

def inlinePreviewAssetBundle
    (cssExtras : List String := [])
    (jsBefore : List String := [])
    (jsAfter : List String := []) : BlueprintAssetBundle :=
  (inlinePreviewCssAssetBundle cssExtras).append
    ({ js := jsBefore ++ jsAfter } : BlueprintAssetBundle)

def previewPanelInlinePreviewAssetBundle
    (cssExtras : List String := [])
    (jsBefore : List String := [])
    (jsAfter : List String := []) : BlueprintAssetBundle :=
  (previewPanelInlinePreviewCssAssetBundle cssExtras).append
    ({ js := jsBefore ++ jsAfter } : BlueprintAssetBundle)

end Informal.Commands
