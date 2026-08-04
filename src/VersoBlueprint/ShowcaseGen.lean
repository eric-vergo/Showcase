/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean

/-!
# Showcase skeleton generator — grouping, packing and rendering

The pure half of `showcase-gen` (the CLI lives in `VersoBlueprint.ShowcaseGenMain`).

`showcase-gen` turns a *subject module* — a formalization that a presentation repo
consumes, typically as a Lake/git dependency — into a Verso blueprint skeleton: one
`:::theorem`/`:::definition` node per public declaration, grouped into `:::group`s and
packed into chapter modules, with empty prose slots for an exposition pipeline to fill.

Everything in this module is a **deterministic pure function** of the declaration
roster and the generator flags: same roster in, byte-identical sources out. The only
environment-dependent step (enumerating the roster) happens in the CLI, and it reuses
`DeclRegistry.enumerateProjectDecls` verbatim so the generated node set and the
declaration registry agree by construction.

## Grouping

Declarations are ordered by source position and segmented into *runs* wherever the
grouping key changes. The key is the first `nsDepth` components of a declaration's
namespace **after** dropping the namespace prefix that every declaration in the roster
shares: a corpus that lives entirely under `ErdosProblems.MulticolourTriangleRamsey`
would otherwise land in a single key at any depth, and a corpus rooted at `GapCVP`
would waste a level on the root. Runs shorter than `minGroup` are absorbed into their
predecessor; adjacent runs that end up with equal keys are coalesced; runs longer than
`maxGroup` are split into near-equal numbered parts. Chapters then greedily pack whole
groups up to `maxPerChapter` declarations (a single oversized group still gets its own
chapter — groups are never split across chapter modules).
-/

namespace VersoBlueprint.ShowcaseGen

open Lean

/-! ## Small string helpers

Deliberately implemented over `String.data` rather than the `String.take`/`Substring`
API so the generator's output cannot drift with a core-library signature change.
-/

/-- The first `n` characters of `s`. -/
def truncateStr (n : Nat) (s : String) : String :=
  if s.length ≤ n then s else String.ofList (s.toList.take n)

/-- `s` with its first character upper-cased; the rest is left alone so acronyms survive. -/
def capitalizeStr (s : String) : String :=
  match s.toList with
  | [] => ""
  | c :: cs => String.ofList (c.toUpper :: cs)

/-- Split an identifier chunk on camel-case and digit boundaries: `GapCVP` ↦ `#["Gap", "CVP"]`. -/
def splitCamel (w : String) : Array String := Id.run do
  let cs := w.toList.toArray
  let mut out : Array String := #[]
  let mut cur : Array Char := #[]
  for i in [0:cs.size] do
    let c := cs[i]!
    let boundary :=
      if i = 0 then false
      else
        let p := cs[i-1]!
        let nextIsLower := (cs[i+1]?.map (·.isLower)).getD false
        (c.isUpper && (p.isLower || p.isDigit))
          || (c.isUpper && p.isUpper && nextIsLower)
          || (c.isDigit && !p.isDigit)
          || (!c.isDigit && p.isDigit && !c.isUpper)
    if boundary && !cur.isEmpty then
      out := out.push (String.ofList cur.toList)
      cur := #[]
    cur := cur.push c
  if !cur.isEmpty then
    out := out.push (String.ofList cur.toList)
  return out

/-- Turn one identifier into display words: `palette_blockCert` ↦ `"Palette Block Cert"`. -/
def humanizeIdent (s : String) : String :=
  let chunks := (s.splitOn "_").filter (· != "")
  let words := chunks.foldl (init := #[]) fun acc chunk => acc ++ splitCamel chunk
  String.intercalate " " (words.toList.map capitalizeStr)

/-- Turn a dotted namespace path into a display title: `A.BC` ↦ `"A B C"`. -/
def humanizePath (path : String) : String :=
  let parts := (path.splitOn ".").filter (· != "")
  String.intercalate " " (parts.map humanizeIdent)

/-- A Lean-identifier-safe CamelCase slug for a display title. Always starts with a letter. -/
def identSlug (title : String) : String :=
  let words := (title.splitOn " ").filter (· != "")
  let joined := String.join (words.map fun w => capitalizeStr (String.ofList (w.toList.filter Char.isAlphanum)))
  let joined := truncateStr 48 joined
  match joined.toList with
  | [] => "Group"
  | c :: _ => if c.isAlpha then joined else "G" ++ joined

/-- Zero-padded three-digit index (`7 ↦ "007"`), widening past 999 rather than truncating. -/
def pad3 (n : Nat) : String :=
  let s := toString n
  if s.length ≥ 3 then s else String.ofList (List.replicate (3 - s.length) '0') ++ s

/-! ## Roster -/

/-- One public declaration of the subject module, as the generator sees it.

`name` is the fully-qualified Lean name; `nsComponents` its namespace (the name minus
its final component). Source positions are 1-based lines / 0-based columns, exactly as
`Lean.DeclarationRange` reports them. -/
structure RosterEntry where
  name : String
  nsComponents : Array String
  /-- Theorem-like declarations (`thmInfo`) get an informal-proof slot; definitions do not. -/
  isTheoremLike : Bool
  line : Nat := 0
  col : Nat := 0
  endLine : Nat := 0
  endCol : Nat := 0
  /-- The subject module the declaration was compiled from. -/
  moduleName : String := ""
  /-- Repository-relative source path, when derivable. -/
  sourcePath : String := ""
  docstring? : Option String := none
deriving Inhabited, Repr

/-- Namespace components of a dotted name (everything before the final component). -/
def namespaceComponentsOf (name : String) : Array String :=
  let parts := (name.splitOn ".").filter (· != "")
  match parts with
  | [] => #[]
  | _ => (parts.dropLast).toArray

/-- Build a roster entry from a name and kind alone — the shape the grouping tests use. -/
def mkRosterEntry (name : String) (isTheoremLike : Bool := true) : RosterEntry :=
  { name, nsComponents := namespaceComponentsOf name, isTheoremLike }

/-- Length of the longest common prefix of two component arrays. -/
def commonPrefixLength (a b : Array String) : Nat := Id.run do
  let mut n := 0
  for i in [0 : min a.size b.size] do
    if a[i]! == b[i]! then n := n + 1 else break
  return n

/-- The namespace prefix shared by every declaration in the roster.

For a single-namespace corpus this is the whole namespace; for a roster with
declarations in `A.B` and `A.C` it is `A`. Empty for an empty roster. -/
def rosterCommonNamespace (roster : Array RosterEntry) : Array String :=
  match roster[0]? with
  | none => #[]
  | some first =>
    let n := roster.foldl (init := first.nsComponents.size) fun acc e =>
      min acc (commonPrefixLength first.nsComponents e.nsComponents)
    first.nsComponents.extract 0 n

/-- The grouping key of a declaration: `nsDepth` namespace components past the shared prefix. -/
def groupKeyOf (common : Nat) (nsDepth : Nat) (e : RosterEntry) : Array String :=
  let ns := e.nsComponents
  if ns.size ≤ common then #[]
  else ns.extract common (min ns.size (common + nsDepth))

/-! ## Groups and chapters -/

/-- A contiguous block of roster entries presented as one `:::group`. -/
structure Group where
  /-- The blueprint label, e.g. `grp:PaletteBlockCertificate`. -/
  label : String
  /-- Display title, e.g. `Palette Block Certificate`. -/
  title : String
  /-- Index of the first roster entry in the group. -/
  first : Nat
  /-- Number of roster entries in the group. -/
  count : Nat
deriving Inhabited, Repr

/-- A generated chapter module holding one or more whole groups. -/
structure Chapter where
  /-- 1-based chapter number. -/
  index : Nat
  title : String
  /-- Module-name suffix, e.g. `C001_MulticolourTriangleRamsey`. -/
  moduleSuffix : String
  groups : Array Group
deriving Inhabited, Repr

/-- Total declaration count of a chapter. -/
def Chapter.declCount (c : Chapter) : Nat :=
  c.groups.foldl (init := 0) fun acc g => acc + g.count

/-- A run of consecutive roster entries sharing a grouping key, before merge/split. -/
private structure Run where
  key : Array String
  first : Nat
  count : Nat
deriving Inhabited

/-- Segment the roster wherever the grouping key changes. -/
private def segmentRuns (common nsDepth : Nat) (roster : Array RosterEntry) : Array Run := Id.run do
  let mut runs : Array Run := #[]
  for i in [0:roster.size] do
    let key := groupKeyOf common nsDepth roster[i]!
    match runs.back? with
    | some last =>
      if last.key == key then
        runs := runs.set! (runs.size - 1) { last with count := last.count + 1 }
      else
        runs := runs.push { key, first := i, count := 1 }
    | none => runs := runs.push { key, first := i, count := 1 }
  return runs

/-- Absorb runs shorter than `minGroup` into their predecessor (or, for a leading short
run, into their successor), then coalesce adjacent runs that ended up with equal keys. -/
private def mergeSmallRuns (minGroup : Nat) (runs : Array Run) : Array Run := Id.run do
  if runs.size ≤ 1 then return runs
  -- Absorb forward into the predecessor; a short *leading* run has none, so it is
  -- carried until the first run that survives, which then absorbs it.
  let mut out : Array Run := #[]
  for run in runs do
    match out.back? with
    | some last =>
      if run.count < minGroup || last.count < minGroup then
        out := out.set! (out.size - 1) { last with count := last.count + run.count }
      else
        out := out.push run
    | none => out := out.push run
  -- Coalesce equal-key neighbours (two stretches of the same namespace separated only
  -- by an absorbed run should read as one group, not as `Foo` and `Foo.2`).
  let mut coalesced : Array Run := #[]
  for run in out do
    match coalesced.back? with
    | some last =>
      if last.key == run.key then
        coalesced := coalesced.set! (coalesced.size - 1) { last with count := last.count + run.count }
      else
        coalesced := coalesced.push run
    | none => coalesced := coalesced.push run
  return coalesced

/-- Split runs longer than `maxGroup` into near-equal parts. -/
private def splitLargeRuns (maxGroup : Nat) (runs : Array Run) : Array (Run × Option Nat) := Id.run do
  let maxGroup := max maxGroup 1
  let mut out : Array (Run × Option Nat) := #[]
  for run in runs do
    if run.count ≤ maxGroup then
      out := out.push (run, none)
    else
      let parts := (run.count + maxGroup - 1) / maxGroup
      let base := run.count / parts
      let extra := run.count % parts
      let mut offset := run.first
      for p in [0:parts] do
        let size := base + (if p < extra then 1 else 0)
        out := out.push ({ run with first := offset, count := size }, some (p + 1))
        offset := offset + size
  return out

/-- Base label text for a run's key: the dotted key, or the last shared-prefix component
when the key is empty (the declarations that sit directly in the shared namespace). -/
private def runLabelBase (commonPrefix : Array String) (key : Array String) : String :=
  if key.isEmpty then
    match commonPrefix.back? with
    | some c => c
    | none => "Root"
  else
    String.intercalate "." key.toList

/-- First unused variant of `base`, disambiguating with a numeric suffix. -/
private def freshLabel (used : Std.HashSet String) (base : String) : String := Id.run do
  if !used.contains base then return base
  for n in [2:10000] do
    let candidate := base ++ "." ++ toString n
    unless used.contains candidate do return candidate
  return base ++ ".dup"

/-- Build the group list: segment, merge, coalesce, split, then label uniquely. -/
def buildGroups (minGroup maxGroup nsDepth : Nat) (roster : Array RosterEntry) : Array Group := Id.run do
  if roster.isEmpty then return #[]
  let commonPrefix := rosterCommonNamespace roster
  let runs := segmentRuns commonPrefix.size nsDepth roster
  let runs := mergeSmallRuns minGroup runs
  let parts := splitLargeRuns maxGroup runs
  let mut used : Std.HashSet String := {}
  let mut groups : Array Group := #[]
  for (run, part?) in parts do
    let base := runLabelBase commonPrefix run.key
    let base := match part? with
      | some p => base ++ "." ++ toString p
      | none => base
    -- Distinct runs can still collide (two split runs of the same namespace, or a
    -- coalescing pass that left two equal keys non-adjacent). Bump until free.
    let candidate := freshLabel used base
    used := used.insert candidate
    groups := groups.push {
      label := "grp:" ++ candidate
      title := humanizePath candidate
      first := run.first
      count := run.count
    }
  return groups

/-- Greedily pack whole groups into chapters of at most `maxPerChapter` declarations.
A group larger than the cap still gets a chapter of its own — groups are never split. -/
def packChapters (maxPerChapter : Nat) (groups : Array Group) : Array Chapter := Id.run do
  let cap := max maxPerChapter 1
  let mut chapters : Array (Array Group) := #[]
  let mut current : Array Group := #[]
  let mut size := 0
  for g in groups do
    if !current.isEmpty && size + g.count > cap then
      chapters := chapters.push current
      current := #[g]
      size := g.count
    else
      current := current.push g
      size := size + g.count
  if !current.isEmpty then chapters := chapters.push current
  let mut out : Array Chapter := #[]
  for i in [0:chapters.size] do
    let gs := chapters[i]!
    let title :=
      if gs.size == 1 then (gs[0]!).title
      else (gs[0]!).title ++ " to " ++ (gs[gs.size - 1]!).title
    out := out.push {
      index := i + 1
      title
      moduleSuffix := "C" ++ pad3 (i + 1) ++ "_" ++ identSlug title
      groups := gs
    }
  return out

/-! ## Node labels -/

/-- The blueprint label of a declaration node. Deliberately keeps the `decl:` prefix so
node labels can never collide with the `grp:` group labels. -/
def declLabel (name : String) : String := "decl:" ++ name

/-! ## Source rendering

Every emitter below is a total function into `String`; nothing consults the clock, the
filesystem or a hash, so re-running the generator on an unchanged olean reproduces the
tree byte for byte.
-/

/-- Generator configuration that reaches the emitted sources. -/
structure RenderConfig where
  /-- Module name of the subject formalization, e.g. `MulticolorTriangleRamsey`. -/
  subjectModule : String
  /-- Document title of `Contents.lean`. -/
  projectTitle : String
  /-- `shortTitle` metadatum of `Contents.lean`. -/
  shortTitle : String
  /-- Copyright holder for the file headers. -/
  copyright : String
  /-- `Authors:` line of the file headers, and the `%%%` author list. -/
  authors : Array String
  /-- Path (relative to the repository root) of the formalization metadata file. -/
  formalizationYaml : String
  /-- Node labels for `{blueprint_dashboard (featured := …)}`; empty ⇒ no argument. -/
  featured : Array String
deriving Inhabited

/-- The Apache-2.0 file header every generated source carries. -/
def fileHeader (cfg : RenderConfig) : String :=
  "/-\nCopyright (c) 2026 " ++ cfg.copyright ++ ". All rights reserved.\n" ++
  "Released under Apache 2.0 license as described in the file LICENSE.\n" ++
  "Authors: " ++ String.intercalate ", " cfg.authors.toList ++ "\n-/\n"

private def generatedNotice : String :=
  "-- Generated by `showcase-gen`. Statement and proof prose is filled in by the\n" ++
  "-- exposition pipeline; regenerating rewrites this file from the subject module.\n"

/-- The placeholder that occupies an unfilled statement slot. -/
def statementPlaceholder : String := "*Statement prose pending.*"

/-- The placeholder that occupies an unfilled proof slot. -/
def proofPlaceholder : String := "*Proof prose pending.*"

/-- Render one chapter module. -/
def renderChapter (cfg : RenderConfig) (roster : Array RosterEntry) (ch : Chapter) : String := Id.run do
  let mut out := fileHeader cfg
  out := out ++ "/-\n" ++ cfg.projectTitle ++ " — chapter " ++ toString ch.index ++ ": " ++
    ch.title ++ ".\n-/\n" ++ generatedNotice ++ "\n"
  out := out ++ "import Verso\nimport VersoManual\nimport VersoBlueprint\n"
  out := out ++ "import Macros\nimport Bibliography\nimport " ++ cfg.subjectModule ++ "\n\n"
  out := out ++ "open Verso.Genre\nopen Verso.Genre.Manual hiding citep citet citehere\nopen Informal\n\n"
  out := out ++ "set_option doc.verso true\nset_option pp.rawOnError true\n\n"
  out := out ++ "#doc (Manual) \"" ++ ch.title ++ "\" =>\n"
  for g in ch.groups do
    out := out ++ "\n:::group \"" ++ g.label ++ "\"\n" ++ g.title ++ "\n:::\n"
    for i in [g.first : g.first + g.count] do
      let e := roster[i]!
      let label := declLabel e.name
      let kind := if e.isTheoremLike then "theorem" else "definition"
      out := out ++ "\n:::" ++ kind ++ " \"" ++ label ++ "\" (lean := \"" ++ e.name ++
        "\") (parent := \"" ++ g.label ++ "\")\n" ++ statementPlaceholder ++ "\n:::\n"
      if e.isTheoremLike then
        out := out ++ "\n:::proof \"" ++ label ++ "\"\n" ++ proofPlaceholder ++ "\n:::\n"
  return out

/-- Render the `Chapters.lean` aggregator. -/
def renderChaptersRoot (cfg : RenderConfig) (chapters : Array Chapter) : String := Id.run do
  let mut out := fileHeader cfg ++ generatedNotice
  for ch in chapters do
    out := out ++ "import Chapters." ++ ch.moduleSuffix ++ "\n"
  return out

/-- Render `Contents.lean` — the top-level document. -/
def renderContents (cfg : RenderConfig) (chapters : Array Chapter) : String := Id.run do
  let mut out := fileHeader cfg
  out := out ++ "/-\n" ++ cfg.projectTitle ++ " — top-level blueprint document.\n-/\n\n"
  out := out ++ "import Verso\nimport VersoManual\nimport VersoBlueprint\n"
  out := out ++ "import VersoBlueprint.Commands.Graph\nimport VersoBlueprint.Commands.Summary\n"
  out := out ++ "import VersoBlueprint.Commands.Bibliography\nimport VersoBlueprint.Commands.Formalization\n\n"
  out := out ++ "import Contents.TeXPrelude\nimport Authors\nimport Bibliography\n"
  for ch in chapters do
    out := out ++ "import Chapters." ++ ch.moduleSuffix ++ "\n"
  out := out ++ "\nopen Verso.Genre\nopen Verso.Genre.Manual hiding citep citet citehere\nopen Informal\n\n"
  out := out ++ "set_option doc.verso true\nset_option pp.rawOnError true\n\n"
  out := out ++ "#doc (Manual) \"" ++ cfg.projectTitle ++ "\" =>\n\n"
  out := out ++ "%%%\nshortTitle := \"" ++ cfg.shortTitle ++ "\"\nauthors := [" ++
    String.intercalate ", " (cfg.authors.toList.map (fun a => "\"" ++ a ++ "\"")) ++ "]\n%%%\n\n"
  if cfg.featured.isEmpty then
    out := out ++ "{blueprint_dashboard}\n"
  else
    out := out ++ "{blueprint_dashboard (featured := \"" ++
      String.intercalate ", " cfg.featured.toList ++ "\")}\n"
  for ch in chapters do
    out := out ++ "\n{include 0 Chapters." ++ ch.moduleSuffix ++ "}\n"
  out := out ++ "\n{blueprint_graph}\n\n{blueprint_summary}\n\n"
  out := out ++ "{blueprint_formalization \"" ++ cfg.formalizationYaml ++ "\"}\n\n"
  out := out ++ "{blueprint_trust_model}\n\n{blueprint_bibliography}\n"
  return out

/-- A stable author id: the display name lower-cased with non-alphanumerics dropped. -/
def authorId (name : String) : String :=
  let s := (String.ofList (name.toList.filter Char.isAlphanum)).toLower
  if s.isEmpty then "author" else truncateStr 32 s

/-- Render `Authors.lean`. -/
def renderAuthors (cfg : RenderConfig) : String := Id.run do
  let mut out := fileHeader cfg
  out := out ++ "/-\n" ++ cfg.projectTitle ++ " — author bylines.\n-/\n\n"
  out := out ++ "import Verso\nimport VersoManual\nimport VersoBlueprint\n\n"
  out := out ++ "open Verso.Genre\nopen Verso.Genre.Manual\nopen Informal\n\n"
  out := out ++ "set_option doc.verso true\n\n"
  out := out ++ "#doc (Manual) \"Authors\" =>\n"
  for a in cfg.authors do
    out := out ++ "\n:::author \"" ++ authorId a ++ "\" (name := \"" ++ a ++ "\")\n:::\n"
  return out

/-- Render `Macros.lean`. -/
def renderMacros (cfg : RenderConfig) : String :=
  fileHeader cfg ++ "import Contents.TeXPrelude\n"

/-- Render `Contents/TeXPrelude.lean`. -/
def renderTeXPrelude (cfg : RenderConfig) : String :=
  fileHeader cfg ++
  "import Verso\nimport VersoManual\nimport VersoBlueprint\n\nopen Informal\n\n" ++
  "tex_prelude r#\"\n" ++
  "% KaTeX in the current harness is missing these shorthands.\n" ++
  "% (\\R and \\Z are already builtin as \\mathbb{R} / \\mathbb{Z}, so do not redefine them.)\n" ++
  "\\newcommand{\\Q}{\\mathbb{Q}}\n\\newcommand{\\C}{\\mathbb{C}}\n\"#\n"

/-- Render `Bibliography.lean` (an empty bibliography the prose pipeline can extend). -/
def renderBibliography (cfg : RenderConfig) : String :=
  fileHeader cfg ++
  "/-\n" ++ cfg.projectTitle ++ " — bibliography.\n-/\n\n" ++
  "import VersoManual.Bibliography\nimport VersoBlueprint.Cite\n\n" ++
  "open Verso.Genre.Manual.Bibliography\n"

/-- Render `Main.lean` — the site-generator entry point. -/
def renderMain (cfg : RenderConfig) : String :=
  fileHeader cfg ++
  "/-\n" ++ cfg.projectTitle ++ " — site generator entrypoint.\n-/\n\n" ++
  "import Std.Data.HashMap\nimport VersoManual\nimport VersoBlueprint.Macros\n" ++
  "import VersoBlueprint.PreviewManifest\nimport VersoBlueprint.Main\nimport Contents\n\n" ++
  "open Verso Doc\nopen Verso.Genre Manual\n\nopen Std (HashMap)\n\n" ++
  "def htmlAssets : HtmlAssets where\n  features := .all\n  extraCss := {}\n" ++
  "  extraJs := [tex_prelude_table_js%, Informal.Macros.blueprintMathJs]\n" ++
  "  extraJsFiles := {}\n  extraCssFiles := {}\n  extraDataFiles := {}\n  licenseInfo := {}\n\n" ++
  "def htmlConfig : HtmlConfig where\n  toHtmlAssets := htmlAssets\n  htmlDepth := 1\n" ++
  "  extraHead : Array Output.Html := #[]\n\n" ++
  "def outputConfig : OutputConfig where\n  emitTeX := false\n  emitHtmlSingle := .no\n" ++
  "  emitHtmlMulti := .immediately\n\n" ++
  "def config : Config where\n  toHtmlConfig := htmlConfig\n  toOutputConfig := outputConfig\n\n" ++
  "def renderConfig : RenderConfig where\n  toConfig := config\n\n" ++
  "def main (args : List String) : IO UInt32 :=\n" ++
  "  Informal.PreviewManifest.blueprintMainWithFeatures\n" ++
  "    (%doc Contents)\n    args\n" ++
  "    (extensionImpls := by exact extension_impls%)\n" ++
  "    (config := renderConfig)\n    (extraSteps := [])\n"

/-! ## Generation manifest

The sidecar the exposition pipeline's extract script reads: for every node, where its
prose slot lives (chapter file + label) and where its Lean source lives (module +
declaration range). Recorded here rather than re-derived later so the prose pipeline
never has to re-open the subject environment.
-/

/-- `Nat` as JSON; `Json.num` wants a `JsonNumber`, and `ToJson` is the shortest safe road. -/
private def jnat (n : Nat) : Json := toJson n

private def entryJson (chapterOf : String) (groupOf : String) (e : RosterEntry) : Json :=
  let base : List (String × Json) := [
    ("name", .str e.name),
    ("kind", .str (if e.isTheoremLike then "theorem" else "definition")),
    ("label", .str (declLabel e.name)),
    ("group", .str groupOf),
    ("chapter", .str chapterOf),
    ("hasProofSlot", .bool e.isTheoremLike),
    ("module", .str e.moduleName),
    ("sourcePath", .str e.sourcePath),
    ("startLine", jnat e.line),
    ("startColumn", jnat e.col),
    ("endLine", jnat e.endLine),
    ("endColumn", jnat e.endCol)
  ]
  match e.docstring? with
  | some doc => Json.mkObj (base ++ [("docstring", .str doc)])
  | none => Json.mkObj base

/-- The `generated-manifest.json` payload. -/
def manifestJson (cfg : RenderConfig) (roster : Array RosterEntry)
    (groups : Array Group) (chapters : Array Chapter)
    (flags : List (String × Json)) : Json := Id.run do
  -- group label -> chapter file, so decl entries can name both.
  let mut groupChapter : Std.HashMap String String := {}
  let mut chapterJson : Array Json := #[]
  for ch in chapters do
    let file := "Chapters/" ++ ch.moduleSuffix ++ ".lean"
    for g in ch.groups do
      groupChapter := groupChapter.insert g.label file
    chapterJson := chapterJson.push <| Json.mkObj [
      ("index", jnat ch.index),
      ("title", .str ch.title),
      ("module", .str ("Chapters." ++ ch.moduleSuffix)),
      ("file", .str file),
      ("declCount", jnat ch.declCount),
      ("groups", .arr (ch.groups.map (fun g => Json.str g.label)))
    ]
  let groupJson := groups.map fun g =>
    Json.mkObj [
      ("label", .str g.label),
      ("title", .str g.title),
      ("chapter", .str (groupChapter.getD g.label "")),
      ("declCount", jnat g.count),
      ("firstDecl", jnat g.first)
    ]
  let mut declJson : Array Json := #[]
  for g in groups do
    let file := groupChapter.getD g.label ""
    for i in [g.first : g.first + g.count] do
      declJson := declJson.push (entryJson file g.label roster[i]!)
  return Json.mkObj [
    ("schemaVersion", jnat 1),
    ("generator", .str "showcase-gen"),
    ("subjectModule", .str cfg.subjectModule),
    ("projectTitle", .str cfg.projectTitle),
    ("flags", Json.mkObj flags),
    ("declCount", jnat roster.size),
    ("groupCount", jnat groups.size),
    ("chapterCount", jnat chapters.size),
    ("chapters", .arr chapterJson),
    ("groups", .arr groupJson),
    ("decls", .arr declJson)
  ]

end VersoBlueprint.ShowcaseGen
