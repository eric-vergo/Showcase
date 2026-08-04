/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.ShowcaseGen

/-!
# `showcase-gen` grouping and rendering

Everything the skeleton generator does after the declaration roster leaves the
environment is a pure function, so it is testable here on synthetic rosters — no
subject corpus, no Lake dependency, no build of a presentation repo required.

The rosters below mirror the three shapes the corpus survey found: one namespace for
the whole module (grouping must fall back to size bands), a small nested namespace
interrupting a long run (must not fragment the module into `Foo` / `Aux` / `Foo.2`
under the default `--min-group`), and namespaces deep enough that `--ns-depth` matters.
-/

namespace VersoBlueprintTests.ShowcaseGenTests

open VersoBlueprint.ShowcaseGen

/-! ## String helpers -/

/-- info: "Multicolour Triangle Ramsey" -/
#guard_msgs in
#eval humanizeIdent "MulticolourTriangleRamsey"

/-- info: "Gap CVP" -/
#guard_msgs in
#eval humanizeIdent "GapCVP"

/-- info: "Erdos 183 Explicit" -/
#guard_msgs in
#eval humanizeIdent "erdos_183_explicit"

#guard humanizePath "Alpha.BetaGamma" == "Alpha Beta Gamma"
#guard identSlug "Palette Block Certificate" == "PaletteBlockCertificate"
#guard identSlug "Multicolour Triangle Ramsey 2" == "MulticolourTriangleRamsey2"
#guard pad3 7 == "007"
#guard pad3 42 == "042"
#guard pad3 1234 == "1234"
#guard declLabel "A.b" == "decl:A.b"

/-! ## Roster shapes -/

/-- `count` declarations in `ns`, named `d<start>` … so every name is distinct. -/
private def block (ns : String) (start count : Nat) : Array RosterEntry :=
  (Array.range count).map fun i => mkRosterEntry s!"{ns}.d{start + i}"

private def labelsOf (gs : Array Group) : Array String := gs.map (·.label)
private def countsOf (gs : Array Group) : Array Nat := gs.map (·.count)

/-- A module with one namespace throughout: the whole roster shares its prefix, so the
grouping key is empty everywhere and the group is named after the shared namespace. -/
private def flatRoster : Array RosterEntry := block "Erdos.MTR" 0 60

#guard rosterCommonNamespace flatRoster == #["Erdos", "MTR"]
#guard labelsOf (buildGroups 20 150 2 flatRoster) == #["grp:MTR"]
#guard countsOf (buildGroups 20 150 2 flatRoster) == #[60]

/-- The pilot's real shape: a long run, a short nested namespace, then the long run
resumes. Under the default `--min-group 20` the short run is absorbed and the two
stretches coalesce into a single group — the alternative (`MTR`, `Aux`, `MTR.2`) would
put two thirds of the module behind a group whose name says "part 2". -/
private def interruptedRoster : Array RosterEntry :=
  block "Erdos.MTR" 0 40 ++ block "Erdos.MTR.Aux" 100 4 ++ block "Erdos.MTR" 200 95

#guard rosterCommonNamespace interruptedRoster == #["Erdos", "MTR"]
#guard labelsOf (buildGroups 20 150 2 interruptedRoster) == #["grp:MTR"]
#guard countsOf (buildGroups 20 150 2 interruptedRoster) == #[139]

/- The same roster with a permissive `--min-group` keeps the nested namespace as its
own group; the resumed run cannot reuse the label, so it becomes `MTR.2`. -/
#guard labelsOf (buildGroups 3 150 2 interruptedRoster) == #["grp:MTR", "grp:Aux", "grp:MTR.2"]
#guard countsOf (buildGroups 3 150 2 interruptedRoster) == #[40, 4, 95]

/-- A leading run shorter than `--min-group` has no predecessor to merge into, so it is
absorbed by the run that follows it rather than surviving as a tiny group. -/
private def shortLeadRoster : Array RosterEntry :=
  block "Erdos.MTR.Aux" 0 3 ++ block "Erdos.MTR" 100 40

#guard labelsOf (buildGroups 20 150 2 shortLeadRoster) == #["grp:Aux"]
#guard countsOf (buildGroups 20 150 2 shortLeadRoster) == #[43]

/- Runs longer than `--max-group` split into near-equal numbered parts. -/
#guard labelsOf (buildGroups 20 150 2 (block "Erdos.MTR" 0 380))
  == #["grp:MTR.1", "grp:MTR.2", "grp:MTR.3"]
#guard countsOf (buildGroups 20 150 2 (block "Erdos.MTR" 0 380)) == #[127, 127, 126]

/-- `--ns-depth` counts components *past* the shared prefix, so a corpus whose modules
all sit under one long namespace still gets useful keys. -/
private def deepRoster : Array RosterEntry :=
  block "P.Q.Alpha.One" 0 30 ++ block "P.Q.Alpha.Two" 100 30 ++ block "P.Q.Beta.One" 200 30

#guard rosterCommonNamespace deepRoster == #["P", "Q"]
#guard labelsOf (buildGroups 20 150 1 deepRoster) == #["grp:Alpha", "grp:Beta"]
#guard countsOf (buildGroups 20 150 1 deepRoster) == #[60, 30]
#guard labelsOf (buildGroups 20 150 2 deepRoster)
  == #["grp:Alpha.One", "grp:Alpha.Two", "grp:Beta.One"]

/- Group titles humanize the label path. -/
#guard (buildGroups 3 150 2 interruptedRoster).map (·.title) == #["MTR", "Aux", "MTR 2"]

/-! ## Chapter packing -/

private def gs (sizes : List Nat) : Array Group :=
  (sizes.toArray.zipIdx).map fun (n, i) =>
    { label := s!"grp:G{i}", title := s!"G {i}", first := 0, count := n }

#guard (packChapters 100 (gs [60, 60, 30])).map (·.declCount) == #[60, 90]
#guard (packChapters 100 (gs [60, 60, 30])).map (·.moduleSuffix) == #["C001_G0", "C002_G1ToG2"]
/- A group bigger than the cap still gets a chapter to itself — groups are never split
across chapter modules, so a `parent :=` reference never crosses a file boundary. -/
#guard (packChapters 100 (gs [139])).map (·.declCount) == #[139]
#guard (packChapters 100 (gs [40, 139, 20])).map (·.declCount) == #[40, 139, 20]
#guard (packChapters 100 #[]).size == 0

/-! ## Rendering

The emitters are checked for the load-bearing contract only: the node directive line the
splicer keys on, the placeholder lines it replaces, and the fact that no `uses :=`
argument is ever written (edges come from `verso.blueprint.autoDeps`, not from the
generator's guesses).
-/

private def demoCfg : RenderConfig := {
  subjectModule := "Subject"
  projectTitle := "Demo"
  shortTitle := "Demo"
  copyright := "Eric Vergo"
  authors := #["Eric Vergo"]
  formalizationYaml := "formalization.yaml"
  featured := #[]
}

private def demoRoster : Array RosterEntry :=
  #[mkRosterEntry "Erdos.MTR.thm_a" (isTheoremLike := true),
    mkRosterEntry "Erdos.MTR.def_b" (isTheoremLike := false)]

private def demoChapter : Chapter :=
  (packChapters 100 (buildGroups 1 150 2 demoRoster))[0]!

private def demoChapterText : String := renderChapter demoCfg demoRoster demoChapter

#guard (demoChapterText.splitOn "(uses :=").length == 1
#guard (demoChapterText.splitOn
  ":::theorem \"decl:Erdos.MTR.thm_a\" (lean := \"Erdos.MTR.thm_a\") (parent := \"grp:MTR\")").length == 2
#guard (demoChapterText.splitOn
  ":::definition \"decl:Erdos.MTR.def_b\" (lean := \"Erdos.MTR.def_b\") (parent := \"grp:MTR\")").length == 2
/- Exactly one proof slot: the theorem gets one, the definition does not. -/
#guard (demoChapterText.splitOn ":::proof \"decl:Erdos.MTR.thm_a\"").length == 2
#guard (demoChapterText.splitOn ":::proof \"decl:Erdos.MTR.def_b\"").length == 1
#guard (demoChapterText.splitOn statementPlaceholder).length == 3
#guard (demoChapterText.splitOn proofPlaceholder).length == 2
#guard (demoChapterText.splitOn "import Subject").length == 2
#guard demoChapterText.endsWith "\n"

/- Rendering is a pure function of its inputs, which is what makes the generator's
run-twice byte-identity property hold. -/
#guard renderChapter demoCfg demoRoster demoChapter == demoChapterText

private def demoContents : String := renderContents demoCfg #[demoChapter]

#guard (demoContents.splitOn "{blueprint_dashboard}").length == 2
#guard (demoContents.splitOn "{blueprint_trust_model}").length == 2
#guard (demoContents.splitOn "{blueprint_formalization \"formalization.yaml\"}").length == 2
#guard (demoContents.splitOn s!"\{include 0 Chapters.{demoChapter.moduleSuffix}}").length == 2

#guard ((renderContents { demoCfg with featured := #["decl:A", "decl:B"] } #[demoChapter]).splitOn
  "{blueprint_dashboard (featured := \"decl:A, decl:B\")}").length == 2

end VersoBlueprintTests.ShowcaseGenTests
