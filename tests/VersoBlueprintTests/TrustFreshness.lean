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
set_option verso.blueprint.trust.expectedKernelIdentities "tests/fixtures/trust/kernel-identities.json"

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

-- Five option-named files, five records, each with the path the option named and a real
-- digest. Nothing before this round carried any of it. The pinned identities are in the
-- ledger for the same reason the status artifact is: a verdict authenticated against a pin
-- that has since moved is a verdict authenticated against nothing (CX-064).
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← capturedInputs
  let has := fun (role path : String) =>
    inputs.any fun (topic, i) =>
      topic.isEmpty && i.role == role && i.path == path && i.sha256.length == 64
  return inputs.size == 5 &&
    has Informal.TrustInputs.roleStatus "tests/fixtures/trust/comparator-status.json" &&
    has Informal.TrustInputs.roleConfig "tests/fixtures/trust/comparator.json" &&
    has Informal.TrustInputs.roleChallenge "tests/fixtures/trust/Challenge.lean" &&
    has Informal.TrustInputs.roleSolution "tests/fixtures/trust/Solution.lean" &&
    has Informal.TrustInputs.roleKernelIdentities "tests/fixtures/trust/kernel-identities.json"

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
        "tests/fixtures/trust/Solution.lean", "Solution source"),
      (Informal.TrustInputs.roleKernelIdentities,
        "tests/fixtures/trust/kernel-identities.json", "pinned kernel identities")] do
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

/-! ## A record with no digest is a record this build cannot check (CX-077)

An input that says it was *present* and carries no digest has nothing to compare, and used
to be skipped for that reason. Nothing this fork writes produces one — a present record
comes from a read that hashed what it read, and a build that found nothing writes
`Input.absent` — so the row is a payload this gate cannot check, which is the thing it
exists to refuse. Skipping it is also what made an absent capture indistinguishable from an
unhashed one, which is half of how the file-appears case got through.
-/

/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let unrecorded : Informal.TrustInputs.Input :=
    { role := Informal.TrustInputs.roleChallenge, path := "tests/fixtures/trust/Challenge.lean" }
  let findings ← Informal.TrustInputs.recheck #[("", unrecorded)]
  let stop ← stopFor #[("", unrecorded)]
  return findings.size == 1 && findings[0]!.kind == "unrecorded" &&
    hasSubstr stop "recorded with no digest" &&
    hasSubstr stop "tests/fixtures/trust/Challenge.lean"

/-! ## Configured, absent, and then there (CX-077)

The comparator configuration and the Solution are the two inputs whose absence is not a
build error: the section is omitted and the page says less. What their absence must not do
is omit the *path*, because then the ledger has no row for it, the recheck has nothing to
re-read, and a file generated at that path afterwards is published by a warm build with its
bytes never compared against the digests the verdict recorded — the comparison a cold build
runs, and fails.

The finding's replay is cold-A (paths absent), then create the files, then warm-B. The
`.olean` is the payload, so the unit-equivalent drives the same comparison from the payload
side: capture with the paths absent, then ask the recheck about a path that is there. That
is the idiom the digest cases above use, for the same reason — it needs no mutation of the
fixture tree.
-/

private def missingSolution : String := "tests/fixtures/trust/NotYetGenerated.lean"
private def missingConfig : String := "tests/fixtures/trust/not-yet-generated.json"

set_option verso.blueprint.trust.comparatorStatus "tests/fixtures/trust/comparator-status.json" in
set_option verso.blueprint.trust.comparatorConfig "tests/fixtures/trust/not-yet-generated.json" in
set_option verso.blueprint.trust.challengeFile "tests/fixtures/trust/Challenge.lean" in
set_option verso.blueprint.trust.solutionFile "tests/fixtures/trust/NotYetGenerated.lean" in
#docs (Manual) pendingDoc "Trust Freshness Pending" :=
:::::::
:::theorem "trust.pending.anchor" (lean := "Nat.add_comm")
Addition on the naturals commutes.
:::

{blueprint_dashboard}
:::::::

/-- The input records the capture above produced, with two of its four paths absent. -/
def pendingInputs : IO (Array Informal.TrustInputs.Tagged) := do
  let (_, st) ← renderManualDocHtmlAndState extension_impls% pendingDoc
  return Informal.TrustFreshness.cachedInputs st

-- Cold A: the build renders — a missing config and Solution are not an error — and both
-- configured paths are on the payload, recorded absent and with no digest.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← pendingInputs
  let recordedAbsent := fun (role path : String) =>
    inputs.any fun (topic, i) =>
      topic.isEmpty && i.role == role && i.path == path && !i.wasPresent && i.sha256.isEmpty
  return inputs.size == 5 &&
    recordedAbsent Informal.TrustInputs.roleConfig missingConfig &&
    recordedAbsent Informal.TrustInputs.roleSolution missingSolution &&
    -- and the two files that were there are recorded the way they always were
    inputs.any (fun (_, i) => i.role == Informal.TrustInputs.roleStatus && i.wasPresent
      && i.sha256.length == 64)

-- Warm B, nothing created: absent then, absent now. The gate is silent, because that is the
-- state the capture describes.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let (_, st) ← renderManualDocHtmlAndState extension_impls% pendingDoc
  let findings ← Informal.TrustInputs.recheck (Informal.TrustFreshness.cachedInputs st)
  Informal.TrustFreshness.run .multi st
  return findings.isEmpty

-- Warm B, the Solution generated in between: the recheck sees a file where the capture
-- recorded none, and the stop names the path, says what it was, and says what it is now.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← pendingInputs
  let appeared := inputs.map fun (topic, i) =>
    if i.role == Informal.TrustInputs.roleSolution then
      (topic, { i with path := "tests/fixtures/trust/Solution.lean" })
    else (topic, i)
  let findings ← Informal.TrustInputs.recheck appeared
  let stop ← stopFor appeared
  return findings.size == 1 && findings[0]!.kind == "appeared" &&
    !findings[0]!.changed &&
    hasSubstr stop "tests/fixtures/trust/Solution.lean" &&
    hasSubstr stop "Solution source" &&
    hasSubstr stop "not there when this payload was captured" &&
    hasSubstr stop "on disk now" &&
    -- the three inputs that did not move are not implicated
    !hasSubstr stop "comparator-status.json" &&
    !hasSubstr stop "tests/fixtures/trust/Challenge.lean" &&
    !hasSubstr stop missingConfig &&
    -- and it explains why an appearance is the same failure as a change
    hasSubstr stop "a cold build would have done that"

-- The reverse transition, on the same payload: a file that was there at capture and is gone
-- now is still named, and named differently.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← capturedInputs
  let vanished := inputs.map fun (topic, i) =>
    if i.role == Informal.TrustInputs.roleSolution then
      (topic, { i with path := missingSolution })
    else (topic, i)
  let findings ← Informal.TrustInputs.recheck vanished
  let stop ← stopFor vanished
  return findings.size == 1 && findings[0]!.kind == "unreadable" &&
    hasSubstr stop missingSolution && hasSubstr stop "cannot be read now"

/-! ## The two F2 side inputs (CX-062, CX-067)

Both findings replay the same warm A→B shape on a different file: edit only the junk-value
table override, or only the characterization sidecar, rebuild, and the byte-identical
`.olean` republishes the previous table's behaviour sentences, version and digest — or the
previous sidecar's statements — under the current revision.

Both files are read at elaboration by `elabTrustData?`, and both are on this ledger, so the
question those findings raise is answered by the gate above rather than by a mechanism of
their own. That is asserted here rather than assumed: the payload has to carry the two
paths with the digests of the bytes read, and a stale digest on either has to stop the
build naming that file and not the others.

The `.olean` is the payload, so the two-build shape is driven from the payload side — the
same idiom as every other case in this module, and for the same reason.
-/

private def tableOverride : String := "tests/fixtures/caveats/table-override.json"
private def sidecar : String := "tests/fixtures/caveats/characterizations.json"

set_option verso.blueprint.trust.junkValueTable "tests/fixtures/caveats/table-override.json" in
set_option verso.blueprint.trust.characterizations "tests/fixtures/caveats/characterizations.json" in
#docs (Manual) sideInputDoc "Trust Freshness Side Inputs" :=
:::::::
:::theorem "trust.sideinputs.anchor" (lean := "Nat.add_comm")
Addition on the naturals commutes.
:::

{blueprint_dashboard}
:::::::

/-- The input records the capture above produced, the two F2 files included. -/
def sideInputs : IO (Array Informal.TrustInputs.Tagged) := do
  let (_, st) ← renderManualDocHtmlAndState extension_impls% sideInputDoc
  return Informal.TrustFreshness.cachedInputs st

-- Cold A: six records, the two new ones with the paths the options named and the digests
-- of the bytes elaboration read.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← sideInputs
  let has := fun (role path : String) =>
    inputs.any fun (topic, i) =>
      topic.isEmpty && i.role == role && i.path == path && i.sha256.length == 64
  let matchesDisk ← do
    let mut ok := true
    for (_, i) in inputs do
      unless (← Informal.TrustInputs.digestOfFile i.path) == i.sha256 do ok := false
    pure ok
  return inputs.size == 7 && matchesDisk &&
    has Informal.TrustInputs.roleCaveatTable tableOverride &&
    has Informal.TrustInputs.roleCharacterizations sidecar

-- Warm B on the junk table alone: the gate stops, names the table, and does not implicate
-- the sidecar or the four comparator artifacts.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← sideInputs
  let stale := staleOn inputs Informal.TrustInputs.roleCaveatTable
  let findings ← Informal.TrustInputs.recheck stale
  let stop ← stopFor stale
  return findings.size == 1 && findings[0]!.changed &&
    hasSubstr stop tableOverride && hasSubstr stop "caveat table" &&
    !hasSubstr stop sidecar &&
    !hasSubstr stop "tests/fixtures/trust/comparator-status.json"

-- Warm B on the characterization sidecar alone: same, the other way round.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let inputs ← sideInputs
  let stale := staleOn inputs Informal.TrustInputs.roleCharacterizations
  let findings ← Informal.TrustInputs.recheck stale
  let stop ← stopFor stale
  return findings.size == 1 && findings[0]!.changed &&
    hasSubstr stop sidecar && hasSubstr stop "characterization sidecar" &&
    !hasSubstr stop tableOverride

-- And the whole gate, on the real files: unmodified, it says nothing.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let (_, st) ← renderManualDocHtmlAndState extension_impls% sideInputDoc
  Informal.TrustFreshness.run .multi st
  let findings ← Informal.TrustInputs.recheck (Informal.TrustFreshness.cachedInputs st)
  return findings.isEmpty

/-! ## The declaration registry's own ledger (CX-062)

The comparator-side half above is only half of the junk table's reach. The registry-side
caveat scan is built by `blueprint_graph`, quoted into *that* block's `.olean`, and
published on every declaration page — and a consumer with no comparator has no trust
payload for the table to ride at all. So the registry records what it read in its own
traversal-store key, and the gate re-reads that too.

Driven from the state side, like the CX-076 case above: the store key is the payload.
-/

private def registryLedger (digest : String) : String :=
  (toJson #[({ role := Informal.TrustInputs.roleCaveatTable, path := tableOverride
               sha256 := digest } : Informal.TrustInputs.Input)]).compress

-- A fresh ledger is silent, and a stale one stops with the registry's own message: the
-- `blueprint_graph` block, the scan it captured, and the file that decided it.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let (_, st) ← renderManualDocHtmlAndState extension_impls% freshnessDoc
  let current ← Informal.TrustInputs.digestOfFile tableOverride
  let fresh := Informal.TraversalIndex.DeclRegistry.saveInputs st (registryLedger current)
  let stale := Informal.TraversalIndex.DeclRegistry.saveInputs st
    (registryLedger (String.ofList (List.replicate 64 'a')))
  Informal.TrustFreshness.run .multi fresh
  let stopped ← try
      Informal.TrustFreshness.run .multi stale
      pure ""
    catch e => pure (toString e)
  return (Informal.TrustFreshness.registryInputs fresh).size == 1 &&
    (Informal.TrustFreshness.registryInputs st).isEmpty &&
    hasSubstr stopped "declaration-registry evidence check FAILED" &&
    hasSubstr stopped tableOverride &&
    hasSubstr stopped "caveat table" &&
    hasSubstr stopped "blueprint_graph" &&
    -- and it does not send the reader to the comparator's block
    !hasSubstr stopped "blueprint_dashboard"

-- The case the trust payload cannot cover: a consumer with a registry and no comparator at
-- all. The registry ledger is checked on its own, so the stale scan still stops the build.
#docs (Manual) noTrustDoc "No Trust Payload" :=
:::::::
:::theorem "trust.notrust.anchor" (lean := "Nat.add_comm")
Addition on the naturals commutes.
:::
:::::::

/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let (_, bare) ← renderManualDocHtmlAndState extension_impls% noTrustDoc
  let stale := Informal.TraversalIndex.DeclRegistry.saveInputs bare
    (registryLedger (String.ofList (List.replicate 64 'a')))
  let stopped ← try
      Informal.TrustFreshness.run .multi stale
      pure ""
    catch e => pure (toString e)
  return (Informal.TrustFreshness.cachedPayload? stale).isNone &&
    hasSubstr stopped "declaration-registry evidence check FAILED" &&
    hasSubstr stopped tableOverride

-- A ledger this build cannot read is nothing to check, not an exception.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let (_, bare) ← renderManualDocHtmlAndState extension_impls% noTrustDoc
  let junk := Informal.TraversalIndex.DeclRegistry.saveInputs bare "not json"
  let empty := Informal.TraversalIndex.DeclRegistry.saveInputs bare "[]"
  Informal.TrustFreshness.run .multi junk
  Informal.TrustFreshness.run .multi empty
  return (Informal.TrustFreshness.registryInputs junk).isEmpty &&
    (Informal.TrustFreshness.registryInputs empty).isEmpty

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

/-! ## A claim badge with nothing behind it (CX-076)

The finding's replay is two processes: elaborate a document while a probe answers, then
import the warm `.olean` with the probe gone and render. The `.olean` *is* the payload, so
the unit-equivalent is the payload — a claim-level registry entry whose bytes came off the
network, with no Palomar record in the input ledger — met by the gate that runs between
traversal and emission. The match boundary is what stops such a payload being written
(`Informal.Palomar.matchEntry?`); this is the backstop for one written elsewhere.
-/

private def probeOrigin : String :=
  "https://data.palomar-registry.org/entries/PALOMAR-2026-08-07-000007-v1.json"

private def registryEntryJson (origin : String) : Json :=
  toJson ({ id := "PALOMAR-2026-08-07-000007", version := 1
            matchBasis := "repo+digest", recordOrigin := origin } : RegistryEntry)

/-- The real capture from the document above, plus the badge a probe-only build would have
minted: everything else is what this build actually read. -/
def withClaimEntry (payload : Json) (origin : String) : Option Json := do
  let cmp ← (payload.getObjVal? "comparator").toOption
  some (payload.setObjVal! "comparator" (cmp.setObjVal! "registryEntry" (registryEntryJson origin)))

-- The finding's shape: claim-level entry, probe origin, and — because no bundle was
-- configured — no Palomar input recorded at all. The gate stops before anything is written,
-- and names the record, the origin and both options.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let (_, st) ← renderManualDocHtmlAndState extension_impls% freshnessDoc
  let some payload := Informal.TrustFreshness.cachedPayload? st | return false
  let some doctored := withClaimEntry payload probeOrigin | return false
  let violations := Informal.TrustFreshness.claimBackingViolations doctored
  let stopped ← try
      Informal.TrustFreshness.run .multi
        (Informal.TraversalIndex.TrustData.saveData st doctored)
      pure ""
    catch e => pure (toString e)
  return violations.size == 1 && violations[0]!.kind == "probed" &&
    violations[0]!.label == "PALOMAR-2026-08-07-000007-v1" &&
    hasSubstr stopped "unbacked claim badge" &&
    hasSubstr stopped "PALOMAR-2026-08-07-000007-v1" &&
    hasSubstr stopped probeOrigin &&
    hasSubstr stopped "palomarProbe" && hasSubstr stopped "palomarBundle" &&
    -- and it says what to do, like every other stop in this module
    hasSubstr stopped "Re-elaborate the module"

-- The other bypass: a record that names a file, on a payload that records no Palomar input.
-- Nothing was read, so nothing can be re-read, whatever the origin field says.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let (_, st) ← renderManualDocHtmlAndState extension_impls% freshnessDoc
  let some payload := Informal.TrustFreshness.cachedPayload? st | return false
  let some doctored := withClaimEntry payload "palomar/entries/PALOMAR-2026-08-07-000007-v1.json"
    | return false
  let violations := Informal.TrustFreshness.claimBackingViolations doctored
  return violations.size == 1 && violations[0]!.kind == "unrecorded" &&
    hasSubstr (Informal.TrustFreshness.claimBackingStopMessage violations)
      "records no Palomar input"

-- Backed and silent: the same entry on a payload that did record the bundle it came from.
-- The gate has an opinion only about badges with nothing behind them.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let (_, st) ← renderManualDocHtmlAndState extension_impls% freshnessDoc
  let some payload := Informal.TrustFreshness.cachedPayload? st | return false
  let recordPath := "tests/fixtures/palomar/bundle/entries/PALOMAR-2026-08-07-000007-v1.json"
  let some doctored := withClaimEntry payload recordPath | return false
  let digest ← Informal.TrustInputs.digestOfFile recordPath
  let inputs := ((doctored.getObjVal? "inputs").toOption.bind (·.getArr?.toOption)).getD #[]
  let doctored := doctored.setObjVal! "inputs" (Json.arr (inputs.push (toJson
    ({ role := Informal.TrustInputs.roleRegistryRecord, path := recordPath, sha256 := digest }
      : Informal.TrustInputs.Input))))
  -- No violation, and the whole gate passes on the real (unmodified) files.
  Informal.TrustFreshness.run .multi (Informal.TraversalIndex.TrustData.saveData st doctored)
  return (Informal.TrustFreshness.claimBackingViolations doctored).isEmpty &&
    -- the untouched capture has nothing to answer for either
    (Informal.TrustFreshness.claimBackingViolations payload).isEmpty

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
