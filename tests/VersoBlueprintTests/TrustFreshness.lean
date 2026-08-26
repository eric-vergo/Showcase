/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import VersoBlueprint
import VersoBlueprintTests.Blueprint.Support
import VersoManual

/-!
The comparator-evidence freshness gate (CX-075).

The defect this covers cannot be reproduced in-tree, because reproducing it needs two Lake
revisions and a warm `.lake` carried between them: change only the comparator status,
config, Challenge and Solution, rebuild, and the same `.olean` replays the entire prior
evidence page — old verdict, old statement, old digests, old links — under the new build's
revision, internally consistent and undetectable from the page.

What *is* testable in-tree is every link of the mechanism that stops it, and that is what
this file does, against the real fixture tree rather than constructed payloads:

- **The capture records what it read.** The four fixture files come back on the payload
  with their paths and the digests of the bytes elaboration hashed.
- **All-match is silent.** The gate run over the unmodified tree finds nothing and emits
  nothing, so the ordinary build is unaffected.
- **Each input class stops the build, named.** A payload digest that disagrees with the
  file is exactly the state a warm replay produces, so the mismatch is simulated by
  rewriting the *recorded* digest — the same comparison, driven from the side that does not
  require mutating the tree.
- **Status-only revocation names the status file and nothing else.** This is the shape the
  finding cares most about: a project publishes a correction, and the old verdict is served
  anyway.
- **A file that is gone stops the build too**, and says so differently from one that moved.

The stop text is asserted, not just the failure: a gate whose message does not name the
file is a gate somebody switches off.
-/

namespace Verso.VersoBlueprintTests.TrustFreshness

open Lean
open Verso Genre Manual
open Informal Informal.Commands
open Verso.VersoBlueprintTests.Blueprint.Support

set_option verso.blueprint.trust.comparatorStatus "tests/fixtures/trust/comparator-status.json"
set_option verso.blueprint.trust.comparatorConfig "tests/fixtures/trust/comparator.json"
set_option verso.blueprint.trust.challengeFile "tests/fixtures/trust/Challenge.lean"
set_option verso.blueprint.trust.solutionFile "tests/fixtures/trust/Solution.lean"

-- The dashboard block is what caches the trust payload, so it is the whole document
-- needed here.
#docs (Manual) freshnessDoc "Trust Freshness" :=
:::::::
:::theorem "trust.freshness.anchor" (lean := "Nat.add_comm")
Addition on the naturals commutes.
:::

{blueprint_dashboard}
:::::::

/-- The input records the real elaboration above captured. -/
def capturedInputs : IO (Array Informal.TrustInputs.Tagged) := do
  let (_, st) ← renderManualDocHtmlAndState extension_impls% freshnessDoc
  return Informal.TrustFreshness.cachedInputs st

/-- Replace the recorded digest of the first input of `role`, which is the state a warm
replay leaves behind: the file on disk has moved on, the payload has not. -/
def staleOn (inputs : Array Informal.TrustInputs.Tagged) (role : String) :
    Array Informal.TrustInputs.Tagged :=
  match inputs.findIdx? (fun i => i.2.role == role) with
  | none => inputs
  | some idx =>
    inputs.set! idx (inputs[idx]!.1,
      { inputs[idx]!.2 with sha256 := String.ofList (List.replicate 64 'a') })

/-- The message the gate would stop with, for a given set of records. -/
def stopFor (inputs : Array Informal.TrustInputs.Tagged) : IO String := do
  let findings ← Informal.TrustInputs.recheck inputs
  if findings.isEmpty then return ""
  return Informal.TrustInputs.stopMessage findings (← IO.currentDir)

/-! ## The capture records the files it was read from -/

-- Four option-named files, four records, each with the path the option named and a real
-- digest. Nothing before this round carried any of it.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← capturedInputs
  let has := fun (role path : String) =>
    inputs.any fun (topic, i) =>
      topic.isEmpty && i.role == role && i.path == path && i.sha256.length == 64
  return inputs.size == 4 &&
    has Informal.TrustInputs.roleStatus "tests/fixtures/trust/comparator-status.json" &&
    has Informal.TrustInputs.roleConfig "tests/fixtures/trust/comparator.json" &&
    has Informal.TrustInputs.roleChallenge "tests/fixtures/trust/Challenge.lean" &&
    has Informal.TrustInputs.roleSolution "tests/fixtures/trust/Solution.lean"

-- The recorded digests are of the bytes on disk, not of something else that happens to be
-- 64 hex characters: recomputing them here reproduces them exactly.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← capturedInputs
  let mut ok := !inputs.isEmpty
  for (_, i) in inputs do
    let current ← Informal.TrustInputs.digestOfFile i.path
    unless current == i.sha256 do ok := false
  return ok

/-! ## All-match: the gate is silent and the build proceeds -/

-- The whole point of the change is that an ordinary build does not notice it.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let (_, st) ← renderManualDocHtmlAndState extension_impls% freshnessDoc
  let findings ← Informal.TrustInputs.recheck (Informal.TrustFreshness.cachedInputs st)
  -- And the gate itself, on the real traversal state, which is how the emission path
  -- calls it.
  Informal.TrustFreshness.run .multi st
  return findings.isEmpty

/-! ## Each input class stops the build, and the stop names it -/

/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← capturedInputs
  let mut ok := true
  for (role, path, noun) in [
      (Informal.TrustInputs.roleStatus,
        "tests/fixtures/trust/comparator-status.json", "comparator status artifact"),
      (Informal.TrustInputs.roleConfig,
        "tests/fixtures/trust/comparator.json", "comparator configuration"),
      (Informal.TrustInputs.roleChallenge,
        "tests/fixtures/trust/Challenge.lean", "Challenge source"),
      (Informal.TrustInputs.roleSolution,
        "tests/fixtures/trust/Solution.lean", "Solution source")] do
    let findings ← Informal.TrustInputs.recheck (staleOn inputs role)
    let stop ← stopFor (staleOn inputs role)
    unless findings.size == 1 && findings[0]!.changed
        && hasSubstr stop path && hasSubstr stop noun
        && hasSubstr stop "on disk now" do
      ok := false
  return ok

/-! ## Status-only revocation

The finding's sharpest case: the project replaces its verdict — a correction, or a
retraction — and nothing else. The stop has to name the status artifact, and must not
implicate the three files that did not move.
-/

/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← capturedInputs
  let stop ← stopFor (staleOn inputs Informal.TrustInputs.roleStatus)
  return hasSubstr stop "tests/fixtures/trust/comparator-status.json" &&
    hasSubstr stop "comparator status artifact" &&
    !hasSubstr stop "tests/fixtures/trust/comparator.json" &&
    !hasSubstr stop "tests/fixtures/trust/Challenge.lean" &&
    !hasSubstr stop "tests/fixtures/trust/Solution.lean" &&
    -- and it says what to do about it rather than only that something is wrong
    hasSubstr stop "Re-elaborate the module" &&
    hasSubstr stop "blueprint_dashboard"

/-! ## A file that is gone -/

-- Distinguished from one that moved: "we could not read it" and "it says something else"
-- are different states, and a reader chasing a build failure needs to know which.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← capturedInputs
  let missing : Informal.TrustInputs.Input := {
    role := Informal.TrustInputs.roleChallenge
    path := "tests/fixtures/trust/NoSuchChallenge.lean"
    sha256 := String.ofList (List.replicate 64 'b') }
  let findings ← Informal.TrustInputs.recheck (inputs.push ("", missing))
  let stop ← stopFor (inputs.push ("", missing))
  return findings.size == 1 && !findings[0]!.changed &&
    findings[0]!.kind == "unreadable" &&
    hasSubstr stop "NoSuchChallenge.lean" &&
    hasSubstr stop "cannot be read now"

/-! ## An unchecked record is not a failure

A payload from a build that recorded no digest for something has nothing to compare. That
is a weaker state, not a violation, and stopping builds over a record's silence would make
the gate the thing consumers switch off.
-/

/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let unrecorded : Informal.TrustInputs.Input :=
    { role := Informal.TrustInputs.roleChallenge, path := "tests/fixtures/trust/gone.lean" }
  let findings ← Informal.TrustInputs.recheck #[("", unrecorded)]
  return findings.isEmpty

/-! ## Reading the records back out of a serialized payload

The gate runs below the rendering layer and walks the payload as JSON, so the walk is
tested on the shape a multi-topic consumer produces: per-topic records have to come back
tagged with the topic that named them, or a stop message would point at the wrong panel.
-/

/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let input := fun (role path digest : String) =>
    Json.mkObj [("role", Json.str role), ("path", Json.str path), ("sha256", Json.str digest)]
  let payload := Json.mkObj [
    ("inputs", Json.arr #[input "formalization-yaml" "formalization.yaml" "aa"]),
    ("comparators", Json.arr #[
      Json.mkObj [("name", Json.str "Topic One"),
        ("comparator", Json.mkObj [("inputs", Json.arr #[input "challenge" "a/C.lean" "bb"])])],
      Json.mkObj [("name", Json.str "Topic Two"),
        ("comparator", Json.mkObj [("inputs", Json.arr #[input "solution" "b/S.lean" "cc"])])]])]
  let found := Informal.TrustInputs.ofPayload payload
  return found.size == 3 &&
    found[0]! == ("", { role := "formalization-yaml", path := "formalization.yaml", sha256 := "aa" }) &&
    found[1]!.1 == "Topic One" && found[1]!.2.path == "a/C.lean" &&
    found[2]!.1 == "Topic Two" && found[2]!.2.path == "b/S.lean"

-- A payload carrying nothing to check yields nothing to check, rather than an exception.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  return (Informal.TrustInputs.ofPayload (Json.mkObj [])).isEmpty &&
    (Informal.TrustInputs.ofPayload (Json.str "not a payload")).isEmpty &&
    (Informal.TrustInputs.ofPayload
      (Json.mkObj [("comparator", Json.null), ("comparators", Json.num 3)])).isEmpty

/-! ## The published provenance record

What a CI gate re-hashes against the working tree. It has to carry the same paths and
digests the payload does, and the revision the build stamped itself with, so the two
cannot be independently sampled the way CX-066 found them being.
-/

/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← capturedInputs
  let doc ← Informal.TrustFreshness.provenanceJson inputs
  let recorded := ((doc.getObjVal? "inputs").toOption.bind (·.getArr?.toOption)).getD #[]
  let paths := recorded.filterMap fun j => (j.getObjValAs? String "path").toOption
  let digests := recorded.filterMap fun j => (j.getObjValAs? String "sha256").toOption
  return (doc.getObjValAs? Nat "schemaVersion").toOption == some 1 &&
    (doc.getObjVal? "buildRevision").toOption.isSome &&
    recorded.size == inputs.size &&
    paths == inputs.map (·.2.path) &&
    digests == inputs.map (·.2.sha256) &&
    -- A topic-less input carries no topic key rather than an empty one, so a gate reading
    -- the record cannot mistake "no topic" for a topic named "".
    recorded.all fun j => (j.getObjVal? "topic").toOption.isNone

end Verso.VersoBlueprintTests.TrustFreshness
