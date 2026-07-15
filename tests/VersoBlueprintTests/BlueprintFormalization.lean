/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.FormalizationYaml
import VersoBlueprint.Commands.TrustStrip

/-!
Tests for the `formalization.yaml` subset parser (`Informal.FormalizationYaml`)
and the dashboard trust-strip HTML builders (`Informal.Commands.trust*`).
-/

namespace Verso.VersoBlueprintTests.BlueprintFormalization

open Lean
open Informal
open Informal.Commands

private def hasSubstr (s needle : String) : Bool :=
  (s.splitOn needle).length > 1

private def countSubstr (s needle : String) : Nat :=
  (s.splitOn needle).length - 1

private def parsed! (s : String) : Json :=
  match FormalizationYaml.parse s with
  | .ok j => j
  | .error e => Json.str s!"PARSE ERROR: {e}"

private def at? (j : Json) : List String → Option Json
  | [] => some j
  | k :: rest =>
    match j.getObjVal? k with
    | .ok v => at? v rest
    | .error _ => none

private def strAt? (j : Json) (path : List String) : Option String :=
  match at? j path with
  | some (Json.str s) => some s
  | _ => none

private def natAt? (j : Json) (path : List String) : Option Nat :=
  (at? j path).bind fun v => (fromJson? (α := Nat) v).toOption

private def intAt? (j : Json) (path : List String) : Option Int :=
  (at? j path).bind fun v => (fromJson? (α := Int) v).toOption

private def boolAt? (j : Json) (path : List String) : Option Bool :=
  match at? j path with
  | some (Json.bool b) => some b
  | _ => none

private def isNullAt (j : Json) (path : List String) : Bool :=
  match at? j path with
  | some Json.null => true
  | _ => false

private def arrAt (j : Json) (path : List String) : Array Json :=
  match at? j path with
  | some (Json.arr a) => a
  | _ => #[]

private def errorOf (s : String) : String :=
  match FormalizationYaml.parse s with
  | .ok _ => ""
  | .error e => e

/-! ### Parser: scalars, comments, quoting, inline lists -/

private def yamlScalars := r##"# full-line comment
version: "v0.3"
count: 42
neg: -7
flag: true
off: false
empty:
nothing: null
tilde: ~
plain: hello world   # trailing comment
quoted: "a # hash inside: kept"
single: 'it''s fine'
nums: [1, 2, 3]
words: ["a b", c]
empty_list: []
"##

/-- info: true -/
#guard_msgs in
#eval
  let doc := parsed! yamlScalars
  strAt? doc ["version"] == some "v0.3" &&
  natAt? doc ["count"] == some 42 &&
  intAt? doc ["neg"] == some (-7) &&
  boolAt? doc ["flag"] == some true &&
  boolAt? doc ["off"] == some false &&
  isNullAt doc ["empty"] &&
  isNullAt doc ["nothing"] &&
  isNullAt doc ["tilde"] &&
  strAt? doc ["plain"] == some "hello world" &&
  strAt? doc ["quoted"] == some "a # hash inside: kept" &&
  strAt? doc ["single"] == some "it's fine"

/-- info: true -/
#guard_msgs in
#eval
  let doc := parsed! yamlScalars
  (arrAt doc ["nums"]).size == 3 &&
  ((arrAt doc ["nums"])[1]?.bind fun v => (fromJson? (α := Nat) v).toOption) == some 2 &&
  (arrAt doc ["words"])[0]? == some (Json.str "a b") &&
  (arrAt doc ["words"])[1]? == some (Json.str "c") &&
  (arrAt doc ["empty_list"]).size == 0

/-! ### Parser: nested maps, block lists, item maps -/

private def yamlNesting := r##"project:
  name: "X"
  meta:
    license: "MIT"
authors:
  - "Eric Vergo"
  - Claude
items:
  - title: "A"
    id: "https://example.org"
  - title: "B"
    type: spec
"##

/-- info: true -/
#guard_msgs in
#eval
  let doc := parsed! yamlNesting
  strAt? doc ["project", "name"] == some "X" &&
  strAt? doc ["project", "meta", "license"] == some "MIT" &&
  (arrAt doc ["authors"]).size == 2 &&
  (arrAt doc ["authors"])[1]? == some (Json.str "Claude") &&
  (arrAt doc ["items"]).size == 2 &&
  ((arrAt doc ["items"])[0]?.bind fun it => strAt? it ["id"]) == some "https://example.org" &&
  ((arrAt doc ["items"])[1]?.bind fun it => strAt? it ["type"]) == some "spec"

/-! ### Parser: folded and literal block scalars -/

private def yamlBlocks := r##"folded: >
  a
  b
folded_strip: >-
  a
  b
literal: |-
  a
  b
para: >-
  one
  two

  three
"##

/-- info: true -/
#guard_msgs in
#eval
  let doc := parsed! yamlBlocks
  strAt? doc ["folded"] == some "a b\n" &&
  strAt? doc ["folded_strip"] == some "a b" &&
  strAt? doc ["literal"] == some "a\nb" &&
  strAt? doc ["para"] == some "one two\nthree"

/-! ### Parser: clear line-numbered errors on unsupported constructs -/

/-- info: true -/
#guard_msgs in
#eval
  hasSubstr (errorOf "a: b\n    deep: x") "line 2" &&
  hasSubstr (errorOf "x: {a: 1}") "flow mappings" &&
  hasSubstr (errorOf "a: 1\na: 2") "duplicate key 'a'" &&
  hasSubstr (errorOf "s: >+\n  x") "unsupported block scalar header" &&
  hasSubstr (errorOf "\ta: 1") "tab characters" &&
  hasSubstr (errorOf "a: &anchor") "anchors"

/-! ### Parser: trimmed real-world example (mirrors the a362583 file) -/

private def yamlRealWorld := r##"# formalization.yaml (v0.3)
version: "v0.3"

project:
  name: "A362583 Irrationality"
  authors:
    - "Eric Vergo"
    - "Claude Fable 5 (Anthropic, via Claude Code)"
  license: "CC0-1.0"

sources:
  - title: "A362583 Irrationality — Lean 4 Formalization Specification"
    authors: ["Eric Vergo"]
    id: "prime_race repo, spec.md"
    type: "specification / informal blueprint"
    author_contacted: "n/a"          # self-authored
  - title: "OEIS A362583"
    authors: ["Eric Vergo"]
    id: "https://oeis.org/A362583"

status:
  scope: >-
    Complete. The constant x is irrational, via a non-degeneracy theorem
    for the mod-4 Chebyshev prime race.

    No PNT is needed.
  sorry_count: 0
  axioms: ["propext", "Classical.choice", "Quot.sound"]
  main_results:
    - declaration: "A362583.irrational_x"
      file: "A362583/Main.lean"
      sorry_count: 0
      axioms: ["propext", "Classical.choice", "Quot.sound"]
      comparator_config: "comparator.json"
      literature_dependencies: []    # everything is proved here or in mathlib

automation:
  methods:
    - method: "agent"
      models: ["claude-fable-5"]
      framework: "Claude Code"
      cost:
        wall_time: "~1 day (2026-07-03)"
        spend_usd: "subscription-based usage"
  notes: >-
    Human role: specification and review.

review:
  status: "agent-reviewed"
  reviewers: []

alignment:
  namespace: "A362583"
  statements:
    - source: "§1 definitions"
      lean: "A362583.oddPrime, A362583.bit, A362583.x, A362583.raceSum"
      module: "A362583/Defs.lean"
      status: "proved"
      note: "statement-hygiene: elementary arithmetic only"
    - source: "§2.7 assembly — main theorem"
      lean: "A362583.irrational_x"
      module: "A362583/Main.lean"
      status: "proved"

acknowledgements: >-
  Built on mathlib4 (pinned v4.31.0).
"##

/-- info: true -/
#guard_msgs in
#eval
  let doc := parsed! yamlRealWorld
  strAt? doc ["project", "name"] == some "A362583 Irrationality" &&
  (arrAt doc ["project", "authors"]).size == 2 &&
  (arrAt doc ["project", "authors"])[1]? ==
    some (Json.str "Claude Fable 5 (Anthropic, via Claude Code)") &&
  (arrAt doc ["sources"]).size == 2 &&
  ((arrAt doc ["sources"])[0]?.bind fun s => strAt? s ["author_contacted"]) == some "n/a" &&
  ((arrAt doc ["sources"])[1]?.bind fun s => strAt? s ["id"]) == some "https://oeis.org/A362583"

/-- info: true -/
#guard_msgs in
#eval
  let doc := parsed! yamlRealWorld
  strAt? doc ["status", "scope"] ==
    some "Complete. The constant x is irrational, via a non-degeneracy theorem for the mod-4 Chebyshev prime race.\nNo PNT is needed." &&
  natAt? doc ["status", "sorry_count"] == some 0 &&
  (arrAt doc ["status", "axioms"]).size == 3 &&
  ((arrAt doc ["status", "main_results"])[0]?.bind fun r => strAt? r ["declaration"]) ==
    some "A362583.irrational_x" &&
  ((arrAt doc ["status", "main_results"])[0]?.map fun r => (arrAt r ["literature_dependencies"]).size) ==
    some 0

/-- info: true -/
#guard_msgs in
#eval
  let doc := parsed! yamlRealWorld
  ((arrAt doc ["automation", "methods"])[0]?.bind fun m => strAt? m ["cost", "wall_time"]) ==
    some "~1 day (2026-07-03)" &&
  strAt? doc ["automation", "notes"] == some "Human role: specification and review." &&
  strAt? doc ["review", "status"] == some "agent-reviewed" &&
  (arrAt doc ["review", "reviewers"]).size == 0 &&
  strAt? doc ["alignment", "namespace"] == some "A362583" &&
  (arrAt doc ["alignment", "statements"]).size == 2 &&
  ((arrAt doc ["alignment", "statements"])[0]?.bind fun s => strAt? s ["lean"]).map
    (fun l => countSubstr l ",") == some 3 &&
  ((arrAt doc ["alignment", "statements"])[0]?.bind fun s => strAt? s ["note"]).isSome &&
  strAt? doc ["acknowledgements"] == some "Built on mathlib4 (pinned v4.31.0)."

/-! ### Trust-strip extraction -/

/-- info: true -/
#guard_msgs in
#eval
  let trust := TrustData.ofFormalizationJson (parsed! yamlRealWorld)
  trust.sorryCount == some 0 &&
  trust.axioms == ["propext", "Classical.choice", "Quot.sound"] &&
  trust.reviewStatus == "agent-reviewed" &&
  trust.comparator.isNone

private def comparatorJson := r##"{
  "status": "configured",
  "config": "comparator.json",
  "solution_module": "A362583",
  "theorem_names": ["A362583.irrational_x", "A362583.raceSum_not_linear"],
  "permitted_axioms": ["propext", "Quot.sound", "Classical.choice"],
  "verified_at": null,
  "note": "Comparator requires Linux; run on CI to flip status to verified."
}"##

/-- info: true -/
#guard_msgs in
#eval
  match Json.parse comparatorJson with
  | .error _ => false
  | .ok j =>
    let cmp := TrustComparator.ofJson j
    cmp.status == "configured" &&
    cmp.verifiedAt == "" &&
    cmp.theoremNames.length == 2 &&
    hasSubstr cmp.note "Linux"

/-! ### Trust-strip badge markup -/

/-- info: true -/
#guard_msgs in
#eval
  let configured := (trustComparatorBadge { status := "configured", note := "runs on CI" }).asString
  let verified := (trustComparatorBadge
    { status := "verified", verifiedAt := "2026-07-03T12:00:00Z" }).asString
  hasSubstr configured "bp_summary_badge_warn" &&
  hasSubstr configured "not yet run" &&
  hasSubstr configured "runs on CI" &&
  -- The badge links to the standalone `comparator/` page (not the removed `trust/…`).
  hasSubstr configured "href=\"comparator/\"" &&
  hasSubstr verified "bp_summary_badge_success" &&
  hasSubstr verified "comparator: verified" &&
  hasSubstr verified "2026-07-03"

/-- info: true -/
#guard_msgs in
#eval
  let trust : TrustData := {
    sorryCount := some 0
    axioms := standardAxioms
    reviewStatus := "agent-reviewed"
    comparator := some { status := "configured", theoremNames := ["A362583.irrational_x"] }
  }
  let strip := (trustStripHtml trust (some "Formalization-Metadata/")).asString
  let empty := (trustStripHtml {} none).asString
  let noComparator := (trustStripHtml { reviewStatus := "agent-reviewed" } (some "Formalization-Metadata/")).asString
  hasSubstr strip "bp_trust_strip" &&
  -- The strip carries only the comparator verdict badge (linking to `comparator/`) plus
  -- the blue `accent` formalization.yaml badge — two `<a class="bp_summary_badge…"`.
  countSubstr strip "<a class=\"bp_summary_badge" == 2 &&
  hasSubstr strip "href=\"comparator/\"" &&
  hasSubstr strip "bp_summary_badge_accent" &&
  hasSubstr strip "href=\"Formalization-Metadata/\"" &&
  hasSubstr strip "formalization.yaml" &&
  -- The deprecated "All checks" affordance and review badge are gone.
  !hasSubstr strip "All checks" &&
  !hasSubstr strip "review:" &&
  -- "Renders only with real trust data": no comparator ⇒ no strip (the accent badge
  -- alone never triggers it).
  noComparator == "" &&
  empty == ""

/-! ### Build-time syntax highlighting + source-link helpers -/

/-! `nonstandardAxioms` filters out the three standard axioms. -/

/-- info: true -/
#guard_msgs in
#eval
  nonstandardAxioms ["propext", "sorryAx", "Classical.choice", "myAxiom"] == ["sorryAx", "myAxiom"] &&
  nonstandardAxioms standardAxioms == []

/-! `blobToRawGitHubUrl?` maps a GitHub blob URL to its raw URL, `none` for non-GitHub. -/

/-- info: true -/
#guard_msgs in
#eval
  blobToRawGitHubUrl? "https://github.com/o/r/blob/abc123/Path/File.lean" ==
    some "https://raw.githubusercontent.com/o/r/abc123/Path/File.lean" &&
  (blobToRawGitHubUrl? "https://gitlab.com/o/r").isNone

/-! `blobToRepoUrl?` / `blobToRepoRelPath?` split a GitHub blob URL into its repo URL and
repo-root path, splitting on the first `/blob/` only (so a literal `blob` path segment
survives); `none` off GitHub or with no `/blob/`. -/

/-- info: true -/
#guard_msgs in
#eval
  blobToRepoUrl? "https://github.com/o/r/blob/abc123/Path/File.lean" == some "https://github.com/o/r" &&
  blobToRepoRelPath? "https://github.com/o/r/blob/abc123/Path/File.lean" == some "Path/File.lean" &&
  -- A path segment literally named `blob` survives (split on the first `/blob/` only).
  blobToRepoUrl? "https://github.com/o/r/blob/abc123/blob/File.lean" == some "https://github.com/o/r" &&
  blobToRepoRelPath? "https://github.com/o/r/blob/abc123/blob/File.lean" == some "blob/File.lean" &&
  -- Non-GitHub and no-`/blob/` URLs degrade to none.
  (blobToRepoUrl? "https://gitlab.com/o/r").isNone &&
  (blobToRepoRelPath? "https://gitlab.com/o/r").isNone &&
  (blobToRepoUrl? "https://github.com/o/r").isNone

/-! `TrustComparator.ofJson` reads the new `permitted_axioms` / `tool_ref` / `config`
fields and tolerates their absence (empty-sentinel defaults). -/

private def statusWithFields := r##"{
  "status": "verified",
  "theorem_names": ["Foo.bar"],
  "permitted_axioms": ["propext", "Quot.sound"],
  "tool_ref": "v4.31.0",
  "config": "comparator/comparator.json"
}"##

/-- info: true -/
#guard_msgs in
#eval
  let withFields := TrustComparator.ofJson ((Json.parse statusWithFields).toOption.getD Json.null)
  let without := TrustComparator.ofJson ((Json.parse r##"{ "status": "configured" }"##).toOption.getD Json.null)
  withFields.permittedAxioms == ["propext", "Quot.sound"] &&
  withFields.toolRef == "v4.31.0" &&
  withFields.configArgPath == "comparator/comparator.json" &&
  without.permittedAxioms == [] &&
  without.toolRef == "" &&
  without.configArgPath == ""

/-! `reproCommands` degrades with the data: project-clone only with a `repoUrl`, `--branch`
only with a `toolRef`, run line only with a `configArgPath`; the tool is always cloned as the
collision-safe `comparator-tool`. -/

/-- info: true -/
#guard_msgs in
#eval
  let full : TrustComparator :=
    { repoUrl := "https://github.com/o/r", toolRef := "v4.31.0", configArgPath := "comparator/comparator.json" }
  let fullS := String.intercalate "\n" (reproCommands full)
  let noRepo := String.intercalate "\n" (reproCommands { toolRef := "v4.31.0", configArgPath := "c.json" })
  let noBranch := String.intercalate "\n" (reproCommands { repoUrl := "https://github.com/o/r", configArgPath := "c.json" })
  let noConfig := String.intercalate "\n" (reproCommands { repoUrl := "https://github.com/o/r", toolRef := "v4.31.0" })
  -- Full data: project clone + branched tool clone + run line with the config path.
  countSubstr fullS "git clone " == 2 &&
  hasSubstr fullS "--branch v4.31.0 https://github.com/leanprover/comparator.git comparator-tool" &&
  hasSubstr fullS "lake env ../comparator-tool/.lake/build/bin/comparator comparator/comparator.json" &&
  -- No repo ⇒ only the tool clone (no project clone line).
  countSubstr noRepo "git clone " == 1 &&
  -- No toolRef ⇒ no `--branch` flag.
  !hasSubstr noBranch "--branch" &&
  -- No configArgPath ⇒ the run line is omitted (a README pointer replaces it in the page).
  !hasSubstr noConfig "lake env"

/-! JSON tokenizer: keys → `const`, string values → `literal string`, numbers →
`literal number`, `true`/`false`/`null` → `keyword`. -/

private def sampleJson := r##"{
  "status": "verified",
  "count": 3,
  "flag": true
}"##

/-- info: true -/
#guard_msgs in
#eval
  let html := (highlightJsonHtml sampleJson).asString
  hasSubstr html "class=\"const\"" &&
  hasSubstr html "class=\"literal string\"" &&
  hasSubstr html "class=\"literal number\"" &&
  hasSubstr html "class=\"keyword\"" &&
  -- the tokenizer is total: values survive verbatim
  hasSubstr html "verified"

/-! Module highlighter: a whole module (header-less here) → highlighted token spans;
degrades to `none` only on failure, never throws. -/

private def sampleModule := r##"namespace ChallengeTest

def two : Nat := 2

theorem two_pos : 0 < two := by decide

end ChallengeTest
"##

/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  match ← Informal.highlightModuleSourceHtml? sampleModule with
  | none => return false
  | some html =>
    return !html.isEmpty && hasSubstr html "namespace" && hasSubstr html "two" &&
      hasSubstr html "<span"

end Verso.VersoBlueprintTests.BlueprintFormalization
