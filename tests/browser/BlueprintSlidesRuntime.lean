/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Slides

open VersoSlides

namespace Verso.VersoBlueprintTests.BlueprintSlidesRuntime

#docs (Slides) slidesRuntimeFixture "Blueprint Slides Runtime" :=
:::::::
# Blueprint Slides Runtime

{blueprint_node "slides_relative" (siteBase := "blueprint")}
:::::::

private def label (s : String) : Lean.Name :=
  Lean.Name.mkSimple s

private def statementKey (s : String) : String :=
  Informal.PreviewCache.key (label s) .statement

private def related (labelText title href : String) : Informal.PreviewManifest.RelatedEntry where
  label := label labelText
  title := title
  href := some href
  previewKey := statementKey labelText

private def entry (labelText title labelDisplay href bodyHtml : String)
    (groupEntries : Array Informal.PreviewManifest.RelatedEntry := #[]) :
    Informal.PreviewManifest.Entry where
  key := statementKey labelText
  targetKind := .block
  label := label labelText
  facet := .statement
  kind := some .definition
  title := title
  displayCaption := some "Definition"
  displayLabel := some labelDisplay
  href := some href
  group :=
    if groupEntries.isEmpty then
      none
    else
      some {
        label := label "slides_group"
        title := "Runtime slide group"
        declared := true
        entries := groupEntries
      }
  html := bodyHtml

private def slideRuntimeManifest : Informal.PreviewManifest.File where
  previews := #[
    entry
      "slides_relative"
      "Definition 1"
      "1"
      "node.html"
      "<p>Generated slide body with <a href=\"body.html\">body link</a>.</p>"
      #[related "slides_peer" "Peer Definition" "peer.html"],
    entry
      "slides_peer"
      "Peer Definition"
      "2"
      "peer.html"
      "<p>Peer body with <a href=\"peer-body.html\">peer body link</a>.</p>"
  ]

private def usage : IO UInt32 := do
  IO.eprintln "usage: lake env lean --run tests/browser/BlueprintSlidesRuntime.lean <output-dir>"
  pure 1

def run (args : List String) : IO UInt32 := do
  match args with
  | [outputDirArg] =>
    let outputDir := System.FilePath.mk outputDirArg
    IO.FS.createDirAll outputDir
    let manifestPath := outputDir / Informal.PreviewManifest.manifestFilename
    IO.FS.writeFile manifestPath (Lean.toJson slideRuntimeManifest).compress
    Informal.Slides.slidesMainWithBlueprintPreviews
      { outputDir := outputDir }
      (previewManifest? := some manifestPath)
      slidesRuntimeFixture.toPart
      (quiet := true)
  | _ => usage

end Verso.VersoBlueprintTests.BlueprintSlidesRuntime

def main (args : List String) : IO UInt32 :=
  Verso.VersoBlueprintTests.BlueprintSlidesRuntime.run args
