/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint.FormalizationYaml
import VersoBlueprint.Commands.TrustStrip
import VersoBlueprint.Commands.Formalization

/-!
Tests for the `formalization.yaml` subset parser (`Informal.FormalizationYaml`), the
structural subset check derived from the v0.4 schema, the v0.4 rendering, and the dashboard
trust-strip HTML builders (`Informal.Commands.trust*`).
-/

namespace Verso.VersoBlueprintTests.BlueprintFormalization

open Lean
open Verso Genre Manual
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
  -- The verified label names its SOURCE and its DATE ("comparator: CI-verified
  -- 2026-07-03") rather than asserting a present-tense "verified": the badge is a
  -- read-back of a past CI run's artifact, not a live check.
  hasSubstr verified "comparator: CI-verified" &&
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

/-! ### Multi-kernel parsing

The comparator is expected to name its kernels (`external_kernels` in the configuration,
per-kernel replays in the status artifact) where today it carries one flag
(`enable_nanoda`) and one revision (`nanoda_ref`). Both spellings must load, neither may
speak for the other, and absence must keep reading as absence.
-/

private def parsedJson (s : String) : Json := (Json.parse s).toOption.getD Json.null

private def nextGenConfig := r##"{
  "challenge_module": "Challenge",
  "external_kernels": { "nanoda": "aa11", "lean4lean": { "ref": "bb22" } }
}"##

/-- info: true -/
#guard_msgs in
#eval
  let ng := parseExternalKernels (parsedJson nextGenConfig)
  -- Object keys come out in key order, each with whatever revision the config records.
  ng == #[("lean4lean", "bb22"), ("nanoda", "aa11")] &&
  -- An array of names, and an array of objects, load too.
  parseExternalKernels (parsedJson r##"{ "external_kernels": ["nanoda"] }"##) == #[("nanoda", "")] &&
  parseExternalKernels (parsedJson r##"{ "external_kernels": [{"kernel": "nanoda", "ref": "cc"}] }"##)
    == #[("nanoda", "cc")] &&
  -- A legacy configuration names no kernels…
  parseExternalKernels (parsedJson r##"{ "enable_nanoda": true }"##) == #[] &&
  -- …but both spellings of "nanoda is enabled" agree, which is what keeps a migrated
  -- configuration from reading as a run/config disagreement.
  configEnablesNanoda (parsedJson r##"{ "enable_nanoda": true }"##) &&
  configEnablesNanoda (parsedJson nextGenConfig) &&
  !configEnablesNanoda (parsedJson r##"{ "external_kernels": ["lean4lean"] }"##) &&
  !configEnablesNanoda (parsedJson r##"{ }"##)

private def nextGenStatus := r##"{
  "status": "verified",
  "kernel_replays": {
    "lean4lean": { "replayed": true, "ref": "bb22" },
    "nanoda": { "replayed": true, "ref": "aa11" }
  },
  "tool_toolchain": "leanprover/lean4:v4.33.1",
  "challenge_chain": [
    { "path": "comparator/ChallengeDeps.lean", "sha256": "dd44" },
    { "path": "comparator/Challenge.lean", "sha256": "ee55" }
  ]
}"##

/-- info: true -/
#guard_msgs in
#eval
  let legacy := TrustComparator.ofJson
    (parsedJson r##"{ "status": "verified", "nanoda_replay": true, "nanoda_ref": "aa11" }"##)
  let next := TrustComparator.ofJson (parsedJson nextGenStatus)
  let pinOnly := TrustComparator.ofJson (parsedJson r##"{ "status": "verified", "nanoda_ref": "aa11" }"##)
  let bare := TrustComparator.ofJson (parsedJson r##"{ "status": "configured" }"##)
  -- Old shape ⇒ the one kernel, readable both generically and through the nanoda fields
  -- the rest of the fork uses.
  legacy.kernelReplays == #[("nanoda", true)] &&
  legacy.recordedKernelRef "nanoda" == "aa11" &&
  legacy.replayedWithNanoda &&
  -- New shape ⇒ both kernels, and the nanoda fields still resolve from the map.
  next.replayedKernels == #["lean4lean", "nanoda"] &&
  next.recordedKernelRef "lean4lean" == "bb22" &&
  next.nanodaRef == "aa11" &&
  next.replayedWithNanoda &&
  next.toolToolchain == "leanprover/lean4:v4.33.1" &&
  next.challengeChain
    == #[("comparator/ChallengeDeps.lean", "dd44"), ("comparator/Challenge.lean", "ee55")] &&
  -- A recorded revision with no recorded replay pins a program; it claims no check.
  pinOnly.kernelReplays == #[] &&
  !pinOnly.replayedWithNanoda &&
  !pinOnly.nanodaReplayRecorded &&
  pinOnly.recordedKernelRef "nanoda" == "aa11" &&
  -- Absence stays absence.
  bare.kernelReplays == #[] && bare.challengeChain == #[] && bare.toolToolchain == ""

/-! The trust payload rides a quoted `TrustData` through the traversal store, so the new
fields have to survive the JSON round trip they are carried by. -/

/-- info: true -/
#guard_msgs in
#eval
  let next := TrustComparator.ofJson (parsedJson nextGenStatus)
  match fromJson? (α := TrustComparator) (toJson next) with
  | .ok back =>
    back.challengeChain == next.challengeChain &&
    back.kernelReplays == next.kernelReplays &&
    back.kernelRefs == next.kernelRefs &&
    back.toolToolchain == next.toolToolchain
  | .error _ => false

/-! ### One canonical record set (CX-069)

A status artifact may spell its run evidence three ways — identity records, a generic
`kernel_replays` map, the legacy `nanoda_replay`/`nanoda_ref` pair. It may not spell it
three *different* ways. Every encoding present is merged into one canonical set, and any
disagreement about a replay boolean or a revision is reported for the elaboration-time
check to throw: picking a winner is how one page ends up naming a different revision than
another for the same claimed replay.
-/

private def dualEncodingStatus := r##"{
  "status": "verified",
  "kernel_identities": [
    { "label": "nanoda", "repository": "https://github.com/ammkrn/nanoda_lib",
      "source_commit": "identity-cafebabe", "executable_sha256": "deadbeef", "replayed": true }
  ],
  "nanoda_replay": false,
  "nanoda_ref": "legacy-deadbeef"
}"##

private def genericVsLegacyStatus := r##"{
  "status": "verified",
  "kernel_replays": { "nanoda": { "replayed": true, "ref": "generic-rev" } },
  "nanoda_replay": false,
  "nanoda_ref": "legacy-rev"
}"##

private def legacyTrueGenericFalseStatus := r##"{
  "status": "verified",
  "kernel_replays": { "nanoda": { "replayed": false, "ref": "same-rev" } },
  "nanoda_replay": true,
  "nanoda_ref": "same-rev"
}"##

private def identityVsGenericStatus := r##"{
  "status": "verified",
  "kernel_identities": [
    { "label": "nanoda", "source_commit": "aaa", "executable_sha256": "d1", "replayed": true }
  ],
  "kernel_replays": { "nanoda": { "replayed": true, "ref": "bbb" } }
}"##

private def agreeingStatus := r##"{
  "status": "verified",
  "kernel_replays": { "nanoda": { "replayed": true, "ref": "same-rev" } },
  "nanoda_replay": true,
  "nanoda_ref": "same-rev"
}"##

private def partialEncodingStatus := r##"{
  "status": "verified",
  "kernel_replays": { "lean4lean": { "replayed": true, "ref": "ll" } },
  "nanoda_replay": true,
  "nanoda_ref": "nn"
}"##

-- Every contradictory pairing is reported, in both boolean directions and for revisions;
-- agreement and partial coverage are not contradictions.
/-- info: (2, 2, 1, 1, 0, 0) -/
#guard_msgs in
#eval
  let conflicts := fun (src : String) =>
    (TrustComparator.ofJson (parsedJson src)).encodingConflicts.size
  -- identity vs legacy: both the boolean and the revision disagree.
  (conflicts dualEncodingStatus,
   -- generic map vs legacy: likewise.
   conflicts genericVsLegacyStatus,
   -- the other boolean direction, with revisions that agree.
   conflicts legacyTrueGenericFalseStatus,
   -- identity vs generic map: same replay, different revisions.
   conflicts identityVsGenericStatus,
   -- three encodings that agree are one fact spelled three times.
   conflicts agreeingStatus,
   -- an encoding may name fewer checkers than another without contradicting it.
   conflicts partialEncodingStatus)

-- The compatibility fields are derived from the canonical set, never parsed beside it, so
-- the raw and semantic readings of a record can no longer differ.
/-- info: true -/
#guard_msgs in
#eval
  let agreeing := TrustComparator.ofJson (parsedJson agreeingStatus)
  let part := TrustComparator.ofJson (parsedJson partialEncodingStatus)
  agreeing.nanodaRef == agreeing.recordedKernelRef "nanoda" &&
  agreeing.nanodaReplay == agreeing.recordedReplay? "nanoda" &&
  agreeing.nanodaRef == "same-rev" &&
  -- A partial encoding unions rather than overrides: both checkers survive, each with its
  -- own revision.
  part.recordedKernelRef "lean4lean" == "ll" &&
  part.recordedKernelRef "nanoda" == "nn" &&
  part.nanodaRef == "nn" &&
  part.replayedKernels == #["lean4lean", "nanoda"]

/-! ### Checker identity (CX-064)

The comparator's `external_kernels` key is a consumer-chosen label it copies into its
output before running the associated command and reading exit status zero as acceptance:
`{"nanoda": ["/usr/bin/true"]}` prints that nanoda accepted the solution. A label, and a
revision typed beside it, therefore authenticate nothing. `kernelIdentityTier` is where
that judgement is made once.
-/

private def spoofedLabelStatus := r##"{
  "status": "verified",
  "kernel_replays": { "nanoda": { "replayed": true, "ref": "f58f2f6d" } }
}"##

private def namedIdentityStatus := r##"{
  "status": "verified",
  "kernel_identities": [
    { "label": "nanoda", "adapter_kind": "nanoda",
      "repository": "https://github.com/ammkrn/nanoda_lib.git",
      "source_commit": "05055695", "command_argv": ["/opt/nanoda_bin"],
      "executable_sha256": "abcdef01", "replayed": true, "verdict": "accepted" }
  ]
}"##

private def wrongRepoStatus := r##"{
  "status": "verified",
  "kernel_identities": [
    { "label": "nanoda", "repository": "https://github.com/attacker/not_nanoda",
      "source_commit": "05055695", "executable_sha256": "abcdef01", "replayed": true }
  ]
}"##

private def noDigestStatus := r##"{
  "status": "verified",
  "kernel_identities": [
    { "label": "nanoda", "repository": "https://github.com/ammkrn/nanoda_lib",
      "source_commit": "05055695", "replayed": true }
  ]
}"##

private def unknownCheckerStatus := r##"{
  "status": "verified",
  "kernel_identities": [
    { "label": "lean4lean", "adapter_kind": "acme", "repository": "https://github.com/x/lean4lean",
      "source_commit": "cc11dd22", "executable_sha256": "9876fedc", "replayed": true }
  ]
}"##

/-- info: ("labeled", "named", "bound", "labeled", "bound", "ci-built") -/
#guard_msgs in
#eval
  -- A label the configuration points somewhere of its choosing, with a revision typed
  -- beside it: authenticates nothing.
  let spoofed := { TrustComparator.ofJson (parsedJson spoofedLabelStatus) with
    externalKernels := #[("nanoda", "")], enableNanoda := true }
  let named := TrustComparator.ofJson (parsedJson namedIdentityStatus)
  let wrongRepo := TrustComparator.ofJson (parsedJson wrongRepoStatus)
  let noDigest := TrustComparator.ofJson (parsedJson noDigestStatus)
  let unknown := TrustComparator.ofJson (parsedJson unknownCheckerStatus)
  -- The legacy pair, which no `external_kernels` map can redirect: the run's CI built the
  -- binary from the recorded revision and wrote both.
  let legacy := TrustComparator.ofJson
    (parsedJson r##"{ "status": "verified", "nanoda_replay": true, "nanoda_ref": "f58f2f6d" }"##)
  (spoofed.kernelIdentityTier "nanoda", named.kernelIdentityTier "nanoda",
   wrongRepo.kernelIdentityTier "nanoda", noDigest.kernelIdentityTier "nanoda",
   unknown.kernelIdentityTier "lean4lean", legacy.kernelIdentityTier "nanoda")

/-- info: true -/
#guard_msgs in
#eval
  let spoofed := { TrustComparator.ofJson (parsedJson spoofedLabelStatus) with
    externalKernels := #[("nanoda", "")], enableNanoda := true }
  let named := TrustComparator.ofJson (parsedJson namedIdentityStatus)
  let unknown := TrustComparator.ofJson (parsedJson unknownCheckerStatus)
  -- The run says a replay happened, and this site must not say nanoda performed it.
  spoofed.replayedKernels == #["nanoda"] &&
  spoofed.assuredKernels == #[] &&
  spoofed.unnamedReplayClaims == #["nanoda"] &&
  !spoofed.replayedWithNanoda &&
  -- A bound identity of a checker this fork does not know by name is identified, but
  -- still not named by it.
  unknown.assuredKernels == #[] && unknown.unnamedReplayClaims == #["lean4lean"] &&
  -- The full binding of a known kernel is the one case that carries the name.
  named.assuredKernels == #["nanoda"] && named.replayedWithNanoda &&
  -- Trailing `.git` and case are spelling, not a different repository.
  named.kernelIdentities.size == 1

/-! A configuration that migrated `enable_nanoda` into `external_kernels` has not turned
the kernel off, so a run that replayed is not drift. Dropping the kernel from the map
still is. -/

/-- info: (none, none, some false) -/
#guard_msgs in
#eval
  let ofConfig (cfg : String) : TrustComparator :=
    let j := parsedJson cfg
    { externalKernels := parseExternalKernels j
      enableNanoda := configEnablesNanoda j
      nanodaReplay := some true }
  ((ofConfig r##"{ "external_kernels": { "nanoda": "aa11" } }"##).nanodaConfigDrift?,
   (ofConfig r##"{ "external_kernels": { "lean4lean": "bb", "nanoda": "aa11" } }"##).nanodaConfigDrift?,
   (ofConfig r##"{ "external_kernels": { "lean4lean": "bb" } }"##).nanodaConfigDrift?)

/-! `reproCommands` degrades with the data: project-clone only with a `repoUrl`, `--branch`
only with a `toolRef`, run line only with a `configArgPath`; the tool is always cloned as the
collision-safe `comparator-tool`. With `enableNanoda`, the flow also clones/builds `nanoda_lib`
and prefixes the run line with `COMPARATOR_NANODA=`; by default no nanoda line appears. -/

/-- info: true -/
#guard_msgs in
#eval
  let full : TrustComparator :=
    { repoUrl := "https://github.com/o/r", toolRef := "v4.31.0", configArgPath := "comparator/comparator.json" }
  let fullS := String.intercalate "\n" (reproCommands full)
  let noRepo := String.intercalate "\n" (reproCommands { toolRef := "v4.31.0", configArgPath := "c.json" })
  let noBranch := String.intercalate "\n" (reproCommands { repoUrl := "https://github.com/o/r", configArgPath := "c.json" })
  let noConfig := String.intercalate "\n" (reproCommands { repoUrl := "https://github.com/o/r", toolRef := "v4.31.0" })
  let withNanoda := String.intercalate "\n" (reproCommands { full with enableNanoda := true })
  -- Full data: project clone + branched tool clone + run line with the config path.
  countSubstr fullS "git clone " == 2 &&
  hasSubstr fullS "--branch v4.31.0 https://github.com/leanprover/comparator.git comparator-tool" &&
  hasSubstr fullS "lake env ../comparator-tool/.lake/build/bin/comparator comparator/comparator.json" &&
  -- No repo ⇒ only the tool clone (no project clone line).
  countSubstr noRepo "git clone " == 1 &&
  -- No toolRef ⇒ no `--branch` flag.
  !hasSubstr noBranch "--branch" &&
  -- No configArgPath ⇒ the run line is omitted (a README pointer replaces it in the page).
  !hasSubstr noConfig "lake env" &&
  -- Nanoda enabled ⇒ clone/build lines + the COMPARATOR_NANODA env prefix on the run line.
  hasSubstr withNanoda "nanoda_lib" &&
  hasSubstr withNanoda "COMPARATOR_NANODA=" &&
  -- Default (flag false) ⇒ no nanoda anywhere.
  !hasSubstr fullS "nanoda"

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


/-! ### Status ↔ config cross-check helpers

The consumer's trust options resolve against the *build CWD* (`site/`) while the
comparator status artifact records *repo-root-relative* paths, so the same file is
spelled `../comparator/comparator.json` and `comparator/comparator.json`. The
agreement check must compare path components, not strings — string equality would
reject every correctly-configured project.
-/

/-- info: true -/
#guard_msgs in
#eval
  -- The real a362583 spelling: option path (site-CWD-relative) vs. status `config`
  -- (repo-root-relative). Must agree.
  pathHasSuffix "../comparator/comparator.json" "comparator/comparator.json" &&
  pathHasSuffix "./comparator/comparator.json" "comparator/comparator.json" &&
  pathHasSuffix "comparator/comparator.json" "comparator/comparator.json" &&
  -- A genuinely different file must NOT agree, including one whose name merely ends
  -- with the same characters (component-boundary matching, not string suffix).
  !pathHasSuffix "../comparator/other.json" "comparator/comparator.json" &&
  !pathHasSuffix "../elsewhere/xcomparator.json" "comparator.json" &&
  -- Suffix longer than the path cannot match.
  !pathHasSuffix "comparator.json" "a/b/comparator.json"

/-- info: true -/
#guard_msgs in
#eval
  -- A config module name maps to the file the page renders by basename, so the
  -- nested `ComparatorChallenges/` layout and the flat one both resolve.
  moduleBasename "Challenge" == "Challenge" &&
  moduleBasename "ComparatorChallenges.I_MulticolorTriangleRamsey" == "I_MulticolorTriangleRamsey" &&
  leanFileStem "../comparator/Challenge.lean" == "Challenge" &&
  leanFileStem ".lake/packages/ten-proofs/ComparatorChallenges/I_Foo.lean" == "I_Foo" &&
  leanFileStem "Solution" == "Solution"

/-! ### Reproduce commands pin what CI actually ran -/

/-- info: true -/
#guard_msgs in
#eval
  let pinned := reproCommands {
    toolRef := "v4.32.0", toolSha := "abc123", nanodaRef := "def456",
    enableNanoda := true, configArgPath := "comparator/comparator.json" }
  let unpinned := reproCommands {
    toolRef := "v4.32.0", enableNanoda := true, configArgPath := "comparator/comparator.json" }
  let joinedPinned := String.intercalate "\n" pinned
  let joinedUnpinned := String.intercalate "\n" unpinned
  -- A mutable tag is not enough: when CI recorded the resolved commit, check it out.
  hasSubstr joinedPinned "git checkout abc123" &&
  hasSubstr joinedPinned "git checkout def456" &&
  -- Without recorded revisions the commands degrade rather than inventing a pin
  -- (the page then says so in prose).
  !hasSubstr joinedUnpinned "git checkout" &&
  hasSubstr joinedUnpinned "nanoda_lib"

/-! ### Reproduce commands rebuild the tool the way the run did

The comparator reads the project's oleans, which carry a compiler stamp, so a run
rebuilds the tool on the *project's* toolchain. When the record says which, the commands
write it into the checkout before building — after the commit pin, before the build. -/

/-- info: true -/
#guard_msgs in
#eval
  let cmp : TrustComparator := {
    toolRef := "v4.33.0", toolSha := "abc123", toolToolchain := "leanprover/lean4:v4.33.1",
    configArgPath := "comparator/comparator.json" }
  let lines := reproCommands cmp
  let joined := String.intercalate "\n" lines
  let idx := fun (needle : String) => lines.findIdx? fun l => hasSubstr l needle
  idx "git checkout abc123" == some 1 &&
  idx "> comparator-tool/lean-toolchain" == some 2 &&
  idx "lake build lean4export" == some 3 &&
  hasSubstr joined "printf '%s\\n' 'leanprover/lean4:v4.33.1' > comparator-tool/lean-toolchain" &&
  -- Unrecorded ⇒ no override line at all (the page says so in prose instead).
  !hasSubstr (String.intercalate "\n" (reproCommands { cmp with toolToolchain := "" }))
    "lean-toolchain"

/-! The verifiers are pinned by revision, so the subject has to be too: the same tools
check different bytes as soon as the default branch moves. When the run recorded which
revision it verified, the project step clones and detaches at it, before anything is
built. -/

/-- info: true -/
#guard_msgs in
#eval
  let pinned : TrustComparator := {
    repository := "eric-vergo/OEIS-A362583-Irrationality"
    commit := "76ea8221111111111111111111111111111111ab"
    toolSha := "abc123", configArgPath := "comparator/comparator.json" }
  let lines := reproCommands pinned
  let idx := fun (needle : String) => lines.findIdx? fun l => hasSubstr l needle
  idx "git clone https://github.com/eric-vergo/OEIS-A362583-Irrationality" == some 0 &&
  idx "git checkout 76ea8221111111111111111111111111111111ab" == some 1 &&
  idx "comparator.git comparator-tool" == some 2 &&
  hasSubstr (String.intercalate "\n" lines)
    "(cd OEIS-A362583-Irrationality && git checkout 76ea8221111111111111111111111111111111ab)" &&
  -- A record with no subject revision keeps exactly the old shape (clone, then the tool).
  (reproCommands { pinned with commit := "" }).length + 1 == lines.length &&
  !hasSubstr (String.intercalate "\n" (reproCommands { pinned with commit := "" }))
    "git checkout 76ea"

/-! An `external_kernels` entry carries its own command vector in the configuration this
page displays, so the flow points at the comparator README rather than inventing a build
— whatever the entry is labeled. The legacy `enable_nanoda` flag, which hands the
comparator a binary through the environment, still gets the real nanoda flow. -/

/-- info: true -/
#guard_msgs in
#eval
  let external : TrustComparator := {
    configArgPath := "c.json", enableNanoda := true,
    externalKernels := #[("nanoda", ""), ("lean4lean", "")] }
  let joined := String.intercalate "\n" (reproCommands external)
  let legacy := String.intercalate "\n"
    (reproCommands { configArgPath := "c.json", enableNanoda := true })
  !hasSubstr joined "nanoda_lib" &&
  !hasSubstr joined "COMPARATOR_NANODA=" &&
  countSubstr joined "external checker labeled" == 2 &&
  hasSubstr legacy "COMPARATOR_NANODA=" &&
  hasSubstr legacy "nanoda_lib"

/-! ### comparator.live permalink -/

/-- info: true -/
#guard_msgs in
#eval
  let url := comparatorLivePermalink "mathlib-stable" "theorem t : True := by trivial" "def s := 1"
  -- Plain (uncompressed) fragment keys, percent-encoded payloads.
  hasSubstr url "comparator.live.lean-lang.org/#project=mathlib-stable" &&
  hasSubstr url "&challenge=" &&
  hasSubstr url "&code=" &&
  -- No raw spaces survive into the fragment.
  !hasSubstr url "theorem t :"

/-! ### Rendering-tier markers -/

/-- info: true -/
#guard_msgs in
#eval
  let reelab := (Informal.NodeCard.tierMarker (some "reelab")).asString
  let delab := (Informal.NodeCard.tierMarker (some "delaborated")).asString
  let unknown := (Informal.NodeCard.tierMarker (some "not-a-tier")).asString
  let absent := (Informal.NodeCard.tierMarker none).asString
  hasSubstr reelab "bp_tier_marker" &&
  hasSubstr reelab "data-bp-tier=\"reelab\"" &&
  hasSubstr reelab "Re-elaborated from source" &&
  hasSubstr delab "data-bp-tier=\"delaborated\"" &&
  -- An unrecognized tier renders NO marker rather than a wrong one.
  unknown.isEmpty && absent.isEmpty

/-! ### Verifier currency

The three-way judgement (`Informal.KernelAdvisories.currencyVerdict`) against a forced
table, so the matrix does not move when the shipped advisories do. The shipped table is
asserted separately, at the end, on the facts a consumer's page depends on.
-/

open Informal.KernelAdvisories in
/-- A fixture table with one version-numbered tool and one commit-numbered one, each
carrying a different flavour of fix evidence. -/
private def testTable : Table where
  advisoriesUpdated := "2026-08-25"
  advisories := #[
    { id := "t-lean", tool := "lean4", advisoryDate := "2026-08-21"
      summary := "Fixture kernel advisory.", url := "https://example.invalid/lean"
      fix := { fixedFromVersion := "v4.33.1", fixedRevisions := #["v4.34.0-rc2"] } },
    { id := "t-nanoda", tool := "nanoda", advisoryDate := "2026-08-25"
      summary := "Fixture checker advisory.", url := "https://example.invalid/nanoda"
      fix := {
        fixedDescendantsOf := "aaaaaaa1111111111111111111111111111111ff"
        fixedRevisions := #["aaaaaaa1111111111111111111111111111111ff"]
        affectedRevisions := #["bbbbbbb2222222222222222222222222222222ff"]
        ancestry := "Descendants of aaaaaaa1 are fixed." } } ]

private def fixedRev := "aaaaaaa1111111111111111111111111111111ff"
private def affectedRev := "bbbbbbb2222222222222222222222222222222ff"
private def unresolvedRev := "ccccccc3333333333333333333333333333333ff"

open Informal.KernelAdvisories in
private def verdictOf (tool revision recordDate : String) (kind : RefKind := .commit)
    (identityAssessable : Bool := true) : String × String :=
  let a := currencyVerdict testTable { tool, revision, kind, identityAssessable, recordDate }
  (a.verdict.name, a.reason)

/-! Green needs an immutable revision the table *resolves*, and nothing else reaches it. -/

/-- info: ("current", "revision-fixed") -/
#guard_msgs in
#eval verdictOf "nanoda" fixedRev "2026-08-20"

-- A revision with no date beside it is still evaluable: the evidence is the revision.
/-- info: ("current", "revision-fixed") -/
#guard_msgs in
#eval verdictOf "nanoda" fixedRev ""

-- CX-046's named case: the run happened *after* the advisory, and pinned a revision the
-- table resolved as predating the fix. Dates-primary would have called this current.
/-- info: ("stale", "known-affected") -/
#guard_msgs in
#eval verdictOf "nanoda" affectedRev "2026-08-26"

-- The one inference a date supports: a build resolved before the fix existed lacks it.
/-- info: ("stale", "recorded-before-fix") -/
#guard_msgs in
#eval verdictOf "nanoda" unresolvedRev "2026-08-04"

-- The same revision recorded after the fix landed is unknown, not current: nothing says
-- which side of the fix that commit is on.
/-- info: ("unknown", "unresolved") -/
#guard_msgs in
#eval verdictOf "nanoda" unresolvedRev "2026-08-25"

-- A moving reference is not a build.
/-- info: ("unknown", "symbolic-revision") -/
#guard_msgs in
#eval verdictOf "nanoda" "main" "2026-08-20"

/-- info: ("unknown", "no-revision") -/
#guard_msgs in
#eval verdictOf "nanoda" "" "2026-08-20"

-- CX-064: a label the record never bound to a program is unknown whatever revision is
-- typed beside it — even the revision the table resolves as fixed.
/-- info: ("unknown", "identity-unbound") -/
#guard_msgs in
#eval verdictOf "nanoda" fixedRev "2026-08-20" (identityAssessable := false)

-- A tool the table says nothing about cannot be called current either.
/-- info: ("unknown", "no-advisories") -/
#guard_msgs in
#eval verdictOf "lean4lean" fixedRev "2026-08-20"

/-! Toolchains are ordered against the recorded minimum; prereleases above it are branch
snapshots whose number does not imply their contents, so they need the allowlist. -/

/-- info: ("stale", "below-fixed-version") -/
#guard_msgs in
#eval verdictOf "lean4" "leanprover/lean4:v4.33.0-rc2" "2026-08-24" (kind := .version)

/-- info: ("current", "revision-fixed") -/
#guard_msgs in
#eval verdictOf "lean4" "leanprover/lean4:v4.33.1" "2026-08-24" (kind := .version)

-- Allowlisted prerelease of the next line: resolved by hand, not by ordering.
/-- info: ("current", "revision-fixed") -/
#guard_msgs in
#eval verdictOf "lean4" "v4.34.0-rc2" "2026-08-24" (kind := .version)

-- Its sibling rc, above the minimum but never checked, stays unknown.
/-- info: ("unknown", "unresolved") -/
#guard_msgs in
#eval verdictOf "lean4" "v4.34.0-rc1" "2026-08-24" (kind := .version)

-- A stable release above the minimum is carried by the ordering alone.
/-- info: ("current", "revision-fixed") -/
#guard_msgs in
#eval verdictOf "lean4" "leanprover/lean4:v4.34.0" "2026-08-24" (kind := .version)

-- A nightly is immutable but unorderable, which is its own state.
/-- info: ("unknown", "incomparable-revision") -/
#guard_msgs in
#eval verdictOf "lean4" "leanprover/lean4:nightly-2026-08-24" "2026-08-24" (kind := .version)

/-! A table older than the record it judges cannot produce a green claim, and the copy
leads with that rather than with what the table happens to resolve. -/

/-- info: ("unknown", "table-older-than-record") -/
#guard_msgs in
#eval verdictOf "nanoda" fixedRev "2026-08-26"

/-- info: true -/
#guard_msgs in
#eval
  let a := Informal.KernelAdvisories.currencyVerdict testTable
    { tool := "nanoda", revision := fixedRev, recordDate := "2026-08-26" }
  let detail := currencyDetail "nanoda" fixedRev "2026-08-26" "2026-08-25" (some true) a
  -- Staleness of the table comes first, and no green sentence precedes it.
  detail.startsWith "This verdict is newer than this site's advisory table" &&
  hasSubstr detail "no currency claim is made" &&
  a.tableStale

/-! The stale copy claims exactly as much as the record does: a recorded replay is a
second-kernel assurance to call dated, an unrecorded one is a pin and nothing more. -/

/-- info: true -/
#guard_msgs in
#eval
  let a := Informal.KernelAdvisories.currencyVerdict testTable
    { tool := "nanoda", revision := affectedRev, recordDate := "2026-08-04" }
  let replayed := currencyDetail "nanoda" affectedRev "2026-08-04" "2026-08-25" (some true) a
  let pinned := currencyDetail "nanoda" affectedRev "2026-08-04" "2026-08-25" none a
  hasSubstr replayed "recorded a replay by nanoda" &&
  hasSubstr replayed "Treat that second-kernel assurance as dated." &&
  hasSubstr pinned "pins nanoda at" &&
  hasSubstr pinned "does not say a replay happened" &&
  !hasSubstr pinned "second-kernel assurance" &&
  -- Both name the date the record carries, and neither claims a fix it cannot see.
  hasSubstr replayed "of 2026-08-04" && hasSubstr pinned "of 2026-08-04"

-- The self-aging clause is a constant obligation, not a branch.
/-- info: true -/
#guard_msgs in
#eval
  hasSubstr (currencyAgingClause "2026-08-25")
    "Advisory table last updated 2026-08-25 — a newer advisory would not appear here." &&
  hasSubstr (currencyAgingClause "") "nothing bounds what it knows"

/-! Rows are built from what the *run* recorded. A checker the configuration merely
enables has no build to assess, and gets no row rather than a neutral one. -/

/-- info: true -/
#guard_msgs in
#eval
  let legacy : TrustComparator :=
    { status := "verified", verifiedAt := "2026-08-04T02:15:05Z", nanodaRef := affectedRev }
  let configOnly : TrustComparator :=
    { status := "verified", verifiedAt := "2026-08-04T02:15:05Z", enableNanoda := true }
  let withToolchain : TrustComparator :=
    { legacy with toolToolchain := "leanprover/lean4:v4.33.1" }
  let legacyRows := legacy.currencyRows testTable
  let toolchainRows := withToolchain.currencyRows testTable
  -- The legacy pair is assessable (no configuration can redirect it) and stale here.
  legacyRows.size == 1 &&
  (legacyRows[0]!).tool == "nanoda" && (legacyRows[0]!).verdict == "stale" &&
  (legacyRows[0]!).advisoriesUpdated == "2026-08-25" &&
  (legacyRows[0]!).advisories.size == 1 &&
  ((legacyRows[0]!).advisories[0]!).state == "affected" &&
  -- Configuration is not run evidence: no build, no row.
  (configOnly.currencyRows testTable).isEmpty &&
  -- The toolchain the run rebuilt the tool on is assessed first, then the checkers.
  toolchainRows.size == 2 &&
  (toolchainRows[0]!).tool == "lean4" && (toolchainRows[0]!).verdict == "current" &&
  (toolchainRows[1]!).tool == "nanoda"

/-! Revision matching: git abbreviations are prefixes, toolchain strings are versions. -/

/-- info: true -/
#guard_msgs in
#eval
  let m := Informal.KernelAdvisories.revisionMatches
  m .commit "f58f2f6" "f58f2f6d535e189a40fcb02ede8eb95f97a92d37" &&
  m .commit "F58F2F6D535E189A40FCB02EDE8EB95F97A92D37" "f58f2f6" &&
  !m .commit "f58f2f6" "aaaaaaa1111111111111111111111111111111ff" &&
  -- Six digits is below git's own abbreviation floor: not a match by prefix.
  !m .commit "f58f2f" "f58f2f6d535e189a40fcb02ede8eb95f97a92d37" &&
  m .version "leanprover/lean4:v4.33.1" "v4.33.1" &&
  !m .version "v4.33.1" "v4.33.1-rc1"

/-- info: true -/
#guard_msgs in
#eval
  let p := Informal.KernelAdvisories.parseVersion?
  let cmp := fun (a b : String) =>
    match p a, p b with
    | some x, some y => some (Informal.KernelAdvisories.compareVersion x y)
    | _, _ => none
  cmp "v4.33.1" "v4.33.1" == some .eq &&
  cmp "v4.33.0-rc2" "v4.33.1" == some .lt &&
  -- Semver: a prerelease precedes the release it leads to.
  cmp "v4.33.1-rc1" "v4.33.1" == some .lt &&
  cmp "v4.34.0-rc2" "v4.33.1" == some .gt &&
  cmp "leanprover/lean4:v4.34.0" "v4.33.1" == some .gt &&
  (p "leanprover/lean4:nightly-2026-08-24").isNone &&
  (p "05055695879dfebb6628a67da88ceca6cd6b0421").isNone

/-! A consumer override replaces the table, and is read from JSON in the shape the
option documents. -/

/-- info: ("stale", "known-affected") -/
#guard_msgs in
#eval
  let overrideJson := r##"{
    "advisoriesUpdated": "2026-09-01",
    "advisories": [
      { "id": "custom", "tool": "nanoda", "advisoryDate": "2026-08-30",
        "summary": "A consumer's own advisory.", "url": "https://example.invalid/x",
        "fix": { "affectedRevisions": ["aaaaaaa1111111111111111111111111111111ff"] } }
    ]
  }"##
  match Informal.KernelAdvisories.Table.ofJson? (parsedJson overrideJson) with
  | .error e => ("parse error", e)
  | .ok t =>
    -- The revision the *fixture* table resolves as fixed is affected under this one.
    let a := Informal.KernelAdvisories.currencyVerdict t
      { tool := "nanoda", revision := fixedRev, recordDate := "2026-08-31" }
    (a.verdict.name, a.reason)

-- Absent evidence reads as absent (a hand-written table need not spell every key), but
-- the three structural defects are errors: an entry that could never apply, a table that
-- does not date itself, and an `advisories` value that is not a list.
/-- info: true -/
#guard_msgs in
#eval
  let ofJson := fun (s : String) => Informal.KernelAdvisories.Table.ofJson? (parsedJson s)
  let errorHas := fun (r : Except String Informal.KernelAdvisories.Table) (needle : String) =>
    match r with
    | .error e => hasSubstr e needle
    | .ok _ => false
  let minimal := ofJson r##"{ "advisoriesUpdated": "2026-09-01",
    "advisories": [ { "tool": "nanoda", "advisoryDate": "2026-08-30" } ] }"##
  let noTool := ofJson r##"{ "advisoriesUpdated": "2026-09-01",
    "advisories": [ { "advisoryDate": "2026-08-30" } ] }"##
  let noDate := ofJson r##"{ "advisories": [] }"##
  let notArray := ofJson r##"{ "advisoriesUpdated": "2026-09-01", "advisories": {} }"##
  -- A minimal entry loads, and proves nothing: no evidence, so `unknown`, never green.
  (match minimal with
   | .ok t =>
     ((Informal.KernelAdvisories.currencyVerdict t
        { tool := "nanoda", revision := fixedRev, recordDate := "2026-08-31" }).verdict.name
      == "unknown")
   | .error _ => false) &&
  errorHas noTool "names no 'tool'" &&
  errorHas noDate "no 'advisoriesUpdated' date" &&
  errorHas notArray "not an array"

/-! The shipped table, on the facts a consumer's page depends on. -/

/-- info: true -/
#guard_msgs in
#eval
  let t := Informal.KernelAdvisories.builtinTable
  let byTool := fun (tool : String) => t.advisories.find? fun a => a.tool == tool
  t.advisoriesUpdated == "2026-08-25" &&
  t.advisories.size == 2 &&
  (byTool "lean4").isSome && (byTool "nanoda").isSome &&
  ((byTool "lean4").map (·.fix.fixedFromVersion)) == some "v4.33.1" &&
  ((byTool "lean4").map (·.advisoryDate)) == some "2026-08-21" &&
  -- The nanoda series completed with #28; that merge commit is the ancestry anchor.
  ((byTool "nanoda").map (·.fix.fixedDescendantsOf)) ==
    some "05055695879dfebb6628a67da88ceca6cd6b0421" &&
  ((byTool "nanoda").map (·.advisoryDate)) == some "2026-08-25"

-- The record this whole surface exists for: a real 2026-08-04 verdict pinning a nanoda
-- revision from three weeks before the fixes. It must read stale against the shipped
-- table, and it must say so without claiming a replay the record never recorded.
/-- info: true -/
#guard_msgs in
#eval
  let real : TrustComparator :=
    { status := "verified", verifiedAt := "2026-08-04T02:15:05Z"
      nanodaRef := "f58f2f6d535e189a40fcb02ede8eb95f97a92d37" }
  let rows := real.currencyRows Informal.KernelAdvisories.builtinTable
  rows.size == 1 && (rows[0]!).verdict == "stale" &&
  hasSubstr (rows[0]!).detail "pins nanoda at f58f2f6d535e189a40fcb02ede8eb95f97a92d37" &&
  !hasSubstr (rows[0]!).detail "second-kernel assurance" &&
  -- And the toolchain that ran is simply not recorded there, so no row claims otherwise.
  !((rows.map (·.tool)).contains "lean4")

/-! ### The v0.4 subset check

A hand-written check of the shape the v0.4 schema states, run only when
`verso.blueprint.trust.validateFormalizationYaml` is on. What it is *not* is a general
validator, and the tests below pin both halves of that: the required fields, types,
enumerations, minimums and the two `repository` conditionals are checked; formats, lengths
and the freeform `alignment` block are not.
-/

private def yamlV04 := r##"version: "v0.4"

project:
  name: "A362583 Irrationality"
  description: "The prime race constant is irrational."
  authors: ["Eric Vergo"]
  responsible_maintainers: ["Eric Vergo"]
  license: "Apache-2.0"

repository:
  role: "substantive-development"

sources:
  - title: "A362583 Irrationality — original proof"
    authors: ["Eric Vergo"]
    id: "https://example.org/proof"
    type: "original-proof"
    location: "§2"
    relationship: "formalizes"
    author_endorsement: "n/a"
    note: "Self-authored."
    contributors:
      - name: "A Referee"
        role: "editor"
        link: "https://example.org/referee"

related_formalizations:
  - id: "https://example.org/other"
    relationship: "independent"
    note: "Parallel work."

classification:
  arxiv: ["math.NT"]
  msc2020: ["11J72", "11N13"]

automation:
  methods:
    - method: "agent"
      models: ["claude-fable-5"]
      framework: "Claude Code"
      cost:
        wall_time: "~1 day"

status:
  sorry_count: 0
  axioms: ["propext"]

review:
  status: "self-assessed"
"##

private def yamlBroken := r##"version: "v0.4"

project:
  authors: []
  license: ""

sources: []

automation:
  methods:
    - method: "wizardry"

review:
  reviewers: ["x"]
"##

private def yamlBadTypes := r##"version: "v0.4"

project:
  name: "X"
  authors: ["Eric Vergo"]
  license: "Apache-2.0"

sources:
  - title: "A source"
    relationship: "sideways"
    author_endorsement: "maybe"
    contributors:
      - name: "Someone"

automation:
  methods:
    - method: "agent"

status:
  sorry_count: -1

review:
  status: "self-assessed"
"##

private def validationOf (src : String) : Array String :=
  FormalizationYaml.validate (parsed! src)

-- A complete v0.4 document, and the v0.3 document from the parser tests above, both pass:
-- the v0.4-only keys are optional in the check exactly as they are in the schema.
/-- info: (0, 0) -/
#guard_msgs in
#eval ((validationOf yamlV04).size, (validationOf yamlRealWorld).size)

-- Required fields, array minimums and enumerations, all reported at once rather than one
-- build at a time.
/-- info: true -/
#guard_msgs in
#eval
  let vs := String.intercalate "\n" (validationOf yamlBroken).toList
  (validationOf yamlBroken).size == 6 &&
  hasSubstr vs "project.name is required" &&
  hasSubstr vs "project.authors must list at least 1 entry" &&
  hasSubstr vs "project.license must not be empty" &&
  hasSubstr vs "sources must list at least 1 entry" &&
  hasSubstr vs "automation.methods[0].method must be one of" &&
  hasSubstr vs "review.status is required"

-- Types and enumerations inside the nested records, with the path that names them.
/-- info: true -/
#guard_msgs in
#eval
  let vs := String.intercalate "\n" (validationOf yamlBadTypes).toList
  hasSubstr vs "sources[0].relationship must be one of" &&
  hasSubstr vs "sources[0].author_endorsement must be one of" &&
  hasSubstr vs "sources[0].contributors[0].role is required" &&
  hasSubstr vs "status.sorry_count must be a non-negative integer"

-- The schema's two `repository` conditionals, which a shape check has to encode by hand.
/-- info: true -/
#guard_msgs in
#eval
  let wrapper := validationOf (yamlV04.replace "  role: \"substantive-development\""
    "  role: \"thin-wrapper\"")
  let both := validationOf (yamlV04.replace "  role: \"substantive-development\""
    "  role: \"substantive-development\"\n  substantive_formalization:\n    id: \"https://example.org/x\"")
  hasSubstr (String.intercalate "\n" wrapper.toList)
    "repository.substantive_formalization is required when repository.role is thin-wrapper" &&
  hasSubstr (String.intercalate "\n" both.toList)
    "must be absent when repository.role is substantive-development"

-- An empty value is the parser's reading of a blank field, and reads as absent — which for
-- a required field is "required", not "empty".
/-- info: true -/
#guard_msgs in
#eval
  let blank := validationOf "project:\n  name:\n  authors: [\"E\"]\n  license: \"X\"\nsources:\n  - title: \"T\"\nautomation:\n  methods:\n    - method: \"manual\"\nreview:\n  status: \"unchecked\"\n"
  blank == #["project.name is required"]

/-! The gate: off by default, and when on a violation stops the build with every problem
named and the check described as what it is. -/

private def checkOutcome (act : CoreM Unit) : CoreM String := do
  try
    act
    return "ok"
  catch e => return (← e.toMessageData.toString)

/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let off := Lean.Options.empty
  let on := off.setBool verso.blueprint.trust.validateFormalizationYaml.name true
  let broken := parsed! yamlBroken
  let quiet ← checkOutcome (checkFormalizationYaml off "f.yaml" broken)
  let loud ← checkOutcome (checkFormalizationYaml on "f.yaml" broken)
  let clean ← checkOutcome (checkFormalizationYaml on "f.yaml" (parsed! yamlV04))
  -- Unset ⇒ nothing is checked and nothing is claimed. Set ⇒ every violation, and the
  -- sentence saying how much of the standard this check covers.
  return quiet == "ok" && clean == "ok" &&
    hasSubstr loud "does not satisfy the formalization.yaml v0.4 standard (6 problems)" &&
    hasSubstr loud "project.name is required" &&
    hasSubstr loud "a subset check derived from the v0.4 JSON Schema, not a general validator"

/-! ### v0.4 rendering

Additive: a v0.3 document renders what it always did, and the v0.4 blocks appear only for
documents that carry them.
-/

private def emptyState : TraverseState := TraverseState.initialize default

private def renderedV04 (validated : Bool := false) : String :=
  (renderFormalization emptyState (parsed! yamlV04) validated).asString

private def renderedV03 : String :=
  (renderFormalization emptyState (parsed! yamlRealWorld)).asString

/-- info: true -/
#guard_msgs in
#eval
  let html := renderedV04
  -- Contributors: name, role, and a link when the entry carries one. Names and links only
  -- — this page renders no avatars.
  hasSubstr html "Contributors" && hasSubstr html "A Referee" && hasSubstr html "(editor)" &&
  hasSubstr html "href=\"https://example.org/referee\"" &&
  !hasSubstr html "avatar" && !hasSubstr html "<img" && !hasSubstr html "<svg" &&
  -- Classification chips: arXiv categories link to their listing, MSC codes are text.
  hasSubstr html "Classification" &&
  hasSubstr html "href=\"https://arxiv.org/list/math.NT/recent\"" &&
  hasSubstr html "11J72" && hasSubstr html "11N13" &&
  !hasSubstr html "href=\"https://arxiv.org/list/11J72/recent\"" &&
  -- The per-source v0.4 fields.
  hasSubstr html "Relationship" && hasSubstr html "formalizes" &&
  hasSubstr html "Location" && hasSubstr html "Author endorsement" &&
  -- The v0.4 project and repository blocks.
  hasSubstr html "Responsible maintainers" &&
  hasSubstr html "The prime race constant is irrational." &&
  hasSubstr html "Related formalizations"

-- A v0.3 document is untouched by all of it: none of the v0.4 blocks appear, and the rows
-- it always had still do.
/-- info: true -/
#guard_msgs in
#eval
  let html := renderedV03
  !hasSubstr html "Classification" && !hasSubstr html "Contributors" &&
  !hasSubstr html "Related formalizations" && !hasSubstr html "Repository" &&
  !hasSubstr html "Relationship" && !hasSubstr html "Author endorsement" &&
  !hasSubstr html "Responsible maintainers" &&
  !hasSubstr html "subset check derived" &&
  !hasSubstr html "bp_formalization_warning" &&
  hasSubstr html "Author contacted" &&
  hasSubstr html "A362583 Irrationality" &&
  hasSubstr html "Alignment"

-- The gate's own provenance line: rendered when the gate ran, absent when it did not, and
-- the only difference between the two pages.
/-- info: true -/
#guard_msgs in
#eval
  let off := renderedV04
  let on := renderedV04 (validated := true)
  !hasSubstr off "Checked at build time" &&
  hasSubstr on "Checked at build time against a subset check derived from the v0.4 JSON Schema, \
    not a general validator." &&
  countSubstr on "bp_formalization_note" == countSubstr off "bp_formalization_note" + 1 &&
  countSubstr on "bp_formalization_section" == countSubstr off "bp_formalization_section"

-- The one thing a v0.4 document cannot omit and still say anything. A v0.3 document with no
-- sources gets no v0.4 warning, because v0.3 did not require one.
/-- info: true -/
#guard_msgs in
#eval
  let broken := (renderFormalization emptyState (parsed! yamlBroken)).asString
  let v03 := (renderFormalization emptyState
    (parsed! "version: \"v0.3\"\nproject:\n  name: \"X\"\n")).asString
  hasSubstr broken "bp_formalization_warning" &&
  hasSubstr broken "requires at least one entry under" &&
  !hasSubstr v03 "bp_formalization_warning"

-- The two Phase-4 cosmetic findings: the badge under a "Review" heading no longer says
-- "review", and a fields container with no rows in it is not emitted.
/-- info: true -/
#guard_msgs in
#eval
  let v03 := renderedV03
  let v04 := renderedV04
  !hasSubstr v03 ">review: agent-reviewed<" &&
  hasSubstr v03 ">agent-reviewed<" &&
  !hasSubstr v04 "<div class=\"bp_formalization_fields\"></div>" &&
  !hasSubstr v03 "<div class=\"bp_formalization_fields\"></div>"

end Verso.VersoBlueprintTests.BlueprintFormalization
