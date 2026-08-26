/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import Lean

/-!
# Kernel advisories, and the currency of a recorded verifier

A verdict names the verifiers that produced it by revision. That pin is what makes the
verdict reproducible, and it is also what makes it age: a kernel pinned to a revision
from before a soundness fix is a second opinion from before the bug was known. In 2026
both halves of exactly that happened at once — a Lean kernel soundness bug, and a nanoda
build a week old with its own separate bug, agreeing on a false proof.

This module is the table that lets a page say so, and the pure function that reads it.

**The table is hand-maintained, and ages.** Nothing here queries anything: no network at
build time, no git ancestry at render time, no clock. It is a list of advisories an
author resolved by hand and wrote down, and its `advisoriesUpdated` date is the honest
bound on what it knows. A soundness fix published the day after that date is invisible
to every verdict this table assesses, which is why every surface that renders a verdict
from it also renders the self-aging clause. That clause is load-bearing, not decoration:
without it a `current` reading would be a claim about the world rather than a claim
about a list.

**Revisions are primary; dates only bound them** (CX-046). A date cannot establish that a
build contains a fix — a run in September may have been handed a checkout from July. So
`current` is reachable only when the run recorded an immutable revision that this table
*resolves* as fixed: membership in an author-checked allowlist, or the recorded ancestry
anchor itself, or (for version-numbered toolchains) a stable release at or above the
release that carries the fix. Everything else that is not positively affected is
`unknown` — neutral, and never green.

Dates run one way only. A build the run resolved *before* the fix existed cannot contain
it, so a record dated before an advisory whose fix evidence does not cover its revision
is `stale`. The converse is not available: a late run says nothing about how old its
checkout was.

**Ancestry is resolved at authoring time.** `fixedDescendantsOf` records a commit an
author checked, together with the statement that descendants of it carry the fix. This
module does not walk that ancestry — there is no git at render time — so the anchor
commit itself counts as fixed and any other commit is simply unresolved. The statement is
published so a reader can settle their own revision with one `git merge-base` call.
-/

namespace Informal.KernelAdvisories

open Lean

/-! ## The table -/

/--
What an author resolved, by hand, about which builds contain an advisory's fix.

Every field is evidence *for* a fix; the one field pointing the other way,
`affectedRevisions`, records revisions the author resolved as predating it. A revision
covered by neither is unresolved, which is a state this module reports rather than
guesses at.
-/
structure FixEvidence where
  /-- Revisions the author checked and found to carry the fix. Membership is proof. -/
  fixedRevisions : Array String := #[]
  /-- A commit the author resolved as carrying the fix, such that every descendant of it
  carries it too. Ancestry is **not** computed here: this commit counts as fixed, and any
  other commit is neither proven fixed nor proven affected by this field. -/
  fixedDescendantsOf : String := ""
  /-- The ancestry statement in words, published so a reader can settle a revision of
  their own. Empty ⇒ none recorded. -/
  ancestry : String := ""
  /-- For version-numbered tools: the lowest **stable** release carrying the fix. A
  stable release at or above it is fixed; a release below it is affected; a prerelease
  above it is a branch snapshot whose contents its number does not imply, so it is
  resolved only by `fixedRevisions`. -/
  fixedFromVersion : String := ""
  /-- Revisions the author resolved as predating the fix. Membership is proof of the
  loud state, independent of any date. -/
  affectedRevisions : Array String := #[]
deriving Inhabited, Repr, ToJson

/-- One hand-recorded advisory against one verifier. -/
structure Advisory where
  /-- Stable identifier, for tests and for a consumer override to replace an entry. -/
  id : String := ""
  /-- The tool this advisory is about, as the key a run's record uses: `lean4` for the
  toolchain the comparator ran on, otherwise the checker's canonical name. -/
  tool : String := ""
  /-- **The date from which a build can contain this advisory's fixes** — the release or
  the merge of the last repair in the series, not the day the defect was first
  whispered about. A revision a run resolved before this date cannot carry the fix, which
  is the one inference this module draws from a date. -/
  advisoryDate : String := ""
  summary : String := ""
  url : String := ""
  fix : FixEvidence := {}
deriving Inhabited, Repr, ToJson

/-- The advisory table: what this site knows, and when it last knew it. -/
structure Table where
  /-- When the table was last revised by hand. Every surface reading a verdict from this
  table also publishes this date, because a fix published after it is invisible here. -/
  advisoriesUpdated : String := ""
  advisories : Array Advisory := #[]
deriving Inhabited, Repr, ToJson

/-! ### Reading a consumer's table

Hand-written rather than derived, for the reason every external-artifact parser in this
fork is: a derived `FromJson` rejects an entry that omits a field it could have defaulted,
so a table written by hand would have to spell every key of every entry to load at all.
Absent fields therefore read as absent — which costs nothing, because absent evidence
proves nothing and the verdict lattice degrades to `unknown` rather than to green. No
malformed entry can manufacture a `current`.

Two things are structural and *are* errors: an `advisories` value that is not an array,
an entry naming no `tool` (it could never apply to anything), and a table that does not
date itself (the self-aging clause is the point of the surface).
-/

private def strField (j : Json) (k : String) : String :=
  (j.getObjValAs? String k).toOption.getD ""

private def strArrayField (j : Json) (k : String) : Array String :=
  match j.getObjVal? k with
  | .ok (.arr xs) => xs.filterMap fun x => match x with | .str s => some s | _ => none
  | _ => #[]

def FixEvidence.ofJson (j : Json) : FixEvidence where
  fixedRevisions := strArrayField j "fixedRevisions"
  fixedDescendantsOf := strField j "fixedDescendantsOf"
  ancestry := strField j "ancestry"
  fixedFromVersion := strField j "fixedFromVersion"
  affectedRevisions := strArrayField j "affectedRevisions"

def Advisory.ofJson? (j : Json) : Except String Advisory := do
  let tool := strField j "tool"
  if tool.isEmpty then
    throw "an advisory entry names no 'tool' (the key a run's record uses for the \
      verifier: 'lean4' for the toolchain, otherwise the checker's canonical name)"
  return {
    id := strField j "id"
    tool
    advisoryDate := strField j "advisoryDate"
    summary := strField j "summary"
    url := strField j "url"
    fix := match j.getObjVal? "fix" with
      | .ok f => FixEvidence.ofJson f
      | .error _ => {} }

def Table.ofJson? (j : Json) : Except String Table := do
  let updated := strField j "advisoriesUpdated"
  if updated.isEmpty then
    throw "the table records no 'advisoriesUpdated' date; without it nothing bounds what \
      the table knows, and every currency claim read from it would be unqualified"
  let entries ← match j.getObjVal? "advisories" with
    | .ok (.arr xs) => pure xs
    | .ok _ => throw "'advisories' is present but is not an array"
    | .error _ => throw "no 'advisories' array"
  let advisories ← entries.mapM Advisory.ofJson?
  return { advisoriesUpdated := updated, advisories }

/-! ## The seed table

Hand-maintained. Two entries, both resolved on 2026-08-25 against the upstream records
linked from each.
-/

/-- The advisories this fork ships. A consumer replaces the whole table with
`verso.blueprint.trust.kernelAdvisories`; there is no merge, because a partial override
of a safety table is a way to lose an entry silently. -/
def builtinTable : Table where
  advisoriesUpdated := "2026-08-25"
  advisories := #[
    { id := "lean4-v4.33.1"
      tool := "lean4"
      -- v4.33.1 was released on this date; the three kernel fixes are in it.
      advisoryDate := "2026-08-21"
      summary :=
        "Lean 4.33.1 is a kernel-soundness patch release: an is_def_eq union-find cache \
         that let definitional equality depend on the order the kernel was asked \
         (#14806), an is_prop implementation that let a non-proof field be projected out \
         of a proposition (#14807), and generated recursors accepted without checking \
         that their type and computation rules are type-correct (#14808)."
      url := "https://lean-lang.org/doc/reference/stable/releases/v4.33.1/"
      fix := {
        fixedFromVersion := "v4.33.1"
        -- The next release line's prereleases are branch snapshots, so their numbers do
        -- not imply their contents: rc2 is listed because it was checked, and rc1 is
        -- deliberately absent rather than inferred from ordering.
        fixedRevisions := #["v4.34.0-rc2"]
      } },
    { id := "nanoda-2026-08"
      tool := "nanoda"
      -- The last repair of the series (#28) merged on this date, so this — not the
      -- 2026-08-21 disclosure — is the date from which a nanoda build can be complete.
      advisoryDate := "2026-08-25"
      summary :=
        "nanoda carried the same class of defect the 2026-08-21 Lean release repaired — \
         is_def_eq and is_sort guards, and recursors accepted without being checked — \
         fixed across pull requests #22 to #28, the last of which merged on 2026-08-25."
      url := "https://github.com/ammkrn/nanoda_lib"
      fix := {
        fixedDescendantsOf := "05055695879dfebb6628a67da88ceca6cd6b0421"
        ancestry :=
          "Every nanoda revision descended from 05055695879dfebb6628a67da88ceca6cd6b0421 \
           (the merge of #28, 2026-08-25) carries the whole series. That was resolved by \
           hand; nothing here walks the history, so settle a revision of your own with \
           `git merge-base --is-ancestor 05055695879dfebb6628a67da88ceca6cd6b0421 <rev>`."
        fixedRevisions := #["05055695879dfebb6628a67da88ceca6cd6b0421"]
        -- Resolved by hand: this revision is the one a362583's 2026-08-04 CI run pinned,
        -- three weeks before the first repair of the series landed.
        affectedRevisions := #["f58f2f6d535e189a40fcb02ede8eb95f97a92d37"]
      } }
  ]

/-! ## Revisions -/

/-- A release version as its numeric components plus a prerelease tail (`rc2`, …). -/
structure Version where
  components : Array Nat := #[]
  prerelease : String := ""
deriving Inhabited, Repr, BEq

/-- The release version a toolchain string names: `leanprover/lean4:v4.33.1` ⇒
`4.33.1`, `v4.34.0-rc2` ⇒ `4.34.0-rc2`. `none` when the string is not a release version
at all — a nightly, a branch, a commit — which is a state the caller reports rather than
guesses past. -/
def parseVersion? (raw : String) : Option Version :=
  let s := raw.trimAscii.toString
  let s := ((s.splitOn ":").getLast?).getD s
  let s := if s.startsWith "v" then (s.drop 1).toString else s
  if s.isEmpty then none
  else
    let parts := s.splitOn "-"
    let base := parts.headD ""
    let prerelease := String.intercalate "-" (parts.drop 1)
    let comps := (base.splitOn ".").map String.toNat?
    if comps.isEmpty || comps.any Option.isNone then none
    else some { components := (comps.filterMap id).toArray, prerelease }

private def compareComponents (a b : Array Nat) : Ordering := Id.run do
  for i in [0 : max a.size b.size] do
    let x := a[i]?.getD 0
    let y := b[i]?.getD 0
    if x < y then return .lt
    if x > y then return .gt
  return .eq

/-- Release ordering, with the semver rule that a prerelease precedes the release it
leads to (`v4.33.1-rc1` < `v4.33.1` < `v4.34.0-rc2`). -/
def compareVersion (a b : Version) : Ordering :=
  match compareComponents a.components b.components with
  | .eq =>
    match a.prerelease.isEmpty, b.prerelease.isEmpty with
    | true, true => .eq
    | true, false => .gt
    | false, true => .lt
    | false, false => compare a.prerelease b.prerelease
  | o => o

/-- How a tool names its builds. -/
inductive RefKind where
  /-- A git revision: immutable when it looks like a hash, and matched by abbreviation. -/
  | commit
  /-- A release version, ordered against a recorded minimum. -/
  | version
deriving Inhabited, Repr, DecidableEq

/-- Whether a string is a git object name rather than a moving reference. Seven hex
digits is git's own abbreviation floor; `main`, `master` and a tag name all fail it. -/
def looksLikeCommit (s : String) : Bool :=
  let s := s.trimAscii.toString
  s.length ≥ 7 && s.all fun c =>
    c.isDigit || ('a' ≤ c.toLower && c.toLower ≤ 'f')

/-- Whether two recorded revisions name the same build. Commits match on
case-insensitive git abbreviation (one a prefix of the other, at least seven digits);
versions match on their parsed form, so `leanprover/lean4:v4.33.1` and `v4.33.1` are one
release. -/
def revisionMatches (kind : RefKind) (a b : String) : Bool :=
  let a := a.trimAscii.toString
  let b := b.trimAscii.toString
  match kind with
  | .version =>
    match parseVersion? a, parseVersion? b with
    | some x, some y => x == y
    | _, _ => a == b
  | .commit =>
    let x := a.toLower
    let y := b.toLower
    x == y || (x.length ≥ 7 && y.length ≥ 7 && (x.startsWith y || y.startsWith x))

/-! ## The verdict -/

/-- Currency of one recorded verifier build against the table. -/
inductive Verdict where
  /-- The run recorded an immutable revision the table resolves as carrying every fix it
  knows of for this tool. -/
  | current
  /-- The recorded revision provably predates a fix. The loud state. -/
  | stale
  /-- Nothing was established, in either direction. Neutral, never green. -/
  | unknown
deriving Inhabited, Repr, DecidableEq

def Verdict.name : Verdict → String
  | .current => "current"
  | .stale => "stale"
  | .unknown => "unknown"

instance : ToString Verdict := ⟨Verdict.name⟩

/-- What one verifier row is assessed from. Deliberately flat and free of any comparator
type: the assessment is pure, and the shape of a status artifact is the caller's problem.
-/
structure Input where
  /-- The table key: `lean4`, or the checker's canonical name. -/
  tool : String := ""
  /-- The revision the *run* recorded. Empty ⇒ nothing to assess. -/
  revision : String := ""
  kind : RefKind := .commit
  /-- Whether the record binds this revision to what actually ran (CX-064). A comparator
  configuration may point any label at any command, so a label with a revision typed
  beside it is not a build: `false` ⇒ `unknown`, whatever the revision says. -/
  identityAssessable : Bool := true
  /-- The date the record is *of* — `verified_at`, or an upstream report's own date.
  Empty ⇒ no date, which weakens the verdict rather than invalidating it. -/
  recordDate : String := ""
deriving Inhabited, Repr

/-- One advisory as it bears on one recorded revision. `state` is `fixed`, `affected` or
`unresolved`; `reason` names which rule decided it. -/
structure Outcome where
  advisory : Advisory := {}
  state : String := "unresolved"
  reason : String := ""
deriving Inhabited, Repr

/-- The assessment of one verifier row: the verdict, the rule that produced it, whether
the table is older than the record it judged, and every advisory that bore on it. -/
structure Assessment where
  verdict : Verdict := .unknown
  /-- Which rule decided: `revision-fixed`, `revision-affected`, `recorded-before-fix`,
  `unresolved`, `no-revision`, `symbolic-revision`, `incomparable-revision`,
  `identity-unbound`, `no-advisories`, `table-older-than-record`. -/
  reason : String := ""
  /-- Whether the record judged is newer than the table judging it. A `current` reading
  is impossible in this state: an advisory published in between would not appear here. -/
  tableStale : Bool := false
  outcomes : Array Outcome := #[]
deriving Inhabited, Repr

/-- The date part of an ISO-8601 timestamp. -/
def dateOnly (s : String) : String := (s.splitOn "T").headD s

/-- Whether the recorded revision names a build at all, as this tool names builds. -/
def revisionResolvable (kind : RefKind) (revision : String) : Bool :=
  match kind with
  | .commit => looksLikeCommit revision
  | .version => (parseVersion? revision).isSome

/-- How one advisory bears on one recorded revision.

Order matters and encodes the priority: what the author resolved by hand beats what the
version numbers imply, and both beat the dates. A date can only ever reach `affected`.
-/
def advisoryOutcome (adv : Advisory) (input : Input) : Outcome :=
  let rev := input.revision.trimAscii.toString
  let fix := adv.fix
  let listed (xs : Array String) := xs.any (revisionMatches input.kind rev ·)
  if listed fix.fixedRevisions then
    { advisory := adv, state := "fixed", reason := "allowlisted" }
  else if !fix.fixedDescendantsOf.isEmpty
      && revisionMatches input.kind rev fix.fixedDescendantsOf then
    { advisory := adv, state := "fixed", reason := "ancestry-anchor" }
  else if listed fix.affectedRevisions then
    { advisory := adv, state := "affected", reason := "known-affected" }
  else
    let byVersion : Option Outcome :=
      match input.kind, parseVersion? rev, parseVersion? fix.fixedFromVersion with
      | .version, some v, some min =>
        match compareVersion v min with
        | .lt => some { advisory := adv, state := "affected", reason := "below-fixed-version" }
        | _ =>
          -- At or above the fix, but a prerelease's number does not imply its contents.
          if v.prerelease.isEmpty then
            some { advisory := adv, state := "fixed", reason := "at-or-above-fixed-version" }
          else none
      | _, _, _ => none
    match byVersion with
    | some o => o
    | none =>
      -- The one inference a date supports: a build resolved before the fix existed does
      -- not contain it.
      let recorded := dateOnly input.recordDate
      if !recorded.isEmpty && !adv.advisoryDate.isEmpty && recorded < adv.advisoryDate then
        { advisory := adv, state := "affected", reason := "recorded-before-fix" }
      else
        { advisory := adv, state := "unresolved", reason := "no-evidence" }

/--
Currency of one recorded verifier build. Pure, total, and the single place the three-way
judgement is made.

`current` needs everything: an identity-bound, immutable revision, and an advisory table
that resolves it as fixed against every advisory it records for the tool — and a table at
least as new as the record it is judging. `stale` needs one advisory the revision
provably predates. Everything else is `unknown`, which is a statement about this site's
knowledge and not about the verifier.
-/
def currencyVerdict (table : Table) (input : Input) : Assessment :=
  let applicable := table.advisories.filter fun a => a.tool == input.tool
  let recorded := dateOnly input.recordDate
  let tableStale :=
    !recorded.isEmpty && !table.advisoriesUpdated.isEmpty
      && table.advisoriesUpdated < recorded
  let unassessed := applicable.map fun a =>
    ({ advisory := a, state := "unresolved", reason := "not-assessed" } : Outcome)
  let rev := input.revision.trimAscii.toString
  if applicable.isEmpty then
    { verdict := .unknown, reason := "no-advisories", tableStale }
  else if !input.identityAssessable then
    { verdict := .unknown, reason := "identity-unbound", tableStale, outcomes := unassessed }
  else if rev.isEmpty then
    { verdict := .unknown, reason := "no-revision", tableStale, outcomes := unassessed }
  else if !revisionResolvable input.kind rev then
    let reason := match input.kind with
      | .commit => "symbolic-revision"
      | .version => "incomparable-revision"
    { verdict := .unknown, reason, tableStale, outcomes := unassessed }
  else
    let outcomes := applicable.map (advisoryOutcome · input)
    if let some hit := outcomes.find? (·.state == "affected") then
      -- A proven staleness stands whatever the table's own age is.
      { verdict := .stale, reason := hit.reason, tableStale, outcomes }
    else if outcomes.all (·.state == "fixed") then
      if tableStale then
        { verdict := .unknown, reason := "table-older-than-record", tableStale, outcomes }
      else { verdict := .current, reason := "revision-fixed", tableStale, outcomes }
    else
      { verdict := .unknown, reason := "unresolved", tableStale, outcomes }

end Informal.KernelAdvisories
