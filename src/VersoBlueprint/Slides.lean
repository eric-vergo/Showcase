/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoSlides
import Verso.Doc.ArgParse
import Verso.Doc.Elab
import VersoBlueprint.Commands.Common

namespace Informal.Slides

open Lean
open Verso Doc Elab ArgParse

def blueprintSlidesCssFilename : String := "blueprint-slides.css"
def blueprintSlidesJsFilename : String := "blueprint-slides.js"

private def slideNodeCss : String := r##"
.bp_slide_node {
  width: min(100%, 1160px);
  margin: 0.55rem auto 0;
  text-align: left;
  color: var(--bp-color-text, #111827);
  font-size: 1.12em;
}

.bp_slide_node_card {
  border: 1px solid var(--bp-color-border, #cbd5e1);
  border-radius: 8px;
  background: var(--bp-color-surface, #ffffff);
  box-shadow: 0 12px 28px rgba(15, 23, 42, 0.14);
  overflow: hidden;
}

.bp_slide_node_header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.75rem 0.9rem 0.65rem;
  border-left: 7px solid #0073a3;
  border-bottom: 1px solid var(--bp-color-border-soft, #e2e8f0);
  background: #eef7fb;
}

.bp_slide_node_title {
  margin: 0;
  color: var(--bp-color-text-strong, #0f172a);
  font-size: 1.2rem;
  line-height: 1.2;
  font-weight: 800;
}

.bp_slide_node_label {
  margin-top: 0.2rem;
  color: var(--bp-color-text-muted, #334155);
  font-family: var(--r-code-font, ui-monospace, SFMono-Regular, Menlo, Consolas, monospace);
  font-size: 0.72rem;
  overflow-wrap: anywhere;
}

.bp_slide_node_kind {
  flex: 0 0 auto;
  border: 1px solid var(--bp-color-border, #cbd5e1);
  border-radius: 999px;
  padding: 0.16rem 0.45rem;
  background: #ffffff;
  color: var(--bp-color-text-muted, #334155);
  font-size: 0.66rem;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.03em;
}

.bp_slide_node_meta {
  display: flex;
  flex-wrap: wrap;
  gap: 0.32rem;
  padding: 0.55rem 0.9rem 0;
}

.bp_slide_node_pill {
  display: inline-flex;
  align-items: center;
  gap: 0.22rem;
  min-width: 0;
  border: 1px solid var(--bp-color-border-soft, #e2e8f0);
  border-radius: 999px;
  background: var(--bp-color-surface-muted, #f8fafc);
  color: var(--bp-color-text-muted, #334155);
  padding: 0.14rem 0.42rem;
  font-size: 0.68rem;
  line-height: 1.25;
}

.bp_slide_node_pill strong {
  color: var(--bp-color-text-strong, #0f172a);
  font-weight: 750;
}

.bp_slide_node_body {
  padding: 0.65rem 0.9rem 0.85rem;
  line-height: 1.35;
  max-height: 16rem;
  overflow: auto;
}

.bp_slide_node_body p {
  margin: 0 0 0.45rem;
}

.bp_slide_node_body p:last-child {
  margin-bottom: 0;
}

.bp_slide_node_body code,
.bp_slide_node_body pre {
  font-size: 0.82em;
}

.bp_slide_node_body pre {
  max-height: 9.5rem;
  overflow: auto;
  margin: 0.4rem 0 0;
}

.bp_slide_node_notice {
  border: 1px solid var(--bp-color-border-soft, #e2e8f0);
  border-radius: 8px;
  background: var(--bp-color-surface-muted, #f8fafc);
  padding: 0.7rem 0.8rem;
  color: var(--bp-color-text-muted, #334155);
}

.bp_slide_node_notice strong {
  color: var(--bp-color-text-strong, #0f172a);
}

.bp_slide_node_blueprint {
  display: flex;
  flex-direction: column;
  gap: 0.42rem;
}

.bp_slide_node .bp_wrapper {
  box-sizing: border-box;
  border: 1px solid var(--bp-color-border, #cbd5e1);
  border-radius: 6px;
  padding: 0.65rem 0.82rem 0.74rem;
  background: var(--bp-color-surface, #ffffff);
  color: var(--bp-color-text, #111827);
  box-shadow: 0 10px 24px rgba(15, 23, 42, 0.12);
  overflow: visible;
}

.bp_slide_node .bp_heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.85rem;
  border-bottom: 1px solid var(--bp-color-border-soft, #e2e8f0);
  padding-bottom: 0.48rem;
}

.bp_slide_node .bp_heading_title_row {
  display: inline-flex;
  align-items: baseline;
  gap: 0.28rem;
  min-width: 0;
}

.bp_slide_node .bp_caption,
.bp_slide_node .bp_label {
  color: var(--bp-color-text-strong, #0f172a);
  font-size: 1.32rem;
  font-weight: 760;
  line-height: 1.1;
}

.bp_slide_node .bp_caption {
  color: #075985;
}

.bp_slide_node .bp_extras {
  display: grid;
  align-items: center;
  justify-content: end;
  grid-template-columns:
    minmax(5.2rem, max-content)
    minmax(5.2rem, max-content)
    max-content
    minmax(6.6rem, max-content);
  grid-template-areas: "group uses code used";
  column-gap: 0.36rem;
  margin-left: auto;
}

.bp_slide_node .bp_extra_slot {
  display: inline-flex;
  align-items: center;
  min-width: 0;
}

.bp_slide_node .bp_extra_slot_group {
  grid-area: group;
  justify-content: flex-start;
}

.bp_slide_node .bp_extra_slot_uses {
  grid-area: uses;
  justify-content: flex-start;
}

.bp_slide_node .bp_extra_slot_code {
  grid-area: code;
  justify-content: flex-end;
}

.bp_slide_node .bp_extra_slot_used_by {
  grid-area: used;
  justify-content: flex-start;
}

.bp_slide_node .bp_extras .bp_inline_preview_ref {
  display: inline-flex;
}

.bp_slide_node .bp_used_by_chip,
.bp_slide_node .bp_code_link,
.bp_slide_node .bp_external_status_badge {
  display: inline-flex;
  align-items: center;
  gap: 0.18rem;
  border: 1px solid var(--bp-color-border-soft, #e2e8f0);
  border-radius: 999px;
  background: var(--bp-color-surface-muted, #f8fafc);
  color: var(--bp-color-text-muted, #334155);
  font-size: 0.78rem;
  font-weight: 700;
  line-height: 1.1;
  padding: 0.22rem 0.58rem;
  white-space: nowrap;
}

.bp_slide_node button.bp_used_by_chip {
  cursor: default;
  font-family: inherit;
}

.bp_slide_node .bp_used_by_wrap {
  display: inline-flex;
  position: relative;
}

.bp_slide_node .bp_used_by_panel {
  box-sizing: border-box;
  display: none;
  position: absolute;
  top: calc(100% + 0.36rem);
  right: 0;
  z-index: 1200;
  width: min(34rem, 82vw);
  max-height: 20rem;
  overflow: auto;
  border: 1px solid var(--bp-color-border, #cbd5e1);
  border-radius: 8px;
  background: var(--bp-color-surface, #ffffff);
  box-shadow: 0 18px 42px rgba(15, 23, 42, 0.2);
  color: var(--bp-color-text, #111827);
  padding: 0.55rem;
}

.bp_slide_node .bp_extra_slot_group .bp_used_by_panel {
  left: 0;
  right: auto;
}

.bp_slide_node .bp_used_by_wrap:hover > .bp_used_by_panel,
.bp_slide_node .bp_used_by_wrap:focus-within > .bp_used_by_panel,
.bp_slide_node .bp_used_by_wrap.bp_used_by_wrap_open > .bp_used_by_panel {
  display: block;
}

.bp_slide_node .bp_used_by_panel_header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 0.75rem;
  border-bottom: 1px solid var(--bp-color-border-soft, #e2e8f0);
  padding-bottom: 0.36rem;
  margin-bottom: 0.45rem;
}

.bp_slide_node .bp_used_by_panel_title {
  color: var(--bp-color-text-strong, #0f172a);
  font-size: 0.98rem;
  font-weight: 800;
}

.bp_slide_node .bp_used_by_panel_meta {
  color: var(--bp-color-text-muted, #64748b);
  font-size: 0.8rem;
}

.bp_slide_node .bp_used_by_panel_body {
  display: grid;
  grid-template-columns: minmax(9.4rem, 0.82fr) minmax(12.5rem, 1.18fr);
  gap: 0.55rem;
}

.bp_slide_node .bp_used_by_list {
  list-style: none;
  margin: 0;
  max-height: 14rem;
  overflow: auto;
  padding: 0;
}

.bp_slide_node .bp_used_by_item + .bp_used_by_item {
  margin-top: 0.22rem;
}

.bp_slide_node .bp_used_by_target {
  display: block;
  border: 1px solid transparent;
  border-radius: 6px;
  color: inherit !important;
  padding: 0.28rem 0.34rem;
  text-decoration: none;
}

.bp_slide_node .bp_used_by_item:hover .bp_used_by_target,
.bp_slide_node .bp_used_by_item:focus-within .bp_used_by_target,
.bp_slide_node .bp_used_by_item.bp_used_by_item_active .bp_used_by_target {
  border-color: var(--bp-color-border-soft, #e2e8f0);
  background: var(--bp-color-surface-muted, #f8fafc);
}

.bp_slide_node .bp_used_by_target_title {
  display: block;
  color: #075985;
  font-size: 0.9rem;
  font-weight: 800;
}

.bp_slide_node .bp_used_by_target_meta {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.24rem;
  color: var(--bp-color-text-muted, #64748b);
  font-size: 0.74rem;
  margin-top: 0.08rem;
}

.bp_slide_node .bp_used_by_axis_badge {
  border: 1px solid var(--bp-color-border-soft, #e2e8f0);
  border-radius: 999px;
  padding: 0.03rem 0.24rem;
}

.bp_slide_node .bp_used_by_preview_surface {
  min-width: 0;
  border-left: 1px solid var(--bp-color-border-soft, #e2e8f0);
  padding-left: 0.55rem;
}

.bp_slide_node .bp_used_by_preview_title {
  color: var(--bp-color-text-strong, #0f172a);
  font-size: 0.94rem;
  font-weight: 800;
  margin-bottom: 0.22rem;
}

.bp_slide_node .bp_used_by_preview_body {
  color: var(--bp-color-text, #111827);
  font-size: 0.9rem;
  line-height: 1.38;
  max-height: 13.5rem;
  overflow: auto;
}

.bp_slide_node .bp_used_by_preview_body p {
  margin: 0 0 0.35rem;
}

.tippy-box[data-theme~='lean'] {
  font-size: 1rem;
  line-height: 1.35;
  max-width: min(34rem, 82vw) !important;
}

.tippy-box[data-theme~='lean'] .hl.lean {
  font-size: inherit;
  line-height: inherit;
}

.tippy-box[data-theme~='lean'] code {
  font-size: 0.94em;
}

.bp_slide_node .bp_code_link_status_proved,
.bp_slide_node .bp_external_status_ok {
  border-color: rgba(22, 163, 74, 0.26);
  background: rgba(22, 163, 74, 0.08);
  color: #166534;
}

.bp_slide_node .bp_code_status_symbol,
.bp_slide_node .bp_external_status_icon {
  color: #16a34a;
  font-weight: 900;
}

.bp_slide_node .bp_content {
  margin-top: 0.35rem;
  padding-left: 0.48rem;
  border-left: 2px solid var(--bp-color-text-muted, #334155);
  line-height: 1.42;
}

.bp_slide_node .bp_content,
.bp_slide_node .bp_content p {
  color: var(--bp-color-text, #111827) !important;
  font-size: 0.84em !important;
  margin: 0;
}

.bp_slide_node .bp_content p {
  line-height: 1.42;
}

.bp_slide_node .bp_content a,
.bp_slide_node .bp_content .bp_inline_preview_ref a {
  color: #0e7490 !important;
  font-size: inherit !important;
  font-weight: 700;
}

.bp_slide_node .bp_content span,
.bp_slide_node .bp_content .bp_inline_preview_ref {
  font-size: inherit !important;
}

.bp_slide_node .bp_slide_node_heading_link {
  color: inherit !important;
  display: inline-flex;
  min-width: 0;
  text-decoration: none;
}

.bp_slide_node .bp_slide_node_heading_link:focus-visible {
  outline: 2px solid var(--bp-color-focus-border, #93c5fd);
  outline-offset: 3px;
}

.bp_slide_node .bp_content .bp_math,
.bp_slide_node .bp_content .katex {
  color: #164e63 !important;
}

.bp_slide_node .bp_code_panel_wrapper {
  margin-top: 0;
}

.bp_slide_node .bp_code_panel {
  border: 0;
}

.bp_slide_node .bp_code_panel > summary {
  cursor: pointer;
  list-style: none;
}

.bp_slide_node .bp_code_panel > summary::-webkit-details-marker {
  display: none;
}

.bp_slide_node .bp_code_summary_text {
  color: #075985;
}

.bp_slide_node .bp_code_summary_label {
  color: var(--bp-color-text-strong, #0f172a);
}

.bp_slide_node .bp_slide_code_body {
  margin-top: 0.38rem;
}

.bp_slide_node .bp_external_decl_list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.bp_slide_node .bp_external_decl_signature_wrap .narrow-only {
  display: none;
}

.bp_slide_node .bp_external_decl_signature_wrap .wide-only {
  display: block;
}

.bp_slide_node .bp_external_decl_item,
.bp_slide_node .bp_external_decl_rendered,
.bp_slide_node .bp_external_decl_rendered .declaration,
.bp_slide_node .bp_external_decl_signature_wrap,
.bp_slide_node .bp_external_decl_signature_wrap .wide-only,
.bp_slide_node .bp_slide_code_signature {
  box-sizing: border-box;
  display: block;
  margin: 0;
  text-align: left;
  width: 100%;
}

.bp_slide_node .bp_external_decl_rendered pre,
.bp_slide_node .bp_slide_code_body pre {
  box-sizing: border-box;
  display: block;
  max-height: 10.2rem;
  overflow: auto;
  width: 100% !important;
  max-width: 100% !important;
  margin: 0.18rem 0 0 !important;
  border: 1px solid var(--bp-color-border-soft, #e2e8f0);
  border-radius: 6px;
  background: var(--bp-color-surface-muted, #f8fafc);
  box-shadow: none !important;
  color: var(--bp-color-text-strong, #0f172a) !important;
  padding: 0.55rem 0.65rem;
  line-height: 1.35;
  font-size: 1.14rem !important;
  white-space: pre-wrap;
}

.bp_slide_node .bp_external_decl_rendered pre *,
.bp_slide_node .bp_slide_code_body pre * {
  color: var(--bp-color-text-strong, #0f172a) !important;
}

.bp_slide_node .bp_external_decl_rendered pre .keyword,
.bp_slide_node .bp_slide_code_body pre .keyword {
  color: #8839a0 !important;
  font-weight: 700;
}

.bp_slide_node .bp_external_decl_rendered pre .const,
.bp_slide_node .bp_slide_code_body pre .const {
  color: #1a5fb4 !important;
}

.bp_slide_node .bp_external_decl_rendered pre .var,
.bp_slide_node .bp_slide_code_body pre .var {
  color: #1a7a6a !important;
}

.bp_slide_node .bp_external_decl_rendered .hover-info {
  display: none;
}

.bp_inline_preview_panel .bp_code_hover_title,
.bp_inline_preview_panel .bp_code_decl_name,
.bp_inline_preview_panel .bp_code_decl_status,
.bp_inline_preview_panel .bp_external_decl_rendered,
.bp_inline_preview_panel .bp_external_decl_signature_wrap,
.bp_inline_preview_panel .bp_external_decl_signature_wrap .wide-only,
.bp_inline_preview_panel .bp_slide_code_signature {
  box-sizing: border-box;
  display: block;
  margin: 0;
  text-align: left;
  width: 100%;
}

.bp_inline_preview_panel .bp_code_hover_title {
  color: var(--bp-color-text-strong, #0f172a);
  font-weight: 800;
  margin-bottom: 0.28rem;
}

.bp_inline_preview_panel .bp_code_hover_list,
.bp_inline_preview_panel .bp_external_decl_list {
  list-style: none;
  margin: 0.25rem 0 0;
  padding: 0;
}

.bp_inline_preview_panel .bp_external_decl_item + .bp_external_decl_item {
  margin-top: 0.38rem;
}

.bp_inline_preview_panel .bp_external_decl_signature_wrap .narrow-only,
.bp_inline_preview_panel .hover-info {
  display: none;
}

.bp_inline_preview_panel .bp_external_decl_signature_wrap pre,
.bp_inline_preview_panel .bp_external_decl_rendered pre,
.bp_inline_preview_panel .bp_slide_code_signature pre {
  box-sizing: border-box;
  display: block;
  max-height: 11rem;
  overflow: auto;
  width: 100% !important;
  max-width: 100% !important;
  margin: 0.2rem 0 0 !important;
  border: 1px solid var(--bp-color-border-soft, #e2e8f0);
  border-radius: 6px;
  background: var(--bp-color-surface-muted, #f8fafc);
  box-shadow: none !important;
  color: var(--bp-color-text-strong, #0f172a) !important;
  padding: 0.55rem 0.65rem;
  line-height: 1.35;
  font-size: 1.05rem !important;
  white-space: pre-wrap;
}

.bp_inline_preview_panel .bp_external_decl_signature_wrap pre *,
.bp_inline_preview_panel .bp_external_decl_rendered pre *,
.bp_inline_preview_panel .bp_slide_code_signature pre * {
  color: var(--bp-color-text-strong, #0f172a) !important;
}

.bp_inline_preview_panel pre .keyword {
  color: #8839a0 !important;
  font-weight: 700;
}

.bp_inline_preview_panel pre .const {
  color: #1a5fb4 !important;
}

.bp_inline_preview_panel pre .var {
  color: #1a7a6a !important;
}

.bp_slide_node_compact .bp_code_panel_wrapper {
  display: none;
}
"##

def blueprintSlidesCss : String :=
  String.intercalate "\n\n" <|
    Informal.Commands.withInlinePreviewCssAssets [slideNodeCss]

def blueprintSlidesCssFile : VersoSlides.CssFile where
  filename := blueprintSlidesCssFilename
  contents := ⟨blueprintSlidesCss⟩

/-
The slide block hydrates preview-manifest JSON in the browser, so it cannot call
`Informal.renderInformalBlockHtml` directly. The JavaScript renderer below keeps
the same standard `HeaderExtras` slot wrapper classes and order.
-/
private def slideNodeJs : String := r##"(function () {
  if (window.bpSlideNodeRuntime) return;

  function escapeHtml(text) {
    return String(text || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function safeArray(value) {
    return Array.isArray(value) ? value : [];
  }

  function trimSlashes(text, side) {
    let value = String(text || "");
    if (side === "left" || side === "both") value = value.replace(/^\/+/, "");
    if (side === "right" || side === "both") value = value.replace(/\/+$/, "");
    return value;
  }

  function readBlueprintBaseUrl(node) {
    if (node instanceof Element) {
      const local = (node.getAttribute("data-bp-site-base") || "").trim();
      if (local) return local;
      const host = node.closest("[data-bp-site-base]");
      if (host instanceof Element) {
        const hostBase = (host.getAttribute("data-bp-site-base") || "").trim();
        if (hostBase) return hostBase;
      }
    }
    const docBase = document.documentElement.getAttribute("data-bp-site-base") || "";
    if (docBase.trim()) return docBase.trim();
    const bodyBase =
      document.body instanceof Element
        ? (document.body.getAttribute("data-bp-site-base") || "").trim()
        : "";
    if (bodyBase) return bodyBase;
    const runtimeBase =
      window.bpSlideNodeRuntimeConfig &&
      typeof window.bpSlideNodeRuntimeConfig.blueprintBaseUrl === "string"
        ? window.bpSlideNodeRuntimeConfig.blueprintBaseUrl
        : "";
    return runtimeBase.trim();
  }

  function rememberBlueprintBaseUrl(node) {
    const baseUrl = readBlueprintBaseUrl(node);
    if (!baseUrl) return "";
    if (!window.bpSlideNodeRuntimeConfig) window.bpSlideNodeRuntimeConfig = {};
    window.bpSlideNodeRuntimeConfig.blueprintBaseUrl = baseUrl;
    return baseUrl;
  }

  function resolveBlueprintHref(href, baseUrl) {
    const raw = String(href || "").trim();
    if (!raw || raw.startsWith("#")) return raw;
    if (/^[a-z][a-z0-9+.-]*:/i.test(raw) || raw.startsWith("//")) return raw;
    const base = String(baseUrl || "").trim();
    if (!base) return raw;
    if (base.startsWith("http://") || base.startsWith("https://") || base.startsWith("/")) {
      return trimSlashes(base, "right") + "/" + trimSlashes(raw, "left");
    }
    return trimSlashes(base, "right") + "/" + trimSlashes(raw, "left");
  }

  function prepareBlueprintLinks(root, baseUrl) {
    if (!(root instanceof Element)) return;
    root.querySelectorAll("a[href]").forEach(function (link) {
      if (!(link instanceof HTMLAnchorElement)) return;
      if (link.getAttribute("data-bp-slide-link") === "blueprint") return;
      const raw = (link.getAttribute("href") || "").trim();
      if (!raw || raw.startsWith("#")) return;
      link.href = resolveBlueprintHref(raw, baseUrl);
      link.target = "bp-slide-blueprint";
      link.rel = "noopener";
      link.setAttribute("data-bp-slide-link", "blueprint");
    });
  }

  function openBlueprintHref(href) {
    const targetHref = String(href || "").trim();
    if (!targetHref) return false;
    const opened = window.open(targetHref, "bp-slide-blueprint");
    if (opened && typeof opened.focus === "function") {
      try {
        opened.focus();
      } catch (_err) {}
    }
    return !!opened;
  }

  function renderPill(label, value) {
    if (value === null || value === undefined || String(value).trim() === "") return "";
    return (
      "<span class=\"bp_slide_node_pill\"><strong>" +
      escapeHtml(label) +
      "</strong> " +
      escapeHtml(value) +
      "</span>"
    );
  }

  function renderDependencyPill(entry) {
    const statementDeps = safeArray(entry.statementDeps);
    const proofDeps = safeArray(entry.proofDeps);
    const count = statementDeps.length + proofDeps.length;
    if (count === 0) return "";
    const label = count === 1 ? "dep" : "deps";
    return renderPill(label, String(count));
  }

  function renderTags(entry) {
    return safeArray(entry.tags)
      .map(function (tag) { return renderPill("tag", tag); })
      .join("");
  }

  function renderMeta(entry) {
    const parts = [
      renderPill("parent", entry.parentTitle || entry.parent),
      renderPill("owner", entry.ownerDisplayName),
      renderPill("priority", entry.priority),
      renderPill("effort", entry.effort),
      renderDependencyPill(entry),
      renderTags(entry)
    ].filter(Boolean);
    if (parts.length === 0) return "";
    return "<div class=\"bp_slide_node_meta\">" + parts.join("") + "</div>";
  }

  function capitalize(text) {
    const raw = String(text || "").trim();
    if (!raw) return "";
    return raw.slice(0, 1).toUpperCase() + raw.slice(1);
  }

  function splitDisplayTitle(entry) {
    const kind = capitalize(entry.kind || entry.targetKind || "Blueprint");
    const title = String(entry.title || "").trim();
    if (title) {
      const match = title.match(/^(\S+)\s+(.+)$/);
      if (match) return { caption: match[1], label: match[2], title: title };
      return { caption: kind, label: title, title: title };
    }
    const label = String(entry.label || "").trim();
    return { caption: kind, label: label, title: kind + (label ? " " + label : "") };
  }

  function manifestEntries() {
    const manifest = window.bpSharedPreviewManifest;
    if (!(manifest instanceof Map)) return [];
    return Array.from(manifest.values());
  }

  function containsLabel(values, label) {
    return safeArray(values).some(function (value) {
      return String(value || "") === label;
    });
  }

  function entryId(entry) {
    return String(entry && (entry.label || entry.key || entry.title) || "").trim();
  }

  function statementPreviewKey(label) {
    const raw = String(label || "").trim();
    return raw ? raw + "--statement" : "";
  }

  function preferStatementEntry(current, next) {
    if (!current) return next;
    if (String(current.facet || "") !== "statement" && String(next && next.facet || "") === "statement") {
      return next;
    }
    return current;
  }

  function titleNumber(entry) {
    const title = String(entry && entry.title || "");
    const match = title.match(/(\d+(?:\.\d+)?)/);
    return match ? Number(match[1]) : Number.POSITIVE_INFINITY;
  }

  function sortEntries(entries) {
    return entries.slice().sort(function (a, b) {
      const aNum = titleNumber(a);
      const bNum = titleNumber(b);
      if (aNum !== bNum) return aNum - bNum;
      return String(a.title || a.label || "").localeCompare(String(b.title || b.label || ""));
    });
  }

  function uniqueEntries(entries) {
    const byId = new Map();
    safeArray(entries).forEach(function (entry) {
      const id = entryId(entry);
      if (!id) return;
      byId.set(id, preferStatementEntry(byId.get(id), entry));
    });
    return sortEntries(Array.from(byId.values()));
  }

  function entryByStatementLabel(label) {
    const target = String(label || "").trim();
    if (!target) return null;
    return manifestEntries().find(function (entry) {
      return (
        entry &&
        entry.targetKind === "block" &&
        String(entry.facet || "") === "statement" &&
        String(entry.label || "").trim() === target
      );
    }) || null;
  }

  function dependencyAxis(entry, label) {
    const inStatement = containsLabel(entry.statementDeps, label);
    const inProof = containsLabel(entry.proofDeps, label);
    if (inStatement && inProof) return "statement, proof";
    if (inProof) return "proof";
    if (inStatement) return "statement";
    return "";
  }

  function dependencyEntries(entry) {
    const labels = [];
    safeArray(entry.statementDeps).concat(safeArray(entry.proofDeps)).forEach(function (label) {
      const raw = String(label || "").trim();
      if (raw && !labels.includes(raw)) labels.push(raw);
    });
    return labels.map(function (label) {
      const manifestEntry = entryByStatementLabel(label);
      const title = manifestEntry && String(manifestEntry.title || "").trim()
        ? String(manifestEntry.title).trim()
        : label;
      return Object.assign(
        {
          label: label,
          key: statementPreviewKey(label),
          title: title,
          axis: dependencyAxis(entry, label)
        },
        manifestEntry || {}
      );
    });
  }

  function usedByEntries(label) {
    if (!label) return [];
    const entries = [];
    manifestEntries().forEach(function (entry) {
      if (!entry || entry.targetKind !== "block") return;
      if (String(entry.facet || "") !== "statement") return;
      if (String(entry.label || "") === label) return;
      const axis = dependencyAxis(entry, label);
      if (axis) {
        entries.push(Object.assign({ axis: axis }, entry));
      }
    });
    return uniqueEntries(entries);
  }

  function groupEntries(entry) {
    const parent = String(entry && entry.parent || "").trim();
    if (!parent) return [];
    return uniqueEntries(manifestEntries().filter(function (candidate) {
      return (
        candidate &&
        candidate.targetKind === "block" &&
        String(candidate.facet || "") === "statement" &&
        String(candidate.parent || "").trim() === parent
      );
    }));
  }

  function codePreviewKeys(entry) {
    return safeArray(entry.leanCodePreviewKeys)
      .map(function (key) { return String(key || "").trim(); })
      .filter(Boolean);
  }

  async function loadCodeEntries(entry, utils) {
    const keys = codePreviewKeys(entry);
    const loaded = [];
    for (const key of keys) {
      const codeEntry = await utils.loadSharedPreviewEntry(key);
      if (codeEntry && typeof codeEntry.html === "string" && codeEntry.html.trim()) {
        loaded.push(codeEntry);
      }
    }
    return loaded;
  }

  function safePreviewId(prefix, value) {
    return prefix + "-" + String(value || "")
      .replace(/[^A-Za-z0-9_-]+/g, "-")
      .replace(/^-+|-+$/g, "");
  }

  function renderPanelEntry(item, currentLabel, idPrefix, axis) {
    const label = String(item.label || "").trim();
    const title = String(item.title || label || "Blueprint entry").trim();
    const href = String(item.href || "").trim();
    const key = String(item.key || statementPreviewKey(label)).trim();
    const active = label && label === currentLabel ? " bp_used_by_item_active" : "";
    const previewId = safePreviewId(idPrefix, label || key || title);
    const axisLabel = String(item.axis || axis || "").trim();
    const target = href
      ? "<a class=\"bp_used_by_target\" href=\"" + escapeHtml(href) + "\">"
      : "<span class=\"bp_used_by_target\">";
    const close = href ? "</a>" : "</span>";
    const axisBadge = axisLabel
      ? "<span class=\"bp_used_by_axis_badge\">" + escapeHtml(axisLabel) + "</span>"
      : "";
    return (
      "<li class=\"bp_used_by_item" + active + "\" data-bp-used-preview-id=\"" +
        escapeHtml(previewId) + "\" data-bp-used-preview-key=\"" + escapeHtml(key) +
        "\" data-bp-used-preview-title=\"" + escapeHtml(title) + "\">" +
        target +
          "<span class=\"bp_used_by_target_title\">" + escapeHtml(title) + "</span>" +
          "<span class=\"bp_used_by_target_meta\"><code>" + escapeHtml(label || key) +
            "</code>" + axisBadge + "</span>" +
        close +
      "</li>"
    );
  }

  function renderSlidePanel(kind, chipText, chipTitle, panelTitle, panelMeta, entries, currentLabel, idPrefix, axis) {
    const count = Array.isArray(entries) ? entries.length : 0;
    const list = count > 0
      ? entries.map(function (item) { return renderPanelEntry(item, currentLabel, idPrefix, axis); }).join("")
      : "<li class=\"bp_used_by_item\"><span class=\"bp_used_by_target\"><span class=\"bp_used_by_target_title\">None</span></span></li>";
    return (
      "<div class=\"bp_used_by_wrap bp_slide_" + escapeHtml(kind) + "_wrap\">" +
        "<button type=\"button\" class=\"bp_used_by_chip\" title=\"" + escapeHtml(chipTitle) +
          "\" aria-expanded=\"false\">" + escapeHtml(chipText) + "</button>" +
        "<div class=\"bp_used_by_panel\" data-bp-slide-panel=\"" + escapeHtml(kind) + "\">" +
          "<div class=\"bp_used_by_panel_header\">" +
            "<div class=\"bp_used_by_panel_title\">" + escapeHtml(panelTitle) + "</div>" +
            "<div class=\"bp_used_by_panel_meta\">" + escapeHtml(panelMeta) + "</div>" +
          "</div>" +
          "<div class=\"bp_used_by_panel_body\">" +
            "<ul class=\"bp_used_by_list\">" + list + "</ul>" +
            "<div class=\"bp_used_by_preview_surface\">" +
              "<div class=\"bp_used_by_preview_title\"></div>" +
              "<div class=\"bp_used_by_preview_body\"></div>" +
            "</div>" +
          "</div>" +
        "</div>" +
      "</div>"
    );
  }

  function renderGroupChip(entry) {
    const title = String(entry.parentTitle || entry.parent || "").trim();
    if (!title) return "";
    const label = String(entry.label || "").trim();
    const entries = groupEntries(entry);
    return (
      "<span class=\"bp_extra_slot bp_extra_slot_group\">" +
        renderSlidePanel(
          "group",
          "group",
          "Other entries in group " + title,
          "Group: " + title + " (" + entries.length + ")",
          "Hover another entry in this group to preview it.",
          entries,
          label,
          "bp-slide-group-" + label,
          ""
        ) +
      "</span>"
    );
  }

  function renderCodeStatusChip(entry, count) {
    if (count <= 0) return "";
    const previewKey = codePreviewKeys(entry)[0] || "";
    const previewTitle = String(entry.label || entry.title || "Lean declarations");
    const chip =
      "<span class=\"bp_code_link bp_code_link_status bp_code_link_status_proved\" " +
        "title=\"Lean declarations (available: " + count + ")\">" +
        "<span class=\"bp_code_status_symbol\">✓</span>" +
        "<span class=\"bp_code_link_label\">L∃∀N</span>" +
      "</span>";
    const body = previewKey
      ? "<span class=\"bp_inline_preview_ref bp_slide_code_chip_preview\" " +
          "data-bp-preview-id=\"bp-slide-code-" + escapeHtml(previewTitle) + "\" " +
          "data-bp-preview-title=\"" + escapeHtml(previewTitle) + "\" " +
          "data-bp-preview-key=\"" + escapeHtml(previewKey) + "\" " +
          "tabindex=\"0\" role=\"button\" aria-label=\"Lean declarations\">" +
          chip +
        "</span>"
      : chip;
    return (
      "<span class=\"bp_extra_slot bp_extra_slot_code\">" +
        "<span class=\"bp_code_summary_preview_root\">" +
          body +
        "</span>" +
      "</span>"
    );
  }

  function renderUsesChip(entries) {
    const count = Array.isArray(entries) ? entries.length : 0;
    if (count <= 0) return "";
    const chipText = "uses " + escapeHtml(String(count));
    return (
      "<span class=\"bp_extra_slot bp_extra_slot_uses\">" +
        renderSlidePanel(
          "uses",
          "uses " + String(count),
          "Statement and proof dependencies",
          "Uses " + String(count),
          "Hover a dependency to preview it.",
          entries,
          "",
          "bp-slide-uses",
          ""
        ) +
      "</span>"
    );
  }

  function renderUsedByChip(entries) {
    const count = Array.isArray(entries) ? entries.length : 0;
    const chipText = "used by " + escapeHtml(String(count));
    if (count > 0) {
      return (
        "<span class=\"bp_extra_slot bp_extra_slot_used_by\">" +
          renderSlidePanel(
            "used-by",
            "used by " + String(count),
            "Reverse dependencies",
            "Used by " + String(count),
            "Hover a use site to preview it.",
            entries,
            "",
            "bp-slide-used-by",
            "statement"
          ) +
        "</span>"
      );
    }
    return (
      "<span class=\"bp_extra_slot bp_extra_slot_used_by\">" +
        "<span class=\"bp_used_by_chip bp_used_by_chip_empty\" title=\"Reverse dependencies\">" +
          chipText +
        "</span>" +
      "</span>"
    );
  }

  function renderExtras(entry, codeCount) {
    const label = String(entry.label || "").trim();
    const group = renderGroupChip(entry);
    const uses = renderUsesChip(dependencyEntries(entry));
    const code = renderCodeStatusChip(entry, codeCount);
    const usedBy = usedByEntries(label);
    const parts = [
      group,
      uses,
      code,
      renderUsedByChip(usedBy)
    ].filter(Boolean);
    if (parts.length === 0) return "";
    const classes = ["bp_extras", "thm_header_extras"];
    if (group) classes.push("bp_extras_with_group");
    if (uses) classes.push("bp_extras_with_uses");
    return "<div class=\"" + classes.join(" ") + "\">" + parts.join("") + "</div>";
  }

  function renderCodeBadge(count) {
    if (count <= 0) return "";
    const noun = count === 1 ? "theorem" : "declarations";
    return (
      "<span class=\"bp_code_summary_indicator\">" +
        "<span class=\"bp_external_status_badge bp_external_status_badge_summary bp_external_status_ok\" " +
          "title=\"Lean declarations: " + count + " available\">" +
          "<span class=\"bp_external_status_icon bp_external_status_ok\">●</span>" +
          "<span class=\"bp_external_status_badge_text\">" + escapeHtml(String(count) + " " + noun) + "</span>" +
        "</span>" +
      "</span>"
    );
  }

  function codeEntrySignatureHtml(codeEntry) {
    const raw = codeEntry && typeof codeEntry.html === "string" ? codeEntry.html : "";
    if (!raw.trim()) return "";
    const template = document.createElement("template");
    template.innerHTML = raw;
    template.content.querySelectorAll(".narrow-only").forEach(function (node) {
      node.remove();
    });
    const pre =
      template.content.querySelector(".bp_external_decl_signature_wrap .wide-only pre") ||
      template.content.querySelector(".bp_external_decl_signature_wrap pre") ||
      template.content.querySelector("pre");
    if (pre instanceof Element) {
      return "<div class=\"bp_slide_code_signature\">" + pre.outerHTML + "</div>";
    }
    const wrapper = document.createElement("div");
    wrapper.appendChild(template.content.cloneNode(true));
    return wrapper.innerHTML;
  }

  function renderCodePanel(entry, codeEntries, parts) {
    if (!Array.isArray(codeEntries) || codeEntries.length === 0) return "";
    const codeHtml = codeEntries.map(codeEntrySignatureHtml).filter(Boolean).join("");
    if (!codeHtml) return "";
    const count = codeEntries.length;
    return (
      "<div class=\"bp_wrapper bp_code_panel_wrapper\">" +
        "<details class=\"bp_code_block bp_code_panel\" open>" +
          "<summary class=\"bp_heading lemma_thmheading\" title=\"Lean code for " +
            escapeHtml(entry.label || parts.title) + "\">" +
            "<span class=\"bp_heading_title_row\">" +
              "<span class=\"bp_caption lemma_thmcaption bp_code_summary_text\">Lean code for " +
                escapeHtml(parts.caption) +
              "</span>" +
              "<span class=\"bp_label lemma_thmlabel bp_code_summary_label\">" +
                escapeHtml(parts.label) +
              "</span>" +
            "</span>" +
            renderCodeBadge(count) +
          "</summary>" +
          "<div class=\"bp_slide_code_body\">" + codeHtml + "</div>" +
        "</details>" +
      "</div>"
    );
  }

  function renderNotice(kind, title, detail) {
    return (
      "<div class=\"bp_slide_node_notice bp_slide_node_notice_" +
      escapeHtml(kind) +
      "\"><strong>" +
      escapeHtml(title) +
      "</strong><br>" +
      escapeHtml(detail) +
      "</div>"
    );
  }

  function loadingHtml(key) {
    return renderNotice("loading", "Loading Blueprint node", key);
  }

  function missingHtml(key) {
    const utils = window.bpPreviewUtils;
    if (utils && typeof utils.readSharedPreviewManifestStatus === "function") {
      const status = utils.readSharedPreviewManifestStatus();
      if (status && status.state === "error" && status.lastError) {
        return renderNotice("error", "Preview manifest unavailable", status.lastError);
      }
    }
    return renderNotice("error", "Blueprint node not found", key);
  }

  function readEntryFacet(entry, node, key) {
    const raw =
      entry && typeof entry.facet === "string"
        ? entry.facet
        : node instanceof Element
          ? node.getAttribute("data-bp-facet") || ""
          : "";
    const facet = String(raw || "").trim().toLowerCase();
    if (facet) return facet;
    return String(key || "").endsWith("--proof") ? "proof" : "statement";
  }

  function entryHref(entry, key, facet, baseUrl) {
    let raw = String(entry && entry.href ? entry.href : "").trim();
    if (facet === "proof" && raw.includes("--statement")) {
      raw = raw.replace("--statement", "--proof");
    }
    return resolveBlueprintHref(raw, baseUrl);
  }

  async function renderEntry(entry, node, key) {
    const utils = window.bpPreviewUtils;
    const parts = splitDisplayTitle(entry);
    const label = entry.label || node.getAttribute("data-bp-label") || key;
    const kind = String(entry.kind || "theorem").toLowerCase();
    const facet = readEntryFacet(entry, node, key);
    const isProof = facet === "proof";
    const renderKind = isProof ? "proof" : kind;
    const html = typeof entry.html === "string" ? entry.html : "";
    const baseUrl = readBlueprintBaseUrl(node);
    const href = entryHref(entry, key, facet, baseUrl);
    const compact = node.getAttribute("data-bp-compact") === "true";
    const codeEntries = compact || !utils ? [] : await loadCodeEntries(entry, utils);
    const titleRow = isProof
      ? "<div class=\"bp_heading_title_row\">" +
          "<span class=\"bp_caption bp_kind_proof_caption proof_caption\" title=\"" +
            escapeHtml(label) + "\">Proof</span>" +
        "</div>"
      : "<div class=\"bp_heading_title_row bp_heading_title_row_statement\">" +
          "<span class=\"bp_caption bp_kind_" + escapeHtml(kind) + "_caption " + escapeHtml(kind) + "_thmcaption\" " +
            "title=\"" + escapeHtml(label) + "\">" + escapeHtml(parts.caption) + "</span>" +
          "<span class=\"bp_label bp_kind_" + escapeHtml(kind) + "_label " + escapeHtml(kind) + "_thmlabel\">" +
            escapeHtml(parts.label) + "</span>" +
        "</div>";
    const linkedTitleRow = href
      ? "<a class=\"bp_slide_node_heading_link\" data-bp-slide-link=\"blueprint\" href=\"" + escapeHtml(href) +
        "\" target=\"bp-slide-blueprint\" rel=\"noopener\" title=\"Open Blueprint node\">" +
        titleRow + "</a>"
      : titleRow;
    const heading =
      "<div class=\"bp_heading bp_kind_" + escapeHtml(renderKind) + "_heading " +
        (isProof ? "proof_heading" : escapeHtml(kind) + "_thmheading") + "\">" +
        linkedTitleRow +
        (isProof ? "" : renderExtras(entry, codeEntries.length)) +
      "</div>";
    const wrapperClass = isProof
      ? "bp_wrapper bp_kind_proof_wrapper proof_thmwrapper proof_wrapper bp_kind_proof bp_style_proof"
      : "bp_wrapper bp_kind_" + escapeHtml(kind) + "_wrapper " + escapeHtml(kind) +
        "_thmwrapper " + escapeHtml(kind) + "_thmwrapper theorem-style-plain bp_kind_" +
        escapeHtml(kind) + " bp_style_plain";
    const contentClass = isProof
      ? "bp_content bp_kind_proof_content proof_content"
      : "bp_content bp_kind_" + escapeHtml(kind) + "_content " + escapeHtml(kind) + "_thmcontent";
    return (
      "<div class=\"bp_slide_node_blueprint\">" +
        "<div class=\"" + wrapperClass + "\" " +
          "title=\"" + escapeHtml(label) + "\">" +
          heading +
          "<div class=\"" + contentClass + "\">" + html + "</div>" +
        "</div>" +
        renderCodePanel(entry, codeEntries, parts) +
      "</div>"
    );
  }

  async function hydrateNode(node) {
    if (!(node instanceof Element)) return;
    const key = (node.getAttribute("data-bp-preview-key") || "").trim();
    if (!key) return;
    if (node.getAttribute("data-bp-slide-node-key") === key) return;
    node.setAttribute("data-bp-slide-node-key", key);
    node.innerHTML = loadingHtml(key);
    const utils = window.bpPreviewUtils;
    if (!utils || typeof utils.loadSharedPreviewEntry !== "function") {
      node.innerHTML = renderNotice(
        "error",
        "Preview runtime unavailable",
        "Rebuild the slide deck with the Blueprint slide assets enabled."
      );
      return;
    }
    const entry = await utils.loadSharedPreviewEntry(key);
    if (!entry) {
      node.removeAttribute("data-bp-slide-node-key");
      node.innerHTML = missingHtml(key);
      return;
    }
    node.innerHTML = await renderEntry(entry, node, key);
    prepareBlueprintLinks(node, rememberBlueprintBaseUrl(node));
    if (typeof utils.renderMath === "function") utils.renderMath(node);
    if (typeof utils.hydratePreviewSubtree === "function") utils.hydratePreviewSubtree(node);
    bindSlideUsedByPanels(node);
  }

  function registerPreviewHydrator() {
    const utils = window.bpPreviewUtils;
    if (!utils || typeof utils.registerPreviewHydrator !== "function") return;
    utils.registerPreviewHydrator("slideBlueprintLinks", function (root) {
      if (!(root instanceof Element)) return;
      prepareBlueprintLinks(root, readBlueprintBaseUrl(root));
      bindSlideUsedByPanels(root);
    });
  }

  function hydrate(root) {
    const scope = root && typeof root.querySelectorAll === "function" ? root : document;
    scope.querySelectorAll(".bp_slide_node[data-bp-preview-key]").forEach(hydrateNode);
    bindSlideUsedByPanels(scope);
  }

  function renderDocstrings(root) {
    if (!root || typeof root.querySelectorAll !== "function") return;
    if (typeof marked === "undefined" || !marked || typeof marked.parse !== "function") return;
    root.querySelectorAll("code.docstring, pre.docstring").forEach(function (node) {
      if (!(node instanceof Element)) return;
      const rendered = document.createElement("div");
      rendered.className = "docstring";
      rendered.innerHTML = marked.parse(node.innerText || "");
      node.parentNode && node.parentNode.replaceChild(rendered, node);
    });
  }

  function leanHoverContent(target) {
    const content = document.createElement("span");
    content.className = "hl lean";
    content.style.display = "block";
    content.style.maxHeight = "300px";
    content.style.overflowY = "auto";
    content.style.overflowX = "hidden";
    const hoverInfo = target.querySelector(".hover-info");
    if (hoverInfo instanceof Element) {
      const clone = hoverInfo.cloneNode(true);
      if (clone instanceof HTMLElement) clone.style.display = "block";
      content.appendChild(clone);
      renderDocstrings(content);
    }
    return content;
  }

  function leanHoverTarget(target) {
    if (!(target instanceof Element)) return null;
    const lean = target.closest(".hl.lean");
    if (!(lean instanceof Element)) return null;
    const token = target.closest(
      ".token, .has-info, .tactic, .level-var, .level-const, .level-op, .sort"
    );
    if (!(token instanceof Element) || !lean.contains(token)) return null;
    if (!token.querySelector(".hover-info")) return null;
    return token;
  }

  function ensureLeanHover(target) {
    const token = leanHoverTarget(target);
    if (!(token instanceof Element)) return null;
    if (token._tippy) return token._tippy;
    if (typeof tippy !== "function") return null;
    tippy(token, {
      content: leanHoverContent,
      maxWidth: "none",
      appendTo: function () { return document.body; },
      interactive: true,
      delay: [100, null],
      followCursor: "initial",
      theme: "lean"
    });
    return token._tippy || null;
  }

  function showPanelPreview(wrap, item) {
    if (!(wrap instanceof Element) || !(item instanceof Element)) return;
    const panel = wrap.querySelector(".bp_used_by_panel");
    const titleNode = wrap.querySelector(".bp_used_by_preview_title");
    const bodyNode = wrap.querySelector(".bp_used_by_preview_body");
    if (!(panel instanceof Element) || !(titleNode instanceof Element) || !(bodyNode instanceof Element)) return;
    wrap.querySelectorAll(".bp_used_by_item_active").forEach(function (active) {
      active.classList.remove("bp_used_by_item_active");
    });
    item.classList.add("bp_used_by_item_active");
    const key = (item.getAttribute("data-bp-used-preview-key") || "").trim();
    const title = (item.getAttribute("data-bp-used-preview-title") || key || "Preview").trim();
    const requestId = String(Date.now()) + "-" + Math.random();
    panel.setAttribute("data-bp-slide-preview-request", requestId);
    titleNode.textContent = title;
    bodyNode.innerHTML = "<div class=\"bp_used_by_preview_message\">Loading preview...</div>";
    const utils = window.bpPreviewUtils;
    if (!key || !utils || typeof utils.loadSharedPreviewEntry !== "function") {
      bodyNode.innerHTML = "<div class=\"bp_used_by_preview_message\">Preview unavailable.</div>";
      return;
    }
    utils.loadSharedPreviewEntry(key).then(function (entry) {
      if (panel.getAttribute("data-bp-slide-preview-request") !== requestId) return;
      const html =
        utils && typeof utils.readPreviewTemplate === "function"
          ? utils.readPreviewTemplate(entry)
          : entry && typeof entry.html === "string"
            ? entry.html
            : "";
      bodyNode.innerHTML = html || "<div class=\"bp_used_by_preview_message\">Preview unavailable.</div>";
      prepareBlueprintLinks(bodyNode, readBlueprintBaseUrl(wrap.closest(".bp_slide_node")));
      if (utils && typeof utils.renderMath === "function") utils.renderMath(bodyNode);
      if (utils && typeof utils.hydratePreviewSubtree === "function") utils.hydratePreviewSubtree(bodyNode);
    });
  }

  function bindSlideUsedByPanels(root) {
    const scope = root && typeof root.querySelectorAll === "function" ? root : document;
    scope.querySelectorAll(".bp_slide_node .bp_used_by_wrap").forEach(function (wrap) {
      if (!(wrap instanceof Element)) return;
      if (wrap.getAttribute("data-bp-slide-used-bound") === "1") return;
      wrap.setAttribute("data-bp-slide-used-bound", "1");
      const button = wrap.querySelector(".bp_used_by_chip");
      const items = Array.from(wrap.querySelectorAll(".bp_used_by_item[data-bp-used-preview-key]"));
      let hideTimer = null;
      function cancelHide() {
        if (hideTimer !== null) {
          window.clearTimeout(hideTimer);
          hideTimer = null;
        }
      }
      function openPanel() {
        cancelHide();
        wrap.classList.add("bp_used_by_wrap_open");
        if (button instanceof HTMLElement) button.setAttribute("aria-expanded", "true");
        const active = wrap.querySelector(".bp_used_by_item_active[data-bp-used-preview-key]");
        const first = active || items[0];
        if (first instanceof Element) showPanelPreview(wrap, first);
      }
      function closePanel() {
        cancelHide();
        wrap.classList.remove("bp_used_by_wrap_open");
        if (button instanceof HTMLElement) button.setAttribute("aria-expanded", "false");
      }
      function scheduleClose() {
        cancelHide();
        hideTimer = window.setTimeout(function () {
          hideTimer = null;
          if (!wrap.matches(":hover") && !wrap.matches(":focus-within")) closePanel();
        }, 180);
      }
      wrap.addEventListener("mouseenter", openPanel);
      wrap.addEventListener("focusin", openPanel);
      wrap.addEventListener("mouseleave", scheduleClose);
      wrap.addEventListener("focusout", function (event) {
        if (event.relatedTarget instanceof Node && wrap.contains(event.relatedTarget)) return;
        scheduleClose();
      });
      items.forEach(function (item) {
        if (!(item instanceof Element)) return;
        item.addEventListener("mouseenter", function () { showPanelPreview(wrap, item); });
        item.addEventListener("focusin", function () { showPanelPreview(wrap, item); });
      });
    });
  }

  let previewCleanupTimer = null;

  function clearSlidePreviewCleanup() {
    if (previewCleanupTimer !== null) {
      window.clearTimeout(previewCleanupTimer);
      previewCleanupTimer = null;
    }
  }

  function hideSlidePreviewPanels() {
    clearSlidePreviewCleanup();
    document
      .querySelectorAll("#bp-inline-preview-panel, #bp-inline-preview-child-panel, .bp_preview_panel")
      .forEach(function (panel) {
        if (!(panel instanceof HTMLElement)) return;
        panel.hidden = true;
        panel.style.left = "";
        panel.style.top = "";
        panel.style.width = "";
        panel.style.minHeight = "";
        panel.querySelectorAll(
          ".bp_inline_preview_panel_title, .bp_preview_panel_title, " +
          ".bp_code_summary_preview_title, .bp_summary_preview_panel_title"
        ).forEach(function (title) {
          if (title instanceof HTMLElement) title.textContent = "";
        });
        panel.querySelectorAll(
          ".bp_inline_preview_panel_body, .bp_preview_panel_body, " +
          ".bp_code_summary_preview_body, .bp_summary_preview_panel_body"
        ).forEach(function (body) {
          if (body instanceof HTMLElement) body.innerHTML = "";
        });
      });
  }

  function pointerIsOnPreviewSurface(target) {
    if (!(target instanceof Element)) return false;
    return !!target.closest(
      ".bp_inline_preview_ref, .bp_inline_preview_panel, .bp_preview_panel, " +
      ".bp_code_summary_preview_wrap_active, .bp_used_by_panel, .bp_used_by_chip"
    );
  }

  function previewSurfaceIsActive() {
    return !!document.querySelector(
      ".bp_inline_preview_ref:hover, .bp_inline_preview_ref:focus-within, " +
      ".bp_inline_preview_panel:hover, .bp_inline_preview_panel:focus-within, " +
      ".bp_preview_panel:hover, .bp_preview_panel:focus-within, " +
      ".bp_code_summary_preview_wrap_active:hover, .bp_code_summary_preview_wrap_active:focus-within, " +
      ".bp_used_by_panel:hover, .bp_used_by_panel:focus-within"
    );
  }

  function scheduleSlidePreviewCleanup() {
    clearSlidePreviewCleanup();
    previewCleanupTimer = window.setTimeout(function () {
      previewCleanupTimer = null;
      if (!previewSurfaceIsActive()) hideSlidePreviewPanels();
    }, 260);
  }

  function start() {
    registerPreviewHydrator();
    hydrate(document);
    document.addEventListener("click", function (event) {
      const target = event.target;
      if (!(target instanceof Element)) return;
      const link = target.closest("a[data-bp-slide-link], .bp_slide_node .bp_slide_node_heading_link");
      if (!(link instanceof HTMLAnchorElement)) return;
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      event.stopPropagation();
      openBlueprintHref(link.href);
    }, true);
    document.addEventListener("mouseover", function (event) {
      const target = event.target;
      if (!(target instanceof Element)) return;
      const host = target.closest("[data-bp-site-base]");
      if (host instanceof Element) rememberBlueprintBaseUrl(host);
      const hover = ensureLeanHover(target);
      if (hover && typeof hover.show === "function") hover.show();
    }, true);
    document.addEventListener("focusin", function (event) {
      const target = event.target;
      if (!(target instanceof Element)) return;
      const host = target.closest("[data-bp-site-base]");
      if (host instanceof Element) rememberBlueprintBaseUrl(host);
      const hover = ensureLeanHover(target);
      if (hover && typeof hover.show === "function") hover.show();
    }, true);
    document.addEventListener("pointermove", function (event) {
      if (pointerIsOnPreviewSurface(event.target)) {
        clearSlidePreviewCleanup();
      } else {
        scheduleSlidePreviewCleanup();
      }
    }, true);
    if (window.Reveal && typeof window.Reveal.on === "function") {
      window.Reveal.on("slidechanged", function (event) {
        hideSlidePreviewPanels();
        hydrate(event.currentSlide || document);
      });
      window.Reveal.on("ready", function (event) {
        hydrate(event.currentSlide || document);
      });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }

  window.bpSlideNodeRuntime = { hydrate: hydrate };
})();"##

def blueprintSlidesJs : String :=
  String.intercalate "\n\n" <|
    Informal.Commands.inlinePreviewJsAssets ++ [slideNodeJs]

def blueprintSlidesExtraJs : Array String :=
  #[blueprintSlidesJsFilename]

def writeBlueprintSlidesJs (outputDir : System.FilePath) : IO Unit :=
  IO.FS.writeFile (outputDir / blueprintSlidesJsFilename) blueprintSlidesJs

public structure BlueprintNodeConfig where
  label : String
  facet : Option String := none
  title : Option String := none
  compact : Bool := false
  siteBase : Option String := none

public meta instance : FromArgs BlueprintNodeConfig DocElabM where
  fromArgs :=
    BlueprintNodeConfig.mk <$>
      .positional `label .string <*>
      .named `facet .string true <*>
      .named `title .string true <*>
      .flag `compact false <*>
      .named `siteBase .string true

private def previewKey (label facet : String) : String :=
  s!"{label}--{facet}"

public meta def blueprintNodeBlock (cfg : BlueprintNodeConfig) : DocElabM Term := do
    let facet := cfg.facet.getD "statement"
    let key := previewKey cfg.label facet
    let className :=
      if cfg.compact then
        "bp_slide_node bp_slide_node_compact"
      else
        "bp_slide_node"
    let mut attrs : Array (String × String) := #[
      ("class", className),
      ("data-bp-label", cfg.label),
      ("data-bp-facet", facet),
      ("data-bp-preview-key", key),
      ("data-bp-compact", if cfg.compact then "true" else "false")
    ]
    if let some title := cfg.title then
      attrs := attrs.push ("data-bp-title", title)
    if let some siteBase := cfg.siteBase then
      attrs := attrs.push ("data-bp-site-base", siteBase)
    let fallback := s!"Loading Blueprint node {cfg.label}..."
    ``(Verso.Doc.Block.other (VersoSlides.BlockExt.wrap $(quote attrs))
        #[Verso.Doc.Block.para #[Verso.Doc.Inline.text $(quote fallback)]])

end Informal.Slides

open Verso Doc Elab

/--
Render a Blueprint preview-manifest entry by label inside a Verso Slides deck.

The slide generator must copy a VBP shared preview manifest to the slide
output's `-verso-data/blueprint-preview-manifest.json` path and include
`Informal.Slides.blueprintSlidesCssFile` plus
`Informal.Slides.blueprintSlidesJs`.
-/
@[block_command]
public meta def blueprint_node : BlockCommandOf Informal.Slides.BlueprintNodeConfig
  | cfg => Informal.Slides.blueprintNodeBlock cfg
