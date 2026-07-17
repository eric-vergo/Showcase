/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.PreviewManifest
import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintMainWrapper

open Verso.Genre.Manual
open Verso.VersoBlueprintTests.Blueprint.Support

/-- info: true -/
#guard_msgs in
#eval
  let cfg : RenderConfig := {}
  let cfg := Informal.PreviewManifest.withBlueprintAssets cfg
  let jsFiles := cfg.toHtmlConfig.toHtmlAssets.extraJsFiles.toArray.map (·.filename)
  let cssFiles := cfg.toHtmlConfig.toHtmlAssets.extraCssFiles.toArray.map (·.filename)
  jsFiles.contains "popper.min.js" &&
    jsFiles.contains "tippy-bundle.umd.min.js" &&
    cssFiles.contains "tippy-border.css"

/-- info: true -/
#guard_msgs in
#eval
  let customJs : JS := "console.log('custom');"
  let cfg : RenderConfig := {
    toHtmlConfig := {
      extraJs := [customJs]
    }
  }
  let cfg := Informal.PreviewManifest.withBlueprintAssets cfg
  cfg.toHtmlConfig.extraJs.toArray.any (·.js.contains "custom")

/-- info: true -/
#guard_msgs in
#eval
  let cfg : RenderConfig := {}
  let cfg := Informal.PreviewManifest.withBlueprintAssets cfg
  cfg.toHtmlConfig.extraHead.any fun html =>
    let source := html.asString
    hasSubstr source "type=\"module\"" &&
      hasSubstr source "-verso-data/blueprint-page-runtime.mjs"

/-- info: true -/
#guard_msgs in
#eval
  let cfg : RenderConfig := {}
  let cfg := Informal.PreviewManifest.withBlueprintAssets cfg
  let cfg := Informal.PreviewManifest.withBlueprintAssets cfg
  (cfg.toHtmlConfig.extraHead.filter fun html =>
    hasSubstr html.asString "-verso-data/blueprint-page-runtime.mjs").size == 1

/-- info: true -/
#guard_msgs in
#eval
  let cfg : RenderConfig := {}
  let cfg := Informal.PreviewManifest.withBlueprintAssets cfg
  cfg.toHtmlConfig.toHtmlAssets.extraCss.toArray.any fun css =>
    hasSubstr css.css ".bp_build_metadata"

/-- info: true -/
#guard_msgs in
#eval
  let metadata : Informal.PreviewManifest.BuildMetadata := {
    compiledAt := "2026-05-05T00:00:00Z"
    commit := "abc123"
    subject := "escape <tag> & message"
    projectRepositoryUrl := some "https://github.com/example/project"
    projectCommitUrl := some "https://github.com/example/project/commit/abc123full"
    leanToolchain := "leanprover/lean4:v4.30.0"
    blueprintVersion := "def456"
    blueprintRepositoryUrl := some "https://github.com/leanprover/verso-blueprint"
    blueprintCommitUrl := some "https://github.com/leanprover/verso-blueprint/commit/def456full"
    mathlibVersion := some "v4.30.0@789abc"
    mathlibRepositoryUrl := some "https://github.com/leanprover-community/mathlib4"
    mathlibCommitUrl := some "https://github.com/leanprover-community/mathlib4/commit/789abcfull"
    upstreamBlueprint := some {
      commit := "up987"
      subject := "upstream <msg> & more"
      repositoryUrl := some "https://github.com/example/upstream"
      commitUrl := some "https://github.com/example/upstream/commit/up987full"
    }
  }
  let input := "<html><body><div class=\"titlepage\"><h1>Example</h1><div class=\"authors\"></div></div></body></html>"
  let metadataHtml := Informal.PreviewManifest.buildMetadataHtmlString metadata
  match Informal.PreviewManifest.insertBuildMetadataHtml? input metadataHtml with
  | some out =>
      hasSubstr out "class=\"bp_build_metadata\"" &&
        hasSubstr out "2026-05-05T00:00:00Z" &&
        hasSubstr out "abc123" &&
        hasSubstr out "https://github.com/example/project" &&
        hasSubstr out "https://github.com/example/project/commit/abc123full" &&
        hasSubstr out "escape &lt;tag&gt; &amp; message" &&
        hasSubstr out "leanprover/lean4:v4.30.0" &&
        hasSubstr out "def456" &&
        hasSubstr out "https://github.com/leanprover/verso-blueprint/commit/def456full" &&
        hasSubstr out "up987" &&
        hasSubstr out "https://github.com/example/upstream" &&
        hasSubstr out "https://github.com/example/upstream/commit/up987full" &&
        hasSubstr out "upstream &lt;msg&gt; &amp; more" &&
        hasSubstr out "v4.30.0@789abc" &&
        hasSubstr out "https://github.com/leanprover-community/mathlib4/commit/789abcfull" &&
        appearsBefore out "<h1>Example</h1>" "class=\"bp_build_metadata\"" &&
        appearsBefore out "class=\"bp_build_metadata\"" "class=\"authors\""
  | none => false

end Verso.VersoBlueprintTests.BlueprintMainWrapper
