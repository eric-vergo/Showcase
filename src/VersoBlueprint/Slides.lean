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

private def slideNodeCss : String := include_str "Slides/blueprint-slides.css"

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
private def slideNodeHydrationJs : String := include_str "Slides/blueprint-slides.js"

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

/--
Local compatibility layer pending the upstream Verso Slides `Block.ofHtml`
constructor tracked in `doc/UPSTREAM_BACKLOG.md`: keep this close to upstream
`slidesMain` so the copied asset/write loop can disappear.
-/
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
