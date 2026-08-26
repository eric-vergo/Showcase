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

/-! ## The record -/

/--
One non-Lean file a trust payload was elaborated from.

`path` is the path exactly as the build resolved it — the configured option value, or the
path a manifest named — and therefore **revision-free**: it identifies a file in a working
tree, not a blob in a repository. It resolves against the build directory, the same way the
option that named it did, so the check re-reads what elaboration read as long as generation
runs from the same directory as the build (which is already required for the option paths
to mean anything).

`sha256` is over the bytes of that one read.
-/
structure Input where
  role : String := ""
  path : String := ""
  /-- Lowercase hex, as `shasum -a 256` spells it. -/
  sha256 : String := ""
deriving Inhabited, BEq, Repr, FromJson, ToJson

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

/-- One input whose current bytes are not the bytes the payload was elaborated from. -/
structure Finding where
  topic : String := ""
  input : Input := {}
  /-- `changed` (readable, different bytes) or `unreadable` (gone, or unreadable now). -/
  kind : String := ""
  /-- The current digest, or the IO error. -/
  detail : String := ""
deriving Inhabited, Repr

/-- Whether this finding is a file whose bytes moved (as opposed to one that vanished). -/
def Finding.changed (f : Finding) : Bool := f.kind == "changed"

/--
Re-read every recorded input and report the ones that no longer hold the bytes the payload
was elaborated from.

Total: an unreadable file is a finding, not an exception, so one missing file cannot hide
the other four. An input recorded without a digest is skipped — a payload written by a
build that could not hash something has nothing to compare, and inventing a failure from
that would stop builds over a record's silence.
-/
def recheck (inputs : Array Tagged) : IO (Array Finding) := do
  let mut findings : Array Finding := #[]
  for (topic, input) in inputs do
    if input.sha256.isEmpty then continue
    let current ←
      try
        pure (Except.ok (← digestOfFile input.path))
      catch e =>
        pure (Except.error (toString e))
    match current with
    | .error err =>
      findings := findings.push { topic, input, kind := "unreadable", detail := err }
    | .ok digest =>
      unless Informal.Sha256.normalizeDigest digest
          == Informal.Sha256.normalizeDigest input.sha256 do
        findings := findings.push { topic, input, kind := "changed", detail := digest }
  return findings

/-- One finding as three lines of the stop message: which file, what it is, and what moved.

Assembled by intercalation rather than as one interpolated literal, because the leading
indentation is load-bearing (it is what makes a list of files scannable in a CI log) and a
string gap eats exactly that. -/
private def findingLine (f : Finding) : String :=
  let topicNote := if f.topic.isEmpty then "" else s!" [topic: {f.topic}]"
  String.intercalate "\n" [
    s!"  {f.input.path} — {roleNoun f.input.role}{topicNote}",
    s!"      elaborated from  {f.input.sha256}",
    if f.changed then s!"      on disk now      {f.detail}"
    else s!"      cannot be read now: {f.detail}"]

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
     payload was elaborated from {if n == 1 then "no longer holds" else "no longer hold"} \
     the bytes this build read.\n\n\
     {lines}\n\n\
     The comparator surfaces — the verdict, the statement, the recorded digests, the \
     repository links, the reproduce commands — are captured when the document module \
     elaborates. Those files are not Lean modules, so changing one invalidates nothing \
     Lake tracks, and this build was about to re-serve the earlier capture under the \
     current revision: the earlier verdict beside the earlier statement, internally \
     consistent and silently out of date.\n\n\
     Re-elaborate the module carrying the `blueprint_dashboard` block so the payload is \
     read from the files above, then regenerate. `lake build <lib> -R` forces it; \
     declaring the files as Lake input files in the consumer's lakefile makes ordinary \
     builds do it (see the `VersoBlueprint.TrustFreshness` module docs).\n\n\
     Paths resolve against the build directory: {cwd}"

end Informal.TrustInputs
