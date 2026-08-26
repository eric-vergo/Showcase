/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint
import VersoBlueprintTests.Blueprint.Support
import VersoManual

/-!
Run evidence and content binding, exercised end to end through the real option path.

`BlueprintFormalization` unit-tests the two rules against constructed payloads. This
file loads them the way a consumer does — `verso.blueprint.trust.*` pointing at
`tests/fixtures/trust/` — and renders the surfaces that present them, so the wiring
between "what the artifact says" and "what the page claims" is covered as well as the
predicates.

Two consequences worth stating, because they are the point:

- **This module elaborating at all is the positive digest test.** The fixture status
  records SHA-256 digests of the three files beside it; the site build hashes the bytes
  it is about to display and refuses to continue if they disagree. Corrupt a fixture byte
  without refreshing its digest and the suite stops here.

- **The fixture is deliberately a legacy record.** It carries `nanoda_ref` but no
  `nanoda_replay`, while the fixture config sets `enable_nanoda: true`. Configuration says
  a future run will replay; the run record says nothing; so no surface may claim a second
  kernel checked this verdict.
-/

namespace Verso.VersoBlueprintTests.TrustEvidence

open Lean
open Verso Genre Manual
open Informal Informal.Commands
open Verso.VersoBlueprintTests.Blueprint.Support

set_option verso.blueprint.trust.comparatorStatus "tests/fixtures/trust/comparator-status.json"
set_option verso.blueprint.trust.comparatorConfig "tests/fixtures/trust/comparator.json"
set_option verso.blueprint.trust.challengeFile "tests/fixtures/trust/Challenge.lean"
set_option verso.blueprint.trust.solutionFile "tests/fixtures/trust/Solution.lean"

-- A document carrying the two surfaces under test: the dashboard (which loads the trust
-- payload and runs the axiom audit) and the trust-model page. The node's `(lean := …)`
-- reference gives the audit something to count, so the kernel row has a measurement to
-- report rather than degrading to "not checked".
#docs (Manual) trustEvidenceDoc "Trust Evidence" :=
:::::::
:::theorem "trust.evidence.anchor" (lean := "Nat.add_comm")
Addition on the naturals commutes.
:::

{blueprint_dashboard}

{blueprint_trust_model}
:::::::

/-! ## The kernel row is measured, not badged -/

-- CX-005: the row used to read "every declaration" behind an unconditional green badge,
-- on a site that also renders Lean it never elaborated. It must now show a count drawn
-- from the audit and name its exclusions.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let html ← renderManualDocHtmlString extension_impls% trustEvidenceDoc
  return hasSubstr html "Kernel type-checking" &&
    -- Measured: the audit counted exactly the one wired declaration.
    hasSubstr html ">1 declaration<" &&
    hasSubstr html "The 1 declaration(s) this build enumerated" &&
    -- The unconditional claim is gone.
    !hasSubstr html ">every declaration<" &&
    !hasSubstr html "Every Lean declaration presented here" &&
    -- The exclusion, cross-referencing the tier legend on the same page.
    hasSubstr html "is source text this build read" &&
    hasSubstr html "claim and solution blocks" &&
    hasSubstr html "rendering-tier legend"

/-! ## No nanoda claim without a run record -/

-- CX-011, on the trust-model page: `enable_nanoda` in the configuration must not put
-- nanoda into what the reader is told they are trusting.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let html ← renderManualDocHtmlString extension_impls% trustEvidenceDoc
  return !hasSubstr html "as the independent kernel the run recorded" &&
    !hasSubstr html "pins its independent kernel" &&
    hasSubstr html "does not say that the run performed one" &&
    -- CX-012: sandbox coverage is claimed for the replay step only.
    hasSubstr html "the sandbox the comparator replay ran under" &&
    hasSubstr html "happened outside the sandbox"

/-! ## Run-evidence predicates

Absence of `nanoda_replay` is `false`, and is never filled in from `enable_nanoda`.
-/

/-- info: (false, false, true, false) -/
#guard_msgs in
#eval
  -- Configuration on, a pinned revision recorded, and no run record: still `false`.
  let unrecorded : TrustComparator := { enableNanoda := true, nanodaRef := "abc" }
  (unrecorded.replayedWithNanoda,
   unrecorded.nanodaReplayRecorded,
   { unrecorded with nanodaReplay := some true : TrustComparator }.replayedWithNanoda,
   { unrecorded with nanodaReplay := some false : TrustComparator }.replayedWithNanoda)

-- Drift is reported only when there is a record to disagree with, and carries which way
-- it went (`some true` ⇒ the configuration now enables what the run did not do).
/-- info: (none, some true, some false, none) -/
#guard_msgs in
#eval
  let base : TrustComparator := { enableNanoda := true }
  (base.nanodaConfigDrift?,
   { base with nanodaReplay := some false : TrustComparator }.nanodaConfigDrift?,
   { base with enableNanoda := false, nanodaReplay := some true : TrustComparator }.nanodaConfigDrift?,
   { base with nanodaReplay := some true : TrustComparator }.nanodaConfigDrift?)

/-! ## The build-time checks

`"ok"` means the check passed; anything else is the error message it threw.
-/

private def checkOutcome (act : CoreM Unit) : CoreM String := do
  try
    act
    return "ok"
  catch e => return (← e.toMessageData.toString)

-- A claimed replay must name its kernel: `nanoda_replay: true` with no `nanoda_ref` is a
-- second-kernel assurance nobody can check or reproduce.
/-- info: (true, "ok", "ok") -/
#guard_msgs in
#eval show CoreM (Bool × String × String) from do
  let incomplete ← checkOutcome
    (checkComparatorRunProvenance { nanodaReplay := some true, nanodaRef := "  " } "status.json")
  let complete ← checkOutcome
    (checkComparatorRunProvenance { nanodaReplay := some true, nanodaRef := "1a2b3c" } "status.json")
  let noClaim ← checkOutcome
    (checkComparatorRunProvenance { nanodaRef := "" } "status.json")
  return (hasSubstr incomplete "no `nanoda_ref`", complete, noClaim)

private def boundClaim : String := "-- the claim\n"
private def otherClaim : String := "-- a different claim\n"

private def boundComparator : TrustComparator :=
  {
    challengeSource := boundClaim
    challengeSha256 := Informal.Sha256.hexOfString boundClaim
    challengeDigest := Informal.Sha256.hexOfString boundClaim
    solutionSource := "-- the solution\n"
    configJson := "{}"
  }

-- Agreement passes; a recorded digest with no displayed file, and a displayed file with
-- no recorded digest, are both unbound rather than failures (legacy artifacts build).
/-- info: ("ok", "ok") -/
#guard_msgs in
#eval show CoreM (String × String) from do
  let bound ← checkOutcome (checkComparatorDigests boundComparator "status.json")
  let unbound ← checkOutcome (checkComparatorDigests
    { challengeSource := boundClaim, challengeDigest := Informal.Sha256.hexOfString boundClaim }
    "status.json")
  return (bound, unbound)

-- The substitution CX-014 is about: same file name, same path shape, different bytes.
-- Every identifier check passes; the digest does not, and the build stops with both
-- digests named.
/-- info: (true, true, true, true) -/
#guard_msgs in
#eval show CoreM (Bool × Bool × Bool × Bool) from do
  let substituted :=
    { boundComparator with
      challengeSource := otherClaim
      challengeDigest := Informal.Sha256.hexOfString otherClaim }
  let msg ← checkOutcome (checkComparatorDigests substituted "status.json")
  return (hasSubstr msg "is not the one the comparator verdict certifies",
          hasSubstr msg (Informal.Sha256.hexOfString boundClaim),
          hasSubstr msg (Informal.Sha256.hexOfString otherClaim),
          hasSubstr msg "verso.blueprint.trust.challengeFile")

-- Case, surrounding space, and a `sha256:` prefix are spelling, not substitution.
/-- info: "ok" -/
#guard_msgs in
#eval show CoreM String from
  checkOutcome (checkComparatorDigests
    { boundComparator with
      challengeSha256 := " SHA256:" ++ (Informal.Sha256.hexOfString boundClaim).toUpper ++ " " }
    "status.json")

/-! ## The comparator page states only what the run recorded -/

private def fixtureComparator : TrustComparator :=
  {
    status := "verified"
    verifiedAt := "2026-08-04T00:00:00Z"
    theoremNames := ["TrustFixture.add_comm_claim"]
    challengeSource := "theorem claim : True := trivial\n"
    solutionSource := "theorem claim : True := trivial\n"
    configJson := "{}"
    nanodaRef := "1111111111111111111111111111111111111111"
    landrunRef := "2222222222222222222222222222222222222222"
  }

private def comparatorHtml (cmp : TrustComparator) : String :=
  (comparatorBody cmp (some "https://ci.example/run/1") (some 3) none).asString

-- Configuration enables the replay; the run recorded nothing. No past-tense claim, and
-- the gap is stated — but the reproduce commands still describe the configuration, which
-- is the one thing it legitimately governs.
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml { fixtureComparator with enableNanoda := true }
  !hasSubstr html "nanoda replays included" &&
  !hasSubstr html "independently the nanoda kernel" &&
  -- Not listed among what the run was "Checked with", either: a recorded revision pins a
  -- program, it does not evidence a check.
  !hasSubstr html "nanoda 1111111111111111111111111111111111111111" &&
  hasSubstr html "predates the field that says whether the" &&
  hasSubstr html "nanoda_lib"

-- The run recorded a replay: now — and only now — the page may say so.
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml
    { fixtureComparator with enableNanoda := true, nanodaReplay := some true }
  hasSubstr html "nanoda replays included" &&
  hasSubstr html "independently the nanoda kernel" &&
  hasSubstr html "nanoda 1111111111111111111111111111111111111111" &&
  !hasSubstr html "predates the field"

-- Disagreement in either direction reads as drift, not as one side winning.
/-- info: (true, true) -/
#guard_msgs in
#eval
  let configOnly := comparatorHtml
    { fixtureComparator with enableNanoda := true, nanodaReplay := some false }
  let runOnly := comparatorHtml
    { fixtureComparator with enableNanoda := false, nanodaReplay := some true }
  (hasSubstr configOnly "configuration has changed since this verdict" &&
     !hasSubstr configOnly "nanoda replays included",
   hasSubstr runOnly "configuration has changed since this verdict" &&
     hasSubstr runOnly "nanoda replays included")

/-! ## The comparator page discloses how the source is bound to the verdict -/

-- Nothing recorded: the tie is a filename, and the page says exactly that.
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml fixtureComparator
  !hasSubstr html "required them to equal the SHA-256 digests" &&
  hasSubstr html "identifiers, not contents" &&
  hasSubstr html "would be displayed here without"

-- Recorded for the claim, absent for the rest: both halves are stated.
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml { fixtureComparator with
    challengeSha256 := Informal.Sha256.hexOfString fixtureComparator.challengeSource }
  hasSubstr html "required them to equal the SHA-256 digests the verifying run recorded" &&
  hasSubstr html "identifiers, not contents"

/-- info: (["the claim"], ["the solution", "the configuration"]) -/
#guard_msgs in
#eval
  let cmp := { fixtureComparator with
    challengeSha256 := Informal.Sha256.hexOfString fixtureComparator.challengeSource }
  (cmp.contentBound, cmp.contentUnbound)

/-! ## A label is not a kernel (CX-064)

The comparator's `external_kernels` key is consumer-chosen text it prints and then runs
the associated command under, reading exit status zero as acceptance. No surface may turn
that into a second-kernel assurance.
-/

private def spoofedKernel : TrustComparator :=
  { fixtureComparator with
    -- `{"nanoda": ["/usr/bin/true"]}` in the configuration, a replay and a revision in
    -- the status artifact, and nothing binding either to a program.
    externalKernels := #[("nanoda", "")]
    enableNanoda := true
    kernelReplays := #[("nanoda", true)]
    kernelRefs := #[("nanoda", "f58f2f6d")] }

private def boundKernel : TrustComparator :=
  { fixtureComparator with
    kernelIdentities := #[
      { label := "nanoda", adapterKind := "nanoda"
        repository := "https://github.com/ammkrn/nanoda_lib"
        sourceCommit := "05055695", executableSha256 := "abcdef01"
        commandArgv := #["/opt/nanoda_bin"], replayed := true, verdict := "accepted" },
      { label := "lean4lean", repository := "https://github.com/x/lean4lean"
        sourceCommit := "cc11dd22", executableSha256 := "9876fedc", replayed := true }]
    kernelReplays := #[("nanoda", true), ("lean4lean", true)]
    kernelRefs := #[("nanoda", "05055695"), ("lean4lean", "cc11dd22")] }

-- The spoofable shape: the page names no second kernel, keeps the label out of "Checked
-- with", and says in the table and in prose what the record does and does not establish.
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml spoofedKernel
  !hasSubstr html "independently the nanoda kernel" &&
  !hasSubstr html "nanoda f58f2f6d" &&
  !hasSubstr html "nanoda replays included" &&
  hasSubstr html "external checker labeled" &&
  hasSubstr html "not authenticated" &&
  hasSubstr html "recorded separately, not bound to it" &&
  hasSubstr html "The comparator takes that label from its configuration"

-- A record that binds a source revision and an executable digest to the repository this
-- fork knows nanoda by earns the name; one that binds them to something else does not.
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml boundKernel
  hasSubstr html "independently the nanoda kernel" &&
  hasSubstr html "nanoda 05055695" &&
  hasSubstr html "binary <code>abcdef01</code>" &&
  -- The second checker is identified but not one this site knows by name, so it is
  -- reported as an external checker rather than as a kernel.
  hasSubstr html "external checker labeled" &&
  hasSubstr html "not a checker this site knows by that name" &&
  !hasSubstr html "lean4lean and nanoda kernels" &&
  !hasSubstr html "checkers labeled" &&
  hasSubstr html "a checker labeled" &&
  hasSubstr html "<code>lean4lean</code>"

-- One authenticated kernel needs no table; more than one checker, or one this site
-- cannot name, does.
/-- info: (false, true, true) -/
#guard_msgs in
#eval
  (hasSubstr (comparatorHtml { fixtureComparator with nanodaReplay := some true })
     "bp_trust_kernel_table",
   hasSubstr (comparatorHtml spoofedKernel) "bp_trust_kernel_table",
   hasSubstr (comparatorHtml boundKernel) "bp_trust_kernel_table")

-- A claimed replay must still name a revision, and the message says a revision is not
-- the binding.
/-- info: (true, true, "ok") -/
#guard_msgs in
#eval show CoreM (Bool × Bool × String) from do
  let unnamed ← checkOutcome
    (checkComparatorRunProvenance { kernelReplays := #[("lean4lean", true)] } "status.json")
  let complete ← checkOutcome (checkComparatorRunProvenance
    { kernelReplays := #[("lean4lean", true), ("nanoda", true)]
      kernelRefs := #[("lean4lean", "cc11"), ("nanoda", "f58f")] } "status.json")
  -- Short substrings: the error formatter wraps long lines.
  return (hasSubstr unnamed "`lean4lean`", hasSubstr unnamed "sufficient", complete)

/-! ## The comparator tool's own toolchain (CX-053) -/

-- Recorded ⇒ the row and the note say which toolchain the tool was built on; absent ⇒ the
-- reproduce section says the commands build it on the tool's own, rather than implying an
-- exact replay.
/-- info: (true, true) -/
#guard_msgs in
#eval
  let recorded := comparatorHtml { fixtureComparator with
    toolRef := "v4.33.0", toolSha := "abc123", toolToolchain := "leanprover/lean4:v4.33.1" }
  let legacy := comparatorHtml { fixtureComparator with toolRef := "v4.33.0", toolSha := "abc123" }
  (hasSubstr recorded "Tool built on" && hasSubstr recorded "leanprover/lean4:v4.33.1" &&
     hasSubstr recorded "rebuilt the comparator on this project's toolchain",
   !hasSubstr legacy "Tool built on" &&
     hasSubstr legacy "does not say which Lean toolchain the comparator itself was")

/-! ## The subject revision the run verified (CX-068) -/

-- Recorded ⇒ the reproduce section says the pinned verifiers see the same bytes; absent ⇒
-- it says plainly that the flow runs against today's tree.
/-- info: (true, true) -/
#guard_msgs in
#eval
  let pinned := comparatorHtml { fixtureComparator with
    repoUrl := "https://github.com/o/r", commit := "76ea8221" }
  let unpinned := comparatorHtml { fixtureComparator with repoUrl := "https://github.com/o/r" }
  (hasSubstr pinned "the revision the recorded run verified" &&
     hasSubstr pinned "git checkout 76ea8221",
   hasSubstr unpinned "current default branch" &&
     hasSubstr unpinned "not an exact reproduction of the run above")

/-! ## A transcribed upstream record is not a verification (CX-042) -/

private def upstreamComparator : TrustComparator :=
  { fixtureComparator with
    status := "reported-upstream"
    reportedSource := "anthropics/zeta-23-lean" }

-- The page names the source, refuses the success tier, and — crucially — refuses
-- `verified_at`'s date, which describes a run this site did not perform.
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml upstreamComparator
  hasSubstr html "Reported upstream" &&
  hasSubstr html "Transcribed from records published by anthropics/zeta-23-lean" &&
  hasSubstr html "Names 1 theorem" &&
  !hasSubstr html "CI-verified" &&
  !hasSubstr html "bp_summary_badge_success" &&
  !hasSubstr html "Certifies 1 theorem" &&
  !hasSubstr html "2026-08-04"

-- The upstream record's own date, when it has one, is the only date it may show.
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml { upstreamComparator with reportedAt := "2026-07-01T00:00:00Z" }
  hasSubstr html "Reported upstream 2026-07-01" &&
  hasSubstr html "datetime=\"2026-07-01T00:00:00Z\"" &&
  !hasSubstr html "2026-08-04"

-- On the strip: a neutral badge, a scope line that reports rather than certifies, and no
-- contribution to the success aggregate.
/-- info: (true, true, true) -/
#guard_msgs in
#eval
  let strip := (trustStripHtml { comparator := some upstreamComparator }
    Option.none Option.none Option.none (some 9)).asString
  let badge := (trustAggregateComparatorBadge
    [{ name := "A", comparator := fixtureComparator },
     { name := "B", comparator := upstreamComparator }]).asString
  (hasSubstr strip "comparator: reported upstream" && !hasSubstr strip "badge_success",
   hasSubstr strip "reported verified upstream: 1 theorem of 9",
   hasSubstr badge "1/2 configs verified" && hasSubstr badge "badge_warn")

/-! ## Multi-config trust surface: N topics render N panels plus an aggregate -/

private def mcTopic (name : String) (thms : List String) : ComparatorTopic :=
  { name, comparator := { fixtureComparator with theoremNames := thms } }

private def mcAxiomDecl : AxiomAuditDecl :=
  { name := "Zeta23.PairCeiling.bound", axioms := ["propext", "Classical.choice"] }

private def mcAxiomTopic : AxiomAuditTopic :=
  { name := "PairCeiling axioms", decls := [mcAxiomDecl] }

private def multiConfigHtml : String :=
  (comparatorsPageBody
    [mcTopic "Main statements" ["Zeta23.thmA", "Zeta23.thmB"],
     mcTopic "Multiplicity" ["Zeta23.thmC"],
     mcTopic "XiPrime zeros" ["Zeta23.xiDeriv"]]
    [mcAxiomTopic]
    (some "https://ci.example/run/1") (some 20) none).asString

-- Three comparator topics render three titled panels; the config-less axiom-audit topic
-- renders a fourth; and the header aggregates the certified theorems (2 + 1 + 1 = 4) of 20
-- across 3 comparator configs.
/-- info: (3, true, true, true) -/
#guard_msgs in
#eval
  (countSubstr multiConfigHtml "bp_trust_topic_title",
   hasSubstr multiConfigHtml "4 independently comparator-certified theorems of 20",
   hasSubstr multiConfigHtml "across 3 comparator configs",
   hasSubstr multiConfigHtml "PairCeiling axioms" &&
     hasSubstr multiConfigHtml "Zeta23.PairCeiling.bound")

/-! ## The headline counts what was certified, not what was configured

CX-042 on this fork's own page: the aggregate sentence used to sum every topic's theorem
names, so a project whose configs had all merely been configured — or whose verdicts were
transcribed from someone else's records — was told it presented that many "independently
comparator-certified" theorems. The count now uses the same predicate as the aggregate
badge, and the rest is described as what it is.
-/

private def mcConfigured (name : String) (thms : List String) : ComparatorTopic :=
  { name, comparator := { fixtureComparator with status := "configured", theoremNames := thms } }

private def mcUpstream (name : String) (thms : List String) : ComparatorTopic :=
  { name, comparator := { upstreamComparator with theoremNames := thms } }

private def mixedTopicsHtml : String :=
  (comparatorsPageBody
    [mcTopic "Main statements" ["Zeta23.thmA", "Zeta23.thmB"],
     mcConfigured "Multiplicity" ["Zeta23.thmC"],
     mcUpstream "Transcribed" ["Zeta23.thmD"]]
    [] (some "https://ci.example/run/1") (some 20) none).asString

-- One verified topic of three: two certified theorems, and the other two named as what
-- they are rather than folded into the certified count.
/-- info: true -/
#guard_msgs in
#eval
  hasSubstr mixedTopicsHtml "2 independently comparator-certified theorems of 20" &&
  hasSubstr mixedTopicsHtml "across 1 of 3 comparator configs" &&
  hasSubstr mixedTopicsHtml
    "A further 2 theorems are configured but not yet run or reported verified upstream" &&
  hasSubstr mixedTopicsHtml "does not present as certified" &&
  -- The old, false headline is gone.
  !hasSubstr mixedTopicsHtml "4 independently comparator-certified"

-- The zeta shape: every topic configured, nothing certified. Said plainly.
/-- info: true -/
#guard_msgs in
#eval
  let html := (comparatorsPageBody
    [mcConfigured "A" ["Zeta23.thmA"], mcConfigured "B" ["Zeta23.thmB", "Zeta23.thmC"]]
    [] Option.none (some 20) Option.none).asString
  hasSubstr html "presents no independently comparator-certified theorems of its 20" &&
  hasSubstr html "Its 2 comparator configs name 3 theorems that are configured but not yet run" &&
  !hasSubstr html "3 independently comparator-certified"

/-! ## Scale cap (c): the degraded rendering tiers render their honest glyphs -/

-- When the registry skips full re-elaboration above `fullElabMaxDecls`, signatures fall to
-- the `signature` tier and proof bodies to `syntactic`; both must render a visible marker so
-- the page shows the code was not re-elaborated (never a silent downgrade).
/-- info: (true, true) -/
#guard_msgs in
#eval
  (hasSubstr (Informal.NodeCard.tierMarker (some "signature")).asString "bp_tier_marker",
   hasSubstr (Informal.NodeCard.tierMarker (some "syntactic")).asString "bp_tier_marker")

end Verso.VersoBlueprintTests.TrustEvidence
