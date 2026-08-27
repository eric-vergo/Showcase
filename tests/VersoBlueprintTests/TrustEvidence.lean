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
set_option verso.blueprint.trust.expectedKernelIdentities "tests/fixtures/trust/kernel-identities.json"

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
    -- Section 5 used to make this point in nanoda-specific prose; it is now the currency
    -- row's own sentence, which says the same thing per checker.
    hasSubstr html "does not say a replay happened" &&
    -- CX-012: sandbox coverage is claimed for the replay step only.
    hasSubstr html "the sandbox the comparator replay ran under" &&
    hasSubstr html "happened outside the sandbox"

/-! ## Run-evidence predicates

Absence of `nanoda_replay` is `false`, and is never filled in from `enable_nanoda`.
-/

/-- info: (false, false, true, false, false) -/
#guard_msgs in
#eval
  -- The site's own pin: the second source the label has to agree with (CX-064).
  let pins : Array KernelIdentityPin :=
    #[{ label := "nanoda", repository := "https://github.com/ammkrn/nanoda_lib",
        sourceCommit := "05055695879dfebb6628a67da88ceca6cd6b0421" }]
  -- Configuration on, a pinned revision recorded, and no run record: still `false`.
  let unrecorded : TrustComparator :=
    ({ enableNanoda := true, nanodaRef := "05055695" } : TrustComparator).withExpectedIdentities pins
  (unrecorded.replayedWithNanoda,
   unrecorded.nanodaReplayRecorded,
   { unrecorded with nanodaReplay := some true : TrustComparator }.replayedWithNanoda,
   { unrecorded with nanodaReplay := some false : TrustComparator }.replayedWithNanoda,
   -- The same record with nothing pinned behind it establishes nothing: a label and a
   -- revision typed beside it are the producer's own word.
   { unrecorded with nanodaReplay := some true, expectedIdentities := #[]
     : TrustComparator }.replayedWithNanoda)

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

/-- The pin file beside the fixture, as a value: the consumer half of the identity check.
The status artifact's `nanoda_ref` agrees with it, which is what lets the currency rows
below assess the revision at all (CX-064). -/
private def fixtureKernelPin : KernelIdentityPin :=
  { label := "nanoda"
    repository := "https://github.com/ammkrn/nanoda_lib"
    sourceCommit := "1111111111111111111111111111111111111111" }

private def fixtureComparator : TrustComparator :=
  {
    expectedIdentities := #[fixtureKernelPin]
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

-- The run recorded a replay: now — and only now — the page may report one. It reports it
-- as the record's own account, never as something this site established (CX-064).
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml
    { fixtureComparator with enableNanoda := true, nanodaReplay := some true }
  hasSubstr html "record additionally names a nanoda replay" &&
  hasSubstr html "The linked run's record additionally names a replay by nanoda, built by \
    the run's CI from 1111111111111111111111111111111111111111" &&
  -- What "authenticated" means here, said where the claim is: two sources agree.
  hasSubstr html "agrees with one this site's author pinned" &&
  hasSubstr html "not as an attestation that it ran" &&
  -- and no tier, this one included, licenses the categorical sentence
  !hasSubstr html "independently the nanoda kernel" &&
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
     !hasSubstr configOnly "record additionally names a nanoda replay",
   hasSubstr runOnly "configuration has changed since this verdict" &&
     hasSubstr runOnly "record additionally names a nanoda replay")

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
        sourceCommit := "05055695", executableSha256 := "f035ee955e00221ee35fe819ac1ea5818edce8a459fffd380120a450373be6dc"
        commandArgv := #["/opt/nanoda_bin"], replayed := true, verdict := "accepted" },
      { label := "lean4lean", repository := "https://github.com/x/lean4lean"
        sourceCommit := "cc11dd22", executableSha256 := "74252c1798f3db857bbb88b7386c80b2ce812e7e27ed9b2abc1f278f4d85eb84", replayed := true }]
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
  !hasSubstr html "record additionally names a nanoda replay" &&
  hasSubstr html "external checker labeled" &&
  hasSubstr html "not authenticated" &&
  hasSubstr html "recorded separately, not bound to it" &&
  hasSubstr html "The comparator takes that label from its configuration"

-- A record that binds a well-formed source revision and executable digest to the
-- repository this fork knows nanoda by earns the name; one that binds them to something
-- else does not. What the name earns is attribution — the record's fields, printed as the
-- producing CI's account — and never the categorical sentence (CX-064).
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml boundKernel
  !hasSubstr html "independently the nanoda kernel" &&
  hasSubstr html "The linked run's record additionally names a replay by nanoda, built \
    from 05055695, binary" &&
  hasSubstr html "nothing here re-ran the checker, fetched that revision, or hashed the \
    binary against it" &&
  hasSubstr html "nanoda 05055695" &&
  hasSubstr html "binary <code>f035ee955e00221ee35fe819ac1ea5818edce8a459fffd380120a450373be6dc</code>" &&
  -- The second checker is identified but not one this site knows by name, so it is
  -- reported as an external checker rather than as a kernel.
  hasSubstr html "external checker labeled" &&
  hasSubstr html "not a checker this site knows by that name" &&
  !hasSubstr html "lean4lean and nanoda kernels" &&
  !hasSubstr html "checkers labeled" &&
  hasSubstr html "a checker labeled" &&
  hasSubstr html "<code>lean4lean</code>"

-- Every checker the verdict mentions gets a row, one or many (CX-070): the one-row
-- shortcut used to hide exactly the states this table exists to show.
/-- info: (true, true, true, false) -/
#guard_msgs in
#eval
  (hasSubstr (comparatorHtml { fixtureComparator with nanodaReplay := some true })
     "bp_trust_kernel_table",
   hasSubstr (comparatorHtml spoofedKernel) "bp_trust_kernel_table",
   hasSubstr (comparatorHtml boundKernel) "bp_trust_kernel_table",
   -- A verdict that mentions no checker at all still renders no table.
   hasSubstr (comparatorHtml { fixtureComparator with nanodaRef := "" })
     "bp_trust_kernel_table")

/-! ## Single-checker states stay visible (CX-070)

One checker is the ordinary deployment shape. Suppressing its row dropped the configured
checker with no run record, the recorded decline, the checker dropped from the
configuration since, and — behind an authenticated success — the executable digest that
the "Checked with" row names no part of.
-/

private def soleChecker (replay? : Option Bool) (configured : Bool) : TrustComparator :=
  { fixtureComparator with
    nanodaRef := "", landrunRef := ""
    externalKernels := if configured then #[("acme", "")] else #[]
    kernelReplays := match replay? with
      | some b => #[("acme", b)]
      | none => #[]
    kernelRefs := #[("acme", "r1")] }

/-- info: (true, true, true, true) -/
#guard_msgs in
#eval
  let cell := fun (c : TrustComparator) (needle : String) =>
    hasSubstr (comparatorHtml c) needle
  -- Configured, no run record: the row says so instead of the page saying nothing.
  (cell (soleChecker none true) "not recorded" &&
     cell (soleChecker none true) "external checker labeled",
   -- A recorded decline is a verdict, and it renders.
   cell (soleChecker (some false) true) "not replayed",
   -- Dropped from the configuration since the run: the label survives, and the
   -- disagreement is shown per checker rather than only for nanoda.
   cell (soleChecker (some true) false) "changed since this verdict" &&
     cell (soleChecker (some true) false) "not enabled",
   -- Enabled after the run that never ran it: drift the other way.
   cell (soleChecker (some false) true) "changed since this verdict")

-- The sole authenticated success: "Checked with" names the revision, and the digest —
-- which nothing else on the page renders — is in the table.
/-- info: true -/
#guard_msgs in
#eval
  let sole : TrustComparator :=
    { fixtureComparator with
      nanodaRef := ""
      kernelIdentities := #[
        { label := "nanoda", repository := "https://github.com/ammkrn/nanoda_lib"
          sourceCommit := "05055695", executableSha256 := "71aec9373ce521f160a4db531c6a865a1d6f236b3b9f99c958313bfaee639303"
          replayed := true }]
      kernelReplays := #[("nanoda", true)]
      kernelRefs := #[("nanoda", "05055695")] }
  let html := comparatorHtml sole
  hasSubstr html "nanoda 05055695" &&
  hasSubstr html "bp_trust_kernel_table" &&
  hasSubstr html "binary <code>71aec9373ce521f160a4db531c6a865a1d6f236b3b9f99c958313bfaee639303</code>"

-- The legacy a362583 shape — a recorded revision, no recorded replay — gains its row and
-- loses nothing: the revision is shown as the pin it is, and the run cell says the replay
-- was never recorded.
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml { fixtureComparator with enableNanoda := true }
  hasSubstr html "bp_trust_kernel_table" &&
  hasSubstr html "not recorded" &&
  hasSubstr html "a pin, not a check" &&
  hasSubstr html "1111111111111111111111111111111111111111" &&
  -- No replay was recorded, so nothing claims one.
  !hasSubstr html "independently the nanoda kernel"

/-! ## A record that contradicts itself fails the build (CX-069) -/

-- Two encodings of the same replay that disagree have no reading; the build stops and
-- names every disagreement rather than letting each surface pick a winner.
/-- info: (true, true, true, "ok") -/
#guard_msgs in
#eval show CoreM (Bool × Bool × Bool × String) from do
  let contradictory : TrustComparator :=
    { encodingConflicts := #["'nanoda' is recorded at revision aaa by X and at bbb by Y"] }
  let msg ← checkOutcome (checkComparatorEncodings contradictory "status.json")
  let clean ← checkOutcome (checkComparatorEncodings fixtureComparator "status.json")
  return (hasSubstr msg "contradicts itself", hasSubstr msg "revision aaa",
          hasSubstr msg "Re-run CI", clean)

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

/-! ## A local run is machine evidence; it is not CI -/

-- The presenter ran the comparator on their own machine. The kernels really ran, so
-- this is not a transcription — but the party that ran them is the party publishing
-- the page, under no sandbox, with no run record anyone can open. Its own tier.
private def localComparator : TrustComparator :=
  { fixtureComparator with
    status := "verified-local"
    localHost := "a maintainer workstation"
    localToolchain := "leanprover/lean4:v4.33.0" }

-- The page wears the accent pill, names the machine and the toolchain, says what is
-- missing, and never offers the site's CI link as this verdict's record.
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml localComparator
  hasSubstr html "Verified locally 2026-08-04 — not CI" &&
  hasSubstr html "bp_summary_badge_accent" &&
  hasSubstr html "a maintainer workstation" &&
  hasSubstr html "leanprover/lean4:v4.33.0" &&
  hasSubstr html "no sandbox isolated the run" &&
  !hasSubstr html "CI verification record" &&
  !hasSubstr html "CI-verified" &&
  !hasSubstr html "bp_summary_badge_success"

-- On the strip: accent, a scope line that says where the run happened, and no
-- contribution to the success aggregate.
/-- info: (true, true, true) -/
#guard_msgs in
#eval
  let strip := (trustStripHtml { comparator := some localComparator }
    Option.none Option.none Option.none (some 9)).asString
  let badge := (trustAggregateComparatorBadge
    [{ name := "A", comparator := fixtureComparator },
     { name := "B", comparator := localComparator }]).asString
  (hasSubstr strip "comparator: verified locally 2026-08-04 — not CI" &&
     !hasSubstr strip "badge_success",
   hasSubstr strip "verified locally, not in CI: 1 theorem of 9",
   hasSubstr badge "1/2 configs verified (1 locally)" && hasSubstr badge "badge_warn")

-- The CI tier is untouched: a `verified` record renders exactly what it rendered
-- before this tier existed.
/-- info: true -/
#guard_msgs in
#eval
  let html := comparatorHtml fixtureComparator
  hasSubstr html "CI-verified 2026-08-04" &&
  hasSubstr html "bp_summary_badge_success" &&
  hasSubstr html "CI verification record" &&
  !hasSubstr html "verified locally" &&
  !hasSubstr html "not CI"

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

/-! ### The dashboard strip's aggregate line counts the same thing

The page headline was fixed; the strip's scope line beside the aggregate badge was not, so
the site's most-read page said "certifies 23 theorems" next to a badge reading
"0/2 configs verified". Same predicate, same vocabulary, both surfaces.
-/

-- Every config verified: the sentence consumers already had, unchanged to the byte.
/-- info: true -/
#guard_msgs in
#eval
  let html := (trustAggregateScopeHtml
    [mcTopic "A" ["Zeta23.thmA", "Zeta23.thmB"], mcTopic "B" ["Zeta23.thmC"]] (some 20)).asString
  hasSubstr html "certifies 3 theorems of 20 across 2 comparator configs"

-- The zeta shape on the strip: two transcribed topics, nothing certified here.
/-- info: true -/
#guard_msgs in
#eval
  let html := (trustAggregateScopeHtml
    [mcUpstream "A" ["Zeta23.thmA"], mcUpstream "B" ["Zeta23.thmB", "Zeta23.thmC"]]
    (some 20)).asString
  hasSubstr html
    "certifies no theorems of 20; 2 comparator configs name 3 theorems, reported verified upstream" &&
  !hasSubstr html "certifies 3 theorems"

-- One of three verified: the certified count, then the remainder as what it is.
/-- info: true -/
#guard_msgs in
#eval
  let html := (trustAggregateScopeHtml
    [mcTopic "A" ["Zeta23.thmA"], mcConfigured "B" ["Zeta23.thmB"],
     mcUpstream "C" ["Zeta23.thmC"]] (some 20)).asString
  hasSubstr html "certifies 1 theorem of 20 across 1 of 3 comparator configs" &&
  hasSubstr html
    "a further 2 theorems are configured but not yet run or reported verified upstream"

/-! ## Verifier currency reaches the page (F3b)

The fixture is the interesting case rather than a convenient one: a real-shaped legacy
record, dated 2026-08-04, pinning a nanoda revision the shipped advisory table cannot
place. The run predates the fixes, so the revision it resolved predates them too — and the
page says that without claiming the replay the record never recorded.
-/

/-- info: true -/
#guard_msgs in
#eval
  let cmp := fixtureComparator.withCurrency Informal.KernelAdvisories.builtinTable
  let html := comparatorHtml cmp
  hasSubstr html "bp_trust_currency_stale" &&
  hasSubstr html "pins nanoda at 1111111111111111111111111111111111111111" &&
  hasSubstr html "a revision predating the fixes below" &&
  -- The record never said a replay happened, so no assurance is called dated.
  !hasSubstr html "second-kernel assurance" &&
  -- The advisory it was measured against is named and linked.
  hasSubstr html "https://github.com/ammkrn/nanoda_lib" &&
  -- And the clause that ages the table itself, always.
  hasSubstr html "Advisory table last updated 2026-08-25" &&
  hasSubstr html "a newer advisory would not appear here" &&
  -- A record with no currency rows renders exactly as it did before: no block at all.
  !hasSubstr (comparatorHtml fixtureComparator) "bp_trust_currency"

-- On the trust-model page, section 5 is driven by the same rows, over every config.
/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  let html ← renderManualDocHtmlString extension_impls% trustEvidenceDoc
  return hasSubstr html "Verifier currency" &&
    -- The fixture's own pin, assessed, in the list rather than in nanoda-specific prose.
    hasSubstr html "nanoda: not current" &&
    hasSubstr html "a revision predating the fixes below" &&
    hasSubstr html "Advisory table last updated 2026-08-25" &&
    -- The record names no toolchain, so the gap is stated instead of assessed.
    hasSubstr html "no verdict here records which Lean release the comparator was built on" &&
    !hasSubstr html "Lean toolchain:"

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
