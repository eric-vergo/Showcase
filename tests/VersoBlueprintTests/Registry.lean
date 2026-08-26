/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import VersoBlueprint
import VersoBlueprintTests.Blueprint.Support
import VersoManual

/-!
The registry surface: what a Palomar record may be said to establish about a claim.

The rules under test are §A5's identity binding and §A9's input contract, and every one of
them is a rule about *not* concluding something:

- a consumer-supplied URL is a link and never a badge;
- a claim-level match needs the record's digest to be the displayed statement's digest
  **and** the verifying run to have recorded that digest;
- where both a repository and a digest are available on both sides, both must agree;
- the projection (`recent.json`) and the feed carry no digest, so neither can identify
  anything, whatever their text says.

The fixtures are in `tests/fixtures/palomar/` and are described by the README beside them.
-/

namespace Verso.VersoBlueprintTests.Registry

open Lean
open Verso Genre Manual
open Informal Informal.Commands
open Verso.VersoBlueprintTests.Blueprint.Support

/-! ## Repository canonicalization -/

private def projRepo : String := "eric-vergo/OEIS-A362583-Irrationality"
private def projUrl : String := "https://github.com/eric-vergo/OEIS-A362583-Irrationality"
private def projCanonical : String := "github.com/eric-vergo/oeis-a362583-irrationality"

-- Transport is spelling: scheme, `git@`, a trailing `.git`, a trailing slash and case in a
-- GitHub path all name one repository. A path on another host keeps its case, because
-- there it may be a different path.
/-- info: true -/
#guard_msgs in
#eval
  let c := Informal.Palomar.canonicalRepo
  c projUrl == projCanonical &&
  c (projUrl ++ ".git") == projCanonical &&
  c (projUrl ++ "/") == projCanonical &&
  c "git@github.com:eric-vergo/OEIS-A362583-Irrationality.git" == projCanonical &&
  c "ssh://git@github.com/eric-vergo/OEIS-A362583-Irrationality" == projCanonical &&
  c "https://www.github.com/Eric-Vergo/OEIS-A362583-Irrationality" == projCanonical &&
  -- A bare owner/repo is GitHub's, which is what the registry's records mean by it.
  c projRepo == projCanonical &&
  -- Off GitHub the path case is kept.
  c "https://gitlab.com/Owner/Repo" == "gitlab.com/Owner/Repo" &&
  -- Two different repositories do not collide.
  c "eric-vergo/other-project" != projCanonical &&
  -- Nothing that is not a repository is coerced into one.
  (c "").isEmpty && (c "not-a-repo").isEmpty && (c "https://example.org").isEmpty

/-! ## The matching rules

Constructed records, so each rule is exercised on its own rather than through whichever
fixture happens to win selection.
-/

private def matchDigest : String :=
  "3f7a1c9b2d5e08461fa93c7b0d2e6584a1cc93f70b5d28e64a3f19c7d05b8e42"

private def otherDigest : String :=
  "9c14be7205da3f68e1b0947c53da682f10cbe947355a2d6018fbc4a930e7715d"

private def record (repo url digest : String) (id : String := "PALOMAR-2026-08-01-000001")
    (title : String := "A record") : Informal.Palomar.Entry :=
  { id, version := 1, registeredAt := "2026-08-01T09:15:00Z", title
    sourceRepository := repo, sourceRepositoryUrl := url
    sourceCommit := "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"
    challengeSha256 := digest
    -- A record comes from somewhere, and where decides what it may establish: this one is a
    -- file in a cached bundle. `probed` is the same record off the network (CX-076).
    origin := s!"tests/fixtures/palomar/bundle/entries/{id}-v1.json" }

/-- The same record as the probe hands it over: identical bytes, fetched from the registry's
data host instead of read from a file. -/
private def probed (e : Informal.Palomar.Entry) : Informal.Palomar.Entry :=
  { e with origin := s!"https://data.palomar-registry.org/entries/{e.label}.json" }

private def basisOf (claim : Informal.Palomar.ClaimIdentity) (e : Informal.Palomar.Entry) :
    String × Bool :=
  match Informal.Palomar.matchEntry? claim e with
  | Option.some m => (m.basis, m.claimLevel)
  | Option.none => ("no-match", false)

private def boundClaim : Informal.Palomar.ClaimIdentity :=
  { displayedDigest := matchDigest, digestStatusBound := true, repo := projRepo }

-- The record registers this repository and this challenge, and the verdict recorded the
-- digest: the one state that binds a registration to a claim.
/-- info: ("repo+digest", true) -/
#guard_msgs in
#eval basisOf boundClaim (record projRepo projUrl matchDigest)

-- Wrong repo (CX-047 fixture): the right digest under another repository's name is not
-- this project's registration, and the both-when-present rule refuses it outright.
/-- info: ("no-match", false) -/
#guard_msgs in
#eval basisOf boundClaim
  (record "attacker/not-this-project" "https://github.com/attacker/not-this-project" matchDigest)

-- Same repo, wrong digest: provenance about the project, never about the claim.
/-- info: ("repo-only", false) -/
#guard_msgs in
#eval basisOf boundClaim (record projRepo projUrl otherDigest)

-- Digest-unbound: the record's digest *is* the displayed bytes', but this verdict recorded
-- no digest of its own, so the bytes are not bound to the verdict and the registration is
-- not bound to the claim.
/-- info: ("digest-unbound", false) -/
#guard_msgs in
#eval basisOf { boundClaim with digestStatusBound := false } (record projRepo projUrl matchDigest)

-- A site that cannot name its own repository still gets a claim-level match from a digest
-- the verdict recorded: there is nothing to disagree about.
/-- info: ("digest", true) -/
#guard_msgs in
#eval basisOf { boundClaim with repo := "" } (record projRepo projUrl matchDigest)

-- URL spoof: a record whose *display text* carries this repository's URL and this
-- challenge's digest matches nothing. `Entry` does not carry an abstract, and no rule
-- reads `title`.
/-- info: ("no-match", false) -/
#guard_msgs in
#eval basisOf boundClaim
  { record "attacker/not-this-project" "https://github.com/attacker/not-this-project" otherDigest
      (title := s!"{projUrl} {matchDigest}") with
    id := "PALOMAR-2026-08-04-000004" }

/-! Selection is deterministic and prefers the strongest reading. -/

/-- info: ("PALOMAR-2026-08-07-000007", "repo+digest", true) -/
#guard_msgs in
#eval
  let entries := #[
    record projRepo projUrl otherDigest (id := "PALOMAR-2026-08-03-000003"),
    record "attacker/not-this-project" "https://github.com/attacker/not-this-project" matchDigest
      (id := "PALOMAR-2026-08-02-000002"),
    record projRepo projUrl matchDigest (id := "PALOMAR-2026-08-07-000007")]
  match Informal.Palomar.selectMatch? boundClaim entries with
  | Option.some m => (m.entry.id, m.basis, m.claimLevel)
  | Option.none => ("none", "", false)

/-! ### A probed record binds nothing (CX-076)

A record fetched over the network is not a file: it is excluded from the input ledger the
freshness gate re-hashes, so a warm rebuild replays whatever it decided with the probe gone
and nothing able to notice. The digest agreement is real and is kept — the basis is
unchanged, and printed — but the match comes back project-level, which is the tier that says
so in as many words.
-/

-- One record, one claim, two origins. Only the origin differs, and only the origin decides.
/-- info: (("repo+digest", true), "repo+digest", false) -/
#guard_msgs in
#eval
  let e := record projRepo projUrl matchDigest
  (basisOf boundClaim e, basisOf boundClaim (probed e))

-- The same demotion where the site cannot name its own repository and the digest is the
-- whole binding: the weaker claim-level basis is still a claim-level basis.
/-- info: (("digest", true), "digest", false) -/
#guard_msgs in
#eval
  let e := record projRepo projUrl matchDigest
  let anonymous := { boundClaim with repo := "" }
  (basisOf anonymous e, basisOf anonymous (probed e))

-- A record that cannot say where its bytes came from is not an input either.
/-- info: ("repo+digest", false) -/
#guard_msgs in
#eval basisOf boundClaim { record projRepo projUrl matchDigest with origin := "" }

-- Selection ranks claim level before everything else, so a bundle holding both spellings of
-- one registration selects the one a claim may rest on — even though the probed record is
-- the later identifier, which is the tiebreak that would otherwise decide.
/-- info: ("PALOMAR-2026-08-01-000001", "repo+digest", true) -/
#guard_msgs in
#eval
  let entries := #[
    probed (record projRepo projUrl matchDigest (id := "PALOMAR-2026-08-09-000009")),
    record projRepo projUrl matchDigest]
  match Informal.Palomar.selectMatch? boundClaim entries with
  | Option.some m => (m.entry.id, m.basis, m.claimLevel)
  | Option.none => ("none", "", false)

-- And the probe-only bundle, which is the finding's own shape: an exact digest match, on a
-- verdict that recorded the digest, with no cache configured. It matches, it keeps its
-- basis, and it is not claim-level.
/-- info: ("repo+digest", false, true) -/
#guard_msgs in
#eval
  let e := probed (record projRepo projUrl matchDigest)
  match Informal.Palomar.selectMatch? boundClaim #[e] with
  | Option.some m => (m.basis, m.claimLevel, Informal.Palomar.isProbeOrigin m.entry.origin)
  | Option.none => ("none", false, false)

/-! ## The input contract (§A9)

The load-bearing input is the canonical record. A projection is not one, and neither is the
feed — both carry a repository, and neither carries the digest a claim-level match needs.
-/

private def bundleDir : String := "tests/fixtures/palomar/bundle"

-- The cached bundle loads five records and refuses two rows: one whose file is not in the
-- bundle, one written to a schema this build does not read. Neither is a build error.
/-- info: (5, 2, true, true) -/
#guard_msgs in
#eval show IO (Nat × Nat × Bool × Bool) from do
  match ← Informal.Palomar.loadBundle bundleDir with
  | .error _ => return (0, 0, false, false)
  | .ok b =>
    let unresolved := String.intercalate "\n" (b.unresolved.map (·.line)).toList
    return (b.entries.size, b.unresolved.size,
      hasSubstr unresolved "PALOMAR-2026-08-05-000005",
      hasSubstr unresolved "PALOMAR-2026-08-06-000006")

-- The provenance line says what was matched against and what could not be read.
/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  match ← Informal.Palomar.loadBundle bundleDir with
  | .error _ => return false
  | .ok b =>
    let p := b.provenance
    return hasSubstr p "5 registry records" && hasSubstr p "cached bundle" &&
      hasSubstr p "2 further rows"

-- A single immutable entry JSON is the other configured form.
/-- info: (1, true) -/
#guard_msgs in
#eval show IO (Nat × Bool) from do
  match ← Informal.Palomar.loadBundle "tests/fixtures/palomar/entry.json" with
  | .error _ => return (0, false)
  | .ok b => return (b.entries.size, b.entries.any (·.id == "PALOMAR-2026-08-01-000001"))

-- The projection on its own identifies nothing: its rows carry a repository and a commit,
-- and the digest a match binds on lives in the record they name.
/-- info: (0, true, true) -/
#guard_msgs in
#eval show IO (Nat × Bool × Bool) from do
  match ← Informal.Palomar.loadBundle "tests/fixtures/palomar/projection-only" with
  | .error _ => return (0, false, false)
  | .ok b =>
    return (b.entries.size, b.unresolved.size > 0,
      (Informal.Palomar.selectMatch? boundClaim b.entries).isNone)

-- Feed text is never identity evidence. The feed carries this repository's URL and the
-- matching digest in its `description`; nothing in the fork parses it, so configuring it
-- as a bundle fails rather than matching.
/-- info: (true, true) -/
#guard_msgs in
#eval show IO (Bool × Bool) from do
  let feed ← IO.FS.readFile "tests/fixtures/palomar/feed.xml"
  match ← Informal.Palomar.loadBundle "tests/fixtures/palomar/feed.xml" with
  | .error e =>
    -- The feed really does contain both match keys as text, and is still refused.
    return (hasSubstr feed matchDigest && hasSubstr feed projUrl, hasSubstr e "could not parse")
  | .ok _ => return (true, false)

-- A bundle whose root document cannot be read is a build error: a configured input that is
-- broken must say so.
/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  match ← Informal.Palomar.loadBundle "tests/fixtures/palomar/malformed" with
  | .error e => return hasSubstr e "could not parse"
  | .ok _ => return false

-- A configured path that is not there is a build error too, for the same reason.
/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  match ← Informal.Palomar.loadBundle "tests/fixtures/palomar/nowhere" with
  | .error e => return hasSubstr e "missing path"
  | .ok _ => return false

/-! ## Cache and probe (§A9, CX-074)

A probe reads a capped projection filtered by repository: what it returns is another, smaller
sample of the same registry, not a better copy of the configured bundle. So its records are
*added* to the cache's. A build that let a non-empty probe stand in for the cache would
publish or withhold configured evidence according to what the registry happened to have
listed that day, which is the one thing an optional network read must not decide.
-/

/-- The digest the bundle fixture's `…-000007` registers, i.e. `claim/Challenge.lean`'s. -/
private def fixtureClaimDigest : String :=
  "67af1753a29d3cd83d05c319e4c0a1c38475127c7cf9b4120cf1c6e519ddfd1d"

/-- A claim displaying those bytes, under a verdict that recorded their digest. -/
private def fixtureClaim : Informal.Palomar.ClaimIdentity :=
  { displayedDigest := fixtureClaimDigest, digestStatusBound := true, repo := projRepo }

private def probeUrl : String := "https://palomar-registry.example/data"

/-- What `Informal.Palomar.probe` would have returned. -/
private def probeBundle (entries : Array Informal.Palomar.Entry) : Informal.Palomar.Bundle :=
  { source := "probe", location := probeUrl, entries }

private def entryPath (label : String) : String :=
  s!"tests/fixtures/palomar/bundle/entries/{label}.json"

-- The regression: the cache holds the record bound to the displayed claim, the probe comes
-- back with a valid record from the same repository that is *not* it, and the claim-level
-- surface survives — alongside, not instead of, the probed record.
/-- info: ("PALOMAR-2026-08-07-000007", "repo+digest", true, 6, true) -/
#guard_msgs in
#eval show IO (String × String × Bool × Nat × Bool) from do
  match ← Informal.Palomar.loadBundle bundleDir with
  | .error _ => return ("load-failed", "", false, 0, false)
  | .ok cache =>
    let probed := probeBundle #[
      { record projRepo projUrl otherDigest (id := "PALOMAR-2026-08-08-000008") with
        origin := s!"{probeUrl}/entries/PALOMAR-2026-08-08-000008-v1.json" }]
    match Informal.Palomar.Bundle.union cache probed with
    | .error _ => return ("union-failed", "", false, 0, false)
    | .ok u =>
      match Informal.Palomar.selectMatch? fixtureClaim u.entries with
      | Option.some m =>
        return (m.entry.id, m.basis, m.claimLevel, u.entries.size,
          u.entries.any (·.id == "PALOMAR-2026-08-08-000008"))
      | Option.none => return ("none", "", false, u.entries.size, false)

-- The same record from both inputs is one record. Where the bytes were read from is not a
-- difference between them: `id`-`v`-`version` names one immutable document.
/-- info: (5, true) -/
#guard_msgs in
#eval show IO (Nat × Bool) from do
  match ← Informal.Palomar.loadBundle bundleDir with
  | .error _ => return (0, false)
  | .ok cache =>
    match ← Informal.Palomar.loadEntryFile (entryPath "PALOMAR-2026-08-03-000003-v1") with
    | .error _ => return (0, false)
    | .ok e =>
      let probed := probeBundle #[{ e with origin := s!"{probeUrl}/entries/{e.label}.json" }]
      match Informal.Palomar.Bundle.union cache probed with
      | .error _ => return (0, false)
      | .ok u => return (u.entries.size, u.source == "cache+probe")

-- Different bytes under one record name is not a merge to settle by preferring a side: one
-- of the two is not the record it names, and the build stops saying which and from where.
/-- info: (true, true, true) -/
#guard_msgs in
#eval show IO (Bool × Bool × Bool) from do
  match ← Informal.Palomar.loadBundle bundleDir with
  | .error _ => return (false, false, false)
  | .ok cache =>
    match ← Informal.Palomar.loadEntryFile (entryPath "PALOMAR-2026-08-07-000007-v1") with
    | .error _ => return (false, false, false)
    | .ok e =>
      let forged :=
        { e with challengeSha256 := otherDigest
                 origin := s!"{probeUrl}/entries/{e.label}.json" }
      match Informal.Palomar.Bundle.union cache (probeBundle #[forged]) with
      | .error err =>
        return (hasSubstr err "PALOMAR-2026-08-07-000007-v1",
          hasSubstr err "different bytes", hasSubstr err probeUrl)
      | .ok _ => return (false, false, false)

-- The provenance line names both inputs, and still counts the rows neither could resolve.
/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  match ← Informal.Palomar.loadBundle bundleDir with
  | .error _ => return false
  | .ok cache =>
    match Informal.Palomar.Bundle.union cache (probeBundle #[]) with
    | .error _ => return false
    | .ok u =>
      let p := u.provenance
      return hasSubstr p "cached bundle" && hasSubstr p probeUrl &&
        hasSubstr p "2 further rows"

/-! ## Rendering

Copy is data here: what a card says is derived from the match basis, and the basis is
printed beside it.
-/

private def claimEntry : RegistryEntry :=
  { id := "PALOMAR-2026-08-07-000007", version := 1, title := "A registered claim"
    recordedAt := "2026-08-07T09:15:00Z", sourceRepo := projRepo, repoUrl := projUrl
    sourceCommit := "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"
    treeUrl := projUrl ++ "/tree/a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"
    challengeSha256 := matchDigest, matchBasis := "repo+digest"
    provenance := "1 registry record read from the cached bundle at tests/fixtures/palomar/bundle"
    recordOrigin := entryPath "PALOMAR-2026-08-07-000007-v1" }

/-- The same registration as a probe-only build would carry it: the same record, the same
basis, fetched over the network instead of read from the bundle. -/
private def probedClaimEntry : RegistryEntry :=
  { claimEntry with
    recordOrigin := "https://data.palomar-registry.org/entries/PALOMAR-2026-08-07-000007-v1.json"
    provenance := "1 registry record fetched from https://data.palomar-registry.org during \
      this build" }

/-- info: true -/
#guard_msgs in
#eval
  let card := (registryCardHtml claimEntry).asString
  hasSubstr card "data-bp-registry-basis=\"repo+digest\"" &&
  hasSubstr card "PALOMAR-2026-08-07-000007-v1 records this claim" &&
  hasSubstr card matchDigest &&
  -- The honesty sentence, verbatim, on every card.
  hasSubstr card "immutable snapshots, recorded once and never re-verified" &&
  hasSubstr card "registration is provenance, not endorsement" &&
  hasSubstr card "Matched against 1 registry record" &&
  -- A card is not a badge.
  !hasSubstr card "bp_summary_badge"

/-- info: true -/
#guard_msgs in
#eval
  let repoOnly := (registryCardHtml { claimEntry with matchBasis := "repo-only" }).asString
  let unbound := (registryCardHtml { claimEntry with matchBasis := "digest-unbound" }).asString
  hasSubstr repoOnly "registers this repository" &&
  hasSubstr repoOnly "not bound to the claim shown here" &&
  hasSubstr unbound "not bound to the claim shown here" &&
  hasSubstr unbound "provenance about the project" &&
  hasSubstr repoOnly "data-bp-registry-basis=\"repo-only\"" &&
  hasSubstr unbound "data-bp-registry-basis=\"digest-unbound\""

-- The demoted card (CX-076): the digest agreed on a basis that binds, and the record is
-- still not bound, because this build cannot re-read the bytes that decided it. The basis
-- stays printed as data — the agreement was real — and the card says which half is missing
-- and where the bytes came from, which is the only way to tell a probed record from a cached
-- one on a page built from both.
/-- info: true -/
#guard_msgs in
#eval
  let card := (registryCardHtml probedClaimEntry).asString
  let cached := (registryCardHtml claimEntry).asString
  RegistryEntry.isClaimLevel claimEntry &&
  !RegistryEntry.isClaimLevel probedClaimEntry &&
  hasSubstr card "data-bp-registry-basis=\"repo+digest\"" &&
  !hasSubstr card "records this claim" &&
  hasSubstr card "not bound to the claim shown here" &&
  hasSubstr card "provenance about the project" &&
  hasSubstr card "not among the inputs this build recorded" &&
  hasSubstr card
    "https://data.palomar-registry.org/entries/PALOMAR-2026-08-07-000007-v1.json" &&
  hasSubstr card "read over the network is not a file this build records" &&
  -- and none of that appears on a cached record's card, which is untouched
  !hasSubstr cached "read over the network"

/-! ### Bundle health (CX-073)

What a build could not read is a fact about its *input*. It therefore has to be reportable
where there is no outcome to hang it on — a page with no matched record is exactly the page
where "was everything the bundle named actually considered?" cannot be answered any other
way.
-/

private def unreadRows : List UnresolvedRecord :=
  [{ label := "PALOMAR-2026-08-05-000005-v1"
     reason := "entries/PALOMAR-2026-08-05-000005-v1.json is not in this bundle"
     source := "cache" },
   { label := "PALOMAR-2026-08-06-000006-v1"
     reason := "schema version 4; this build reads entries of version 3"
     source := "probe" }]

private def bundleReport : RegistryBundleReport :=
  { source := "cache+probe"
    provenance := "5 registry records read from the cached bundle at \
      tests/fixtures/palomar/bundle; 2 further rows named a record this build could not \
      read, and they were not considered"
    unresolved := unreadRows }

-- (1) A selected record plus unresolved siblings: the card is there, and so are the names of
-- the rows matching never saw — with the input each came from.
/-- info: true -/
#guard_msgs in
#eval
  let out := (registrySection? (Option.some claimEntry) "" (Option.some bundleReport)).asString
  hasSubstr out "PALOMAR-2026-08-07-000007-v1 records this claim" &&
  hasSubstr out "PALOMAR-2026-08-05-000005-v1" &&
  hasSubstr out "PALOMAR-2026-08-06-000006-v1" &&
  hasSubstr out "is not in this bundle" &&
  hasSubstr out "(cache)" && hasSubstr out "(probe)" &&
  hasSubstr out "data-bp-registry-unread=\"2\""

-- (2) No selected record and the same siblings: the identities are still there, and the
-- section is explicit about what it is not. An unread row is not an absent registration.
/-- info: true -/
#guard_msgs in
#eval
  let out := (registrySection? Option.none "" (Option.some bundleReport)).asString
  hasSubstr out "PALOMAR-2026-08-05-000005-v1" &&
  hasSubstr out "PALOMAR-2026-08-06-000006-v1" &&
  hasSubstr out "an unread record is not an absent one" &&
  hasSubstr out "data-bp-registry-unread=\"2\"" &&
  -- Not a claim, not a verdict, not a badge, and not a statement that nothing is registered.
  !hasSubstr out "records this claim" &&
  !hasSubstr out "registers this repository" &&
  !hasSubstr out "bp_summary_badge"

-- A bundle every row of which was read reports nothing: this section exists to name what was
-- skipped, and a clean read has nothing to name.
/-- info: true -/
#guard_msgs in
#eval !hasSubstr (registrySection? Option.none "" Option.none).asString "bp_trust"

-- Bounded: a long list is cut off and the remainder counted, so a broken bundle cannot turn
-- the page into a directory listing.
/-- info: true -/
#guard_msgs in
#eval
  let many := (List.range 12).map fun i =>
    ({ label := s!"PALOMAR-2026-09-{i}-0000{i}-v1", reason := "not in this bundle"
       source := "cache" } : UnresolvedRecord)
  let out := (registrySection? Option.none "" (Option.some { bundleReport with
    unresolved := many })).asString
  hasSubstr out "data-bp-registry-unread=\"12\"" &&
  hasSubstr out "and 4 further rows this build could not read" &&
  countSubstr out "<li>" == 9

-- The report rides the payload into an `.olean` and back, like every other trust field; a
-- payload from before it existed decodes without one.
/-- info: (true, true) -/
#guard_msgs in
#eval
  let trust : TrustData := { registryBundle? := Option.some bundleReport }
  ((match fromJson? (α := TrustData) (toJson trust) with
    | .error _ => false
    | .ok back =>
      let rows : List UnresolvedRecord :=
        (back.registryBundle?.map RegistryBundleReport.unresolved).getD []
      rows.length == 2 &&
      (rows.head?.map UnresolvedRecord.label) == Option.some "PALOMAR-2026-08-05-000005-v1"),
   (match fromJson? (α := TrustData) (toJson ({} : TrustData)) with
    | .error _ => false
    | .ok old => old.registryBundle?.isNone))

-- The consumer link: a link, labelled unverified, with none of the registration language a
-- matched record earns.
/-- info: true -/
#guard_msgs in
#eval
  let row := (registryLinkHtml "https://palomar-registry.org/PALOMAR-2026-08-07-000007").asString
  hasSubstr row "Registry link provided by this site's author (unverified)" &&
  hasSubstr row "data-bp-registry-basis=\"consumer-link\"" &&
  hasSubstr row "<a href=" &&
  !hasSubstr row "bp_summary_badge" &&
  !hasSubstr row "Registered in" &&
  !hasSubstr row "records this claim"

/-! The badge is for claim-bound records only, and a consumer link never reaches the strip
at all. -/

private def verifiedComparator : TrustComparator :=
  { status := "verified", verifiedAt := "2026-08-07T00:00:00Z"
    theoremNames := ["RegistryFixture.mul_comm_claim"] }

/-- info: true -/
#guard_msgs in
#eval
  let plain : TrustData := { comparator := Option.some verifiedComparator }
  let bound : TrustData :=
    { comparator := Option.some { verifiedComparator with registryEntry? := Option.some claimEntry } }
  let projectOnly : TrustData :=
    { plain with registryEntry? := Option.some { claimEntry with matchBasis := "repo-only" } }
  let linkOnly : TrustData :=
    { plain with registryLink := "https://palomar-registry.org/PALOMAR-2026-08-07-000007" }
  let s := fun (t : TrustData) => (trustStripHtml t).asString
  -- Bound ⇒ one extra badge, naming the record and carrying the honesty sentence.
  hasSubstr (s bound) "registry: Palomar entry" &&
  hasSubstr (s bound) "PALOMAR-2026-08-07-000007-v1" &&
  hasSubstr (s bound) "registration is provenance, not endorsement" &&
  countSubstr (s bound) "bp_summary_badge" == countSubstr (s plain) "bp_summary_badge" + 1 &&
  -- Project-level provenance and an author's link are not verdicts about this site, so
  -- neither reaches the strip: both render byte-identically to no registry at all.
  s projectOnly == s plain &&
  s linkOnly == s plain

-- The probe-only badge, which is the finding (CX-076). A payload carrying the record on a
-- binding basis but with nothing behind it earns no badge: the strip is byte-identical to
-- one with no registration, and the payload's own claim-level accessor is empty.
/-- info: true -/
#guard_msgs in
#eval
  let plain : TrustData := { comparator := Option.some verifiedComparator }
  let probedBound : TrustData :=
    { comparator := Option.some
        { verifiedComparator with registryEntry? := Option.some probedClaimEntry } }
  let bound : TrustData :=
    { comparator := Option.some
        { verifiedComparator with registryEntry? := Option.some claimEntry } }
  let s := fun (t : TrustData) => (trustStripHtml t).asString
  (TrustData.claimRegistryEntries probedBound).isEmpty &&
  (TrustData.claimRegistryEntries bound).length == 1 &&
  s probedBound == s plain &&
  !hasSubstr (s probedBound) "registry: Palomar entry"

/-! The payload rides a quoted `TrustData` into an `.olean` and out again through the
traversal store, so the fields the comparator page reads have to survive that trip — and a
payload from before this round, which sets none of them, has to decode unchanged. -/

/-- info: true -/
#guard_msgs in
#eval
  let trust : TrustData :=
    { comparator := Option.some { verifiedComparator with registryEntry? := Option.some claimEntry }
      registryEntry? := Option.some { claimEntry with matchBasis := "repo-only" }
      registryLink := "https://palomar-registry.org/PALOMAR-2026-08-07-000007" }
  match fromJson? (α := TrustData) (toJson trust) with
  | .error _ => false
  | .ok back =>
    let claim? : Option RegistryEntry := back.comparator.bind TrustComparator.registryEntry?
    let project? : Option RegistryEntry := back.registryEntry?
    claim?.map RegistryEntry.matchBasis == Option.some "repo+digest" &&
    project?.map RegistryEntry.matchBasis == Option.some "repo-only" &&
    back.registryLink == trust.registryLink &&
    claim?.map RegistryEntry.label == Option.some claimEntry.label &&
    -- A payload written before the registry fields existed decodes to none of them.
    (match fromJson? (α := TrustData)
        (toJson ({ comparator := Option.some verifiedComparator } : TrustData)) with
     | .ok old =>
       let oldClaim? : Option RegistryEntry := old.comparator.bind TrustComparator.registryEntry?
       old.registryEntry?.isNone && old.registryLink.isEmpty && oldClaim?.isNone
     | .error _ => false)

/-! ## The page

`registrySection?` is where the two levels are kept apart: a claim-bound record renders
inside its panel, a project-level one on the page.
-/

/-- info: true -/
#guard_msgs in
#eval
  let panelPlain := (comparatorPanelInner verifiedComparator Option.none Option.none Option.none).asString
  let panelBound := (comparatorPanelInner
    { verifiedComparator with registryEntry? := Option.some claimEntry }
    Option.none Option.none Option.none).asString
  -- Nothing configured ⇒ the panel is exactly what it was: no section, no markers.
  !hasSubstr panelPlain "bp_trust_registry" &&
  !hasSubstr panelPlain "Palomar" &&
  hasSubstr panelBound "Registry record" &&
  hasSubstr panelBound "bp_trust_registry"

/-- info: true -/
#guard_msgs in
#eval
  let body := fun (e : Option RegistryEntry) (link : String) =>
    (comparatorBody verifiedComparator Option.none Option.none Option.none {} Option.none e link).asString
  let none' := body Option.none ""
  let projectOnly := body (Option.some { claimEntry with matchBasis := "repo-only" }) ""
  let linkOnly := body Option.none "https://palomar-registry.org/PALOMAR-2026-08-07-000007"
  -- Options off ⇒ no registry markup anywhere on the page.
  !hasSubstr none' "bp_trust_registry" && !hasSubstr none' "Palomar" &&
  -- Project-level provenance is a page section, never a panel one.
  hasSubstr projectOnly "Registry record" &&
  hasSubstr projectOnly "not bound to the claim shown here" &&
  -- A link with no record still says what it is, under its own heading.
  hasSubstr linkOnly "Registry link" &&
  hasSubstr linkOnly "(unverified)" &&
  !hasSubstr linkOnly "records this claim"

/-! ## End to end, through the real option path

The fixture verdict is content-bound — its `challenge_sha256` is the digest of the
challenge file beside it — and one record in the cached bundle registers exactly those
bytes. That is the whole precondition for a claim-level match, and this document exercises
it the way a consumer does.
-/

set_option verso.blueprint.trust.comparatorStatus "tests/fixtures/palomar/claim/comparator-status.json"
set_option verso.blueprint.trust.comparatorConfig "tests/fixtures/palomar/claim/comparator.json"
set_option verso.blueprint.trust.challengeFile "tests/fixtures/palomar/claim/Challenge.lean"

#docs (Manual) registryControlDoc "Registry Control" :=
:::::::
:::theorem "registry.control.anchor" (lean := "Nat.mul_comm")
Multiplication on the naturals commutes.
:::

{blueprint_dashboard}
:::::::

set_option verso.blueprint.trust.palomarBundle "tests/fixtures/palomar/bundle" in
set_option verso.blueprint.trust.palomarEntryUrl "https://palomar-registry.org/PALOMAR-2026-08-07-000007" in
#docs (Manual) registryBoundDoc "Registry Bound" :=
:::::::
:::theorem "registry.bound.anchor" (lean := "Nat.mul_comm")
Multiplication on the naturals commutes.
:::

{blueprint_dashboard}
:::::::

-- The same document with the registry options unset carries no registry anything: an
-- unconfigured consumer's page is untouched by this feature.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let html ← renderManualDocHtmlString extension_impls% registryControlDoc
  return !hasSubstr html "Palomar" && !hasSubstr html "registry:" &&
    !hasSubstr html "bp_trust_registry"

-- With the bundle configured, the verdict's own digest selects the record that registers
-- it, and the strip says so once.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let html ← renderManualDocHtmlString extension_impls% registryBoundDoc
  return hasSubstr html "registry: Palomar entry" &&
    hasSubstr html "PALOMAR-2026-08-07-000007-v1" &&
    hasSubstr html "registration is provenance, not endorsement" &&
    -- The author's link is not a strip badge, whatever else is configured.
    !hasSubstr html "Registry link provided by this site's author" &&
    -- The wrong-repo, wrong-digest and spoof records in the same bundle lose.
    !hasSubstr html "PALOMAR-2026-08-02-000002" &&
    !hasSubstr html "PALOMAR-2026-08-03-000003" &&
    !hasSubstr html "PALOMAR-2026-08-04-000004"

end Verso.VersoBlueprintTests.Registry
