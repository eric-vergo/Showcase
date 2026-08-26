/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import VersoBlueprint.TrustInputs
import VersoBlueprint.TraversalIndex
import VersoBlueprint.RuntimeCache
import VersoBlueprint.Palomar

/-!
# Comparator-evidence freshness gate, run *before* any HTML is written

The trust payload is read from `verso.blueprint.trust.*`-named files at elaboration and
quoted into the `.olean`; generation decodes the quoted payload and re-reads nothing. None
of those files is a Lean module, so Lake tracks no read of them: change the comparator
status, the configuration, the Challenge and the Solution, rebuild, and the same
`.olean` is reused and the *entire prior evidence page* is published under the new build's
revision — the old verdict beside the old statement, links naming the old bytes, all
internally consistent (CX-075).

This gate is what makes that stop. Every input the payload records
(`Informal.TrustInputs`) is re-read and its digest compared against the capture; any
mismatch or unreadable file aborts the build with the files named, before anything is
written. It never re-serves the snapshot and never repairs it: a capture that does not
match its sources is not evidence about this build, and the only correct outcome is a
rebuild.

Placed beside `Informal.GraphGate` in `PreviewManifest.emitBlueprintHtml` rather than in
an `ExtraStep`, and for the same reason: it runs between traversal and emission, so it
covers **both** consumers of the payload — the dashboard trust strip and the trust-model
page, which render during `emit`, and the `comparator/` page, which is an `ExtraStep`
after it — and a failing gate leaves no rendered site on disk.

## Making the stop a backstop rather than the workflow

The gate is correct but blunt: it turns a stale capture into a failed build, and the fix
is always "re-elaborate the capturing module". Ordinary builds should do that on their own,
and Lake can be told to make them.

**Not from here, though.** Nothing in Lean lets an elaborator register a non-Lean file as
an input of the module it is elaborating. `include_str` is the nearest thing and it does
not do it either — its elaborator is `IO.FS.readFile` and nothing else
(`Lean/Elab/BuiltinTerm.lean`, `elabIncludeStr`), a limitation the toolchain documents in
as many words in `Lean/Widget/Types.lean`: "beware that this does not register a
dependency with Lake". `Lean.recordExtraModUse` records edges to Lean *modules*, not to
files. And even if such an API existed, these paths are consumer option values resolved at
the consumer's build, not literals known when this fork is compiled.

So the edge is declared where the paths are known — the consumer's lakefile — and this is
the form that works:

```lean
-- The trust surfaces are captured at elaboration from files Lake does not otherwise
-- track (CX-075). An `input_file` hashes one into the library's extra-dep job trace,
-- which Lake mixes into every module's `depTrace`, so an ordinary `lake build`
-- re-elaborates the capture when the file changes and `Informal.TrustFreshness`'s
-- fail-closed stop stays the backstop it is meant to be.
input_file comparatorStatus where
  path := "../comparator/comparator-status.json"

input_file comparatorConfig where
  path := "../comparator/comparator.json"

input_file comparatorChallenge where
  path := "../comparator/Challenge.lean"

input_file comparatorSolution where
  path := "../comparator/Solution.lean"

lean_lib Contents where
  needs := #[`@/comparatorStatus, `@/comparatorConfig,
             `@/comparatorChallenge, `@/comparatorSolution]
  -- existing roots / globs / leanOptions unchanged
```

Three things about that snippet are load-bearing, and getting any of them wrong gives a
consumer a dependency edge that is not there:

- **`needs`, never `extraDepTargets`.** `extraDepTargets` is deprecated, and for a
  *named-kind* declaration — which `input_file` is — Lake resolves it through a branch
  that neither builds the target nor contributes a trace (`Lake/Build/Index.lean`, the
  `Job.pure` case), so `extraDepTargets := #[`comparatorStatus]` is a silent no-op. `needs`
  fetches the target for real. (A hand-written `target`, which has anonymous kind, does
  work through `extraDepTargets` — which is why the trap is easy to fall into.)
- **`path` is relative to the *package* directory**, so a consumer whose site is a
  sub-package writes `../…` exactly as the trust option does.
- **Leave `text` at its default (`false`).** `text := true` normalizes line endings before
  hashing, so a CRLF↔LF change would move this gate's byte digest without moving Lake's
  trace — a build that fails the gate and cannot be fixed by rebuilding. Binary hashing
  keeps the two mechanisms looking at the same bytes.

Granularity is the library, not the module: every module in that `lean_lib` re-elaborates
when one of the files changes. For a small `Contents` library that is the right trade; for
a large one, isolate the module carrying the `blueprint_dashboard` block into its own
library and put `needs` there.

Where the edge is not declared, `lake build <lib> -R` (or touching the capturing module) is
the reliable trigger, and this gate is what makes forgetting it loud instead of silent.

## The other half: a badge with nothing behind it

Re-reading the recorded inputs answers "are these still the bytes?". It cannot answer "was
there ever a file?", and CX-076 was exactly that: with no bundle configured, a record the
probe fetched could mint a claim-level registry badge whose bytes are deliberately excluded
from the ledger above, so a warm rebuild kept the badge with the probe long gone and this
gate had nothing to re-hash.

The match boundary is where that is fixed (`Informal.Palomar.matchEntry?`: a probed record
is never claim-level). `claimBackingViolations` is the backstop for a payload that says
otherwise — one quoted into an `.olean` by an older or a patched fork — and it is checked
here, before emission, for the same reason as the digests: a badge that cannot be
re-established is not something to render and explain afterwards.

## The machine-readable record

`emitTrustProvenance` writes the same input set, plus the revision the build stamped
itself with, to `-verso-data/trust-provenance.json`. A publishing gate re-hashes those
paths in the working tree and compares — the same check as this gate, run by CI against
the *committed* files rather than against the build's own idea of them, which is what
catches a site generated from an uncommitted or differently-rooted tree.
-/

namespace Informal.TrustFreshness

open Lean
open Verso.Genre Manual

/-- The trust payload the traversal cached, as the JSON it was quoted from. `none` when
none was stored (no `blueprint_dashboard` block, or no trust option configured). -/
def cachedPayload? (state : TraverseState) : Option Json :=
  Informal.TraversalIndex.TrustData.raw? state

/-- The input records the traversal-cached trust payload carries. Empty when no payload was
stored (no `blueprint_dashboard` block, or no trust option configured). -/
def cachedInputs (state : TraverseState) : Array Informal.TrustInputs.Tagged :=
  match cachedPayload? state with
  | some payload => Informal.TrustInputs.ofPayload payload
  | none => #[]

/-! ## Claim-level registry badges, and what has to be behind one -/

/-- A claim-level registry entry this build would render with nothing recorded behind it. -/
structure ClaimBacking where
  /-- `id`-`v`-`version`, as the payload names the record. -/
  label : String := ""
  /-- The comparator topic whose panel carries it; empty for the single-pair comparator. -/
  topic : String := ""
  /-- The record's `recordOrigin`: a URL where the probe fetched it, empty where the payload
  does not say. -/
  origin : String := ""
  /-- `probed` (the bytes came off the network) or `unrecorded` (the payload records no
  Palomar input at all). -/
  kind : String := ""
deriving Inhabited, Repr

/-- The input roles whose records are Palomar bytes. -/
private def registryRoles : List String :=
  [Informal.TrustInputs.roleRegistryBundle, Informal.TrustInputs.roleRegistryRecord]

private def registryEntryOf? (comparator : Json) : Option Json :=
  match comparator.getObjVal? "registryEntry" with
  | .ok (j@(.obj _)) => some j
  | _ => none

/-- The registry entries the payload's comparators carry, each with the topic that named it.

The project-level `registryEntry` is deliberately not walked. It is the soft tier — no
badge, a card that says in prose what it is not — and a record demoted to it *because* its
bytes are unrecorded belongs there. -/
private def comparatorRegistryEntries (payload : Json) : Array (String × Json) := Id.run do
  let mut out : Array (String × Json) := #[]
  if let .ok cmp := payload.getObjVal? "comparator" then
    if let some e := registryEntryOf? cmp then out := out.push ("", e)
  if let .ok (.arr topics) := payload.getObjVal? "comparators" then
    for t in topics do
      let name := (t.getObjValAs? String "name").toOption.getD ""
      if let .ok cmp := t.getObjVal? "comparator" then
        if let some e := registryEntryOf? cmp then out := out.push (name, e)
  return out

/--
Claim-level registry entries on this payload that no recorded Palomar input backs.

Two shapes, and they catch different bypasses. A record whose origin is a URL was fetched
during elaboration and has no file behind it, whatever else the payload recorded — this is
the cache-plus-probe case. A payload that records no Palomar input at all cannot back any
claim-level entry, whatever its origin says — this is the CX-076 case, where no bundle was
configured and the ledger is empty.

An entry whose origin the payload does not state, on a payload that *did* record registry
inputs, is left alone: it is an older capture that named its bytes less precisely, not a
badge with nothing behind it, and stopping a build over a field's silence is how a gate
becomes the thing consumers switch off.
-/
def claimBackingViolations (payload : Json) : Array ClaimBacking := Id.run do
  let entries := comparatorRegistryEntries payload
  if entries.isEmpty then return #[]
  let str := fun (j : Json) (k : String) => (j.getObjValAs? String k).toOption.getD ""
  let recorded := (Informal.TrustInputs.ofPayload payload).filter
    fun (_, i) => registryRoles.contains i.role
  let mut out : Array ClaimBacking := #[]
  for (topic, entry) in entries do
    unless Informal.Palomar.claimLevelBases.contains (str entry "matchBasis") do continue
    let origin := str entry "recordOrigin"
    let id := str entry "id"
    let version := (entry.getObjValAs? Nat "version").toOption.getD 0
    let label := if id.isEmpty then "an unnamed record" else s!"{id}-v{version}"
    if Informal.Palomar.isProbeOrigin origin then
      out := out.push { label, topic, origin, kind := "probed" }
    else if recorded.isEmpty then
      out := out.push { label, topic, origin, kind := "unrecorded" }
  return out

/-- One violation as two lines: which record, and what is missing behind it. -/
private def backingLine (v : ClaimBacking) : String :=
  let topicNote := if v.topic.isEmpty then "" else s!" [topic: {v.topic}]"
  let detail :=
    if v.kind == "probed" then
      s!"fetched from {v.origin} while the capturing build ran; there is no file to re-read"
    else "this payload records no Palomar input, so there are no bytes to re-read"
  String.intercalate "\n" [s!"  {v.label}{topicNote}", s!"      {detail}"]

/--
The stop message: which badge, why it cannot be published, and how to get the binding back.

Written for the same reader as `Informal.TrustInputs.stopMessage` — a CI log, no other
context — and it says which of the two things they can do: cache the record, or accept the
softer surface.
-/
def claimBackingStopMessage (violations : Array ClaimBacking) : String :=
  let n := violations.size
  let noun := if n == 1 then "badge" else "badges"
  let lines := String.intercalate "\n" (violations.map backingLine).toList
  s!"Showcase registry evidence check FAILED (unbacked claim badge): {n} claim-level Palomar \
     {noun} on this payload {if n == 1 then "is" else "are"} not backed by a registry record \
     this build recorded.\n\n\
     {lines}\n\n\
     A claim-level registration is the one registry surface that reads as being about the \
     statement on the page: it earns a strip badge and renders inside that claim's panel. It \
     is therefore only ever taken from a record in the configured bundle \
     ('verso.blueprint.trust.palomarBundle'), whose bytes this build records as an input and \
     re-reads before anything is written. A record fetched by \
     'verso.blueprint.trust.palomarProbe' is a network response that no longer exists at \
     generation time, so a warm rebuild would replay the badge with nothing behind it and \
     nothing able to notice (CX-076).\n\n\
     This payload was elaborated by a build that did not enforce that. Re-elaborate the \
     module carrying the `blueprint_dashboard` block against this fork (`lake build <lib> \
     -R`): the registration will render as project-level provenance, which is what an \
     unrecorded record establishes. To keep it bound to the claim, cache the record and \
     configure 'verso.blueprint.trust.palomarBundle'."

/--
Stop the build if the trust payload cannot be published as it stands.

Two checks, both before the caller emits anything, both throwing `IO.userError`:

- every file the payload was elaborated from is re-read and its digest compared, so a
  capture that no longer matches its sources fails instead of shipping (CX-075);
- every claim-level registry badge is required to have a recorded Palomar record behind it,
  so a badge minted from a network response cannot survive into a warm rebuild (CX-076).

Runs in both output modes: the strip and the trust-model page render in single-page output
too, so a stale capture is just as publishable there.

Silent when there is nothing to check — no payload, or a payload from a fork build that
recorded no inputs and carries no claim-level registry entry. A missing input record is not
evidence of freshness, but neither is it grounds to stop a build that never claimed any:
the failure mode the first check guards is a *stale* capture, and a payload with no inputs
has nothing to be stale against.
-/
def run (_mode : Mode) (state : TraverseState) : IO Unit := do
  let some payload := cachedPayload? state | return ()
  let violations := claimBackingViolations payload
  unless violations.isEmpty do
    throw <| IO.userError (claimBackingStopMessage violations)
  let inputs := Informal.TrustInputs.ofPayload payload
  if inputs.isEmpty then return ()
  let findings ← Informal.TrustInputs.recheck inputs
  unless findings.isEmpty do
    throw <| IO.userError (Informal.TrustInputs.stopMessage findings (← IO.currentDir))

/-! ## Machine-readable provenance -/

/-- Schema version of `-verso-data/trust-provenance.json`. -/
def provenanceSchemaVersion : Nat := 1

/-- Filename of the provenance record under `-verso-data/`. -/
def provenanceFilename : String := "trust-provenance.json"

/--
The provenance document: what the trust payload was elaborated from, and which revision
this build describes itself by.

`buildRevision` comes from `RuntimeCache.currentBuildRevision` — the single probe the build
stamp and every project-local source link already share, so a publishing gate comparing
this record against the stamp is comparing one value with itself rather than two
independent samples of git (the CX-066 failure).

`dirty` is carried rather than folded into the commit: a gate that requires a clean tree
needs to say *that*, not parse a `-dirty` suffix off a display string.
-/
def provenanceJson (inputs : Array Informal.TrustInputs.Tagged) : IO Json := do
  let rev ← Informal.RuntimeCache.currentBuildRevision
  let strOpt : Option String → Json := fun s? => (s?.map Json.str).getD Json.null
  let boolOpt : Option Bool → Json := fun b? => (b?.map Json.bool).getD Json.null
  let records : Array Json := inputs.map fun (topic, input) =>
    Json.mkObj <|
      [("role", Json.str input.role),
       ("path", Json.str input.path),
       ("sha256", Json.str input.sha256)] ++
      (if topic.isEmpty then [] else [("topic", Json.str topic)])
  return Json.mkObj [
    ("schemaVersion", Json.num provenanceSchemaVersion),
    ("buildRevision", Json.mkObj [
      ("commit", strOpt rev.fullCommit?),
      ("shortCommit", strOpt rev.shortCommit?),
      ("dirty", boolOpt rev.dirty?),
      ("repositoryUrl", strOpt rev.repositoryUrl?)]),
    ("inputs", Json.arr records)]

/--
`ExtraStep` writing `-verso-data/trust-provenance.json`.

Emits nothing when the payload records no inputs, so a consumer configuring no trust
option gets no new file. Deliberately separate from `emitBlueprintComparatorPage`: that
step returns early in several honest states (no dashboard block, an undecodable payload,
no comparator configured) and the provenance record is exactly what a publishing gate
wants in some of them.
-/
def emitTrustProvenance : ExtraStep :=
  fun mode cfg state _text => do
    let inputs := cachedInputs state
    if inputs.isEmpty then return ()
    let outDir := cfg.destination.join
      (match mode with | .single => "html-single" | .multi => "html-multi")
    let dataDir := outDir.join "-verso-data"
    IO.FS.createDirAll dataDir
    IO.FS.writeFile (dataDir.join provenanceFilename)
      ((← provenanceJson inputs).compress ++ "\n")

end Informal.TrustFreshness
