/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import VersoBlueprint.StatementClosure

/-!
# `statement-closure` — the meaning closure of a certified claim, computed clean

Reads a JSON job spec naming a challenge chain and the theorems a verifier certified,
elaborates that chain in a **fresh environment**, and writes the closure of those
theorems' statements as JSON on stdout.

## Why a subprocess

The site's own elaboration environment contains the subject library, Mathlib and Verso.
Re-elaborating a challenge file there would resolve its short names against everything in
scope, which is not the environment the verifier saw: a name could resolve to a different
constant, and the resulting reading list would describe a statement nobody certified.
This process imports exactly the chain's declared import closure — no subject library, no
Verso, no site state — so what it reads is what the chain says.

## The boundary is per file, not per chain (CX-044)

Loading the union of the whole chain's declared imports once and carrying one environment
forward moves the same defect one file down: a dependency that does not elaborate under
its own header succeeds because a *later* file imported what it was missing, and the tool
reports a completed closure over a file the comparator's own import discipline would
reject.

So each file elaborates in an environment built from **its own declared imports plus the
earlier chain files it transitively imports** — which is exactly what Lean's transitive
`import` gives it, and nothing more. A file that needs something only a later file
declared fails at its own step, with its own error, and no closure is written.

Earlier chain modules have no `.olean`, so they are materialized by re-elaborating them
into the later file's environment. That re-elaboration happens under a superset of the
imports the file itself declared, so it is cross-checked: the names a replay produces must
be exactly the names that file produced at its own step, or the tool stops rather than
reporting a closure over a differently-elaborated dependency. In the ordinary case — a
linear chain whose later files declare no import their dependencies did not — the previous
file's finished environment *is* the next file's base, and nothing is replayed at all.

## Required working directory

Module resolution is `LEAN_PATH`-driven, so the tool must run **from the consumer's Lake
workspace**: the package root whose `.lake/packages` holds the oleans the chain imports,
which is the same build CWD the site's trust options resolve against. Invoked by the
build-time driver this is automatic (the child inherits the site build's environment).
Run by hand, use `lake env statement-closure job.json` from the consumer package root, or
set `LEAN_PATH` yourself. Relative paths in the job spec resolve against that directory.

## Contract

Success writes one document with `"ok": true`; every failure writes
`{"ok": false, "stage": …, "error": …}` and exits nonzero. A partial result is never
written: a reading list that silently lost its last import is worse than none.
-/

namespace Informal.StatementClosure.Tool

open Lean
open Informal.StatementClosure

def helpText : String := String.intercalate "\n" [
  "statement-closure - the meaning closure of a certified claim, computed in a clean environment",
  "",
  "Usage:",
  "  statement-closure <job.json>     compute the closure described by a job spec",
  "  statement-closure --self-test    elaborate a built-in chain against Init and check it",
  "  statement-closure --help         this message",
  "",
  "Working directory:",
  "  Run from the consumer's Lake workspace (the package root whose .lake/packages holds",
  "  the oleans the chain imports); module resolution is LEAN_PATH-driven, so",
  "    lake env statement-closure job.json",
  "  from that directory is the reliable invocation. Job-spec paths resolve against it.",
  "",
  "Job spec:",
  "  {",
  "    \"files\":          [chain paths, dependencies first, primary Challenge last],",
  "    \"imports\":        [module names] - optional; replaces the chain headers' closure,",
  "    \"roots\":          [theorem names the verifier certified],",
  "    \"maxNodes\":       cap on recorded declarations (floor 32),",
  "    \"trustedRoots\":   [module roots the walk stops at] - optional,",
  "    \"subjectRoots\":   [module roots of the presented library] - optional,",
  "    \"signatureChars\": cap on a recorded signature's characters - optional,",
  "    \"caveatTable\":    the junk-value table to match, by value - optional; omitted",
  "                      means no symbols are looked for, reported as a disabled scan",
  "  }",
  "",
  "Output: {\"ok\": true, \"schemaVersion\", \"chain\", \"declared\", \"closure\", \"caveats\"}",
  "  on success; {\"ok\": false, \"stage\", \"error\"} and a nonzero exit otherwise."
]

/-- A chain file with the bytes that were hashed and will be elaborated. Read from disk in
the normal path; supplied inline by `--self-test`. -/
structure ChainSource where
  path : String
  source : String
  digest : String
deriving Inhabited

/-- A chain file after its header has been parsed. -/
structure ChainParsed extends ChainSource where
  imports : Array Import
  isModule : Bool
  inputCtx : Parser.InputContext
  parserState : Parser.ModuleParserState

/-- The tool's own failure: the stage it stopped at, and why. -/
structure Failure where
  stage : String
  message : String

abbrev ToolM := ExceptT Failure IO

private def fail (stage message : String) : ToolM α := throw { stage, message }

/-- Run an `IO` action, turning its exception into a staged failure. `try`/`catch` in
`ToolM` catches `Failure`, not `IO.Error`, so every fallible call goes through here. -/
private def tryIO (stage : String) (what : String) (act : IO α) : ToolM α := do
  match ← (act.toBaseIO : BaseIO (Except IO.Error α)) with
  | .ok a => return a
  | .error e => fail stage s!"{what}: {e}"

/-- The path form of a module name, as an import would name a file. -/
def importPathForm (m : Name) : String :=
  m.toString.replace "." "/" ++ ".lean"

/-- Index of the chain file an import names, when the import is satisfied by the chain
rather than by an olean. -/
def chainFileFor? (paths : Array String) (m : Name) : Option Nat :=
  paths.findIdx? (fun p => pathHasSuffix p (importPathForm m))

/-- A chain file's basename without its extension. -/
def fileStem (path : String) : String :=
  let base := (((normalizePathForCompare path).splitOn "/").getLast?).getD path
  if base.endsWith ".lean" then (base.dropEnd 5).toString else base

/-- Read a chain file, hashing exactly the bytes that will be elaborated. -/
def readChainSource (path : String) : ToolM ChainSource := do
  unless ← tryIO "chain-read" "probing the chain file" (System.FilePath.pathExists path) do
    fail "chain-read" s!"chain file does not exist (resolved against the working directory \
      {(← IO.currentDir).toString}): {path}"
  let bytes ← tryIO "chain-read" s!"reading {path}" (IO.FS.readBinFile path)
  match String.fromUTF8? bytes with
  | none => fail "chain-read" s!"{path} is not valid UTF-8, so it cannot be elaborated."
  | some source => return { path, source, digest := Informal.Sha256.hex bytes }

private def messageLogText (msgs : MessageLog) : IO String := do
  let mut lines : Array String := #[]
  for msg in msgs.toList do
    if msg.severity == .error then
      lines := lines.push (← msg.toString).trimAscii.toString
  return String.intercalate "; " lines.toList

/-- Parse a chain file's header. Errors here are the chain's, not the tool's, so they are
reported verbatim. -/
def parseChainHeader (src : ChainSource) : ToolM ChainParsed := do
  let inputCtx := Parser.mkInputContext src.source src.path
  let (header, parserState, msgs) ←
    tryIO "chain-parse" s!"parsing the header of {src.path}" (Lean.Parser.parseHeader inputCtx)
  if msgs.hasErrors then
    fail "chain-parse" s!"{src.path} has header errors: \
      {← tryIO "chain-parse" "reading header messages" (messageLogText msgs)}"
  return {
    toChainSource := src
    imports := Lean.Elab.headerToImports header
    isModule := Lean.Elab.HeaderSyntax.isModule header
    inputCtx
    parserState
  }

/-- Deduplicating union of two import lists, first-appearance order preserved. -/
private def unionImports (a b : Array Import) : Array Import :=
  b.foldl (init := a) fun acc imp =>
    if acc.any (fun c => c.module == imp.module && c.isMeta == imp.isMeta) then acc
    else acc.push imp

/-- The chain's import structure, kept **per file** rather than as one union: which
imports each file declares that no chain file satisfies, and which earlier chain files it
imports. -/
structure ChainImports where
  /-- Per file, in chain order: the imports an `importModules` call has to load for it. -/
  external : Array (Array Import) := #[]
  /-- Per file: indices of the earlier chain files it imports directly. -/
  internal : Array (Array Nat) := #[]
  /-- Module names satisfied by an earlier chain file rather than by an olean, in
  first-appearance order. The provenance line's `chainInternalImports`. -/
  internalNames : Array String := #[]
deriving Inhabited

/-- Every import the chain loads anywhere, in chain-then-import order. What the provenance
line reports: the modules this run read. It is deliberately **not** what any one file
elaborates against — see `elaborateChain`. -/
def ChainImports.allExternal (ci : ChainImports) : Array Import :=
  ci.external.foldl (init := #[]) unionImports

/--
Partition each chain file's declared imports into the ones an `importModules` call must
load and the ones an earlier chain file satisfies.

An import naming a *later* chain file is a chain-order error rather than something to
paper over: elaborating in the stated order would not see it, and guessing an order is
the kind of quiet repair that makes a provenance record worthless.
-/
def partitionImports (files : Array ChainParsed) : ToolM ChainImports := do
  let paths := files.map (·.path)
  let mut external : Array (Array Import) := #[]
  let mut internal : Array (Array Nat) := #[]
  let mut internalNames : Array String := #[]
  for (f, i) in files.zipIdx do
    let mut ext : Array Import := #[]
    let mut int : Array Nat := #[]
    for imp in f.imports do
      match chainFileFor? paths imp.module with
      | some k =>
        if k < i then
          unless int.contains k do int := int.push k
          unless internalNames.contains imp.module.toString do
            internalNames := internalNames.push imp.module.toString
        else if k == i then
          fail "chain-order" s!"{f.path} imports {imp.module}, which names the file itself."
        else
          fail "chain-order" s!"{f.path} imports {imp.module}, which the job spec lists \
            after it ({paths[k]!}). The chain elaborates in the order given, so a \
            dependency must be listed before the file that imports it."
      | none =>
        unless ext.any (fun c => c.module == imp.module && c.isMeta == imp.isMeta) do
          ext := ext.push imp
    external := external.push ext
    internal := internal.push int
  return { external, internal, internalNames }

/-- Indices of every earlier chain file `i` imports, directly or through another chain
file, in ascending (elaboration) order.

`import` is transitive in Lean, so a file that imports a chain module also sees that
module's imports. It sees **nothing else**: that is the whole of the per-file boundary. -/
def transitiveChainDeps (internal : Array (Array Nat)) (i : Nat) : Array Nat := Id.run do
  let mut seen : Array Nat := #[]
  let mut stack : Array Nat := (internal[i]?).getD #[]
  while !stack.isEmpty do
    let k := stack.back!
    stack := stack.pop
    unless seen.contains k do
      seen := seen.push k
      stack := stack ++ (internal[k]?).getD #[]
  return seen.qsort (· < ·)

/-- The module name to elaborate a chain file under: the name a later chain file imports
it by when one does, else the file's stem. It affects private-name mangling and message
text only — nothing the closure reads. -/
def mainModuleFor (files : Array ChainParsed) (idx : Nat) : Name := Id.run do
  let path := (files[idx]?).map (·.path) |>.getD ""
  for f in files do
    for imp in f.imports do
      if pathHasSuffix path (importPathForm imp.module) then
        return imp.module
  return (fileStem path).toName

/-- Names the elaborated chain itself declared, minus compiler-internal auxiliaries,
sorted so the document is a deterministic function of the chain. -/
def chainDeclaredNames (env : Environment) : Array String :=
  let names := Lean.SMap.foldStage2
    (fun (acc : Array Name) n _ => if isAuxiliary env n then acc else acc.push n)
    #[] env.constants
  (names.map (·.toString)).qsort (· < ·)

/-- Elaborate one chain file into `env`, failing with the file's own messages. Heartbeats
are unlimited: the elaboration is a handful of statements, and a heartbeat failure here
would degrade a trust surface for a reason that has nothing to do with trust. -/
private unsafe def elabChainFile (files : Array ChainParsed) (elabOpts : Options)
    (env : Environment) (i : Nat) : ToolM Environment := do
  let some f := files[i]?
    | fail "elaborate" s!"chain position {i} is not a file this run read."
  let cmdState := Lean.Elab.Command.mkState (env.setMainModule (mainModuleFor files i)) {} elabOpts
  let st ← tryIO "elaborate" s!"elaborating {f.path}"
    (Lean.Elab.IO.processCommands f.inputCtx f.parserState cmdState)
  if st.commandState.messages.hasErrors then
    fail "elaborate" s!"{f.path} did not elaborate: \
      {← tryIO "elaborate" "reading messages" (messageLogText st.commandState.messages)}"
  return st.commandState.env

/-- Names in `after` that are not in `before`: what elaborating one file added. -/
private def addedNames (before after : Array String) : Array String :=
  let seen : Std.HashSet String := before.foldl (init := {}) (·.insert ·)
  after.filter fun n => !seen.contains n

/-- The identity of an environment as a base: which imports it loaded, at which olean
level, and which chain files were elaborated into it. Two files with the same key need the
same environment, which is what lets a linear chain reuse one. -/
private def baseKey (imports : Array Import) (exported : Bool) (deps : Array Nat) : String :=
  let imps := (imports.map fun c => c.module.toString ++ (if c.isMeta then "!" else "")).toList
  s!"{deps.toList}|{exported}|{imps}"

/--
The environment one chain file elaborates in: its effective import closure loaded fresh,
then every earlier chain file it transitively imports, replayed in chain order.

The replay is the only way to materialize a chain module — it has no `.olean` — and it
runs under a superset of the imports that file declared for itself, so it is checked
against what that file declared at its own step. A dependency that elaborates to a
different set of names in the two environments is not a dependency this tool can report a
closure over.
-/
private unsafe def assembleBase (files : Array ChainParsed) (elabOpts : Options)
    (imports : Array Import) (exported : Bool) (deps : Array Nat)
    (declaredBy : Array (Array String)) : ToolM Environment := do
  let level : OLeanLevel := if exported then .exported else .private
  let mut env ← tryIO "import"
    s!"importing the chain's declared closure \
      ({String.intercalate ", " (imports.map (·.module.toString)).toList}); the tool \
      resolves modules through LEAN_PATH, so it must run from the consumer's Lake workspace"
    (Lean.importModules imports {} (trustLevel := 1024) (loadExts := true) (level := level))
  for k in deps do
    let before := chainDeclaredNames env
    env ← elabChainFile files elabOpts env k
    let added := addedNames before (chainDeclaredNames env)
    match declaredBy[k]? with
    | some expected =>
      unless added == expected do
        let path := ((files[k]?).map (·.path)).getD s!"chain position {k}"
        fail "elaborate" s!"{path} declares different names under its own imports than \
          under the imports a later chain file requires ({expected.size} against \
          {added.size}). A dependency whose meaning depends on which file is reading it \
          is not one this tool can compute a closure over."
    | none => pure ()
  return env

/--
Elaborate the chain and return the final environment with what was elaborated.

Each file gets its own base (`assembleBase`) built from **its own** declared imports plus
those of the earlier chain files it transitively imports — never from imports only a later
file declared (CX-044). Where consecutive files need the same base plus the previous file,
the previous file's finished environment is reused, so an ordinary linear chain still
imports once and elaborates each file once.

A caller-supplied `imports` override replaces the header closure for every file, verbatim,
which is what the job spec documents it to do.
-/
unsafe def elaborateChain (files : Array ChainParsed) (importsOverride? : Option (Array String)) :
    ToolM (Environment × Provenance) := do
  let ci ← partitionImports files
  let overrideImports? : Option (Array Import) :=
    importsOverride?.map fun names => names.map fun n => ({ module := n.toName } : Import)
  let n := files.size
  let deps : Array (Array Nat) := (Array.range n).map (transitiveChainDeps ci.internal ·)
  let effective : Array (Array Import) := (Array.range n).map fun i =>
    match overrideImports? with
    | some imps => imps
    | none => ((deps[i]!).push i).foldl (init := #[]) fun acc k => unionImports acc (ci.external[k]!)
  -- The olean level a file's own base loads at is decided by that file and the chain files
  -- it imports, for the same reason its import set is: a `module` keyword in a file nobody
  -- imports is not a fact about this one's environment.
  let exported : Array Bool := (Array.range n).map fun i =>
    ((deps[i]!).push i).all fun k => ((files[k]?).map (·.isModule)).getD false
  let elabOpts : Options := Lean.Options.set {} `maxHeartbeats (0 : Nat)
  let mut declaredBy : Array (Array String) := #[]
  let mut prev? : Option (String × Environment) := none
  let mut final? : Option Environment := none
  for i in [0:n] do
    let want := baseKey effective[i]! exported[i]! deps[i]!
    let base ←
      match prev? with
      | some (k, e) => if k == want then pure e else
          assembleBase files elabOpts effective[i]! exported[i]! deps[i]! declaredBy
      | none => assembleBase files elabOpts effective[i]! exported[i]! deps[i]! declaredBy
    let before := chainDeclaredNames base
    let env ← elabChainFile files elabOpts base i
    declaredBy := declaredBy.push (addedNames before (chainDeclaredNames env))
    prev? := some (baseKey effective[i]! exported[i]! ((deps[i]!).push i), env)
    final? := some env
  let some env := final?
    | fail "chain-read" "the job spec names no chain files, so there is nothing to elaborate."
  let loaded : Array Import :=
    match overrideImports? with
    | some imps => imps
    | none => ci.allExternal
  let provenance : Provenance := {
    files := files.map fun f => { path := f.path, sha256 := f.digest }
    -- By module name: `Init` is imported twice (once `meta`), which is a fact about the
    -- import records, not about what a reader of the provenance line needs.
    imports := loaded.foldl (init := #[]) fun acc imp =>
      let m := imp.module.toString
      if acc.contains m then acc else acc.push m
    chainInternalImports := ci.internalNames
    importsOverridden := importsOverride?.isSome
  }
  return (env, provenance)

/-- Compute the closure of `roots` in `env`, with the caveat scan riding the same walk. -/
def runClosure (env : Environment) (cfg : Config) (roots : Array Name)
    (table? : Option Informal.JunkValues.Table) :
    ToolM (Result × Option Informal.JunkValues.ScanReport) := do
  for r in roots do
    if (env.find? r).isNone then
      fail "roots" s!"the chain does not declare '{r}'. The closure must be computed from \
        the statements the verifier certified, so a root the chain never declared is a \
        configuration error rather than an empty reading list."
  let ctx : Core.Context := {
    fileName := "<statement-closure>"
    fileMap := FileMap.ofString ""
    maxHeartbeats := 0
  }
  let (out, _) ← tryIO "closure" "walking the closure"
    (((closureAndScan cfg roots table?).run').toIO ctx { env })
  return out

/--
The `set_option` half of the caveat scan (§A7(f)).

Lexical, over the bytes this tool hashed and elaborated — the whole chain, not only the
primary Challenge — so what is reported is bound to the same digests as the closure. Only
the published allowlist is reported, and the copy that renders these says "configuration
override present" and nothing sharper.
-/
def scanChainOptions (sources : Array ChainSource) : Array Informal.JunkValues.OptionOverride :=
  sources.foldl (init := #[]) fun acc s =>
    acc ++ Informal.JunkValues.scanSetOptions s.path s.source

unsafe def runJob (job : Job) : ToolM Json := do
  let sources ← job.files.mapM readChainSource
  let parsed ← sources.mapM parseChainHeader
  let (env, provenance) ← elaborateChain parsed job.importsOverride?
  let roots := job.roots.map String.toName
  let (result, scan?) ← runClosure env job.config roots job.caveatTable?
  -- A job with no table gets the switched-off report rather than no report: a caller that
  -- omitted the table is told so, instead of reading an absent field as "nothing found".
  let caveats? : Option Informal.JunkValues.ScanReport :=
    match scan? with
    | none => some (Informal.JunkValues.disabled
        "the job spec carried no caveat table, so no symbols were looked for")
    | some c => some { c with
        optionOverrides := scanChainOptions sources
        optionScanFiles := sources.map (·.path) }
  let report : Report := { provenance, result, declared := chainDeclaredNames env, caveats? }
  return report.toJson

/-! ## Self-test

A chain importing nothing but `Init`, exercising each rule the walk has: a definition
expanded through its value, an inductive expanded through its constructor types (which
name the inductive back, so the cycle guard runs), and frontier constants recorded but
never expanded. `gap` additionally hides a table symbol behind a wrapper — the statement
never mentions truncated subtraction, its meaning closure does — so the caveat scan is
exercised on the shape it exists for. `set_option maxRecDepth` gives the lexical half
something to find. Cheap enough to run as a build smoke test.
-/

def selfTestSource : String :=
"set_option maxRecDepth 512

namespace StatementClosureSelfTest

/-- Expanded through its value, which names a frontier constant. -/
def wrap (n : Nat) : Nat := Nat.succ n

/-- The statement never mentions subtraction; its meaning closure reaches it here. -/
def gap (a b : Nat) : Nat := a - b

/-- Expanded through its constructor types, which name it back. -/
inductive Tag where
  | plain
  | wrapped (n : Nat)

def tagValue : Tag → Nat
  | .plain => 0
  | .wrapped n => wrap (gap n 0)

theorem root : tagValue (Tag.wrapped 0) = 1 := rfl

end StatementClosureSelfTest
"

unsafe def runSelfTest : ToolM (Json × Array String) := do
  let src : ChainSource := {
    path := "SelfTest.lean"
    source := selfTestSource
    digest := Informal.Sha256.hexOfString selfTestSource
  }
  let parsed ← parseChainHeader src
  let (env, provenance) ← elaborateChain #[parsed] none
  let cfg : Config := {}
  let table? := (Informal.JunkValues.bundled).toOption
  let (result, scan?) ← runClosure env cfg #[`StatementClosureSelfTest.root] table?
  let caveats? := scan?.map fun c => { c with
    optionOverrides := scanChainOptions #[src]
    optionScanFiles := #[src.path] }
  let report : Report := { provenance, result, declared := chainDeclaredNames env, caveats? }
  let originOf (n : String) : Option String :=
    (result.entries.find? (·.name == n)).map (·.origin)
  let mut failures : Array String := #[]
  if originOf "StatementClosureSelfTest.wrap" != some "challenge" then
    failures := failures.push "the chain's own `wrap` was not reached as a challenge declaration"
  if originOf "StatementClosureSelfTest.Tag.wrapped" != some "challenge" then
    failures := failures.push "the inductive's constructor was not reached"
  if originOf "Nat" != some "core" then
    failures := failures.push "`Nat` was not recorded as a core frontier constant"
  if result.truncated then
    failures := failures.push "the walk truncated on a chain of five declarations"
  if result.untrusted == 0 then
    failures := failures.push "nothing outside the trusted frontier was recorded"
  if table?.isNone then
    failures := failures.push "the bundled caveat table did not parse"
  match caveats? with
  | none => failures := failures.push "the caveat scan produced no report"
  | some c =>
    if c.status != Informal.JunkValues.statusCompletedWithHits then
      failures := failures.push s!"the caveat scan reported '{c.status}' rather than a hit"
    unless c.hits.any (·.symbol == "Nat.sub") do
      failures := failures.push "truncated subtraction, reached behind a wrapper, was not matched"
    unless c.optionOverrides.any (·.option == "maxRecDepth") do
      failures := failures.push "the chain's `set_option maxRecDepth` was not found"
  return (report.toJson, failures)

/-! ## Driver -/

private def emitError (f : Failure) : IO UInt32 := do
  IO.println (errorJson f.stage f.message).compress
  return 1

unsafe def main (args : List String) : IO UInt32 := do
  if args.isEmpty || args.contains "--help" || args.contains "-h" then
    IO.println helpText
    return (if args.isEmpty then 1 else 0)
  Lean.initSearchPath (← Lean.findSysroot)
  Lean.enableInitializersExecution
  if args.contains "--self-test" then
    match ← runSelfTest.run with
    | .error f => emitError f
    | .ok (doc, failures) =>
      IO.println doc.compress
      if failures.isEmpty then
        IO.eprintln "statement-closure: --self-test passed"
        return 0
      for msg in failures do
        IO.eprintln s!"statement-closure: --self-test failed: {msg}"
      return 1
  else
    let jobPath := args.head!
    if jobPath.startsWith "--" then
      IO.println (errorJson "job-spec" s!"unrecognized option '{jobPath}'").compress
      return 1
    let run : ToolM Json := do
      unless ← tryIO "job-spec" "probing the job spec" (System.FilePath.pathExists jobPath) do
        fail "job-spec" s!"job spec does not exist (resolved against the working directory \
          {(← IO.currentDir).toString}): {jobPath}"
      let raw ← tryIO "job-spec" s!"reading {jobPath}" (IO.FS.readFile jobPath)
      let j ← match Json.parse raw with
        | .error err => fail "job-spec" s!"could not parse {jobPath}: {err}"
        | .ok j => pure j
      let job ← match Job.ofJson? j with
        | .error err => fail "job-spec" err
        | .ok job => pure job
      runJob job
    match ← run.run with
    | .error f => emitError f
    | .ok doc =>
      IO.println doc.compress
      return 0

end Informal.StatementClosure.Tool

unsafe def main (args : List String) : IO UInt32 :=
  Informal.StatementClosure.Tool.main args
