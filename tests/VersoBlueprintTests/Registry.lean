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
    challengeSha256 := digest }

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
    let unresolved := String.intercalate "\n" b.unresolved.toList
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
    provenance := "1 registry record read from the cached bundle at tests/fixtures/palomar/bundle" }

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
