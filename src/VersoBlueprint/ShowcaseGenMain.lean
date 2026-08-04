/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint.DeclRegistry
import VersoBlueprint.ShowcaseGen

/-!
# `showcase-gen` — blueprint skeleton generator

Turns a compiled *subject module* into a Verso blueprint skeleton: one node per public
declaration, grouped and packed into chapter modules, with empty prose slots.

Run it from the **presentation repository**, so Lake supplies a `LEAN_PATH` that
contains the subject module's oleans:

```
lake exe showcase-gen --module MulticolorTriangleRamsey --out .
```

The subject module is loaded with `importModules` at runtime (hence
`supportInterpreter := true` on the Lake target) rather than imported statically: the
generator ships in the blueprint fork and must not depend on any particular corpus.

Declarations are enumerated with `DeclRegistry.enumerateProjectDecls`, the very function
the declaration registry and the all-declarations graph use, so the generated node set
and the registry's public-declaration set agree by construction.

Output is a deterministic function of the olean plus the flags: nothing consults the
clock, the environment, or a hash. `--check` re-runs the emitters and reports whether
anything on disk would change, which is how the run-twice determinism test is phrased.
-/

namespace VersoBlueprint.ShowcaseGen

open Lean

/-! ## Command line -/

structure CliOptions where
  subjectModule : Name := .anonymous
  outDir : System.FilePath := "."
  maxPerChapter : Nat := 100
  minGroup : Nat := 20
  maxGroup : Nat := 150
  nsDepth : Nat := 2
  /-- Comparator config whose `theorem_names` seed the dashboard's featured cards. -/
  comparatorConfig? : Option System.FilePath := none
  projectTitle : String := ""
  shortTitle : String := ""
  copyright : String := "Eric Vergo"
  authors : Array String := #[]
  formalizationYaml : String := "formalization.yaml"
  /-- Overwrite the scaffolding files (`Contents.lean`, `Authors.lean`, …) that are
  otherwise written only when absent. Chapter modules are always rewritten. -/
  force : Bool := false
  /-- Report what would change without writing anything. -/
  check : Bool := false
deriving Inhabited

def helpText : String := String.intercalate "\n" [
  "showcase-gen - generate a Verso blueprint skeleton from a compiled Lean module",
  "",
  "Usage:",
  "  lake exe showcase-gen --module <Module> --out <dir> [options]",
  "",
  "Required:",
  "  --module <Module>            subject module to present (must be on LEAN_PATH)",
  "  --out <dir>                  presentation repository root to write into",
  "",
  "Grouping:",
  "  --max-per-chapter <n>        declarations per chapter module (default 100)",
  "  --min-group <n>              runs smaller than this merge into the predecessor (default 20)",
  "  --max-group <n>              runs larger than this split into numbered parts (default 150)",
  "  --ns-depth <n>               namespace components past the shared prefix (default 2)",
  "",
  "Document:",
  "  --title <text>               document title (default: humanized module name)",
  "  --short-title <text>         short title (default: the module name)",
  "  --author <name>              author byline; repeatable",
  "  --copyright <name>           copyright holder in file headers (default \"Eric Vergo\")",
  "  --formalization-yaml <path>  path passed to {blueprint_formalization} (default formalization.yaml)",
  "  --comparator-config <path>   comparator JSON whose theorem_names become featured cards",
  "",
  "Other:",
  "  --force                      rewrite scaffolding files that already exist",
  "  --check                      report differences without writing",
  "  --help                       this message"
]

private def parseNat (flag arg : String) : Except String Nat :=
  match arg.toNat? with
  | some n => .ok n
  | none => .error s!"{flag} expects a natural number, got '{arg}'"

partial def parseArgs (args : List String) (acc : CliOptions) : Except String CliOptions :=
  match args with
  | [] => .ok acc
  | "--module" :: v :: rest => parseArgs rest { acc with subjectModule := v.toName }
  | "--out" :: v :: rest => parseArgs rest { acc with outDir := v }
  | "--max-per-chapter" :: v :: rest =>
    parseNat "--max-per-chapter" v >>= fun n => parseArgs rest { acc with maxPerChapter := n }
  | "--min-group" :: v :: rest =>
    parseNat "--min-group" v >>= fun n => parseArgs rest { acc with minGroup := n }
  | "--max-group" :: v :: rest =>
    parseNat "--max-group" v >>= fun n => parseArgs rest { acc with maxGroup := n }
  | "--ns-depth" :: v :: rest =>
    parseNat "--ns-depth" v >>= fun n => parseArgs rest { acc with nsDepth := n }
  | "--title" :: v :: rest => parseArgs rest { acc with projectTitle := v }
  | "--short-title" :: v :: rest => parseArgs rest { acc with shortTitle := v }
  | "--author" :: v :: rest => parseArgs rest { acc with authors := acc.authors.push v }
  | "--copyright" :: v :: rest => parseArgs rest { acc with copyright := v }
  | "--formalization-yaml" :: v :: rest => parseArgs rest { acc with formalizationYaml := v }
  | "--comparator-config" :: v :: rest => parseArgs rest { acc with comparatorConfig? := some v }
  | "--force" :: rest => parseArgs rest { acc with force := true }
  | "--check" :: rest => parseArgs rest { acc with check := true }
  | flag :: _ =>
    if flag.startsWith "--" then
      .error s!"unrecognized or incomplete option '{flag}'"
    else
      .error s!"unexpected positional argument '{flag}'"

/-! ## Roster construction -/

/-- Source path of a module inside its own package, derived from the module name.

The manifest records package-relative paths (`MulticolorTriangleRamsey.lean`) rather
than the absolute checkout path, so the file stays byte-identical across machines and
the prose pipeline can resolve it against whatever checkout it has. -/
private def modulePathText (m : Name) : String :=
  (toString m).replace "." "/" ++ ".lean"

/-- Enumerate the subject module's public declarations, in source order. -/
def buildRoster (roots : NameSet) : CoreM (Array RosterEntry) := do
  let env ← getEnv
  let decls ← Informal.DeclRegistry.enumerateProjectDecls roots (includePrivate := false)
  let mut entries : Array RosterEntry := #[]
  for (name, cinfo, modName) in decls do
    let ranges? ← Lean.findDeclarationRanges? name
    let doc? ← Lean.findDocString? env name
    let isTheoremLike :=
      match Informal.Data.ConstantInfo.blueprintNodeKind? cinfo with
      | some k => k.isTheoremLike
      | none => false
    let r := ranges?.map (·.range)
    entries := entries.push {
      name := toString name
      nsComponents := namespaceComponentsOf (toString name)
      isTheoremLike
      line := (r.map (·.pos.line)).getD 0
      col := (r.map (·.pos.column)).getD 0
      endLine := (r.map (·.endPos.line)).getD 0
      endCol := (r.map (·.endPos.column)).getD 0
      moduleName := toString modName
      sourcePath := modulePathText modName
      docstring? := doc?
    }
  -- Source order, with the name as a total tiebreaker so the sort is deterministic even
  -- for declarations that share a range (or carry none): `qsort` is not stable, so the
  -- comparison has to be a total order on its own.
  let cmp := fun (a b : RosterEntry) =>
    (compare a.moduleName b.moduleName).then <|
      (compare a.line b.line).then <|
        (compare a.col b.col).then (compare a.name b.name)
  return entries.qsort fun a b => cmp a b == .lt

/-! ## Featured cards -/

/-- Node labels for the dashboard's featured cards: the comparator config's
`theorem_names`, restricted to declarations this generator actually emitted, capped at
five (the dashboard's design maximum). Absent/unparsable config ⇒ no featured cards. -/
def featuredLabels (roster : Array RosterEntry) (configJson? : Option Json) : Array String :=
  match configJson? with
  | none => #[]
  | some j =>
    let names := (j.getObjValAs? (List String) "theorem_names").toOption.getD []
    let known := roster.foldl (init := ({} : Std.HashSet String)) fun acc e => acc.insert e.name
    let hits := names.filter known.contains
    ((hits.take 5).map declLabel).toArray

/-! ## Writing -/

private structure WriteStats where
  written : Nat := 0
  unchanged : Nat := 0
  skipped : Nat := 0
  removed : Nat := 0
  wouldChange : Array String := #[]

/-- Write `contents` to `path` unless it is already byte-identical. In `--check` mode
nothing is written and differing paths are collected instead. -/
private def writeFileIfChanged (opts : CliOptions) (stats : WriteStats) (path : System.FilePath)
    (contents : String) : IO WriteStats := do
  let existing? ← if ← path.pathExists then some <$> IO.FS.readFile path else pure none
  if existing? == some contents then
    return { stats with unchanged := stats.unchanged + 1 }
  if opts.check then
    return { stats with wouldChange := stats.wouldChange.push path.toString }
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile path contents
  return { stats with written := stats.written + 1 }

/-- Write a scaffolding file only when it is absent (or `--force`). -/
private def writeScaffold (opts : CliOptions) (stats : WriteStats) (path : System.FilePath)
    (contents : String) : IO WriteStats := do
  if (← path.pathExists) && !opts.force then
    return { stats with skipped := stats.skipped + 1 }
  writeFileIfChanged opts stats path contents

/-- Whether a filename is one this generator owns (`C###_*.lean`). -/
private def isGeneratedChapterFile (name : String) : Bool :=
  if !name.endsWith ".lean" then false
  else match name.data with
    | 'C' :: rest =>
      let digits := rest.takeWhile Char.isDigit
      !digits.isEmpty && (rest.drop digits.length).headD ' ' == '_'
    | _ => false

/-- Delete chapter modules left over from a previous run with different group boundaries.
Only files matching the generator's own naming pattern are ever removed. -/
private def pruneStaleChapters (opts : CliOptions) (stats : WriteStats)
    (chaptersDir : System.FilePath) (keep : Std.HashSet String) : IO WriteStats := do
  unless ← chaptersDir.pathExists do return stats
  let mut stats := stats
  let entries := (← chaptersDir.readDir).qsort
    (fun a b => compare a.fileName b.fileName == .lt)
  for entry in entries do
    let name := entry.fileName
    if isGeneratedChapterFile name && !keep.contains name then
      if opts.check then
        stats := { stats with wouldChange := stats.wouldChange.push (entry.path.toString ++ " (stale)") }
      else
        IO.FS.removeFile entry.path
        stats := { stats with removed := stats.removed + 1 }
  return stats

/-! ## Driver -/

unsafe def run (opts : CliOptions) : IO UInt32 := do
  if opts.subjectModule.isAnonymous then
    IO.eprintln "showcase-gen: --module is required"
    return 1
  Lean.initSearchPath (← Lean.findSysroot)
  Lean.enableInitializersExecution
  let env ← Lean.importModules #[{ module := opts.subjectModule }] {}
    (trustLevel := 1024) (loadExts := true)
  let roots : NameSet := ({} : NameSet).insert opts.subjectModule
  let ctx : Core.Context := {
    fileName := "<showcase-gen>"
    fileMap := FileMap.ofString ""
    maxHeartbeats := 0
  }
  let (roster, _) ← (buildRoster roots).toIO ctx { env }
  if roster.isEmpty then
    IO.eprintln s!"showcase-gen: module {opts.subjectModule} contributed no public declarations"
    return 1

  let groups := buildGroups opts.minGroup opts.maxGroup opts.nsDepth roster
  let chapters := packChapters opts.maxPerChapter groups

  let configJson? ← match opts.comparatorConfig? with
    | none => pure none
    | some p =>
      if ← p.pathExists then
        match Json.parse (← IO.FS.readFile p) with
        | .ok j => pure (some j)
        | .error e =>
          IO.eprintln s!"showcase-gen: warning: could not parse {p}: {e}"
          pure none
      else
        IO.eprintln s!"showcase-gen: warning: comparator config {p} does not exist"
        pure none
  let featured := featuredLabels roster configJson?

  let moduleText := toString opts.subjectModule
  let cfg : RenderConfig := {
    subjectModule := moduleText
    projectTitle :=
      if opts.projectTitle.isEmpty then humanizePath moduleText else opts.projectTitle
    shortTitle := if opts.shortTitle.isEmpty then moduleText else opts.shortTitle
    copyright := opts.copyright
    authors := if opts.authors.isEmpty then #["Eric Vergo"] else opts.authors
    formalizationYaml := opts.formalizationYaml
    featured
  }

  let out := opts.outDir
  let chaptersDir := out / "Chapters"
  let mut stats : WriteStats := {}
  let mut keep : Std.HashSet String := {}
  for ch in chapters do
    let file := ch.moduleSuffix ++ ".lean"
    keep := keep.insert file
    stats ← writeFileIfChanged opts stats (chaptersDir / file) (renderChapter cfg roster ch)
  stats ← pruneStaleChapters opts stats chaptersDir keep
  stats ← writeFileIfChanged opts stats (out / "Chapters.lean") (renderChaptersRoot cfg chapters)
  stats ← writeScaffold opts stats (out / "Contents.lean") (renderContents cfg chapters)
  stats ← writeScaffold opts stats (out / "Authors.lean") (renderAuthors cfg)
  stats ← writeScaffold opts stats (out / "Macros.lean") (renderMacros cfg)
  stats ← writeScaffold opts stats (out / "Bibliography.lean") (renderBibliography cfg)
  stats ← writeScaffold opts stats (out / "Contents" / "TeXPrelude.lean") (renderTeXPrelude cfg)
  stats ← writeScaffold opts stats (out / "Main.lean") (renderMain cfg)

  let flags : List (String × Json) := [
    ("maxPerChapter", .num opts.maxPerChapter),
    ("minGroup", .num opts.minGroup),
    ("maxGroup", .num opts.maxGroup),
    ("nsDepth", .num opts.nsDepth)
  ]
  let manifest := (manifestJson cfg roster groups chapters flags).pretty ++ "\n"
  stats ← writeFileIfChanged opts stats (out / "generated-manifest.json") manifest

  IO.println s!"showcase-gen: {roster.size} declarations, {groups.size} groups, {chapters.size} chapters"
  for ch in chapters do
    IO.println s!"  {ch.moduleSuffix}: {ch.declCount} decls in {ch.groups.size} group(s) — {ch.title}"
  if opts.check then
    if stats.wouldChange.isEmpty then
      IO.println s!"showcase-gen: --check clean ({stats.unchanged} file(s) already up to date)"
      return 0
    else
      IO.println "showcase-gen: --check found differences:"
      for p in stats.wouldChange do IO.println s!"  {p}"
      return 1
  IO.println s!"showcase-gen: wrote {stats.written}, unchanged {stats.unchanged}, \
    kept {stats.skipped} existing, removed {stats.removed} stale"
  return 0

unsafe def main (args : List String) : IO UInt32 := do
  if args.isEmpty || args.contains "--help" || args.contains "-h" then
    IO.println helpText
    return (if args.isEmpty then 1 else 0)
  match parseArgs args {} with
  | .error e =>
    IO.eprintln s!"showcase-gen: {e}"
    IO.eprintln helpText
    return 1
  | .ok opts =>
    try
      run opts
    catch e =>
      IO.eprintln s!"showcase-gen: {e}"
      return 1

end VersoBlueprint.ShowcaseGen

unsafe def main (args : List String) : IO UInt32 :=
  VersoBlueprint.ShowcaseGen.main args
