/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoBlueprint.Slides

open VersoSlides

namespace Verso.VersoBlueprintTests.BlueprintSlidesRuntime

#docs (Slides) slidesRuntimeFixture "Blueprint Slides Runtime" :=
:::::::
# Blueprint Slides Runtime

{blueprint_node "collatz_step" (siteBase := "blueprint")}
:::::::

private def usage : IO UInt32 := do
  IO.eprintln "usage: lake env lean --run tests/browser/BlueprintSlidesRuntime.lean <output-dir> <blueprint-manifest> <blueprint-html-cache>"
  pure 1

def run (args : List String) : IO UInt32 := do
  match args with
  | [outputDirArg, manifestArg, htmlCacheArg] =>
    let outputDir := System.FilePath.mk outputDirArg
    let manifestPath := System.FilePath.mk manifestArg
    let htmlCachePath := System.FilePath.mk htmlCacheArg
    IO.FS.createDirAll outputDir
    Informal.Slides.slidesMainWithBlueprintPreviews
      { outputDir := outputDir }
      (previewManifest? := some manifestPath)
      slidesRuntimeFixture.toPart
      (previewHtmlCache? := some htmlCachePath)
      (quiet := true)
  | _ => usage

end Verso.VersoBlueprintTests.BlueprintSlidesRuntime

def main (args : List String) : IO UInt32 :=
  Verso.VersoBlueprintTests.BlueprintSlidesRuntime.run args
