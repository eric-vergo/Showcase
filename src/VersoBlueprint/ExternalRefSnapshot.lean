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

/--
Resolve the source link for a declaration from its module/path/range: the
consumer's `verso.blueprint.externalCode.sourceLinkTemplate` when configured,
else an automatic GitHub blob URL when the source belongs to a Git checkout with
a GitHub `origin` remote; `none` when underivable. Shared by the external-ref
snapshot (`Data.ExternalRef.sourceHref?`) and the declaration registry
(`DeclRegistry.Entry.sourceHref?`), so both build identical URLs.
-/
def sourceLinkHref? (opts : Lean.Options) (workspaceRoot : System.FilePath)
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
  -- Then one level up (the workspace / monorepo root). A `(lean := …)` decl
  -- frequently lives in a *separate* package whose source dir is absent from the
  -- build-time source search path (only the consumer's own source dir is on it
  -- during elaboration), so the decl's `.lean` source — and hence its captured
  -- proof/value body — is reachable only by looking outward. The parent may itself
  -- be a package root (a consumer nested inside the formalization repo, e.g.
  -- `<repo>/site` consuming `<repo>`'s modules), or the target may live in one of
  -- the parent's sibling subdirectories.
  match workspaceRoot.parent with
  | some parent =>
    if let some path ← existingSourcePath? workspaceRoot (parent / modulePath) then
      return some path
    scanChildDirsForModule workspaceRoot parent modulePath
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
Slice the proof/value source of one declaration out of its file's full content
and range (the pure core of `captureProofSource?`, exposed so callers that
already hold the file content — e.g. the declaration registry's per-module
file-content cache — avoid re-reading the file per declaration). `none` when the
extracted declaration has no top-level `:=` body.
-/
def proofSourceFromContent? (content : String) (range : Lean.DeclarationRange) :
    Option String :=
  let fileMap := Lean.FileMap.ofString content
  let startPos := fileMap.ofPosition range.pos
  let endPos := fileMap.ofPosition range.endPos
  sliceProofSource (String.Pos.Raw.extract content startPos endPos)

/--
Read the proof/value source of one declaration from its source file and range.

Reads the file, extracts the declaration substring spanning `range`, and slices
off the body after the top-level `:=` (see `sliceProofSource`). Degrades to `none`
on any IO or lookup failure so snapshotting never fails on a missing/unreadable
source file.
-/
def captureProofSource?
    (sourcePath? : Option System.FilePath) (range? : Option Lean.DeclarationRange) :
    IO (Option String) := do
  match sourcePath?, range? with
  | some sourcePath, some range =>
    try
      let content ← IO.FS.readFile sourcePath
      return proofSourceFromContent? content range
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

open SubVerso.Highlighting in
/--
Syntactically highlight a whole Lean *module* source string (the module analogue
of `highlightProofSourceHtml?`), returning a self-contained highlighted-code HTML
fragment (token spans themed by the shared `--verso-code-*` CSS in both light and
dark; wrap in `<code class="hl lean">`).

Because a module begins with a header (`module`/`prelude`/`import` lines) that the
`term`/command parser categories do not accept, we first `parseHeader`, then loop
`parseCommand` to collect the header plus every top-level command, and highlight
each with SubVerso's `highlightIncludingUnparsed` fed **empty** info trees and an
**empty** message log — purely *syntactic* classification (keywords, literals,
comments, punctuation), no elaboration. Any region a command fails to parse is
filled verbatim from the source file map, so an unparsable construct degrades to
plain source text within an otherwise-highlighted module rather than failing.

Degrades to `none` (the caller falls back to escaping the raw source) on any
exception, on empty input, or if the command loop fails to terminate within a
generous iteration bound (an anti-hang guard for pathological inputs).
-/
def highlightModuleSourceHtml? (moduleSrc : String) : Lean.CoreM (Option String) := do
  if moduleSrc.trimAscii.isEmpty then return none
  let env ← getEnv
  let fileMap := Lean.FileMap.ofString moduleSrc
  try
    let ictx := Lean.Parser.mkInputContext moduleSrc "<challenge>"
    let (headerStx, pstate0, msgs0) ← Lean.Parser.parseHeader ictx
    let pmctx : Lean.Parser.ParserModuleContext :=
      { env, options := {}, currNamespace := .anonymous, openDecls := [] }
    -- Collect the header (only when it carries a real token — a trivia-only header has
    -- no position) plus every top-level command.
    let mut stxs : Array Lean.Syntax := if headerStx.raw.getPos?.isSome then #[headerStx] else #[]
    let mut pstate := pstate0
    let mut msgs := msgs0
    let mut guard : Nat := 0
    repeat
      guard := guard + 1
      if guard > 20000 then return none
      let (cmd, pstate', msgs') := Lean.Parser.parseCommand ictx pmctx pstate msgs
      stxs := stxs.push cmd
      pstate := pstate'
      msgs := msgs'
      if Lean.Parser.isTerminalCommand cmd then break
    -- Highlight the whole module in a SINGLE pass over one null node wrapping every
    -- command. We deliberately let `startPos?` default to the node's own position
    -- rather than forcing 0: forcing 0 makes the highlighter both *fill* `[0, firstToken]`
    -- and render that same span again as the first token's leading trivia, duplicating a
    -- leading block comment. Inter-command comments/whitespace are still filled because
    -- they lie between child token spans.
    let allStx := Lean.mkNullNode stxs
    let act : Lean.Elab.TermElabM Highlighted :=
      highlightIncludingUnparsed allStx #[] PersistentArray.empty
    let hl ←
      withTheReader Lean.Core.Context (fun ctx => { ctx with fileMap }) <|
        act.run'.run'
    return some (renderHighlightedSelfContainedHtml hl)
  catch _ =>
    return none

/-- Whether a declaration's source region is a plain `binders : type` signature
that can be re-elaborated as an `opaque` for the verbatim-source highlight.
`inductive`/`structure`/constructor/recursor/quotient declarations are excluded —
their source is not a signature and their card is rendered from `DeclType`. -/
def isStatementSignatureCandidate (cinfo : Lean.ConstantInfo) : Bool :=
  match cinfo with
  | .defnInfo _ | .thmInfo _ | .opaqueInfo _ | .axiomInfo _ => true
  | _ => false

/-- Assemble a `declSig` (binders + `: type`) syntax node from a parsed
`declSig`/`optDeclSig`, reusing the original binder and type-ascription child
nodes so their *source positions* are preserved (the semantic highlighter matches
info-tree entries against these positions). `none` when there is no explicit type
ascription — e.g. a `def` whose type is inferred — since there is then nothing to
elaborate into a signature. -/
private def statementDeclSig? (sig : Lean.Syntax) : Option Lean.Syntax :=
  let binders := sig[0]
  let typeSpec? : Option Lean.Syntax :=
    if sig.getKind == ``Lean.Parser.Command.declSig then some sig[1]
    else if sig.getKind == ``Lean.Parser.Command.optDeclSig && sig[1].getNumArgs > 0 then
      some sig[1][0]
    else none
  typeSpec?.map fun ts =>
    Lean.Syntax.node .none ``Lean.Parser.Command.declSig #[binders, ts]

/-- The namespace the declaration was written in: the full (de-mangled) name minus
the name components the author actually wrote after the `theorem`/`def` keyword.
E.g. full `A362583.exists_norm_LFunction_lt_near_half` written as
`exists_norm_LFunction_lt_near_half` inside `namespace A362583` yields `A362583`;
a fully-qualified top-level `theorem A362583.foo` yields `Name.anonymous`. `none`
when the written name is not a suffix of the full name (unexpected — caller keeps
the anonymous namespace). -/
private def declWrittenNamespace? (fullName writtenName : Lean.Name) : Option Lean.Name :=
  go fullName writtenName
where
  go : Lean.Name → Lean.Name → Option Lean.Name
    | f, .anonymous => some f
    | .str f' s', .str w' s => if s' == s then go f' w' else none
    | .num f' n', .num w' n => if n' == n then go f' w' else none
    | _, _ => none

/--
Run a *nested* re-elaboration without its heartbeat spend leaking into the
enclosing command's budget.

Lean's heartbeat counter is thread-local and monotonically increasing; a budget
check is `getNumHeartbeats - ctx.initHeartbeats > max`. Every nested
re-elaboration we run (each with its own fresh `initHeartbeats`, taken inside
`Command.runCore` at each `CoreM` lift) increments that same counter, but the
ENCLOSING command's `initHeartbeats` is fixed — so after many nested runs (e.g.
~150 Mathlib-heavy proofs inside one `{blueprint_graph}` command) the outer
command's next `whnf` sees the accumulated delta and dies with a deterministic
timeout, far away from any of our `try/catch`es. `withCurrHeartbeats` cannot fix
this: it re-baselines only the *wrapped* computation, and the reader context
reverts afterwards, leaving the outer continuation with its stale baseline.

Instead we snapshot the counter and *restore* it after the nested run
(`IO.setNumHeartbeats`, success or failure), so the nested spend is invisible to
the caller's budget while each nested run keeps its own cap (its baseline is read
fresh from the counter we restored).
-/
private def withRestoredHeartbeats (act : Lean.CoreM α) : Lean.CoreM α := do
  let saved ← IO.getNumHeartbeats
  try
    act
  finally
    IO.setNumHeartbeats saved

open SubVerso.Highlighting Lean Elab in
/-- The `CommandElabM` core of `highlightStatementFromSource?`: re-elaborate the
verbatim statement (as a fresh, clash-free `opaque`, so it never collides with the
real declaration and never needs its proof), then highlight the *original* name +
signature syntax against the resulting info trees. Runs in an isolated command
state supplied by the caller. Returns `none` if elaboration reports any error
(e.g. an identifier that only resolves under the module's `open`s / `variable`s
that are not in scope here), so the caller degrades to the delaborated signature. -/
private def highlightStatementAct (declText : String) (deIndentCol : Nat)
    (declId declSig : Lean.Syntax) :
    Command.CommandElabM (Option SubVerso.Highlighting.Highlighted) := do
  let freshId := mkIdentFrom declId (Lean.Name.mkSimple "_versoBlueprintSourceSig")
  let declIdFresh ← `(Lean.Parser.Command.declId| $freshId:ident)
  let sigT : Lean.TSyntax ``Lean.Parser.Command.declSig := ⟨declSig⟩
  -- `unsafe` avoids an `Inhabited` obligation on the result type; `noncomputable`
  -- because `opaque` has no executable value. The signature is spliced verbatim,
  -- so its source positions survive into the captured info trees.
  let cmd ← `(command| noncomputable unsafe opaque $declIdFresh $sigT)
  let trees ← withoutModifyingEnv do
    Command.elabCommand cmd
    pure (← getInfoState).trees
  if ← Lean.MonadLog.hasErrors then return none
  let hl ← Command.liftTermElabM <|
    withTheReader Lean.Core.Context ({· with fileMap := Lean.FileMap.ofString declText}) do
      let name ← highlight declId #[] trees
      let sigHl ← highlight declSig #[] trees
      pure (SubVerso.Highlighting.Highlighted.seq #[name, sigHl])
  return some (hl.deIndent deIndentCol)

open Lean Elab in
/--
Highlight a declaration's **statement** from its verbatim source text, with full
semantic info (const/type classification and hovers), preserving the author's
exact layout/whitespace.

Unlike the delaborated `Signature.forName` path (which pretty-prints the *type*
and re-lays it out at a fixed width, dropping hovers on tokens the delaborator
never tags), this slices the declaration's source region (`range`), re-parses it,
re-elaborates just the signature as a fresh `opaque` (so no proof is rerun and no
name clashes), and runs SubVerso's highlighter over the **original source syntax**
with the resulting info trees. Every identifier that resolves therefore carries
its hover payload, and the layout is exactly what the author wrote.

The re-elaboration runs inside the declaration's own namespace (derived from
`declName` minus the source-written name — see `declWrittenNamespace?`, with
private names de-mangled first), so sibling declarations referenced by short name
(e.g. `χ` for `A362583.χ` inside `namespace A362583`) resolve exactly as they did
at the original site.

Degrades to `none` — the caller falls back to `Signature.forName` — when the
source has no explicit type ascription, fails to parse, or fails to elaborate in
this context (identifiers relying on the module's `open`s that are not in scope).
-/
def highlightStatementFromSource? (declName : Lean.Name) (content : String)
    (range : Lean.DeclarationRange) :
    Lean.CoreM (Option SubVerso.Highlighting.Highlighted) := do
  let fileMap := Lean.FileMap.ofString content
  let startPos := fileMap.ofPosition range.pos
  let endPos := fileMap.ofPosition range.endPos
  let declText := String.Pos.Raw.extract content startPos endPos
  let env ← getEnv
  let .ok cmdStx := Lean.Parser.runParserCategory env `command declText "<statement>"
    | return none
  let some declId := cmdStx.find? (·.getKind == ``Lean.Parser.Command.declId)
    | return none
  let some sigNode := cmdStx.find? (fun s =>
      s.getKind == ``Lean.Parser.Command.declSig || s.getKind == ``Lean.Parser.Command.optDeclSig)
    | return none
  let some declSig := statementDeclSig? sigNode
    | return none
  -- Enter the namespace the author wrote the declaration in, so short-name
  -- references to namespace siblings resolve. Private names are de-mangled first
  -- (the source is written against the user-facing name).
  let userName := (privateToUserName? declName).getD declName
  let currNamespace :=
    (declWrittenNamespace? userName declId[0].getId).getD Lean.Name.anonymous
  let declFileMap := Lean.FileMap.ofString declText
  let cctx : Lean.Elab.Command.Context :=
    { fileName := "<statement>", fileMap := declFileMap, snap? := none, cancelTk? := none }
  let cmdState : Lean.Elab.Command.State :=
    { env, maxRecDepth := (← readThe Lean.Core.Context).maxRecDepth,
      scopes := [{ header := "", currNamespace }] }
  withRestoredHeartbeats do
    try
      match (← liftM <| EIO.toIO' <|
          (highlightStatementAct declText range.pos.column declId declSig cctx).run cmdState) with
      | .error _ => return none
      | .ok (result, _) => return result
    catch _ => return none

/-- Whether a declaration is worth *fully re-elaborating* from source (statement +
body) for real proof-body hover info: only declarations that carry a value/proof —
theorems and definitions. `opaque`/`axiom` have no body to re-run (the cheaper
`opaque`-signature path suffices), and structure/inductive-like declarations are not
plain commands whose body is a term. -/
def isFullReelabCandidate (cinfo : Lean.ConstantInfo) : Bool :=
  match cinfo with
  | .thmInfo _ | .defnInfo _ => true
  | _ => false

/-- Heartbeat cap for a full-declaration (statement + proof) re-elaboration, in the
option's ×1000 units: 4× Lean's default `maxHeartbeats` of 200000. A proof re-run
from verbatim source is pure overhead on top of the real build, so a runaway
`decide`/`induction`/`simp` body is bounded here and degrades to the cheaper
signature-only path rather than stalling generation. Kept as a hardcoded constant
(not a lakefile option) since no consumer has needed to tune it. -/
def fullDeclReelabMaxHeartbeats : Nat := 4 * 200000

open Lean Elab in
/-- Whether a parsed top-level command is — or macro-expands to — a plain
`Lean.Parser.Command.declaration`.

Mathlib's `lemma` is its *own* command kind whose `@[macro]` expander rewrites the
node **in place** (`setKind`/`modifyArg` on the same subtrees, no re-quotation) to a
`theorem` declaration — so every `declId`/`declSig`/`declVal` node, and hence every
source position the highlighter matches info-tree entries against, is shared
between the original and expanded forms. We therefore check *eligibility* by
expanding step by step (fuel-bounded), while the caller keeps operating on the
ORIGINAL syntax: the rename/attribute-strip rewrite targets the
`declId`/`declModifiers` nodes (present verbatim in the original since `lemma` is
built from the standard declaration parsers), and `Command.elabCommand` performs
this same macro expansion itself during the real elaboration. Environment-driven —
no hard dependency on any Mathlib name: in a consumer without the `lemma` macro
that kind never parses, and a non-`declaration` command that expands to nothing
yields `false` (caller degrades to the fallback paths). -/
private partial def expandsToDeclaration (stx : Lean.Syntax) (fuel : Nat := 8) :
    Command.CommandElabM Bool := do
  if stx.getKind == ``Lean.Parser.Command.declaration then return true
  if fuel == 0 then return false
  try
    match ← liftMacroM (Lean.Macro.expandMacro? stx) with
    | some stx' => expandsToDeclaration stx' (fuel - 1)
    | none => return false
  catch _ => return false

open SubVerso.Highlighting Lean Elab in
/-- The `CommandElabM` core of `highlightDeclFromSource?`: elaborate a *spliced*
copy of the whole declaration (fresh clash-free name, attributes stripped) as a
genuine `theorem`/`def` — so its tactics actually run and the resulting info trees
carry const/fvar/hover data for the proof body — then highlight the *original*
statement and body syntax against those trees. Runs in an isolated command state
(caller-supplied, seeded with the decl's written namespace + the heartbeat cap).
Returns the signature `Highlighted` (identical shape to `highlightStatementAct`)
paired with the optional body `Highlighted`. `none` on any elaboration error. -/
private def highlightDeclAct (declText : String) (sigDeIndentCol : Nat)
    (origCmd declId declSig : Lean.Syntax) (bodyStx? : Option Lean.Syntax)
    (freshName : Lean.Name) :
    Command.CommandElabM (Option (SubVerso.Highlighting.Highlighted ×
        Option SubVerso.Highlighting.Highlighted)) := do
  -- Accept only commands that are — or macro-expand to (e.g. Mathlib's `lemma`) —
  -- a plain single declaration; `mutual`/`example`/arbitrary commands fall back.
  unless ← expandsToDeclaration origCmd do return none
  let origPos := declId.getPos?
  let freshIdent := mkIdentFrom declId[0] freshName
  let declIdKind := ``Lean.Parser.Command.declId
  let modsKind := ``Lean.Parser.Command.declModifiers
  -- Rename *this* declaration (matched by kind + source position, so nested `where`
  -- helper `declId`s keep their names) to a fresh non-clashing name, and drop the
  -- attribute block (index 1 of `declModifiers`) so `@[simp]`/`instance`/… attributes
  -- are never (re-)registered — mirroring how the signature path splices a bare
  -- `opaque`. Everything else (binders, type, `noncomputable`/`unsafe`/`partial`
  -- markers, the proof body) is kept verbatim so it elaborates as written.
  let spliced := origCmd.rewriteBottomUp fun s =>
    if s.getKind == declIdKind && s.getPos? == origPos then s.setArg 0 freshIdent
    else if s.getKind == modsKind then s.setArg 1 Lean.mkNullNode
    else s
  let trees ← withoutModifyingEnv do
    Command.elabCommand spliced
    pure (← getInfoState).trees
  if ← Lean.MonadLog.hasErrors then return none
  let (sigHl, bodyHl?) ← Command.liftTermElabM <|
    withTheReader Lean.Core.Context ({· with fileMap := Lean.FileMap.ofString declText}) do
      let name ← highlight declId #[] trees
      let sigHl ← highlight declSig #[] trees
      let sig := SubVerso.Highlighting.Highlighted.seq #[name, sigHl]
      let bodyHl? ← match bodyStx? with
        | none => pure none
        | some body =>
          let hl ← highlight body #[] trees
          pure (some (hl.deIndent hl.indentation))
      pure (sig.deIndent sigDeIndentCol, bodyHl?)
  return some (sigHl, bodyHl?)

open Lean Elab in
/--
Highlight a declaration's **statement *and* proof/value body** from its verbatim
source text with full semantic info (const/fvar classification and hovers on the
tactic body), preserving the author's exact layout.

Where `highlightStatementFromSource?` splices a bodyless `opaque` (so lemma
references *inside a proof* stay `unknown`, un-hoverable tokens), this re-elaborates
the **entire** declaration — a real `theorem`/`def` under a fresh clash-free name —
so its tactics run and the info trees carry the proof body's semantic data. From
that one elaboration it produces BOTH the signature `Highlighted` (same shape the
`opaque` path returns, so callers render signatures identically) and the body
`Highlighted`, avoiding a second elaboration for the signature.

Seeded with the declaration's written namespace (see `declWrittenNamespace?`) and
capped at `fullDeclReelabMaxHeartbeats`. Degrades to `none` — caller falls back to
the `opaque`-signature + syntactic-body paths — when the source is not a single
declaration (commands that macro-expand to one, e.g. Mathlib's `lemma`, are
accepted — see `expandsToDeclaration`), has no explicit type ascription, uses a
non-simple `:=` body with
`where`/termination clauses (kept whole by the text path instead), or fails to
parse/elaborate in this context (module-level `open`/`variable`/`section` state that
is not in scope here). The body component is `none` (signature still returned) when
the body is not a plain `:= term`.
-/
def highlightDeclFromSource? (declName : Lean.Name) (content : String)
    (range : Lean.DeclarationRange) :
    Lean.CoreM (Option (SubVerso.Highlighting.Highlighted ×
        Option SubVerso.Highlighting.Highlighted)) := do
  let fileMap := Lean.FileMap.ofString content
  let startPos := fileMap.ofPosition range.pos
  let endPos := fileMap.ofPosition range.endPos
  let declText := String.Pos.Raw.extract content startPos endPos
  let env ← getEnv
  let .ok cmdStx := Lean.Parser.runParserCategory env `command declText "<decl>"
    | return none
  -- Eligibility (single plain declaration, possibly behind a declaration-producing
  -- macro like Mathlib's `lemma`) is checked inside the act (`expandsToDeclaration`,
  -- which needs `CommandElabM` for macro expansion). Here we only require the
  -- standard declaration nodes to be present in the ORIGINAL syntax — they are, for
  -- both `declaration` and `lemma`-style commands built from the standard parsers.
  let some declId := cmdStx.find? (·.getKind == ``Lean.Parser.Command.declId)
    | return none
  let some sigNode := cmdStx.find? (fun s =>
      s.getKind == ``Lean.Parser.Command.declSig || s.getKind == ``Lean.Parser.Command.optDeclSig)
    | return none
  let some declSig := statementDeclSig? sigNode
    | return none
  -- The proof/value body: the term after a top-level `:=`, but only when the body is
  -- a plain `declValSimple` with no `where`/termination suffix — otherwise the term
  -- node would not cover the whole body, so we leave `bodyStx? = none` and let the
  -- caller keep the text/syntactic body (which spans everything after `:=`).
  let bodyStx? : Option Lean.Syntax :=
    match cmdStx.find? (·.getKind == ``Lean.Parser.Command.declValSimple) with
    | some dv =>
      -- `dv[2]` is the always-present `Termination.suffix` node (two optional
      -- children) and `dv[3]` the optional `where`; both carry no source position /
      -- args when absent. Only then does the body term `dv[1]` span the whole body.
      if dv[2].getPos?.isNone && dv[3].getNumArgs == 0 then some dv[1] else none
    | none => none
  let userName := (privateToUserName? declName).getD declName
  let currNamespace :=
    (declWrittenNamespace? userName declId[0].getId).getD Lean.Name.anonymous
  let declFileMap := Lean.FileMap.ofString declText
  let cctx : Lean.Elab.Command.Context :=
    { fileName := "<decl>", fileMap := declFileMap, snap? := none, cancelTk? := none }
  let opts := Lean.maxHeartbeats.set {} fullDeclReelabMaxHeartbeats
  let cmdState : Lean.Elab.Command.State :=
    { env, maxRecDepth := (← readThe Lean.Core.Context).maxRecDepth,
      scopes := [{ header := "", currNamespace, opts }] }
  let freshName := Lean.Name.mkSimple "_versoBlueprintSourceDecl"
  withRestoredHeartbeats do
    try
      match (← liftM <| EIO.toIO' <|
          (highlightDeclAct declText range.pos.column cmdStx declId declSig bodyStx? freshName
            cctx).run cmdState) with
      | .error _ => return none
      | .ok (result, _) => return result
    catch _ => return none

/-- The `sorryAx` constant, whose presence anywhere in a declaration's axiom closure
means the proof is incomplete — including *transitively*, through a helper lemma
whose own body carries the `sorry`. Direct `Expr.hasSorry` inspection cannot see
that; `Lean.collectAxioms` can. -/
def sorryAxiomName : Lean.Name := Lean.Name.mkSimple "sorryAx"

/-- The declaration's kernel axiom footprint (`Lean.collectAxioms`), as sorted display
strings. Cheap for imported declarations: `collectAxioms` reads a pre-computed
per-module table rather than walking bodies across module boundaries. -/
def declAxiomNames (name : Lean.Name) : Lean.CoreM (Array String) := do
  let axs ← Lean.collectAxioms name
  return (axs.map toString).qsort (· < ·)

/-- Whether the module's source file is newer than the `.olean` it was compiled into.
Best-effort: any lookup/stat failure yields `false` (never a build error) — the
annotation is a warning surface, not a gate. -/
def sourceNewerThanOlean (moduleName : Lean.Name) (sourcePath : System.FilePath) :
    IO Bool := do
  try
    let oleanPath ← Lean.findOLean moduleName
    let srcMeta ← sourcePath.metadata
    let oleanMeta ← oleanPath.metadata
    let src := srcMeta.modified
    let ole := oleanMeta.modified
    return src.sec > ole.sec || (src.sec == ole.sec && src.nsec > ole.nsec)
  catch _ =>
    return false

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
    -- Kernel axiom audit (layer A): the transitive axiom closure. `sorryAx` in the
    -- closure means the proof is incomplete even when nothing in *this* declaration
    -- carries a literal `sorry`, so it upgrades the status — and, because every
    -- roll-up (node badge, dashboard progress, worklist) reads `provedStatus`, the
    -- transitive gap propagates everywhere for free.
    let axioms ← declAxiomNames canonical
    let directStatus :=
      Informal.Data.ConstantInfo.blueprintProvedStatus cinfo (allowOpaque := true)
    let provedStatus :=
      if axioms.contains (toString sorryAxiomName) then
        match directStatus with
        | .containsSorry _ => directStatus
        | .axiomLike => directStatus
        | _ => .containsSorry #[{ location := .proof }]
      else directStatus
    let ref : Data.ExternalRef := {
      ref with
      canonical
      present := true
      provedStatus
      kind := nodeKind
      axioms? := some axioms
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
    -- Read the source file once (shared by the verbatim-signature highlight and the
    -- proof-body capture below); `none` on any missing/unreadable source.
    let content? : Option String ←
      match sourcePath? with
      | some p => (try pure (some (← IO.FS.readFile p)) catch _ => pure none)
      | none => pure none
    -- Full-declaration re-elaboration (statement + proof) from verbatim source: one
    -- real `theorem`/`def` elaboration yielding BOTH the signature highlight and a
    -- semantically-highlighted proof body (lemma references inside the proof become
    -- hoverable const tokens). Only for theorems/defs with local source; degrades to
    -- `none` on any failure — the signature then comes from the cheaper `opaque` path
    -- below and the proof body from the syntactic path, so we never double-elaborate.
    let fullDecl? : Option (SubVerso.Highlighting.Highlighted ×
        Option SubVerso.Highlighting.Highlighted) ←
      match content?, ranges? with
      | some content, some ranges =>
        if isFullReelabCandidate cinfo then
          highlightDeclFromSource? canonical content ranges.range
        else pure none
      | _, _ => pure none
    -- Verbatim-source signature (full hovers + author's layout) for the node card,
    -- when local source is available and the declaration has an elaboratable
    -- signature. Prefer the full-decl re-elaboration's signature; else re-elaborate
    -- just the signature as an `opaque`. Structures/inductives/recursors keep the
    -- delaborated path (their source is not a plain `binders : type` signature).
    -- Degrades to `none` (→ `Signature.forName`) on any parse/elaboration failure.
    let sourceSig? : Option Verso.Genre.Manual.Signature ←
      match fullDecl? with
      | some (sigHl, _) => pure (some { wide := sigHl, narrow := sigHl })
      | none =>
        match content?, ranges? with
        | some content, some ranges =>
          if isStatementSignatureCandidate cinfo then
            match ← highlightStatementFromSource? canonical content ranges.range with
            | some hl => pure (some { wide := hl, narrow := hl })
            | none => pure none
          else pure none
        | _, _ => pure none
    let renderResult ← (renderDeclHtmlDirectFromInfoE canonical cinfo sourceSig?).run'
    let render : Data.ExternalDeclRender :=
      match renderResult with
      | .ok html => .ok html
      | .error err => .error err
    let proofSource? : Option String :=
      match content?, ranges? with
      | some content, some ranges => proofSourceFromContent? content ranges.range
      | _, _ => none
    -- Proof-body HTML: prefer the fully re-elaborated body (real hovers), else the
    -- purely-syntactic highlight of the captured source text.
    let proofHtml? ←
      match fullDecl? with
      | some (_, some bodyHl) => pure (some (renderHighlightedSelfContainedHtml bodyHl))
      | _ =>
        match proofSource? with
        | some src => highlightProofSourceHtml? src
        | none => pure none
    -- Rendering tiers, decided exactly where the fallback chain above resolved. A
    -- silent downgrade (heartbeat cap, unparsable source, module `open`s out of
    -- scope) therefore becomes a *visible* tier change rather than an invisible one.
    let sigTier? : Option String :=
      if fullDecl?.isSome then some "reelab"
      else if sourceSig?.isSome then some "signature"
      else some "delaborated"
    let proofTier? : Option String :=
      match fullDecl? with
      | some (_, some _) => some "reelab"
      | _ =>
        if proofHtml?.isSome then some "syntactic"
        else if proofSource?.isSome then some "raw"
        else none
    -- Displayed text comes from the source file; status comes from the compiled
    -- environment. Flag the case where those two can disagree.
    let sourceStale ←
      match moduleName?, sourcePath? with
      | some m, some p => liftM (sourceNewerThanOlean m p)
      | _, _ => pure false
    pure {
      ref with
      provenance
      range? := ranges?.map (fun r => r.range)
      selectionRange?
      sourceHref?
      render
      proofSource?
      proofHtml?
      sigTier?
      proofTier?
      sourceStale
    }

def workspaceRoot : Lean.CoreM System.FilePath := do
  let cwd ← liftM <| IO.currentDir
  liftM <| IO.FS.realPath cwd

def externalRefSnapshotAtCurrentDir (opts : Lean.Options)
    (ref : Data.ExternalRef) : Lean.CoreM Data.ExternalRef := do
  externalRefSnapshot opts (← workspaceRoot) ref

end Informal
