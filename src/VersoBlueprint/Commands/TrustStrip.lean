/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean
import Std.Data.HashMap
import Verso
import VersoManual
import VersoBlueprint.Git
import VersoBlueprint.RuntimeCache
import VersoBlueprint.AxiomAudit
import VersoBlueprint.DependencyAnalysis
import VersoBlueprint.Commands.Common
import VersoBlueprint.FormalizationYaml
import VersoBlueprint.ExternalRefSnapshot
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.TraversalIndex
import VersoBlueprint.GraphApi
import VersoBlueprint.GraphChecks
import VersoBlueprint.NodeRoute
import VersoBlueprint.Sha256
import VersoBlueprint.TrustInputs
import VersoBlueprint.KernelAdvisories
import VersoBlueprint.StatementClosure
import VersoBlueprint.JunkValues
import VersoBlueprint.CaveatsRender
import VersoBlueprint.Palomar

/-!
Dashboard trust strip.

A compact badge row surfaced with `blueprint_dashboard`: the statement-comparator
verdict plus a link to the project's `formalization.yaml` metadata page. It is fed
by build options naming machine-readable artifacts, read at elaboration time (paths
resolve against the build CWD, i.e. the consumer package root):

- `verso.blueprint.trust.formalizationYaml` — the project's
  `formalization.yaml` (v0.3).
- `verso.blueprint.trust.comparatorStatus` — a comparator-status JSON artifact
  (`{status, theorem_names, verified_at, note, ...}`); supplies the comparator
  badge, which links to the standalone `comparator/` page.

Degrades gracefully: an unset option silently omits its badge; a *set* option
naming a missing or unparsable file is a build error (a configured trust signal
must not vanish silently). When the document also renders a
`blueprint_formalization` page, the strip links to it (resolved through the
`FormalizationPage` traversal store, never a guessed slug). The strip renders only
when it carries a real trust signal (a configured comparator).
-/

namespace Informal.Commands

open Lean
open Verso Doc Html Genre Manual
open Verso.Output.Html

register_option verso.blueprint.trust.formalizationYaml : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the project's formalization.yaml; feeds the dashboard trust strip. Empty disables."
}

register_option verso.blueprint.trust.validateFormalizationYaml : Bool := {
  defValue := false
  descr := "Whether to check the project's formalization.yaml before rendering it. Off by default. What runs is a subset check derived from the v0.4 JSON Schema, not a general validator: it establishes the required fields, types, enumerations and array minimums the standard states, and leaves formats, string lengths, uniqueness and the deliberately freeform `alignment` block alone — run `check-jsonschema` against the published schema for the rest. Every violation is reported at once, and any violation fails the build: a metadata page is a set of claims about a project, and one rendered from a document this build could not read is a set of claims nobody checked. A v0.3 document passes when its required fields are present; the v0.4-only keys are optional in the check exactly as they are in the schema."
}

register_option verso.blueprint.trust.palomarEntryUrl : String := {
  defValue := ""
  descr := "A Palomar registry permalink the site's author pastes in. Rendered as an explicitly UNVERIFIED link — never a badge, and never as \"registered in\" anything: nothing about it is checked, and a URL is not evidence that the record behind it is about this project, still less about the claim on the page. To bind a registration to a claim, configure 'verso.blueprint.trust.palomarBundle', which matches on the record's own challenge digest. Empty disables."
}

register_option verso.blueprint.trust.palomarBundle : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to cached Palomar registry data: either a directory holding the registry's recent.json together with the entries/<id>-v<version>.json records it names, or a single immutable entry JSON. Those canonical records are the only identity evidence this fork matches on — they carry the repository, the revision and `verification.challenge_sha256`, none of which the registry's XML feed does — and, because they are files this build records and re-reads before publishing, they are also the only records a CLAIM-level match may rest on: a record fetched by 'verso.blueprint.trust.palomarProbe' is project-level provenance whatever it agrees with. Set-but-missing, or a root document this build cannot read, is a build error. A single record that a projection row names and this build cannot read is counted and named on the page instead of failing the build (a bundle from a live registry legitimately holds records written to a schema this build has no rules for), and can never match. Empty disables."
}

register_option verso.blueprint.trust.palomarProbe : Bool := {
  defValue := false
  descr := "Whether the site build may fetch Palomar records from the registry's data host (via curl) rather than reading a cached bundle. Off by default and ALWAYS soft: no curl, no network, or an unreadable document degrades to 'verso.blueprint.trust.palomarBundle' when one is configured and to no registry surface otherwise. A probe never fails a build and is never required for one. What it fetches is added to the configured records, never substituted for them, and it is NEVER bound to a claim: a fetched record is a network response with no file behind it, so it is outside the input ledger this build re-reads before publishing, and it renders only as project-level provenance — explicitly labelled as fetched during the build — however exactly it agrees with the claim. Bind a registration to a claim by caching the record and configuring 'verso.blueprint.trust.palomarBundle'. What it fetches is the same canonical records a cached bundle holds, bounded to the projection rows naming this project's repository. The published site fetches nothing: the records are read at build time and baked into the page."
}

register_option verso.blueprint.trust.comparatorStatus : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to a comparator-status JSON artifact; feeds the dashboard trust strip's comparator badge. Empty disables."
}

register_option verso.blueprint.trust.comparatorConfig : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the comparator's configuration JSON; its contents are embedded verbatim (pretty-printed) on the comparator evidence page. Empty disables. Configured-but-missing ⇒ the section is omitted (probe-and-degrade), and the path is recorded on the payload as absent, so a file generated at it after this capture fails the freshness gate rather than being published without its digests ever being checked (CX-077)."
}

register_option verso.blueprint.trust.comparatorTopics : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to a JSON manifest listing MULTIPLE comparator topics, each rendered as its own first-class certified panel on the comparator page (the multi-config trust surface). Schema: {\"topics\": [ {\"name\", \"kind\"?, \"status\", \"config\"?, \"challenge\"?, \"solution\"? }, … ]}. A topic with kind \"comparator\" (the default) names its own status/config/Challenge/Solution paths (same semantics as the single-pair options); a topic with kind \"axiom-audit\" names a set of declarations ({\"decls\": [\"Ns.foo\", …]}) and certifies only their kernel-audited axiom closure (no Challenge/Solution pair). The single-pair options keep working and are independent of this — a consumer uses one scheme or the other. Empty disables."
}

register_option verso.blueprint.trust.challengeFile : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the comparator's Challenge Lean file; its contents are embedded verbatim on the comparator evidence page. Empty or missing ⇒ omitted (probe-and-degrade)."
}

register_option verso.blueprint.trust.solutionFile : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the comparator's Solution Lean file; its contents are embedded verbatim on the comparator evidence page (after the Challenge file). Empty disables. Configured-but-missing ⇒ the section is omitted (probe-and-degrade), and the path is recorded on the payload as absent, so a Solution generated at it after this capture fails the freshness gate rather than being published without its digests ever being checked (CX-077)."
}

register_option verso.blueprint.trust.kernelAdvisories : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to a JSON advisory table replacing the one this fork ships, for assessing the currency of the verifier revisions a comparator run recorded. Schema: {\"advisoriesUpdated\": \"YYYY-MM-DD\", \"advisories\": [ {\"id\", \"tool\", \"advisoryDate\", \"summary\", \"url\", \"fix\": {\"fixedRevisions\": [...], \"fixedDescendantsOf\", \"ancestry\", \"fixedFromVersion\", \"affectedRevisions\": [...]}}, … ]}. `tool` is `lean4` for the toolchain the comparator was built on, otherwise the checker's canonical name. The override REPLACES the built-in table rather than merging into it (a partial override of a safety table loses entries silently). Empty ⇒ the built-in table; set-but-missing or unparsable ⇒ build error."
}

register_option verso.blueprint.trust.statementClosure : Bool := {
  defValue := false
  descr := "Whether to compute, for each certified comparator claim, the closure of declarations its STATEMENT depends on — what a reader must read to know what the claim says, as opposed to how it is proved. Off by default. When on, the site build runs the fork's `statement-closure` executable, which elaborates the challenge chain in a FRESH environment holding exactly the chain's declared imports (not this site's environment, where the subject library and Verso are in scope and a short name could resolve to something the verifier never saw). Probe-and-degrade: a tool that is absent or fails records the reason rather than failing the build."
}

register_option verso.blueprint.trust.statementClosureMaxNodes : Nat := {
  defValue := 400
  descr := "Cap on the declarations one statement closure records. Reaching it makes the closure a lower bound rather than a count, and the surface says so. Values below 32 are a build error: under that a truncated closure is not a weak claim but an empty one."
}

register_option verso.blueprint.trust.statementClosureTool : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the `statement-closure` executable. Empty ⇒ the build probes `.lake/build/bin/statement-closure` and `.lake/packages/VersoBlueprint/.lake/build/bin/statement-closure`, and records an honest unavailable notice when neither exists. Set-but-missing is a build error: a configured tool must not degrade into a probe."
}

-- `verso.blueprint.trust.statementCaveats` and `.junkValueTable` are registered in
-- `VersoBlueprint.JunkValues`, which the declaration registry also reads them from: the
-- registry cannot import this module, and one registration is the only way both scans
-- answer to the same switch.

register_option verso.blueprint.trust.characterizations : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to a JSON sidecar declaring what the project takes its definitions to be characterized by — the consumer's answer to a junk-value caveat. Schema: {\"schemaVersion\": 1, \"characterizations\": [ {\"decl\", \"statement\", \"reference\"?, \"note\"?} ]}. Rendered on the comparator page as \"consumer-declared characterization\", with the sidecar's path and digest, and asserted by nobody. Every failure mode is a build error rather than a silent omission: a missing file, a malformed document, two entries for one declaration, or a `decl` this build's environment does not have. Empty disables. Read at elaboration (see the warm-rebuild staleness note)."
}

register_option verso.blueprint.trust.requireConnected : Bool := {
  defValue := true
  descr := "Whether a disconnected `uses` graph (more than one weakly-connected component) FAILS the site build. Default true (a coherent formalization should be a single connected development). Set false for a deliberately multi-topic blueprint (independent example chapters): the connectivity check is then reported for information but does not gate the build. Acyclicity always hard-gates regardless."
}

register_option verso.blueprint.trust.ciRunUrl : String := {
  defValue := ""
  descr := "URL of the CI run that produced the comparator verdict (e.g. a GitHub Actions run). Used as a fallback for the comparator page's \"View CI run\" link when the status artifact carries no run_url of its own. Empty ⇒ no CI link (local builds). The consumer supplies this from its CI environment (it is not obtainable at site-build time)."
}

register_option verso.blueprint.trust.requireAuditClean : Bool := {
  defValue := false
  descr := "Whether a build-time axiom-audit finding FAILS the site build. Default false: a declaration whose transitive axiom closure contains `sorryAx`, or an axiom beyond {propext, Classical.choice, Quot.sound}, is reported as a build warning plus a dashboard badge. Set true for a project that claims completeness (the finding becomes an error). Contradictions between `formalization.yaml` and the environment are ALWAYS errors, regardless of this option."
}

register_option verso.blueprint.trust.comparatorLiveProject : String := {
  defValue := ""
  descr := "Project id for comparator.live (the Lean FRO's experimental in-browser statement comparator), e.g. \"mathlib-stable\". When set — and when the challenge and solution sources are both available — the comparator page adds a permalink that opens the exact claim/solution pair in the browser for inspection (it does not re-run the verdict: the solution's import of the project library is not available there). Links only: nothing is fetched at build time and the offline guarantee is untouched. Empty disables the link."
}

/-! ### Reserved payload structures

The trust payload is quoted into an `.olean` and decoded again at generation time, so
every field added to it recompiles the whole downstream tree. The structures below are
therefore landed as one batch: what the multi-kernel surface uses today, plus
empty-default carriers for the statement-closure, statement-caveat, verifier-currency
and registry payloads that later rounds attach. Nothing populates the reserved ones
yet, and an artifact that sets none of them renders exactly as it does today.
-/

/-- One declaration a certified statement's meaning depends on. -/
structure StatementClosureEntry where
  name : String := ""
  /-- Where the declaration is defined: `challenge`, `subject`, `mathlib`, `core`, or
  another module root, named. -/
  origin : String := ""
  /-- `def`, `theorem`, `structure`, `inductive`, `constructor`, `axiom`, … -/
  kind : String := ""
  /-- Machinery rather than something a reader reads: an auto-generated recursor,
  matcher, `noConfusion`, or a reserved derived name. Counted like everything else —
  the walk reached it through a real dependency edge — and flagged so a reading list
  can fold it away and say that it did. -/
  auxiliary : Bool := false
  /-- Distance from the certified statement (0 ⇒ named by it directly). -/
  depth : Nat := 0
  /-- Where a reader can read it — a page on this site or an outbound source link.
  Empty ⇒ none resolved. -/
  href : String := ""
  /-- Capped signature text. Empty ⇒ not captured. -/
  signature : String := ""
  /-- Defining module; empty for a declaration the challenge chain itself makes. -/
  definesModule : String := ""
  /-- The declarations this one's meaning refers to, restricted to entries the reading
  list records. The meaning graph is drawn from these; an edge into something the cap
  turned away is dropped rather than pointing at a row that is not there. -/
  uses : Array String := #[]
deriving Inhabited, FromJson, ToJson, Quote

/-- What a reader must read to believe one certified claim.

Computed by the `statement-closure` subprocess, which elaborates the challenge chain in a
fresh environment holding exactly the chain's declared imports. This payload records what
came back and how firmly it is tied to the verified run; it makes no claim of its own. -/
structure StatementClosure where
  /-- What the closure was computed from: `chain` (the recorded challenge chain, digest
  bound), `chain-unbound`, `claim-decls`, `unavailable`. Empty ⇒ not computed. -/
  provenance : String := ""
  /-- Why the closure is unbound or unavailable, in the register the page uses. Empty for
  a bound closure. -/
  reason : String := ""
  /-- The certified statements the closure was computed from. -/
  roots : List String := []
  total : Nat := 0
  /-- Entries whose origin is not `mathlib`. -/
  outsideMathlib : Nat := 0
  /-- Entries outside the trusted frontier: what a reader cannot skip by accepting the
  libraries this site treats as given. -/
  untrusted : Nat := 0
  /-- Whether the walk stopped at `maxNodes`. Truncation is a verdict state of its own:
  a truncated closure reports a lower bound, never an exact count. -/
  truncated : Bool := false
  maxNodes : Nat := 0
  /-- Per-origin totals, in first-appearance order. -/
  counts : Array (String × Nat) := #[]
  /-- The chain as the tool read it: (path, SHA-256) in elaboration order. This is what
  `TrustComparator.challengeChain` is compared against to decide `provenance`. -/
  chainFiles : Array (String × String) := #[]
  /-- The import closure loaded into the fresh environment. -/
  imports : Array String := #[]
  entries : Array StatementClosureEntry := #[]
deriving Inhabited, FromJson, ToJson, Quote

/-! ### The caveat-scan payload

Defined in `VersoBlueprint.JunkValues`, which the `statement-closure` subprocess also
imports: one definition of the scan's data, so the wire format and the payload cannot
drift. The `Quote` instances are derived here rather than there, since the deriving handler
lives in Verso and the tool has no business importing it.
-/

deriving instance Quote for Informal.JunkValues.Finding
deriving instance Quote for Informal.JunkValues.OptionOverride
deriving instance Quote for Informal.JunkValues.ScanReport
deriving instance Quote for Informal.JunkValues.Characterization
deriving instance Quote for Informal.JunkValues.Characterizations

/-! ### The input record

`Informal.TrustInputs.Input` is defined below the rendering layer, for the same reason the
caveat payload is: the freshness gate that consumes it (`Informal.TrustFreshness`) runs
between traversal and emission and has no business importing this module. Its `Quote`
instance is derived here, where the deriving handler is in scope.
-/

deriving instance Quote for Informal.TrustInputs.Input

/-- One advisory as it bore on one recorded verifier revision, ready to render. -/
structure VerifierAdvisory where
  summary : String := ""
  /-- The date from which a build can carry this advisory's fixes. -/
  advisoryDate : String := ""
  url : String := ""
  /-- `fixed`, `affected` or `unresolved` for the revision assessed. -/
  state : String := ""
  /-- The table's ancestry statement, published so a reader can settle a revision of
  their own. Empty ⇒ none recorded. -/
  ancestry : String := ""
deriving Inhabited, FromJson, ToJson, Quote

/-- Currency of one verifier the run recorded, against the advisories known to this
site. Computed at elaboration by `TrustComparator.currencyRows`; empty ⇒ the record
mentioned no verifier build to assess. -/
structure VerifierCurrency where
  /-- The advisory-table key: `lean4` for the toolchain the comparator was built on,
  otherwise the checker's recorded label. -/
  tool : String := ""
  /-- `current`, `unknown`, or `stale`. Never `current` without a revision the advisory
  table proves fixed. -/
  verdict : String := ""
  /-- The immutable revision the verdict was computed against. Empty ⇒ there was nothing
  to assess, which is `unknown` rather than `current`: dates select which advisories
  apply, they do not establish that a fix is in the build that ran. -/
  revision : String := ""
  /-- Which rule decided (`revision-affected`, `identity-unbound`, … — see
  `KernelAdvisories.Assessment.reason`). Carried so the copy and the data cannot drift. -/
  reason : String := ""
  detail : String := ""
  /-- When the advisory table this verdict was computed against was last updated. -/
  advisoriesUpdated : String := ""
  /-- Whether the record assessed is newer than the table that judged it. No green claim
  is available in this state, and the copy leads with the reason. -/
  tableStale : Bool := false
  advisories : Array VerifierAdvisory := #[]
deriving Inhabited, FromJson, ToJson, Quote

/--
A registry record this build matched, and what it matched on.

Everything here is copied from one canonical Palomar record (`Informal.Palomar.Entry`);
nothing is derived, and in particular no URL to the record itself is invented, because the
registry's data host publishes records under paths this fork has no business guessing.

`matchBasis` is the whole of what the surface may claim. `repo+digest` and `digest` bind the
record to the claim on the page: the record's immutable challenge digest is the digest of
the statement shown, and the verifying run recorded that digest too. `digest-unbound` and
`repo-only` do not: they are provenance about the project, and every surface that renders
them says so in as many words.
-/
structure RegistryEntry where
  /-- The registry identifier, `PALOMAR-YYYY-MM-DD-NNNNNN`. -/
  id : String := ""
  /-- Which version of the record; registrations are append-only and versioned. -/
  version : Nat := 0
  title : String := ""
  /-- The record's `registered_at`. -/
  recordedAt : String := ""
  /-- `owner/repo`, as the record states it. -/
  sourceRepo : String := ""
  repoUrl : String := ""
  /-- The revision the registration is of. -/
  sourceCommit : String := ""
  /-- Commit-pinned tree URL of the registered project directory. -/
  treeUrl : String := ""
  /-- The record's `verification.challenge_sha256` — the field a claim-level match binds on. -/
  challengeSha256 : String := ""
  /-- When the registry's own verification ran. -/
  verifiedAt : String := ""
  /-- The registry's submission workflow run. -/
  workflowUrl : String := ""
  /-- `repo+digest`, `digest` (claim-level), `digest-not-verified`, `digest-unbound`,
  `digest-identity-mismatch`, `repo-only` (all project-level). -/
  matchBasis : String := ""
  /-- What disagreed, where the basis says something did. Empty otherwise. -/
  matchNote : String := ""
  /-- What this build matched against and where it came from, for the card's provenance
  line. -/
  provenance : String := ""
  /-- The file or URL this record's bytes were read from. A path is an input this build
  recorded and can re-read; a URL is a network response that is gone, and decides that this
  record is not claim-level (`isClaimLevel`). -/
  recordOrigin : String := ""
deriving Inhabited, FromJson, ToJson, Quote

/-- Whether a match binds the record to the claim on the page, rather than to the project.

Both halves are required, and the second is the CX-076 half: the basis must be one that
binds, *and* the bytes that decided it must be a file this build recorded as an input. A
record the probe fetched keeps its basis and stays project-level, because nothing can
re-read it — so a payload carrying one cannot earn a badge here even if some other build
minted it. -/
def RegistryEntry.isClaimLevel (e : RegistryEntry) : Bool :=
  Informal.Palomar.claimLevelBases.contains e.matchBasis
    && Informal.Palomar.isCachedOrigin e.recordOrigin

/-- `id`-`v`-`version`, the way the registry names one record. -/
def RegistryEntry.label (e : RegistryEntry) : String := s!"{e.id}-v{e.version}"

/-- One record this build could not read, as the page reports it: which record, why, and
which input it was named by. -/
structure UnresolvedRecord where
  /-- `id`-`v`-`version`. -/
  label : String := ""
  /-- Why this build could not read it. -/
  reason : String := ""
  /-- `cache` (the configured bundle) or `probe`. -/
  source : String := ""
deriving Inhabited, FromJson, ToJson, Quote

/--
What this build had to match against, whatever it went on to match.

Carried apart from any `RegistryEntry` because it is not about one record. A reader has to be
able to tell "the readable records did not mention this project" from "a row that might have
mentioned it was skipped unread", and the second is invisible if it can only be reported
inside a card that a successful match produced — which is precisely the case where there is
no card. Present only when something *was* skipped: a bundle that read cleanly has nothing to
report here, and says nothing.
-/
structure RegistryBundleReport where
  /-- `cache`, `probe`, or `cache+probe`. -/
  source : String := ""
  /-- `Informal.Palomar.Bundle.provenance`: how many records were read, and from where. -/
  provenance : String := ""
  /-- The rows this build could not read, in the order the projection named them. -/
  unresolved : List UnresolvedRecord := []
deriving Inhabited, FromJson, ToJson, Quote

/--
What one run recorded about one external checker it invoked.

**The label is not an identity.** The comparator's `external_kernels` map is
`String → Array String`: it copies the map key into the name it prints and runs the
command array, treating exit status zero as acceptance. `{"nanoda": ["/usr/bin/true"]}`
therefore produces "nanoda kernel accepts the solution" (verified against the pinned
tool). A label, with or without a separately typed revision, says nothing about what
program ran.

What does say something is this record, written by the run itself: the argv it invoked,
the digest of the executable, and the immutable revision that executable was built from.
Only a record carrying `executableSha256` **and** `sourceCommit` is treated as naming a
program; only one that *also* carries the canonical `repository` of a kernel this fork
knows is treated as naming that kernel.
-/
structure KernelReplayRecord where
  /-- The consumer-chosen key from the comparator configuration. Display text, never an
  identity claim. -/
  label : String := ""
  /-- Which protocol the comparator used to talk to the checker. Empty ⇒ unrecorded. -/
  adapterKind : String := ""
  /-- Source repository the executable was built from. Empty ⇒ unrecorded. -/
  repository : String := ""
  /-- Immutable revision of that repository. Empty ⇒ unrecorded. -/
  sourceCommit : String := ""
  /-- The exact command the run invoked. Empty ⇒ unrecorded. -/
  commandArgv : Array String := #[]
  /-- SHA-256 of the executable that ran. This, with `sourceCommit`, is what binds the
  row to a program rather than to a name. Empty ⇒ unrecorded. -/
  executableSha256 : String := ""
  replayed : Bool := false
  /-- The checker's own verdict, as the run recorded it. Empty ⇒ unrecorded. -/
  verdict : String := ""
deriving Inhabited, FromJson, ToJson, Quote

/-- Comparator verdict extracted from the comparator-status artifact.

`runUrl`/`configJson`/`challengeSource` are empty-string sentinels (matching the
other fields; empty ⇒ absent): the optional CI-run URL (from the status
artifact's `run_url` field, absent today ⇒ empty) and the verbatim contents of
the comparator config JSON / Challenge Lean file (embedded on the evidence page,
read from the `verso.blueprint.trust.comparatorConfig` / `.challengeFile`
options at elaboration; probe-and-degrade to empty). -/
structure TrustComparator where
  status : String := ""
  verifiedAt : String := ""
  theoremNames : List String := []
  note : String := ""
  runUrl : String := ""
  /-- The permitted axioms recorded in the comparator status artifact
  (`permitted_axioms`); rendered as the verdict header's axiom list. Empty ⇒ the row is
  omitted. -/
  permittedAxioms : List String := []
  /-- The comparator tool version the verdict was produced with (the status artifact's
  `tool_ref`, written by CI alongside the pinned checkout tag). Drives the `--branch` flag
  in the tier-3 reproduce commands; empty ⇒ no pinned version (the section shows a
  "check out the tag matching `lean-toolchain`" note instead). -/
  toolRef : String := ""
  /-- The comparator config path as passed on the command line (the status artifact's
  `config`, repo-root-relative) — exactly the argument the tier-3 reproduce command needs.
  Empty ⇒ recovered from the config blob URL when possible (`enrichTrustData`), else the
  run line is replaced by a README pointer. -/
  configArgPath : String := ""
  /-- The project's repository URL (derived from the first resolved challenge/solution/config
  blob URL in `enrichTrustData`). Adds a "clone the project" step to the tier-3 reproduce
  commands; empty ⇒ the commands run from the reader's own checkout.

  This is what *this build's* checkout says. `repository` is what the verifying run
  recorded, and takes precedence in the reproduce commands. -/
  repoUrl : String := ""
  /-- The subject repository the verifying run checked out (the status artifact's
  `repository`), as a URL or as `owner/repo`. Empty ⇒ unrecorded. -/
  repository : String := ""
  /-- The subject revision the verifying run checked out (the status artifact's `commit`).
  The comparator and its kernels are pinned by revision; without this the project itself
  is not, and re-running the commands after the default branch moves feeds different
  Challenge, Solution and configuration bytes to the same pinned verifiers. Empty ⇒
  unrecorded, and the reproduce section says the flow is a current-tree rerun. -/
  commit : String := ""
  configJson : String := ""
  challengeSource : String := ""
  /-- Verbatim contents of the comparator's Solution Lean file (embedded on the
  evidence page after the Challenge file, read from the
  `verso.blueprint.trust.solutionFile` option; probe-and-degrade to empty). -/
  solutionSource : String := ""
  /-- Syntactically-highlighted HTML for `configJson` / `challengeSource` /
  `solutionSource` (built at elaboration by `enrichTrustData`; empty ⇒ the evidence
  page falls back to escaped plain text). `challengeHtml` / `solutionHtml` are the
  inner markup of a `<code class="hl lean">`. -/
  configHtml : String := ""
  challengeHtml : String := ""
  solutionHtml : String := ""
  /-- Outbound links for the Challenge / Solution sources (probe-and-degrade to empty
  when git info is unavailable): a GitHub blob URL at the pinned commit for the
  Challenge file, the Solution file, and the comparator config JSON, and a
  Lean-playground URL that opens the Challenge file against the playground's *current*
  Mathlib. -/
  githubChallengeUrl : String := ""
  githubSolutionUrl : String := ""
  githubConfigUrl : String := ""
  playgroundUrl : String := ""
  /-- Whether the comparator's independent nanoda-kernel replay is enabled *for the next
  run*, parsed from `enable_nanoda` in the comparator *config* JSON (the file behind
  `verso.blueprint.trust.comparatorConfig`).

  This is **configuration, not run evidence**, and it governs exactly two things: the
  nanoda clone/build lines in `reproCommands`, and what the page says a future run will
  do. Nothing about the *linked past run* may be derived from it — see `nanodaReplay`. -/
  enableNanoda : Bool := false
  /-- Whether the run that produced this verdict actually performed the independent
  nanoda-kernel replay: the status artifact's `nanoda_replay`, machine-written by CI on a
  successful run.

  `none` ⇒ the artifact predates the field and records nothing about its run; the page
  must then say the replay is *unrecorded*, never infer it from `enableNanoda`. Whether an
  independent kernel replay happened is historical evidence, and a configuration file
  edited afterwards cannot supply it. -/
  nanodaReplay : Option Bool := none
  /-- SHA-256 of the comparator configuration CI verified (the status artifact's
  `config_sha256`), lowercase hex. Empty ⇒ the run recorded no digest, so the displayed
  configuration is bound to this verdict by name alone (legacy artifact). -/
  configSha256 : String := ""
  /-- SHA-256 of the Challenge source CI verified (the status artifact's
  `challenge_sha256`). Empty ⇒ unbound; see `configSha256`. -/
  challengeSha256 : String := ""
  /-- SHA-256 of the Solution source CI verified (the status artifact's
  `solution_sha256`). Empty ⇒ unbound; see `configSha256`. -/
  solutionSha256 : String := ""
  /-- SHA-256 this build computed over the bytes it read for `configJson`. Compared
  against `configSha256` at elaboration; a mismatch is a hard build error. -/
  configDigest : String := ""
  /-- SHA-256 this build computed over the bytes it read for `challengeSource`. -/
  challengeDigest : String := ""
  /-- SHA-256 this build computed over the bytes it read for `solutionSource`. -/
  solutionDigest : String := ""
  /-- Exact commit of the comparator tool the verdict was produced with (the status
  artifact's `tool_sha`). `toolRef` is a *tag*, which is mutable; this is not. Empty ⇒
  the status artifact records no SHA and the page says only which tag was requested. -/
  toolSha : String := ""
  /-- Revision of `ammkrn/nanoda_lib` used for the independent kernel replay (the status
  artifact's `nanoda_ref`). Pins the reproduce commands to what CI actually ran; empty ⇒
  the commands clone nanoda unpinned and the page says so. -/
  nanodaRef : String := ""
  /-- Revision of `Zouuup/landrun` used to sandbox the replay (the status artifact's
  `landrun_ref`). Empty ⇒ the page states plainly that the local reproduce flow has no
  sandbox. -/
  landrunRef : String := ""
  /-- The challenge module named in the comparator's *config* JSON (`challenge_module`).
  Cross-checked against `verso.blueprint.trust.challengeFile` at elaboration so the page
  cannot display one file while the verdict certifies another. -/
  challengeModule : String := ""
  /-- The solution module named in the comparator's config JSON (`solution_module`),
  cross-checked the same way. -/
  solutionModule : String := ""
  /-- Permalink that opens this exact claim/solution pair on comparator.live for
  inspection, built from `verso.blueprint.trust.comparatorLiveProject` plus the two
  sources. Empty ⇒ not configured, or a source was unavailable. -/
  comparatorLiveUrl : String := ""
  /-- The Lean toolchain the comparator tool itself was built with (the status
  artifact's `tool_toolchain`).

  The tool reads the project's oleans, which carry a compiler stamp, so a run
  rebuilds the tool on the *project's* toolchain rather than the tool's own — and the
  replay then runs on the kernel of the release the project pins. Empty ⇒ the record
  predates the field, and the reproduce commands say plainly that they build the tool
  on its own toolchain instead. -/
  toolToolchain : String := ""
  /-- External checkers the comparator *configuration* enables, as (label, recorded spec)
  pairs parsed from a config-side `external_kernels` map (comparator ≥ v4.34). The spec is
  whatever the config records for that label — a revision, a path, or empty.

  Consumer-chosen labels, not identities (see `KernelReplayRecord`), and configuration
  rather than run evidence: like `enableNanoda` this governs the reproduce commands and
  what a *future* run does. Empty ⇒ the config uses the older `enable_nanoda` flag, or
  enables no external checker. -/
  externalKernels : Array (String × String) := #[]
  /-- Per-label run evidence: what the status artifact recorded about each replay, as
  (label, replayed) pairs.

  Parsed tolerantly from a `kernel_replays` map/array or from the identity records, or
  synthesized from the legacy `nanoda_replay` flag. **Empty ⇒ the record says nothing
  about any replay**, which is not the same as recording that none happened, and is never
  filled in from the configuration. -/
  kernelReplays : Array (String × Bool) := #[]
  /-- Revisions the run recorded per label, as (label, revision) pairs; the legacy
  `nanoda_ref` is one entry of it. A separately typed revision pins nothing on its own:
  it is not bound to the executable the run invoked. -/
  kernelRefs : Array (String × String) := #[]
  /-- Per-checker identity records the run wrote (a status-side `kernel_identities`
  array, or a `kernel_replays` array whose entries carry the identity fields). This is
  the only thing on a status artifact that can bind a replay row to a program rather than
  to a label. Empty ⇒ the record identifies nothing it ran. -/
  kernelIdentities : Array KernelReplayRecord := #[]
  /-- Disagreements between the encodings a status artifact used for its run evidence
  (identity records, a `kernel_replays` map, the legacy `nanoda_replay`/`nanoda_ref`
  pair). Reported by the parser, thrown by `checkComparatorEncodings` at elaboration; a
  payload that reaches rendering always has this empty, because a record that contradicts
  itself fails the build rather than picking a winner. -/
  encodingConflicts : Array String := #[]
  /-- The ordered challenge chain the verifying run recorded (the status artifact's
  `challenge_chain`): (path, SHA-256) per file, primary Challenge included, in
  elaboration order. Empty ⇒ the record predates the field, so the chain this site
  reads is bound to the verdict by nothing.

  Stored and round-tripped here; the surface that binds a meaning closure to it is a
  later round. -/
  challengeChain : Array (String × String) := #[]
  /-- When the *upstream* record this verdict was transcribed from was made (the status
  artifact's `reported_at`), for a `reported-upstream` status. Deliberately distinct
  from `verifiedAt`: this site's CI verified nothing, so no date with
  `verified_at` semantics may be shown. Empty ⇒ no date is rendered at all. -/
  reportedAt : String := ""
  /-- Who published the upstream record (the status artifact's `reported_source`), named
  in the `reported-upstream` label and tooltip. Empty ⇒ the copy says "the subject
  repository". -/
  reportedSource : String := ""
  /-- Chain files beyond the primary Challenge, in elaboration order (a topic manifest's
  `challenge_deps`). Reserved for the statement-closure surface. -/
  challengeDeps : Array String := #[]
  /-- Subject-side declarations aligned with the certified statements (a topic
  manifest's `claim_decls`). Reserved as the statement-closure fallback anchor. -/
  claimDecls : Array String := #[]
  /-- The certified claims' meaning closure. Reserved; `none` ⇒ not computed. -/
  closure? : Option StatementClosure := none
  /-- Total-function conventions in the certified statements a reader could misread, from
  the scan that rode the meaning traversal. `none` ⇒ not scanned, which is a different
  thing from a scan that matched nothing and renders differently. -/
  caveats? : Option Informal.JunkValues.ScanReport := none
  /-- Per-verifier currency against the advisories known to this site, computed at
  elaboration from the recorded revisions. Empty ⇒ the record named no verifier build to
  assess (which is itself said in prose, never rendered as a clean bill). -/
  currency : Array VerifierCurrency := #[]
  /-- A registry record bound to *this claim*: its immutable challenge digest is the digest
  of the statement this panel displays, and the verifying run recorded that digest as well.
  `none` ⇒ nothing configured, or nothing matched, or what matched was weaker than that and
  is reported at project level instead. -/
  registryEntry? : Option RegistryEntry := none
  /-- The non-Lean files THIS elaboration read to build this verdict — status artifact,
  configuration, Challenge, Solution, and each challenge-chain file the closure tool hashed
  — as revision-free paths plus the SHA-256 of the bytes read.

  Not the run's digests (`challengeSha256` and friends): those bind the display to the
  *verifying run*, and are unaffected by any of this. These bind the display to the *build*,
  which nothing did before. Lake tracks no read of these files, so a warm rebuild would
  otherwise decode this whole record — verdict, statement, digests, links — and publish it
  under a newer revision, internally consistent and out of date (CX-075). The gate that
  re-reads them before emission is `Informal.TrustFreshness`. -/
  inputs : Array Informal.TrustInputs.Input := #[]
deriving Inhabited, FromJson, ToJson, Quote

/-- A named comparator topic: a display name plus its verdict. The multi-config
trust surface (`verso.blueprint.trust.comparatorTopics`) carries a list of these,
each rendered as a first-class certified panel reusing the single-panel body. -/
structure ComparatorTopic where
  name : String := ""
  comparator : TrustComparator := {}
deriving Inhabited, FromJson, ToJson, Quote

/-- One declaration's kernel-audited axiom closure, for a config-less
axiom-audit topic (`Lean.collectAxioms`, the same closure `#print axioms`
reports). -/
structure AxiomAuditDecl where
  name : String := ""
  axioms : List String := []
  /-- Whether `sorryAx` is in the transitive closure (an incomplete proof). -/
  sorried : Bool := false
  /-- Axioms beyond {propext, Classical.choice, Quot.sound}. -/
  nonstandard : List String := []
deriving Inhabited, FromJson, ToJson, Quote

/-- A config-less axiom-audit topic: a named set of declarations, each with its
kernel-audited axiom closure. Unlike a comparator topic it has no
Challenge/Solution pair — it certifies only "these declarations use exactly these
axioms" (e.g. a `#print axioms`-only bound). -/
structure AxiomAuditTopic where
  name : String := ""
  decls : List AxiomAuditDecl := []
deriving Inhabited, FromJson, ToJson, Quote

/-- Trust-strip payload: only fields present in the configured artifacts are set.
The `formalization.yaml`-derived scalars (`sorryCount` / `axioms` / `reviewStatus`)
are captured for downstream use; the strip and comparator page draw on `comparator`,
and the graph gate on `requireConnected`. -/
structure TrustData where
  sorryCount : Option Nat := none
  axioms : List String := []
  reviewStatus : String := ""
  comparator : Option TrustComparator := none
  /-- The multi-config comparator topics, from
  `verso.blueprint.trust.comparatorTopics`. Empty ⇒ the consumer uses the
  single-pair options (`comparator` above) or no comparator at all. When
  non-empty the comparator page renders one certified panel per topic and the
  strip/trust-model aggregate across them. -/
  comparators : List ComparatorTopic := []
  /-- Config-less axiom-audit topics, from `verso.blueprint.trust.comparatorTopics`
  (topics with `kind: "axiom-audit"`). Each renders a panel certifying the
  kernel-audited axiom closure of a named declaration set, with no
  Challenge/Solution pair. -/
  axiomAuditTopics : List AxiomAuditTopic := []
  /-- Whether a disconnected `uses` graph fails the build (item 1). Default `true`;
  a deliberately multi-topic blueprint sets `verso.blueprint.trust.requireConnected`
  false, and the connectivity check is then reported for information without gating. -/
  requireConnected : Bool := true
  /-- URL of the CI run that produced the comparator verdict, from the
  `verso.blueprint.trust.ciRunUrl` option (`none` ⇒ unset, e.g. a local build).
  Used as a fallback for the comparator page's "View CI run" link when the status
  artifact carries no `run_url` of its own. The SHA/run id lives in CI and is not
  readable at site-build time, so the consumer supplies it. -/
  ciRunUrl : Option String := none
  /-- Findings of the build-time axiom audit (`Informal.AxiomAudit.run`, executed by
  `blueprint_dashboard` where the environment is available). This is *run evidence*:
  the trust-model page, the audit page, and the dashboard badge all report this one
  run rather than each recomputing or restating `formalization.yaml`. `none` ⇒ the
  audit did not run (no dashboard block). -/
  audit? : Option Informal.AxiomAudit.Summary := none
  /-- Divergence between the authored `uses` edges and the const-level dependencies
  of the associated Lean (`DependencyAnalysis.auditAuthoredEdges`). `none` ⇒ the
  comparison did not run. -/
  edgeAudit? : Option Informal.DependencyAnalysis.EdgeAudit := none
  /-- Whether an axiom-audit finding fails the build
  (`verso.blueprint.trust.requireAuditClean`), carried so the trust-model page can
  state which contract this project is under. -/
  requireAuditClean : Bool := false
  /-- A registry record about this *project* rather than about any one claim: matched by
  repository alone, or by a digest the verifying run never recorded. `none` ⇒ nothing
  configured, nothing matched, or a claim-level match was found and says more.
  -/
  registryEntry? : Option RegistryEntry := none
  /-- A registry permalink the site's author supplied
  (`verso.blueprint.trust.palomarEntryUrl`). Carried apart from `registryEntry?` because it
  is not evidence of anything: nothing checked that the record behind it exists, describes
  this project, or concerns the claim on the page, and the surface that renders it says so
  rather than styling it as a verdict. Empty ⇒ none supplied. -/
  registryLink : String := ""
  /-- The state of the registry records this build read, independently of whether any of
  them matched. `none` ⇒ nothing was configured, or every row the projection named was read
  cleanly; either way there is nothing to report and nothing is rendered. -/
  registryBundle? : Option RegistryBundleReport := none
  /-- When the kernel-advisory table this build assessed verifier currency against was
  last revised by hand. Carried on the payload rather than only on the currency rows,
  because the self-aging clause is exactly what a page with *no* assessable verifier
  still has to publish. Empty ⇒ no table was read (a payload from before this field). -/
  advisoriesUpdated : String := ""
  /-- The characterization sidecar this project declares
  (`verso.blueprint.trust.characterizations`), with the path and digest of the bytes read.
  Project-level rather than per-claim, which is what a sidecar of declarations is. `none` ⇒
  none configured. -/
  characterizations? : Option Informal.JunkValues.Characterizations := none
  /-- The project-level non-Lean files this elaboration read: `formalization.yaml`, the
  topic manifest, the kernel-advisory and caveat-table overrides, the characterization
  sidecar, and the Palomar records a cached bundle supplied. Per-verdict files live on
  `TrustComparator.inputs`.

  Same purpose and same gate: every one of these shapes the comparator page or the strip,
  every one is read at elaboration, and Lake tracks none of them. -/
  inputs : Array Informal.TrustInputs.Input := #[]
deriving Inhabited, FromJson, ToJson, Quote

/-- The Mathlib project id used to open the Challenge file in the Lean 4 web
playground (`live.lean-lang.org`, `#project=<id>`). The exact id string is a
deployment detail of the playground; kept as a single easily-changed constant.
`MathlibDemo` is the `Projects/` folder name in the lean4web deployment (its
`leanweb-config.json` is `name := "Latest Mathlib"`, `default := true`), so even
if the id ever drifts the playground falls back to this default project. -/
def playgroundMathlibProjectId : String := "MathlibDemo"

/-- Extract the trust-relevant fields from a parsed `formalization.yaml` document. -/
def TrustData.ofFormalizationJson (doc : Json) : TrustData :=
  let status := (doc.getObjVal? "status").toOption.getD Json.null
  let review := (doc.getObjVal? "review").toOption.getD Json.null
  {
    sorryCount := (status.getObjValAs? Nat "sorry_count").toOption
    axioms := (status.getObjValAs? (List String) "axioms").toOption.getD []
    reviewStatus := (review.getObjValAs? String "status").toOption.getD ""
  }

/-! ### Multi-kernel parsing

The comparator grew from one optional second kernel (`enable_nanoda` in the config,
`nanoda_replay` in the status artifact) towards naming its kernels (`external_kernels`).
Both spellings are read here, and neither is allowed to speak for the other:
configuration says what the *next* run does, the status artifact says what the *linked*
run did, and a record that says nothing about a replay records nothing — it does not
record that none happened.

Everything is tolerant of shape and total. A field spelled in a way this parser does not
recognize yields no kernels rather than a build error: the surfaces that consume it all
degrade to "unrecorded", which is the honest reading of "we could not tell".
-/

/-- The revision-ish string a kernel entry records: a plain string value, or the
`ref`/`rev`/`path` of an object one. Empty when it records only a name. -/
private def kernelSpecString (j : Json) : String :=
  match j with
  | .str s => s
  | .obj _ =>
    let pick := fun k => (j.getObjValAs? String k).toOption.getD ""
    let ref := pick "ref"
    if !ref.isEmpty then ref
    else
      let rev := pick "rev"
      if !rev.isEmpty then rev else pick "path"
  | _ => ""

/-- The (name, replayed?, revision) triples of a kernel map/array, accepting an object
map (`{"nanoda": true}`, `{"nanoda": {"replayed": true, "ref": "…"}}`, `{"nanoda": "…"}`)
and an array of objects (`[{"kernel": "nanoda", "replayed": true, "ref": "…"}]`) or of
bare names. Object keys come out in key order, which is stable across builds. -/
private def kernelEntries (j : Json) : Array (String × Option Bool × String) :=
  let fields := fun (v : Json) =>
    match v with
    | .bool b => (some b, "")
    | .obj _ =>
      let replayed :=
        match (v.getObjValAs? Bool "replayed").toOption with
        | Option.some b => Option.some b
        | Option.none => (v.getObjValAs? Bool "replay").toOption
      (replayed, kernelSpecString v)
    | _ => (none, kernelSpecString v)
  match j with
  | .obj kvs =>
    kvs.foldl (init := (#[] : Array (String × Option Bool × String))) fun acc k v =>
      let (replayed, ref) := fields v
      acc.push (k, replayed, ref)
  | .arr items =>
    items.filterMap fun it =>
      match it with
      | .str s => if s.isEmpty then none else some (s, none, "")
      | .obj _ =>
        let named := (it.getObjValAs? String "kernel").toOption.getD ""
        let named := if named.isEmpty then (it.getObjValAs? String "name").toOption.getD "" else named
        if named.isEmpty then none
        else
          let (replayed, ref) := fields it
          some (named, replayed, ref)
      | _ => none
  | _ => #[]

/-- Kernels a comparator *configuration* enables, from an `external_kernels` field.
Absent ⇒ empty (the config uses `enable_nanoda`, or enables no second kernel). -/
def parseExternalKernels (config : Json) : Array (String × String) :=
  match config.getObjVal? "external_kernels" with
  | .ok j => (kernelEntries j).map fun e => (e.1, e.2.2)
  | .error _ => #[]

/-- Whether a comparator *configuration* enables the nanoda replay, in either spelling:
the `enable_nanoda` flag, or an `external_kernels` entry named `nanoda`. A configuration
that migrated from the first to the second has not turned anything off. -/
def configEnablesNanoda (config : Json) : Bool :=
  (config.getObjValAs? Bool "enable_nanoda").toOption.getD false
    || (parseExternalKernels config).any fun e => e.1 == "nanoda"

/-- Per-label run evidence carried by the legacy `nanoda_replay`/`nanoda_ref` pair. -/
private def legacyKernelEntries (status : Json) : Array (String × Option Bool × String) :=
  let replay := (status.getObjValAs? Bool "nanoda_replay").toOption
  let ref := (status.getObjValAs? String "nanoda_ref").toOption.getD ""
  if replay.isNone && ref.isEmpty then #[] else #[("nanoda", replay, ref)]

/-- Whether a JSON object carries any of the identity fields — the difference between a
run that recorded what it invoked and one that recorded only a label. -/
private def hasIdentityFields (j : Json) : Bool :=
  ["executable_sha256", "source_commit", "command_argv", "repository", "adapter_kind",
   "verdict"].any fun k => (j.getObjVal? k).toOption.isSome

/-- The per-checker identity records a run wrote: a status-side `kernel_identities`
array, or a `kernel_replays` array whose entries carry identity fields. Absent ⇒ empty,
and every surface then renders labels as labels. -/
def parseKernelIdentities (status : Json) : Array KernelReplayRecord :=
  let ofObj := fun (it : Json) =>
    let str := fun k => (it.getObjValAs? String k).toOption.getD ""
    let label :=
      let l := str "label"
      if l.isEmpty then (let k := str "kernel"; if k.isEmpty then str "name" else k) else l
    if label.isEmpty then Option.none
    else Option.some {
      label
      adapterKind := str "adapter_kind"
      repository := str "repository"
      sourceCommit := str "source_commit"
      commandArgv := (it.getObjValAs? (Array String) "command_argv").toOption.getD #[]
      executableSha256 := str "executable_sha256"
      replayed := (it.getObjValAs? Bool "replayed").toOption.getD false
      verdict := str "verdict"
      : KernelReplayRecord }
  let fromArray := fun (items : Array Json) => items.filterMap fun it =>
    match it with
    | .obj _ => ofObj it
    | _ => Option.none
  match status.getObjVal? "kernel_identities" with
  | .ok (.arr items) => fromArray items
  | _ =>
    match status.getObjVal? "kernel_replays" with
    | .ok (.arr items) => if items.any hasIdentityFields then fromArray items else #[]
    | _ => #[]

/-- Whether `kernel_replays` is itself the identity source, in which case it is one
encoding rather than two: reading the same array twice, once as identities and once
generically, would compare a record with itself under two different key spellings. -/
private def kernelReplaysIsIdentitySource (status : Json) : Bool :=
  match status.getObjVal? "kernel_identities" with
  | .ok (.arr _) => false
  | _ =>
    match status.getObjVal? "kernel_replays" with
    | .ok (.arr items) => items.any hasIdentityFields
    | _ => false

/-! ### Canonicalization

A status artifact may spell its run evidence three ways: identity records, a generic
`kernel_replays` map or array, and the legacy `nanoda_replay`/`nanoda_ref` pair. Earlier
this parser kept two independent projections of that — the generic one for the semantic
accessors, the raw legacy fields for whatever read them directly — so a record saying
`replayed: true` at one revision under one spelling and `false` at another under the other
loaded happily, and different pages then reported different revisions for the same claimed
replay.

There is now exactly one canonical record set. Every encoding present is parsed, and the
encodings must AGREE: for each label, at most one distinct recorded replay boolean and at
most one distinct non-empty revision across all of them. Disagreement is a build error —
a machine record that contradicts itself has no reading, and picking a winner would be
inventing one. Labels named by one encoding and not another are a union, not a conflict:
an encoding may be partial without being wrong.

The same rule holds *within* the identity array, and on every identity-bearing field
rather than on the two the cross-encoding pass compares: see `canonicalKernelIdentities`.
Uniqueness there is what lets `identityFor?` be a lookup instead of a choice.
-/

/-- Repository URL in the form the comparison uses: lower-cased, without a trailing
`.git` or `/`. -/
def normalizeRepoUrl (u : String) : String :=
  let u := u.trimAscii.toString.toLower
  let u := if u.endsWith ".git" then (u.dropEnd 4).toString else u
  if u.endsWith "/" then (u.dropEnd 1).toString else u

/-- A digest in the form comparisons use: trimmed and lower-cased. Hex case is spelling,
not identity, so a record giving the same digest twice in two cases has recorded one. -/
private def normalizeDigest (s : String) : String := s.trimAscii.toString.toLower

/-- The identity-bearing fields of one record, named and in the normalized form same-label
records must agree on.

Field by field rather than structural equality, for two reasons: a disagreement can be
*named* (a reader of the build error learns which field), and a field added later for
display alone does not silently become a conflict criterion by existing. -/
private def identityFields (r : KernelReplayRecord) : Array (String × String) := #[
  ("repository", normalizeRepoUrl r.repository),
  ("source_commit", r.sourceCommit.trimAscii.toString),
  ("executable_sha256", normalizeDigest r.executableSha256),
  -- JSON-rendered: readable in the error, and escaped, so no argument can spell a
  -- separator and make two different vectors compare equal.
  ("command_argv", (toJson r.commandArgv).compress),
  ("adapter_kind", r.adapterKind.trimAscii.toString),
  ("replayed", toString r.replayed),
  ("verdict", r.verdict.trimAscii.toString)]

private def shownFieldValue (s : String) : String :=
  if s.isEmpty then "(absent)" else s

/--
Merge same-label identity records into one, or name every disagreement.

`parseKernelIdentities` keeps every object in the array, so one artifact can carry two
`nanoda` records — a canonical repository and executable digest in the first, an
attacker's in the second. The conflict pass above compares only the replay boolean and
the recorded revision, so a pair agreeing on those two survived it intact, and
`identityFor?` then takes the *first*: a non-semantic permutation of a JSON array decided
the assurance tier, the displayed digest, and whether the label could be called the kernel
it names. Both orders validated (CX-071).

Same-label records must therefore agree on every identity-bearing field — repository,
source commit, executable digest, argv, adapter kind, replay and verdict — under the
normalizations this module already uses elsewhere (repository URLs canonicalized, digests
lower-cased, the rest trimmed). Identical duplicates are the one benign case and merge to
a single record. Anything else is named here and thrown before selection can happen: a
record that contradicts itself about what ran has no reading, and picking one of its
halves would be inventing one.

Returns the merged records in first-mention order, plus the conflicts.
-/
def canonicalKernelIdentities (identities : Array KernelReplayRecord) :
    Array KernelReplayRecord × Array String := Id.run do
  let mut merged : Array KernelReplayRecord := #[]
  let mut conflicts : Array String := #[]
  for r in identities do
    match merged.findIdx? (fun m => m.label == r.label) with
    | Option.none => merged := merged.push r
    | Option.some i =>
      let kept := identityFields merged[i]!
      let dup := identityFields r
      for k in [0:kept.size] do
        let (field, keptValue) := kept[k]!
        let dupValue := (dup[k]!).2
        if keptValue != dupValue then
          conflicts := conflicts.push
            s!"'{r.label}' has two identity records disagreeing on {field}: \
               {shownFieldValue keptValue} and {shownFieldValue dupValue}"
  return (merged, conflicts)

/-- The encodings a status artifact carries, each as (source name, entries). -/
private def kernelEncodings (status : Json)
    (identities : Array KernelReplayRecord) : Array (String × Array (String × Option Bool × String)) :=
  let identityEntries := identities.map fun r =>
    (r.label, Option.some r.replayed, r.sourceCommit)
  let identitySourceName :=
    if kernelReplaysIsIdentitySource status then "kernel_replays" else "kernel_identities"
  let genericEntries :=
    if kernelReplaysIsIdentitySource status then #[]
    else match status.getObjVal? "kernel_replays" with
      | .ok j => kernelEntries j
      | .error _ => #[]
  let legacyEntries := legacyKernelEntries status
  (if identityEntries.isEmpty then #[] else #[(identitySourceName, identityEntries)]) ++
  (if genericEntries.isEmpty then #[] else #[("kernel_replays", genericEntries)]) ++
  (if legacyEntries.isEmpty then #[] else #[("nanoda_replay/nanoda_ref", legacyEntries)])

/-- Merge the encodings into one canonical record set, reporting every disagreement.

Returns the canonical entries — (label, recorded replay, recorded revision), in the order
labels are first mentioned — and a list of human-readable conflicts. A non-empty conflict
list is a build error at the point the artifact is read; it is carried on the record rather
than thrown here so that the parser stays total and the conflicts stay directly testable. -/
private def canonicalKernelRecords
    (encodings : Array (String × Array (String × Option Bool × String))) :
    Array (String × Option Bool × String) × Array String := Id.run do
  let mut labels : Array String := #[]
  for (_, entries) in encodings do
    for e in entries do
      unless labels.contains e.1 do labels := labels.push e.1
  let mut canonical : Array (String × Option Bool × String) := #[]
  let mut conflicts : Array String := #[]
  for label in labels do
    let mut replay : Option Bool := Option.none
    let mut replaySource : String := ""
    let mut ref : String := ""
    let mut refSource : String := ""
    for (source, entries) in encodings do
      for e in entries do
        if e.1 != label then continue
        match e.2.1 with
        | Option.some b =>
          match replay with
          | Option.some b' =>
            if b != b' then
              conflicts := conflicts.push
                s!"'{label}' is recorded as replayed={b'} by {replaySource} and replayed={b} by \
                   {source}"
          | Option.none => replay := Option.some b; replaySource := source
        | Option.none => pure ()
        let entryRef := e.2.2.trimAscii.toString
        unless entryRef.isEmpty do
          if ref.isEmpty then ref := entryRef; refSource := source
          else if ref != entryRef then
            conflicts := conflicts.push
              s!"'{label}' is recorded at revision {ref} by {refSource} and at {entryRef} by \
                 {source}"
    canonical := canonical.push (label, replay, ref)
  return (canonical, conflicts)

/-- The ordered challenge chain a run recorded (`challenge_chain`): (path, SHA-256) per
file, in elaboration order. Entries without a path are dropped; a missing digest reads as
empty, i.e. that entry is unbound. Absent ⇒ empty. -/
def parseChallengeChain (status : Json) : Array (String × String) :=
  match status.getObjVal? "challenge_chain" with
  | .ok (.arr items) =>
    items.filterMap fun it =>
      match it with
      | .str p => if p.isEmpty then none else some (p, "")
      | .obj _ =>
        let path := (it.getObjValAs? String "path").toOption.getD ""
        if path.isEmpty then none
        else some (path, (it.getObjValAs? String "sha256").toOption.getD "")
      | _ => none
  | _ => #[]

/-- Extract the comparator verdict from a comparator-status artifact (`verified_at` may be `null`).
Every field beyond `status` is optional (absent in older artifacts ⇒ empty-sentinel default), so
an artifact written before the provenance fields existed still loads. The embedded config /
Challenge sources are filled in later from their own options (`elabTrustData?`). -/
def TrustComparator.ofJson (j : Json) : TrustComparator :=
  -- ONE identity record per checker label, before anything can select between two.
  let (identities, identityConflicts) := canonicalKernelIdentities (parseKernelIdentities j)
  -- ONE canonical record set, merged from every encoding present and required to agree.
  let (kernels, conflicts) := canonicalKernelRecords (kernelEncodings j identities)
  let kernelOf := fun (name : String) => kernels.find? fun e => e.1 == name
  -- The nanoda-specific fields are derived FROM the canonical set, never parsed beside it:
  -- they are a compatibility spelling of the same fact, not a second opinion about it.
  let nanodaReplay := (kernelOf "nanoda").bind (·.2.1)
  let nanodaRef := ((kernelOf "nanoda").map (·.2.2)).getD ""
  {
    status := (j.getObjValAs? String "status").toOption.getD ""
    verifiedAt := (j.getObjValAs? String "verified_at").toOption.getD ""
    theoremNames := (j.getObjValAs? (List String) "theorem_names").toOption.getD []
    note := (j.getObjValAs? String "note").toOption.getD ""
    runUrl := (j.getObjValAs? String "run_url").toOption.getD ""
    permittedAxioms := (j.getObjValAs? (List String) "permitted_axioms").toOption.getD []
    toolRef := (j.getObjValAs? String "tool_ref").toOption.getD ""
    configArgPath := (j.getObjValAs? String "config").toOption.getD ""
    toolSha := (j.getObjValAs? String "tool_sha").toOption.getD ""
    toolToolchain := (j.getObjValAs? String "tool_toolchain").toOption.getD ""
    -- The subject the run verified. Without the revision, "reproduce this" reproduces the
    -- verifiers but not the bytes they checked.
    repository := (j.getObjValAs? String "repository").toOption.getD ""
    commit := (j.getObjValAs? String "commit").toOption.getD ""
    nanodaRef
    landrunRef := (j.getObjValAs? String "landrun_ref").toOption.getD ""
    challengeModule := (j.getObjValAs? String "challenge_module").toOption.getD ""
    solutionModule := (j.getObjValAs? String "solution_module").toOption.getD ""
    -- Run evidence. Absent ⇒ `none` (unrecorded), which is *not* the same as `false`
    -- and is never filled in from the current configuration.
    nanodaReplay
    kernelReplays := kernels.filterMap fun e => e.2.1.map fun b => (e.1, b)
    kernelRefs := kernels.filterMap fun e => if e.2.2.isEmpty then none else some (e.1, e.2.2)
    kernelIdentities := identities
    -- Identity disagreements first: they are the ones that would otherwise be settled by
    -- array order rather than by evidence.
    encodingConflicts := identityConflicts ++ conflicts
    -- Content binding. Absent ⇒ empty ⇒ the displayed source is bound to this verdict
    -- by name and path shape only.
    configSha256 := (j.getObjValAs? String "config_sha256").toOption.getD ""
    challengeSha256 := (j.getObjValAs? String "challenge_sha256").toOption.getD ""
    solutionSha256 := (j.getObjValAs? String "solution_sha256").toOption.getD ""
    challengeChain := parseChallengeChain j
    -- Upstream-report provenance. `reported_at` is the date the *upstream* record was
    -- made; it never stands in for `verified_at`.
    reportedAt := (j.getObjValAs? String "reported_at").toOption.getD ""
    reportedSource := (j.getObjValAs? String "reported_source").toOption.getD ""
  }

/-! ### Run evidence -/

/-- Per-kernel run evidence in a stable order, with the legacy `nanoda_replay` field
read as the entry it is. Records built by hand (tests, fixtures) set one or the other;
both spell the same fact. -/
def TrustComparator.recordedReplays (cmp : TrustComparator) : Array (String × Bool) :=
  if cmp.kernelReplays.any (fun e => e.1 == "nanoda") then cmp.kernelReplays
  else
    match cmp.nanodaReplay with
    | Option.some b => cmp.kernelReplays.push ("nanoda", b)
    | Option.none => cmp.kernelReplays

/-- What the linked run recorded about `kernel`: `some true` it replayed, `some false`
it did not, `none` it said nothing. Never derived from the configuration. -/
def TrustComparator.recordedReplay? (cmp : TrustComparator) (kernel : String) : Option Bool :=
  (cmp.recordedReplays.find? fun e => e.1 == kernel).map (·.2)

/-- The revision the run recorded for `kernel`; empty ⇒ none recorded. -/
def TrustComparator.recordedKernelRef (cmp : TrustComparator) (kernel : String) : String :=
  match cmp.kernelRefs.find? fun e => e.1 == kernel with
  | Option.some e => e.2
  | Option.none => if kernel == "nanoda" then cmp.nanodaRef else ""

/-- Kernels the current *configuration* enables, in a stable order. `enable_nanoda` and
an `external_kernels` entry named `nanoda` are two spellings of the same thing, so a
migrated configuration is not read as having dropped the kernel. -/
def TrustComparator.configuredKernels (cmp : TrustComparator) : Array String :=
  let named := cmp.externalKernels.map (·.1)
  if cmp.enableNanoda && !named.contains "nanoda" then named.push "nanoda" else named

/-- Kernels the linked run recorded that it replayed with. Labels, not identities —
`kernelIdentityTier` says how much each one is worth. -/
def TrustComparator.replayedKernels (cmp : TrustComparator) : Array String :=
  (cmp.recordedReplays.filter (·.2)).map (·.1)

/-- Every checker this verdict mentions at all, in a stable order: recorded replays
first, then labels carrying only a recorded revision or an identity record, then those
the configuration enables and the record never mentions.

This is the row set of the per-checker table. A label reaches it by being mentioned
*anywhere*, because each way of being mentioned and not another is itself the state a
reader needs: a revision with no replay, a replay the configuration has since dropped, a
configured checker the run never ran. -/
def TrustComparator.mentionedKernels (cmp : TrustComparator) : Array String := Id.run do
  let mut out : Array String := #[]
  let push := fun (acc : Array String) (k : String) =>
    if k.isEmpty || acc.contains k then acc else acc.push k
  for e in cmp.recordedReplays do out := push out e.1
  for e in cmp.kernelRefs do out := push out e.1
  for r in cmp.kernelIdentities do out := push out r.label
  -- Records built in source (tests, fixtures) may carry only the legacy fields.
  if cmp.nanodaReplay.isSome || !cmp.nanodaRef.isEmpty then out := push out "nanoda"
  for k in cmp.configuredKernels do out := push out k
  return out

/-! ### Checker identity

A comparator `external_kernels` key is a consumer-chosen label the tool copies into its
output; the tool runs the associated command array and reads exit status zero as
acceptance. `{"nanoda": ["/usr/bin/true"]}` prints that nanoda accepted the solution.
Nothing on this page may therefore turn a label — or a separately typed revision beside
it — into a claim about which program checked the proof.

`kernelIdentityTier` is the single place that judgement is made, and every surface reads
it rather than re-deciding.
-/

/-- Canonical source repositories of the checkers this fork is willing to name. A record
whose label is one of these but whose recorded repository is something else is not that
checker: the label is consumer-chosen text. -/
def knownKernelRepos : List (String × String) :=
  [("nanoda", "https://github.com/ammkrn/nanoda_lib")]

/-- Whether every character is a lowercase hex digit. -/
private def isLowerHex (s : String) : Bool :=
  !s.isEmpty && s.toList.all fun c => ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

/--
Whether a recorded executable digest is *shaped like* one: 64 lowercase hex characters, as
every tool that writes a SHA-256 spells it.

This is a well-formedness floor, not an attestation — nothing here checks that the digest is
of the binary that ran, and nothing can (CX-064). What it does rule out is the shape the
finding's fixture used: an arbitrary non-empty string, typed by a producer into a field
named `executable_sha256`, earning the tier that names a kernel. A record that spells its
digest some other way, uppercase included, falls to `labeled`, which is the safe direction:
it claims less than the record does, never more.
-/
def isExecutableDigest (s : String) : Bool :=
  let s := s.trimAscii.toString
  s.length == 64 && isLowerHex s

/-- Whether a recorded source revision is shaped like a git object name: 7 to 40 lowercase
hex characters, abbreviated or full. Same floor, same direction as `isExecutableDigest`: a
branch name, a tag, or a sentence is not a revision an executable can be bound to. -/
def isSourceRevision (s : String) : Bool :=
  let s := s.trimAscii.toString
  7 ≤ s.length && s.length ≤ 40 && isLowerHex s

/-- The run's identity record for `label`, if it wrote one.

At most one record per label survives parsing: `canonicalKernelIdentities` merges
identical duplicates and makes any disagreement a build error, so this `find?` cannot be
a choice between two answers. -/
def TrustComparator.identityFor? (cmp : TrustComparator) (label : String) :
    Option KernelReplayRecord :=
  cmp.kernelIdentities.find? fun r => r.label == label

/--
How much the run's record *says* about the checker it labels `label` — and no more than
that. Every tier here is a reading of a producer's own JSON: nothing on this page re-runs a
checker, fetches a source tree, or hashes a binary, so no tier is an attestation and none of
them licenses categorical prose about which program checked the proof (CX-064).

- `"named"` — the record binds a well-formed executable digest to a well-formed revision of
  the repository this fork knows that name by. The strongest thing a record can say about
  itself; the surfaces attribute it to the producing CI rather than asserting it.
- `"ci-built"` — the legacy `nanoda_replay`/`nanoda_ref` pair, with no `external_kernels`
  map able to redirect the label: the run's CI supplied the binary it built from the
  recorded revision, and the record's honesty rests on that CI rather than on a digest.
- `"bound"` — a well-formed digest and revision, but not a checker this fork knows by name
  (or a recorded repository that is not the canonical one). A program is identified; which
  program it *is* is not this site's to say.
- `"labeled"` — a label, at most a separately typed revision, and nothing binding either
  to what ran. **Also where a malformed identity record lands**: a producer that typed
  something other than a digest into `executable_sha256` has bound nothing, and the tier
  says so rather than reading the field's name as its content.
-/
def TrustComparator.kernelIdentityTier (cmp : TrustComparator) (label : String) : String :=
  match cmp.identityFor? label with
  | Option.some rec =>
    if !isExecutableDigest rec.executableSha256 || !isSourceRevision rec.sourceCommit then
      "labeled"
    else
      match knownKernelRepos.find? fun p => p.1 == label with
      | Option.some (_, canonical) =>
        if normalizeRepoUrl rec.repository == normalizeRepoUrl canonical then "named" else "bound"
      | Option.none => "bound"
  | Option.none =>
    -- No identity record. The legacy pair is still the tier it always was: a replay the
    -- run's CI recorded beside the revision that CI built the checker from.
    if cmp.externalKernels.isEmpty && cmp.kernelIdentities.isEmpty
        && (knownKernelRepos.any fun p => p.1 == label)
        && !(cmp.recordedKernelRef label).isEmpty then "ci-built"
    else "labeled"

/-- Checkers whose replay this page may report *under the name the record gives them*: the
run recorded that they replayed, and their identity tier says the record binds that name to
something rather than typing it beside a label.

Not "assured" in the sense of attested. What earns a place here is a well-formed record, and
the copy that reads this attributes it to the run that wrote it — see `TrustPages`. -/
def TrustComparator.assuredKernels (cmp : TrustComparator) : Array String :=
  cmp.replayedKernels.filter fun k =>
    let tier := cmp.kernelIdentityTier k
    tier == "named" || tier == "ci-built"

/-- Replay claims this page must present as *unnamed* external checkers: the run says
something ran and accepted, and nothing says what. -/
def TrustComparator.unnamedReplayClaims (cmp : TrustComparator) : Array String :=
  cmp.replayedKernels.filter fun k => !(cmp.assuredKernels.contains k)

/--
Whether the run that produced this verdict **recorded** a nanoda replay in a form this site
is willing to repeat under that name.

Two things must hold, and neither implies the other. The run must have recorded the
replay (`nanoda_replay`, or the `nanoda` entry of its kernel map) — an artifact that
records nothing about its run reads as `false`, because under-claiming a replay that may
have happened is a presentation defect while claiming one that did not is a false
assertion about a dated verification. And the record must bind the label to something: a
comparator configuration may point the key `nanoda` at any command, so a label alone is
not the kernel. See `kernelIdentityTier`.

What it is **not** is evidence that nanoda ran. It is a reading of the producing run's own
record, and every surface that consumes it says so in those terms (CX-064).
-/
def TrustComparator.replayedWithNanoda (cmp : TrustComparator) : Bool :=
  cmp.recordedReplay? "nanoda" == some true &&
    (let tier := cmp.kernelIdentityTier "nanoda"; tier == "named" || tier == "ci-built")

/-- Whether the status artifact carries the nanoda run-evidence field at all. `false` ⇒
legacy artifact: the page says the replay is *unrecorded*, not that it did not happen. -/
def TrustComparator.nanodaReplayRecorded (cmp : TrustComparator) : Bool :=
  (cmp.recordedReplay? "nanoda").isSome

/--
Disagreement between the current comparator configuration and the linked run's record,
for one kernel.

`some true` ⇒ the configuration now enables the replay but the run did not perform one;
`some false` ⇒ the run performed one but the configuration no longer enables it. Either
way the configuration has changed since the verdict was produced, and the page says so
rather than silently adopting one side. `none` ⇒ they agree, or the run recorded nothing
to disagree with.

A configuration that migrated `enable_nanoda` to an `external_kernels` entry is not
drift, because `configuredKernels` reads both spellings.
-/
def TrustComparator.kernelConfigDrift? (cmp : TrustComparator) (kernel : String) :
    Option Bool :=
  match cmp.recordedReplay? kernel with
  | Option.some replayed =>
    let configured := cmp.configuredKernels.contains kernel
    if replayed == configured then Option.none else Option.some configured
  | Option.none => Option.none

/-- `kernelConfigDrift?` for nanoda, the kernel every current consumer configures. -/
def TrustComparator.nanodaConfigDrift? (cmp : TrustComparator) : Option Bool :=
  cmp.kernelConfigDrift? "nanoda"

/-! ### Content binding -/

/-- Displayed comparator artifacts whose bytes this build verified against a SHA-256
recorded in the status artifact. -/
def TrustComparator.contentBound (cmp : TrustComparator) : List String :=
  (if !cmp.challengeSource.isEmpty && !cmp.challengeSha256.isEmpty then ["the claim"] else []) ++
  (if !cmp.solutionSource.isEmpty && !cmp.solutionSha256.isEmpty then ["the solution"] else []) ++
  (if !cmp.configJson.isEmpty && !cmp.configSha256.isEmpty then ["the configuration"] else [])

/-- Displayed comparator artifacts tied to the verdict by name and path shape only,
because the status artifact records no digest for them. -/
def TrustComparator.contentUnbound (cmp : TrustComparator) : List String :=
  (if !cmp.challengeSource.isEmpty && cmp.challengeSha256.isEmpty then ["the claim"] else []) ++
  (if !cmp.solutionSource.isEmpty && cmp.solutionSha256.isEmpty then ["the solution"] else []) ++
  (if !cmp.configJson.isEmpty && cmp.configSha256.isEmpty then ["the configuration"] else [])

/-- The axioms every kernel-checked Mathlib development is expected to use.
Single-sourced in `Informal.AxiomAudit` (which computes footprints); re-exported
here so the metadata-page badges keep their existing spelling. -/
def standardAxioms : List String := Informal.AxiomAudit.standardAxioms

/-- The axioms of `names` that are *not* one of the three standard ones. -/
def nonstandardAxioms (names : List String) : List String :=
  Informal.AxiomAudit.nonstandardAxioms names

/-!
## Build-time JSON syntax highlighting

A tiny, total JSON tokenizer used to render the embedded comparator configuration on
the comparator evidence page. It reuses the shared Lean code-token classes
(`.hl.lean .const` for object keys, `.literal.string` / `.literal.number` for scalar
values, `.keyword` for `true`/`false`/`null`) so every color comes from the existing
`--verso-code-*` variables — no new color token, both themes for free. It never
fails: any character that does not begin a recognized token is emitted as base text,
so malformed input degrades to (escaped) plain text rather than throwing.
-/

open Verso.Output.Html in
/-- Tokenize a (pretty-printed) JSON string into themed token spans. Result is the
inner markup to wrap in `<code class="hl lean">`. -/
def highlightJsonHtml (src : String) : Output.Html := Id.run do
  let cs := src.toList.toArray
  let n := cs.size
  let mut out : Array Output.Html := #[]
  let mut plain : String := ""
  let mut i : Nat := 0
  while i < n do
    let c := cs[i]!
    if c == '"' then
      if !plain.isEmpty then out := out.push (.text true plain); plain := ""
      -- String literal (keys and string values). Track escapes so an escaped quote
      -- does not close the string early.
      let mut j := i + 1
      let mut str : String := "\""
      let mut closed := false
      while j < n && !closed do
        let d := cs[j]!
        if d == '\\' && j + 1 < n then
          str := (str.push d).push cs[j+1]!
          j := j + 2
        else if d == '"' then
          str := str.push d
          j := j + 1
          closed := true
        else
          str := str.push d
          j := j + 1
      -- Object key iff the next non-whitespace character is a colon.
      let mut k := j
      while k < n && (cs[k]!).isWhitespace do k := k + 1
      let isKey := k < n && cs[k]! == ':'
      let cls := if isKey then "const" else "literal string"
      out := out.push (.tag "span" #[("class", cls)] (.text true str))
      i := j
    else if c.isDigit || (c == '-' && i + 1 < n && (cs[i+1]!).isDigit) then
      if !plain.isEmpty then out := out.push (.text true plain); plain := ""
      let mut j := i + 1
      while j < n &&
          (let d := cs[j]!; d.isDigit || d == '.' || d == 'e' || d == 'E' || d == '+' || d == '-') do
        j := j + 1
      let mut num : String := ""
      for p in [i:j] do num := num.push cs[p]!
      out := out.push (.tag "span" #[("class", "literal number")] (.text true num))
      i := j
    else if c.isAlpha then
      if !plain.isEmpty then out := out.push (.text true plain); plain := ""
      let mut j := i
      while j < n && (cs[j]!).isAlpha do j := j + 1
      let mut word : String := ""
      for p in [i:j] do word := word.push cs[p]!
      if word == "true" || word == "false" || word == "null" then
        out := out.push (.tag "span" #[("class", "keyword")] (.text true word))
      else
        out := out.push (.text true word)
      i := j
    else
      plain := plain.push c
      i := i + 1
  if !plain.isEmpty then out := out.push (.text true plain)
  return .seq out

/-!
## Comparator-source enrichment

At elaboration time the full environment (project + Mathlib) is available, so we can
syntax-highlight the comparator's config/Challenge/Solution blocks and resolve their
outbound source links (GitHub blob at the pinned commit + Lean-playground). Everything
here probes-and-degrades — a missing file or git remote yields empty fields, never a
build error.
-/

/-- Derive the `raw.githubusercontent.com` URL for a GitHub *blob* URL (splitting on
the first `/blob/` so a path segment literally named `blob` is preserved). `none` for
a non-GitHub URL. -/
def blobToRawGitHubUrl? (blob : String) : Option String :=
  let gh := "https://github.com/"
  if blob.startsWith gh then
    match ((blob.drop gh.length).toString).splitOn "/blob/" with
    | ownerRepo :: rest =>
      some s!"https://raw.githubusercontent.com/{ownerRepo}/{String.intercalate "/blob/" rest}"
    | [] => Option.none
  else Option.none

/-- The repository URL (everything before the first `/blob/`) of a GitHub *blob* URL, e.g.
`https://github.com/o/r/blob/<sha>/Path.lean` ↦ `https://github.com/o/r`. Splits on the
first `/blob/` only (so a path segment literally named `blob` is preserved). `none` for a
non-GitHub URL or one with no `/blob/` segment → degrade. -/
def blobToRepoUrl? (blob : String) : Option String :=
  let gh := "https://github.com/"
  if blob.startsWith gh then
    match ((blob.drop gh.length).toString).splitOn "/blob/" with
    | ownerRepo :: _ :: _ => some s!"https://github.com/{ownerRepo}"
    | _ => Option.none
  else Option.none

/-- The repo-root-relative path (everything after `/blob/<commit>/`) of a GitHub *blob* URL,
e.g. `https://github.com/o/r/blob/<sha>/Path/File.lean` ↦ `Path/File.lean`. Splits on the
first `/blob/` only, so a path segment literally named `blob` survives. `none` for a
non-GitHub URL or one with no `/blob/` segment → degrade. -/
def blobToRepoRelPath? (blob : String) : Option String :=
  let gh := "https://github.com/"
  if blob.startsWith gh then
    match ((blob.drop gh.length).toString).splitOn "/blob/" with
    | _ownerRepo :: rest@(_ :: _) =>
      -- `rest` rejoined is `<commit>/<path…>`; drop the leading commit segment.
      match (String.intercalate "/blob/" rest).splitOn "/" with
      | _commit :: pathSegs@(_ :: _) => some (String.intercalate "/" pathSegs)
      | _ => Option.none
    | _ => Option.none
  else Option.none

/-- The tier-3 "reproduce it yourself" shell commands, as a list of lines, derived purely
from a `TrustComparator` (unit-testable, total). Degrades with the data: the project-clone
line appears only with a `repoUrl`, the `--branch` flag only with a `toolRef`, and the final
`comparator` run line only with a `configArgPath` (otherwise the reproduce section points the
reader at the project README rather than guessing the config path). The tool is always cloned
as `comparator-tool` — a distinct directory that cannot collide with a project's own in-repo
`comparator/` folder (mirroring the CI checkout). These are *reproduction instructions*, so
they are the one place the current configuration legitimately drives the prose: when the
config enables the independent nanoda kernel through `enable_nanoda`, the flow clones and builds
`nanoda_lib` — describing what a run from this configuration does, not what the linked run did
(`replayedWithNanoda`) — and points the comparator at it via `COMPARATOR_NANODA`; the relative
`../nanoda_lib/…` path resolves
because the run line first cd's into the project directory, a sibling of the two clones.

An `external_kernels` entry gets a pointer to the comparator's own documentation instead,
whatever it is labeled: that mechanism carries its own command vector in the
configuration this page displays, and inventing a build for it would describe a different
run. -/
def reproCommands (cmp : TrustComparator) : List String :=
  let branchFlag := if cmp.toolRef.isEmpty then "" else s!"--branch {cmp.toolRef} "
  let cloneTool := s!"git clone {branchFlag}https://github.com/leanprover/comparator.git comparator-tool"
  -- A tag is mutable. When CI recorded the exact commit it resolved to, check that
  -- out so the reader runs the same tool, not "whatever the tag points at today".
  let pinTool :=
    if cmp.toolSha.isEmpty then []
    else [s!"(cd comparator-tool && git checkout {cmp.toolSha})"]
  -- The tool reads the project's oleans, which carry a compiler stamp, so the run that
  -- produced this verdict rebuilt the tool on the project's toolchain. Building it on
  -- the tool's own toolchain instead is a different program checking different bytes.
  let pinToolchain :=
    if cmp.toolToolchain.isEmpty then []
    else [s!"printf '%s\\n' '{cmp.toolToolchain}' > comparator-tool/lean-toolchain"]
  let buildTool := "(cd comparator-tool && lake build lean4export comparator)"
  -- The nanoda lines describe the `enable_nanoda` mechanism, where the comparator runs a
  -- binary it is handed through the environment. A configuration that instead lists the
  -- checker in `external_kernels` carries its own command vector, which is displayed with
  -- the configuration — inventing a build for it would be describing a different run.
  let labeledExternally := fun (k : String) => cmp.externalKernels.any fun e => e.1 == k
  let nanodaBuild :=
    if cmp.enableNanoda && !labeledExternally "nanoda" then
      -- Same reasoning for the independent kernel: CI pins nanoda by revision, so the
      -- reproduce flow must too, or it is checking a different program.
      let nanodaRef := cmp.recordedKernelRef "nanoda"
      ["git clone https://github.com/ammkrn/nanoda_lib.git"] ++
      (if nanodaRef.isEmpty then []
       else [s!"(cd nanoda_lib && git checkout {nanodaRef})"]) ++
      ["(cd nanoda_lib && cargo build --release --locked)"]
    else []
  let otherKernels :=
    cmp.externalKernels.toList.map fun e =>
      s!"# this configuration also runs an external checker labeled {e.1} — see the \
         comparator README for building it; the command it runs is in the configuration \
         shown below"
  let nanodaEnv :=
    if cmp.enableNanoda && !labeledExternally "nanoda" then
      "COMPARATOR_NANODA=../nanoda_lib/target/release/nanoda_bin " else ""
  -- The run's own record of what it checked out wins over what this build's checkout
  -- happens to point at.
  let recordedRepo :=
    if cmp.repository.isEmpty then ""
    else if cmp.repository.startsWith "http" || cmp.repository.startsWith "git@" then cmp.repository
    else s!"https://github.com/{cmp.repository}"
  let cloneUrl := if recordedRepo.isEmpty then cmp.repoUrl else recordedRepo
  let projectClone := if cloneUrl.isEmpty then [] else [s!"git clone {cloneUrl}"]
  let projectDir :=
    if cloneUrl.isEmpty then "path/to/your/project"
    else
      let last := ((cloneUrl.splitOn "/").getLast?).getD "your-project"
      if last.endsWith ".git" then (last.dropEnd 4).toString else last
  -- The verifiers are pinned by revision; the subject must be too, or the same tools check
  -- different bytes as soon as the default branch moves.
  let projectPin :=
    if cmp.commit.isEmpty || cloneUrl.isEmpty then []
    else [s!"(cd {projectDir} && git checkout {cmp.commit})"]
  let runLines :=
    if cmp.configArgPath.isEmpty then []
    else [s!"cd {projectDir}", s!"{nanodaEnv}lake env ../comparator-tool/.lake/build/bin/comparator {cmp.configArgPath}"]
  projectClone ++ projectPin ++ [cloneTool] ++ pinTool ++ pinToolchain ++ [buildTool]
    ++ nanodaBuild ++ otherKernels ++ runLines

/-- Absolute path of an option-configured path (relative to the build CWD). -/
private def absOptionPath (workspaceRoot : System.FilePath) (p : String) : System.FilePath :=
  let fp := System.FilePath.mk p
  if fp.isAbsolute then fp else workspaceRoot / p

open Informal in
/-- Highlight one comparator's config/Challenge/Solution blocks and resolve its
source links, given the file paths behind them (relative to the build CWD).
Shared by the single-pair path and each multi-config topic. Runs in `CoreM`
(environment + git available at elaboration); every enrichment degrades to empty
rather than failing. -/
def enrichComparatorSources (opts : Lean.Options) (workspaceRoot : System.FilePath)
    (cmp0 : TrustComparator) (chalPath solPath cfgPath : String) : Lean.CoreM TrustComparator := do
  let mut cmp := cmp0
  if !cmp.configJson.isEmpty then
    cmp := { cmp with configHtml := (highlightJsonHtml cmp.configJson).asString }
  if !cmp.challengeSource.isEmpty then
    if let some html ← Informal.highlightModuleSourceHtml? cmp.challengeSource then
      cmp := { cmp with challengeHtml := html }
  if !cmp.solutionSource.isEmpty then
    if let some html ← Informal.highlightModuleSourceHtml? cmp.solutionSource then
      cmp := { cmp with solutionHtml := html }
  -- Blob URLs via the shared source-link builder (auto GitHub when the file is in a
  -- checkout with a GitHub `origin`; degrades to none), resolved against the checkout
  -- as it stands *here* rather than at emission. Deliberate, and the opposite choice
  -- from the declaration registry's: the blocks above hold the Challenge/Solution/config
  -- bytes read a few lines earlier, and these links have to name the revision those
  -- bytes came from. Those files are not Lean modules, so nothing invalidates this
  -- capture when they change; re-dating the link at emission would point a reader at
  -- bytes other than the ones displayed beside it.
  if !chalPath.isEmpty then
    if let some blob ← liftM <| sourceLinkHrefNow? opts workspaceRoot none
        (some (absOptionPath workspaceRoot chalPath)) none then
      cmp := { cmp with githubChallengeUrl := blob }
      if let some raw := blobToRawGitHubUrl? blob then
        cmp := { cmp with
          playgroundUrl :=
            s!"https://live.lean-lang.org/#project={playgroundMathlibProjectId}&url={System.Uri.escapeUri raw}" }
  if !solPath.isEmpty then
    if let some blob ← liftM <| sourceLinkHrefNow? opts workspaceRoot none
        (some (absOptionPath workspaceRoot solPath)) none then
      cmp := { cmp with githubSolutionUrl := blob }
  if !cfgPath.isEmpty then
    if let some blob ← liftM <| sourceLinkHrefNow? opts workspaceRoot none
        (some (absOptionPath workspaceRoot cfgPath)) none then
      cmp := { cmp with githubConfigUrl := blob }
  -- Project repo URL for the tier-3 "clone the project" step: the repository of the first
  -- blob we managed to resolve. Degrades to empty when no GitHub remote is available.
  if let some blob := [cmp.githubChallengeUrl, cmp.githubSolutionUrl, cmp.githubConfigUrl].find?
      (fun u => !u.isEmpty) then
    if let some repo := blobToRepoUrl? blob then
      cmp := { cmp with repoUrl := repo }
  -- Config arg path for the tier-3 run line: prefer the status JSON's own `config` (already
  -- parsed by `ofJson`); otherwise recover it from the config blob's repo-root path.
  if cmp.configArgPath.isEmpty && !cmp.githubConfigUrl.isEmpty then
    if let some rel := blobToRepoRelPath? cmp.githubConfigUrl then
      cmp := { cmp with configArgPath := rel }
  return cmp

def enrichTrustData (opts : Lean.Options) (trust : TrustData) : Lean.CoreM TrustData := do
  let workspaceRoot ← Informal.workspaceRoot
  let mut trust := trust
  -- Single-pair comparator: highlight the config/Challenge blocks and resolve the
  -- source links from the option paths. (Multi-config topics are enriched at build
  -- time in `elabComparatorTopics?`, which knows each topic's own paths.)
  if let some cmp := trust.comparator then
    let chalPath := opts.get verso.blueprint.trust.challengeFile.name
      verso.blueprint.trust.challengeFile.defValue
    let solPath := opts.get verso.blueprint.trust.solutionFile.name
      verso.blueprint.trust.solutionFile.defValue
    let cfgPath := opts.get verso.blueprint.trust.comparatorConfig.name
      verso.blueprint.trust.comparatorConfig.defValue
    let cmp ← enrichComparatorSources opts workspaceRoot cmp chalPath solPath cfgPath
    trust := { trust with comparator := some cmp }
  return trust

/--
One trust badge. Reuses the dashboard's `.bp_summary_badge` classes (`variant`
is one of `""`/`success`/`warn`/`error`/`accent`); `title?` becomes a tooltip.
When `href?` is set the badge renders as an `<a>` linking to a page; otherwise it is
a plain `<span>`.
-/
def trustBadgeHtml (text : String) (variant : String := "")
    (title? : Option String := Option.none) (href? : Option String := Option.none) :
    Output.Html :=
  let className :=
    if variant.isEmpty then "bp_summary_badge"
    else s!"bp_summary_badge bp_summary_badge_{variant}"
  let attrs := #[("class", className)]
  let attrs :=
    match title? with
    | Option.some t => attrs.push ("title", t)
    | Option.none => attrs
  match href? with
  | Option.some href => .tag "a" (attrs.push ("href", href)) (.text true text)
  | Option.none => .tag "span" attrs (.text true text)

/-- One titled section of a trust page. `id?` gives the section a link target, for the
one case that needs one: the reading list points back at the rendered Challenge source
where the chain's own declarations are printed. -/
def trustSection (title : String) (body : Output.Html) (id? : Option String := Option.none) :
    Output.Html :=
  let attrs := #[("class", "bp_trust_section")]
  let attrs := match id? with
    | Option.some anchor => attrs.push ("id", anchor)
    | Option.none => attrs
  .tag "section" attrs
    (.seq #[{{ <h2 class="bp_trust_section_title">{{.text true title}}</h2> }}, body])

/-- A quiet outbound link. -/
def trustOutLink (href label : String) : Output.Html :=
  {{ <a class="bp_trust_out_link" href={{href}} target="_blank" rel="noopener">{{.text true label}}</a> }}

/-- The date part (`YYYY-MM-DD`) of an ISO-8601 timestamp; the whole string when there
is no `T` separator. -/
private def isoDate (s : String) : String := (s.splitOn "T").headD s

/-! ### Transcribed upstream verdicts

A project may present a verdict it did not produce: the subject repository ran the
comparator, and this site transcribes what that run reported. The `reported-upstream`
status is the vocabulary for exactly that. It is not a weaker `verified` — it is a
different kind of claim, so it never renders in the success tier, never counts towards a
success aggregate, and never carries a date with `verified_at` semantics. Its only date
is `reported_at`, the moment the *upstream* record was made, and it renders no date at
all when that is absent.
-/

/-- Whether this verdict is a transcription of an upstream record rather than a run this
project's CI performed. -/
def TrustComparator.isReportedUpstream (cmp : TrustComparator) : Bool :=
  cmp.status == "reported-upstream"

/-- Whether this verdict is a comparator **success**: the one status that certifies
anything.

Named once because more than one surface turns on it and they must not disagree about what
counts. `configured` has not run, `reported-upstream` is somebody else's record transcribed,
and a failure is a failure; none of the three certifies a claim, so none of them may carry a
success badge or bind a registration to one (CX-065). -/
def TrustComparator.isSuccessVerdict (cmp : TrustComparator) : Bool :=
  cmp.status == "verified"

/-- Who published the transcribed record, for the label and tooltip; the generic
"the subject repository" when the artifact does not say. -/
def TrustComparator.reportedSourceName (cmp : TrustComparator) : String :=
  if cmp.reportedSource.isEmpty then "the subject repository" else cmp.reportedSource

/-- The one sentence every `reported-upstream` surface says: what the verdict is, and
what this site did not do. -/
def TrustComparator.reportedUpstreamNote (cmp : TrustComparator) : String :=
  s!"Transcribed from records published by {cmp.reportedSourceName}; this site's CI did \
     not run the comparator on it, and nothing here re-checked the claim."

/-! ### Verifier currency

A pinned verifier is reproducible and ages; the page has to say which of the two it is
looking at. `Informal.KernelAdvisories` owns the table and the three-way judgement, and
this section is the adapter: it decides *which* verifier builds a record actually
recorded, hands each to the pure verdict function, and writes the one sentence the
surfaces render.

Two rules shape what appears at all. A checker the *configuration* enables but the run
never mentioned has no build to assess, and the drift notes already say so, so it gets no
row — the currency block reports on what ran, not on what would run next. And a label the
record does not bind to a program (CX-064) yields `unknown` whatever revision is typed
beside it, because the revision is not evidence about the executable.

Like the digest cross-checks below, the assessment runs at elaboration, so Lake caches it
with the module's `.olean`: editing only a consumer's advisory-table override changes no
Lean input, and a warm rebuild can reuse the previous verdicts. A cold build — CI, or any
build after the document module re-elaborates — recomputes them, which is the build that
publishes the site.
-/

/-- The date the record is *of*: a run this site's CI performed, or the date the upstream
record it transcribes was made. Empty ⇒ the record carries no date. -/
def TrustComparator.recordDate (cmp : TrustComparator) : String :=
  if cmp.isReportedUpstream then cmp.reportedAt else cmp.verifiedAt

/-- Checkers whose *run record* names something assessable: a replay, a revision, or an
identity record. A checker the configuration merely enables is excluded — there is no
build to be current or stale. -/
def TrustComparator.currencyKernels (cmp : TrustComparator) : Array String :=
  cmp.mentionedKernels.filter fun k =>
    (cmp.recordedReplay? k).isSome || !(cmp.recordedKernelRef k).isEmpty
      || (cmp.identityFor? k).isSome

/-- Whether a checker's identity tier lets its recorded revision stand for the program
that ran: a full identity binding, or the legacy pair no configuration can redirect. -/
def TrustComparator.currencyAssessable (cmp : TrustComparator) (label : String) : Bool :=
  let tier := cmp.kernelIdentityTier label
  tier == "named" || tier == "ci-built"

open Informal.KernelAdvisories in
/-- How to name a tool in the currency copy. -/
private def currencyToolPhrase (tool : String) : String :=
  if tool == "lean4" then "the Lean toolchain the comparator was built on" else tool

open Informal.KernelAdvisories in
/-- The dates in a stale verdict's advisories, as prose: what the revision predates. -/
private def currencyFixDates (as : Assessment) : String :=
  let dates := (as.outcomes.filter (·.state == "affected")).filterMap fun o =>
    if o.advisory.advisoryDate.isEmpty then none else some o.advisory.advisoryDate
  let dates := dates.foldl (init := #[]) fun acc d => if acc.contains d then acc else acc.push d
  String.intercalate " and " dates.toList

open Informal.KernelAdvisories in
/--
The one sentence a currency row says, given what the record is and what the table
resolved. Kept here rather than in the renderer so the copy is unit-testable and cannot
disagree with the verdict beside it.

`replayed?` shapes the stale case only, and shapes it in the direction of claiming less:
a record that never said the replay happened has no second-kernel assurance to call
dated, and the sentence says that instead.
-/
def currencyDetail (tool : String) (revision recordDate advisoriesUpdated : String)
    (replayed? : Option Bool) (as : Assessment) : String :=
  let who := currencyToolPhrase tool
  let isToolchain := tool == "lean4"
  let date := dateOnly recordDate
  let fixes :=
    let d := currencyFixDates as
    if d.isEmpty then "the fixes below" else s!"the fixes below (dated {d})"
  match as.verdict with
  | .stale =>
    let lead := if date.isEmpty then "This verdict" else s!"This verdict, of {date},"
    if isToolchain then
      s!"{lead} was produced by a comparator built on {revision} — a Lean release \
         predating {fixes}. The kernel that accepted this proof is the one those fixes \
         repaired."
    else if replayed? == some true then
      s!"{lead} recorded a replay by {who} {revision}, a revision predating {fixes}. \
         Treat that second-kernel assurance as dated."
    else
      s!"{lead} pins {who} at {revision}, a revision predating {fixes}. The record does \
         not say a replay happened, so nothing here rests on it — and the pin is not \
         current either."
  | .current =>
    if isToolchain then
      s!"The comparator was built on {revision}, at or above every Lean release this \
         site's advisory table records a kernel-soundness fix in."
    else
      -- The verdict is about the revision the record names, not about the program that
      -- ran: nothing here binds the two beyond the producing CI's own say-so (CX-064).
      s!"Per the recorded revision, {who} {revision} is one this site's advisory table \
         resolves as carrying every fix it records for it. That is a reading of the run's \
         record, not a check of the binary it invoked."
  | .unknown =>
    match as.reason with
    | "table-older-than-record" =>
      s!"This verdict is newer than this site's advisory table, last revised \
         {advisoriesUpdated}, so no currency claim is made for {who}: an advisory \
         published since would not appear here. Against what the table does record, \
         {revision} carries every fix."
    | "identity-unbound" =>
      s!"Nothing in this record binds the label {tool} to a program — no revision and \
         executable digest of the shape those fields are for — so there is no build whose \
         currency could be assessed. That is a gap in the record, not a finding about the \
         checker."
    | "no-revision" =>
      s!"The record names {who} but no revision of it, so there is nothing to assess \
         against the advisories below."
    | "symbolic-revision" =>
      s!"The record names {who} at '{revision}', a moving reference rather than a \
         revision: what it pointed at when the run happened is not recoverable here, so \
         currency cannot be assessed."
    | "incomparable-revision" =>
      s!"The record names {who} as '{revision}', which this site's table cannot order \
         against a release — a nightly or a branch build — so currency cannot be assessed."
    | "no-advisories" =>
      s!"This site's advisory table records nothing about {tool}, so it can neither \
         confirm nor deny that the build behind this verdict is current."
    | _ =>
      s!"{revision} is not a revision this site's table resolved for {tool}, and the \
         record's date settles nothing either way. Currency unknown — which is not a \
         finding of staleness."

open Informal.KernelAdvisories in
/-- One rendered currency row from a pure assessment. -/
private def currencyRow (table : Table) (tool revision recordDate : String)
    (replayed? : Option Bool) (as : Assessment) : VerifierCurrency :=
  { tool
    verdict := as.verdict.name
    revision
    reason := as.reason
    detail := currencyDetail tool revision recordDate table.advisoriesUpdated replayed? as
    advisoriesUpdated := table.advisoriesUpdated
    tableStale := as.tableStale
    advisories := as.outcomes.map fun o =>
      { summary := o.advisory.summary
        advisoryDate := o.advisory.advisoryDate
        url := o.advisory.url
        state := o.state
        ancestry := o.advisory.fix.ancestry } }

open Informal.KernelAdvisories in
/--
Currency of every verifier build this verdict's record names: the Lean toolchain the
comparator was rebuilt on, then each checker the run mentioned.

Pure, so the whole matrix is testable without a site. Empty ⇒ the record named no build,
and the surfaces say that in prose rather than rendering silence as a clean bill.
-/
def TrustComparator.currencyRows (cmp : TrustComparator) (table : Table) :
    Array VerifierCurrency :=
  let recordDate := cmp.recordDate
  let toolchainRow : Array VerifierCurrency :=
    if cmp.toolToolchain.isEmpty then #[]
    else
      let input : Input := {
        tool := "lean4", revision := cmp.toolToolchain, kind := .version,
        identityAssessable := true, recordDate }
      #[currencyRow table "lean4" cmp.toolToolchain recordDate none (currencyVerdict table input)]
  let kernelRows : Array VerifierCurrency := cmp.currencyKernels.map fun k =>
    let revision := cmp.recordedKernelRef k
    let input : Input := {
      tool := k, revision, kind := .commit,
      identityAssessable := cmp.currencyAssessable k, recordDate }
    currencyRow table k revision recordDate (cmp.recordedReplay? k) (currencyVerdict table input)
  toolchainRow ++ kernelRows

open Informal.KernelAdvisories in
/-- The verdict with its currency rows attached. -/
def TrustComparator.withCurrency (cmp : TrustComparator) (table : Table) :
    TrustComparator :=
  { cmp with currency := cmp.currencyRows table }

/-- The self-aging clause every currency surface publishes. A verdict read from a
hand-maintained table is a claim about the table, and this is the sentence that says so.
-/
def currencyAgingClause (advisoriesUpdated : String) : String :=
  if advisoriesUpdated.isEmpty then
    "This site's advisory table records no revision date, so nothing bounds what it knows."
  else
    s!"Advisory table last updated {advisoriesUpdated} — a newer advisory would not appear \
       here."

/--
The comparator verdict badge, linking to the standalone `comparator/` page.

The label is deliberately **"comparator: CI-verified ⟨date⟩"**, not "verified". The
badge is a read-back of a JSON artifact a past CI run wrote; nothing is re-checked
when this page is built, and a hand-edited artifact would render the same pill. The
wording therefore names the source (CI) and the moment (the date) rather than
asserting a present-tense property of the site.

A `reported-upstream` record names a different source — someone else's CI — and so gets
a neutral badge and, at most, the upstream record's own date.
-/
def trustComparatorBadge (cmp : TrustComparator) : Output.Html :=
  let theoremsTitle :=
    if cmp.theoremNames.isEmpty then ""
    else s!"; certified: {String.intercalate ", " cmp.theoremNames}"
  if cmp.isSuccessVerdict then
    let label :=
      if cmp.verifiedAt.isEmpty then "comparator: CI-verified"
      else s!"comparator: CI-verified {isoDate cmp.verifiedAt}"
    trustBadgeHtml label "success"
      (Option.some
        s!"Recorded by the project's CI run; this page reads that run's artifact back rather \
           than re-running the check{theoremsTitle}")
      (Option.some Informal.NodeRoute.comparatorHref)
  else if cmp.status == "configured" then
    let title := if cmp.note.isEmpty then s!"Comparator configured{theoremsTitle}" else cmp.note
    trustBadgeHtml "comparator: configured — not yet run" "warn" (Option.some title)
      (Option.some Informal.NodeRoute.comparatorHref)
  else if cmp.isReportedUpstream then
    -- Neutral, not success and not warning: the record is someone else's, which is
    -- information about provenance rather than a fault. The date, when there is one, is
    -- the upstream record's own.
    let label :=
      if cmp.reportedAt.isEmpty then "comparator: reported upstream"
      else s!"comparator: reported upstream {isoDate cmp.reportedAt}"
    trustBadgeHtml label ""
      (Option.some s!"{cmp.reportedUpstreamNote}{theoremsTitle}")
      (Option.some Informal.NodeRoute.comparatorHref)
  else
    trustBadgeHtml s!"comparator: {cmp.status}" (href? := Option.some Informal.NodeRoute.comparatorHref)

/-- The scope line under the badge row: how much of the site the comparator verdict
actually covers. Omitted when no comparator names any theorem. -/
def trustScopeHtml (cmp? : Option TrustComparator) (theoremLikeTotal : Option Nat) :
    Output.Html :=
  match cmp? with
  | Option.none => .empty
  | Option.some cmp =>
    if cmp.theoremNames.isEmpty then .empty
    else
      let k := cmp.theoremNames.length
      let noun := if k == 1 then "theorem" else "theorems"
      -- A transcribed verdict reports; it does not certify.
      let verb := if cmp.isReportedUpstream then "reported verified upstream:" else "certifies"
      let text :=
        match theoremLikeTotal with
        | Option.some n => s!"{verb} {k} {noun} of {n}"
        | Option.none => s!"{verb} {k} named {noun}"
      {{ <span class="bp_trust_strip_scope">{{.text true text}}</span> }}

/-- What the topics that certified nothing actually are, in their own vocabulary rather
than in the certified sentence's.

Named once for the same reason as `TrustComparator.isSuccessVerdict`: the dashboard strip's
aggregate scope line and the comparator page's headline describe the same set of topics, and
they must not describe it two different ways. -/
def uncertifiedStatusPhrase (others : List ComparatorTopic) : String :=
  let phrases :=
    (if others.any (·.comparator.status == "configured") then ["configured but not yet run"]
     else []) ++
    (if others.any (·.comparator.isReportedUpstream) then ["reported verified upstream"]
     else []) ++
    (if others.any (fun t => t.comparator.status != "configured" && !t.comparator.isReportedUpstream)
     then ["recorded with another status"] else [])
  if phrases.isEmpty then "not certified here" else String.intercalate " or " phrases

/-- Aggregate scope line for the multi-config trust surface: certified theorems across the
comparator topics, out of the site's theorem-like total, and how many comparator configs did
the certifying.

**Counts `verified` topics only**, like the badge beside it and like the comparator page's
headline. It used to sum the theorem names of every topic whatever its status, so a dashboard
whose configs had all merely been *configured* — or whose verdicts had been transcribed from
another repository's records — told a reader on the site's most-read page that it certified
that many theorems, directly beside a badge reading `0/m configs verified`. The other topics
are still counted, in a clause that says what they are.

The every-config-verified sentence is unchanged to the byte: that is every consumer that was
telling the truth already. -/
def trustAggregateScopeHtml (comparators : List ComparatorTopic)
    (theoremLikeTotal : Option Nat) : Output.Html :=
  if comparators.isEmpty then .empty
  else
    let m := comparators.length
    let verified := comparators.filter (·.comparator.isSuccessVerdict)
    let others := comparators.filter (fun t => !t.comparator.isSuccessVerdict)
    let v := verified.length
    let k := (verified.map (·.comparator.theoremNames.length)).foldl (· + ·) 0
    let j := (others.map (·.comparator.theoremNames.length)).foldl (· + ·) 0
    let noun := if k == 1 then "theorem" else "theorems"
    let jNoun := if j == 1 then "theorem" else "theorems"
    let jVerb := if j == 1 then "is" else "are"
    let cfgNoun := if m == 1 then "comparator config" else "comparator configs"
    let text :=
      if others.isEmpty then
        match theoremLikeTotal with
        | Option.some n => s!"certifies {k} {noun} of {n} across {m} {cfgNoun}"
        | Option.none => s!"certifies {k} named {noun} across {m} {cfgNoun}"
      else
        let lead :=
          if k == 0 then
            match theoremLikeTotal with
            | Option.some n => s!"certifies no theorems of {n}"
            | Option.none => "certifies no theorems"
          else
            match theoremLikeTotal with
            | Option.some n => s!"certifies {k} {noun} of {n} across {v} of {m} {cfgNoun}"
            | Option.none => s!"certifies {k} named {noun} across {v} of {m} {cfgNoun}"
        let tail :=
          if j == 0 then ""
          else if k == 0 then
            s!"; {m} {cfgNoun} name {j} {jNoun}, {uncertifiedStatusPhrase others}"
          else
            s!"; a further {j} {jNoun} {jVerb} {uncertifiedStatusPhrase others}"
        lead ++ tail
    {{ <span class="bp_trust_strip_scope">{{.text true text}}</span> }}

/-- The multi-config comparator badge: how many of the M configs are verified,
linking to the comparator page.

Only `verified` counts. A `configured` topic has not run, and a `reported-upstream` one
is a record this site transcribed rather than produced; neither is a verification that
happened here, so neither may push the badge to the success tier. -/
def trustAggregateComparatorBadge (comparators : List ComparatorTopic) : Output.Html :=
  let m := comparators.length
  let cfgNoun := if m == 1 then "config" else "configs"
  let verified := (comparators.filter (·.comparator.isSuccessVerdict)).length
  if verified == m then
    trustBadgeHtml s!"comparator: {m} {cfgNoun} verified" "success"
      (href? := Option.some Informal.NodeRoute.comparatorHref)
  else
    trustBadgeHtml s!"comparator: {verified}/{m} {cfgNoun} verified" "warn"
      (href? := Option.some Informal.NodeRoute.comparatorHref)

/-- Badges for the structural `uses`-graph gates the build already ran. The gate itself
lives in `Informal.GraphGate` (pre-emission); these badges report its verdict, which
until now was computed on the dashboard and then discarded. -/
def trustGraphBadges (checks? : Option Informal.GraphChecks.Results) : Array Output.Html :=
  match checks? with
  | Option.none => #[]
  | Option.some checks =>
    if checks.graphEmpty then #[]
    else Id.run do
      let mut out : Array Output.Html := #[]
      out := out.push <|
        if checks.acyclic.ok then
          trustBadgeHtml "graph: acyclic" "success"
            (Option.some
              s!"Build gate: the `uses` graph over {checks.acyclic.nodeCount} nodes and \
                 {checks.acyclic.edgeCount} edges has no dependency cycle.")
        else
          trustBadgeHtml "graph: cyclic" "error"
            (Option.some "Build gate: a dependency cycle was detected.")
      out := out.push <|
        if checks.connected.ok then
          trustBadgeHtml "graph: connected" "success"
            (Option.some
              s!"Build gate: all {checks.connected.nodeCount} nodes lie in one weakly-connected \
                 component — no orphaned material.")
        else
          trustBadgeHtml s!"graph: {checks.connected.componentCount} components" "warn"
            (Option.some
              s!"{checks.connected.stragglers.size} node(s) lie outside the main component. \
                 Reported, not gated (verso.blueprint.trust.requireConnected is false).")
      return out

/-- The axiom-audit badge. Rendered only when the audit found something to report —
a clean audit on an unconfigured consumer adds no badge, so nothing changes for
projects that never opted in. -/
def trustAuditBadge? (audit? : Option Informal.AxiomAudit.Summary) : Option Output.Html := do
  let audit ← audit?
  if !audit.ran then Option.none
  else if !audit.sorried.isEmpty then
    Option.some <|
      trustBadgeHtml s!"axiom audit: {audit.sorried.size} incomplete" "error"
        (Option.some
          s!"`Lean.collectAxioms` found `sorryAx` in the transitive closure of \
             {audit.sorried.size} of {audit.checked} audited declarations.")
  else if !audit.nonstandard.isEmpty then
    Option.some <|
      trustBadgeHtml s!"axiom audit: {audit.nonstandard.size} nonstandard" "warn"
        (Option.some
          s!"{audit.nonstandard.size} of {audit.checked} audited declarations depend on axioms \
             beyond propext, Classical.choice, and Quot.sound.")
  else
    Option.some <|
      trustBadgeHtml s!"axiom audit: {audit.checked} clean" "success"
        (Option.some
          s!"`Lean.collectAxioms` over {audit.checked} declarations: no `sorryAx`, no axioms \
             beyond propext, Classical.choice, and Quot.sound.")

/-! ### Registry records

A registration is provenance: somebody submitted a repository at a revision, and a registry
recorded that it did. The strip carries it only where the record is bound to a claim the
page presents — the record's challenge digest is the digest of a statement this site
displays, and the verifying run recorded that digest too. A repository match, or a digest
the verdict never recorded, has a card on the comparator page and no badge: a badge in the
trust row would read as a verdict about this site, which is exactly what a registration
is not.
-/

/-- The claim-level registry matches on this payload, across both comparator schemes.

`isClaimLevel` is re-checked here rather than trusted: `attachRegistry` attaches only bound
records to a comparator, and the badge is the one surface where being wrong about that
would read as a verdict. The check covers the record's origin as well as its basis, so a
payload from elsewhere carrying a probed record on a binding basis earns nothing here. -/
def TrustData.claimRegistryEntries (t : TrustData) : List RegistryEntry :=
  ((t.comparator.bind (·.registryEntry?)).toList
    ++ t.comparators.filterMap (·.comparator.registryEntry?)).filter RegistryEntry.isClaimLevel

/-- The project's repository, as the verifying run recorded it or as this checkout says.
Empty ⇒ this build cannot name its own repository, which is not the same as a mismatch. -/
def TrustData.projectRepoIdentity (t : TrustData) : String :=
  let ofCmp := fun (c : TrustComparator) =>
    if !c.repository.isEmpty then c.repository else c.repoUrl
  let candidates := (t.comparator.map ofCmp).toList ++ t.comparators.map (fun t => ofCmp t.comparator)
  (candidates.find? (fun s => !s.isEmpty)).getD ""

/-- The registry badge, for claim-bound records only.

Neutral tier deliberately: `success` is what this site's own CI verifying something looks
like, and a registration is a record somebody else kept. -/
def trustRegistryBadge? (t : TrustData) : Option Output.Html :=
  match t.claimRegistryEntries with
  | [] => Option.none
  | [e] =>
    Option.some <|
      trustBadgeHtml "registry: Palomar entry" ""
        (Option.some
          s!"{e.label} records the challenge this verdict certifies (match basis: \
             {e.matchBasis}). {Informal.Palomar.honestyNote}")
        (Option.some Informal.NodeRoute.comparatorHref)
  | entries =>
    Option.some <|
      trustBadgeHtml s!"registry: {entries.length} Palomar entries" ""
        (Option.some
          s!"{entries.length} of this page's claims are recorded in the Palomar registry, \
             each matched on the challenge digest the verdict certifies. \
             {Informal.Palomar.honestyNote}")
        (Option.some Informal.NodeRoute.comparatorHref)

/--
The rendered strip: a labeled badge row.

Carries the comparator verdict, the structural `uses`-graph gate verdicts, the
axiom-audit result, and — when the document emits a formalization-metadata page or a
trust-model page — accent badges linking to them, followed by a scope line saying how
much of the site the comparator verdict actually covers.

`checks?` used to be accepted and ignored: the dashboard computed the acyclicity and
connectivity verdicts and then threw them away, so the homepage showed no sign that
the build had gated on them at all. It is now rendered.

The strip renders only when it carries a real signal — a configured comparator, an
axiom audit that actually ran, or a non-empty graph. An unconfigured consumer with no
graph still sees nothing.
-/
def trustStripHtml (trust : TrustData) (detailsHref? : Option String := Option.none)
    (checks? : Option Informal.GraphChecks.Results := Option.none)
    (trustModelHref? : Option String := Option.none)
    (theoremLikeTotal : Option Nat := Option.none) :
    Output.Html :=
  let badges : Array Output.Html := Id.run do
    let mut out : Array Output.Html := #[]
    if !trust.comparators.isEmpty then
      out := out.push (trustAggregateComparatorBadge trust.comparators)
    else if let some cmp := trust.comparator then
      out := out.push (trustComparatorBadge cmp)
    if let some auditBadge := trustAuditBadge? trust.audit? then
      out := out.push auditBadge
    out := out ++ trustGraphBadges checks?
    if let some registryBadge := trustRegistryBadge? trust then
      out := out.push registryBadge
    return out
  if badges.isEmpty then
    .empty
  else
    -- The cross-link badges attach only when the strip already carries a real signal,
    -- preserving the "renders only with real trust data" rule.
    let badges : Array Output.Html :=
      match detailsHref? with
      | Option.some href =>
        badges.push <|
          trustBadgeHtml "formalization.yaml" "accent"
            (title? := Option.some "Project formalization.yaml metadata")
            (href? := Option.some href)
      | Option.none => badges
    let badges : Array Output.Html :=
      match trustModelHref? with
      | Option.some href =>
        badges.push <|
          trustBadgeHtml "trust model" "accent"
            (title? := Option.some "What is machine-checked here, and what is not")
            (href? := Option.some href)
      | Option.none => badges
    {{
      <section class="bp_trust_strip" "aria-label"="Trust signals">
        <span class="bp_trust_strip_label">"Trust"</span>
        <div class="bp_summary_badge_row">{{badges}}</div>
        {{if trust.comparators.isEmpty then trustScopeHtml trust.comparator theoremLikeTotal
          else trustAggregateScopeHtml trust.comparators theoremLikeTotal}}
      </section>
    }}

-- Trust-strip stylesheet: the centred fit-content dashboard strip plus the claim-first
-- comparator page (verdict header, prose sections, reproduce list). See trust-strip.css.
def trustStripCss := include_str "trust-strip.css"

-- The caveat block rides the same site-wide channel: it appears on the comparator page,
-- which reuses the site chrome, and its rules are tokens-only.
def trustStripAssetBundle : BlueprintAssetBundle :=
  blueprintCssAssetBundle [trustStripCss, Informal.CaveatsRender.css]

open Verso Doc Elab Genre Manual in
block_extension Block.trustStrip (trust : TrustData) where
  data := toJson trust
  traverse _id data _contents := do
    -- Stash the trust payload so the generation-time ExtraSteps (`emitBlueprintGraphGate`
    -- for `requireConnected`, `emitBlueprintComparatorPage` for the comparator verdict)
    -- can read it. `data` is the block's already `toJson`ed `TrustData`.
    modify fun st => Informal.TraversalIndex.TrustData.saveData st data
    return none
  toTeX := none
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI _goB _id data _blocks => do
      let some trust ← Informal.ExtensionDecode.decode? (α := TrustData) data
          (fun err => s!"Malformed data in Block.trustStrip.toHtml ({err})")
        | pure .empty
      let st ← HtmlT.state
      let checks := Informal.GraphChecks.run (Informal.GraphApi.masterGraph st)
      let theoremLikeTotal :=
        (Informal.TraversalIndex.Summary.cachedSummary? st).map fun s =>
          s.theorems + s.lemmas + s.propositions + s.corollaries
      pure (trustStripHtml trust (Informal.TraversalIndex.FormalizationPage.href? st) (some checks)
        (Informal.TraversalIndex.TrustModelPage.href? st) theoremLikeTotal)
  extraCss := trustStripAssetBundle.css
  extraJs := trustStripAssetBundle.js

/-! ## Status ↔ configuration cross-checks

The comparator's *configuration* says what will be checked; the *status artifact*
says what a CI run reported. Nothing previously compared them, so a status file
naming different theorems, different permitted axioms, or a different challenge
module than the config the verdict was produced from would render as a green
verdict about the wrong claim. These checks make that a build error.

**Two kinds of check live here, and only one of them is a security boundary.**

*Content binding* (`checkComparatorDigests`) compares SHA-256 digests the verifying run
recorded against the bytes this build is about to display. That distinguishes two
different files, so it is the substitution barrier.

*Identifier agreement* (`crossCheckComparator`) compares theorem names, axiom lists,
module names, and path suffixes. **Path shape and module basename are identifiers, not
content bindings**: any `fake/Challenge.lean` satisfies module `Challenge`, and
`pathHasSuffix` deliberately accepts a differently-rooted path so a site-relative option
can match a repo-root-relative status record. These checks catch drift and copy-paste
error — a verdict drifting away from the configuration it was produced from — and they
are hard errors because that drift is worth failing on. They are **not** a defence
against a deliberately substituted same-named file; a status artifact that records no
digests leaves the displayed source unbound, and the comparator page says so.

Neither kind is re-verification: nothing here re-runs the comparator.

**Both run at elaboration, so Lake caches their verdict with the module's `.olean`.**
Editing only a comparator source file changes no Lean input, so an *incremental* rebuild
reuses the whole capture — the verdict, the statement, these checks' success, the blob
links — and would publish it under the newer revision, internally consistent and out of
date (CX-075). That is no longer merely documented: every file read here is recorded on
the payload with its path and digest (`TrustComparator.inputs` / `TrustData.inputs`), and
`Informal.TrustFreshness` re-reads them between traversal and emission and stops the build
if any has moved. Cold builds remain the publishing path; a warm one that would have
served a stale capture now fails instead of shipping.

The recorded set is every non-Lean file this module reads — and, for the two inputs whose
absence is not an error, every path it was configured to read and found nothing at, marked
absent (CX-077): recording only the files that existed made a Solution generated after the
capture invisible to the gate, so a warm build published it with its digests never compared
against the verdict's. The set: the comparator status artifact,
its config, the Challenge and Solution sources, the topic manifest and each topic's own
four files, the challenge-chain files the closure tool hashes, `formalization.yaml`, the
kernel-advisory override, the **junk-value table override**
(`verso.blueprint.trust.junkValueTable`), the **characterization sidecar**
(`verso.blueprint.trust.characterizations`), and the Palomar records a cached bundle
supplies. Records the `verso.blueprint.trust.palomarProbe` option fetched over the network
are the one exception, because there is no file to re-read — and because they are outside
this set, nothing a claim rests on may be one of them: `Informal.Palomar.matchEntry?`
returns a probed record project-level, so the exception cannot become a hole in the ledger
(CX-076).
-/

/--
Content binding: the digests the verifying run recorded, against the bytes this build
read for display.

A recorded digest that disagrees with the displayed bytes is a hard build error — the
page would otherwise show one file under a verdict about another, which is exactly the
substitution the identifier checks cannot see. Silent when a digest is absent (a status
artifact written before CI recorded them) or when the corresponding file is not
configured; the comparator page discloses which artifacts are bound and which are not,
so an absent digest degrades into a visible weaker claim rather than a silent one.

Public rather than `private` so the test suite can drive the substitution case directly:
a security check whose failure path is only reachable by hand-editing a consumer's status
artifact is a check nobody re-verifies after the next refactor.
-/
def checkComparatorDigests (cmp : TrustComparator) (statusPath : String) :
    Lean.CoreM Unit := do
  let check := fun (what optionName recorded computed : String) => do
    let recorded := Informal.Sha256.normalizeDigest recorded
    unless recorded.isEmpty || computed.isEmpty || recorded == computed do
      throwError "the {what} this site displays is not the one the comparator verdict \
        certifies: the SHA-256 digests are of different bytes.\n\
        {statusPath} records: {recorded}\n\
        {optionName} hashes to: {computed}\n\
        Point the option at the file CI verified, or re-run CI so the status artifact is \
        regenerated from this source."
  check "challenge file" "verso.blueprint.trust.challengeFile"
    cmp.challengeSha256 cmp.challengeDigest
  check "solution file" "verso.blueprint.trust.solutionFile"
    cmp.solutionSha256 cmp.solutionDigest
  check "comparator configuration" "verso.blueprint.trust.comparatorConfig"
    cmp.configSha256 cmp.configDigest

/--
Self-agreement of a status artifact's run evidence.

Two shapes of disagreement land here, and neither has a reading:

- **Across encodings.** A record may spell the same replay three ways; it may not spell it
  three *different* ways. When the identity records, the `kernel_replays` map and the
  legacy `nanoda_replay`/`nanoda_ref` pair disagree about whether a checker replayed or at
  which revision, one page would say the run used one binary and another page a different
  one.
- **Within the identity array.** Two records for one checker label that disagree about
  repository, source commit, executable digest, argv, adapter, replay or verdict are two
  incompatible accounts of one program, and which of them a renderer sees is a fact about
  JSON array order rather than about the run (CX-071).

Either way the build stops with every disagreement named, before any surface selects.

Public for the same reason as `checkComparatorDigests`.
-/
def checkComparatorEncodings (cmp : TrustComparator) (statusPath : String) :
    Lean.CoreM Unit := do
  unless cmp.encodingConflicts.isEmpty do
    throwError "{statusPath} contradicts itself about what its verifiers did:\\n\\
      {String.intercalate "\\n" cmp.encodingConflicts.toList}\\n\\
      Run evidence may be spelled more than one way, and one checker may be described more \\
      than once; the spellings and the descriptions have to agree. There is no reading of \\
      this record: rendering it would report one revision or one binary on one page and \\
      another elsewhere, and which account comes first in a JSON array is not a fact about \\
      the run. Re-run CI so the artifact is regenerated, or remove the stale encoding or \\
      the duplicate record."

/--
Internal completeness of the status artifact's own run-evidence fields.

A record claiming an independent kernel replay must say *which* kernel: `nanoda_replay:
true` without a `nanoda_ref` is a claim nobody can check or reproduce, and the page would
render it as a second-kernel assurance. Hard error.

The requirement is per *claimed* kernel, not per known one: a record naming three kernels
and recording a revision for two of them is two thirds of a reproducible claim, and the
third is the one the page must not print.

Public for the same reason as `checkComparatorDigests`.
-/
def checkComparatorRunProvenance (cmp : TrustComparator) (statusPath : String) :
    Lean.CoreM Unit := do
  -- A malformed identity record is not a contradiction, so it is not an error: the record
  -- simply binds nothing, `kernelIdentityTier` reads it as `labeled`, and every surface
  -- says less accordingly (CX-064). It is worth a warning all the same — a producer who
  -- typed something other than a digest into `executable_sha256` meant to record one, and
  -- silently rendering the weaker page is how they never find out.
  for rec in cmp.kernelIdentities do
    let bad :=
      (if rec.executableSha256.isEmpty then [] else
        if isExecutableDigest rec.executableSha256 then [] else
          [s!"`executable_sha256` is '{rec.executableSha256}', which is not 64 lowercase hex \
             characters"]) ++
      (if rec.sourceCommit.isEmpty then [] else
        if isSourceRevision rec.sourceCommit then [] else
          [s!"`source_commit` is '{rec.sourceCommit}', which is not 7-40 lowercase hex \
             characters"])
    unless bad.isEmpty do
      logWarning m!"{statusPath}: the identity record for `{rec.label}` does not bind that \
        label to a program — {String.intercalate "; and " bad}. The row renders as \
        an unauthenticated label and its currency as unknown, which is what an unbound \
        record establishes; record the revision the checker was built from and the SHA-256 \
        of the executable that ran, or drop the fields."
  for kernel in cmp.replayedKernels do
    unless (cmp.recordedKernelRef kernel).trimAscii.toString.isEmpty do continue
    if kernel == "nanoda" then
      throwError "{statusPath} records `nanoda_replay: true` but no `nanoda_ref`. An \
        independent kernel replay with no recorded revision cannot be reproduced or \
        assessed for currency, and would be rendered as a second-kernel assurance. Record \
        the nanoda revision the run used, or drop the claim."
    else
      throwError "{statusPath} records a replay by an external checker labeled \
        `{kernel}` but no revision for it. A replay with no recorded revision cannot be \
        reproduced or assessed for currency. Record the revision the run used, or drop \
        the claim — and note that a revision typed beside a label is necessary, not \
        sufficient: only a recorded source commit plus the digest of the executable that \
        ran binds the row to a program."

/-- Normalize a filesystem path for comparison: separators to `/`, `./` segments
dropped. Deliberately does **not** resolve `..` — the two paths being compared are
rooted differently by design. -/
def normalizePathForCompare (p : String) : String :=
  Informal.StatementClosure.normalizePathForCompare p

/-- Whether `path` ends with `suffix` on a *path-component* boundary.

The consumer's option paths resolve against the build CWD (`site/`), while the
status artifact records repo-root-relative paths, so the same file is spelled
`../comparator/comparator.json` and `comparator/comparator.json`. Comparing the
strings would reject every correctly-configured project; comparing components
catches a genuinely different file while accepting a different root.

Defined in `StatementClosure` so the chain-binding comparison, the closure tool and
these cross-checks cannot drift into three slightly different notions of "same file". -/
def pathHasSuffix (path suffix : String) : Bool :=
  Informal.StatementClosure.pathHasSuffix path suffix

/-- A module name's final component (`ComparatorChallenges.I_Foo` ↦ `I_Foo`), which is
what a Lake `srcDir` layout names the file. -/
def moduleBasename (m : String) : String := ((m.splitOn ".").getLast?).getD m

/-- A path's basename without its `.lean` extension. -/
def leanFileStem (p : String) : String :=
  let base := (((normalizePathForCompare p).splitOn "/").getLast?).getD p
  if base.endsWith ".lean" then (base.dropEnd 5).toString else base

/-- Two string lists as sets (order-insensitive, duplicates ignored). -/
private def sameSet (a b : List String) : Bool :=
  a.all (b.contains ·) && b.all (a.contains ·)

/-- Cross-check the comparator *status* artifact against the comparator *config* it
claims to describe, and against the file paths this site renders. Every mismatch is a
hard error: a verdict that has drifted away from the configuration it was produced from
is worse than no verdict.

Identifier-level only — see this section's header. The theorem/axiom/module comparisons
are between two records; the path comparisons are between two spellings of a path. None
of them can tell two same-named files apart, which is what `checkComparatorDigests` is
for.

Silent on anything absent — a status artifact without `theorem_names`, or a project
that configures no `comparatorConfig`, simply has less to check. -/
private def crossCheckComparator (cmp : TrustComparator) (configJson : Json)
    (statusPath cfgPath chalPath solPath : String) : Lean.CoreM Unit := do
  let cfgTheorems := (configJson.getObjValAs? (List String) "theorem_names").toOption.getD []
  unless cmp.theoremNames.isEmpty || cfgTheorems.isEmpty || sameSet cmp.theoremNames cfgTheorems do
    throwError "comparator status/config disagree on the certified theorems.\n\
      {statusPath} says: {String.intercalate ", " cmp.theoremNames}\n\
      {cfgPath} says: {String.intercalate ", " cfgTheorems}\n\
      The verdict would be displayed next to a different claim than the one the \
      comparator was configured to check. Re-run CI so the status artifact is \
      regenerated from this configuration."
  let cfgAxioms := (configJson.getObjValAs? (List String) "permitted_axioms").toOption.getD []
  unless cmp.permittedAxioms.isEmpty || cfgAxioms.isEmpty
      || sameSet cmp.permittedAxioms cfgAxioms do
    throwError "comparator status/config disagree on the permitted axioms.\n\
      {statusPath} says: {String.intercalate ", " cmp.permittedAxioms}\n\
      {cfgPath} says: {String.intercalate ", " cfgAxioms}"
  let cfgChallengeModule := (configJson.getObjValAs? String "challenge_module").toOption.getD ""
  unless cmp.challengeModule.isEmpty || cfgChallengeModule.isEmpty
      || cmp.challengeModule == cfgChallengeModule do
    throwError "comparator status/config disagree on the challenge module \
      ({statusPath}: '{cmp.challengeModule}'; {cfgPath}: '{cfgChallengeModule}')."
  let cfgSolutionModule := (configJson.getObjValAs? String "solution_module").toOption.getD ""
  unless cmp.solutionModule.isEmpty || cfgSolutionModule.isEmpty
      || cmp.solutionModule == cfgSolutionModule do
    throwError "comparator status/config disagree on the solution module \
      ({statusPath}: '{cmp.solutionModule}'; {cfgPath}: '{cfgSolutionModule}')."
  -- The status artifact records the config path CI passed on the command line
  -- (repo-root-relative); the option resolves against the build CWD. Agreement is
  -- checked on trailing path components, so the two roots do not have to match.
  -- DIAGNOSTIC, not a binding: a differently-rooted path with the same trailing
  -- components (`../fake/comparator/comparator.json`) passes by construction. The
  -- content binding is `config_sha256`.
  unless cmp.configArgPath.isEmpty || cfgPath.isEmpty
      || pathHasSuffix cfgPath cmp.configArgPath || pathHasSuffix cmp.configArgPath cfgPath do
    throwError "the comparator status artifact was produced from a different \
      configuration file than this site renders.\n\
      {statusPath} records config: {cmp.configArgPath}\n\
      verso.blueprint.trust.comparatorConfig: {cfgPath}\n\
      Point the option at the file CI actually used."
  -- The rendered Challenge/Solution files must at least be *named* like the modules the
  -- config names. DIAGNOSTIC, not a binding: this compares a module's final component
  -- against a file's basename, so any `fake/Challenge.lean` — stating an entirely
  -- different theorem — satisfies module `Challenge`. It catches a file pointed at the
  -- wrong module, nothing more; `challenge_sha256`/`solution_sha256` are the binding.
  let checkModuleFile := fun (what modName path : String) => do
    unless modName.isEmpty || path.isEmpty || moduleBasename modName == leanFileStem path do
      throwError "the {what} file rendered on the comparator page is not named like the \
        module the comparator checked ({cfgPath} names module '{modName}'; \
        verso.blueprint.trust.{what}File points at '{path}'). The page would show one \
        file while the verdict certifies another."
  checkModuleFile "challenge" (if cfgChallengeModule.isEmpty then cmp.challengeModule else cfgChallengeModule) chalPath
  checkModuleFile "solution" (if cfgSolutionModule.isEmpty then cmp.solutionModule else cfgSolutionModule) solPath

/-- Build the comparator.live permalink for a claim/solution pair.

The deployed bundle accepts plain, uncompressed `challenge=` / `code=` fragment keys
(read back with `decodeURIComponent`), so `System.Uri.escapeUri` — a safe superset of
`encodeURIComponent` — produces a working link with no dependency on the optional
lz-string variants. Links only: nothing is fetched at build time. -/
def comparatorLivePermalink (project challenge solution : String) : String :=
  "https://comparator.live.lean-lang.org/#project=" ++ System.Uri.escapeUri project
    ++ "&challenge=" ++ System.Uri.escapeUri challenge
    ++ "&code=" ++ System.Uri.escapeUri solution

/-- Read a file once as bytes: its SHA-256 and its decoded text. See
`Informal.TrustInputs.readWithDigest` for why the two come from one read. -/
private def readSourceWithDigest (path : String) : IO (String × String) :=
  Informal.TrustInputs.readWithDigest path

/-- Record one input on a verdict, from the digest the read that produced it computed. -/
private def withInput (cmp : TrustComparator) (role path digest : String) : TrustComparator :=
  { cmp with inputs := cmp.inputs.push (Informal.TrustInputs.Input.ofDigest role path digest) }

/-- Record a configured path that held no file when this verdict was captured.

The options whose file is optional degrade to omitting a section; what they must not do is
degrade to omitting the *path*, because then the file appearing later moves nothing the
freshness gate can see, and a warm build publishes a capture whose content binding was
never run against those bytes (CX-077). -/
private def withAbsentInput (cmp : TrustComparator) (role path : String) : TrustComparator :=
  { cmp with inputs := cmp.inputs.push (Informal.TrustInputs.Input.absent role path) }

open Verso Doc Elab in
/--
Attach the config / Challenge / Solution source (with digests, cross-checks, and
the comparator.live permalink) to a comparator verdict already parsed from its
status artifact. Shared by the single-pair path and each multi-config topic so
the honesty guarantees are identical: content digests are checked against what
the verifying run recorded (hard error on disagreement), the run record's
internal completeness is checked, status↔config identifier agreement is
diagnosed, and — like the single-pair path — the Challenge FAILS CLOSED (a
configured-but-missing/empty challenge is an error, since a verdict without the
statement it certifies is unreadable).

`statusPath` and `statusDigest` are the artifact this verdict was parsed from: the
path names it in error text, and the digest is what the freshness gate compares the
file against before this capture is published (`TrustComparator.inputs`). The status
artifact is the one input this function does not read for itself — the caller parsed
it — so the digest is passed in rather than recomputed from a second read.
-/
def attachComparatorSources (cmp0 : TrustComparator)
    (statusPath statusDigest cfgPath chalPath solPath liveProject : String) :
    PartElabM TrustComparator := do
  let mut cmp := cmp0
  -- Every read below records what it read, in the order it read it: the stop message a
  -- stale capture produces lists the files a reader would go looking for, in that order.
  -- A configured path with no file at it is recorded too, as absent: the two optional
  -- inputs degrade to omitting a section, never to omitting the path, or a file generated
  -- after this capture would appear on a warm build without its bytes ever being compared
  -- against the digests the verdict recorded (CX-077).
  unless statusPath.isEmpty || statusDigest.isEmpty do
    cmp := withInput cmp Informal.TrustInputs.roleStatus statusPath statusDigest
  let mut configJson? : Option Json := Option.none
  if !cfgPath.isEmpty then
    if (← System.FilePath.pathExists cfgPath) then
      let (digest, raw) ← readSourceWithDigest cfgPath
      cmp := { cmp with configDigest := digest }
      cmp := withInput cmp Informal.TrustInputs.roleConfig cfgPath digest
      match Json.parse raw with
      | .ok j =>
        configJson? := Option.some j
        cmp := { cmp with
          configJson := j.pretty
          externalKernels := parseExternalKernels j
          -- Either spelling counts, so a config that migrated `enable_nanoda` into
          -- `external_kernels` does not read as having disabled the kernel.
          enableNanoda := configEnablesNanoda j }
      | .error _ =>
        cmp := { cmp with configJson := raw }
    else
      cmp := withAbsentInput cmp Informal.TrustInputs.roleConfig cfgPath
  if !chalPath.isEmpty then
    unless ← System.FilePath.pathExists chalPath do
      throwError "comparator challenge file names a missing file (resolved against the build \
        directory): {chalPath}. The comparator page must not publish a verdict without the \
        statement it certifies."
    let (digest, src) ← readSourceWithDigest chalPath
    if src.trimAscii.toString.isEmpty then
      throwError "comparator challenge file names an empty file: {chalPath}. The comparator page \
        must not publish a verdict without the statement it certifies."
    cmp := { cmp with challengeSource := src, challengeDigest := digest }
    cmp := withInput cmp Informal.TrustInputs.roleChallenge chalPath digest
  if !solPath.isEmpty then
    if (← System.FilePath.pathExists solPath) then
      let (digest, src) ← readSourceWithDigest solPath
      cmp := { cmp with solutionSource := src, solutionDigest := digest }
      cmp := withInput cmp Informal.TrustInputs.roleSolution solPath digest
    else
      cmp := withAbsentInput cmp Informal.TrustInputs.roleSolution solPath
  -- Self-consistency of the record first: a contradictory record has no reading, so
  -- nothing downstream should get the chance to pick one.
  liftM (checkComparatorEncodings cmp statusPath)
  liftM (checkComparatorDigests cmp statusPath)
  liftM (checkComparatorRunProvenance cmp statusPath)
  if let some cfgJson := configJson? then
    liftM (crossCheckComparator cmp cfgJson statusPath cfgPath chalPath solPath)
  if !liveProject.isEmpty && !cmp.challengeSource.isEmpty && !cmp.solutionSource.isEmpty then
    cmp := { cmp with
      comparatorLiveUrl := comparatorLivePermalink liveProject cmp.challengeSource cmp.solutionSource }
  return cmp

/-! ### Statement closure

The build-time driver for the `statement-closure` subprocess (§A2). What it may and may
not conclude:

- The closure is computed by a separate process that imports **exactly** the chain's
  declared imports. Nothing about this site's environment reaches it.
- The closure is labelled `chain` — bound to the verdict — only when every chain file the
  tool hashed matches, in order, what the verifying run recorded in `challenge_chain`
  (§A1). Anything else is `chain-unbound` with the specific reason, including the case
  the run recorded no chain at all.
- A missing or failing tool degrades to the `claim_decls` anchor when the manifest supplies
  one — a closure computed here, over the subject declarations the consumer aligned with
  the certified statements, and labelled as being of those rather than of the challenge
  file — and to `unavailable` carrying the reason when it does not. It never fails the
  build and never quietly omits the surface: once the option is on, the absence is itself
  recorded.

The ladder is therefore `chain` → `chain-unbound` → `claim-decls` → `unavailable`, and
every rung renders something. Note that `chain-unbound` does **not** fall through: a
closure of the right file that is not tied to the recorded run is still a closure of the
right file, and is worth more than a closure of something else.
-/

/-- Where the build looks for the tool when the option does not name it. Relative to the
build CWD: the first is a consumer that *is* this package, the second a consumer that
depends on it. -/
private def statementClosureToolCandidates : Array String := #[
  ".lake/build/bin/statement-closure",
  ".lake/packages/VersoBlueprint/.lake/build/bin/statement-closure"
]

open Verso Doc Elab in
/-- Locate the tool. A configured path that does not exist is a build error (a configured
signal must not degrade into a probe); an unconfigured probe that finds nothing returns
the reason it will record. -/
def findStatementClosureTool (opts : Lean.Options) : PartElabM (Except String String) := do
  let configured := opts.get verso.blueprint.trust.statementClosureTool.name
    verso.blueprint.trust.statementClosureTool.defValue
  if !configured.isEmpty then
    unless ← System.FilePath.pathExists configured do
      throwError "option 'verso.blueprint.trust.statementClosureTool' names a missing file \
        (resolved against the build directory): {configured}"
    return .ok configured
  for cand in statementClosureToolCandidates do
    if ← System.FilePath.pathExists cand then
      return .ok cand
  return .error s!"the statement-closure tool was not found (looked for \
    {String.intercalate " and " statementClosureToolCandidates.toList} under \
    {(← liftM Informal.workspaceRoot).toString}); build it with `lake build \
    statement-closure`, or name it with 'verso.blueprint.trust.statementClosureTool'"

/-- Run the tool on a job spec, following the `runTrimmedCommand?` precedent: every
failure is a reason string, never an exception. The child inherits this build's working
directory and `LEAN_PATH`, which is how it resolves the chain's imports. -/
def runStatementClosureTool (tool : String) (job : Json) : IO (Except String Json) := do
  try
    IO.FS.withTempFile fun handle jobPath => do
      handle.putStr job.compress
      handle.flush
      let out ← IO.Process.output { cmd := tool, args := #[jobPath.toString] }
      match Json.parse out.stdout with
      | .error err =>
        return .error s!"the statement-closure tool exited with code {out.exitCode} and \
          wrote no readable result ({err}){
            let e := out.stderr.trimAscii.toString
            if e.isEmpty then "" else s!"; stderr: {e}"}"
      | .ok j =>
        -- A nonzero exit with a document claiming success contradicts itself; the exit
        -- code is the one signal the tool cannot have written by mistake.
        if out.exitCode != 0 && (j.getObjValAs? Bool "ok").toOption == some true then
          return .error s!"the statement-closure tool exited with code {out.exitCode} but \
            wrote a result claiming success"
        return .ok j
  catch e =>
    return .error s!"the statement-closure tool could not be run: {e}"

/-- The honest empty state: the option is on, and this is why there is no closure. -/
def statementClosureUnavailable (reason : String) : StatementClosure :=
  { provenance := "unavailable", reason }

/-! #### The caveat table and the characterization sidecar (F2)

Both are *configured inputs*, so both fail the build rather than degrading: a project that
configured a safety table and got the default one, or that declared characterizations that
silently vanished, is worse off than a project that was told to fix its configuration.

Both are read at elaboration, which puts them on the warm-rebuild staleness list beside the
comparator artifacts: editing the override or the sidecar without touching the document that
carries the dashboard block leaves the previous contents in the `.olean`. Cold CI builds
remain the publishing path.
-/

open Verso Doc Elab in
/-- The effective caveat table: the bundled one, with a consumer override merged over it.
`none` when the surface is off. Every way the override can be wrong is a build error. -/
def elabCaveatTable? : PartElabM (Option Informal.JunkValues.Table) := do
  let opts ← Lean.getOptions
  unless Informal.JunkValues.caveatsEnabled opts do return none
  let path := Informal.JunkValues.tableOverridePath opts
  match ← liftM (Informal.JunkValues.loadTableWithOverride path) with
  | .error err =>
    if path.isEmpty then
      throwError "the caveat table this fork ships is unusable: {err}"
    else
      throwError "option 'verso.blueprint.trust.junkValueTable' {err}"
  | .ok (table, override?) =>
    -- The one check the loader cannot make: whether the override's match keys name
    -- anything in this build's environment. An override that can never match would
    -- otherwise be served to the reader as a scan that found nothing (CX-060).
    if let some override := override? then
      if let some reason :=
          Informal.JunkValues.overrideUnusableReason? (← Lean.getEnv) path override then
        throwError "option 'verso.blueprint.trust.junkValueTable' {reason}"
    return some table

open Verso Doc Elab in
/--
The consumer's characterization sidecar, with every failure mode raised.

The unresolved-declaration check happens here rather than in the loader because it is the
one check that needs this build's environment: a sidecar naming a declaration the project
does not have is describing something else.
-/
def elabCharacterizations? : PartElabM (Option Informal.JunkValues.Characterizations) := do
  let opts ← Lean.getOptions
  let path := opts.get verso.blueprint.trust.characterizations.name
    verso.blueprint.trust.characterizations.defValue
  if path.isEmpty then return none
  match ← liftM (Informal.JunkValues.loadCharacterizations path) with
  | .error err => throwError "option 'verso.blueprint.trust.characterizations' {err}"
  | .ok cs =>
    let missing := Informal.JunkValues.unresolvedDecls (← Lean.getEnv) cs
    unless missing.isEmpty do
      throwError "{cs.path} declares characterizations for \
        {String.intercalate ", " missing.toList}, which this build's environment does not \
        have. A characterization of a declaration nobody can look up describes something \
        other than this project."
    return some cs

/-! #### Where a reader can go and read one of these declarations

Rows the reading list can resolve are worth more than rows it cannot, and a row linked to
the wrong place is worth less than an unlinked one. Three resolutions, three rules:

- **Challenge**: the chain's own declarations are printed on the comparator page itself,
  so the row anchors there. Resolved at render time; nothing to look up.
- **Subject**: this site publishes a page for these, and which page (node or declaration)
  is the registry's business, so that resolution happens at generation time from the
  registry rather than being guessed from a name here.
- **Everything else** — Mathlib, core, an unexpected root: an outbound link into the
  package checkout the build read the declaration from, resolved here because only
  elaboration has the module index and the options. Probe-and-degrade: a package that is
  not a Git checkout, a module whose file cannot be located, a checkout with no GitHub
  remote all yield an unlinked row.
-/

/-- The `.lake/packages/<pkg>` checkout a resolved source path lies in, which is the unit
repository information is looked up per: one `git` call for Mathlib, not one per Mathlib
subdirectory. `none` for a path outside any checkout — a toolchain source, say, which is
in no repository this build can name. -/
private def lakePackageRoot? (path : System.FilePath) : Option System.FilePath :=
  let marker := "/.lake/packages/"
  match (path.toString.splitOn marker) with
  | before :: rest :: _ =>
    match (rest.splitOn "/").head? with
    | Option.some pkg => if pkg.isEmpty then Option.none
        else Option.some (System.FilePath.mk (before ++ marker ++ pkg))
    | Option.none => Option.none
  | _ => Option.none

/-- An outbound source link for a declaration in a dependency checkout: the GitHub blob
URL of the file its module was compiled from, at the revision the checkout is pinned to.

Deliberately not routed through `sourceLinkHref?`: the consumer's source-link template
maps paths inside *its own* repository, and applying it to a Mathlib file would produce a
confident link to a file that is not there. Locating the module is
`packageModuleSourcePath?`'s job, so the `srcDir := "src"` layout resolves here exactly as
it does everywhere else. -/
private def librarySourceHref? (workspaceRoot : System.FilePath) (m : Name) :
    IO (Option String) := do
  try
    let Option.some path ← Informal.packageModuleSourcePath? workspaceRoot m
      | return Option.none
    let Option.some pkgRoot := lakePackageRoot? path | return Option.none
    let Option.some gitRoot ← Informal.RuntimeCache.cachedGitRoot? pkgRoot
      (Informal.Git.toplevelAt? pkgRoot)
      | return Option.none
    let Option.some info ← Informal.RuntimeCache.cachedGitRepoInfo? gitRoot
      (Informal.Git.repositoryInfoAtRoot? gitRoot)
      | return Option.none
    let rootText := (← IO.FS.realPath gitRoot).toString
    let pathText := (← IO.FS.realPath path).toString
    unless pathText.startsWith (rootText ++ "/") do
      return Option.none
    let rel := (pathText.drop (rootText.length + 1)).toString
    return Option.some s!"{info.githubUrl}/blob/{info.commit}/{rel}"
  catch _ =>
    return Option.none

/--
Resolve outbound source links for every closure entry the site cannot resolve itself,
memoized per defining module.

Challenge and subject rows are skipped: the first are printed on the comparator page, the
second are the registry's to place at generation time, and a link into a dependency
checkout would be wrong for both. Public so a test can measure what a real tree resolves —
"probe-and-degrade" is only honest if somebody checks which of the two it does.
-/
def resolveClosureHrefs (workspaceRoot : System.FilePath)
    (entries : Array Informal.StatementClosure.Entry) : IO (Array StatementClosureEntry) := do
  let mut cache : Std.HashMap String (Option String) := {}
  let mut out : Array StatementClosureEntry := #[]
  for e in entries do
    let mut href := ""
    if e.origin != "challenge" && e.origin != "subject" && !e.definesModule.isEmpty then
      match cache[e.definesModule]? with
      | Option.some resolved => href := resolved.getD ""
      | Option.none =>
        let resolved ← librarySourceHref? workspaceRoot e.definesModule.toName
        cache := cache.insert e.definesModule resolved
        href := resolved.getD ""
    out := out.push {
      name := e.name
      origin := e.origin
      kind := e.kind
      auxiliary := e.auxiliary
      depth := e.depth
      href
      signature := e.signature
      definesModule := e.definesModule
      uses := e.uses
    }
  return out

open Verso Doc Elab in
/--
The `claim_decls` rung: a closure of the subject declarations the consumer aligned with
the certified statements, computed here, in this site's own environment.

Those declarations *are* in scope here — that is the whole reason this rung exists — so no
subprocess is involved and §A2's argument does not apply: nothing is being elaborated, and
the constants walked are the ones this build compiled. What it is not is a closure of the
challenge file, and every surface that renders it says so.

`none` when the manifest supplies no anchor, or when it names nothing this environment
has: an empty reading list under a confident label is worse than the honest notice.
-/
def claimDeclsClosure? (cmp : TrustComparator) (maxNodes : Nat) (chainReason : String)
    (table? : Option Informal.JunkValues.Table) :
    PartElabM (Option (StatementClosure × Option Informal.JunkValues.ScanReport)) := do
  if cmp.claimDecls.isEmpty then return none
  let opts ← Lean.getOptions
  let env ← Lean.getEnv
  let names := cmp.claimDecls.map String.toName
  let roots := names.filter (fun n => (env.find? n).isSome)
  if roots.isEmpty then return none
  let missing := (names.filter (fun n => (env.find? n).isNone)).map toString
  let cfg : Informal.StatementClosure.Config := {
    subjectRoots := Informal.configuredSubjectModuleRoots opts
    -- No module here is the challenge, and a constant with no defining module is one this
    -- document is elaborating rather than one the chain declared.
    chainModules := #[]
    localIsChain := false
    maxNodes
  }
  let (r, scan?) ← liftM (m := Lean.MetaM)
    (Informal.StatementClosure.closureAndScan cfg roots table?)
  let missingNote :=
    if missing.isEmpty then ""
    else s!" The manifest also names {String.intercalate ", " missing.toList}, which this \
      build's environment does not have; {if missing.size == 1 then "it is" else "they are"} \
      not in the closure below."
  let entries ← liftM (resolveClosureHrefs (← liftM Informal.workspaceRoot) r.entries)
  return some ({
    provenance := "claim-decls"
    reason := chainReason ++ missingNote
    roots := (roots.map toString).toList
    total := r.total
    outsideMathlib := r.outsideMathlib
    untrusted := r.untrusted
    truncated := r.truncated
    maxNodes := r.maxNodes
    counts := r.counts
    entries
  }, scan?)

/--
Record the challenge-chain files a closure hashed as payload inputs.

The digests are the *tool's*, from its own read of each file — the only digests that
exist for the chain, since the fork hands the paths to a subprocess rather than reading
them. The paths are the ones it was given (the manifest's `challenge_deps` plus the
primary Challenge), so they are relative and revision-free like every other input.

The primary Challenge is in the chain and was already recorded from this build's own
read, so paths already present are skipped: two records of one file would double the
work and, if the two reads ever disagreed, report a conflict the chain binding
(`StatementClosure.bindChain`) already reports better.
-/
private def withChainInputs (cmp : TrustComparator) (chainFiles : Array (String × String)) :
    TrustComparator := Id.run do
  let mut inputs := cmp.inputs
  for (path, digest) in chainFiles do
    if path.isEmpty || digest.isEmpty then continue
    let key := normalizePathForCompare path
    if inputs.any (fun i => normalizePathForCompare i.path == key) then continue
    inputs := inputs.push
      (Informal.TrustInputs.Input.ofDigest Informal.TrustInputs.roleChain path digest)
  return { cmp with inputs }

open Verso Doc Elab in
/--
Compute one claim's statement closure and record it, bound or not.

`chalPath` is the primary Challenge; `cmp.challengeDeps` are the chain files elaborated
before it, in manifest order. That order is what gets hashed and compared, so a
dependency edited without touching the primary Challenge drops the binding.
-/
def attachStatementClosure (cmp : TrustComparator) (chalPath : String) :
    PartElabM TrustComparator := do
  let opts ← Lean.getOptions
  unless opts.get verso.blueprint.trust.statementClosure.name
      verso.blueprint.trust.statementClosure.defValue do
    return cmp
  let maxNodes := opts.get verso.blueprint.trust.statementClosureMaxNodes.name
    verso.blueprint.trust.statementClosureMaxNodes.defValue
  if maxNodes < Informal.StatementClosure.capFloor then
    throwError "option 'verso.blueprint.trust.statementClosureMaxNodes' is {maxNodes}; the \
      floor is {Informal.StatementClosure.capFloor}. Below it a truncated closure is not a \
      weak claim but an empty one: a handful of arbitrary declarations, reported as a lower \
      bound nobody can use."
  -- The caveat table, when the caveat surface is on. It is loaded here rather than in the
  -- tool so that a bad override is a build error at the consumer's boundary, and so that
  -- the version and digest the page names are the ones this build merged.
  let table? ← elabCaveatTable?
  let record (c : StatementClosure) (scan? : Option Informal.JunkValues.ScanReport) :
      TrustComparator :=
    withChainInputs { cmp with closure? := some c, caveats? := scan? } c.chainFiles
  -- The bottom two rungs, taken together: the aligned-statement anchor when the manifest
  -- has one, and otherwise the notice that says why there is nothing. A rung with no
  -- closure has no traversal for the caveat scan to ride, so the scan is unavailable for
  -- the same reason and says so rather than reporting an empty result.
  let fallback (reason : String) : PartElabM TrustComparator := do
    match ← claimDeclsClosure? cmp maxNodes reason table? with
    | Option.some (c, scan?) => return record c scan?
    | Option.none =>
      return record (statementClosureUnavailable reason)
        (if table?.isNone then none else some (Informal.JunkValues.unavailable reason))
  if chalPath.isEmpty then
    return ← fallback
      "no Challenge source is configured for this claim, so there is no statement to close over"
  if cmp.theoremNames.isEmpty then
    return ← fallback
      "the run record names no certified theorem, so there is no statement to close over"
  let job : Informal.StatementClosure.Job := {
    files := cmp.challengeDeps.push chalPath
    roots := cmp.theoremNames.toArray
    maxNodes
    subjectRoots := (Informal.configuredSubjectModuleRoots opts).map (·.toString)
    caveatTable? := table?
  }
  match ← findStatementClosureTool opts with
  | .error reason => fallback reason
  | .ok tool =>
    match ← liftM (runStatementClosureTool tool job.toJson) with
    | .error reason => fallback reason
    | .ok doc =>
      match Informal.StatementClosure.Report.ofJson? doc with
      | .error reason =>
        fallback s!"the statement-closure tool did not produce a closure — {reason}"
      | .ok report =>
        let binding := Informal.StatementClosure.bindChain report.provenance.files cmp.challengeChain
        let r := report.result
        let entries ← liftM (resolveClosureHrefs (← liftM Informal.workspaceRoot) r.entries)
        -- A tool old enough to omit the caveat report is reported as unavailable rather
        -- than as a scan that found nothing.
        let scan? : Option Informal.JunkValues.ScanReport :=
          if table?.isNone then Option.none
          else match report.caveats? with
            | Option.some c => Option.some c
            | Option.none => Option.some (Informal.JunkValues.unavailable
                "the statement-closure tool this build ran returned no caveat report")
        return record (scan? := scan?) {
          provenance := binding.provenanceTag
          reason := binding.reason
          roots := cmp.theoremNames
          total := r.total
          outsideMathlib := r.outsideMathlib
          untrusted := r.untrusted
          truncated := r.truncated
          maxNodes := r.maxNodes
          counts := r.counts
          chainFiles := report.provenance.files.map fun f => (f.path, f.sha256)
          imports := report.provenance.imports
          entries
        }

open Verso Doc Elab in
/--
Build the multi-config comparator + axiom-audit topics from the JSON manifest
named by `verso.blueprint.trust.comparatorTopics` (`""` ⇒ none). A missing or
unparsable manifest, or a topic missing its `status` (comparator) / `decls`
(axiom-audit), is a build error: a configured multi-config surface must not
vanish silently. Paths inside the manifest resolve against the build CWD, like
the single-pair options. Reads `verso.blueprint.trust.comparatorLiveProject` for
the per-topic comparator.live permalink.

Returns the manifest's own input record alongside the topics: the manifest is read at
elaboration like everything else it names, and a manifest edited afterwards — a topic
renamed, a path repointed, a topic removed — would otherwise replay through the same
stale `.olean` as the files it names (CX-075).
-/
def elabComparatorTopics? :
    PartElabM (List ComparatorTopic × List AxiomAuditTopic ×
      Array Informal.TrustInputs.Input) := do
  let opts ← Lean.getOptions
  let path := opts.get verso.blueprint.trust.comparatorTopics.name
    verso.blueprint.trust.comparatorTopics.defValue
  if path.isEmpty then return ([], [], #[])
  unless ← System.FilePath.pathExists path do
    throwError "option 'verso.blueprint.trust.comparatorTopics' names a missing file (resolved \
      against the build directory): {path}"
  let (manifestDigest, manifestRaw) ← readSourceWithDigest path
  let manifestInput :=
    Informal.TrustInputs.Input.ofDigest Informal.TrustInputs.roleTopics path manifestDigest
  let doc ← match Json.parse manifestRaw with
    | .error err => throwError "could not parse {path}: {err}"
    | .ok j => pure j
  let topics := (doc.getObjVal? "topics").toOption.getD Json.null
  let arr := topics.getArr?.toOption.getD #[]
  let liveProject := opts.get verso.blueprint.trust.comparatorLiveProject.name
    verso.blueprint.trust.comparatorLiveProject.defValue
  let str? (j : Json) (k : String) : String := (j.getObjValAs? String k).toOption.getD ""
  let workspaceRoot ← liftM Informal.workspaceRoot
  let mut comparators : List ComparatorTopic := []
  let mut axiomTopics : List AxiomAuditTopic := []
  for t in arr do
    let name := str? t "name"
    let kind := let k := str? t "kind"; if k.isEmpty then "comparator" else k
    match kind with
    | "axiom-audit" =>
      let declNames := (t.getObjValAs? (List String) "decls").toOption.getD []
      if declNames.isEmpty then
        throwError "comparator topic '{name}' in {path} has kind \"axiom-audit\" but names no \
          declarations (\"decls\": [...])."
      let mut decls : List AxiomAuditDecl := []
      for dn in declNames do
        match ← liftM (Informal.AxiomAudit.declAxioms? dn.toName) with
        | Option.some d =>
          let entry : AxiomAuditDecl := {
            name := d.name
            axioms := d.axioms.toList
            sorried := d.sorried
            nonstandard := d.nonstandard.toList
          }
          decls := decls ++ [entry]
        | Option.none =>
          throwError "comparator topic '{name}' in {path}: declaration '{dn}' is not in the \
            environment this site was generated from, so its axiom closure cannot be audited."
      let topicEntry : AxiomAuditTopic := { name, decls }
      axiomTopics := axiomTopics ++ [topicEntry]
    | _ =>
      let statusPath := str? t "status"
      if statusPath.isEmpty then
        throwError "comparator topic '{name}' in {path} names no status artifact (\"status\": …)."
      unless ← System.FilePath.pathExists statusPath do
        throwError "comparator topic '{name}' in {path} names a missing status file (resolved \
          against the build directory): {statusPath}"
      let (statusDigest, statusRaw) ← readSourceWithDigest statusPath
      let cmp0 ← match Json.parse statusRaw with
        | .error err => throwError "could not parse {statusPath} (topic '{name}'): {err}"
        | .ok j => pure (TrustComparator.ofJson j)
      let cfgPath := str? t "config"
      let chalPath := str? t "challenge"
      let solPath := str? t "solution"
      let cmp ← attachComparatorSources cmp0 statusPath statusDigest cfgPath chalPath solPath
        liveProject
      -- Same source enrichment (highlighting + links) as the single-pair path.
      let cmp ← liftM (enrichComparatorSources opts workspaceRoot cmp chalPath solPath cfgPath)
      -- Reserved manifest inputs: the chain files beyond the primary Challenge (in
      -- elaboration order) and the subject-side statements aligned with the claim.
      -- Carried now so the statement-closure round needs no second schema pass.
      let cmp := { cmp with
        challengeDeps := (t.getObjValAs? (Array String) "challenge_deps").toOption.getD #[]
        claimDecls := (t.getObjValAs? (Array String) "claim_decls").toOption.getD #[] }
      -- After `challenge_deps`: the chain order is what gets hashed and compared.
      let cmp ← attachStatementClosure cmp chalPath
      let topicEntry : ComparatorTopic := { name, comparator := cmp }
      comparators := comparators ++ [topicEntry]
  return (comparators, axiomTopics, #[manifestInput])

open Verso Doc Elab in
/--
The advisory table currency is assessed against: the one this fork ships, or the one
`verso.blueprint.trust.kernelAdvisories` names. A set option pointing at a missing or
unparsable file is a build error — a configured safety table must not degrade into the
default without saying so, since the two differ exactly in what they would have caught.

The override replaces the built-in table rather than merging into it: a merge would let
a consumer drop an advisory by omission, which is the one edit nobody would notice.

The built-in table ships in this fork's source, so it moves only when a Lean module does
and needs no input record. A consumer override is a file Lake does not track, and comes
back with one.
-/
def elabKernelAdvisories :
    PartElabM (Informal.KernelAdvisories.Table × Array Informal.TrustInputs.Input) := do
  let opts ← Lean.getOptions
  let path := opts.get verso.blueprint.trust.kernelAdvisories.name
    verso.blueprint.trust.kernelAdvisories.defValue
  if path.isEmpty then return (Informal.KernelAdvisories.builtinTable, #[])
  unless ← System.FilePath.pathExists path do
    throwError "option 'verso.blueprint.trust.kernelAdvisories' names a missing file \
      (resolved against the build directory): {path}"
  let (digest, raw) ← readSourceWithDigest path
  let j ← match Json.parse raw with
    | .error err => throwError "could not parse {path}: {err}"
    | .ok j => pure j
  match Informal.KernelAdvisories.Table.ofJson? j with
  | .error err =>
    throwError "{path} is not a kernel-advisory table: {err}. Expected an object with \
      'advisoriesUpdated' (a date) and 'advisories' (an array of entries, each with \
      'tool', 'advisoryDate', 'summary', 'url' and a 'fix' object) — see the option's \
      description for the full shape."
  | .ok table =>
    return (table,
      #[Informal.TrustInputs.Input.ofDigest Informal.TrustInputs.roleAdvisories path digest])

/-! ### Registry records (Palomar)

Three options, one of which is evidence. `palomarBundle` names canonical records — the only
documents that carry a repository, a revision and a challenge digest — and is therefore the
only input a *claim-level* match may rest on. `palomarProbe` may fetch the same records over
the network; what it returns is added to the records a match is run over, but a probed
record can only ever reach the project-level card and the bundle-health surface, both of
which say what they are (CX-076). `palomarEntryUrl` is a link the author pasted in and is
never matched against anything at all; it rides the payload so the page can render it,
labelled, as what it is.

The boundary is enforced in `Informal.Palomar.matchEntry?` — the one place a match is built
— rather than at each surface, and re-checked below by `RegistryEntry.isClaimLevel` and
again before emission by `Informal.TrustFreshness`.
-/

open Verso Doc Elab in
/--
The registry records this build will match against.

The cached bundle is validated first whatever the probe does: a configured input that is
broken has to say so on the build where the network happened to answer too.

What the probe returns is then *unioned* with the cache rather than substituted for it
(`Informal.Palomar.Bundle.union`). The probe reads a capped recent projection filtered by
repository, so it routinely comes back without a record the configured bundle holds; a build
that let a non-empty probe stand in for the cache would delete a claim-level surface the
cache proves, on the strength of what the registry happened to have listed that day. That is
the "switching the probe on cannot silently remove a surface" clause, honoured for the case
where the probe answered rather than only for the case where it did not.

The one thing the union will not do is choose between two spellings of one record: a registry
record is immutable, so cache and probe disagreeing under one `id`-`v`-`version` means one of
them is not that record, and the build stops.
-/
def elabPalomarBundle? (repo : String) : PartElabM (Option Informal.Palomar.Bundle) := do
  let opts ← Lean.getOptions
  let bundlePath := opts.get verso.blueprint.trust.palomarBundle.name
    verso.blueprint.trust.palomarBundle.defValue
  let probeOn := opts.get verso.blueprint.trust.palomarProbe.name
    verso.blueprint.trust.palomarProbe.defValue
  let cached? ←
    if bundlePath.isEmpty then pure Option.none
    else match ← liftM (Informal.Palomar.loadBundle bundlePath) with
      | .error err => throwError "option 'verso.blueprint.trust.palomarBundle' {err}"
      | .ok b => pure (Option.some b)
  unless probeOn do return cached?
  let some probed ← liftM (Informal.Palomar.probe repo) | return cached?
  match cached? with
  | Option.none =>
    -- Nothing configured. A probe that read no rows at all has nothing to report, not even
    -- about itself; one that skipped rows says so through the bundle-health surface.
    return if probed.entries.isEmpty && probed.unresolved.isEmpty then Option.none
      else Option.some probed
  | Option.some cache =>
    match Informal.Palomar.Bundle.union cache probed with
    | .error err =>
      throwError "the Palomar records this build read do not agree: {err}. Either the \
        configured bundle ('verso.blueprint.trust.palomarBundle') is not the registry's \
        bytes, or the probe fetched something that is not the record it names; this build \
        will not pick one."
    | .ok union => return Option.some union

/--
The registry documents this build read off disk, as input records.

Every record the bundle holds, not only the one that matched: which record matches is
decided by their bytes, so a record edited after elaboration can change the *match* as
easily as it can change the card. A cached bundle's root document — the configured entry
file, or the `recent.json` of a configured directory — comes back too, since it is what
names the records at all.

Probed records are outside this: they were fetched over the network during elaboration and
there is no file to re-read. A warm rebuild does replay them, and this cannot detect it —
which is why the probe is soft everywhere, and why a probed record is not allowed to be
load-bearing at all: `Informal.Palomar.matchEntry?` returns it project-level, so nothing a
claim rests on is ever outside this ledger (CX-076). The same predicate decides both, so
"recorded here" and "may bind a claim" cannot come apart.
-/
private def registryInputs (bundlePath : String) (bundle : Informal.Palomar.Bundle) :
    IO (Array Informal.TrustInputs.Input) := do
  let mut out : Array Informal.TrustInputs.Input := #[]
  unless bundlePath.isEmpty do
    let fsPath : System.FilePath := bundlePath
    let isDir ← try fsPath.isDir catch _ => pure false
    let root := if isDir then (fsPath / "recent.json").toString else bundlePath
    if ← System.FilePath.pathExists root then
      if let some i ← Informal.TrustInputs.Input.probe?
          Informal.TrustInputs.roleRegistryBundle root then
        out := out.push i
  for e in bundle.entries do
    let origin := e.origin
    unless Informal.Palomar.isCachedOrigin origin do continue
    if out.any (fun i => i.path == origin) then continue
    unless ← System.FilePath.pathExists origin do continue
    if let some i ← Informal.TrustInputs.Input.probe?
        Informal.TrustInputs.roleRegistryRecord origin then
      out := out.push i
  return out

open Verso Doc Elab in
/--
Match the configured registry records against the claims this page presents.

The rules are `Informal.Palomar.matchEntry?`'s; what is decided here is where a match is
allowed to appear. A claim-level match — the record's digest is the digest of a displayed
statement, the verifying run recorded that digest, and the record itself came from a
configured bundle — attaches to that claim's panel and earns a strip badge. Anything weaker
attaches to the page, once, and only when no claim was bound: a record about the project,
printed under a claim that a stronger record already identifies, adds ambiguity rather than
provenance.

"Anything weaker" now includes a record that agreed on everything a binding needs but was
read over the network (CX-076). It is not thrown away — the agreement is real and worth
printing — it is printed on the page-level card, which says in prose that it is provenance
and why.
-/
def attachRegistry (trust : TrustData) : PartElabM TrustData := do
  let opts ← Lean.getOptions
  let link := opts.get verso.blueprint.trust.palomarEntryUrl.name
    verso.blueprint.trust.palomarEntryUrl.defValue
  let bundlePath := opts.get verso.blueprint.trust.palomarBundle.name
    verso.blueprint.trust.palomarBundle.defValue
  let probeOn := opts.get verso.blueprint.trust.palomarProbe.name
    verso.blueprint.trust.palomarProbe.defValue
  if link.isEmpty && bundlePath.isEmpty && !probeOn then return trust
  let trust := { trust with registryLink := link }
  let some bundle ← elabPalomarBundle? trust.projectRepoIdentity | return trust
  -- What this build read off disk to do the matching below, recorded before any of it is
  -- used: the match itself is a function of these bytes.
  let trust := { trust with
    inputs := trust.inputs ++ (← liftM (registryInputs bundlePath bundle)) }
  -- Bundle health first, and unconditionally: what this build could not read is a fact about
  -- the input, not about the outcome, so it must survive every path below — including the
  -- one where nothing matches and no card is rendered at all.
  let trust :=
    if bundle.unresolved.isEmpty then trust
    else { trust with registryBundle? := Option.some {
      source := bundle.source
      provenance := bundle.provenance
      unresolved := bundle.unresolved.toList.map fun u =>
        { label := u.label, reason := u.reason, source := u.source } } }
  let entryOf (m : Informal.Palomar.Match) : RegistryEntry :=
    let e := m.entry
    { id := e.id
      version := e.version
      title := e.title
      recordedAt := e.registeredAt
      sourceRepo := e.sourceRepository
      repoUrl := e.sourceRepositoryUrl
      sourceCommit := e.sourceCommit
      treeUrl := e.sourceTreeUrl
      challengeSha256 := e.challengeSha256
      verifiedAt := e.verifiedAt
      workflowUrl := e.workflowUrl
      matchBasis := m.basis
      matchNote := m.note
      provenance := bundle.provenance
      recordOrigin := e.origin }
  -- What this site knows about one claim: the digest of the statement it displays, whether
  -- the verifying run recorded that digest, and the repository the run named.
  let claimOf (cmp : TrustComparator) : Informal.Palomar.ClaimIdentity :=
    let recorded := Informal.Sha256.normalizeDigest cmp.challengeSha256
    let displayed := Informal.Sha256.normalizeDigest cmp.challengeDigest
    -- The paths the verdict names, as the *run* recorded them (repository-root-relative):
    -- the configuration CI was passed, and every challenge-chain file it hashed. A record
    -- registering some other directory of this repository is not about this claim.
    let paths : Array String :=
      (if cmp.configArgPath.isEmpty then #[] else #[cmp.configArgPath])
        ++ cmp.challengeChain.map (·.1)
    { displayedDigest := cmp.challengeDigest
      digestStatusBound := !recorded.isEmpty && !displayed.isEmpty && recorded == displayed
      statusSuccess := cmp.isSuccessVerdict
      repo := if !cmp.repository.isEmpty then cmp.repository else cmp.repoUrl
      sourceCommit := cmp.commit
      projectPaths := paths }
  let matchOf (cmp : TrustComparator) : Option Informal.Palomar.Match :=
    Informal.Palomar.selectMatch? (claimOf cmp) bundle.entries
  let claimEntry? (cmp : TrustComparator) : Option RegistryEntry := do
    let m ← matchOf cmp
    if m.claimLevel then some (entryOf m) else none
  let trust := { trust with
    comparator := trust.comparator.map fun cmp => { cmp with registryEntry? := claimEntry? cmp }
    comparators := trust.comparators.map fun t =>
      { t with comparator := { t.comparator with registryEntry? := claimEntry? t.comparator } } }
  if !trust.claimRegistryEntries.isEmpty then return trust
  -- Nothing was bound to a claim. The weaker readings, in the order they are worth
  -- anything: a record that agreed on a binding basis but was fetched over the network, then
  -- one whose digest is the displayed bytes' under a verdict that recorded no digest, then
  -- one that registers this repository.
  let unbound : List Informal.Palomar.Match :=
    ((trust.comparator.bind matchOf).toList ++ trust.comparators.filterMap (matchOf ·.comparator))
  let onBasis := fun (bases : List String) =>
    unbound.find? (fun (m : Informal.Palomar.Match) => bases.contains m.basis)
  let ladder : List (List String) :=
    [Informal.Palomar.claimLevelBases,
     [Informal.Palomar.basisNotVerified],
     ["digest-unbound"],
     [Informal.Palomar.basisIdentityMismatch]]
  let projectMatch? :=
    match ladder.findSome? onBasis with
    | Option.some m => Option.some m
    | Option.none =>
      Informal.Palomar.selectMatch? { repo := trust.projectRepoIdentity } bundle.entries
  return { trust with registryEntry? := projectMatch?.map entryOf }

/--
The `formalization.yaml` gate, where every reader of the file runs it.

Off by default, and when off nothing about the document is checked and nothing about it is
claimed. When on, every violation the subset check finds is reported at once and the build
stops: the alternative is a metadata page that presents a document this build could not
read as though it had been read.

Generic in the monad so the trust payload's reader and the metadata page's command share
one implementation, and a document cannot pass one gate and fail the other.
-/
def checkFormalizationYaml [Monad m] [Lean.MonadError m] (opts : Lean.Options) (path : String)
    (doc : Json) : m Unit := do
  unless opts.get verso.blueprint.trust.validateFormalizationYaml.name
      verso.blueprint.trust.validateFormalizationYaml.defValue do
    return
  let violations := Informal.FormalizationYaml.validate doc
  unless violations.isEmpty do
    let n := violations.size
    throwError "{path} does not satisfy the formalization.yaml v0.4 standard \
      ({n} problem{if n == 1 then "" else "s"}):\n\
      {String.intercalate "\n" ((violations.map (fun v => s!"  - {v}")).toList)}\n\
      This is {Informal.FormalizationYaml.validationProvenance}: it checks the required \
      fields, types, enumerations and array minimums the standard states, and nothing about \
      formats, lengths, or the deliberately freeform `alignment` block. Fix the document, or \
      unset 'verso.blueprint.trust.validateFormalizationYaml'."

open Verso Doc Elab in
/--
Read the artifacts named by the `verso.blueprint.trust.*` options into a
`TrustData` payload. `none` when all options are unset; a build error when a
set option names a missing or unparsable file. Reads happen at elaboration
time; relative paths resolve against the build CWD (the consumer package root).
-/
def elabTrustData? : PartElabM (Option TrustData) := do
  let opts ← Lean.getOptions
  let yamlPath : String :=
    opts.get verso.blueprint.trust.formalizationYaml.name
      verso.blueprint.trust.formalizationYaml.defValue
  let cmpPath : String :=
    opts.get verso.blueprint.trust.comparatorStatus.name
      verso.blueprint.trust.comparatorStatus.defValue
  let topicsPath : String :=
    opts.get verso.blueprint.trust.comparatorTopics.name
      verso.blueprint.trust.comparatorTopics.defValue
  -- Both F2 inputs are validated here, before the early return, so that a configured file
  -- which is missing or malformed fails the build whether or not this document also
  -- carries a comparator. A configured input that is never read is a configured input
  -- nobody finds out is broken.
  let caveatTable? ← elabCaveatTable?
  let characterizations? ← elabCharacterizations?
  -- Project-level input records, collected in read order. Kept apart from `trust` because
  -- the `formalization.yaml` branch below replaces the payload wholesale; merged back in
  -- before the registry step, which appends its own.
  let mut projectInputs : Array Informal.TrustInputs.Input := #[]
  if caveatTable?.isSome then
    -- The bundled table ships in this fork's source and moves with a Lean module; only a
    -- consumer override is a file Lake does not track.
    if let some i ← liftM (Informal.TrustInputs.Input.probe?
        Informal.TrustInputs.roleCaveatTable (Informal.JunkValues.tableOverridePath opts)) then
      projectInputs := projectInputs.push i
  if let some cs := characterizations? then
    if let some i ← liftM (Informal.TrustInputs.Input.probe?
        Informal.TrustInputs.roleCharacterizations cs.path) then
      projectInputs := projectInputs.push i
  if yamlPath.isEmpty && cmpPath.isEmpty && topicsPath.isEmpty then
    -- A configured registry surface with no comparator has nowhere to appear: the strip
    -- carries claim-bound records and the comparator page carries the cards, and neither
    -- exists without a verdict. Say so rather than reading the options and doing nothing.
    let registryConfigured :=
      !(opts.get verso.blueprint.trust.palomarEntryUrl.name
          verso.blueprint.trust.palomarEntryUrl.defValue).isEmpty
        || !(opts.get verso.blueprint.trust.palomarBundle.name
          verso.blueprint.trust.palomarBundle.defValue).isEmpty
        || opts.get verso.blueprint.trust.palomarProbe.name
          verso.blueprint.trust.palomarProbe.defValue
    if registryConfigured then
      logWarning "the Palomar registry options are set, but this document configures no \
        comparator verdict. A registration is rendered beside the claim it records, so with \
        no comparator there is no strip badge and no comparator page for it to appear on."
    return Option.none
  let mut trust : TrustData := {}
  let mut statusDigest : String := ""
  if !yamlPath.isEmpty then
    if !(← System.FilePath.pathExists yamlPath) then
      throwError "option 'verso.blueprint.trust.formalizationYaml' names a missing file (resolved against the build directory): {yamlPath}"
    let (digest, raw) ← readSourceWithDigest yamlPath
    projectInputs := projectInputs.push
      (Informal.TrustInputs.Input.ofDigest Informal.TrustInputs.roleFormalization yamlPath digest)
    match Informal.FormalizationYaml.parse raw with
    | .error err => throwError "could not parse {yamlPath}: {err}"
    | .ok doc =>
      checkFormalizationYaml opts yamlPath doc
      trust := TrustData.ofFormalizationJson doc
  if !cmpPath.isEmpty then
    if !(← System.FilePath.pathExists cmpPath) then
      throwError "option 'verso.blueprint.trust.comparatorStatus' names a missing file (resolved against the build directory): {cmpPath}"
    let (digest, raw) ← readSourceWithDigest cmpPath
    statusDigest := digest
    match Json.parse raw with
    | .error err => throwError "could not parse {cmpPath}: {err}"
    | .ok j => trust := { trust with comparator := Option.some (TrustComparator.ofJson j) }
  -- Embed the comparator's config JSON + Challenge/Solution Lean source verbatim on the
  -- comparator page. Unlike the two required options above, these degrade silently
  -- when their file is empty/missing (probe-and-degrade) and only attach when a
  -- comparator verdict exists — silently in what they render, not in what they record:
  -- a configured path with no file at it comes back on the payload as absent (CX-077).
  if let some cmp := trust.comparator then
    let cfgPath : String :=
      opts.get verso.blueprint.trust.comparatorConfig.name
        verso.blueprint.trust.comparatorConfig.defValue
    let chalPath : String :=
      opts.get verso.blueprint.trust.challengeFile.name
        verso.blueprint.trust.challengeFile.defValue
    let solPath : String :=
      opts.get verso.blueprint.trust.solutionFile.name
        verso.blueprint.trust.solutionFile.defValue
    let liveProject : String :=
      opts.get verso.blueprint.trust.comparatorLiveProject.name
        verso.blueprint.trust.comparatorLiveProject.defValue
    -- Config/Challenge/Solution embedding + digests + cross-checks + live permalink,
    -- via the shared helper (identical honesty logic for the multi-config topics).
    let cmp ← attachComparatorSources cmp cmpPath statusDigest cfgPath chalPath solPath
      liveProject
    -- The single-pair path has no topic manifest, so its chain is the Challenge alone.
    let cmp ← attachStatementClosure cmp chalPath
    trust := { trust with comparator := Option.some cmp }
  -- Multi-config comparator + axiom-audit topics, independent of the single-pair
  -- options above (a consumer uses one scheme or the other).
  let (comparators, axiomAuditTopics, topicInputs) ← elabComparatorTopics?
  trust := { trust with comparators, axiomAuditTopics }
  projectInputs := projectInputs ++ topicInputs
  -- Layer on the comparator-source enrichment (syntax highlighting + source links).
  -- Runs in `CoreM`; degrades to empty fields, never a build error.
  trust := (← liftM (enrichTrustData opts trust))
  -- Currency of the verifier builds each record names, against the advisory table. Pure
  -- once the table is read, and computed for every verdict on the page so the
  -- single-pair and multi-config surfaces cannot answer differently.
  let (advisories, advisoryInputs) ← elabKernelAdvisories
  projectInputs := projectInputs ++ advisoryInputs
  trust := { trust with
    advisoriesUpdated := advisories.advisoriesUpdated
    comparator := trust.comparator.map (·.withCurrency advisories)
    comparators := trust.comparators.map fun t =>
      { t with comparator := t.comparator.withCurrency advisories } }
  let requireConnected : Bool :=
    opts.get verso.blueprint.trust.requireConnected.name
      verso.blueprint.trust.requireConnected.defValue
  let requireAuditClean : Bool :=
    opts.get verso.blueprint.trust.requireAuditClean.name
      verso.blueprint.trust.requireAuditClean.defValue
  let ciRunUrl : Option String :=
    let u := opts.get verso.blueprint.trust.ciRunUrl.name
      verso.blueprint.trust.ciRunUrl.defValue
    if u.isEmpty then none else some u
  trust := { trust with requireConnected, requireAuditClean, ciRunUrl }
  -- The consumer's own characterizations, which the caveat surface renders as theirs.
  trust := { trust with characterizations? }
  -- What this elaboration read, on the payload that carries what it read it for. The
  -- freshness gate compares these against the files before any of the above is published
  -- (CX-075); `Informal.TrustFreshness` is where and why.
  trust := { trust with inputs := trust.inputs ++ projectInputs }
  -- Registry records last: matching reads the challenge digests and repository identity the
  -- steps above established, and a record can only be bound to a claim that is finished.
  trust ← attachRegistry trust
  return Option.some trust

open Verso Doc Elab in
/--
The parsed `formalization.yaml` named by `verso.blueprint.trust.formalizationYaml`,
for the build-time axiom audit's claim checking. `none` when the option is unset;
a build error when it names a missing or unparsable file (mirroring
`elabTrustData?`, which reads the same file for its badges).
-/
def elabFormalizationDoc? : PartElabM (Option Json) := do
  let opts ← Lean.getOptions
  let yamlPath : String :=
    opts.get verso.blueprint.trust.formalizationYaml.name
      verso.blueprint.trust.formalizationYaml.defValue
  if yamlPath.isEmpty then return Option.none
  if !(← System.FilePath.pathExists yamlPath) then
    throwError "option 'verso.blueprint.trust.formalizationYaml' names a missing file \
      (resolved against the build directory): {yamlPath}"
  match Informal.FormalizationYaml.parse (← IO.FS.readFile yamlPath) with
  | .error err => throwError "could not parse {yamlPath}: {err}"
  | .ok doc =>
    checkFormalizationYaml (← Lean.getOptions) yamlPath doc
    return Option.some doc

end Informal.Commands
