/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import VersoBlueprint
import VersoBlueprintTests.Blueprint.Support
import VersoBlueprintTests.CaveatsFixture
import VersoManual

/-!
Known caveat patterns: the table, the two scans, the states, and the copy.

The claims under test are the ones a reader would be hurt by if they were wrong:

- **The scan rides the meaning traversal, not the root's type** (§A7(a)). Asserted by
  contrast, on the same declaration: the shallow registry-side scan finds nothing on a
  statement whose closure reaches three table symbols, and the traversal scan finds them.
  If those two ever agree on that fixture, the traversal scan has stopped being one.
- **The guard states are three, and none of them is "guarded"** (§A7(c)). Including
  CX-059's case, where a guard-shaped hypothesis is about something other than the flagged
  operand and the scan cannot tell — which is what the copy for that state says.
- **A zero result is not a clean bill** (§A7(b)). Every state that found nothing renders
  the sentence naming the table's version and digest and disclaiming exhaustiveness, and
  the five states are five different sentences.
- **Configured inputs fail loudly** (§A7(e)). An override at the wrong schema version, an
  override claiming a key another entry owns, a sidecar with a duplicate or an unresolvable
  declaration: build errors, never a quiet fall-back to the default.
- **Absence is absence.** A payload with no scan renders exactly the page it rendered
  before this round.
-/

namespace Verso.VersoBlueprintTests.Caveats

open Lean
open Verso Genre Manual
open Informal Informal.Commands
open Informal.JunkValues
open Verso.VersoBlueprintTests.Blueprint.Support

private def fixtureNs : Name := `VersoBlueprintTests.CaveatFixture
private def toolPath : String := "./.lake/build/bin/statement-closure"
private def challengeFixture : String := "tests/fixtures/caveats/Challenge.lean"
private def fixtureDir : String := "tests/fixtures/caveats"

private def bundledTable : Table := (bundled).toOption.getD {}
private def bundledIndex : Index := bundledTable.index

/-! ## The bundled table -/

-- It parses, it has entries, and it names a version and a digest the copy can print.
/-- info: (true, true, true, true) -/
#guard_msgs in
#eval
  ((bundled.toOption).isSome,
   decide (bundledTable.entries.size > 20),
   bundledTable.version == "2026-08-25",
   bundledTable.digest.length == 12)

-- Notation reaches a symbol through its instance, which is why instances are match keys:
-- `a - b : ℕ` names `instSubNat` and never names `Nat.sub`.
/-- info: (some "Nat.sub", some "Nat.sub", some "HDiv.hDiv", none) -/
#guard_msgs in
#eval
  ((bundledIndex.find? `instSubNat).map (·.symbol),
   (bundledIndex.find? `Nat.sub).map (·.symbol),
   (bundledIndex.find? `HDiv.hDiv).map (·.symbol),
   (bundledIndex.find? `Nat.succ).map (·.symbol))

/-! ## Override merge (§A7(e))

Entry-replace on the stable `symbol` key, a duplicate match key refused, an unsupported
version refused. All three are build errors at the call sites; here they are the loader's
own verdicts.
-/

private def loadFixtureTable (name : String) : IO (Except String Table) :=
  loadTable s!"{fixtureDir}/{name}"

private def errorHas (e : Except String α) (needle : String) : Bool :=
  match e with
  | .error msg => (msg.splitOn needle).length > 1
  | .ok _ => false

-- Replace, not field-merge: the bundled `Nat.sub` entry is gone whole, guards included.
/-- info: (true, some "Replaced by the consumer.", some 0, true, true) -/
#guard_msgs in
#eval show IO (Bool × Option String × Option Nat × Bool × Bool) from do
  match ← loadFixtureTable "table-override.json" with
  | .error _ => return (false, none, none, false, false)
  | .ok t =>
    let sub := t.entries.find? (·.symbol == "Nat.sub")
    return (
      t.entries.size == bundledTable.entries.size + 1,
      sub.map (·.behavior),
      sub.map (·.guards.size),
      t.entries.any (·.symbol == "CaveatFixture.score"),
      -- The effective table is the consumer's, and its digest says so.
      t.version == "2099-01-01" && t.digest != bundledTable.digest)

-- A key another entry already owns is refused rather than resolved by iteration order.
/-- info: (true, true) -/
#guard_msgs in
#eval show IO (Bool × Bool) from do
  let r ← loadFixtureTable "table-duplicate-alias.json"
  return ((r.toOption).isNone, errorHas r "is claimed by both 'Nat.sub' and 'Local.thing'")

-- An unsupported schema version is refused by name.
/-- info: (true, true) -/
#guard_msgs in
#eval show IO (Bool × Bool) from do
  let r ← loadFixtureTable "table-future-version.json"
  return ((r.toOption).isNone, errorHas r "schema version 99")

-- A configured path that does not exist is an error, never a silent default table.
/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  return errorHas (← loadTable s!"{fixtureDir}/no-such-table.json") "names a missing file"

/-! ## The keys have to exist where the scan runs (CX-060)

A match key is a name, and a name that does not resolve in the environment a scan runs
against can never be matched by it. Two consequences, deliberately different:

- an override **none** of whose keys resolve is a broken configuration, refused at the
  option like every other set-but-broken trust input;
- an override **some** of whose keys resolve is legitimate, and the ones that could not
  have matched are carried into the report and named in the copy.

The unqualified `completed-zero` — a table saying it looked and found nothing, over a key
that could never have matched — is what neither of these leaves behind.
-/

private def loadFixtureOverride (name : String) : IO (Option Table) := do
  match ← loadTableWithOverride s!"{fixtureDir}/{name}" with
  | .error _ => return none
  | .ok (_, o?) => return o?

-- The bundled table's own keys resolve where the registry scan runs. (Not all of them:
-- this test library does not import every module the table names, which is the state the
-- report is now able to say out loud.)
/-- info: (true, true, true) -/
#guard_msgs in
#eval show CoreM (Bool × Bool × Bool) from do
  let r := Table.resolveKeys (← getEnv) bundledTable
  return (r.ran, decide (r.resolved > 0), r.keys == r.resolved + r.unresolved.size)

-- Codex's exact override: one entry, one key, and the key names nothing here.
/-- info: (true, true, true) -/
#guard_msgs in
#eval show CoreM (Bool × Bool × Bool) from do
  let env ← getEnv
  let some override ← liftM (loadFixtureOverride "table-unresolved.json") | return (false, false, false)
  let reason? := overrideUnusableReason? env "t.json" override
  return (reason?.isSome,
    ((reason?.getD "").splitOn "Definitely.Not.A.Real.Declaration").length > 1,
    ((reason?.getD "").splitOn "would report that as having found nothing").length > 1)

-- One key that resolves is enough for the override to be usable: the unresolved rest is
-- reported, not refused.
/-- info: (true, 1, #["Definitely.Not.A.Real.Declaration"]) -/
#guard_msgs in
#eval show CoreM (Bool × Nat × Array String) from do
  let env ← getEnv
  let some override ← liftM (loadFixtureOverride "table-partly-unresolved.json")
    | return (false, 0, #[])
  let r := Table.resolveKeys env override
  return ((overrideUnusableReason? env "t.json" override).isNone, r.resolved, r.unresolved)

-- The index carries the resolution, so every report the scan produces states it. An index
-- built without an environment says nothing rather than implying everything resolved.
/-- info: (false, true, true) -/
#guard_msgs in
#eval show CoreM (Bool × Bool × Bool) from do
  let envless := bundledTable.index
  let resolved := bundledTable.indexIn (← getEnv)
  return (envless.resolution.ran, resolved.resolution.ran,
    resolved.byKey.size == envless.byKey.size)

-- The copy: nothing at all where no resolution ran, and the unresolved keys named where
-- one did.
/-- info: (true, true, true) -/
#guard_msgs in
#eval
  let silent : ScanReport := { status := statusCompletedZero }
  let clean : ScanReport := { status := statusCompletedZero, tableKeys := 12 }
  let holed : ScanReport := { status := statusCompletedZero, tableKeys := 12
                              tableUnresolved := #["No.Such.Name"] }
  ((Informal.CaveatsRender.tableHealthCopy silent).isEmpty,
   hasSubstr (Informal.CaveatsRender.tableHealthCopy clean) "All 12 of the table's match keys",
   hasSubstr (Informal.CaveatsRender.tableHealthCopy holed) "11 of the table's 12 match keys" &&
     hasSubstr (Informal.CaveatsRender.tableHealthCopy holed)
       "could not have matched here (No.Such.Name)")

-- End to end through the real subprocess, on Codex's exact override: the zero-match state
-- is still `completed-zero`, and it is no longer unqualified.
/-- info: (true, 1, #["Definitely.Not.A.Real.Declaration"], true) -/
#guard_msgs in
#eval show IO (Bool × Nat × Array String × Bool) from do
  let some override ← loadFixtureOverride "table-unresolved.json" | return (false, 0, #[], false)
  let job : Informal.StatementClosure.Job := {
    files := #["tests/fixtures/trust/Challenge.lean"]
    roots := #["TrustFixture.add_comm_claim"]
    caveatTable? := some override
  }
  match ← runStatementClosureTool toolPath job.toJson with
  | .error _ => return (false, 0, #[], false)
  | .ok doc =>
    match Informal.StatementClosure.Report.ofJson? doc with
    | .error _ => return (false, 0, #[], false)
    | .ok report =>
      match report.caveats? with
      | none => return (false, 0, #[], false)
      | some c =>
        return (c.status == statusCompletedZero, c.tableKeys, c.tableUnresolved,
          hasSubstr (Informal.CaveatsRender.body c).asString
            "could not have matched here (Definitely.Not.A.Real.Declaration)")

/-! ## Guard presence is three states, and none of them is "guarded" (§A7(c)) -/

private def headsOfDecl (n : Name) : CoreM (Std.HashSet Name) := do
  match (← getEnv).find? (fixtureNs ++ n) with
  | some info => return guardHeads info.type
  | none => return {}

private def stateFor (symbol : Name) (decl : Name) : CoreM String := do
  match bundledIndex.find? symbol with
  | none => return "no-such-entry"
  | some e => return guardState e (← headsOfDecl decl)

/-- info: ("candidate-present", "candidate-present", "not-detected", "not-evaluated") -/
#guard_msgs in
#eval show CoreM (String × String × String × String) from do
  return (
    -- A hypothesis of the guarding shape for truncated subtraction.
    ← stateFor `Nat.sub `guarded,
    -- CX-059: `c ≠ 0` where the divisor is `b`. The scan sees `Ne` and cannot relate it.
    ← stateFor `Nat.div `guardedElsewhere,
    -- Nothing of the shape at all.
    ← stateFor `Nat.sub `unguarded,
    -- The table records no guard shape for a floor function, so nothing was looked for.
    ← stateFor `Nat.sqrt `noGuardShape)

/-! ## The traversal scan versus the shallow one (§A7(a))

The same declaration, scanned twice. `scoreZero`'s type names `score` and nothing a table
lists; `score`'s value names two wrappers whose values name three. This is the zeta shape,
and the contrast is the assertion: if the shallow scan ever finds these, the fixture has
stopped testing anything.
-/

private def fixtureCfg : Informal.StatementClosure.Config :=
  { chainModules := #[`VersoBlueprintTests.CaveatsFixture] }

private def scanFixtureRoot : MetaM ScanReport := do
  let (_, scan?) ← Informal.StatementClosure.closureAndScan fixtureCfg
    #[fixtureNs ++ `scoreZero] (some bundledTable)
  return scan?.getD (unavailable "no scan")

-- The shallow scan: nothing, and it says which table was silent.
/-- info: ("completed-zero", 0, "direct constants plus one instance hop") -/
#guard_msgs in
#eval show CoreM (String × Nat × String) from do
  let env ← getEnv
  let info := (env.find? (fixtureNs ++ `scoreZero)).get!
  let r := scanDeclType env bundledIndex info.type
  return (r.status, r.hits.size, r.coverage)

-- The traversal scan, on the same root: three symbols, each reached through a wrapper.
/-- info: ("completed-with-hits", true, true, true, true) -/
#guard_msgs in
#eval show CoreM (String × Bool × Bool × Bool × Bool) from do
  let r ← (scanFixtureRoot).run'
  let has (s : String) := r.hits.any (·.symbol == s)
  return (r.status, has "Nat.sub", has "Nat.div", has "HDiv.hDiv",
    -- Nothing was matched at the statement itself; every hit is behind something.
    r.hits.all (·.depth > 0))

-- Matching happens at the trusted frontier and stops there: `instSubNat` is a core
-- constant the walk never expands, and it is where truncated subtraction was seen.
/-- info: (some "instSubNat", some "core") -/
#guard_msgs in
#eval show CoreM (Option String × Option String) from do
  let r ← (scanFixtureRoot).run'
  let sub := r.hits.find? (·.symbol == "Nat.sub")
  return (sub.map (·.matchedVia), sub.map (·.origin))

-- Guard state comes from the root's own telescope, and `scoreZero` has no binders.
/-- info: some "not-detected" -/
#guard_msgs in
#eval show CoreM (Option String) from do
  let r ← (scanFixtureRoot).run'
  return (r.hits.find? (·.symbol == "Nat.sub")).map (·.guard)

-- CX-059, end to end: a `≠ 0` hypothesis about a variable that is not the divisor puts
-- the row in `candidate-present`, and what the page then says is the non-association
-- sentence — not that the statement is guarded.
/-- info: (true, true, true) -/
#guard_msgs in
#eval show CoreM (Bool × Bool × Bool) from do
  let (_, scan?) ← (Informal.StatementClosure.closureAndScan fixtureCfg
    #[fixtureNs ++ `guardedElsewhere] (some bundledTable)).run'
  let html := (Informal.CaveatsRender.render scan?).asString
  return (
    (scan?.map (fun r => r.hits.any (fun f => f.guard == guardCandidatePresent))).getD false,
    hasSubstr html
      "A guard-shaped hypothesis occurs; this presence scan did not relate it to the \
       flagged operand.",
    !hasSubstr html "is guarded")

/-! ## The subprocess, end to end (§A7(a), §A7(f))

The same shape through the real tool: a chain file elaborated in a clean environment, the
scan riding that walk, and the lexical `set_option` pass over the bytes the tool hashed.
-/

private def runFixtureJob (table? : Option Table) :
    IO (Except String Informal.StatementClosure.Report) := do
  let job : Informal.StatementClosure.Job := {
    files := #[challengeFixture]
    roots := #["CaveatFixture.score_zero"]
    caveatTable? := table?
  }
  match ← runStatementClosureTool toolPath job.toJson with
  | .error e => return .error e
  | .ok doc => return Informal.StatementClosure.Report.ofJson? doc

/-- info: ("completed-with-hits", true, true, some "instSubNat") -/
#guard_msgs in
#eval show IO (String × Bool × Bool × Option String) from do
  match ← runFixtureJob (some bundledTable) with
  | .error _ => return ("tool failed", false, false, none)
  | .ok report =>
    match report.caveats? with
    | none => return ("no caveat report", false, false, none)
    | some c =>
      let has (s : String) := c.hits.any (·.symbol == s)
      return (c.status, has "Nat.sub", has "Nat.div",
        (c.hits.find? (·.symbol == "Nat.sub")).map (·.matchedVia))

-- §A7(f): the real `set_option` is found; the one in a comment and the one in a string
-- literal are not; the allowlist keeps `pp.*` and friends out by construction.
/-- info: (1, some "maxRecDepth", some "700", some "file", true) -/
#guard_msgs in
#eval show IO (Nat × Option String × Option String × Option String × Bool) from do
  match ← runFixtureJob (some bundledTable) with
  | .error _ => return (0, none, none, none, false)
  | .ok report =>
    match report.caveats? with
    | none => return (0, none, none, none, false)
    | some c =>
      let first := c.optionOverrides[0]?
      return (c.optionOverrides.size, first.map (·.option), first.map (·.value),
        first.map (·.scope),
        c.optionScanFiles.any (fun f => (f.splitOn "Challenge.lean").length > 1))

-- §A7(f) again, on a two-file chain: the scan covers the whole elaborated chain, so an
-- override one file away from the Challenge is still found, and the symbol that lives
-- there is still matched.
/-- info: (2, #["maxHeartbeats", "maxRecDepth"], 2, true) -/
#guard_msgs in
#eval show IO (Nat × Array String × Nat × Bool) from do
  let job : Informal.StatementClosure.Job := {
    files := #[s!"{fixtureDir}/Deps.lean", s!"{fixtureDir}/ChainChallenge.lean"]
    roots := #["CaveatChain.wrapped_zero"]
    caveatTable? := some bundledTable
  }
  match ← runStatementClosureTool toolPath job.toJson with
  | .error _ => return (0, #[], 0, false)
  | .ok doc =>
    match Informal.StatementClosure.Report.ofJson? doc with
    | .error _ => return (0, #[], 0, false)
    | .ok report =>
      match report.caveats? with
      | none => return (0, #[], 0, false)
      | some c =>
        return (c.optionScanFiles.size, c.optionOverrides.map (·.option),
          c.optionOverrides.size, c.hits.any (·.symbol == "Nat.sub"))

-- A job with no table is told so, rather than served a result that found nothing.
/-- info: (some "disabled", true) -/
#guard_msgs in
#eval show IO (Option String × Bool) from do
  match ← runFixtureJob none with
  | .error _ => return (none, false)
  | .ok report =>
    return (report.caveats?.map (·.status),
      (report.caveats?.map (·.hits.isEmpty)).getD false)

/-! ## The copy, state by state (§A7(b))

Each state's sentence, asserted for itself and against its neighbours'. The fixed lead is
on every state that reports a result at all.
-/

private def sampleFinding : Finding :=
  { symbol := "Nat.sub"
    matchedVia := "instSubNat"
    behavior := "Subtraction on the naturals is truncated."
    guard := guardNotDetected
    guardHint := "A hypothesis bounding the subtrahend, such as `b ≤ a`."
    provenance := "core"
    origin := "core"
    depth := 3 }

private def zeroReport : ScanReport :=
  { status := statusCompletedZero
    tableVersion := "2026-08-25"
    tableDigest := "751a90def3b1"
    coverage := coverageMeaningClosure }

private def hitsReport : ScanReport :=
  { zeroReport with status := statusCompletedWithHits, hits := #[sampleFinding] }

private def htmlOf (r : ScanReport) : String :=
  (Informal.CaveatsRender.render (some r)).asString

/-- info: (true, true, true) -/
#guard_msgs in
#eval
  let html := htmlOf zeroReport
  (hasSubstr html
     "Caveats to check, not findings of error: these symbols have total-function \
      conventions a reader can misread.",
   hasSubstr html
     "No matches in the configured partial table (version 2026-08-25, digest \
      751a90def3b1); this is not evidence that no total-function caveat applies.",
   -- A zero result never borrows the with-hits sentence.
   !hasSubstr html "occur in what this statement means")

/-- info: (true, true, true, true) -/
#guard_msgs in
#eval
  let html := htmlOf hitsReport
  (hasSubstr html "1 symbol in the configured table occurs in what this statement means.",
   hasSubstr html
     "The table is partial (version 2026-08-25, digest 751a90def3b1): a symbol it does not \
      list is a symbol nobody looked for.",
   -- Backtick spans become `<code>`, like every other prose surface on the trust pages.
   hasSubstr html "Matched through <code>instSubNat</code> in core, 3 edges from the statement.",
   -- A list of hits is still not a clean bill about the rest.
   !hasSubstr html "No matches in the configured partial table")

-- The three guard sentences, and the word this surface never writes.
/-- info: (true, true, true, true) -/
#guard_msgs in
#eval
  let present := htmlOf { hitsReport with
    hits := #[{ sampleFinding with guard := guardCandidatePresent }] }
  let absent := htmlOf hitsReport
  let none_ := htmlOf { hitsReport with
    hits := #[{ sampleFinding with guard := guardNotEvaluated }] }
  (hasSubstr present
     "A guard-shaped hypothesis occurs; this presence scan did not relate it to the flagged \
      operand.",
   hasSubstr absent
     "No hypothesis of the guarding shape was detected. This is a presence check: the \
      statement may be guarded another way, or may not need a guard.",
   hasSubstr none_ "No guard shape is recorded for this symbol, so nothing was looked for.",
   -- Not in any of them.
   !hasSubstr present "is guarded" && !hasSubstr absent "is guarded" &&
     !hasSubstr none_ "is guarded")

-- Truncation is a lower bound, said as one.
/-- info: (true, true) -/
#guard_msgs in
#eval
  let html := htmlOf { hitsReport with status := statusPartial, truncated := true }
  (hasSubstr html
     "The walk reached this site's configured cap before finishing, so this is a lower \
      bound: 1 match among the declarations that were reached. Symbols beyond the cap were \
      not examined.",
   !hasSubstr html "occurs in what this statement means")

-- The two states that report no scan at all say which one they are.
/-- info: (true, true) -/
#guard_msgs in
#eval
  (hasSubstr (htmlOf (unavailable "the tool was not found"))
     "No caveat scan is available here: the tool was not found.",
   hasSubstr (htmlOf (disabled "the job spec carried no caveat table"))
     "The caveat scan is switched off for this site, so no symbols were looked for")

-- A state from a newer schema is named, not guessed at.
/-- info: (true, true) -/
#guard_msgs in
#eval
  let html := htmlOf { zeroReport with status := "completed-elsewhere" }
  (hasSubstr html
     "This build does not recognize the caveat-scan state 'completed-elsewhere' recorded \
      here, so it reports nothing about it.",
   !hasSubstr html "No matches in the configured partial table")

/-! ## The `set_option` subsection -/

private def optionReport : ScanReport :=
  { zeroReport with
    optionScanFiles := #["comparator/Challenge.lean", "comparator/Deps.lean"]
    optionOverrides := #[
      { option := "maxHeartbeats", value := "400000", file := "comparator/Challenge.lean"
        line := 3, column := 1, scope := "file" }] }

/-- info: (true, true, true, true) -/
#guard_msgs in
#eval
  let html := htmlOf optionReport
  (hasSubstr html
     "Configuration override present: the chain sets 1 of the options this site reports on. \
      An override is a configuration fact, not a finding of error.",
   hasSubstr html "comparator/Challenge.lean:3:1 · file scope",
   -- The allowlist is published beside the findings.
   hasSubstr html "Options reported: debug.skipKernelTC, debug.byAsSorry" &&
     hasSubstr html "An option outside that list was not looked for.",
   -- Both chain files are named, so a reader can see the scan covered the whole chain.
   hasSubstr html "Files scanned: comparator/Challenge.lean, comparator/Deps.lean.")

-- Looking and finding none is not the same as not looking, and reads differently.
/-- info: (true, true) -/
#guard_msgs in
#eval
  let looked := htmlOf { optionReport with optionOverrides := #[] }
  let didnt := htmlOf zeroReport
  (hasSubstr looked "No configuration override was found in the 2 chain files scanned.",
   !hasSubstr didnt "Configuration override" && !hasSubstr didnt "Options reported:")

/-! ## The lexer (§A7(f)) -/

private def optionNames (src : String) : Array String :=
  (scanSetOptions "F.lean" src).map (·.option)

/-- info: (#[], #[], #["maxRecDepth"], #["maxHeartbeats"], #[]) -/
#guard_msgs in
#eval
  (optionNames "-- set_option maxHeartbeats 1\n",
   optionNames "/- set_option maxHeartbeats 1 -/\n",
   optionNames "def s := \"set_option maxHeartbeats 1\"\nset_option maxRecDepth 9\n",
   optionNames "set_option maxHeartbeats 1 in\ntheorem t : True := trivial\n",
   -- Not on the allowlist: display and diagnostics are deliberately not reported.
   optionNames "set_option pp.all true\nset_option trace.Meta.synthInstance true\n")

-- Nested block comments, and a doc comment, are all comment.
/-- info: #[] -/
#guard_msgs in
#eval optionNames "/- outer /- set_option maxRecDepth 1 -/ still comment -/\n\
  /-- set_option maxHeartbeats 2 -/\ndef d := 1\n"

-- Scope is read from the trailing `in`, and the position is the keyword's.
/-- info: (some "term", some "file", some 2, some 1) -/
#guard_msgs in
#eval
  let scoped_ := scanSetOptions "F.lean" "\nset_option maxRecDepth 9 in\ndef d := 1\n"
  let plain := scanSetOptions "F.lean" "set_option maxRecDepth 9\n"
  (scoped_[0]?.map (·.scope), plain[0]?.map (·.scope),
   scoped_[0]?.map (·.line), scoped_[0]?.map (·.column))

/-! ## Registry encoding (§A7(d))

Six states an entry's `scan` can arrive in. The one that matters most is the first: an
entry with no `scan` was not scanned, and no consumer may read that as a result.
-/

/-- A registry entry as the artifact carries it, with no scan: the legacy (v2) shape. -/
private def legacyEntry : Informal.DeclRegistry.Entry :=
  { name := "A.f", kind := "Definition", moduleName := "A", sourcePath := "A.lean"
    range? := none, signatureText := "Nat", signatureHtml? := none, status := "proved" }

/-- The same entry with a `scan` value spliced in, as a document a consumer would read. -/
private def entryJson (scanValue : String) : Json :=
  let base := toJson legacyEntry
  if scanValue.isEmpty then base
  else
    match Json.parse scanValue with
    | .error _ => base
    | .ok s => base.setObjVal! "scan" s

private def entryScan? (scanValue : String) : Option ScanReport :=
  match fromJson? (α := Informal.DeclRegistry.Entry) (entryJson scanValue) with
  | .error _ => none
  | .ok e => e.scan?

private def renderedStatus (scanValue : String) : String :=
  (Informal.CaveatsRender.render (entryScan? scanValue)).asString

/-- info: (none, true) -/
#guard_msgs in
#eval
  -- 1. v2 legacy: no `scan` key at all. Not scanned, and nothing renders.
  ((entryScan? "").map (·.status), (renderedStatus "").isEmpty)

/-- info: (some "completed-zero", some "completed-with-hits", some "partial") -/
#guard_msgs in
#eval
  -- 2/3/4. The three states a v3 scan can report.
  ((entryScan? "{\"status\":\"completed-zero\",\"matches\":[]}").map (·.status),
   (entryScan? "{\"status\":\"completed-with-hits\",\"matches\":[{\"symbol\":\"Nat.sub\"}]}").map
     (·.status),
   (entryScan? "{\"status\":\"partial\",\"matches\":[],\"truncated\":true}").map (·.status))

/-- info: (some "", true) -/
#guard_msgs in
#eval
  -- 5. Malformed: the scan reads as empty, and an empty state renders nothing rather than
  -- a confident one.
  ((entryScan? "\"nonsense\"").map (·.status), (renderedStatus "\"nonsense\"").isEmpty)

/-- info: true -/
#guard_msgs in
#eval
  -- 6. A future state: named, not guessed at.
  hasSubstr (renderedStatus "{\"status\":\"completed-elsewhere\",\"matches\":[]}")
    "does not recognize the caveat-scan state 'completed-elsewhere'"

-- A whole v2 registry document still reads, with every entry not-scanned; this build
-- writes v4 (v3 added the optional `scan`, v4 each entry's `isInstance`).
/-- info: (2, 4, true) -/
#guard_msgs in
#eval
  let v2 : Json := Json.mkObj [
    ("schemaVersion", Json.num 2), ("namePrefix", Json.str "A"), ("declCount", Json.num 1),
    ("decls", Json.arr #[entryJson ""])]
  match fromJson? (α := Informal.DeclRegistry.Registry) v2 with
  | .error _ => (0, 0, false)
  | .ok r =>
    (r.schemaVersion, ({} : Informal.DeclRegistry.Registry).schemaVersion,
     r.decls.all (·.scan?.isNone))

/-! ## The characterization sidecar (§A7(e)) -/

private def loadFixtureChars (name : String) : IO (Except String Characterizations) :=
  loadCharacterizations s!"{fixtureDir}/{name}"

/-- info: (1, true, true) -/
#guard_msgs in
#eval show IO (Nat × Bool × Bool) from do
  match ← loadFixtureChars "characterizations.json" with
  | .error _ => return (0, false, false)
  | .ok cs =>
    return (cs.entries.size, cs.digest.length == 12,
      (cs.path.splitOn "characterizations.json").length > 1)

/-- info: (true, true, true) -/
#guard_msgs in
#eval show IO (Bool × Bool × Bool) from do
  return (
    errorHas (← loadFixtureChars "characterizations-duplicate.json")
      "declares two characterizations for 'Nat.sub'",
    errorHas (← loadFixtureChars "characterizations-malformed.json")
      "characterization entry has no 'decl'",
    errorHas (← loadFixtureChars "no-such-sidecar.json") "names a missing file")

-- The one failure the loader cannot see: a declaration this environment does not have.
/-- info: (#[], #["No.Such.Declaration.Anywhere"]) -/
#guard_msgs in
#eval show CoreM (Array String × Array String) from do
  let env ← getEnv
  let ok ← liftM (loadFixtureChars "characterizations.json")
  let bad ← liftM (loadFixtureChars "characterizations-unresolved.json")
  return (unresolvedDecls env (ok.toOption.getD {}),
    unresolvedDecls env (bad.toOption.getD {}))

/-! ## Rendering the sidecar -/

/-- info: (true, true, true) -/
#guard_msgs in
#eval show IO (Bool × Bool × Bool) from do
  match ← loadFixtureChars "characterizations.json" with
  | .error _ => return (false, false, false)
  | .ok cs =>
    let html := (Informal.CaveatsRender.characterizationsBody cs).asString
    return (
      hasSubstr html "Consumer-declared characterization: each row is the project's own \
        statement of what one of its definitions is pinned down by.",
      hasSubstr html "Nothing here was checked by this site or by the verifier",
      -- Path and digest, so "consumer-declared" points somewhere.
      hasSubstr html s!"Declared in {fixtureDir}/characterizations.json (digest {cs.digest}).")

/-! ## Absence is absence

A comparator payload with no scan renders exactly the page it rendered before this round.
-/

private def baseComparator : TrustComparator :=
  { status := "verified"
    verifiedAt := "2026-08-04T00:00:00Z"
    theoremNames := ["TrustFixture.add_comm_claim"]
    challengeSource := "theorem add_comm_claim (m n : Nat) : m + n = n + m := by sorry\n"
    configJson := "{}" }

private def panelOf (cmp : TrustComparator) : String :=
  (comparatorBody cmp none (some 3) none).asString

/-- info: (true, true, true) -/
#guard_msgs in
#eval
  let before := panelOf baseComparator
  let after := panelOf { baseComparator with caveats? := some zeroReport }
  (before == panelOf { baseComparator with caveats? := none },
   !hasSubstr before "bp_caveats" && !hasSubstr before "Known caveat patterns",
   hasSubstr after "Known caveat patterns" && hasSubstr after "bp_caveats")

-- The sidecar section is page-level, and absent when none is configured.
/-- info: (true, true) -/
#guard_msgs in
#eval show IO (Bool × Bool) from do
  let none_ := panelOf baseComparator
  let some_ ← do
    match ← loadFixtureChars "characterizations.json" with
    | .error _ => pure ""
    | .ok cs =>
      pure (comparatorBody baseComparator none (some 3) none {} (some cs)).asString
  return (!hasSubstr none_ "Consumer-declared characterizations",
    hasSubstr some_ "Consumer-declared characterizations")

end Verso.VersoBlueprintTests.Caveats
