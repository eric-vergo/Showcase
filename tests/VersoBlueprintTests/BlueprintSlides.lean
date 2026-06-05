/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Slides
import Verso.Doc.Concrete
import VersoBlueprintTests.Blueprint.Support
import VersoBlueprintTests.BlueprintPreviewWiring.Shared

open VersoSlides

namespace Verso.VersoBlueprintTests.BlueprintSlides

open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

#docs (Slides) blueprintNodeSlideFixture "Blueprint Node Slide" :=
:::::::
# Example Blueprint Node

{blueprint_node "addition_assoc" (siteBase := "blueprint")}
:::::::

#docs (Slides) staticBlueprintNodeSlideFixture "Static Blueprint Node Slide" :=
:::::::
# Static Blueprint Node

{blueprint_node "def:code.preview" (siteBase := "blueprint")}
:::::::

/-- info: true -/
#guard_msgs in
#eval
  let js := Informal.Slides.blueprintSlidesJs
  hasSubstr js "function bindUsedByPanel(panel)" &&
    hasSubstr js "function hydrate(root)" &&
    hasSubstr js "function prepareBlueprintLinks(root, baseUrl)" &&
    !hasSubstr js "function bindSlideUsedByPanels" &&
    !hasSubstr js "async function renderEntry(entry, node, key)" &&
    !hasSubstr js "function renderGroupChip(entry)" &&
    !hasSubstr js "function renderUsesChip(entries)" &&
    !hasSubstr js "function renderCodeStatusChip(entry, count)"

/-- info: true -/
#guard_msgs in
#eval
  let cfg := Informal.Slides.withBlueprintSlidesAssets {}
  let cfgAgain := Informal.Slides.withBlueprintSlidesAssets cfg
  cfg.extraCss.any (·.filename == Informal.Slides.blueprintSlidesCssFilename) &&
    cfg.extraJs.contains Informal.Slides.blueprintSlidesJsFilename &&
    cfgAgain.extraCss.size == cfg.extraCss.size &&
    cfgAgain.extraJs.size == cfg.extraJs.size

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls leanCodeLinkPreviewDoc
    let file ← Informal.PreviewManifest.buildManifestFile manualImpls (fun _ => pure ()) st
    let blockKey := Informal.PreviewCache.key (Lean.Name.mkSimple "def:code.preview") .statement
    let codeKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey `Nat.add
    let some blockEntry := file.previews.find? (fun entry => entry.key == blockKey)
      | return false
    pure <|
      blockEntry.leanCodePreviewKeys.contains codeKey &&
        file.previews.any (fun entry =>
          entry.key == codeKey &&
            match entry.targetKind with
            | .leanDecl => true
            | _ => false)

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls usedByPreviewDoc
    let file ← Informal.PreviewManifest.buildManifestFile manualImpls (fun _ => pure ()) st
    let blockKey := Informal.PreviewCache.key (Lean.Name.mkSimple "def:used.target") .statement
    let codeKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      `Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.usedByPreviewTarget
    let some blockEntry := file.previews.find? (fun entry => entry.key == blockKey)
      | return false
    pure <| blockEntry.leanCodePreviewKeys.contains codeKey

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls leanCodeLinkPreviewDoc
    let file ← Informal.PreviewManifest.buildManifestFile manualImpls (fun _ => pure ()) st
    let key := Informal.PreviewCache.key (Lean.Name.mkSimple "def:code.preview") .statement
    let placeholder :=
      "<div data-bp-blueprint-node=\"true\" class=\"bp_slide_node\" " ++
      "data-bp-label=\"def:code.preview\" data-bp-facet=\"statement\" " ++
      s!"data-bp-preview-key=\"{key}\" data-bp-compact=\"false\" " ++
      "data-bp-site-base=\"blueprint\"><p>Loading Blueprint node def:code.preview...</p></div>"
    let rendered := Informal.Slides.renderBlueprintSlideNodesInHtml (some file) placeholder
    pure <|
      hasSubstr rendered "data-bp-rendered=\"static\"" &&
        hasSubstr rendered "bp_slide_node_blueprint" &&
        hasSubstr rendered "bp_extra_slot_code" &&
        hasSubstr rendered "bp_code_panel_wrapper" &&
        hasSubstr rendered "data-bp-site-base=\"blueprint\"" &&
        hasSubstr rendered "href=\"#--informal-preview" &&
        !hasSubstr rendered "Loading Blueprint node"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls groupPreviewDoc
    let file ← Informal.PreviewManifest.buildManifestFile manualImpls (fun _ => pure ()) st
    let key := Informal.PreviewCache.key (Lean.Name.mkSimple "def:group.target") .statement
    let placeholder :=
      "<div data-bp-blueprint-node=\"true\" class=\"bp_slide_node\" " ++
      "data-bp-label=\"def:group.target\" data-bp-facet=\"statement\" " ++
      s!"data-bp-preview-key=\"{key}\" data-bp-compact=\"false\" " ++
      "data-bp-site-base=\"blueprint\"><p>Loading Blueprint node def:group.target...</p></div>"
    let rendered := Informal.Slides.renderBlueprintSlideNodesInHtml (some file) placeholder
    pure <|
      hasSubstr rendered "bp_extra_slot_group" &&
        hasSubstr rendered "bp_extra_slot_used_by" &&
        hasSubstr rendered "data-bp-slide-panel=\"group\"" &&
        hasSubstr rendered "data-bp-slide-panel=\"used-by\"" &&
        hasSubstr rendered "bp_used_by_item_active" &&
        !hasSubstr rendered "Loading Blueprint node"

/--
info: Slides written to /tmp/verso-blueprint-slides-smoke-test/slides/index.html
---
info: true
-/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls leanCodeLinkPreviewDoc
    let file ← Informal.PreviewManifest.buildManifestFile manualImpls (fun _ => pure ()) st
    let root := System.FilePath.mk "/tmp/verso-blueprint-slides-smoke-test"
    let outDir := root / "slides"
    let manifestPath := root / Informal.PreviewManifest.manifestFilename
    if !(← root.pathExists) then
      IO.FS.createDirAll root
    let indexPath := outDir / "index.html"
    if ← indexPath.pathExists then
      IO.FS.removeFile indexPath
    if ← manifestPath.pathExists then
      IO.FS.removeFile manifestPath
    IO.FS.writeFile manifestPath (Lean.toJson file).compress
    let rc ← Informal.Slides.slidesMainWithBlueprintPreviews
      { outputDir := outDir }
      (previewManifest? := some manifestPath)
      staticBlueprintNodeSlideFixture.toPart
    if rc != 0 then
      return false
    if !(← indexPath.pathExists) then
      return false
    let index ← IO.FS.readFile indexPath
    let copiedManifest := Informal.Slides.blueprintSlidesPreviewManifestPath outDir
    let normalizedKey := Informal.PreviewCache.key (Lean.Name.mkSimple "def:code.preview") .statement
    pure <|
      (← copiedManifest.pathExists) &&
        hasSubstr index "data-bp-rendered=\"static\"" &&
        hasSubstr index "bp_slide_node_blueprint" &&
        hasSubstr index "bp_extra_slot_code" &&
        hasSubstr index s!"data-bp-preview-key=\"{normalizedKey}\"" &&
        hasSubstr index "data-bp-site-base=\"blueprint\"" &&
        hasSubstr index "href=\"#--informal-preview" &&
        !hasSubstr index "Loading Blueprint node"

end Verso.VersoBlueprintTests.BlueprintSlides
