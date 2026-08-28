/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint.PreviewManifest

/-!
Tests for the shared static chrome: the blueprint's page-wide CSS and its bulkier
scripts are written once to `-verso-data/bp-chrome.{css,js}` and linked, instead of
being inlined into every page's `<head>`.

`Informal.PreviewManifest.shareBlueprintChrome` is the whole of it — it runs at the
one point every emit path funnels through — so these tests drive it directly, both
on a synthetic asset set and on the real `blueprintHtmlAssets` bundle.
-/

namespace Verso.VersoBlueprintTests.BlueprintSharedChrome

open Verso.Genre.Manual
open Informal.PreviewManifest

private def pad (chunks : Nat) : String :=
  String.join (List.replicate chunks "0123456789")

/-- A script comfortably over `inlineJsByteBudget`. -/
private def bulkyJs : String :=
  "// BULKY-MARKER\nwindow.bulky = \"" ++ pad 400 ++ "\";\n"

/-- A script comfortably under `inlineJsByteBudget`. -/
private def tinyJs : String :=
  "// TINY-MARKER\nwindow.tiny = 1;\n"

/-! ## Which scripts keep their inline `<script>` -/

-- Size decides, except that the pre-paint appliers are pinned inline whatever the
-- budget is: they must set the color scheme and text size before first paint, and
-- an external file would put that behind a separate request.
/-- info: (false, true, true, true) -/
#guard_msgs in
#eval
  (mustStayInlineJs bulkyJs,
   mustStayInlineJs tinyJs,
   mustStayInlineJs Informal.ColorScheme.applierJs,
   mustStayInlineJs Informal.TextSize.applierJs)

/-! ## The move itself -/

private def sample : HtmlAssets where
  extraCss := (["/* CSS-A */ .a { color: red }", "/* CSS-B */ .b { color: blue }"] : List String)
  extraJs := ([bulkyJs, tinyJs, Informal.ColorScheme.applierJs] : List String)

private def sampleShared : HtmlAssets := shareBlueprintChrome sample

private def cssFileText (assets : HtmlAssets) : String :=
  String.join (assets.extraCssFiles.toArray.toList.map (·.contents.css))

private def jsFileText (assets : HtmlAssets) : String :=
  String.join (assets.extraJsFiles.toArray.toList.map (·.contents.js))

private def has (haystack needle : String) : Bool :=
  (haystack.splitOn needle).length > 1

/-- info: true -/
#guard_msgs in
#eval
  let cssFiles := sampleShared.extraCssFiles.toArray
  let jsFiles := sampleShared.extraJsFiles.toArray
  -- Nothing bulky is left inline …
  sampleShared.extraCss.isEmpty &&
    sampleShared.extraJs.size == 2 &&
    -- … one stylesheet and one script file appear, under stable names …
    cssFiles.size == 1 && jsFiles.size == 1 &&
    cssFiles.map (·.filename) == #[sharedChromeCssFilename] &&
    jsFiles.map (·.filename) == #[sharedChromeJsFilename]

-- Contents: every CSS chunk lands in the stylesheet, in the order Verso would have
-- emitted the `<style>` tags in; the bulky script lands in the script file and the
-- inline-pinned ones do not.
/-- info: true -/
#guard_msgs in
#eval
  let css := cssFileText sampleShared
  let js := jsFileText sampleShared
  let inlineJs := String.join (sampleShared.extraJs.toArray.toList.map (·.js))
  -- The chunks appear in `extraCss`'s own iteration order — the order Verso would
  -- have emitted the `<style>` tags in — so the cascade is unchanged.
  has css (String.intercalate "\n\n" (sample.extraCss.toArray.toList.map (·.css))) &&
    has js "BULKY-MARKER" &&
    !has js "TINY-MARKER" &&
    has inlineJs "TINY-MARKER" &&
    !has inlineJs "BULKY-MARKER"

-- Idempotent: `--resume-from` re-applies this to a state that already went through
-- it, and must not produce a second (empty) file or drop the inline remainder.
/-- info: true -/
#guard_msgs in
#eval
  let twice := shareBlueprintChrome sampleShared
  twice.extraCss.isEmpty &&
    twice.extraCssFiles.size == 1 &&
    twice.extraJsFiles.size == 1 &&
    twice.extraJs.size == sampleShared.extraJs.size &&
    cssFileText twice == cssFileText sampleShared &&
    jsFileText twice == jsFileText sampleShared

/-! ## The real bundle -/

-- Applied to the site-wide bundle every page carries, the whole design system ends
-- up in the one stylesheet: tokens, build metadata, palette, rail, docs chrome, the
-- node/declaration page frame and the print rules all present, and nothing left inline.
-- The page-frame rules are here rather than in each page's own `<style>` — that is the
-- move, and on a site of tens of thousands of declaration pages it is most of what the
-- frame used to cost.
/-- info: true -/
#guard_msgs in
#eval
  let shared := shareBlueprintChrome blueprintHtmlAssets
  let css := cssFileText shared
  shared.extraCss.isEmpty &&
    has css "--bp-color-surface" &&
    has css ".bp_build_metadata" &&
    has css ".bp_command_palette" &&
    has css "#bp-metadata-rail" &&
    has css ".bp_node_breadcrumb" &&
    has css ".bp_decl_page_fq" &&
    has css ".bp_caveats" &&
    has css "@media print"

end Verso.VersoBlueprintTests.BlueprintSharedChrome
