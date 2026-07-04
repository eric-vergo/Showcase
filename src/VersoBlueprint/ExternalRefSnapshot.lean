/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import SubVerso.Highlighting
import VersoBlueprint.Data
import VersoBlueprint.ProvedStatus
import VersoBlueprint.ExternalDeclRender
import VersoBlueprint.Git
import VersoBlueprint.RuntimeCache

namespace Informal

open Lean

/--
Template used to build source links for external declarations.
Supported placeholders are: path, relpath, module, line, column, endLine, endColumn.

Empty template uses automatic GitHub source link generation when the source file
belongs to a Git checkout with a GitHub `origin` remote.
-/
register_option verso.blueprint.externalCode.sourceLinkTemplate : String := {
  defValue := ""
  descr := "Template for external declaration source links ({path},{relpath},{module},{line},{column},{endLine},{endColumn}); empty uses automatic GitHub links when available"
}

private def externalSourceLinkTemplate (opts : Lean.Options) : String :=
  opts.get
    verso.blueprint.externalCode.sourceLinkTemplate.name
    verso.blueprint.externalCode.sourceLinkTemplate.defValue

private def workspaceRelativeSourcePath? (workspaceRoot sourcePath : System.FilePath) : Option String :=
  let root := workspaceRoot.toString
  let sep := System.FilePath.pathSeparator.toString
  let rootPrefix := if root.endsWith sep then root else root ++ sep
  let sourcePathText := sourcePath.toString
  if sourcePathText.startsWith rootPrefix then
    some (sourcePathText.drop rootPrefix.length).toString
  else
    none

private def instantiateSourceLinkTemplate (template : String) (vars : Array (String × String)) : String :=
  vars.foldl (init := template) fun acc kv =>
    acc.replace ("{" ++ kv.1 ++ "}") kv.2

private def sourceLineFragment? (range? : Option Lean.DeclarationRange) : Option String := do
  let range ← range?
  let startLine := range.pos.line
  let endLine := range.endPos.line
  if startLine == 0 then
    none
  else if endLine > startLine then
    some s!"#L{startLine}-L{endLine}"
  else
    some s!"#L{startLine}"

private def absoluteSourcePath (workspaceRoot sourcePath : System.FilePath) : System.FilePath :=
  if sourcePath.isAbsolute then
    sourcePath
  else
    workspaceRoot / sourcePath.toString

private def normalizeSourcePath? (workspaceRoot sourcePath : System.FilePath) :
    IO (Option System.FilePath) := do
  let sourcePath := absoluteSourcePath workspaceRoot sourcePath
  try
    some <$> IO.FS.realPath sourcePath
  catch _ =>
    pure (some sourcePath)

private def gitHubSourceHref? (workspaceRoot sourcePath : System.FilePath)
    (range? : Option Lean.DeclarationRange) : IO (Option String) := do
  let sourcePath := absoluteSourcePath workspaceRoot sourcePath
  let sourceDir := sourcePath.parent.getD sourcePath
  let some gitRoot ← RuntimeCache.cachedGitRoot? sourceDir (Git.toplevelAt? sourceDir)
    | return none
  let some repoInfo ← RuntimeCache.cachedGitRepoInfo? gitRoot (Git.repositoryInfoAtRoot? gitRoot)
    | return none
  let relPath := (workspaceRelativeSourcePath? repoInfo.root sourcePath).getD sourcePath.toString
  let fragment := sourceLineFragment? range? |>.getD ""
  pure <| some s!"{repoInfo.githubUrl}/blob/{repoInfo.commit}/{relPath}{fragment}"

private def sourceLinkHref? (opts : Lean.Options) (workspaceRoot : System.FilePath)
    (moduleName? : Option Lean.Name) (sourcePath? : Option System.FilePath)
    (range? : Option Lean.DeclarationRange) : IO (Option String) := do
  let template := (externalSourceLinkTemplate opts).trimAscii.toString
  if template.isEmpty then
    match sourcePath? with
    | some sourcePath => gitHubSourceHref? workspaceRoot sourcePath range?
    | none => pure none
  else
    match sourcePath? with
    | none => pure none
    | some sourcePath =>
      let relPath := (workspaceRelativeSourcePath? workspaceRoot sourcePath).getD sourcePath.toString
      let line := (range?.map (fun r => toString r.pos.line)).getD ""
      let column := (range?.map (fun r => toString r.pos.column)).getD ""
      let endLine := (range?.map (fun r => toString r.endPos.line)).getD ""
      let endColumn := (range?.map (fun r => toString r.endPos.column)).getD ""
      let href :=
        instantiateSourceLinkTemplate template #[
          ("path", sourcePath.toString),
          ("relpath", relPath),
          ("module", (moduleName?.map toString).getD ""),
          ("line", line),
          ("column", column),
          ("endLine", endLine),
          ("endColumn", endColumn)
        ]
      let href := href.trimAscii.toString
      if href.isEmpty then pure none else pure (some href)

private def moduleSourcePathText (moduleName : Lean.Name) : String :=
  (toString moduleName).replace "." "/" ++ ".lean"

private def dropFirstPathComponent? (pathText : String) : Option String :=
  match pathText.splitOn "/" with
  | _pkg :: next :: rest => some (String.intercalate "/" (next :: rest))
  | _ => none

private def dropLakePackagesPrefix? (pathText : String) : Option String :=
  match pathText.splitOn ".lake/packages/" with
  | _ :: rest :: _ => dropFirstPathComponent? rest
  | _ => none

def elegantSourcePath (workspaceRoot : System.FilePath)
    (moduleName? : Option Lean.Name) (sourcePath : System.FilePath) : String :=
  let relPath := (workspaceRelativeSourcePath? workspaceRoot sourcePath).getD sourcePath.toString
  match dropLakePackagesPrefix? relPath with
  | some path => path
  | none =>
    match moduleName? with
    | some moduleName =>
      let modulePath := moduleSourcePathText moduleName
      if relPath.endsWith modulePath then
        modulePath
      else
        modulePath
    | none => relPath

private def externalDeclHeaderSource?
    (workspaceRoot : System.FilePath) (moduleName? : Option Lean.Name)
    (sourcePath? : Option System.FilePath) (sourceHref? : Option String) :
    Option ExternalDeclHeaderSource := do
  match sourcePath? with
  | some sourcePath =>
    some {
      text := elegantSourcePath workspaceRoot moduleName? sourcePath
      href? := sourceHref?
    }
  | none =>
    let moduleName ← moduleName?
    some {
      text := moduleSourcePathText moduleName
      href? := sourceHref?
    }

private def moduleNameForDecl? (env : Lean.Environment) (decl : Lean.Name) : Option Lean.Name := do
  match env.getModuleIdxFor? decl with
  | some moduleIdx => env.header.moduleNames[moduleIdx.toNat]?
  | none =>
    if env.mainModule.isAnonymous then
      none
    else
      some env.mainModule

private def currentSourcePath? (workspaceRoot : System.FilePath) : Lean.CoreM (Option System.FilePath) := do
  let fileName ← Lean.getFileName
  if fileName.isEmpty || fileName.startsWith "<" then
    pure none
  else
    liftM <| normalizeSourcePath? workspaceRoot (System.FilePath.mk fileName)

private def existingSourcePath? (workspaceRoot path : System.FilePath) :
    IO (Option System.FilePath) := do
  let path := absoluteSourcePath workspaceRoot path
  if ← path.pathExists then
    normalizeSourcePath? workspaceRoot path
  else
    pure none

/-- Scan the immediate subdirectories of `dir` for `<child>/<modulePath>`. -/
private def scanChildDirsForModule (workspaceRoot dir : System.FilePath)
    (modulePath : String) : IO (Option System.FilePath) := do
  try
    for entry in ← dir.readDir do
      if ← entry.path.isDir then
        if let some path ← existingSourcePath? workspaceRoot (entry.path / modulePath) then
          return some path
    pure none
  catch _ =>
    pure none

private def workspaceModuleSourcePath? (workspaceRoot : System.FilePath)
    (moduleName : Lean.Name) : IO (Option System.FilePath) := do
  let modulePath := moduleSourcePathText moduleName
  if let some path ← existingSourcePath? workspaceRoot (System.FilePath.mk modulePath) then
    return some path
  -- First the consumer's own subdirectories.
  if let some path ← scanChildDirsForModule workspaceRoot workspaceRoot modulePath then
    return some path
  -- Then sibling packages one level up (the workspace / monorepo root). A
  -- `(lean := …)` decl frequently lives in a *separate* package whose source dir
  -- is absent from the build-time source search path (only the consumer's own
  -- source dir is on it during elaboration), so the decl's `.lean` source — and
  -- hence its captured proof/value body — is reachable only by looking outward.
  match workspaceRoot.parent with
  | some parent => scanChildDirsForModule workspaceRoot parent modulePath
  | none => pure none

def sourcePathForModule? (workspaceRoot : System.FilePath)
    (moduleName : Lean.Name) : Lean.CoreM (Option System.FilePath) := do
  RuntimeCache.cachedModuleSourcePath? workspaceRoot moduleName do
    let srcSearchPath ← Lean.getSrcSearchPath
    match ← srcSearchPath.findModuleWithExt "lean" moduleName with
    | some path =>
      liftM <| normalizeSourcePath? workspaceRoot path
    | none =>
      if moduleName == (← getEnv).mainModule then
        currentSourcePath? workspaceRoot
      else
        liftM <| workspaceModuleSourcePath? workspaceRoot moduleName

private def workspacePathPrefix (workspaceRoot : System.FilePath) : String :=
  let root := workspaceRoot.toString
  let sep := System.FilePath.pathSeparator.toString
  if root.endsWith sep then root else root ++ sep

private def isPathInWorkspace (workspaceRoot sourcePath : System.FilePath) : Bool :=
  let root := workspaceRoot.toString
  let rootPrefix := workspacePathPrefix workspaceRoot
  let src := sourcePath.toString
  src == root || src.startsWith rootPrefix

private def mkProvenance (workspaceRoot : System.FilePath)
    (moduleName? : Option Lean.Name) (sourcePath? : Option System.FilePath) : Data.ExternalDeclProvenance :=
  match moduleName? with
  | none => .unknown
  | some moduleName =>
    match sourcePath? with
    | some sourcePath =>
      if isPathInWorkspace workspaceRoot sourcePath then
        .inWorkspace moduleName sourcePath.toString
      else
        .outWorkspace moduleName (some sourcePath.toString)
    | none =>
      .outWorkspace moduleName none

private def externalDeclStatusBadge (status : Data.ProvedStatus) : ExternalDeclHeaderBadge :=
  let view := status.presentation
  { className := view.externalDeclClass, text := view.externalHeaderText }

/--
Slice the proof/value source out of a full declaration source snippet: return the
text after the first top-level `:=` (the tactic block or defining term), trimmed.

The scan tracks bracket nesting (`()`, `[]`, `{}`, `⟨⟩`) and skips string literals
and `--` / `/- -/` comments so a `:=` inside a binder default, an anonymous
constructor, or a comment in the signature does not get mistaken for the body
separator. Returns `none` when there is no top-level `:=` (e.g. `example`s the
range does not cover, or a declaration with no body).
-/
private def sliceProofSource (declSrc : String) : Option String := Id.run do
  let cs := declSrc.data.toArray
  let n := cs.size
  let mut depth : Nat := 0
  let mut i : Nat := 0
  let mut inString := false
  let mut inLineComment := false
  let mut blockDepth : Nat := 0
  while i < n do
    let c := cs[i]!
    let next? := cs[i + 1]?
    if inLineComment then
      if c == '\n' then inLineComment := false
      i := i + 1
    else if blockDepth > 0 then
      if c == '-' && next? == some '/' then blockDepth := blockDepth - 1; i := i + 2
      else if c == '/' && next? == some '-' then blockDepth := blockDepth + 1; i := i + 2
      else i := i + 1
    else if inString then
      if c == '\\' then i := i + 2
      else if c == '"' then inString := false; i := i + 1
      else i := i + 1
    else if c == '"' then inString := true; i := i + 1
    else if c == '-' && next? == some '-' then inLineComment := true; i := i + 2
    else if c == '/' && next? == some '-' then blockDepth := 1; i := i + 2
    else if depth == 0 && c == ':' && next? == some '=' then
      let tail := (String.ofList (cs.toList.drop (i + 2))).trim
      return (if tail.isEmpty then none else some tail)
    else if c == '(' || c == '[' || c == '{' || c == '⟨' then depth := depth + 1; i := i + 1
    else if c == ')' || c == ']' || c == '}' || c == '⟩' then
      depth := (if depth == 0 then 0 else depth - 1); i := i + 1
    else i := i + 1
  return none

/--
Read the proof/value source of one declaration from its source file and range.

Reads the file, extracts the declaration substring spanning `range`, and slices
off the body after the top-level `:=` (see `sliceProofSource`). Degrades to `none`
on any IO or lookup failure so snapshotting never fails on a missing/unreadable
source file.
-/
private def captureProofSource?
    (sourcePath? : Option System.FilePath) (range? : Option Lean.DeclarationRange) :
    IO (Option String) := do
  match sourcePath?, range? with
  | some sourcePath, some range =>
    try
      let content ← IO.FS.readFile sourcePath
      let fileMap := Lean.FileMap.ofString content
      let startPos := fileMap.ofPosition range.pos
      let endPos := fileMap.ofPosition range.endPos
      let declSrc := String.Pos.Raw.extract content startPos endPos
      return sliceProofSource declSrc
    catch _ =>
      return none
  | _, _ => return none

open SubVerso.Highlighting in
/--
Syntactically highlight a captured proof/value source string, returning a
self-contained highlighted-code HTML fragment (token spans themed by the shared
`--verso-code-*` CSS in both light and dark).

Full semantic highlighting (const/type coloring, hovers) needs the proof's
elaboration info trees, which are not persisted in `.olean`s and so are
unavailable at generation time for imported declarations. This instead parses the
captured source as a Lean `term` and runs SubVerso's highlighter with *no* info
trees, over a file map built from the source text alone, yielding purely
*syntactic* classification (keywords, literals, comments, punctuation) — a large
legibility gain over flat monospace text.

Degrades to `none` (the caller falls back to escaping the raw source) on any parse
or highlight failure, so snapshotting never fails on an odd proof body.
-/
def highlightProofSourceHtml? (proofSrc : String) : Lean.CoreM (Option String) := do
  let env ← getEnv
  match Lean.Parser.runParserCategory env `term proofSrc "<proof>" with
  | .error _ => return none
  | .ok stx =>
    try
      let hl ←
        withTheReader Lean.Core.Context
            (fun ctx => { ctx with fileMap := Lean.FileMap.ofString proofSrc }) <|
          (highlight stx #[] PersistentArray.empty).run'.run'
      return some (renderHighlightedSelfContainedHtml hl)
    catch _ =>
      return none

/--
Build a full snapshot for one external declaration reference using the environment
available at elaboration/registration time.
-/
def externalRefSnapshot (opts : Lean.Options) (workspaceRoot : System.FilePath)
    (ref : Data.ExternalRef) : Lean.CoreM Data.ExternalRef := do
  let env ← getEnv
  let canonical := ref.canonical.eraseMacroScopes
  match env.find? canonical with
  | none =>
    pure {
      ref with
      canonical
      present := false
      provedStatus := .missing
      render := .error (.moduleUnavailable canonical)
    }
  | some cinfo =>
    let nodeKind ←
      match Informal.Data.ConstantInfo.blueprintNodeKind? cinfo with
      | some nodeKind => pure nodeKind
      | none =>
        match cinfo with
        | .axiomInfo _ | .opaqueInfo _ =>
          pure ref.kind
        | _ =>
          throwError m!"Unsupported external Lean reference '{ref.written}' (canonical '{canonical}') with kind '{Informal.Data.ConstantInfo.blueprintKindText cinfo}'. Only definition-like declarations, theorems, and axiom-like placeholders are currently supported."
    let ref : Data.ExternalRef := {
      ref with
      canonical
      present := true
      provedStatus := Informal.Data.ConstantInfo.blueprintProvedStatus cinfo (allowOpaque := true)
      kind := nodeKind
    }
    let ranges? ← findDeclarationRanges? canonical
    let moduleName? := moduleNameForDecl? env canonical
    let sourcePath? ←
      match moduleName? with
      | some moduleName => sourcePathForModule? workspaceRoot moduleName
      | none => pure none
    let provenance := mkProvenance workspaceRoot moduleName? sourcePath?
    let selectionRange? := ranges?.map (fun r => r.selectionRange)
    let sourceHref? ←
      liftM <| sourceLinkHref? opts workspaceRoot moduleName? sourcePath? (ranges?.map (fun r => r.range))
    let headerSource? := externalDeclHeaderSource? workspaceRoot moduleName? sourcePath? sourceHref?
    let renderResult ←
      (renderDeclHtmlDirectFromInfoE canonical cinfo
        (headerBadge? := some (externalDeclStatusBadge ref.provedStatus))
        (headerSource? := headerSource?)).run'
    let render : Data.ExternalDeclRender :=
      match renderResult with
      | .ok html => .ok html
      | .error err => .error err
    let proofSource? ← liftM <| captureProofSource? sourcePath? (ranges?.map (fun r => r.range))
    let proofHtml? ←
      match proofSource? with
      | some src => highlightProofSourceHtml? src
      | none => pure none
    pure {
      ref with
      provenance
      range? := ranges?.map (fun r => r.range)
      selectionRange?
      sourceHref?
      render
      proofSource?
      proofHtml?
    }

def workspaceRoot : Lean.CoreM System.FilePath := do
  let cwd ← liftM <| IO.currentDir
  liftM <| IO.FS.realPath cwd

def externalRefSnapshotAtCurrentDir (opts : Lean.Options)
    (ref : Data.ExternalRef) : Lean.CoreM Data.ExternalRef := do
  externalRefSnapshot opts (← workspaceRoot) ref

end Informal
