/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import VersoBlueprint
import VersoBlueprintTests.Blueprint.Support
import VersoManual

/-!
The reader-facing half of the statement closure: what each rung of the degradation ladder
renders, and what it must not.

The ladder — `chain` (bound), `chain-unbound`, `claim-decls`, `unavailable` — is a ladder
of *claims about what was closed over*, and the whole point of the surface is that a
reader can tell which rung they are on without reading the source. So each rung is
asserted for its own label and against its neighbours' copy. Two rules are asserted
negatively as well as positively, because both are ways of overstating:

- **§A3.** A truncated closure reports a lower bound. The exact-count sentence, the
  favourable gradient and the graph must all be absent, and the cap must be present.
- **§A1.** An unbound closure may not carry the favourable gradient: "this is short, so
  it is easy to check" is exactly the sentence that must not be said about files nothing
  ties to the verdict.

The last section runs the real tool over the trust fixture and renders what comes back,
so the engine, the wire format, the binding and the rendering are exercised as one path
rather than three.
-/

namespace Verso.VersoBlueprintTests.StatementClosureRender

open Lean
open Verso Genre Manual
open Informal Informal.Commands
open Verso.VersoBlueprintTests.Blueprint.Support

/-! ## Fixtures -/

private def baseComparator : TrustComparator :=
  {
    status := "verified"
    verifiedAt := "2026-08-04T00:00:00Z"
    theoremNames := ["TrustFixture.add_comm_claim"]
    challengeSource := "theorem add_comm_claim (m n : Nat) : m + n = n + m := by sorry\n"
    solutionSource := "theorem add_comm_claim (m n : Nat) : m + n = n + m := Nat.add_comm m n\n"
    configJson := "{}"
  }

/-- A small closure with one declaration from each origin the copy distinguishes, plus a
piece of machinery to fold away. Deliberately hand-built: the rendering rules are what is
under test, and a fixture the engine produced would make them depend on the engine. -/
private def entries : Array StatementClosureEntry := #[
  { name := "TrustFixture.add_comm_claim", origin := "challenge", kind := "theorem"
    depth := 0, signature := "∀ (m n : Nat), m + n = n + m"
    uses := #["TrustFixture.Wrapper", "Nat"] },
  { name := "TrustFixture.Wrapper", origin := "challenge", kind := "structure"
    depth := 1, signature := "Type", uses := #["Nat"] },
  { name := "TrustFixture.Wrapper.rec", origin := "challenge", kind := "recursor"
    auxiliary := true, depth := 2, signature := "…" },
  { name := "TrustFixture.Wrapper.noConfusionType", origin := "challenge"
    kind := "def", auxiliary := true, depth := 2, signature := "Sort u" },
  { name := "Subject.raceKernel", origin := "subject", kind := "def", depth := 1
    signature := "Nat → Nat", definesModule := "Subject.Defs" },
  { name := "Subject.unpublished", origin := "subject", kind := "def", depth := 2
    signature := "Nat", definesModule := "Subject.Defs" },
  { name := "Nat", origin := "core", kind := "inductive", depth := 1, signature := "Type"
    definesModule := "Init.Prelude" },
  { name := "Real.pi", origin := "mathlib", kind := "def", depth := 2, signature := "ℝ"
    definesModule := "Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic"
    href := "https://github.com/leanprover-community/mathlib4/blob/abc/Mathlib/X.lean" }
]

private def counts : Array (String × Nat) :=
  #[("challenge", 4), ("subject", 2), ("core", 1), ("mathlib", 1)]

/-- A complete closure bound to the recorded run: the top rung. -/
private def boundClosure : StatementClosure :=
  {
    provenance := "chain"
    roots := ["TrustFixture.add_comm_claim"]
    total := 8
    outsideMathlib := 7
    untrusted := 6
    truncated := false
    maxNodes := 400
    counts
    chainFiles := #[("tests/fixtures/trust/Challenge.lean", "1811a3f8")]
    entries
  }

private def comparatorWith (c : StatementClosure) : TrustComparator :=
  { baseComparator with closure? := some c }

private def htmlOf (cmp : TrustComparator) (ctx : StatementClosurePanel.Context := {}) : String :=
  (comparatorBody cmp (some "https://ci.example/run/1") (some 3) none ctx).asString

/-! ## The surface is opt-in, and its absence is exactly the old page

The option defaults off, and a payload with no closure must leave the comparator page
byte-identical to what it rendered before this round — including the claim section, which
gains an id only when a row wants to link to it.
-/

/-- info: (true, true) -/
#guard_msgs in
#eval
  let before := htmlOf baseComparator
  let after := htmlOf (comparatorWith { provenance := "" })
  (before == after,
   !hasSubstr before "bp_closure" && !hasSubstr before "What you must read" &&
     !hasSubstr before "bp-trust-claim")

/-! ## Rung 1 — bound and complete

The only rung that gets the exact-count headline, the favourable gradient and the graph.
-/

private def boundHtml : String := htmlOf (comparatorWith boundClosure)

/-- info: true -/
#guard_msgs in
#eval
  hasSubstr boundHtml "What you must read to believe this claim" &&
  hasSubstr boundHtml "Bound to the recorded run" &&
  hasSubstr boundHtml
    "To believe this claim you must read 8 declarations (7 outside Mathlib): 4 declared in \
     the challenge chain itself, 2 from the subject project and 2 from Mathlib and Lean's \
     core libraries, used as given." &&
  -- The chain the closure was computed from, named where the claim is made.
  hasSubstr boundHtml "Chain read, in elaboration order: tests/fixtures/trust/Challenge.lean."

-- The gradient: short, so the favourable sentence, and it counts what a reader cannot
-- skip by accepting the libraries rather than the whole closure.
/-- info: true -/
#guard_msgs in
#eval
  hasSubstr boundHtml
    "The statement check here is short: outside Mathlib and Lean's core libraries, this \
     claim's meaning rests on 6 declarations." &&
  !hasSubstr boundHtml "substantial part of trusting this result"

-- Past the threshold the sentence flips, and nothing about the flip is favourable.
/-- info: true -/
#guard_msgs in
#eval
  let big := htmlOf (comparatorWith { boundClosure with untrusted := 40 })
  hasSubstr big "Reading this statement's dependencies is a substantial part of trusting this result." &&
  !hasSubstr big "The statement check here is short"

-- The boundary is the constant, not a number spelled twice.
/-- info: (true, true) -/
#guard_msgs in
#eval
  let at_ := htmlOf (comparatorWith
    { boundClosure with untrusted := StatementClosurePanel.gradientShortMax })
  let over := htmlOf (comparatorWith
    { boundClosure with untrusted := StatementClosurePanel.gradientShortMax + 1 })
  (hasSubstr at_ "The statement check here is short",
   hasSubstr over "substantial part of trusting this result")

/-! ## The reading list -/

-- Grouped by origin, with each group's own heading and count.
/-- info: true -/
#guard_msgs in
#eval
  hasSubstr boundHtml "Reading list (8)" &&
  hasSubstr boundHtml "Declared in the challenge chain" &&
  hasSubstr boundHtml "From the subject project" &&
  hasSubstr boundHtml "From Mathlib, used as given" &&
  hasSubstr boundHtml "From Lean's core libraries, used as given"

-- Machinery is folded into a subgroup that says how much it folded, and is still counted
-- in the total above it (8, not 6).
/-- info: true -/
#guard_msgs in
#eval
  hasSubstr boundHtml "compiler-generated auxiliaries (2)" &&
  hasSubstr boundHtml "TrustFixture.Wrapper.noConfusionType" &&
  hasSubstr boundHtml "Reading list (8)"

-- Depth-descending within a group: the claim itself is the last row of its group, and the
-- deepest row comes first.
/-- info: true -/
#guard_msgs in
#eval
  let deepAt := (boundHtml.splitOn "Subject.unpublished").length
  let shallowAt := (boundHtml.splitOn "Subject.raceKernel").length
  -- Both present, and `unpublished` (depth 2) is emitted before `raceKernel` (depth 1).
  deepAt > 1 && shallowAt > 1 &&
  ((boundHtml.splitOn "Subject.unpublished").head!.length <
    (boundHtml.splitOn "Subject.raceKernel").head!.length)

/-! ## Link resolution

Three origins, three resolutions, and no guessing: a name the site does not publish
renders unlinked rather than pointing at a page that was never emitted.
-/

private def resolvingCtx : StatementClosurePanel.Context :=
  { siteHref := fun n => if n == "Subject.raceKernel" then some "decl/subject_racekernel/" else none }

/-- info: (true, true, true, true) -/
#guard_msgs in
#eval
  let html := htmlOf (comparatorWith boundClosure) resolvingCtx
  (-- challenge → the claim section on this page, spelled through the page's own path so
   -- it survives the `<base>` element every emitted page carries
   hasSubstr html "href=\"comparator/#bp-trust-claim\"" && hasSubstr html "id=\"bp-trust-claim\"",
   -- subject, published here → the registry's answer
   hasSubstr html "href=\"decl/subject_racekernel/\"",
   -- library → the outbound source link the build resolved
   hasSubstr html "href=\"https://github.com/leanprover-community/mathlib4/blob/abc/Mathlib/X.lean\"",
   -- subject, not published here → no link at all, and certainly not a guessed decl slug
   !hasSubstr html "decl/subject_unpublished/")

-- Outbound library links are resolved against the real package checkouts, so this asserts
-- which of "probe" and "degrade" the probe actually does. `SubVerso.Highlighting`
-- exercises the `srcDir := "src"` layout a naive `<pkg>/<Module/Path>.lean` probe would
-- miss; a module from the toolchain rather than from a checkout is the honest unresolved
-- case, and it degrades to no link rather than to a guessed one.
/-- info: (true, true, true) -/
#guard_msgs in
#eval show IO (Bool × Bool × Bool) from do
  let root ← IO.FS.realPath (← IO.currentDir)
  let probe : Array Informal.StatementClosure.Entry := #[
    { name := "SubVerso.Highlighting.Highlighted", origin := "other", kind := "inductive"
      auxiliary := false, depth := 1, signature := "Type"
      definesModule := "SubVerso.Highlighting", uses := #[] },
    { name := "Nat", origin := "core", kind := "inductive", auxiliary := false, depth := 1
      signature := "Type", definesModule := "Init.Prelude", uses := #[] },
    { name := "TrustFixture.claim", origin := "challenge", kind := "theorem"
      auxiliary := false, depth := 0, signature := "True", definesModule := "", uses := #[] }]
  let resolved ← resolveClosureHrefs root probe
  return (
    -- Located through the package's own source layout, and pointed at the pinned revision.
    (resolved[0]!.href.splitOn "/blob/").length > 1 &&
      (resolved[0]!.href.splitOn "SubVerso/Highlighting.lean").length > 1,
    -- No checkout to link into: unlinked, not a guessed URL.
    resolved[1]!.href.isEmpty,
    -- The chain's own declarations are never linked into a dependency checkout.
    resolved[2]!.href.isEmpty)

-- Without a resolver nothing outside the challenge and the library rows is linked, and
-- the page still renders.
/-- info: (true, true) -/
#guard_msgs in
#eval
  (hasSubstr boundHtml "Subject.raceKernel", !hasSubstr boundHtml "decl/subject_racekernel/")

-- A multi-topic page anchors each panel at its own claim.
/-- info: true -/
#guard_msgs in
#eval
  let topics := [{ name := "A", comparator := comparatorWith boundClosure : ComparatorTopic },
    { name := "B", comparator := comparatorWith boundClosure }]
  let html := (comparatorsPageBody topics [] Option.none (some 9) Option.none).asString
  hasSubstr html "id=\"bp-trust-claim-1\"" && hasSubstr html "id=\"bp-trust-claim-2\"" &&
  hasSubstr html "href=\"comparator/#bp-trust-claim-1\"" &&
  hasSubstr html "href=\"comparator/#bp-trust-claim-2\""

/-! ## The meaning graph (F1b) -/

/-- info: true -/
#guard_msgs in
#eval
  hasSubstr boundHtml "Meaning graph — what the statement refers to, not how it is proved." &&
  hasSubstr boundHtml "bp_closure_graph" &&
  hasSubstr boundHtml "data-bp-graph-static=\"true\"" &&
  -- The edges the schema-2 wire format carries reached the DOT the graph is drawn from.
  hasSubstr boundHtml "\"source\":\"TrustFixture.Wrapper\",\"target\":\"TrustFixture.add_comm_claim\""

-- Past the size where a picture is one, the graph is dropped and the drop is stated with
-- the number that caused it.
/-- info: true -/
#guard_msgs in
#eval
  let wide := htmlOf (comparatorWith
    { boundClosure with
      entries := (List.range (StatementClosurePanel.graphMaxNodes + 1)).toArray.map fun i =>
        { name := s!"Wide.d{i}", origin := "subject", kind := "def", depth := 1 } })
  hasSubstr wide "No meaning graph is drawn: this closure has 121 declarations" &&
  !hasSubstr wide "Meaning graph — what the statement refers to"

/-! ## Rung 1b — bound but truncated (§A3)

Truncation is a verdict state. The count becomes a lower bound, and the three things a
lower bound cannot support all disappear.
-/

private def truncatedHtml : String :=
  htmlOf (comparatorWith
    { boundClosure with truncated := true, total := 40, maxNodes := 32 })

/-- info: true -/
#guard_msgs in
#eval
  hasSubstr truncatedHtml
    "At least 40 declarations were discovered before this site's configured cap (32); the \
     reading list is incomplete." &&
  hasSubstr truncatedHtml "Incomplete — cap 32" &&
  hasSubstr truncatedHtml "Reading list (8 of at least 40)"

-- What must NOT be there: the exact-count sentence, either gradient, and the graph.
/-- info: true -/
#guard_msgs in
#eval
  !hasSubstr truncatedHtml "To believe this claim you must read" &&
  !hasSubstr truncatedHtml "The statement check here is short" &&
  !hasSubstr truncatedHtml "substantial part of trusting this result" &&
  !hasSubstr truncatedHtml "Meaning graph — what the statement refers to"

/-! ## Rung 2 — the right file, bound to nothing (§A1) -/

private def unboundHtml : String :=
  htmlOf (comparatorWith
    { boundClosure with
      provenance := "chain-unbound"
      reason := "the run record carries no challenge chain, so the files this site read are \
        tied to the verdict by nothing" })

/-- info: true -/
#guard_msgs in
#eval
  hasSubstr unboundHtml
    "Source exploration of the current tree — not bound to the recorded verifier run." &&
  hasSubstr unboundHtml "Not bound to the recorded run" &&
  hasSubstr unboundHtml "The run record carries no challenge chain" &&
  -- The closure finished, so its count is exact and may be stated as one.
  hasSubstr unboundHtml "To believe this claim you must read 8 declarations"

-- But the favourable gradient is not available: a short closure of a file nothing ties to
-- the verdict is not evidence that the verdict is easy to check.
/-- info: true -/
#guard_msgs in
#eval
  !hasSubstr unboundHtml "The statement check here is short" &&
  !hasSubstr unboundHtml "substantial part of trusting this result" &&
  !hasSubstr unboundHtml "Bound to the recorded run"

/-! ## Rung 3 — the subject's aligned statements -/

private def claimDeclsHtml : String :=
  htmlOf (comparatorWith
    { boundClosure with
      provenance := "claim-decls"
      roots := ["Subject.add_comm_claim"]
      chainFiles := #[]
      reason := "the statement-closure tool was not found" })

/-- info: true -/
#guard_msgs in
#eval
  hasSubstr claimDeclsHtml
    "Closure of the subject's aligned statements, not of the challenge file." &&
  hasSubstr claimDeclsHtml "Subject's aligned statements" &&
  hasSubstr claimDeclsHtml "Closed over: Subject.add_comm_claim" &&
  -- Why the rung above was not taken, kept where the label is.
  hasSubstr claimDeclsHtml "The statement-closure tool was not found"

-- The headline is relabelled: this is not a count of what the certified claim depends on.
/-- info: true -/
#guard_msgs in
#eval
  hasSubstr claimDeclsHtml
    "Reading the subject's aligned statements means reading 8 declarations (7 outside Mathlib)" &&
  !hasSubstr claimDeclsHtml "To believe this claim you must read"

-- The gradient survives the relabel: the closure did finish, and it is a closure of
-- something this build actually walked.
/-- info: true -/
#guard_msgs in
#eval hasSubstr claimDeclsHtml "The statement check here is short"

/-! ## Rung 4 — nothing, and why -/

private def unavailableHtml : String :=
  htmlOf (comparatorWith (statementClosureUnavailable
    "the statement-closure tool was not found; build it with `lake build statement-closure`"))

/-- info: true -/
#guard_msgs in
#eval
  hasSubstr unavailableHtml "What you must read to believe this claim" &&
  hasSubstr unavailableHtml "No statement closure is available for this claim." &&
  hasSubstr unavailableHtml "The statement-closure tool was not found; build it with `lake build statement-closure`" &&
  -- No list, no headline, no graph: there is nothing to list.
  !hasSubstr unavailableHtml "Reading list (" &&
  !hasSubstr unavailableHtml "To believe this claim you must read" &&
  !hasSubstr unavailableHtml "Meaning graph"

/-! ## Headline shapes that are not the common one -/

-- A closure that touches no Mathlib omits the parenthetical rather than printing a zero.
/-- info: true -/
#guard_msgs in
#eval
  let html := htmlOf (comparatorWith
    { boundClosure with
      counts := #[("challenge", 4), ("core", 1)], total := 5, outsideMathlib := 5 })
  hasSubstr html "To believe this claim you must read 5 declarations: 4 declared in the \
    challenge chain itself and 1 from Lean's core libraries, used as given." &&
  !hasSubstr html "(5 outside Mathlib)"

-- A module root this fork has no name for is surfaced under its own name, above the
-- libraries a reader was invited to skip.
/-- info: true -/
#guard_msgs in
#eval
  let html := htmlOf (comparatorWith
    { boundClosure with
      counts := #[("challenge", 1), ("Batteries", 2), ("mathlib", 1)]
      total := 4, outsideMathlib := 3
      entries := #[
        { name := "C.claim", origin := "challenge", kind := "theorem", depth := 0 },
        { name := "Batteries.x", origin := "Batteries", kind := "def", depth := 1 },
        { name := "Batteries.y", origin := "Batteries", kind := "def", depth := 1 },
        { name := "Real.pi", origin := "mathlib", kind := "def", depth := 1 }] })
  hasSubstr html "1 declared in the challenge chain itself, 2 from Batteries and 1 from \
    Mathlib, used as given." &&
  hasSubstr html "From Batteries"

/-! ## End to end over the real tool

The engine, the wire format, the §A1 binding and this module's rendering, exercised as one
path over the a362583-shaped fixture: a challenge file, a recorded chain beside it, and a
closure that must come back bound.
-/

/-- info: (true, true, true, true) -/
#guard_msgs in
#eval show IO (Bool × Bool × Bool × Bool) from do
  let recorded ← do
    match Json.parse (← IO.FS.readFile "tests/fixtures/trust/comparator-status.json") with
    | .error _ => pure #[]
    | .ok j => pure (TrustComparator.ofJson j).challengeChain
  let job : Informal.StatementClosure.Job := {
    files := #["tests/fixtures/trust/Challenge.lean"]
    roots := #["TrustFixture.add_comm_claim"]
  }
  match ← runStatementClosureTool "./.lake/build/bin/statement-closure" job.toJson with
  | .error _ => return (false, false, false, false)
  | .ok doc =>
    match Informal.StatementClosure.Report.ofJson? doc with
    | .error _ => return (false, false, false, false)
    | .ok report =>
      let binding := Informal.StatementClosure.bindChain report.provenance.files recorded
      let r := report.result
      let closure : StatementClosure := {
        provenance := binding.provenanceTag
        reason := binding.reason
        roots := ["TrustFixture.add_comm_claim"]
        total := r.total
        outsideMathlib := r.outsideMathlib
        untrusted := r.untrusted
        truncated := r.truncated
        maxNodes := r.maxNodes
        counts := r.counts
        chainFiles := report.provenance.files.map fun f => (f.path, f.sha256)
        entries := r.entries.map fun e =>
          { name := e.name, origin := e.origin, kind := e.kind, auxiliary := e.auxiliary
            depth := e.depth, signature := e.signature, definesModule := e.definesModule
            uses := e.uses }
      }
      let html := htmlOf (comparatorWith closure)
      return (
        -- Bound, so the page may say so.
        hasSubstr html "Bound to the recorded run",
        -- The claim itself is a row of its own reading list, linked into the source above.
        hasSubstr html "TrustFixture.add_comm_claim" &&
          hasSubstr html "href=\"comparator/#bp-trust-claim\"",
        -- The closure finished, so the count is exact.
        hasSubstr html "To believe this claim you must read" && !r.truncated,
        -- The edges the schema-2 wire format added reached the graph.
        r.entries.any (fun e => !e.uses.isEmpty) &&
          hasSubstr html "Meaning graph — what the statement refers to")

end Verso.VersoBlueprintTests.StatementClosureRender
