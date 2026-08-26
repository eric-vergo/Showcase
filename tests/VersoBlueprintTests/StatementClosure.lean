/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import Lean
import VersoBlueprint
import VersoBlueprintTests.StatementClosureFixture

/-!
Statement closure: the walk, the subprocess boundary, and the §A1 chain binding.

The engine is exercised against `StatementClosureFixture`, whose shape is known (a root
theorem, a definition wrapping a frontier constant, an inductive that names itself back
through its constructors, recursion machinery). The subprocess is exercised through the
real binary — building this library builds it (`extraDepTargets`) — so a tree where the
tool is broken fails here rather than skipping.
-/

namespace Verso.VersoBlueprintTests.StatementClosure

open Lean
open Informal.StatementClosure

private def fixtureModule : Name := `VersoBlueprintTests.StatementClosureFixture
private def rootThm : Name := `VersoBlueprintTests.ClosureFixture.size_nonneg
private def wrapDef : Name := `VersoBlueprintTests.ClosureFixture.wrap
private def treeTy : Name := `VersoBlueprintTests.ClosureFixture.Tree
private def treeNode : Name := `VersoBlueprintTests.ClosureFixture.Tree.node
private def sizeDef : Name := `VersoBlueprintTests.ClosureFixture.size

/-- The fixture's module read as the challenge chain. -/
private def cfg : Config := { chainModules := #[fixtureModule] }

private def toolPath : String := "./.lake/build/bin/statement-closure"

/-! ## The walk -/

-- Statements, not proofs: the root's type reaches `size`, `Tree` and `Nat`, while
-- `Nat.zero_le` — named only by the root's proof term — is never reached.
/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let w : Walk := walk (m := Id) (← getEnv) cfg #[rootThm]
  let names := w.nodes.map (·.site.name)
  return names.contains rootThm && names.contains sizeDef && names.contains treeTy
    && names.contains `Nat && names.contains wrapDef
    && !names.contains `Nat.zero_le
    && !w.truncated

-- Origins: the fixture's declarations are the chain and expand; `Nat` is core and stops.
/-- info: (some "challenge", some "core", some false, some true) -/
#guard_msgs in
#eval show CoreM (Option String × Option String × Option Bool × Option Bool) from do
  let w : Walk := walk (m := Id) (← getEnv) cfg #[rootThm]
  let site? (n : Name) := (w.nodes.find? (·.site.name == n)).map (·.site)
  return ((site? wrapDef).map (·.origin), (site? `Nat).map (·.origin),
    (site? wrapDef).map (·.trusted), (site? `Nat).map (·.trusted))

-- The cycle: `Tree`'s constructor types name `Tree` back, and each is recorded once.
/-- info: (1, 1) -/
#guard_msgs in
#eval show CoreM (Nat × Nat) from do
  let w : Walk := walk (m := Id) (← getEnv) cfg #[rootThm]
  let count (n : Name) := (w.nodes.filter (·.site.name == n)).size
  return (count treeTy, count treeNode)

-- Recursion machinery is reached and flagged rather than dropped: the count is the
-- closure's, and what a reading list shows is a separate decision made where the reader
-- can be told what was folded away.
/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let w : Walk := walk (m := Id) (← getEnv) cfg #[rootThm]
  return w.nodes.any (·.auxiliary) && w.nodes.any (fun n => !n.auxiliary)

/-! ## The visitor hook (§A7(a))

The junk-value scan rides this traversal rather than running one of its own, so the
visitor must see what the walk *declines* to expand — the trusted frontier — and must see
repeat encounters, which is where a match-then-stop scan gets its coverage.
-/

/-- info: (false, true, true, true) -/
#guard_msgs in
#eval show CoreM (Bool × Bool × Bool × Bool) from do
  let (w, log) :=
    (walk (m := StateM (Array Encounter)) (← getEnv) cfg #[rootThm]
      (fun e => modify (·.push e))).run #[]
  return (
    -- nothing at the frontier is expanded,
    log.any (fun e => e.site.trusted && e.expanded),
    -- but the frontier is reported,
    log.any (·.site.trusted),
    -- repeat encounters are reported too,
    log.size > w.nodes.size,
    -- and an untruncated walk records exactly its first visits.
    w.nodes.size == (log.filter (·.firstVisit)).size)

/-! ## Truncation (§A3)

Truncation is a verdict state: the walk stops recording, says so, and the total is the
cap rather than the closure. Forced here by trusting nothing, so the frontier stops
nowhere.
-/

/-- info: (true, 32, 32) -/
#guard_msgs in
#eval show CoreM (Bool × Nat × Nat) from do
  let cfg' : Config := { cfg with trustedRoots := #[], maxNodes := capFloor }
  let w : Walk := walk (m := Id) (← getEnv) cfg' #[rootThm]
  return (w.truncated, w.nodes.size, capFloor)

-- Breadth-first, so what survives truncation is the shallowest part of the reading list:
-- the root is kept, and recorded depths never decrease.
/-- info: true -/
#guard_msgs in
#eval show CoreM Bool from do
  let cfg' : Config := { cfg with trustedRoots := #[], maxNodes := capFloor }
  let w : Walk := walk (m := Id) (← getEnv) cfg' #[rootThm]
  let depths := w.nodes.map (·.depth)
  return (w.nodes.map (·.site.name)).contains rootThm
    && depths.zipIdx.all (fun p => p.2 == 0 || p.1 ≥ depths[p.2 - 1]!)

-- A cap above the closure is not truncation.
/-- info: (false, true) -/
#guard_msgs in
#eval show CoreM (Bool × Bool) from do
  let w : Walk := walk (m := Id) (← getEnv) { cfg with maxNodes := 400 } #[rootThm]
  return (w.truncated, w.nodes.size < 400)

/-! ## Job-spec validation

The cap floor and the two required lists are enforced at the boundary, so a
misconfiguration is a refusal rather than a document that reads like an answer.
-/

private def parseJob (s : String) : Except String Job := do
  match Json.parse s with
  | .error e => throw e
  | .ok j => Job.ofJson? j

private def refusedFor (e : Except String Job) (needle : String) : Bool :=
  match e with
  | .error msg => (msg.splitOn needle).length > 1
  | .ok _ => false

/-- info: (true, true, true, true, true) -/
#guard_msgs in
#eval
  (parseJob "{\"files\":[\"C.lean\"],\"roots\":[\"A\"],\"maxNodes\":32}" |>.toOption.isSome,
   refusedFor (parseJob "{\"files\":[\"C.lean\"],\"roots\":[\"A\"],\"maxNodes\":31}")
     "the floor is 32",
   refusedFor (parseJob "{\"files\":[],\"roots\":[\"A\"],\"maxNodes\":400}")
     "names no chain files",
   refusedFor (parseJob "{\"files\":[\"C.lean\"],\"roots\":[],\"maxNodes\":400}")
     "names no root theorems",
   refusedFor (parseJob "{\"files\":[\"C.lean\"],\"roots\":[\"A\"],\"maxNodes\":0}")
     "the floor is 32")

-- `trustedRoots` absent is the default set; `trustedRoots: []` trusts nothing. The
-- difference is what makes "trust nothing" expressible at all.
/-- info: (5, 0) -/
#guard_msgs in
#eval
  ((parseJob "{\"files\":[\"C.lean\"],\"roots\":[\"A\"],\"maxNodes\":400}"
      |>.toOption.map (·.trustedRoots.size)).getD 0,
   (parseJob "{\"files\":[\"C.lean\"],\"roots\":[\"A\"],\"maxNodes\":400,\"trustedRoots\":[]}"
      |>.toOption.map (·.trustedRoots.size)).getD 99)

/-! ## Chain binding (§A1)

The closure is a statement about bytes. It may be presented as adjacent to the verdict
only when the bytes this build read are the bytes the run recorded, in the same order.
-/

private def chainRead : Array ChainDigest :=
  #[{ path := "comparator/Deps.lean", sha256 := "aa" },
    { path := "comparator/Challenge.lean", sha256 := "bb" }]

private def reasonHas (b : Binding) (needle : String) : Bool :=
  (b.reason.splitOn needle).length > 1

/-- info: ("chain", "") -/
#guard_msgs in
#eval
  let b := bindChain chainRead
    #[("comparator/Deps.lean", "aa"), ("comparator/Challenge.lean", "bb")]
  (b.provenanceTag, b.reason)

-- The two records are rooted differently by design: the run writes repo-root-relative
-- paths, the site's options resolve against its own build directory.
/-- info: "chain" -/
#guard_msgs in
#eval (bindChain #[{ path := "../comparator/Challenge.lean", sha256 := "bb" }]
  #[("comparator/Challenge.lean", "BB")]).provenanceTag

-- §A1's regression case: the dependency changed, the primary Challenge did not. The
-- label must drop.
/-- info: (true, true) -/
#guard_msgs in
#eval
  let b := bindChain chainRead
    #[("comparator/Deps.lean", "a9"), ("comparator/Challenge.lean", "bb")]
  (b.provenanceTag == "chain-unbound", reasonHas b "does not match the bytes the run recorded")

-- Order is part of what is compared.
/-- info: (true, true) -/
#guard_msgs in
#eval
  let b := bindChain chainRead
    #[("comparator/Challenge.lean", "bb"), ("comparator/Deps.lean", "aa")]
  (b.provenanceTag == "chain-unbound", reasonHas b "in the run record")

-- A file the run never saw.
/-- info: (true, true) -/
#guard_msgs in
#eval
  let b := bindChain chainRead
    #[("comparator/Other.lean", "aa"), ("comparator/Challenge.lean", "bb")]
  (b.provenanceTag == "chain-unbound", reasonHas b "in the run record")

-- A shorter recorded chain, and a record with no chain at all.
/-- info: (true, true, true) -/
#guard_msgs in
#eval
  let short := bindChain chainRead #[("comparator/Challenge.lean", "bb")]
  let empty := bindChain chainRead #[]
  (reasonHas short "chain file(s)",
   empty.provenanceTag == "chain-unbound",
   reasonHas empty "carries no challenge chain")

/-! ## The subprocess -/

/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  let out ← IO.Process.output { cmd := toolPath, args := #["--self-test"] }
  unless out.exitCode == 0 do
    IO.eprintln s!"statement-closure --self-test failed: {out.stderr}"
    return false
  match Json.parse out.stdout with
  | .error _ => return false
  | .ok j => return (Report.ofJson? j).isOk

-- The tool on the trust fixture's Challenge, bound to the chain that fixture's status
-- record carries. This is the positive end of §A1, end to end: the bytes the tool hashed
-- are the bytes the recorded run says it verified — read from the record rather than
-- transcribed here, so the fixture cannot drift away from the assertion.
/-- info: (true, true, true, true) -/
#guard_msgs in
#eval show IO (Bool × Bool × Bool × Bool) from do
  let recorded ← do
    match Json.parse (← IO.FS.readFile "tests/fixtures/trust/comparator-status.json") with
    | .error _ => pure #[]
    | .ok j => pure (Informal.Commands.TrustComparator.ofJson j).challengeChain
  let job : Job := {
    files := #["tests/fixtures/trust/Challenge.lean"]
    roots := #["TrustFixture.add_comm_claim"]
  }
  match ← Informal.Commands.runStatementClosureTool toolPath job.toJson with
  | .error _ => return (false, false, false, false)
  | .ok doc =>
    match Report.ofJson? doc with
    | .error _ => return (false, false, false, false)
    | .ok r =>
      return (
        (bindChain r.provenance.files recorded).provenanceTag == "chain",
        r.result.entries.any (·.name == "TrustFixture.add_comm_claim"),
        r.result.entries.any (fun e => e.name == "Nat" && e.origin == "core"),
        !r.result.truncated)

-- Job-spec validation reaches the caller as a refusal, not as an empty closure.
/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  let job := Json.mkObj [
    ("files", Json.arr #[Json.str "tests/fixtures/trust/Challenge.lean"]),
    ("roots", Json.arr #[Json.str "TrustFixture.add_comm_claim"]),
    ("maxNodes", Json.num 8)]
  match ← Informal.Commands.runStatementClosureTool toolPath job with
  | .error _ => return false
  | .ok doc =>
    match Report.ofJson? doc with
    | .ok _ => return false
    | .error reason => return (reason.splitOn "job-spec: ").length > 1

/-! ### The environment is clean (§A2)

The point of running elsewhere: a chain that only elaborates because the *host* imported
the right declarations and macros is not the chain the verifier checked. Both fixtures
name things that are in scope right here — this test asserts that — and both must be
refused by the subprocess.
-/

/-- info: (true, true, "elaborate", "elaborate") -/
#guard_msgs in
#eval show CoreM (Bool × Bool × String × String) from do
  let env ← getEnv
  let stageOf (file root : String) : IO String := do
    let job : Job := { files := #[file], roots := #[root] }
    match ← Informal.Commands.runStatementClosureTool toolPath job.toJson with
    | .error e => return e
    | .ok doc => return (doc.getObjValAs? String "stage").toOption.getD "no failure"
  return (
    (env.find? `Informal.Sha256.hexOfString).isSome,
    (env.find? `Verso.Genre.Manual).isSome,
    ← stageOf "tests/fixtures/statement-closure/AmbientTerm.lean" "ambientOnly",
    ← stageOf "tests/fixtures/statement-closure/AmbientCommand.lean" "ambientDoc")

-- A missing tool is a reason string, never an exception and never a silent omission.
/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  let job : Job := { files := #["x.lean"], roots := #["A"] }
  match ← Informal.Commands.runStatementClosureTool "./.lake/build/bin/no-such-tool"
      job.toJson with
  | .ok _ => return false
  | .error reason => return reason.startsWith "the statement-closure tool"

end Verso.VersoBlueprintTests.StatementClosure
