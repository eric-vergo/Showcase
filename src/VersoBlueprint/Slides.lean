/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Std.Data.HashMap
import VersoSlides
import Verso.Doc.ArgParse
import Verso.Doc.Elab
import VersoBlueprint.Commands.Common
import VersoBlueprint.Informal.Block.Assets
import VersoBlueprint.LabelNameParsing
import VersoBlueprint.PreviewManifest
import VersoBlueprint.PreviewCache
import VersoBlueprint.Slides.Render

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
    Informal.Commands.withPreviewPanelInlinePreviewCssAssets
      [Informal.Block.Assets.css, Verso.Genre.Manual.docstringStyle, slideNodeCss]

def blueprintSlidesCssFile : VersoSlides.CssFile where
  filename := blueprintSlidesCssFilename
  contents := ⟨blueprintSlidesCss⟩

/--
Hydrate interactions around Blueprint slide nodes whose HTML shell was rendered
while generating the slide deck.
-/
private def slideNodeHydrationJs : String := r##"(function () {
  if (window.bpSlideNodeRuntime) return;

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

  function hideSlidePreviewPanels() {
    document
      .querySelectorAll("#bp-inline-preview-panel, #bp-inline-preview-child-panel, .bp_preview_panel")
      .forEach(function (panel) {
        if (!(panel instanceof HTMLElement)) return;
        panel.hidden = true;
        panel.style.left = "";
        panel.style.top = "";
      });
  }

  function hydrate(root) {
    const scope = root && typeof root.querySelectorAll === "function" ? root : document;
    scope.querySelectorAll(".bp_slide_node").forEach(function (node) {
      if (!(node instanceof Element)) return;
      const baseUrl = rememberBlueprintBaseUrl(node);
      prepareBlueprintLinks(node, baseUrl);
      const utils = window.bpPreviewUtils;
      if (utils && typeof utils.renderMath === "function") utils.renderMath(node);
      if (utils && typeof utils.hydratePreviewSubtree === "function") utils.hydratePreviewSubtree(node);
    });
  }

  function registerPreviewHydrator() {
    const utils = window.bpPreviewUtils;
    if (!utils || typeof utils.registerPreviewHydrator !== "function") return;
    utils.registerPreviewHydrator("slideBlueprintLinks", function (root) {
      if (!(root instanceof Element)) return;
      prepareBlueprintLinks(root, readBlueprintBaseUrl(root));
    });
  }

  function start() {
    registerPreviewHydrator();
    hydrate(document);
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
    Informal.Commands.inlinePreviewJsAssets ++
      [Informal.Block.Assets.usedByPanelJs, slideNodeHydrationJs]

public def blueprintSlidesExtraJs : Array String :=
  #[blueprintSlidesJsFilename]

private def pushIfMissing [BEq α] (values : Array α) (value : α) : Array α :=
  if values.contains value then values else values.push value

private def writeFileWithDirs (path : System.FilePath) (content : String) : IO Unit := do
  let dir := path.parent.getD "."
  if !(← dir.pathExists) then
    IO.FS.createDirAll dir
  IO.FS.writeFile path content

private def writeBinFileWithDirs (path : System.FilePath) (content : ByteArray) : IO Unit := do
  let dir := path.parent.getD "."
  if !(← dir.pathExists) then
    IO.FS.createDirAll dir
  IO.FS.writeBinFile path content

private inductive SlideAssetPayload where
  | text (body : String)
  | binary (bytes : ByteArray)

private def SlideAssetPayload.equal : SlideAssetPayload → SlideAssetPayload → Bool
  | .text a, .text b => a == b
  | .binary a, .binary b => a == b
  | _, _ => false

private def SlideAssetPayload.kind : SlideAssetPayload → String
  | .text _ => "text"
  | .binary _ => "binary"

private def recordSlideAsset
    (seen : Std.HashMap String (String × SlideAssetPayload))
    (filename source : String) (payload : SlideAssetPayload) :
    IO (Std.HashMap String (String × SlideAssetPayload)) := do
  match seen.get? filename with
  | none => pure <| seen.insert filename (source, payload)
  | some (prevSource, prev) =>
    if prev.equal payload then
      pure seen
    else
      throw <| IO.userError
        s!"Filename collision in config: \"{filename}\" is claimed by {prevSource} ({prev.kind}) and {source} ({payload.kind}) with different contents."

private def collectSlideAssets (config : VersoSlides.Config) :
    IO (Std.HashMap String (String × SlideAssetPayload)) := do
  let mut seen : Std.HashMap String (String × SlideAssetPayload) := {}
  if let .custom theme := config.theme then
    seen ← recordSlideAsset seen theme.stylesheet.filename
      "theme stylesheet" (.text theme.stylesheet.contents.css)
    for asset in theme.assets do
      seen ← recordSlideAsset seen asset.filename
        "theme asset" (.binary asset.contents)
  seen ← recordSlideAsset seen config.highlightTheme.filename
    "highlight.js theme" (.text config.highlightTheme.contents.css)
  for css in config.extraCss do
    seen ← recordSlideAsset seen css.filename
      "extraCss" (.text css.contents.css)
  pure seen

@[reducible] private def defaultSlidesGenreHtml :
    Verso.Doc.Html.GenreHtml VersoSlides.Slides IO :=
  inferInstance

@[reducible] private def blueprintSlidesGenreHtml
    (renderContext : Informal.Slides.RenderContext) :
    Verso.Doc.Html.GenreHtml VersoSlides.Slides IO :=
  { defaultSlidesGenreHtml with
    block := fun inlineHtml blockHtml container contents => do
      match container with
      | .wrap attrs =>
        match renderBlueprintSlideNodeFromAttrs? renderContext attrs with
        | some html => pure html
        | none => defaultSlidesGenreHtml.block inlineHtml blockHtml container contents
      | _ =>
        defaultSlidesGenreHtml.block inlineHtml blockHtml container contents
  }

private def slidesMainWithBlueprintRenderer
    (config : VersoSlides.Config)
    (manifest? : Option Informal.PreviewManifest.File)
    (doc : Verso.Doc.Part VersoSlides.Slides)
    (quiet : Bool := false) : IO UInt32 := do
  let assetPlan ← collectSlideAssets config
  let renderContext := Informal.Slides.RenderContext.ofManifest? manifest?
  let hasError ← IO.mkRef false
  let logError (msg : String) : IO Unit := do
    hasError.set true
    IO.eprintln msg
  let (doc, traverseState) ←
    (VersoSlides.Slides.traverse doc : VersoSlides.TraverseM (Verso.Doc.Part VersoSlides.Slides)) () {}
  let ctx : Verso.Doc.Html.HtmlT.Context VersoSlides.Slides IO := {
    options := { logError := logError }
    traverseContext := ()
    traverseState := traverseState
    definitionIds := {}
    linkTargets := {}
    codeOptions := {}
  }
  let (slidesHtml, hoverState) ←
    (let _ : Verso.Doc.Html.GenreHtml VersoSlides.Slides IO :=
        blueprintSlidesGenreHtml renderContext
     (VersoSlides.renderDocument config doc).run ctx |>.run {})
  let title := VersoSlides.inlinesToPlainText doc.title
  let fullHtml := VersoSlides.renderFullHtml config title slidesHtml traverseState.cssBlocks
  let dir := config.outputDir
  if !(← dir.pathExists) then
    IO.FS.createDirAll dir
  let indexPath := dir / "index.html"
  IO.FS.writeFile indexPath ("<!doctype html>\n" ++ fullHtml.asString)
  IO.FS.writeFile (dir / "-verso-docs.json") (toString hoverState.dedup.docJson)
  VersoSlides.writeVendoredAssets dir config.theme
  for (filename, _source, payload) in assetPlan.toList do
    match payload with
    | .text body => writeFileWithDirs (dir / filename) body
    | .binary bytes => writeBinFileWithDirs (dir / filename) bytes
  if !traverseState.imageFiles.isEmpty then
    let imagesDir := dir / "images"
    IO.FS.createDirAll imagesDir
    for (resolved, outputName) in traverseState.imageFiles.toList do
      let contents ← IO.FS.readBinFile resolved
      writeBinFileWithDirs (imagesDir / outputName) contents
  unless quiet do
    IO.println s!"Slides written to {indexPath}"
  if ← hasError.get then
    IO.eprintln "Errors were encountered!"
    pure 1
  else
    pure 0

/-- Add the Blueprint slide CSS/JS assets to a Verso Slides config. -/
public def withBlueprintSlidesAssets (config : VersoSlides.Config := {}) : VersoSlides.Config :=
  { config with
    extraCss := pushIfMissing config.extraCss blueprintSlidesCssFile
    extraJs := pushIfMissing config.extraJs blueprintSlidesJsFilename }

/-- Write the JavaScript file referenced by {name}`withBlueprintSlidesAssets`. -/
public def writeBlueprintSlidesJs (outputDir : System.FilePath) : IO Unit :=
  writeFileWithDirs (outputDir / blueprintSlidesJsFilename) blueprintSlidesJs

/-- Output path where slide decks expect the shared Blueprint preview manifest. -/
public def blueprintSlidesPreviewManifestPath (outputDir : System.FilePath) : System.FilePath :=
  outputDir / "-verso-data" / Informal.PreviewManifest.manifestFilename

/-- Copy a generated Blueprint shared preview manifest into a slide deck output directory. -/
public def copyBlueprintPreviewManifest
    (outputDir source : System.FilePath) : IO Unit := do
  let contents ← IO.FS.readFile source
  writeFileWithDirs (blueprintSlidesPreviewManifestPath outputDir) contents

/--
Generate a slide deck with Blueprint preview-node assets enabled.

When `previewManifest?` is provided, the manifest is read during slide
generation so `{blueprint_node}` blocks render as static Blueprint shells. The
same manifest is also copied to the deck's
`-verso-data/blueprint-preview-manifest.json` path after the deck is written.
-/
public def slidesMainWithBlueprintPreviews
    (config : VersoSlides.Config := {})
    (previewManifest? : Option System.FilePath := none)
    (doc : Verso.Doc.Part VersoSlides.Slides)
    (quiet : Bool := false) : IO UInt32 := do
  let config := withBlueprintSlidesAssets config
  let manifest? ← previewManifest?.mapM readBlueprintPreviewManifest
  let rc ← slidesMainWithBlueprintRenderer config manifest? doc (quiet := quiet)
  if rc == 0 then
    writeBlueprintSlidesJs config.outputDir
    if let some previewManifest := previewManifest? then
      copyBlueprintPreviewManifest config.outputDir previewManifest
  pure rc

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
  let label := Informal.LabelNameParsing.parse label
  match facet with
  | "statement" => Informal.PreviewCache.key label .statement
  | "proof" => Informal.PreviewCache.key label .proof
  | other => s!"{label}--{other}"

public meta def blueprintNodeBlock (cfg : BlueprintNodeConfig) : DocElabM Term := do
  let facet := cfg.facet.getD "statement"
  let key := previewKey cfg.label facet
  let node : BlueprintSlideNode := {
    label := cfg.label
    facet := facet
    key := key
    title? := cfg.title
    compact := cfg.compact
    siteBase? := cfg.siteBase
  }
  let attrs := node.toAttrs
  let fallback := node.fallbackText
  ``(Verso.Doc.Block.other (VersoSlides.BlockExt.wrap $(quote attrs))
      #[Verso.Doc.Block.para #[Verso.Doc.Inline.text $(quote fallback)]])

end Informal.Slides

open Verso Doc Elab

/--
Render a Blueprint preview-manifest entry by label inside a Verso Slides deck.

Use {name}`Informal.Slides.slidesMainWithBlueprintPreviews` in the deck
generator, or add {name}`Informal.Slides.withBlueprintSlidesAssets` to the
config and call {name}`Informal.Slides.writeBlueprintSlidesJs` manually.
-/
@[block_command]
public meta def blueprint_node : BlockCommandOf Informal.Slides.BlueprintNodeConfig
  | cfg => Informal.Slides.blueprintNodeBlock cfg
