/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import Lean
import VersoBlueprint.Sha256

/-!
# The non-Lean files a trust payload was elaborated from

Every `verso.blueprint.trust.*` option names a file, and every one of those files is read
at **elaboration**: the comparator status artifact, its configuration, the Challenge and
Solution sources, the topic manifest and each topic's own four files, the challenge-chain
files the closure tool hashes, `formalization.yaml`, the kernel-advisory override, the
caveat-table override, the characterization sidecar, and the registry records a cached
Palomar bundle holds. What comes out of those reads — a verdict, a date, statement text,
digests, blob links — is quoted into the `.olean` and decoded again at generation time.

None of them is a Lean module, so **Lake tracks none of these reads**. Editing one changes
no input Lake knows about, the module is not re-elaborated, and generation decodes the
previous capture and publishes it under the current build's revision. The snapshot stays
internally consistent while it does so — its links name the bytes displayed beside them —
which is exactly why nobody notices (CX-075).

This module is the record that makes that detectable: the path and SHA-256 of every such
file, carried on the payload beside the data derived from it, and re-checked against the
current bytes before anything is written (`Informal.TrustFreshness`).

Two things it is deliberately not:

- **Not a substitution barrier.** `checkComparatorDigests` compares the displayed bytes
  against the digests the *verifying run* recorded; that is the security boundary and it
  is unaffected. What is recorded here is what *this elaboration* read, so a stale capture
  and its files can be told apart. The two answer different questions.
- **Not a replacement for the Lake edge.** A build that re-elaborates when these files
  change never reaches the check (see the consumer recipe in `TrustFreshness`); the check
  is the backstop for the builds that do not.

Kept below `Commands.TrustStrip` — the payload carries `Input`s and the gate reads them
back out of raw traversal JSON, so neither side needs the rendering layer.
-/

namespace Informal.TrustInputs

open Lean

/-! ## Roles

The vocabulary a stop message names a file by. String-typed rather than an inductive so a
payload written by a later fork, naming a role this build has no phrase for, still
round-trips and still gets checked: the digest comparison does not depend on knowing what
the file is *for*.
-/

/-- Comparator status artifact (`verso.blueprint.trust.comparatorStatus`, or a topic's
`status`). -/
def roleStatus : String := "comparator-status"
/-- Comparator configuration JSON. -/
def roleConfig : String := "comparator-config"
/-- The Challenge Lean source displayed as "the claim". -/
def roleChallenge : String := "challenge"
/-- The Solution Lean source. -/
def roleSolution : String := "solution"
/-- A challenge-chain file elaborated before the primary Challenge, as the statement-closure
tool hashed it. -/
def roleChain : String := "challenge-chain"
/-- The multi-topic manifest (`verso.blueprint.trust.comparatorTopics`). -/
def roleTopics : String := "topics-manifest"
/-- The project's `formalization.yaml`. -/
def roleFormalization : String := "formalization-yaml"
/-- A consumer kernel-advisory table replacing the built-in one. -/
def roleAdvisories : String := "kernel-advisories"
/-- The consumer's characterization sidecar. -/
def roleCharacterizations : String := "characterizations"
/-- A consumer junk-value (caveat) table override. -/
def roleCaveatTable : String := "junk-value-table"
/-- The root of a cached Palomar bundle: the configured entry file, or the `recent.json` of
a configured directory. -/
def roleRegistryBundle : String := "palomar-bundle"
/-- One canonical Palomar record read from disk. -/
def roleRegistryRecord : String := "palomar-record"

/-- How a stop message names a file of this role. Unknown roles print the role string
itself, which is still more use than nothing. -/
def roleNoun (role : String) : String :=
  if role == roleStatus then "comparator status artifact"
  else if role == roleConfig then "comparator configuration"
  else if role == roleChallenge then "Challenge source"
  else if role == roleSolution then "Solution source"
  else if role == roleChain then "challenge-chain file"
  else if role == roleTopics then "comparator topic manifest"
  else if role == roleFormalization then "formalization.yaml"
  else if role == roleAdvisories then "kernel-advisory table"
  else if role == roleCharacterizations then "characterization sidecar"
  else if role == roleCaveatTable then "caveat table"
  else if role == roleRegistryBundle then "Palomar bundle"
  else if role == roleRegistryRecord then "Palomar record"
  else role

/-! ## Capture states

A configured path that was **not there** when the payload was captured is as much a fact
about the capture as one that was: some of these options are documented to degrade when
their file is missing (the comparator configuration, the Solution), and a repository may
legitimately configure a Solution it has not generated yet.

Recording only the files that existed is what CX-077 found: the path is absent from the
ledger, so it is absent from the recheck, so the file *appearing* later moves nothing this
gate can see — and a warm build then publishes a capture that a cold build refuses, because
the cold build would hash the new bytes against the digests the verdict recorded and stop.

So absence is recorded, as a state rather than as a missing row, and every transition is a
mismatch: absent→present, present→absent, present→changed.
-/

/-- The path held a file this build read, and `sha256` is over those bytes. This is the
state a record carries by saying nothing (`Input.state?` unset). -/
def statePresent : String := "present"

/-- The option named this path and there was no file there. `sha256` is empty — the only
state in which it legally is. -/
def stateAbsent : String := "absent"

/-! ## The record -/

/--
One non-Lean file a trust payload was elaborated from, or was configured to be.

`path` is the path exactly as the build resolved it — the configured option value, or the
path a manifest named — and therefore **revision-free**: it identifies a file in a working
tree, not a blob in a repository. It resolves against the build directory, the same way the
option that named it did, so the check re-reads what elaboration read as long as generation
runs from the same directory as the build (which is already required for the option paths
to mean anything).

`sha256` is over the bytes of that one read, and is empty exactly when `state` is `absent`.
-/
structure Input where
  role : String := ""
  path : String := ""
  /-- Lowercase hex, as `shasum -a 256` spells it. Empty exactly when this record is
  `absent`. -/
  sha256 : String := ""
  /-- `absent` (`stateAbsent`) when the capture found no file at this path. Unset is
  `present`: it is what every row of every payload written before this field existed meant,
  and — since the derived `ToJson` omits a `none` — it keeps those payloads byte-identical.
  An `Option` rather than a defaulted `String` deliberately: the derived `FromJson` fails on
  a *missing* non-optional field, which would make a legacy payload undecodable and
  therefore silently unchecked. -/
  state? : Option String := none
deriving Inhabited, BEq, Repr, FromJson, ToJson

/-- Whether this record says the path held a file at capture. -/
def Input.wasPresent (i : Input) : Bool := i.state? != some stateAbsent

/-- Read a file once as bytes: its SHA-256 and its decoded text.

One read, one digest — hashing the same bytes that become the displayed text is what makes
the digest a statement about what the page shows, rather than about a second read that
could differ from it. -/
def readWithDigest (path : String) : IO (String × String) := do
  let bytes ← IO.FS.readBinFile path
  match String.fromUTF8? bytes with
  | some decoded => pure (Informal.Sha256.hex bytes, decoded)
  | none =>
    throw <| IO.userError s!"{path} is not valid UTF-8, so this build cannot read it."

/-- The SHA-256 of a file's bytes.

Used where the caller already parsed the file through a loader of its own and needs only
the freshness anchor. That is a second read of the same path, which is a weaker guarantee
than `readWithDigest` gives — it anchors the *path* rather than the exact bytes the loader
saw — and it is used only for inputs whose loaders own their parsing (the caveat table,
the characterization sidecar, the registry records). -/
def digestOfFile (path : String) : IO String := do
  return Informal.Sha256.hex (← IO.FS.readBinFile path)

/-- An input record for a file whose bytes are already in hand. -/
def Input.ofDigest (role path sha256 : String) : Input := { role, path, sha256 }

/-- An input record for a configured path that held no file when the payload was captured.

There is nothing to hash, and that is the point: what is recorded is that this build looked
and found nothing, so a file appearing at that path afterwards is a change, not a state the
recheck has no opinion about (CX-077). -/
def Input.absent (role path : String) : Input :=
  { role, path, state? := some stateAbsent }

/-- An input record for a file read through somebody else's loader. Returns `none` when the
path is empty; propagates an IO error, since a file the build just read successfully has to
be readable a line later. -/
def Input.probe? (role path : String) : IO (Option Input) := do
  if path.isEmpty then return none
  return some { role, path, sha256 := ← digestOfFile path }

/-! ## Reading the records back out of a serialized payload

The gate runs below the rendering layer, so it walks the payload as raw JSON rather than
decoding `Commands.TrustData`. The walk is total: a payload with no `inputs` anywhere
yields nothing to check, which is what a consumer configuring no trust options should get.
-/

/-- One input, plus the comparator topic that named it (empty for a project-level input and
for the single-pair options). -/
abbrev Tagged := String × Input

private def inputsOf (topic : String) (j : Json) : Array Tagged :=
  match j.getObjVal? "inputs" with
  | .ok (.arr items) =>
    items.filterMap fun it =>
      match fromJson? (α := Input) it with
      | .ok input => if input.path.isEmpty then none else some (topic, input)
      | .error _ => none
  | _ => #[]

/--
Every input record a serialized trust payload carries: the project-level ones, the
single-pair comparator's, and each topic's, tagged with the topic name.

Order is the payload's, which is the order elaboration read them in; the stop message
therefore lists files in the order a reader would go looking for them.
-/
def ofPayload (payload : Json) : Array Tagged := Id.run do
  let mut out := inputsOf "" payload
  match payload.getObjVal? "comparator" with
  | .ok j => out := out ++ inputsOf "" j
  | .error _ => pure ()
  match payload.getObjVal? "comparators" with
  | .ok (.arr topics) =>
    for t in topics do
      let name := (t.getObjValAs? String "name").toOption.getD ""
      match t.getObjVal? "comparator" with
      | .ok j => out := out ++ inputsOf name j
      | .error _ => pure ()
  | _ => pure ()
  return out

/-! ## The check -/

/-- One input that is not now what the payload says it was. -/
structure Finding where
  topic : String := ""
  input : Input := {}
  /-- `changed` (readable, different bytes), `unreadable` (gone, or unreadable now),
  `appeared` (recorded absent, there now) or `unrecorded` (recorded present with no digest,
  so this build cannot tell). -/
  kind : String := ""
  /-- The current digest, or the IO error. -/
  detail : String := ""
deriving Inhabited, Repr

/-- Whether this finding is a file whose bytes moved (as opposed to one that vanished,
appeared, or was recorded without a digest). -/
def Finding.changed (f : Finding) : Bool := f.kind == "changed"

/--
Re-read every recorded input and report the ones that are not what the payload says.

Every transition is a finding, in both directions (CX-077):

- recorded present, readable, different bytes ⇒ `changed`;
- recorded present, not readable now ⇒ `unreadable`;
- recorded **absent**, a file there now ⇒ `appeared` — the case a ledger of only-existing
  files cannot see, and the one where a warm build would otherwise skip the content binding
  a cold build applies to the new bytes;
- recorded absent and still absent ⇒ nothing. That is the state the capture describes.

Total: an unreadable file is a finding, not an exception, so one missing file cannot hide
the other four.

A record that says `present` and carries no digest is itself a finding (`unrecorded`)
rather than being skipped. Nothing this fork writes produces one — every present record
comes from a read that hashed what it read, and a build that found nothing writes
`Input.absent` — so such a row is a payload this build cannot check, which is exactly what
the gate exists to refuse. (It was previously skipped, which is the half of CX-077 that
made an absent capture indistinguishable from an unhashed one.)
-/
def recheck (inputs : Array Tagged) : IO (Array Finding) := do
  let mut findings : Array Finding := #[]
  for (topic, input) in inputs do
    let current ←
      try
        pure (Except.ok (← digestOfFile input.path))
      catch e =>
        pure (Except.error (toString e))
    if !input.wasPresent then
      -- Recorded absent, so existence is the question — asked directly rather than inferred
      -- from a failed read, which would report a file that is there but unreadable as still
      -- missing. The digest, or the reason there is none, rides along so the stop message
      -- can name what turned up.
      let there ← try System.FilePath.pathExists input.path catch _ => pure false
      if there then
        findings := findings.push { topic, input, kind := "appeared"
                                    detail := match current with
                                              | .ok digest => digest
                                              | .error err => err }
      continue
    match current with
    | .error err =>
      findings := findings.push { topic, input, kind := "unreadable", detail := err }
    | .ok digest =>
      if input.sha256.isEmpty then
        findings := findings.push { topic, input, kind := "unrecorded", detail := digest }
      else
        unless Informal.Sha256.normalizeDigest digest
            == Informal.Sha256.normalizeDigest input.sha256 do
          findings := findings.push { topic, input, kind := "changed", detail := digest }
  return findings

/-- One finding as three lines of the stop message: which file, what it is, and what moved.

Assembled by intercalation rather than as one interpolated literal, because the leading
indentation is load-bearing (it is what makes a list of files scannable in a CI log) and a
string gap eats exactly that.

Public because there is more than one ledger: the trust payload's and the declaration
registry's (CX-062). They stop with different prose about different surfaces, and they
must name a file the same way. -/
def findingLine (f : Finding) : String :=
  let topicNote := if f.topic.isEmpty then "" else s!" [topic: {f.topic}]"
  let (was, now) :=
    if f.kind == "appeared" then
      ("not there when this payload was captured", s!"on disk now      {f.detail}")
    else if f.kind == "unrecorded" then
      ("recorded with no digest, so this build cannot tell what it was",
        s!"on disk now      {f.detail}")
    else if f.changed then
      (s!"elaborated from  {f.input.sha256}", s!"on disk now      {f.detail}")
    else (s!"elaborated from  {f.input.sha256}", s!"cannot be read now: {f.detail}")
  String.intercalate "\n" [
    s!"  {f.input.path} — {roleNoun f.input.role}{topicNote}",
    s!"      {was}",
    s!"      {now}"]

/--
The stop message: which files moved, why that is not recoverable at generation time, and
what to do about it.

Written to be actionable from a CI log with no other context — the reader is looking at a
build that failed after a green comparator run, and the thing they need to know first is
that the site was about to publish an *older* verdict than the one in their tree.
-/
def stopMessage (findings : Array Finding) (cwd : System.FilePath) : String :=
  let n := findings.size
  let noun := if n == 1 then "file" else "files"
  let lines := String.intercalate "\n" (findings.map findingLine).toList
  s!"Showcase comparator evidence check FAILED (stale capture): {n} {noun} the trust \
     payload describes {if n == 1 then "is" else "are"} not what it says — different bytes, \
     gone, or there when this build recorded nothing at that path.\n\n\
     {lines}\n\n\
     The comparator surfaces — the verdict, the statement, the recorded digests, the \
     repository links, the reproduce commands — are captured when the document module \
     elaborates. Those files are not Lean modules, so changing one — or creating one where \
     the capture found nothing — invalidates nothing Lake tracks, and this build was about \
     to re-serve the earlier capture under the current revision: the earlier verdict beside \
     the earlier statement, internally consistent and silently out of date. A file that has \
     appeared since the capture is the same failure read forward: the verdict's recorded \
     digests were never checked against those bytes, and a cold build would have done \
     that.\n\n\
     Re-elaborate the module carrying the `blueprint_dashboard` block so the payload is \
     read from the files above, then regenerate. `lake build <lib> -R` forces it; \
     declaring the files as Lake input files in the consumer's lakefile makes ordinary \
     builds do it (see the `VersoBlueprint.TrustFreshness` module docs).\n\n\
     Paths resolve against the build directory: {cwd}"

end Informal.TrustInputs
