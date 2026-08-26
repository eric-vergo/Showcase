/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import Lean
import VersoBlueprint.Process
import VersoBlueprint.Sha256

/-!
# Palomar registry records

The Palomar registry publishes immutable snapshots of formalization results: a record is
written once, at one revision of one repository, and is never revisited. This module reads
those records so a site can say *that* a claim it presents was registered — and, much more
carefully, say nothing more than that.

**What may be read, and what may not.** The registry publishes an XML feed and a JSON
database. The feed carries a title, a link and a description; it carries no repository, no
commit and no digest, so nothing in it can identify what a record is *about*. It is
therefore not read here at all. The load-bearing input is the canonical record: an
`entries/<id>-v<version>.json` document under the registry's schema v3, which carries
`source.repository`/`source.commit` and `verification.challenge_sha256`. `recent.json` is a
bounded projection of those records; it is read only to find out which entry files a bundle
refers to, never as evidence of anything, because it does not carry the challenge digest a
claim-level match needs.

**What a match may conclude.** A registration binds to a claim only through the challenge
digest: the entry's `verification.challenge_sha256` must equal the digest of the challenge
bytes this page displays, *and* that digest must be one the verifying run recorded, so the
bytes are bound to the verdict as well as to the entry. Where the record also carries a
repository and the site knows its own, both must agree — a digest that matches under
another repository's name is not this project's registration. A repository match on its own
is project-level provenance and says nothing about the claim on the page.

**Which records may conclude it.** Only records the build can re-read. A record read from a
configured bundle is a file with a path and a digest, recorded as an input and re-checked
between traversal and emission (`Informal.TrustInputs`); a record the probe fetched is a
network response that no longer exists by the time the site is written, and a warm rebuild
replays it with nothing to compare against. So a probed record keeps whatever basis it
earned and is **never** claim-level: it may inform the project-level card and the
bundle-health surface, which are explicitly soft, and nothing else (CX-076). The rule lives
in `matchEntry?`, the one place a `Match` is built, so no caller can arrive at a claim-level
match another way.

Titles and abstracts are display text. `Entry` carries the title so a card can name the
record; no matching rule reads it, which is what keeps a record whose *title* contains this
repository's URL and this challenge's digest from matching anything.

**Honesty.** A registration is a record that something was submitted and accepted at a
moment in time. It is not a re-verification, and it is not an endorsement; `honestyNote`
is the sentence every surface built on this module prints.
-/

namespace Informal.Palomar

open Lean

/-- Schema version of the canonical Palomar record this build reads
(`https://data.palomar-registry.org/schema-v3.json`). A record written to another version
is not read: the fields this module matches on are exactly the ones a version change is
free to move. -/
def entrySchemaVersion : Nat := 3

/-- Schema version of the `recent.json` projection this build reads. -/
def recentSchemaVersion : Nat := 2

/-- The sentence every registry surface prints, whatever the match basis. -/
def honestyNote : String :=
  "Palomar entries are immutable snapshots, recorded once and never re-verified; \
   registration is provenance, not endorsement."

/-- The label a consumer-supplied permalink renders under. It is a link the site's author
pasted in; nothing about it was checked, and it is never a badge. -/
def consumerLinkNote : String :=
  "Registry link provided by this site's author (unverified)"

/-- Where the optional build-time probe reads from. Not an option: a consumer who wants a
different origin caches a bundle from it and configures that, which is the input this
module is willing to match on anyway. -/
def dataBaseUrl : String := "https://data.palomar-registry.org"

/-! ## The canonical record -/

/--
The part of a Palomar record this fork reads.

Deliberately narrow. Everything a match reads (`sourceRepository`, `sourceRepositoryUrl`,
`sourceCommit`, `challengeSha256`) is a field the registry's own schema constrains by
pattern; everything else here is display or an outbound link into data the record itself
published. There is no `abstract`, and `title` is never compared against anything.
-/
structure Entry where
  id : String := ""
  version : Nat := 0
  /-- When this version was registered (the record's `registered_at`). -/
  registeredAt : String := ""
  title : String := ""
  /-- `owner/repo`, as the record states it. -/
  sourceRepository : String := ""
  sourceRepositoryUrl : String := ""
  /-- The 40-hex revision the registration is of. -/
  sourceCommit : String := ""
  /-- Commit-pinned tree URL of the registered project directory. -/
  sourceTreeUrl : String := ""
  /-- Repository-root-relative path of the registered Lean project; empty ⇒ the root. -/
  projectPath : String := ""
  /-- SHA-256 of the challenge the registry verified. The only field a claim-level match
  binds on. -/
  challengeSha256 : String := ""
  solutionSha256 : String := ""
  /-- When the registry's own verification ran. -/
  verifiedAt : String := ""
  /-- The registry's submission workflow run. -/
  workflowUrl : String := ""
  theoremNames : Array String := #[]
  /-- Where these bytes were read from — a path in a cached bundle, or a URL the probe
  fetched. -/
  origin : String := ""
deriving Inhabited, Repr, BEq

/-- `id`-`v`-`version`, the way the registry names one record. -/
def Entry.label (e : Entry) : String := s!"{e.id}-v{e.version}"

/-! ### Where a record's bytes came from

`origin` is a path when a bundle held the record and a URL when the probe fetched it, and
the difference is not bookkeeping. A path can be re-read and digested as an input of this
build, so a later build can tell whether the bytes that decided a match are still the bytes
on disk; a network response cannot be, and a warm rebuild replays it silently.

Everything that turns on that distinction — the match rule below, the input ledger the
freshness gate re-reads, and the copy on the card — routes through these two predicates, so
the three cannot drift apart about which records are which.
-/

/-- Whether these bytes were fetched over the network while the build ran. -/
def isProbeOrigin (origin : String) : Bool :=
  origin.startsWith "https://" || origin.startsWith "http://"

/-- Whether these bytes came from a file this build can name, re-read and digest. An empty
origin is not one: a record that cannot say where it came from is not an input either. -/
def isCachedOrigin (origin : String) : Bool :=
  !origin.isEmpty && !isProbeOrigin origin

/-- Whether this record's bytes are a re-readable input of this build (`isCachedOrigin`),
which is the precondition for its match being claim-level. -/
def Entry.fromCachedInput (e : Entry) : Bool := isCachedOrigin e.origin

/-! ### Structural checks

A subset check derived from the registry's schema v3, not a general validator: it
establishes the shape of the fields this module reads and says nothing about the rest of
the document.
-/

private def isDigits (n : Nat) (s : String) : Bool :=
  s.length == n && s.toList.all Char.isDigit

private def isLowerHex (n : Nat) (s : String) : Bool :=
  s.length == n && s.toList.all fun c =>
    ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

/-- `PALOMAR-YYYY-MM-DD-NNNNNN`, the registry's identifier shape. -/
def isEntryId (s : String) : Bool :=
  match s.splitOn "-" with
  | ["PALOMAR", y, m, d, n] => isDigits 4 y && isDigits 2 m && isDigits 2 d && isDigits 6 n
  | _ => false

private def isSlugChar (c : Char) : Bool :=
  c.isAlphanum || c == '_' || c == '.' || c == '-'

/-- `owner/repo`, the registry's repository shape. -/
def isRepoSlug (s : String) : Bool :=
  match s.splitOn "/" with
  | [owner, repo] =>
    !owner.isEmpty && !repo.isEmpty && owner.toList.all isSlugChar && repo.toList.all isSlugChar
  | _ => false

private def objField? (j : Json) (key : String) : Option Json := (j.getObjVal? key).toOption

private def requireObj (origin : String) (j : Json) (key : String) : Except String Json :=
  match objField? j key with
  | some (v@(.obj _)) => .ok v
  | some _ => .error s!"{origin}: '{key}' is not an object"
  | none => .error s!"{origin}: '{key}' is missing"

private def requireStr (origin : String) (j : Json) (key : String) : Except String String :=
  match objField? j key with
  | some (.str s) =>
    if s.trimAscii.toString.isEmpty then .error s!"{origin}: '{key}' is empty"
    else .ok s
  | some _ => .error s!"{origin}: '{key}' is not a string"
  | none => .error s!"{origin}: '{key}' is missing"

private def optStr (j : Json) (key : String) : String :=
  match objField? j key with
  | some (.str s) => s
  | _ => ""

private def optStrArray (j : Json) (key : String) : Array String :=
  match objField? j key with
  | some (.arr items) => items.filterMap fun i => match i with
    | .str s => some s
    | _ => none
  | _ => #[]

private def requireNat (origin : String) (j : Json) (key : String) : Except String Nat :=
  match (j.getObjValAs? Nat key).toOption with
  | some n => .ok n
  | none => .error s!"{origin}: '{key}' is missing or is not a non-negative integer"

/--
Read one canonical record, refusing every shape this module's matching rules assume.

`origin` names the bytes for the error message and is recorded on the entry, so a card can
say where its identity evidence came from.
-/
def Entry.ofJson? (origin : String) (j : Json) : Except String Entry := do
  let schema ← requireNat origin j "schema_version"
  if schema != entrySchemaVersion then
    .error s!"{origin}: schema version {schema}; this build reads Palomar records of version \
      {entrySchemaVersion}"
  let id ← requireStr origin j "id"
  unless isEntryId id do
    .error s!"{origin}: '{id}' is not a Palomar identifier"
  let version ← requireNat origin j "version"
  if version == 0 then
    .error s!"{origin}: 'version' is 0; registry versions start at 1"
  let status ← requireStr origin j "status"
  unless status == "registered" do
    .error s!"{origin}: status is '{status}'; only a registered record is a registration"
  let title ← requireStr origin j "title"
  let registeredAt ← requireStr origin j "registered_at"
  let source ← requireObj origin j "source"
  let sourceOrigin := s!"{origin}: source"
  let sourceRepository ← requireStr sourceOrigin source "repository"
  unless isRepoSlug sourceRepository do
    .error s!"{sourceOrigin}: 'repository' is not an owner/repo pair"
  let sourceRepositoryUrl ← requireStr sourceOrigin source "repository_url"
  unless sourceRepositoryUrl.startsWith "https://github.com/" do
    .error s!"{sourceOrigin}: 'repository_url' is not a GitHub URL"
  let sourceCommit ← requireStr sourceOrigin source "commit"
  unless isLowerHex 40 sourceCommit do
    .error s!"{sourceOrigin}: 'commit' is not a 40-character revision"
  let verification ← requireObj origin j "verification"
  let verificationOrigin := s!"{origin}: verification"
  let challengeSha256 ← requireStr verificationOrigin verification "challenge_sha256"
  unless isLowerHex 64 challengeSha256 do
    .error s!"{verificationOrigin}: 'challenge_sha256' is not a SHA-256 digest"
  let formalization := (objField? j "formalization").getD Json.null
  return {
    id, version, registeredAt, title
    sourceRepository, sourceRepositoryUrl, sourceCommit
    sourceTreeUrl := optStr source "tree_url"
    projectPath := optStr source "project_path"
    challengeSha256
    solutionSha256 := optStr verification "solution_sha256"
    verifiedAt := optStr verification "verified_at"
    workflowUrl := optStr verification "workflow_url"
    theoremNames := optStrArray formalization "theorem_names"
    origin
  }

/-! ## `recent.json`, and what it is for

The projection carries no challenge digest, so it can establish nothing. What it can do is
say which entry files a bundle contains — which is the only use it is put to here.
-/

/-- One row of `recent.json`: an identifier, and the entry file that holds the record. -/
structure RecentRow where
  id : String := ""
  version : Nat := 0
  /-- `entries/<id>-v<version>.json`, relative to the bundle root. -/
  path : String := ""
  /-- The row's `source.repository`, used only to decide which entry files the *probe*
  bothers to fetch. Never a match key: the record it points at is. -/
  repository : String := ""
deriving Inhabited, Repr, BEq

/-- Parse a `recent.json` projection, refusing a document whose rows do not name their own
entry files: a row pointing somewhere else is a bundle asking this build to read a record
under an identifier that is not its own. -/
def parseRecent? (origin : String) (j : Json) : Except String (Array RecentRow) := do
  let schema ← requireNat origin j "schema_version"
  if schema != recentSchemaVersion then
    .error s!"{origin}: schema version {schema}; this build reads recent.json of version \
      {recentSchemaVersion}"
  let entries ← match objField? j "entries" with
    | some (.arr items) => pure items
    | _ => .error s!"{origin}: 'entries' is missing or is not an array"
  let mut rows : Array RecentRow := #[]
  for (row, i) in entries.zipIdx do
    let rowOrigin := s!"{origin}: entries[{i}]"
    let id ← requireStr rowOrigin row "id"
    unless isEntryId id do
      .error s!"{rowOrigin}: '{id}' is not a Palomar identifier"
    let version ← requireNat rowOrigin row "version"
    let path ← requireStr rowOrigin row "path"
    let expected := s!"entries/{id}-v{version}.json"
    unless path == expected do
      .error s!"{rowOrigin}: path '{path}' does not name its own entry ({expected})"
    let repository := match objField? row "source" with
      | some src => optStr src "repository"
      | none => ""
    rows := rows.push { id, version, path, repository }
  return rows

/-! ## Bundles -/

/--
A projection row whose record this build could not read.

The identity is kept apart from the reason because the surfaces that report this have to
*name* the record: "a row was skipped" and "PALOMAR-2026-08-06-000006-v1 was skipped" are
different things to publish, and only the second lets a reader go and look.
-/
structure Unresolved where
  /-- `id`-`v`-`version`, the way the registry names one record. -/
  label : String := ""
  /-- Why this build could not read it: missing, malformed, or not the record it names. -/
  reason : String := ""
  /-- Which input the row came from: `cache` or `probe`. -/
  source : String := ""
deriving Inhabited, Repr, BEq

/-- The one-line form: which record, and what went wrong reading it. -/
def Unresolved.line (u : Unresolved) : String := s!"{u.label}: {u.reason}"

/--
The records a build has to match against, and where they came from.

`unresolved` is the honest half: a projection row whose record this build could not read is
not a record, and cannot match anything. It is counted and named rather than dropped,
because "nothing matched" and "the thing that would have matched was unreadable" are
different states.
-/
structure Bundle where
  /-- `cache` (a configured bundle on disk), `probe` (fetched during this build), or
  `cache+probe` (both, unioned by `Bundle.union`). -/
  source : String := ""
  /-- The directory, file or base URL the records came from. -/
  location : String := ""
  /-- For a `cache+probe` bundle, the base URL the probed records came from; `location` is
  then the configured bundle's. Empty ⇒ this bundle has a single source. -/
  probedFrom : String := ""
  entries : Array Entry := #[]
  /-- Projection rows whose record could not be read, each with the reason. -/
  unresolved : Array Unresolved := #[]
deriving Inhabited, Repr

/-- One line saying what this build matched against, for the card's provenance. -/
def Bundle.provenance (b : Bundle) : String :=
  let what :=
    if b.source == "probe" then s!"fetched from {b.location} during this build"
    else if b.source == "cache+probe" then
      s!"read from the cached bundle at {b.location}, together with the records fetched from \
         {b.probedFrom} during this build"
    else s!"read from the cached bundle at {b.location}"
  let n := b.entries.size
  let recordNoun := if n == 1 then "record" else "records"
  let unresolvedClause :=
    if b.unresolved.isEmpty then ""
    else
      let u := b.unresolved.size
      s!"; {u} further {if u == 1 then "row" else "rows"} named a record this build could not \
         read, and {if u == 1 then "it was" else "they were"} not considered"
  s!"{n} registry {recordNoun} {what}{unresolvedClause}"

/-- Whether two records are the same document: every field the registry publishes, ignoring
only where this build happened to read the bytes from. -/
def Entry.sameRecord (a b : Entry) : Bool :=
  { a with origin := "" } == { b with origin := "" }

/--
The records of a configured bundle and of a probe, as one set.

Unioning rather than replacing is what keeps the probe soft in the direction that matters. A
probe reads a bounded recent projection, filtered by repository and capped, so it
legitimately comes back without a record the configured bundle holds; letting a non-empty
probe stand in for the cache would delete evidence the build was configured with, on the
strength of what the registry happened to have listed recently.

A registry record is immutable and `id`-`v`-`version` names exactly one document, so two
sources holding that name must hold the same bytes. Agreement deduplicates to the configured
copy. Disagreement is not a merge to settle by preferring a side — one of the two is then not
the record it says it is — so it fails closed, naming both origins.
-/
def Bundle.union (cache probe : Bundle) : Except String Bundle := Id.run do
  let mut entries := cache.entries
  let mut conflicts : Array String := #[]
  for p in probe.entries do
    match entries.find? (fun c => c.id == p.id && c.version == p.version) with
    | some c =>
      unless Entry.sameRecord c p do
        conflicts := conflicts.push
          s!"{p.label}: {c.origin} and {p.origin} hold different bytes"
    | none => entries := entries.push p
  unless conflicts.isEmpty do
    return .error s!"the configured Palomar bundle and the probe disagree about a record that \
      cannot change, so one of them is not the record it names: \
      {String.intercalate "; " conflicts.toList}"
  return .ok { cache with
    source := "cache+probe"
    probedFrom := probe.location
    entries
    unresolved := cache.unresolved ++ probe.unresolved }

private def readFileOr (path : String) : IO (Except String String) := do
  try
    return .ok (← IO.FS.readFile path)
  catch e =>
    return .error s!"could not read {path}: {e}"

/-- Read one canonical record from a file. -/
def loadEntryFile (path : String) : IO (Except String Entry) := do
  match ← readFileOr path with
  | .error e => return .error e
  | .ok raw =>
    match Json.parse raw with
    | .error err => return .error s!"could not parse {path}: {err}"
    | .ok j => return Entry.ofJson? path j

/--
Load a cached bundle: either a directory holding `recent.json` plus the `entries/` files it
names, or a single immutable entry JSON.

The two forms fail differently, and deliberately. A single configured entry file *is* the
contract, so a malformed one is an error the consumer has to fix. In a directory, the
contract is `recent.json`; an individual record that is missing or written to a schema this
build does not read is recorded as unresolved and skipped, because a bundle fetched from a
live registry legitimately contains records this build has no rules for, and bricking every
build over one of them would be worse than saying so.
-/
def loadBundle (path : String) : IO (Except String Bundle) := do
  let fsPath : System.FilePath := path
  unless ← fsPath.pathExists do
    return .error s!"names a missing path (resolved against the build directory): {path}"
  let isDir ← try fsPath.isDir catch _ => pure false
  if !isDir then
    match ← loadEntryFile path with
    | .error e => return .error e
    | .ok entry => return .ok { source := "cache", location := path, entries := #[entry] }
  let recentPath := (fsPath / "recent.json").toString
  unless ← System.FilePath.pathExists recentPath do
    return .error s!"names a directory with no recent.json: {path}. A bundle directory is the \
      registry's recent.json together with the entries/ files it names."
  let raw ← match ← readFileOr recentPath with
    | .error e => return .error e
    | .ok raw => pure raw
  let j ← match Json.parse raw with
    | .error err => return .error s!"could not parse {recentPath}: {err}"
    | .ok j => pure j
  let rows ← match parseRecent? recentPath j with
    | .error e => return .error e
    | .ok rows => pure rows
  let mut entries : Array Entry := #[]
  let mut unresolved : Array Unresolved := #[]
  for row in rows do
    let entryPath := (fsPath / row.path).toString
    let label := s!"{row.id}-v{row.version}"
    let skip (reason : String) : Unresolved := { label, reason, source := "cache" }
    unless ← System.FilePath.pathExists entryPath do
      unresolved := unresolved.push (skip s!"{row.path} is not in this bundle")
      continue
    match ← loadEntryFile entryPath with
    | .error e => unresolved := unresolved.push (skip e)
    | .ok entry =>
      if entry.id != row.id || entry.version != row.version then
        unresolved := unresolved.push
          (skip s!"{row.path} holds {entry.label}, which is a different record")
      else
        entries := entries.push entry
  return .ok { source := "cache", location := path, entries, unresolved }

/-! ## Repository canonicalization

Two spellings of one repository have to compare equal, and two repositories must not. The
rule: drop the transport (scheme, `git@`, a trailing `.git`, a trailing slash, a leading
`www.`), keep host and the first two path segments, lower-case the host always and the path
only for `github.com`, whose owner and repository names are case-insensitive. A bare
`owner/repo` is read as GitHub's, which is what the registry's own records mean by it.

Nothing else is normalized. A path on a host whose case might matter keeps its case, and a
string that does not look like a repository at all comes back empty rather than being
coerced into one.
-/

/-- Canonical form for repository comparison; empty when the input names no repository. -/
def canonicalRepo (s : String) : String := Id.run do
  let mut t := s.trimAscii.toString
  if t.isEmpty then return ""
  -- Transport prefixes, including the `scp`-style `git@host:owner/repo`.
  for p in ["git+", "https://", "http://", "ssh://", "git://"] do
    if t.startsWith p then t := (t.drop p.length).toString
  if t.startsWith "git@" then
    t := (t.drop 4).toString
    t := String.intercalate "/" (t.splitOn ":")
  while t.endsWith "/" do t := (t.dropEnd 1).toString
  if t.endsWith ".git" then t := (t.dropEnd 4).toString
  let parts := (t.splitOn "/").filter (fun p => !p.isEmpty)
  let (host, path) :=
    match parts with
    | [] => ("", ([] : List String))
    | first :: rest =>
      -- A first segment with a dot is a host; otherwise the string is a bare owner/repo,
      -- which the registry writes for GitHub.
      if (first.splitOn ".").length > 1 && !rest.isEmpty then (first.toLower, rest)
      else ("github.com", parts)
  let host := if host == "www.github.com" then "github.com" else host
  if path.length < 2 then return ""
  let path := path.take 2
  let path := if host == "github.com" then path.map String.toLower else path
  return String.intercalate "/" (host :: path)

/-! ## Path comparison

A record names the project directory it registered; a verdict names files it was produced
from. Both are repository-root-relative, and both are canonicalized the way repositories
are — separators normalized, `./` dropped, empty segments dropped — before anything is
compared, so `comparator`, `./comparator/` and `comparator//` are one directory and
`comparators` is not.
-/

/-- Path components, canonicalized for comparison. -/
private def pathComponents (p : String) : List String :=
  ((p.replace "\\" "/").splitOn "/").filter fun s => s != "." && !s.isEmpty

/-- Whether `projectPath` is the directory `candidate` lies in, or an ancestor of it.

An empty project path is the repository root and contains every path. Comparison is on
whole components, so a registered `comparator` directory does not contain
`comparators/Challenge.lean`. -/
def projectPathContains (projectPath candidate : String) : Bool :=
  let proj := pathComponents projectPath
  let cand := pathComponents candidate
  proj.length ≤ cand.length && proj == cand.take proj.length

/-- Whether two recorded revisions name the same commit, allowing for abbreviation: git
writes both `05055695` and its 40-character expansion for one object, so one being a prefix
of the other is agreement. Below seven characters nothing is compared — that is not a
revision. -/
def revisionsAgree (a b : String) : Bool :=
  let a := a.trimAscii.toString.toLower
  let b := b.trimAscii.toString.toLower
  if a.length < 7 || b.length < 7 then false
  else if a.length ≤ b.length then b.startsWith a else a.startsWith b

/-! ## Matching -/

/--
What this site knows about the claim a record might be bound to.

`digestStatusBound` is the field that decides whether a digest agreement is worth anything:
the challenge bytes this page displays are bound to the verdict only when the verifying run
recorded their digest. Where it did not, an agreeing registration is a registration of the
same bytes under no verdict in particular, which is provenance and not a claim-level match.

`statusSuccess`, `sourceCommit` and `projectPaths` are the rest of the identity a
claim-level match binds on (CX-065). A registration cannot record "the challenge this
verdict certifies" when the verdict has not run; and a registration of a different revision
of the project, or of a directory the verdict's own files do not lie in, is a registration
of something else that happens to share a digest.
-/
structure ClaimIdentity where
  /-- SHA-256 of the challenge bytes this page displays. Empty ⇒ none read. -/
  displayedDigest : String := ""
  /-- Whether the verifying run recorded that digest. -/
  digestStatusBound : Bool := false
  /-- Whether the verdict is a comparator success. A `configured`, failed or transcribed
  verdict certifies nothing here, so no record may be presented as recording what it
  certifies. -/
  statusSuccess : Bool := false
  /-- The project's repository, as the run recorded it or as this checkout says. Empty ⇒
  unknown, which is not the same as "does not match". -/
  repo : String := ""
  /-- The subject revision the verifying run checked out. Empty ⇒ unrecorded. -/
  sourceCommit : String := ""
  /-- Repository-root-relative paths the verdict names — the configuration CI was passed and
  the challenge chain the run recorded. Empty ⇒ the record names none, and there is nothing
  to compare a registered directory against. -/
  projectPaths : Array String := #[]
deriving Inhabited, Repr

/-- A record matched against a claim, and on what. -/
structure Match where
  entry : Entry := {}
  /-- `repo+digest`, `digest`, `digest-not-verified`, `digest-unbound`,
  `digest-identity-mismatch`, `repo-only`. -/
  basis : String := ""
  /-- Whether this match binds the record to the claim on the page. Three things are needed:
  a digest the verdict recorded, a verdict that is a success, and a record this build can
  re-read (`Entry.fromCachedInput`). Anything less keeps the basis it earned and comes back
  project-level. -/
  claimLevel : Bool := false
  /-- What disagreed, or what was missing, in the register the page will use. Empty when
  nothing did. -/
  note : String := ""
deriving Inhabited, Repr

/-- The bases a claim-level match can rest on, named once so no surface has to re-derive the
rule. Necessary and not sufficient: a record on one of these bases that this build fetched
over the network is still project-level (`matchEntry?`, CX-076). -/
def claimLevelBases : List String := ["repo+digest", "digest"]

/-- The digest agreed and the verdict recorded it, but the verdict is not a success: there
is no certified claim for the registration to be about (CX-065). -/
def basisNotVerified : String := "digest-not-verified"

/-- The digest agreed and the verdict recorded it, but the record's own source identity —
its revision, or the project directory it registered — disagrees with the verdict's. Two
records of the same bytes under different provenance are not one claim. -/
def basisIdentityMismatch : String := "digest-identity-mismatch"

/--
Match one record against one claim.

Six rules, in the order they bite:

1. **Both when present, on the repository.** A record that names a repository, matched
   against a site that knows its own, must agree with it. A digest that matches under
   another repository's name is not this project's registration, whatever else it agrees
   about. This one rejects outright, because a different repository is a different project.
2. **A claim-level match needs a status-bound digest.** The record's immutable
   `challenge_sha256` must equal the digest of the displayed challenge, and the verdict
   must have recorded that digest too.
3. **Both when present, on the rest of the source identity.** The record's revision and the
   revision the verifying run checked out must agree where both are recorded; the directory
   the record registered must contain the files the verdict names, where it names any.
   Disagreement does not reject the record — the digest agreement is real and worth printing
   — it takes the match down to `basisIdentityMismatch`, where the page says what disagreed
   (CX-065).
4. **A claim-level match needs a verdict that certifies something.** A `configured`,
   failed or transcribed verdict has certified nothing, so no record may be shown as
   recording the challenge it certifies. That is `basisNotVerified`.
5. **A claim-level match needs a record this build can re-read.** A probed record is a
   network response with no file behind it: it is excluded from the input ledger the
   freshness gate re-hashes, so a warm rebuild would keep its badge with the probe long
   gone and nothing able to notice. It keeps the basis it earned — the digest really did
   agree — and comes back project-level, which is the tier that is soft in as many words
   (CX-076).
6. **Everything weaker is project-level.** An agreeing digest the verdict does not bind, or
   a repository match with no digest to compare, is provenance about the project — never
   about the claim on the page.

Rules 3-5 are here rather than at the selection layer because this is the only place a
`Match` is constructed: `selectMatch?` ranks what this returns, and a caller reaching past
it gets the same answer.
-/
def matchEntry? (claim : ClaimIdentity) (e : Entry) : Option Match :=
  let entryRepo :=
    canonicalRepo (if e.sourceRepositoryUrl.isEmpty then e.sourceRepository else e.sourceRepositoryUrl)
  let claimRepo := canonicalRepo claim.repo
  let repoComparable := !entryRepo.isEmpty && !claimRepo.isEmpty
  let repoAgrees := repoComparable && entryRepo == claimRepo
  let entryDigest := Informal.Sha256.normalizeDigest e.challengeSha256
  let claimDigest := Informal.Sha256.normalizeDigest claim.displayedDigest
  let digestAgrees := !entryDigest.isEmpty && !claimDigest.isEmpty && entryDigest == claimDigest
  let commitDisagrees :=
    !e.sourceCommit.trimAscii.isEmpty && !claim.sourceCommit.trimAscii.isEmpty
      && !revisionsAgree e.sourceCommit claim.sourceCommit
  let pathDisagrees :=
    !e.projectPath.trimAscii.isEmpty && !claim.projectPaths.isEmpty
      && !claim.projectPaths.any (projectPathContains e.projectPath ·)
  let identityNote :=
    if commitDisagrees && pathDisagrees then
      s!"the record registers {e.sourceCommit} and the directory {e.projectPath}; the \
         verifying run recorded {claim.sourceCommit} and files outside it"
    else if commitDisagrees then
      s!"the record registers revision {e.sourceCommit}; the verifying run recorded \
         {claim.sourceCommit}"
    else
      s!"the record registers the directory {e.projectPath}; none of the files the verifying \
         run recorded lies in it"
  if repoComparable && !repoAgrees then none
  else if digestAgrees && claim.digestStatusBound && (commitDisagrees || pathDisagrees) then
    some { entry := e, basis := basisIdentityMismatch, note := identityNote }
  else if digestAgrees && claim.digestStatusBound && !claim.statusSuccess then
    some { entry := e, basis := basisNotVerified }
  else if digestAgrees && claim.digestStatusBound then
    some { entry := e, basis := if repoAgrees then "repo+digest" else "digest"
           claimLevel := e.fromCachedInput }
  else if digestAgrees then
    some { entry := e, basis := "digest-unbound" }
  else if repoAgrees then
    some { entry := e, basis := "repo-only" }
  else none

private def basisRank : String → Nat
  | "repo+digest" => 6
  | "digest" => 5
  | "digest-not-verified" => 4
  | "digest-unbound" => 3
  | "digest-identity-mismatch" => 2
  | "repo-only" => 1
  | _ => 0

/-- Whether `a` is the better of two matches: bound before unbound, then the stronger
basis, then the later record. Total and deterministic, so two builds of one tree select the
same registration. -/
private def betterMatch (a b : Match) : Bool :=
  if a.claimLevel != b.claimLevel then a.claimLevel
  else if basisRank a.basis != basisRank b.basis then basisRank a.basis > basisRank b.basis
  else if a.entry.id != b.entry.id then a.entry.id > b.entry.id
  else a.entry.version > b.entry.version

/-- The best match a bundle offers for one claim, or `none`.

A bundle with no match renders nothing at all: it is a bounded projection of a registry, so
its silence about a project is not evidence that the registry is silent too.

Claim level is decided in `matchEntry?` and only ranked here, so a bundle holding both a
cached record and a probed one on the same basis selects the cached one — which is the only
one a claim may rest on. -/
def selectMatch? (claim : ClaimIdentity) (entries : Array Entry) : Option Match :=
  entries.foldl (init := none) fun best e =>
    match matchEntry? claim e with
    | none => best
    | some m =>
      match best with
      | none => some m
      | some b => if betterMatch m b then some m else some b

/-! ## The optional probe

Always soft, and never load-bearing: it fetches the same canonical records a cached bundle
holds, and every failure — no `curl`, no network, an unreadable document — degrades to the
cached bundle or to nothing at all. A build with no network still renders; it renders
without the registry surface, which is what "no evidence" looks like here.

Soft also in the other direction, which is the direction that is easy to get wrong: what a
probe returns is *added* to the configured records by `Bundle.union`, never substituted for
them. This projection is capped and filtered by repository, so it comes back without records
a cached bundle holds as a matter of course, and a build that let it stand in for the cache
would publish or suppress configured evidence according to what the registry listed today.

The projection is used to *choose* which records to fetch (rows naming this project's
repository, capped), not to match: the record fetched is what a match reads.

And soft in the third direction, the one CX-076 found open: whatever a probed record agrees
with, it is never bound to a claim. `matchEntry?` returns it project-level, because the
bytes it agreed on are gone by the time the site is written and no later build can check
that they were ever there.
-/

/-- How many entry files one probe will fetch. A bounded projection with a bounded number
of candidates keeps the build's network use proportional to the site, not to the registry. -/
def probeMaxEntries : Nat := 8

private def curlText? (url : String) : IO (Option String) :=
  Informal.Process.runTrimmedCommand? "curl"
    #["-fsSL", "--max-time", "20", "--retry", "1", url]

/--
Fetch the records for `repo` from the registry's data host.

`none` when there is nothing to say: the projection could not be fetched or read, or the
site does not know its own repository (with no candidate rows to select, a probe that
fetched the whole registry would be doing something else).
-/
def probe (repo : String) (baseUrl : String := dataBaseUrl)
    (maxEntries : Nat := probeMaxEntries) : IO (Option Bundle) := do
  if (canonicalRepo repo).isEmpty then return none
  let recentUrl := s!"{baseUrl}/recent.json"
  let some raw ← curlText? recentUrl | return none
  let .ok j := Json.parse raw | return none
  let .ok rows := parseRecent? recentUrl j | return none
  let wanted := canonicalRepo repo
  let candidates := (rows.filter fun r => canonicalRepo r.repository == wanted).take maxEntries
  let mut entries : Array Entry := #[]
  let mut unresolved : Array Unresolved := #[]
  for row in candidates do
    let url := s!"{baseUrl}/{row.path}"
    let label := s!"{row.id}-v{row.version}"
    let skip (reason : String) : Unresolved := { label, reason, source := "probe" }
    match ← curlText? url with
    | none => unresolved := unresolved.push (skip s!"{url} could not be fetched")
    | some body =>
      match Json.parse body with
      | .error err => unresolved := unresolved.push (skip s!"could not parse {url}: {err}")
      | .ok ej =>
        match Entry.ofJson? url ej with
        | .error e => unresolved := unresolved.push (skip e)
        | .ok entry => entries := entries.push entry
  return some { source := "probe", location := baseUrl, entries, unresolved }

end Informal.Palomar
