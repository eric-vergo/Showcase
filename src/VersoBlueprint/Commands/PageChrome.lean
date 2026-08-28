/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean

/-!
Styling for the two server-rendered static page frames — node pages and declaration
pages: the breadcrumb trail, the header row that holds it, the section rhythm, and the
declaration page's fully-qualified-name subtitle and docstring-provenance chip.

These rules used to be emitted as an inline `<style>` inside each page's own header,
where they were correct but repeated: a site with tens of thousands of declaration pages
paid the same few kilobytes once per page. They live here, upstream of `NodePage` and
`DeclPage`, so `PreviewManifest`'s site-wide `extraCss` channel can carry them — which
means `shareBlueprintChrome` writes them once into `-verso-data/bp-chrome.css` with the
rest of the design system, and the pages emit no `<style>` at all.

Moving them from the page body into the `<head>` is safe because nothing here relies on
winning a cascade tie against another stylesheet: the only rule anywhere else that
matches these elements is `NodeCard`'s `main > .content-wrapper .bp_node_page section`,
which has strictly higher specificity and therefore won before the move as well.

Everything is `--bp-*` design tokens (with light literal fallbacks), so light and dark
come from the four scheme blocks in `Commands/Common.lean` for free.
-/

namespace Informal.PageChrome

/-- The node/declaration page frame: breadcrumb trail (Book › Chapter › node), the
header row that holds it, and the page's section rhythm. -/
def nodePageCss : String := r##"
.bp_node_page_topbar {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem 0.9rem;
  align-items: center;
  justify-content: space-between;
  margin: 0 0 0.6rem;
}

.bp_node_breadcrumb {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.1rem 0.35rem;
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-caption, 0.78rem);
  letter-spacing: 0.02em;
  color: var(--bp-color-text-muted, #4d5e6d);
}

.bp_node_breadcrumb a {
  color: var(--bp-color-accent, #1c5fb8);
  text-decoration: none;
}

.bp_node_breadcrumb a:hover {
  text-decoration: underline;
}

.bp_node_breadcrumb_sep {
  color: var(--bp-color-text-faint, #5f6f7e);
}

.bp_node_breadcrumb_current {
  color: var(--bp-color-text, #15212b);
  font-weight: 600;
}

.bp_node_page_group {
  color: var(--bp-color-text-muted, #4d5e6d);
  font-size: var(--bp-fs-small, 0.875rem);
  margin: 0.25rem 0 0;
}

.bp_node_page_graph_note {
  margin: 0 0 var(--bp-space-2, 8px);
  color: var(--bp-color-text-muted, #4d5e6d);
  font-size: var(--bp-fs-small, 0.875rem);
}

.bp_node_page h2 {
  font-size: 1.15rem;
  font-weight: 600;
}

.bp_node_page > section {
  margin-top: var(--bp-space-5, 1.5rem);
}
"##

/-- Extra styling for declaration pages: the muted fully-qualified-name subtitle under
the clean card header, and the quiet provenance chip on the informal-statement cell. -/
def declPageCss : String := r##"
.bp_decl_page_fq {
  margin-top: var(--bp-space-1);
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-caption, 0.78rem);
  font-style: normal;
  font-weight: 400;
  color: var(--bp-color-text-muted);
  overflow-wrap: anywhere;
}

/* Quiet provenance marker for the informal-statement cell: notes that the shown
   prose is derived from the declaration's docstring. A restrained hairline chip in
   the status-dot register (small, muted); tokens only, so both themes come for
   free. */
.bp_decl_provenance {
  display: inline-flex;
  align-items: center;
  margin-top: var(--bp-space-3);
  padding: 0.05rem var(--bp-space-2);
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-pill);
  font-size: var(--bp-fs-badge, 0.72rem);
  line-height: 1.5;
  color: var(--bp-color-text-faint);
}
"##

end Informal.PageChrome
