/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.Elab.Command
import Std.Data.HashMap
import Std.Data.HashSet
import VersoManual
import VersoManual.HighlightedCode
import VersoBlueprint.Cite
import VersoBlueprint.Informal.Block
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Informal.Group
import VersoBlueprint.Informal.LeanCodePreview
import VersoBlueprint.PreviewCache
import VersoBlueprint.PreviewRender
import VersoBlueprint.Git
import VersoBlueprint.Process
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

namespace Informal.PreviewManifest

open Lean Elab Command Term Meta
open Verso Doc
open Verso.Genre Manual

private def buildMetadataCss : String := r##"
.bp_build_metadata {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 0.3rem 0.75rem;
  margin: 0.45rem 0 1.1rem;
  color: var(--bp-color-text-muted, #475569);
  font-size: 0.82rem;
  line-height: 1.4;
}

.bp_build_metadata_item {
  display: inline-flex;
  align-items: baseline;
  gap: 0.28rem;
  min-width: 0;
  flex-wrap: wrap;
}

.bp_build_metadata_label {
  color: var(--bp-color-text-subtle, #475569);
  font-weight: 600;
}

.bp_build_metadata_link {
  color: inherit;
  text-decoration: underline;
  text-decoration-style: dotted;
  text-underline-offset: 0.12em;
}

.bp_build_metadata_link:hover {
  text-decoration-style: solid;
}

.bp_build_metadata_commit {
  padding: 0.02rem 0.22rem;
  border: 1px solid var(--bp-color-border-soft, #e2e8f0);
  border-radius: 0.25rem;
  background: var(--bp-color-surface-muted, #f8fafc);
  color: var(--bp-color-text-strong, #0f172a);
  font-size: 0.86em;
}

.bp_build_metadata_commit_link {
  text-decoration: none;
}

.bp_build_metadata_commit_link:hover .bp_build_metadata_commit {
  border-color: var(--bp-color-link, #2563eb);
}

.bp_build_metadata_subject {
  overflow-wrap: anywhere;
}

@media (max-width: 640px) {
  .bp_build_metadata {
    justify-content: flex-start;
  }
}
"##

def buildMetadataHtmlAssets : HtmlAssets :=
  { extraCss := [buildMetadataCss] }

def blueprintHtmlAssets : HtmlAssets :=
  Verso.Genre.Manual.highlightAssets.combine buildMetadataHtmlAssets

def withBuildMetadataAssets (config : RenderConfig := {}) : RenderConfig :=
  let htmlConfig := config.toHtmlConfig
  let htmlAssets := htmlConfig.toHtmlAssets.combine buildMetadataHtmlAssets
  { config with
    toHtmlConfig := { htmlConfig with toHtmlAssets := htmlAssets }
  }

def withBlueprintAssets (config : RenderConfig := {}) : RenderConfig :=
  let htmlConfig := config.toHtmlConfig
  let htmlAssets := htmlConfig.toHtmlAssets.combine blueprintHtmlAssets
  { config with
    toHtmlConfig := { htmlConfig with toHtmlAssets := htmlAssets }
  }

structure GitCommitMetadata where
  commit : String
  subject : String
  repositoryUrl : Option String := none
  commitUrl : Option String := none
deriving Inhabited, Repr

structure PackageMetadata where
  version : String
  repositoryUrl : Option String := none
  commitUrl : Option String := none
deriving Inhabited, Repr

structure BuildMetadata where
  compiledAt : String
  commit : String
  subject : String
  projectRepositoryUrl : Option String := none
  projectCommitUrl : Option String := none
  leanToolchain : String
  blueprintVersion : String
  blueprintRepositoryUrl : Option String := none
  blueprintCommitUrl : Option String := none
  mathlibVersion : Option String := none
  mathlibRepositoryUrl : Option String := none
  mathlibCommitUrl : Option String := none
  upstreamBlueprint : Option GitCommitMetadata := none
deriving Inhabited, Repr

private def unknownMetadataValue : String := "unknown"

private def outputDirNameForMode : Mode → String
  | .single => "html-single"
  | .multi => "html-multi"

private def outDirForMode (cfg : Verso.Genre.Manual.Config) (mode : Mode) : System.FilePath :=
  cfg.destination / outputDirNameForMode mode

private def readTrimmedFile? (path : System.FilePath) : IO (Option String) := do
  try
    unless ← path.pathExists do
      return none
    let text := (← IO.FS.readFile path).trimAscii.toString
    if text.isEmpty then
      pure none
    else
      pure (some text)
  catch _ =>
    pure none

private def gitCommitMetadataAt? (dir : System.FilePath) : IO (Option GitCommitMetadata) := do
  let some commit ← Git.shortCommitAt? dir
    | return none
  let subject ← Git.subjectAt? dir
  let repositoryUrl ← Git.repositoryUrlAt? dir
  let commitUrl := Git.commitUrl? repositoryUrl (← Git.fullCommitAt? dir)
  pure <| some {
    commit
    subject := subject.getD unknownMetadataValue
    repositoryUrl
    commitUrl
  }

private def readLeanToolchain : IO String := do
  let cwd ← IO.currentDir
  match ← readTrimmedFile? (cwd / "lean-toolchain") with
  | some toolchain => pure toolchain
  | none =>
      pure <| (← Process.runTrimmedCommand? "lean" #["--version"]).getD unknownMetadataValue

private def readLakeManifestJson? : IO (Option Json) := do
  let cwd ← IO.currentDir
  try
    unless ← (cwd / "lake-manifest.json").pathExists do
      return none
    match Json.parse (← IO.FS.readFile (cwd / "lake-manifest.json")) with
    | .ok json => pure (some json)
    | .error _ => pure none
  catch _ =>
    pure none

private def jsonStringField? (json : Json) (field : String) : Option String :=
  match json.getObjValAs? String field with
  | .ok value => some value
  | .error _ => none

private def manifestPackages? (json : Json) : Option (Array Json) :=
  match json.getObjVal? "packages" with
  | .ok (.arr packages) => some packages
  | _ => none

private def manifestPackageByName? (manifest : Json) (names : Array String) : Option Json := do
  let packages ← manifestPackages? manifest
  packages.find? fun pkg =>
    match jsonStringField? pkg "name" with
    | some name => names.any (· == name)
    | none => false

private def shortRev (rev : String) : String :=
  if rev.length <= 12 then rev else (rev.take 12).copy

private def versionFromManifestPackage? (pkg : Json) : Option String :=
  match jsonStringField? pkg "rev" with
  | some rev =>
      let rev := shortRev rev
      match jsonStringField? pkg "inputRev" with
      | some inputRev =>
          if inputRev == rev then
            some rev
          else
            some s!"{inputRev}@{rev}"
      | none => some rev
  | none => none

private def packageMetadataFromPathPackage? (pkg : Json) : IO (Option PackageMetadata) := do
  let some dir := jsonStringField? pkg "dir"
    | return none
  let cwd ← IO.currentDir
  let packageDir := (cwd / dir).normalize
  let some version ← Git.shortCommitAt? packageDir
    | return none
  let repositoryUrl ← Git.repositoryUrlAt? packageDir
  let commitUrl := Git.commitUrl? repositoryUrl (← Git.fullCommitAt? packageDir)
  pure <| some { version, repositoryUrl, commitUrl }

private def packageMetadataFromGitPackage? (pkg : Json) : Option PackageMetadata := do
  let version ← versionFromManifestPackage? pkg
  let repositoryUrl :=
    match jsonStringField? pkg "url" with
    | some url => Git.githubRepositoryUrl? url
    | none => none
  let commitUrl := Git.commitUrl? repositoryUrl (jsonStringField? pkg "rev")
  some { version, repositoryUrl, commitUrl }

private def packageMetadata? (manifest : Json) (names : Array String) : IO (Option PackageMetadata) := do
  let some pkg := manifestPackageByName? manifest names
    | return none
  match packageMetadataFromGitPackage? pkg with
  | some metadata => pure (some metadata)
  | none => packageMetadataFromPathPackage? pkg

private def gitPackageMetadataAt (dir : System.FilePath) : IO PackageMetadata := do
  let version ← Git.shortCommitAt? dir
  let repositoryUrl ← Git.repositoryUrlAt? dir
  let commitUrl := Git.commitUrl? repositoryUrl (← Git.fullCommitAt? dir)
  pure {
    version := version.getD unknownMetadataValue
    repositoryUrl
    commitUrl
  }

private def readBlueprintPackage (manifest? : Option Json) : IO PackageMetadata := do
  match manifest? with
  | some manifest =>
      match ← packageMetadata? manifest #["VersoBlueprint", "verso-blueprint"] with
      | some metadata => pure metadata
      | none => gitPackageMetadataAt (← IO.currentDir)
  | none => gitPackageMetadataAt (← IO.currentDir)

private def readMathlibPackage? (manifest? : Option Json) : IO (Option PackageMetadata) := do
  match manifest? with
  | some manifest => packageMetadata? manifest #["mathlib", "Mathlib"]
  | none => pure none

private def tomlQuotedValue? (line key : String) : Option String :=
  let line := line.trimAscii.toString
  match line.splitOn "=" with
  | lhs :: rhsParts =>
      if lhs.trimAscii.toString != key then
        none
      else
        let rhs := (String.intercalate "=" rhsParts).trimAscii.toString
        match rhs.splitOn "\"" with
        | "" :: value :: _ => some value
        | _ => none
  | _ => none

private def firstTomlQuotedValue? (lines : List String) (key : String) : Option String :=
  match lines with
  | [] => none
  | line :: lines =>
      match tomlQuotedValue? line key with
      | some value => some value
      | none => firstTomlQuotedValue? lines key

private def readHarnessFormalizationPath? : IO (Option String) := do
  let cwd ← IO.currentDir
  match ← readTrimmedFile? (cwd / "verso-harness.toml") with
  | some text => pure <| firstTomlQuotedValue? (text.splitOn "\n") "formalization_path"
  | none => pure none

private def readUpstreamBlueprint? : IO (Option GitCommitMetadata) := do
  let cwd ← IO.currentDir
  let some upstreamPath ← readHarnessFormalizationPath?
    | return none
  let upstreamDir := (cwd / upstreamPath).normalize
  unless ← upstreamDir.pathExists do
    return none
  match (← Git.toplevelAt? cwd), (← Git.toplevelAt? upstreamDir) with
  | some projectRoot, some upstreamRoot =>
      if projectRoot == upstreamRoot then
        return none
  | _, _ => pure ()
  gitCommitMetadataAt? upstreamDir

def readBuildMetadata : IO BuildMetadata := do
  let cwd ← IO.currentDir
  let manifest? ← readLakeManifestJson?
  let compiledAt ← Process.runTrimmedCommand? "date" #["-u", "+%Y-%m-%dT%H:%M:%SZ"]
  let commit ← Git.shortCommitAt? cwd
  let subject ← Git.subjectAt? cwd
  let projectRepositoryUrl ← Git.repositoryUrlAt? cwd
  let projectCommitUrl := Git.commitUrl? projectRepositoryUrl (← Git.fullCommitAt? cwd)
  let leanToolchain ← readLeanToolchain
  let blueprintPackage ← readBlueprintPackage manifest?
  let mathlibPackage? ← readMathlibPackage? manifest?
  let upstreamBlueprint ← readUpstreamBlueprint?
  pure {
    compiledAt := compiledAt.getD unknownMetadataValue
    commit := commit.getD unknownMetadataValue
    subject := subject.getD unknownMetadataValue
    projectRepositoryUrl
    projectCommitUrl
    leanToolchain
    blueprintVersion := blueprintPackage.version
    blueprintRepositoryUrl := blueprintPackage.repositoryUrl
    blueprintCommitUrl := blueprintPackage.commitUrl
    mathlibVersion := mathlibPackage?.map (·.version)
    mathlibRepositoryUrl := mathlibPackage?.bind (·.repositoryUrl)
    mathlibCommitUrl := mathlibPackage?.bind (·.commitUrl)
    upstreamBlueprint
  }

private def escapedHtmlText (text : String) : Output.Html :=
  Output.Html.text false <|
    ((text.replace "&" "&amp;").replace "<" "&lt;").replace ">" "&gt;"

private def buildMetadataLabelHtml (label : String) (href? : Option String) : Output.Html :=
  match href? with
  | some href =>
      Output.Html.tag "a"
        #[("class", "bp_build_metadata_label bp_build_metadata_link"), ("href", href)]
        (escapedHtmlText label)
  | none =>
      Output.Html.tag "span" #[("class", "bp_build_metadata_label")] (escapedHtmlText label)

private def buildMetadataCodeHtml (value : String) (href? : Option String) : Output.Html :=
  let code := Output.Html.tag "code" #[("class", "bp_build_metadata_commit")] (escapedHtmlText value)
  match href? with
  | some href =>
      Output.Html.tag "a" #[("class", "bp_build_metadata_commit_link"), ("href", href)] code
  | none => code

def buildMetadataHtml (metadata : BuildMetadata) : Output.Html :=
  open Verso.Output.Html in
  {{
    <div class="bp_build_metadata" aria-label="Build metadata">
      <span class="bp_build_metadata_item">
        <span class="bp_build_metadata_label">"Compiled"</span>
        <span class="bp_build_metadata_value">{{escapedHtmlText metadata.compiledAt}}</span>
      </span>
      <span class="bp_build_metadata_item">
        {{buildMetadataLabelHtml "Project" metadata.projectRepositoryUrl}}
        {{buildMetadataCodeHtml metadata.commit metadata.projectCommitUrl}}
        <span class="bp_build_metadata_subject">{{escapedHtmlText metadata.subject}}</span>
      </span>
      <span class="bp_build_metadata_item">
        <span class="bp_build_metadata_label">"Lean"</span>
        <span class="bp_build_metadata_value">{{escapedHtmlText metadata.leanToolchain}}</span>
      </span>
      <span class="bp_build_metadata_item">
        {{buildMetadataLabelHtml "VersoBlueprint" metadata.blueprintRepositoryUrl}}
        {{buildMetadataCodeHtml metadata.blueprintVersion metadata.blueprintCommitUrl}}
      </span>
      {{if let some upstream := metadata.upstreamBlueprint then
        {{<span class="bp_build_metadata_item">
            {{buildMetadataLabelHtml "Upstream" upstream.repositoryUrl}}
            {{buildMetadataCodeHtml upstream.commit upstream.commitUrl}}
            <span class="bp_build_metadata_subject">{{escapedHtmlText upstream.subject}}</span>
          </span>}}
        else .empty}}
      {{if let some mathlibVersion := metadata.mathlibVersion then
        {{<span class="bp_build_metadata_item">
            {{buildMetadataLabelHtml "Mathlib" metadata.mathlibRepositoryUrl}}
            {{buildMetadataCodeHtml mathlibVersion metadata.mathlibCommitUrl}}
          </span>}}
        else .empty}}
    </div>
  }}

def buildMetadataHtmlString (metadata : BuildMetadata) : String :=
  Output.Html.asString <| buildMetadataHtml metadata

def insertBuildMetadataHtml? (html metadataHtml : String) : Option String :=
  if html.contains "class=\"bp_build_metadata\"" then
    some html
  else
    let titlePageMarker := "<div class=\"titlepage\">"
    let h1CloseMarker := "</h1>"
    match html.splitOn titlePageMarker with
    | before :: titlePagePart :: titlePageRest =>
        let afterTitlePage := String.intercalate titlePageMarker (titlePagePart :: titlePageRest)
        match afterTitlePage.splitOn h1CloseMarker with
        | titleHtml :: afterTitle :: afterTitleRest =>
            some <|
              before ++ titlePageMarker ++ titleHtml ++ h1CloseMarker ++ "\n" ++ metadataHtml ++
                String.intercalate h1CloseMarker (afterTitle :: afterTitleRest)
        | _ => none
    | _ => none

private def writeBuildMetadataHtml
    (metadata : BuildMetadata)
    (logError : String → IO Unit)
    (path : System.FilePath) : IO Unit := do
  unless ← path.pathExists do
    logError s!"Blueprint build metadata: missing root page {path}"
    return
  let html ← IO.FS.readFile path
  match insertBuildMetadataHtml? html (buildMetadataHtmlString metadata) with
  | some html => IO.FS.writeFile path html
  | none => logError s!"Blueprint build metadata: could not find title page heading in {path}"

def emitBuildMetadata (metadata : BuildMetadata) : ExtraStep := fun mode logError cfg _state _text => do
  writeBuildMetadataHtml metadata logError (outDirForMode cfg mode / "index.html")

private def highlightedDocstringInnerTextRead : String :=
  "const str = d.innerText;"

private def highlightedDocstringTextContentRead : String :=
  "const str = d.textContent || \"\";"

private def highlightedTacticShowGuardBefore : String :=
  "if (inst.reference.className == 'tactic') {
            const toggle = inst.reference.querySelector(\"input.tactic-toggle\");"

private def highlightedTacticShowGuardAfter : String :=
  "if (inst.reference.className == 'tactic') {
            if (!inst.reference.querySelector(\".tactic-state\")) {
              return false;
            }
            const toggle = inst.reference.querySelector(\"input.tactic-toggle\");"

private def highlightedTacticContentBefore : String :=
  "if (tgt.className == 'tactic') {
            const state = tgt.querySelector(\".tactic-state\").cloneNode(true);"

private def highlightedTacticContentAfter : String :=
  "if (tgt.className == 'tactic') {
            const stateSource = tgt.querySelector(\".tactic-state\");
            if (!stateSource) {
              return content;
            }
            const state = stateSource.cloneNode(true);"

private def patchHighlightedStartupJs (js : JS) : JS :=
  let patched :=
    js.js
      |>.replace highlightedDocstringInnerTextRead highlightedDocstringTextContentRead
      |>.replace highlightedTacticShowGuardBefore highlightedTacticShowGuardAfter
      |>.replace highlightedTacticContentBefore highlightedTacticContentAfter
  { js with js := patched }

private def patchBlueprintHtmlAssets (assets : HtmlAssets) : HtmlAssets :=
  { assets with
    extraJs :=
      Std.HashSet.ofArray <|
        assets.extraJs.toArray.map patchHighlightedStartupJs
  }

private def patchBlueprintTraverseState (state : TraverseState) : TraverseState :=
  state.modifyHtmlAssets patchBlueprintHtmlAssets

def manifestFilename : String := "blueprint-manifest.json"

def htmlCacheFilename : String := "blueprint-html-cache.json"

inductive EntryKind where
  | block
  | leanDecl
  | citation
deriving Inhabited, Repr, ToJson, FromJson

/-- Dependency axis for a related informal node. -/
inductive RelationAxis where
  | statement
  | proof
deriving Inhabited, Repr, BEq, ToJson, FromJson

def RelationAxis.display : RelationAxis → String
  | .statement => "statement"
  | .proof => "proof"

/-- Manifest-owned related informal node metadata for slide and tooling consumers. -/
structure RelatedEntry where
  /-- Informal label for the related node. -/
  label : Name
  /-- Resolved display title for the related node. -/
  title : String
  /-- Canonical link target for the related informal node, if available. -/
  href : Option String := none
  /-- HTML-cache key for this related node's statement preview. -/
  previewKey : String
  /-- Statement/proof dependency axes through which this related node is connected. -/
  axes : Array RelationAxis := #[]
deriving Inhabited, Repr, ToJson, FromJson

/-- Manifest-owned group metadata for an informal node. -/
structure GroupRelation where
  /-- Parent/group label. -/
  label : Name
  /-- Resolved group title, or the parent label when no group declaration exists. -/
  title : String
  /-- Whether a matching `:::group` declaration was present. -/
  declared : Bool := false
  /-- Traversal-ordered statement siblings in this group, excluding the current node. -/
  entries : Array RelatedEntry := #[]
deriving Inhabited, Repr, ToJson, FromJson

structure Entry where
  /-- Composite preview lookup key for this target family. -/
  key : String
  /-- Preview target family. -/
  targetKind : EntryKind
  /-- Canonical target label: informal label, Lean declaration name, or citation label. -/
  label : Name
  /-- Which preview variant this entry contains; non-block previews use `statement`. -/
  facet : PreviewCache.Facet
  /-- Kind (definition, proposition, lemma, theorem, corollary). -/
  kind : Option Informal.Data.NodeKind := none
  /-- Resolved display title for this preview entry. -/
  title : String
  /-- Structured heading caption for renderers that need to lay out the title. -/
  displayCaption : Option String := none
  /-- Structured heading label or number for renderers that need to lay out the title. -/
  displayLabel : Option String := none
  /-- Canonical link target for the rendered informal node. -/
  href : Option String := none
  /-- Parent/group label for this informal node, if any. -/
  parent : Option Name := none
  /-- Resolved display title for the parent/group, if any. -/
  parentTitle : Option String := none
  /-- Structured statement use metadata, preserving origin and intent tags. -/
  statementUses : Array Informal.Data.UseRef := #[]
  /-- Structured proof use metadata, preserving origin and intent tags. -/
  proofUses : Array Informal.Data.UseRef := #[]
  /-- HTML-cache keys for Lean declaration previews associated with this entry. -/
  leanCodePreviewKeys : Array String := #[]
  /-- Canonical Lean code data associated with this informal node, if any. -/
  codeData : Option Informal.BlockCodeData := none
  /-- Informal nodes used by this entry, with statement/proof axes and preview keys. -/
  uses : Array RelatedEntry := #[]
  /-- Informal statement nodes that depend on this entry, with dependency axes and preview keys. -/
  usedBy : Array RelatedEntry := #[]
  /-- Group declaration status and traversal-ordered sibling statement entries. -/
  group : Option GroupRelation := none
  /-- Resolved display name of the assigned owner, if available. -/
  ownerDisplayName : Option String := none
  /-- Normalized tags attached to this informal node. -/
  tags : Array String := #[]
  /-- Declared triage priority for this informal node, if any. -/
  priority : Option String := none
  /-- Declared effort estimate for this informal node, if any. -/
  effort : Option String := none
deriving Inhabited, Repr, ToJson, FromJson

structure File where
  /-- Semantic preview entries keyed by `PreviewCache`, Lean preview key, or citation key. -/
  previews : Array Entry := #[]
deriving Inhabited, Repr, ToJson, FromJson

namespace HtmlCache

/--
First hover id reserved for cache-rendered fragments.

Verso writes page-local hover tables after rendering the main document. Cache
fragments are rendered separately and then merged into that table, so their ids
must live outside the normal small page-local range unless the HTML fragments are
structurally remapped. Keeping a reserved range preserves normal
`data-verso-hover` markup without duplicating hover payloads into each fragment.
-/
def hoverIdStart : Nat := 1000000

structure HoverDoc where
  /-- Numeric `data-verso-hover` id reserved for a cached rendered fragment. -/
  id : Nat
  /-- Rendered hover payload HTML for this id. -/
  html : String
deriving Inhabited, Repr, ToJson, FromJson

structure Entry where
  /-- Composite preview lookup key for this rendered HTML fragment. -/
  key : String
  /-- Rendered HTML fragment for this preview/cache entry. -/
  html : String
deriving Inhabited, Repr, ToJson, FromJson

structure File where
  /-- Rendered HTML fragments keyed by preview/cache entry key. -/
  entries : Array Entry := #[]
  /-- Verso hover payloads referenced by the rendered HTML fragments. -/
  hoverDocs : Array HoverDoc := #[]
deriving Inhabited, Repr, ToJson, FromJson

structure Index where
  entriesByKey : Std.HashMap String Entry := {}
deriving Inhabited

def Index.ofFile (file : File) : Index := {
  entriesByKey := file.entries.foldl (fun entries entry => entries.insert entry.key entry) {}
}

def File.index (file : File) : Index :=
  Index.ofFile file

def Index.findEntry? (index : Index) (key : String) : Option Entry :=
  index.entriesByKey.get? key

def Index.findHtml? (index : Index) (key : String) : Option String :=
  (index.findEntry? key).map (·.html)

def File.findEntry? (file : File) (key : String) : Option Entry :=
  file.index.findEntry? key

def File.findHtml? (file : File) (key : String) : Option String :=
  file.index.findHtml? key

def initialHoverState : Verso.Code.Hover.State Output.Html :=
  { dedup := { ({} : Verso.Code.Hover.Dedup Output.Html) with nextId := hoverIdStart }
    idSupply := {} }

def HoverDoc.ofDedup (dedup : Verso.Code.Hover.Dedup Output.Html) : Array HoverDoc :=
  dedup.contentId.toArray.map (fun (id, html) => {
    id
    html := html.asString
  }) |>.qsort (fun a b => a.id < b.id)

def HoverDoc.toHtml (doc : HoverDoc) : Output.Html :=
  Output.Html.text false doc.html

def File.hoverDocsJson (file : File) : Json :=
  file.hoverDocs.foldl (init := Json.mkObj []) fun out doc =>
    out.setObjVal! (toString doc.id) (Json.str doc.html)

def File.hoverDedup (file : File) : Verso.Code.Hover.Dedup Output.Html :=
  let nextId :=
    file.hoverDocs.foldl (init := 0) fun next doc =>
      Nat.max next (doc.id + 1)
  let contentId :=
    file.hoverDocs.foldl (init := {}) fun content doc =>
      content.insert doc.id doc.toHtml
  let idContent :=
    file.hoverDocs.foldl (init := {}) fun ids doc =>
      ids.insert doc.toHtml doc.id
  { nextId, contentId, idContent }

def File.hoverState (file : File) : Verso.Code.Hover.State Output.Html :=
  { dedup := file.hoverDedup
    idSupply := {} }

private def pushDistinctHtml (values : Array String) (html : String) : Array String :=
  if values.contains html then values else values.push html

/--
Rendered Lean-code preview bodies for an informal entry, deduplicated by the
actual rendered HTML fragment.
-/
def Index.codeHtmlBodies (index : Index) (entry : _root_.Informal.PreviewManifest.Entry) :
    Array String :=
  entry.leanCodePreviewKeys.foldl (init := #[]) fun bodies key =>
    match index.findHtml? key with
    | some html => pushDistinctHtml bodies html
    | none => bodies

def File.codeHtmlBodies (file : File) (entry : _root_.Informal.PreviewManifest.Entry) :
    Array String :=
  file.index.codeHtmlBodies entry

def readFile (path : System.FilePath) : IO File := do
  let json ←
    match Json.parse (← IO.FS.readFile path) with
    | .ok json => pure json
    | .error err => throw <| IO.userError s!"could not parse Blueprint HTML cache {path}: {err}"
  match fromJson? (α := File) json with
  | .ok file => pure file
  | .error err => throw <| IO.userError s!"could not decode Blueprint HTML cache {path}: {err}"

end HtmlCache

structure Files where
  manifest : File := {}
  htmlCache : HtmlCache.File := {}
deriving Inhabited, Repr

structure Index where
  entriesByKey : Std.HashMap String Entry := {}
deriving Inhabited

def Index.ofFile (file : File) : Index := {
  entriesByKey := file.previews.foldl (fun entries entry => entries.insert entry.key entry) {}
}

def File.index (file : File) : Index :=
  Index.ofFile file

def Index.findEntry? (index : Index) (key : String) : Option Entry :=
  index.entriesByKey.get? key

def File.findEntry? (file : File) (key : String) : Option Entry :=
  file.index.findEntry? key

/-- Count available Lean-code preview entries before display-level deduplication. -/
def Index.codeEntryCount (index : Index) (entry : Entry) : Nat :=
  (entry.leanCodePreviewKeys.filterMap index.findEntry?).size

/--
Lean-code preview keys are declaration-granular. Return the semantic entries in
key order while keeping display-level rendered-HTML deduplication in
`HtmlCache.Index.codeHtmlBodies`.
-/
def Index.codeEntries (index : Index) (entry : Entry) : Array Entry :=
  entry.leanCodePreviewKeys.filterMap index.findEntry?

def readFile (path : System.FilePath) : IO File := do
  let json ←
    match Json.parse (← IO.FS.readFile path) with
    | .ok json => pure json
    | .error err => throw <| IO.userError s!"could not parse Blueprint manifest {path}: {err}"
  match fromJson? (α := File) json with
  | .ok file => pure file
  | .error err => throw <| IO.userError s!"could not decode Blueprint manifest {path}: {err}"

private structure SchemaState where
  seen : Std.HashSet Name := {}
  defs : Array (String × Json) := #[]

private def jsonSchemaRef (name : Name) : Json :=
  Json.mkObj [("$ref", Json.str s!"#/$defs/{name}")]

private def fieldKey (name : Name) : String :=
  name.getString!

private def fieldType (fieldName : Name) : MetaM Expr := do
  let info ← getConstInfo fieldName
  Meta.forallTelescopeReducing info.type fun _ body => pure body

private def docSummary (docs : String) : String :=
  match docs.trimAscii.toString.splitOn "\n\n" with
  | [] => ""
  | first :: _ => first.trimAscii.toString

private def schemaWithDescription (schema : Json) (docs : String) : Json :=
  let docs := docSummary docs
  if docs.isEmpty then
    schema
  else
    let combined :=
      match schema.getObjValAs? String "description" with
      | .ok existing =>
          let existing := existing.trimAscii.toString
          if existing.isEmpty then docs else s!"{docs} {existing}"
      | .error _ => docs
    schema.setObjVal! "description" (Json.str combined)

private partial def schemaForType (ty : Expr) : StateT SchemaState MetaM Json := do
  let ty ← Meta.whnf ty
  let args := Expr.getAppArgs ty
  match Expr.getAppFn ty with
  | .const ``String _ =>
      pure <| Json.mkObj [("type", Json.str "string")]
  | .const ``Name _ =>
      pure <| Json.mkObj [("type", Json.str "string")]
  | .const ``Bool _ =>
      pure <| Json.mkObj [("type", Json.str "boolean")]
  | .const ``Nat _ =>
      pure <| Json.mkObj [("type", Json.str "integer")]
  | .const ``Int _ =>
      pure <| Json.mkObj [("type", Json.str "integer")]
  | .const ``Float _ =>
      pure <| Json.mkObj [("type", Json.str "number")]
  | .const ``Array _ =>
      let itemSchema ← schemaForType args[0]!
      pure <| Json.mkObj [("type", Json.str "array"), ("items", itemSchema)]
  | .const ``List _ =>
      let itemSchema ← schemaForType args[0]!
      pure <| Json.mkObj [("type", Json.str "array"), ("items", itemSchema)]
  | .const ``Option _ =>
      let itemSchema ← schemaForType args[0]!
      pure <| Json.mkObj [
        ("anyOf", Json.arr #[
          itemSchema,
          Json.mkObj [("type", Json.str "null")]
        ])
      ]
  | .const name _ =>
      let st ← get
      if st.seen.contains name then
        return jsonSchemaRef name
      modify fun st => { st with seen := st.seen.insert name }
      let env ← getEnv
      if let some info := getStructureInfo? env name then
        let mut properties : List (String × Json) := []
        let mut required : Array Json := #[]
        for fieldInfo in info.fieldInfo do
          let schema ← schemaForType (← fieldType fieldInfo.projFn)
          let docs? ← findDocString? env fieldInfo.projFn
          let schema :=
            match docs? with
            | some docs => schemaWithDescription schema docs
            | none => schema
          let key := fieldKey fieldInfo.fieldName
          properties := properties.concat (key, schema)
          required := required.push (Json.str key)
        let schema := Json.mkObj [
          ("type", Json.str "object"),
          ("properties", Json.mkObj properties),
          ("required", Json.arr required),
          ("additionalProperties", Json.bool false)
        ]
        modify fun st => { st with defs := st.defs.push (name.toString, schema) }
        pure <| jsonSchemaRef name
      else
        match env.find? name with
        | some (.inductInfo info) =>
            let mut enumVals : Array Json := #[]
            for ctorName in info.ctors do
              let ctorInfo ← getConstInfoCtor ctorName
              unless ctorInfo.numFields == 0 do
                let schema := Json.mkObj [
                  ("type", Json.str "object"),
                  ("description", Json.str s!"Derived JSON representation for '{name}'.")
                ]
                modify fun st => { st with defs := st.defs.push (name.toString, schema) }
                return jsonSchemaRef name
              enumVals := enumVals.push (Json.str ctorName.getString!)
            let schema := Json.mkObj [
              ("type", Json.str "string"),
              ("enum", Json.arr enumVals)
            ]
            modify fun st => { st with defs := st.defs.push (name.toString, schema) }
            pure <| jsonSchemaRef name
        | _ =>
            throwError "Unsupported schema type: {ty}"
  | _ =>
      throwError "Unsupported schema type: {ty}"

syntax (name := previewManifestSchema) "previewManifestSchema%" : term

@[term_elab previewManifestSchema]
def elabPreviewManifestSchema : TermElab := fun _ _ => do
  let rootTy := Lean.mkConst ``Informal.PreviewManifest.File
  let (_rootRef, st) ← Meta.liftMetaM <| (schemaForType rootTy).run {}
  let defs := st.defs.qsort (fun a b => a.1 < b.1)
  let schema : Json := Json.mkObj [
    ("$schema", Json.str "https://json-schema.org/draft/2020-12/schema"),
    ("$ref", Json.str s!"#/$defs/{``Informal.PreviewManifest.File}"),
    ("$defs", Json.mkObj defs.toList)
  ]
  let schemaText := schema.render.pretty 80
  return mkStrLit schemaText

def schemaString : String :=
  previewManifestSchema%

def schemaJson : Json :=
  match Json.parse schemaString with
  | .ok json => json
  | .error err => panic! s!"Invalid generated Blueprint manifest schema: {err}"

private def jsonPretty (json : Json) : String :=
  json.render.pretty 80

private def xrefExcludedDomainNames : Array Name :=
  Informal.TraversalIndex.allSpecs.filterMap fun spec =>
    match spec.kind with
    | .semanticDomain => none
    | .internalIndex | .runtimeCache | .accumulator => some spec.name

private def isPublicXrefDomain (name : Name) : Bool :=
  !xrefExcludedDomainNames.any (· == name)

private def publicXrefDomains (domains : Verso.NameMap Verso.Multi.Domain) :
    Verso.NameMap Verso.Multi.Domain := Id.run do
  let mut publicDomains : Verso.NameMap Verso.Multi.Domain := {}
  for (name, domain) in domains do
    if isPublicXrefDomain name then
      publicDomains := publicDomains.insert! name domain
  publicDomains

def buildPublicXrefJson (state : TraverseState) : Json :=
  Verso.Multi.xrefJson (publicXrefDomains state.domains) state.externalTags

private def replaceFindPageXref (html xrefJson : String) : Option String :=
  let marker := "window.xref = "
  match html.splitOn marker with
  | before :: afterMarkerPart :: afterMarkerParts =>
      let afterMarker := String.intercalate marker (afterMarkerPart :: afterMarkerParts)
      match afterMarker.splitOn Verso.Genre.Manual.find.js with
      | _oldJson :: afterFindJsPart :: afterFindJsParts =>
          some <|
            before ++ marker ++ xrefJson ++ ";\n" ++
            Verso.Genre.Manual.find.js ++
            String.intercalate Verso.Genre.Manual.find.js (afterFindJsPart :: afterFindJsParts)
      | _ => none
  | _ => none

def emitPublicXref (mode : Mode) (logError : String → IO Unit) (cfg : Verso.Genre.Manual.Config)
    (state : TraverseState) : IO Unit := do
  let outDir := outDirForMode cfg mode
  let json := (buildPublicXrefJson state).compress
  IO.FS.writeFile (outDir / "xref.json") json
  let findIndex := outDir / "find" / "index.html"
  if ← findIndex.pathExists then
    let html ← IO.FS.readFile findIndex
    match replaceFindPageXref html json with
    | some html => IO.FS.writeFile findIndex html
    | none => logError s!"Blueprint xref filter: could not find embedded xref payload in {findIndex}"

private def blockInfo? (state : TraverseState) (label : Name) : Option Informal.BlockData :=
  match Informal.TraversalIndex.Nodes.data? state label with
  | some blockData => some (blockData.withResolvedNumbering state)
  | none => none

private def blockTitle (state : TraverseState) (label : Name)
    (facet : PreviewCache.Facet := .statement) (blockData? : Option Informal.BlockData := none) : String :=
  match blockData? <|> blockInfo? state label with
  | some blockData =>
      match facet with
      | .proof => blockData.displayProofTitle state
      | .statement => blockData.displayTitle state
  | none => label.toString

private structure BlockHeadingParts where
  caption : String
  label : String

private def blockHeadingParts? (state : TraverseState) (label : Name)
    (facet : PreviewCache.Facet := .statement) (blockData? : Option Informal.BlockData := none) :
    Option BlockHeadingParts := do
  let blockData ← blockData? <|> blockInfo? state label
  let numberText := blockData.displayNumber state
  match facet with
  | .statement =>
      let kind ← blockData.statementKind? state
      some { caption := toString kind, label := numberText }
  | .proof =>
      let label :=
        match blockData.statementKind? state with
        | some kind => s!"for {kind} {numberText}"
        | none => numberText
      some { caption := "Proof", label }

private def blockHref (state : TraverseState) (label : Name)
    (facet : PreviewCache.Facet := .statement) : Option String :=
  Informal.TraversalIndex.TraversalPreviews.hrefFor? state label facet <|>
    Informal.TraversalIndex.Nodes.href? state label

private def blockKind? (blockData? : Option Informal.BlockData) : Option Informal.Data.NodeKind :=
  match blockData? with
  | some blockData =>
      match blockData.kind with
      | Informal.Data.InProgressKind.statement kind => some kind
      | Informal.Data.InProgressKind.proof => none
  | none => none

private def groupTitle? (state : TraverseState) (parent : Name) : Option String :=
  match Informal.TraversalIndex.Groups.data? state parent with
  | some groupData =>
      let header := groupData.header.trimAscii.toString
      if header.isEmpty then none else some header
  | none => none

private def blockParentTitle? (state : TraverseState) (blockData? : Option Informal.BlockData) : Option String :=
  blockData?.bind fun blockData =>
    blockData.parent.map fun parent =>
      (groupTitle? state parent).getD parent.toString

private def pushUnique [BEq α] (values : Array α) (value : α) : Array α :=
  if values.contains value then values else values.push value

private def inlineCodePreviewKeys (state : TraverseState) (label : Name) : Array String :=
  match Informal.TraversalIndex.InlineCode.data? state label with
  | none => #[]
  | some codeData =>
    let decls := (codeData.definedDefs.map (·.name)) ++ (codeData.definedTheorems.map (·.name))
    decls.map Informal.TraversalIndex.LeanCodePreviews.lookupKey

private def blockLeanCodePreviewKeys
    (state : TraverseState)
    (label : Name)
    (entry : PreviewCache.Entry) : Array String :=
  (inlineCodePreviewKeys state label).foldl
    (init := entry.leanCodePreviewKeys)
    (fun keys key => pushUnique keys key)

private def externalDeclsFromLeanPreviewKeys
    (state : TraverseState)
    (keys : Array String) : Array Informal.Data.ExternalRef :=
  keys.filterMap fun key =>
    match Informal.TraversalIndex.LeanCodePreviews.object? state key with
    | none => none
    | some obj =>
        match fromJson? (α := Informal.LeanCodePreview.Entry) obj.data with
        | .ok { source := .externalDecl decl, .. } => some decl
        | _ => none

private def blockCodeData?
    (state : TraverseState)
    (label : Name)
    (entry : PreviewCache.Entry)
    (blockData? : Option Informal.BlockData) : Option Informal.BlockCodeData :=
  let inline? := Informal.TraversalIndex.InlineCode.data? state label
  let externalDecls := externalDeclsFromLeanPreviewKeys state entry.leanCodePreviewKeys
  let external? :=
    if externalDecls.isEmpty then
      blockData?.bind (·.codeData)
    else
      some (Informal.BlockCodeData.external externalDecls)
  Informal.BlockCodeData.ofHintAndInline external? inline?

private def relatedAxes (source : Informal.BlockData) (target : Name) : Array RelationAxis :=
  let axes : Array RelationAxis :=
    if source.statementDeps.contains target then #[.statement] else #[]
  if source.proofDeps.contains target then axes.push .proof else axes

private def relatedEntryForLabel
    (state : TraverseState)
    (label : Name)
    (axes : Array RelationAxis := #[]) : RelatedEntry :=
  let blockData? := blockInfo? state label
  {
    label
    title := blockTitle state label .statement blockData?
    href := blockHref state label
    previewKey := PreviewCache.key label .statement
    axes
  }

private def relatedEntryForBlock
    (state : TraverseState)
    (blockData : Informal.BlockData)
    (axes : Array RelationAxis := #[]) : RelatedEntry :=
  {
    label := blockData.label
    title := blockTitle state blockData.label .statement (some blockData)
    href := blockHref state blockData.label
    previewKey := PreviewCache.key blockData.label .statement
    axes
  }

private def buildUsesRelations
    (state : TraverseState)
    (blockData : Informal.BlockData) : Array RelatedEntry :=
  let labels := (blockData.statementDeps ++ blockData.proofDeps).foldl
    (fun acc label => if acc.contains label then acc else acc.push label)
    #[]
  labels.map fun label =>
    relatedEntryForLabel state label (relatedAxes blockData label)

private def buildUsedByRelations
    (state : TraverseState)
    (storedBlocks : Array Informal.BlockData)
    (blockData : Informal.BlockData) : Array RelatedEntry :=
  storedBlocks.filterMap fun source =>
    if source.label == blockData.label then
      none
    else
      let axes := relatedAxes source blockData.label
      if axes.isEmpty then
        none
      else
        some <| relatedEntryForBlock state source axes

private def buildGroupRelation?
    (state : TraverseState)
    (storedBlocks : Array Informal.BlockData)
    (blockData : Informal.BlockData) : Option GroupRelation := do
  let parent ← blockData.parent
  let groupData? := Informal.TraversalIndex.Groups.data? state parent
  let title :=
    match groupData? with
    | some groupData =>
      let header := groupData.header.trimAscii.toString
      if header.isEmpty then parent.toString else header
    | none => parent.toString
  let entries := storedBlocks.filterMap fun source =>
    if source.label == blockData.label then
      none
    else if source.parent == some parent then
      match source.kind with
      | .statement _ => some <| relatedEntryForBlock state source
      | .proof => none
    else
      none
  some {
    label := parent
    title
    declared := groupData?.isSome
    entries
  }

private def buildTraversalEntries
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState)
    (hoverState : Verso.Code.Hover.State Output.Html) :
    IO (Array Entry × Array HtmlCache.Entry × Verso.Code.Hover.State Output.Html) := do
  let some domain := Informal.TraversalIndex.TraversalPreviews.domain? state
    | return (#[], #[], hoverState)
  let storedBlocks := Informal.collectStoredBlocks state
  let mut entries := #[]
  let mut htmlEntries := #[]
  let mut hoverState := hoverState
  for (_key, obj) in domain.objects.toArray do
    match fromJson? (α := PreviewCache.Entry) obj.data with
    | .error err =>
      logError s!"Blueprint manifest: malformed preview entry {obj.canonicalName}: {err}"
    | .ok entry =>
      if entry.blocks.isEmpty then
        continue
      let rendered ← Informal.renderManualBlocksHtmlWithStateAndHovers entry.blocks impls state
        (logError := logError) (hoverState := hoverState)
      hoverState := rendered.hoverState
      let html := rendered.html.asString
      if html.trimAscii.isEmpty then
        continue
      let blockData? := blockInfo? state entry.label
      let key := PreviewCache.key entry.label entry.facet
      let headingParts? := blockHeadingParts? state entry.label entry.facet blockData?
      let codeData := blockCodeData? state entry.label entry blockData?
      let manifestEntry : Entry := {
        key
        targetKind := .block
        label := entry.label
        facet := entry.facet
        kind := blockKind? blockData?
        title := blockTitle state entry.label entry.facet blockData?
        displayCaption := headingParts?.map (·.caption)
        displayLabel := headingParts?.map (·.label)
        href := blockHref state entry.label entry.facet
        parent := blockData?.bind (·.parent)
        parentTitle := blockParentTitle? state blockData?
        statementUses := blockData?.map (·.statementUses) |>.getD #[]
        proofUses := blockData?.map (·.proofUses) |>.getD #[]
        leanCodePreviewKeys := blockLeanCodePreviewKeys state entry.label entry
        codeData
        uses := blockData?.map (buildUsesRelations state ·) |>.getD #[]
        usedBy := blockData?.map (buildUsedByRelations state storedBlocks ·) |>.getD #[]
        group := blockData?.bind (buildGroupRelation? state storedBlocks)
        ownerDisplayName := blockData?.bind (·.ownerDisplayName)
        tags := blockData?.map (·.tags) |>.getD #[]
        priority := blockData?.bind (·.priority)
        effort := blockData?.bind (·.effort)
      }
      entries := entries.push manifestEntry
      htmlEntries := htmlEntries.push { key, html }
  pure (entries, htmlEntries, hoverState)

private def buildLeanCodeEntries
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState)
    (hoverState : Verso.Code.Hover.State Output.Html) :
    IO (Array Entry × Array HtmlCache.Entry × Verso.Code.Hover.State Output.Html) := do
  let some domain := Informal.TraversalIndex.LeanCodePreviews.domain? state
    | return (#[], #[], hoverState)
  let mut entries := #[]
  let mut htmlEntries := #[]
  let mut hoverState := hoverState
  for (_key, obj) in domain.objects.toArray do
    match fromJson? (α := Informal.LeanCodePreview.Entry) obj.data with
    | .error err =>
      logError s!"Blueprint manifest: malformed Lean-code preview entry {obj.canonicalName}: {err}"
    | .ok entry =>
      let rendered ← Informal.LeanCodePreview.renderWithState entry impls state
        (logError := logError) (hoverState := hoverState)
      hoverState := rendered.hoverState
      let html := rendered.html.asString
      if html.trimAscii.isEmpty then
        continue
      let manifestEntry : Entry := {
        key := Informal.TraversalIndex.LeanCodePreviews.lookupKey entry.target
        targetKind := .leanDecl
        label := entry.target
        facet := .statement
        title := Informal.LeanCodePreview.title entry.target
      }
      entries := entries.push manifestEntry
      htmlEntries := htmlEntries.push { key := manifestEntry.key, html }
  pure (entries, htmlEntries, hoverState)

private def renderCitationEntryHtml
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState)
    (entry : Informal.Cite.CitationPreviewData)
    (hoverState : Verso.Code.Hover.State Output.Html) :
    IO (String × Verso.Code.Hover.State Output.Html) := do
  let rendered ← Informal.renderManualHtmlWithStateAndHovers
    (entry.item.citation.bibHtml (Verso.Doc.Html.ToHtml.toHtml (genre := Verso.Genre.Manual)))
    impls state (logError := logError) (hoverState := hoverState)
  let body := Informal.Cite.citationPreviewBody rendered.html entry.kind entry.index
  pure (Output.Html.asString body, rendered.hoverState)

private def buildCitationEntries
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState)
    (hoverState : Verso.Code.Hover.State Output.Html) :
    IO (Array Entry × Array HtmlCache.Entry × Verso.Code.Hover.State Output.Html) := do
  let some domain := Informal.TraversalIndex.CitationPreviews.domain? state
    | return (#[], #[], hoverState)
  let mut entries := #[]
  let mut htmlEntries := #[]
  let mut hoverState := hoverState
  for (_key, obj) in domain.objects.toArray do
    match fromJson? (α := Informal.Cite.CitationPreviewData) obj.data with
    | .error err =>
      logError s!"Blueprint manifest: malformed citation preview entry {obj.canonicalName}: {err}"
    | .ok citation =>
      let (html, hoverState') ← renderCitationEntryHtml impls logError state citation hoverState
      hoverState := hoverState'
      if html.trimAscii.isEmpty then
        continue
      let manifestEntry : Entry := {
        key := citation.key
        targetKind := .citation
        label := citation.item.label.toName
        facet := .statement
        title := Informal.Cite.citationPreviewTitle citation.item
        href := Informal.TraversalIndex.Bibliography.href? state citation.item.label
      }
      entries := entries.push manifestEntry
      htmlEntries := htmlEntries.push { key := manifestEntry.key, html }
  pure (entries, htmlEntries, hoverState)

/--
Build the semantic Blueprint manifest and rendered HTML cache from a completed
Manual traversal state.
-/
def buildPreviewDataFiles
    (impls : ExtensionImpls)
    (logError : String → IO Unit)
    (state : TraverseState) : IO Files := do
  let hoverState := HtmlCache.initialHoverState
  let (traversalPreviews, traversalHtml, hoverState) ← buildTraversalEntries impls logError state hoverState
  let (leanCodePreviews, leanCodeHtml, hoverState) ← buildLeanCodeEntries impls logError state hoverState
  let (citationPreviews, citationHtml, hoverState) ← buildCitationEntries impls logError state hoverState
  let previews := (traversalPreviews ++ leanCodePreviews ++ citationPreviews).qsort (fun a b => a.key < b.key)
  let htmlEntries := (traversalHtml ++ leanCodeHtml ++ citationHtml).qsort (fun a b => a.key < b.key)
  pure {
    manifest := { previews }
    htmlCache := {
      entries := htmlEntries
      hoverDocs := HtmlCache.HoverDoc.ofDedup hoverState.dedup
    }
  }

private def parseRenderConfigOptions (config : RenderConfig := {}) :
    List String → ReaderT ExtensionImpls IO RenderConfig
  | ("--output"::dir::more) => parseRenderConfigOptions { config with destination := dir } more
  | ("--depth"::n::more) => parseRenderConfigOptions { config with htmlDepth := n.toNat! } more

  | ("--with-tex"::more) => parseRenderConfigOptions { config with emitTeX := true } more
  | ("--without-tex"::more) => parseRenderConfigOptions { config with emitTeX := false } more

  | ("--with-html-single"::more) => parseRenderConfigOptions { config with emitHtmlSingle := .immediately } more
  | ("--delay-html-single"::more) =>
    match Verso.CLI.requireFilename "--delay-html-single" more with
    | .ok f more' _ => parseRenderConfigOptions { config with emitHtmlSingle := .delay f } more'
    | .error e => throw (↑ e)
  | ("--resume-html-single"::more) =>
    match Verso.CLI.requireFilename "--resume-html-single" more with
    | .ok f more' _ => parseRenderConfigOptions { config with emitHtmlSingle := .resumeFrom f } more'
    | .error e => throw (↑ e)
  | ("--without-html-single"::more) => parseRenderConfigOptions { config with emitHtmlSingle := .no } more

  | ("--with-html-multi"::more) => parseRenderConfigOptions { config with emitHtmlMulti := .immediately } more
  | ("--delay-html-multi"::more) =>
    match Verso.CLI.requireFilename "--delay-html-multi" more with
    | .ok f more' _ => parseRenderConfigOptions { config with emitHtmlMulti := .delay f } more'
    | .error e => throw (↑ e)
  | ("--resume-html-multi"::more) =>
    match Verso.CLI.requireFilename "--resume-html-multi" more with
    | .ok f more' _ => parseRenderConfigOptions { config with emitHtmlMulti := .resumeFrom f } more'
    | .error e => throw (↑ e)
  | ("--without-html-multi"::more) => parseRenderConfigOptions { config with emitHtmlMulti := .no } more

  | ("--with-word-count"::more) =>
    match Verso.CLI.requireFilename "--with-word-count" more with
    | .ok file more' _ => parseRenderConfigOptions { config with wordCount := some file } more'
    | .error e => throw (↑ e)
  | ("--without-word-count"::more) => parseRenderConfigOptions { config with wordCount := none } more
  | ("--draft"::more) => parseRenderConfigOptions { config with draft := true } more
  | ("--verbose"::more) => parseRenderConfigOptions { config with verbose := true } more
  | ("--remote-config"::more) =>
    match Verso.CLI.requireFilename "--remote-config" more with
    | .ok file more' _ => parseRenderConfigOptions { config with remoteConfigFile := some file } more'
    | .error e => throw (↑ e)
  | (other :: _) => throw (↑ s!"Unknown option {other}")
  | [] => pure config

private def dumpManifest
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {}) : IO UInt32 := do
  let errorCount : IO.Ref Nat ← IO.mkRef 0
  let logError msg := do
    errorCount.modify (· + 1)
    IO.eprintln msg
  let cfg ← ReaderT.run (parseRenderConfigOptions config options) extensionImpls
  let (_text, traverseState) ← ReaderT.run (Verso.Genre.Manual.traverseHtmlMulti logError cfg text) extensionImpls
  let files ← buildPreviewDataFiles extensionImpls logError traverseState
  IO.println <| jsonPretty <| toJson files.manifest
  if (← errorCount.get) == 0 then pure 0 else pure 1

private def dumpHtmlCache
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {}) : IO UInt32 := do
  let errorCount : IO.Ref Nat ← IO.mkRef 0
  let logError msg := do
    errorCount.modify (· + 1)
    IO.eprintln msg
  let cfg ← ReaderT.run (parseRenderConfigOptions config options) extensionImpls
  let (_text, traverseState) ← ReaderT.run (Verso.Genre.Manual.traverseHtmlMulti logError cfg text) extensionImpls
  let files ← buildPreviewDataFiles extensionImpls logError traverseState
  IO.println <| jsonPretty <| toJson files.htmlCache
  if (← errorCount.get) == 0 then pure 0 else pure 1

private def readJsonFileOrEmptyObject (path : System.FilePath) : IO Json := do
  if !(← path.pathExists) then
    pure <| Json.mkObj []
  else
    match Json.parse (← IO.FS.readFile path) with
    | .ok json => pure json
    | .error err => throw <| IO.userError s!"could not parse JSON file {path}: {err}"

private def mergeHtmlCacheHoverDocsIntoVersoDocs
    (docsPath : System.FilePath) (htmlCache : HtmlCache.File) : IO Unit := do
  if htmlCache.hoverDocs.isEmpty then
    return
  let docs ← readJsonFileOrEmptyObject docsPath
  IO.FS.writeFile docsPath (toString <| docs.mergeObj htmlCache.hoverDocsJson)

/--
Emit the canonical Blueprint manifest and rendered HTML cache files.

The manifest contains semantic data keyed by `PreviewCache`, Lean preview key,
or citation key. The HTML cache contains the corresponding rendered HTML
fragments for browser hover previews and file-mode consumers such as slides.
-/
def emitBlueprintPreviewData (extensionImpls : ExtensionImpls) : ExtraStep := fun mode logError cfg state _text => do
  let files ← buildPreviewDataFiles extensionImpls logError state
  let outDir := outDirForMode cfg mode
  let dataDir := outDir / "-verso-data"
  IO.FS.createDirAll dataDir
  IO.FS.writeFile (dataDir / manifestFilename) (toJson files.manifest).compress
  IO.FS.writeFile (dataDir / htmlCacheFilename) (toJson files.htmlCache).compress
  mergeHtmlCacheHoverDocsIntoVersoDocs (outDir / "-verso-docs.json") files.htmlCache
  emitPublicXref mode logError cfg state

def dumpSchemaFlag : String := "--dump-schema"
def dumpManifestFlag : String := "--dump-manifest"
def dumpHtmlCacheFlag : String := "--dump-html-cache"
def helpFlag : String := "--help"

def helpText : String := String.intercalate "\n" [
  "Blueprint manifest/cache options:",
  s!"  {dumpSchemaFlag}       Print the semantic manifest JSON Schema and exit.",
  s!"  {dumpManifestFlag}     Print the generated semantic manifest JSON and exit.",
  s!"  {dumpHtmlCacheFlag}  Print the generated rendered HTML cache JSON and exit.",
  s!"  {helpFlag}              Show this help text and exit.",
  "",
  "Standard manual rendering options:",
  "  --output <dir>",
  "  --depth <n>",
  "  --with-tex | --without-tex",
  "  --with-html-single | --delay-html-single <file> | --resume-html-single <file> | --without-html-single",
  "  --with-html-multi | --delay-html-multi <file> | --resume-html-multi <file> | --without-html-multi",
  "  --with-word-count <file> | --without-word-count",
  "  --draft",
  "  --verbose",
  "  --remote-config <file>"
]

private def stripFlag (flag : String) (args : List String) : List String :=
  args.filter (· != flag)

def handleDumpSchemaFlag (args : List String) : IO (Option UInt32 × List String) := do
  if args.contains dumpSchemaFlag then
    IO.println schemaString
    pure (some 0, stripFlag dumpSchemaFlag args)
  else
    pure (none, args)

def handleCliFlags
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {}) : IO (Option UInt32 × List String) := do
  if options.contains helpFlag then
    IO.println helpText
    pure (some 0, stripFlag helpFlag options)
  else if options.contains dumpManifestFlag then
    let options := stripFlag dumpManifestFlag options
    let code ← dumpManifest text options extensionImpls config
    pure (some code, options)
  else if options.contains dumpHtmlCacheFlag then
    let options := stripFlag dumpHtmlCacheFlag options
    let code ← dumpHtmlCache text options extensionImpls config
    pure (some code, options)
  else
    handleDumpSchemaFlag options

private abbrev HtmlTraverse :=
  (String → IO Unit) → RenderConfig → Part Manual → ReaderT ExtensionImpls IO (Part Manual × TraverseState)

private abbrev HtmlEmitter :=
  (String → IO Unit) → RenderConfig → Part Manual → TraverseState → ReaderT ExtensionImpls IO Unit

private def emitBlueprintHtml
    (extraSteps : List ExtraStep)
    (how : EmitHtml)
    (mode : Mode)
    (logError : String → IO Unit)
    (cfg : RenderConfig)
    (text : Part Manual)
    (traverse : HtmlTraverse)
    (emit : HtmlEmitter) :
    ReaderT ExtensionImpls IO Unit := do
  let outDir := outputDirNameForMode mode
  match how with
  | .no => pure ()
  | .immediately =>
      if cfg.verbose then
        IO.println s!"Saving {match mode with | .single => "single" | .multi => "multi"}-page HTML"
      let (text', traverseState) ← traverse logError cfg text
      let traverseState := patchBlueprintTraverseState traverseState
      emitXrefsJson (cfg.destination / outDir) traverseState
      emit logError cfg text' traverseState
      for step in extraSteps do
        step mode logError cfg.toConfig traverseState text'
  | .delay f =>
      let (text', traverseState) ← traverse logError cfg text
      let traverseState := patchBlueprintTraverseState traverseState
      emitXrefsJson (cfg.destination / outDir) traverseState
      SavedState.mk text' traverseState |>.save f
  | .resumeFrom f =>
      let { text, traverseState } ← SavedState.load f
      let traverseState := patchBlueprintTraverseState traverseState
      emit logError cfg text traverseState
      for step in extraSteps do
        step mode logError cfg.toConfig traverseState text

def blueprintMain (text : Part Manual)
    (extensionImpls : ExtensionImpls := by exact extension_impls%)
    (options : List String)
    (config : RenderConfig := {})
    (extraSteps : List ExtraStep := []) : IO UInt32 :=
  ReaderT.run go extensionImpls
where
  go : ReaderT ExtensionImpls IO UInt32 := do
    let errorCount : IO.Ref Nat ← IO.mkRef 0
    let logError msg := do
      errorCount.modify (· + 1)
      IO.eprintln msg
    let cfg ← parseRenderConfigOptions (withBuildMetadataAssets config) options
    let buildMetadata ← readBuildMetadata
    let extraSteps := emitBuildMetadata buildMetadata :: extraSteps

    if cfg.emitTeX then
      if cfg.verbose then
        IO.println "Saving TeX"
      emitTeX logError cfg.toConfig text

    emitBlueprintHtml extraSteps cfg.emitHtmlSingle .single logError cfg text
      traverseHtmlSingle emitHtmlSingle
    emitBlueprintHtml extraSteps cfg.emitHtmlMulti .multi logError cfg text
      traverseHtmlMulti emitHtmlMulti

    if let some wcFile := cfg.wordCount then
      if cfg.verbose then
        IO.println s!"Saving word counts to {wcFile}"
      wordCount wcFile logError cfg.toConfig text

    match ← errorCount.get with
    | 0 => return 0
    | 1 =>
        IO.eprintln "An error was encountered!"
        return 1
    | n =>
        IO.eprintln s!"{n} errors were encountered!"
        return 1

def blueprintMainWithPreviewData
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {})
    (extraSteps : List ExtraStep := []) : IO UInt32 := do
  let config := withBlueprintAssets config
  let (dumped?, options) ← handleCliFlags text options extensionImpls config
  if let some code := dumped? then
    return code
  blueprintMain text (extensionImpls := extensionImpls) (options := options) (config := config)
    (extraSteps := emitBlueprintPreviewData extensionImpls :: extraSteps)

def manualMainWithPreviewData
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {})
    (extraSteps : List ExtraStep := []) : IO UInt32 :=
  blueprintMainWithPreviewData text options extensionImpls config extraSteps

-- Compatibility for reference generators pinned before preview data was renamed.
def manualMainWithSharedPreviewManifest
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {})
    (extraSteps : List ExtraStep := []) : IO UInt32 :=
  manualMainWithPreviewData text options extensionImpls config extraSteps

end Informal.PreviewManifest
