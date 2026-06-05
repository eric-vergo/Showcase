/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Init.Data.Random
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

private def blueprintNode (label key : String) : Informal.Slides.BlueprintSlideNode where
  label := label
  facet := "statement"
  key := key
  title? := none
  compact := false
  siteBase? := some "blueprint"

private def dummySlidesCss (filename body : String) : VersoSlides.CssFile where
  filename
  contents := ⟨body⟩

private partial def freshSlidesSmokeRoot : IO System.FilePath := do
  let suffix ← IO.rand 0 1000000000000
  let root :=
    System.FilePath.mk ".lake" / "build" / "tmp" /
      "verso-blueprint-slides-smoke-test" / toString suffix
  if ← root.pathExists then
    freshSlidesSmokeRoot
  else
    pure root

/-- info: true -/
#guard_msgs in
#eval
  let js := Informal.Slides.blueprintSlidesJs
  hasSubstr js "function bindUsedByPanel(panel)" &&
    hasSubstr js "function hydrate(root)" &&
    hasSubstr js "function prepareBlueprintLinks(root, baseUrl)" &&
    !hasSubstr js "function openBlueprintHref(href)" &&
    !hasSubstr js "function renderDocstrings(root)" &&
    !hasSubstr js "function ensureLeanHover(target)" &&
    !hasSubstr js "function scheduleSlidePreviewCleanup()" &&
    !hasSubstr js "function bindSlideUsedByPanels" &&
    !hasSubstr js "async function renderEntry(entry, node, key)" &&
    !hasSubstr js "function renderGroupChip(entry)" &&
    !hasSubstr js "function renderUsesChip(entries)" &&
    !hasSubstr js "function renderCodeStatusChip(entry, count)"

/-- info: true -/
#guard_msgs in
#eval
  let node := blueprintNode "def:code.preview" "def:code.preview--statement"
  Informal.Slides.BlueprintSlideNode.fromAttrs? node.toAttrs == some node

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
    try
      let _ ← Informal.Slides.slidesMainWithBlueprintPreviews
        { outputDir := ".lake/build/tmp/verso-blueprint-slides-config-collision",
          extraCss := #[dummySlidesCss "dup.css" "one", dummySlidesCss "dup.css" "two"] }
        (previewManifest? := none)
        staticBlueprintNodeSlideFixture.toPart
        (quiet := true)
      pure false
    catch ex =>
      let msg := toString ex
      pure <|
        hasSubstr msg "Filename collision in config" &&
          hasSubstr msg "dup.css" &&
          hasSubstr msg "extraCss" &&
          hasSubstr msg "text"

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
    let ctx := Informal.Slides.RenderContext.ofManifest? (some file)
    let renderedHtml := Informal.Slides.renderBlueprintSlideNode ctx
      (blueprintNode "def:code.preview" key)
    let rendered := renderedHtml.asString
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
    let some entry := file.previews.find? (fun entry => entry.key == key)
      | return false
    let groupManifestOk :=
      match entry.group with
      | some group =>
        group.declared &&
          group.entries.size == 2 &&
          !group.entries.any (fun related => related.label == entry.label)
      | none => false
    let usedByManifestOk :=
      match entry.usedBy[0]? with
      | some related =>
        entry.usedBy.size == 1 &&
          related.axes.contains Informal.PreviewManifest.RelationAxis.statement
      | none => false
    let ctx := Informal.Slides.RenderContext.ofManifest? (some file)
    let renderedHtml := Informal.Slides.renderBlueprintSlideNode ctx
      (blueprintNode "def:group.target" key)
    let rendered := renderedHtml.asString
    pure <|
      groupManifestOk &&
        usedByManifestOk &&
        hasSubstr rendered "bp_extra_slot_group" &&
        hasSubstr rendered "bp_extra_slot_used_by" &&
        hasSubstr rendered "data-bp-slide-panel=\"group\"" &&
        hasSubstr rendered "data-bp-slide-panel=\"used-by\"" &&
        hasSubstr rendered "Group: Preview group title. (2)" &&
        hasSubstr rendered "bp_used_by_item_active" &&
        !hasSubstr rendered "Loading Blueprint node"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls missingGroupPreviewDoc
    let file ← Informal.PreviewManifest.buildManifestFile manualImpls (fun _ => pure ()) st
    let key := Informal.PreviewCache.key (Lean.Name.mkSimple "def:group.missing.target") .statement
    let some entry := file.previews.find? (fun entry => entry.key == key)
      | return false
    let groupManifestOk :=
      match entry.group with
      | some group => !group.declared && group.entries.size == 1
      | none => false
    let ctx := Informal.Slides.RenderContext.ofManifest? (some file)
    let renderedHtml := Informal.Slides.renderBlueprintSlideNode ctx
      (blueprintNode "def:group.missing.target" key)
    let rendered := renderedHtml.asString
    pure <|
      groupManifestOk &&
        hasSubstr rendered "bp_extra_slot_group" &&
        hasSubstr rendered "bp_used_by_chip_warn" &&
        hasSubstr rendered "data-bp-slide-panel=\"group\"" &&
        hasSubstr rendered "Undeclared group"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls leanCodeLinkPreviewDoc
    let file ← Informal.PreviewManifest.buildManifestFile manualImpls (fun _ => pure ()) st
    let root ← freshSlidesSmokeRoot
    let outDir := root / "slides"
    let manifestPath := root / Informal.PreviewManifest.manifestFilename
    if !(← root.pathExists) then
      IO.FS.createDirAll root
    IO.FS.writeFile manifestPath (Lean.toJson file).compress
    let rc ← Informal.Slides.slidesMainWithBlueprintPreviews
      { outputDir := outDir }
      (previewManifest? := some manifestPath)
      staticBlueprintNodeSlideFixture.toPart
      (quiet := true)
    if rc != 0 then
      return false
    let indexPath := outDir / "index.html"
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
