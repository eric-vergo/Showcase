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

open Verso
open Verso.Genre.Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

def graftManualLeftValue : Nat := 2

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

#docs (Slides) sideBySideBlueprintNodeSlideFixture "Side-by-Side Blueprint Node Slide" :=
:::::::
# Side-by-Side Blueprint Nodes

:::blueprint_side_by_side +boxed
{blueprint_node "def:graft.slide.left" -header (siteBase := "blueprint")}

{blueprint_node "def:graft.slide.right" -header (siteBase := "blueprint")}
:::
:::::::

#docs (Genre.Manual) slideMetadataPanelDoc "Slide Metadata Panel" :=
:::::::
:::definition "def:slide.meta.panel" (tags := "slides, renderer") (effort := "small") (priority := "high")
Manifest-backed slide rendering should use the standard Blueprint block renderer.
:::
:::::::

#docs (Genre.Manual) manualGraftDoc "Manual Blueprint Graft" :=
:::::::
:::definition "def:graft.manual.source"
Manual graft body.
:::

{blueprint_node "def:graft.manual.source" -header +compact}
:::::::

#docs (Genre.Manual) manualSideBySideGraftDoc "Manual Side-by-Side Blueprint Graft" :=
:::::::
:::definition "def:graft.manual.left" (tags := "graft, source") (effort := "small") (lean := "graftManualLeftValue")
Manual left graft body with inline math $`x + y = y + x` and an attached Lean preview.
:::

:::theorem "thm:graft.manual.sum" (uses := "def:graft.manual.left") (priority := "high")
The grafted theorem states $`(a + b) + c = a + (b + c)`.
:::

:::proof "thm:graft.manual.sum"
The proof graft records the same goal and keeps the proof facet selectable.
:::

:::definition "def:graft.manual.right" (uses := "thm:graft.manual.sum")
Manual right graft body references {uses "def:graft.manual.left"}[] and includes display math:
$$`\sum_{i=0}^{n} i = n`.
:::

:::blueprint_side_by_side +boxed
{blueprint_node "def:graft.manual.left" (displayLabel := "Featured definition")}

{blueprint_node "thm:graft.manual.sum" (displayLabel := "Theorem view") -header +compact}

{blueprint_node "thm:graft.manual.sum" (facet := "proof") (displayLabel := "Proof view") -header +compact}

{blueprint_node "def:graft.manual.right" (displayLabel := "Uses view") +compact}
:::
:::::::

#docs (Genre.Manual) slideGraftSourceDoc "Slide Blueprint Graft Sources" :=
:::::::
:::definition "def:graft.slide.left"
Slide left graft body.
:::

:::definition "def:graft.slide.right"
Slide right graft body.
:::
:::::::

private def blueprintNode (label key : String) : Informal.Graft.BlueprintNode where
  label := label
  facet := "statement"
  key := key
  displayLabel? := none
  compact := false
  siteBase? := some "blueprint"

private def manifestCodeEntry (key : String) : Informal.PreviewManifest.Entry where
  key := key
  targetKind := .leanDecl
  label := Lean.Name.mkSimple key
  facet := .statement
  title := key

private def htmlCacheEntry (key html : String) : Informal.PreviewManifest.HtmlCache.Entry where
  key := key
  html := html

private def manifestBlockEntry (key : String) (codeKeys : Array String) :
    Informal.PreviewManifest.Entry where
  key := key
  targetKind := .block
  label := Lean.Name.mkSimple key
  facet := .statement
  title := key
  leanCodePreviewKeys := codeKeys

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
  hasSubstr js "function bindRelationPanel(panel)" &&
    hasSubstr js "function hydrate(root)" &&
    hasSubstr js "function prepareBlueprintLinks(root, baseUrl)" &&
    hasSubstr js "data-bp-slide-href" &&
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
  Informal.Graft.BlueprintNode.fromAttrs? node.toAttrs == some node

/-- info: true -/
#guard_msgs in
#eval
  let node := { blueprintNode "def:code.preview" "def:code.preview--statement" with
    displayLabel? := some "Custom slide label" }
  let attrs := node.toAttrs
  Informal.Graft.BlueprintNode.fromAttrs? attrs == some node &&
    attrs.contains ("data-bp-display-label", "Custom slide label") &&
    !(attrs.any (fun attr => attr.1 == "data-bp-title"))

/-- info: true -/
#guard_msgs in
#eval
  let node := { blueprintNode "def:code.preview" "def:code.preview--statement" with
    showHeader := false }
  let attrs := node.toAttrs
  Informal.Graft.BlueprintNode.fromAttrs? attrs == some node &&
    attrs.contains ("data-bp-show-header", "false")

/-- info: true -/
#guard_msgs in
#eval
  let blockEntry := manifestBlockEntry "block" #["a", "b", "c"]
  let file : Informal.PreviewManifest.File := {
    previews := #[
      blockEntry,
      manifestCodeEntry "a",
      manifestCodeEntry "b",
      manifestCodeEntry "c"
    ]
  }
  let cache : Informal.PreviewManifest.HtmlCache.File := {
    entries := #[
      htmlCacheEntry "a" "<pre>same</pre>",
      htmlCacheEntry "b" "<pre>same</pre>",
      htmlCacheEntry "c" "<pre>different</pre>"
    ]
  }
  let index := file.index
  index.codeEntryCount blockEntry == 3 &&
    (index.codeEntries blockEntry).map (·.key) == #["a", "b", "c"] &&
    cache.codeHtmlBodies blockEntry == #["<pre>same</pre>", "<pre>different</pre>"]

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
    let files ← Informal.PreviewManifest.buildPreviewDataFiles manualImpls (fun _ => pure ()) st
    let file := files.manifest
    let cache := files.htmlCache
    let blockKey := Informal.PreviewCache.key (Lean.Name.mkSimple "def:code.preview") .statement
    let codeKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey `Nat.add
    let some blockEntry := file.previews.find? (fun entry => entry.key == blockKey)
      | return false
    let some blockHtml := cache.findHtml? blockKey
      | return false
    let some codeHtml := cache.findHtml? codeKey
      | return false
    pure <|
        blockEntry.leanCodePreviewKeys.contains codeKey &&
        blockEntry.codeData.isSome &&
        hasSubstr blockHtml "Statement with an associated Lean declaration link" &&
        hasSubstr codeHtml "bp_external_decl_rendered" &&
        blockEntry.displayCaption == some "Definition" &&
        blockEntry.displayLabel.any (fun label => !label.trimAscii.isEmpty) &&
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
    let files ← Informal.PreviewManifest.buildPreviewDataFiles manualImpls (fun _ => pure ()) st
    let cache := files.htmlCache
    let codeKey := Informal.TraversalIndex.LeanCodePreviews.lookupKey
      `Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.usedByPreviewTarget
    let some codeHtml := cache.findHtml? codeKey
      | return false
    pure <|
      hasSubstr codeHtml "class=\"hl lean block\"" &&
        hasSubstr codeHtml "examples" &&
        hasSubstr codeHtml "data-verso-hover=" &&
        !files.htmlCache.hoverDocs.isEmpty &&
        files.htmlCache.hoverDocs.all (fun doc => doc.id >= Informal.PreviewManifest.HtmlCache.hoverIdStart) &&
        !hasSubstr codeHtml "<pre>def "

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (html, _st) ← renderManualDocHtmlStringAndState manualImpls manualGraftDoc
    pure <|
      hasSubstr html "bp_graft_node" &&
        countSubstr html "Manual graft body." == 2 &&
        countSubstr html "class=\"bp_heading " == 1 &&
        !hasSubstr html "Blueprint node not found"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (html, _st) ← renderManualDocHtmlStringAndState manualImpls manualSideBySideGraftDoc
    pure <|
      hasSubstr html "bp_graft_side_by_side" &&
        hasSubstr html "bp_graft_side_by_side_boxed" &&
        countSubstr html "data-bp-blueprint-node=\"true\"" == 4 &&
        countSubstr html "Manual left graft body with inline math" == 2 &&
        countSubstr html "The grafted theorem states" == 2 &&
        countSubstr html "The proof graft records" == 2 &&
        countSubstr html "Manual right graft body references" == 2 &&
        hasSubstr html "Featured definition" &&
        hasSubstr html "Uses view" &&
        hasSubstr html "graftManualLeftValue" &&
        hasSubstr html "bp_math inline" &&
        hasSubstr html "bp_math display" &&
        hasSubstr html "data-bp-facet=\"proof\"" &&
        hasSubstr html "bp_code_panel_wrapper" &&
        !hasSubstr html "Blueprint node not found"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls usedByPreviewDoc
    let files ← Informal.PreviewManifest.buildPreviewDataFiles manualImpls (fun _ => pure ()) st
    let file := files.manifest
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
    let files ← Informal.PreviewManifest.buildPreviewDataFiles manualImpls (fun _ => pure ()) st
    let key := Informal.PreviewCache.key (Lean.Name.mkSimple "def:code.preview") .statement
    let ctx := Informal.Slides.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)
    let renderedHtml ← Informal.Slides.renderBlueprintSlideNode ctx
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
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls slideMetadataPanelDoc
    let files ← Informal.PreviewManifest.buildPreviewDataFiles manualImpls (fun _ => pure ()) st
    let key := Informal.PreviewCache.key (Lean.Name.mkSimple "def:slide.meta.panel") .statement
    let ctx := Informal.Slides.RenderContext.ofPreviewData? (some files.manifest) (some files.htmlCache)
    let renderedHtml ← Informal.Slides.renderBlueprintSlideNode ctx
      (blueprintNode "def:slide.meta.panel" key)
    let rendered := renderedHtml.asString
    pure <|
      hasSubstr rendered "class=\"bp_metadata_panel\"" &&
        hasSubstr rendered "slides" &&
        hasSubstr rendered "renderer" &&
        hasSubstr rendered "Effort" &&
        hasSubstr rendered "small" &&
        hasSubstr rendered "Priority" &&
        hasSubstr rendered "high"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls groupPreviewDoc
    let files ← Informal.PreviewManifest.buildPreviewDataFiles manualImpls (fun _ => pure ()) st
    let file := files.manifest
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
    let ctx := Informal.Slides.RenderContext.ofPreviewData? (some file) (some files.htmlCache)
    let renderedHtml ← Informal.Slides.renderBlueprintSlideNode ctx
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
        hasSubstr rendered "bp_relation_item_active" &&
        !hasSubstr rendered "Loading Blueprint node"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls missingGroupPreviewDoc
    let files ← Informal.PreviewManifest.buildPreviewDataFiles manualImpls (fun _ => pure ()) st
    let file := files.manifest
    let key := Informal.PreviewCache.key (Lean.Name.mkSimple "def:group.missing.target") .statement
    let some entry := file.previews.find? (fun entry => entry.key == key)
      | return false
    let groupManifestOk :=
      match entry.group with
      | some group => !group.declared && group.entries.size == 1
      | none => false
    let ctx := Informal.Slides.RenderContext.ofPreviewData? (some file) (some files.htmlCache)
    let renderedHtml ← Informal.Slides.renderBlueprintSlideNode ctx
      (blueprintNode "def:group.missing.target" key)
    let rendered := renderedHtml.asString
    pure <|
      groupManifestOk &&
        hasSubstr rendered "bp_extra_slot_group" &&
        hasSubstr rendered "bp_relation_chip_warn" &&
        hasSubstr rendered "data-bp-slide-panel=\"group\"" &&
        hasSubstr rendered "Undeclared group"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls leanCodeLinkPreviewDoc
    let files ← Informal.PreviewManifest.buildPreviewDataFiles manualImpls (fun _ => pure ()) st
    let root ← freshSlidesSmokeRoot
    let outDir := root / "slides"
    let manifestPath := root / Informal.PreviewManifest.manifestFilename
    let htmlCachePath := root / Informal.PreviewManifest.htmlCacheFilename
    if !(← root.pathExists) then
      IO.FS.createDirAll root
    IO.FS.writeFile manifestPath (Lean.toJson files.manifest).compress
    IO.FS.writeFile htmlCachePath (Lean.toJson files.htmlCache).compress
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
    let copiedManifest := Informal.Slides.blueprintSlidesManifestPath outDir
    let copiedHtmlCache := Informal.Slides.blueprintSlidesHtmlCachePath outDir
    let normalizedKey := Informal.PreviewCache.key (Lean.Name.mkSimple "def:code.preview") .statement
    pure <|
      (← copiedManifest.pathExists) &&
        (← copiedHtmlCache.pathExists) &&
        hasSubstr index "data-bp-rendered=\"static\"" &&
        hasSubstr index "bp_slide_node_blueprint" &&
        hasSubstr index "bp_extra_slot_code" &&
        hasSubstr index s!"data-bp-preview-key=\"{normalizedKey}\"" &&
        hasSubstr index "data-bp-site-base=\"blueprint\"" &&
        hasSubstr index "href=\"#--informal-preview" &&
        !hasSubstr index "Loading Blueprint node"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (_out, st) ← renderManualDocHtmlStringAndState manualImpls slideGraftSourceDoc
    let files ← Informal.PreviewManifest.buildPreviewDataFiles manualImpls (fun _ => pure ()) st
    let root ← freshSlidesSmokeRoot
    let outDir := root / "slides"
    let manifestPath := root / Informal.PreviewManifest.manifestFilename
    let htmlCachePath := root / Informal.PreviewManifest.htmlCacheFilename
    if !(← root.pathExists) then
      IO.FS.createDirAll root
    IO.FS.writeFile manifestPath (Lean.toJson files.manifest).compress
    IO.FS.writeFile htmlCachePath (Lean.toJson files.htmlCache).compress
    let rc ← Informal.Slides.slidesMainWithBlueprintPreviews
      { outputDir := outDir }
      (previewManifest? := some manifestPath)
      sideBySideBlueprintNodeSlideFixture.toPart
      (quiet := true)
    if rc != 0 then
      return false
    let indexPath := outDir / "index.html"
    if !(← indexPath.pathExists) then
      return false
    let index ← IO.FS.readFile indexPath
    pure <|
      hasSubstr index "bp_graft_side_by_side" &&
        countSubstr index "data-bp-rendered=\"static\"" == 2 &&
        hasSubstr index "Slide left graft body." &&
        hasSubstr index "Slide right graft body." &&
        !hasSubstr index "Blueprint node not found" &&
        !hasSubstr index "Loading Blueprint node"

end Verso.VersoBlueprintTests.BlueprintSlides
