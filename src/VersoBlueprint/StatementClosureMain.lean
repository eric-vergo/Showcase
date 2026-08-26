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
  "    \"signatureChars\": cap on a recorded signature's characters - optional",
  "  }",
  "",
  "Output: {\"ok\": true, \"schemaVersion\", \"chain\", \"declared\", \"closure\"} on success;",
  "  {\"ok\": false, \"stage\", \"error\"} and a nonzero exit otherwise."
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

/--
Partition the chain's declared imports into the closure to load and the imports an
earlier chain file satisfies.

An import naming a *later* chain file is a chain-order error rather than something to
paper over: elaborating in the stated order would not see it, and guessing an order is
the kind of quiet repair that makes a provenance record worthless.
-/
def partitionImports (files : Array ChainParsed) : ToolM (Array Import × Array String) := do
  let paths := files.map (·.path)
  let mut closure : Array Import := #[]
  let mut internal : Array String := #[]
  for (f, i) in files.zipIdx do
    for imp in f.imports do
      match chainFileFor? paths imp.module with
      | some k =>
        if k < i then
          unless internal.contains imp.module.toString do
            internal := internal.push imp.module.toString
        else if k == i then
          fail "chain-order" s!"{f.path} imports {imp.module}, which names the file itself."
        else
          fail "chain-order" s!"{f.path} imports {imp.module}, which the job spec lists \
            after it ({paths[k]!}). The chain elaborates in the order given, so a \
            dependency must be listed before the file that imports it."
      | none =>
        unless closure.any (fun c => c.module == imp.module && c.isMeta == imp.isMeta) do
          closure := closure.push imp
  return (closure, internal)

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

/--
Elaborate the chain in a fresh environment and return it with what was elaborated.

`importModules` receives exactly the partitioned closure, so the environment holds the
chain's imports and nothing else. Heartbeats are unlimited: the elaboration is a handful
of statements, and a heartbeat failure here would degrade a trust surface for a reason
that has nothing to do with trust.
-/
unsafe def elaborateChain (files : Array ChainParsed) (importsOverride? : Option (Array String)) :
    ToolM (Environment × Provenance) := do
  let (headerImports, internal) ← partitionImports files
  let imports : Array Import :=
    match importsOverride? with
    | some names => names.map fun n => { module := n.toName : Import }
    | none => headerImports
  let level : OLeanLevel := if files.all (·.isModule) then .exported else .private
  let env0 ← tryIO "import"
    s!"importing the chain's declared closure \
      ({String.intercalate ", " (imports.map (·.module.toString)).toList}); the tool \
      resolves modules through LEAN_PATH, so it must run from the consumer's Lake workspace"
    (Lean.importModules imports {} (trustLevel := 1024) (loadExts := true) (level := level))
  let elabOpts : Options := Lean.Options.set {} `maxHeartbeats (0 : Nat)
  let mut env := env0
  for (f, i) in files.zipIdx do
    let cmdState := Lean.Elab.Command.mkState (env.setMainModule (mainModuleFor files i)) {} elabOpts
    let st ← tryIO "elaborate" s!"elaborating {f.path}"
      (Lean.Elab.IO.processCommands f.inputCtx f.parserState cmdState)
    if st.commandState.messages.hasErrors then
      fail "elaborate" s!"{f.path} did not elaborate: \
        {← tryIO "elaborate" "reading messages" (messageLogText st.commandState.messages)}"
    env := st.commandState.env
  let provenance : Provenance := {
    files := files.map fun f => { path := f.path, sha256 := f.digest }
    -- By module name: `Init` is imported twice (once `meta`), which is a fact about the
    -- import records, not about what a reader of the provenance line needs.
    imports := imports.foldl (init := #[]) fun acc imp =>
      let m := imp.module.toString
      if acc.contains m then acc else acc.push m
    chainInternalImports := internal
    importsOverridden := importsOverride?.isSome
  }
  return (env, provenance)

/-- Compute the closure of `roots` in `env`. -/
def runClosure (env : Environment) (cfg : Config) (roots : Array Name) : ToolM Result := do
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
  let (result, _) ← tryIO "closure" "walking the closure"
    (((closure cfg roots).run').toIO ctx { env })
  return result

unsafe def runJob (job : Job) : ToolM Json := do
  let sources ← job.files.mapM readChainSource
  let parsed ← sources.mapM parseChainHeader
  let (env, provenance) ← elaborateChain parsed job.importsOverride?
  let roots := job.roots.map String.toName
  let result ← runClosure env job.config roots
  let report : Report := { provenance, result, declared := chainDeclaredNames env }
  return report.toJson

/-! ## Self-test

A chain importing nothing but `Init`, exercising each rule the walk has: a definition
expanded through its value, an inductive expanded through its constructor types (which
name the inductive back, so the cycle guard runs), and frontier constants recorded but
never expanded. Cheap enough to run as a build smoke test.
-/

def selfTestSource : String :=
"namespace StatementClosureSelfTest

/-- Expanded through its value, which names a frontier constant. -/
def wrap (n : Nat) : Nat := Nat.succ n

/-- Expanded through its constructor types, which name it back. -/
inductive Tag where
  | plain
  | wrapped (n : Nat)

def tagValue : Tag → Nat
  | .plain => 0
  | .wrapped n => wrap n

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
  let result ← runClosure env cfg #[`StatementClosureSelfTest.root]
  let report : Report := { provenance, result, declared := chainDeclaredNames env }
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
    failures := failures.push "the walk truncated on a chain of four declarations"
  if result.untrusted == 0 then
    failures := failures.push "nothing outside the trusted frontier was recorded"
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
