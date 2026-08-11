/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean
import Verso
import VersoManual
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

register_option verso.blueprint.trust.comparatorStatus : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to a comparator-status JSON artifact; feeds the dashboard trust strip's comparator badge. Empty disables."
}

register_option verso.blueprint.trust.comparatorConfig : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the comparator's configuration JSON; its contents are embedded verbatim (pretty-printed) on the comparator evidence page. Empty or missing ⇒ omitted (probe-and-degrade)."
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
  descr := "Path (relative to the build CWD) to the comparator's Solution Lean file; its contents are embedded verbatim on the comparator evidence page (after the Challenge file). Empty or missing ⇒ omitted (probe-and-degrade)."
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
  commands; empty ⇒ the commands run from the reader's own checkout. -/
  repoUrl : String := ""
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

/-- Extract the comparator verdict from a comparator-status artifact (`verified_at` may be `null`).
Every field beyond `status` is optional (absent in older artifacts ⇒ empty-sentinel default), so
an artifact written before the provenance fields existed still loads. The embedded config /
Challenge sources are filled in later from their own options (`elabTrustData?`). -/
def TrustComparator.ofJson (j : Json) : TrustComparator :=
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
    nanodaRef := (j.getObjValAs? String "nanoda_ref").toOption.getD ""
    landrunRef := (j.getObjValAs? String "landrun_ref").toOption.getD ""
    challengeModule := (j.getObjValAs? String "challenge_module").toOption.getD ""
    solutionModule := (j.getObjValAs? String "solution_module").toOption.getD ""
    -- Run evidence. Absent ⇒ `none` (unrecorded), which is *not* the same as `false`
    -- and is never filled in from the current configuration.
    nanodaReplay := (j.getObjValAs? Bool "nanoda_replay").toOption
    -- Content binding. Absent ⇒ empty ⇒ the displayed source is bound to this verdict
    -- by name and path shape only.
    configSha256 := (j.getObjValAs? String "config_sha256").toOption.getD ""
    challengeSha256 := (j.getObjValAs? String "challenge_sha256").toOption.getD ""
    solutionSha256 := (j.getObjValAs? String "solution_sha256").toOption.getD ""
  }

/-! ### Run evidence -/

/--
Whether the run that produced this verdict performed the independent nanoda-kernel
replay.

Run evidence only: the status artifact's `nanoda_replay`. An artifact that predates the
field records nothing about its run, so absence reads as `false` — under-claiming a
replay that may have happened is a presentation defect; claiming one that did not is a
false assertion about a dated verification.
-/
def TrustComparator.replayedWithNanoda (cmp : TrustComparator) : Bool :=
  cmp.nanodaReplay == some true

/-- Whether the status artifact carries the nanoda run-evidence field at all. `false` ⇒
legacy artifact: the page says the replay is *unrecorded*, not that it did not happen. -/
def TrustComparator.nanodaReplayRecorded (cmp : TrustComparator) : Bool :=
  cmp.nanodaReplay.isSome

/--
Disagreement between the current comparator configuration and the linked run's record.

`some true` ⇒ the configuration now enables the replay but the run did not perform one;
`some false` ⇒ the run performed one but the configuration no longer enables it. Either
way the configuration has changed since the verdict was produced, and the page says so
rather than silently adopting one side. `none` ⇒ they agree, or the run recorded nothing
to disagree with.
-/
def TrustComparator.nanodaConfigDrift? (cmp : TrustComparator) : Option Bool :=
  match cmp.nanodaReplay with
  | Option.some replayed =>
    if replayed == cmp.enableNanoda then Option.none else Option.some cmp.enableNanoda
  | Option.none => Option.none

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
config enables the independent nanoda kernel (`enableNanoda`), the flow clones and builds
`nanoda_lib` — describing what a run from this configuration does, not what the linked run did
(`replayedWithNanoda`) — and points the comparator at it via `COMPARATOR_NANODA`; the relative
`../nanoda_lib/…` path resolves
because the run line first cd's into the project directory, a sibling of the two clones. -/
def reproCommands (cmp : TrustComparator) : List String :=
  let branchFlag := if cmp.toolRef.isEmpty then "" else s!"--branch {cmp.toolRef} "
  let cloneTool := s!"git clone {branchFlag}https://github.com/leanprover/comparator.git comparator-tool"
  -- A tag is mutable. When CI recorded the exact commit it resolved to, check that
  -- out so the reader runs the same tool, not "whatever the tag points at today".
  let pinTool :=
    if cmp.toolSha.isEmpty then []
    else [s!"(cd comparator-tool && git checkout {cmp.toolSha})"]
  let buildTool := "(cd comparator-tool && lake build lean4export comparator)"
  let nanodaBuild :=
    if cmp.enableNanoda then
      -- Same reasoning for the independent kernel: CI pins nanoda by revision, so the
      -- reproduce flow must too, or it is checking a different program.
      ["git clone https://github.com/ammkrn/nanoda_lib.git"] ++
      (if cmp.nanodaRef.isEmpty then []
       else [s!"(cd nanoda_lib && git checkout {cmp.nanodaRef})"]) ++
      ["(cd nanoda_lib && cargo build --release --locked)"]
    else []
  let nanodaEnv :=
    if cmp.enableNanoda then "COMPARATOR_NANODA=../nanoda_lib/target/release/nanoda_bin " else ""
  let projectClone := if cmp.repoUrl.isEmpty then [] else [s!"git clone {cmp.repoUrl}"]
  let projectDir :=
    if cmp.repoUrl.isEmpty then "path/to/your/project"
    else ((cmp.repoUrl.splitOn "/").getLast?).getD "your-project"
  let runLines :=
    if cmp.configArgPath.isEmpty then []
    else [s!"cd {projectDir}", s!"{nanodaEnv}lake env ../comparator-tool/.lake/build/bin/comparator {cmp.configArgPath}"]
  projectClone ++ [cloneTool] ++ pinTool ++ [buildTool] ++ nanodaBuild ++ runLines

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
  -- Blob URLs at the pinned commit, via the shared source-link builder (auto GitHub
  -- when the file is in a checkout with a GitHub `origin`; degrades to none).
  if !chalPath.isEmpty then
    if let some blob ← liftM <| sourceLinkHref? opts workspaceRoot none
        (some (absOptionPath workspaceRoot chalPath)) none then
      cmp := { cmp with githubChallengeUrl := blob }
      if let some raw := blobToRawGitHubUrl? blob then
        cmp := { cmp with
          playgroundUrl :=
            s!"https://live.lean-lang.org/#project={playgroundMathlibProjectId}&url={System.Uri.escapeUri raw}" }
  if !solPath.isEmpty then
    if let some blob ← liftM <| sourceLinkHref? opts workspaceRoot none
        (some (absOptionPath workspaceRoot solPath)) none then
      cmp := { cmp with githubSolutionUrl := blob }
  if !cfgPath.isEmpty then
    if let some blob ← liftM <| sourceLinkHref? opts workspaceRoot none
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

/-- The date part (`YYYY-MM-DD`) of an ISO-8601 timestamp; the whole string when there
is no `T` separator. -/
private def isoDate (s : String) : String := (s.splitOn "T").headD s

/--
The comparator verdict badge, linking to the standalone `comparator/` page.

The label is deliberately **"comparator: CI-verified ⟨date⟩"**, not "verified". The
badge is a read-back of a JSON artifact a past CI run wrote; nothing is re-checked
when this page is built, and a hand-edited artifact would render the same pill. The
wording therefore names the source (CI) and the moment (the date) rather than
asserting a present-tense property of the site.
-/
def trustComparatorBadge (cmp : TrustComparator) : Output.Html :=
  let theoremsTitle :=
    if cmp.theoremNames.isEmpty then ""
    else s!"; certified: {String.intercalate ", " cmp.theoremNames}"
  if cmp.status == "verified" then
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
      let text :=
        match theoremLikeTotal with
        | Option.some n => s!"certifies {k} {noun} of {n}"
        | Option.none => s!"certifies {k} named {noun}"
      {{ <span class="bp_trust_strip_scope">{{.text true text}}</span> }}

/-- Aggregate scope line for the multi-config trust surface: total certified
theorems across all comparator topics, out of the site's theorem-like total, and
how many comparator configs did the certifying. -/
def trustAggregateScopeHtml (comparators : List ComparatorTopic)
    (theoremLikeTotal : Option Nat) : Output.Html :=
  if comparators.isEmpty then .empty
  else
    let k := (comparators.map (·.comparator.theoremNames.length)).foldl (· + ·) 0
    let m := comparators.length
    let noun := if k == 1 then "theorem" else "theorems"
    let cfgNoun := if m == 1 then "comparator config" else "comparator configs"
    let text :=
      match theoremLikeTotal with
      | Option.some n => s!"certifies {k} {noun} of {n} across {m} {cfgNoun}"
      | Option.none => s!"certifies {k} named {noun} across {m} {cfgNoun}"
    {{ <span class="bp_trust_strip_scope">{{.text true text}}</span> }}

/-- The multi-config comparator badge: how many of the M configs are verified,
linking to the comparator page. -/
def trustAggregateComparatorBadge (comparators : List ComparatorTopic) : Output.Html :=
  let m := comparators.length
  let cfgNoun := if m == 1 then "config" else "configs"
  let verified := (comparators.filter (·.comparator.status == "verified")).length
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

/--
The rendered strip: a labelled badge row.

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

def trustStripAssetBundle : BlueprintAssetBundle :=
  blueprintCssAssetBundle [trustStripCss]

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
can reuse a stale success; a cold build — CI, or any build after the document module
itself changes — always re-checks. The binding is therefore a property of the build that
produced a site from scratch, which is the build that publishes it. (Verified: a
substituted challenge file is accepted by a warm rebuild and rejected as soon as the
module re-elaborates.)
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
Internal completeness of the status artifact's own run-evidence fields.

A record claiming an independent kernel replay must say *which* kernel: `nanoda_replay:
true` without a `nanoda_ref` is a claim nobody can check or reproduce, and the page would
render it as a second-kernel assurance. Hard error.

Public for the same reason as `checkComparatorDigests`.
-/
def checkComparatorRunProvenance (cmp : TrustComparator) (statusPath : String) :
    Lean.CoreM Unit := do
  if cmp.replayedWithNanoda && cmp.nanodaRef.trimAscii.toString.isEmpty then
    throwError "{statusPath} records `nanoda_replay: true` but no `nanoda_ref`. An \
      independent kernel replay with no recorded revision cannot be reproduced or \
      assessed for currency, and would be rendered as a second-kernel assurance. Record \
      the nanoda revision the run used, or drop the claim."

/-- Normalize a filesystem path for comparison: separators to `/`, `./` segments
dropped. Deliberately does **not** resolve `..` — the two paths being compared are
rooted differently by design. -/
def normalizePathForCompare (p : String) : String :=
  let segs := ((p.replace "\\" "/").splitOn "/").filter fun s => s != "." && !s.isEmpty
  String.intercalate "/" segs

/-- Whether `path` ends with `suffix` on a *path-component* boundary.

The consumer's option paths resolve against the build CWD (`site/`), while the
status artifact records repo-root-relative paths, so the same file is spelled
`../comparator/comparator.json` and `comparator/comparator.json`. Comparing the
strings would reject every correctly-configured project; comparing components
catches a genuinely different file while accepting a different root. -/
def pathHasSuffix (path suffix : String) : Bool :=
  let ps := (normalizePathForCompare path).splitOn "/"
  let ss := (normalizePathForCompare suffix).splitOn "/"
  ss.length ≤ ps.length && ss == ps.drop (ps.length - ss.length)

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

/--
Read a file once as bytes, returning its SHA-256 digest and its decoded text.

One read, one digest: hashing the same bytes that become the displayed text is what
makes the digest a statement about what the page shows, rather than about a second read
that could differ from it.
-/
private def readSourceWithDigest (path : String) : IO (String × String) := do
  let bytes ← IO.FS.readBinFile path
  match String.fromUTF8? bytes with
  | Option.some decoded => pure (Informal.Sha256.hex bytes, decoded)
  | Option.none =>
    throw <| IO.userError s!"{path} is not valid UTF-8, so it cannot be displayed verbatim."

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
statement it certifies is unreadable). `statusPath` is used only for error text.
-/
def attachComparatorSources (cmp0 : TrustComparator)
    (statusPath cfgPath chalPath solPath liveProject : String) :
    PartElabM TrustComparator := do
  let mut cmp := cmp0
  let mut configJson? : Option Json := Option.none
  if !cfgPath.isEmpty then
    if (← System.FilePath.pathExists cfgPath) then
      let (digest, raw) ← readSourceWithDigest cfgPath
      cmp := { cmp with configDigest := digest }
      match Json.parse raw with
      | .ok j =>
        configJson? := Option.some j
        cmp := { cmp with
          configJson := j.pretty
          enableNanoda := (j.getObjValAs? Bool "enable_nanoda").toOption.getD false }
      | .error _ =>
        cmp := { cmp with configJson := raw }
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
  if !solPath.isEmpty then
    if (← System.FilePath.pathExists solPath) then
      let (digest, src) ← readSourceWithDigest solPath
      cmp := { cmp with solutionSource := src, solutionDigest := digest }
  liftM (checkComparatorDigests cmp statusPath)
  liftM (checkComparatorRunProvenance cmp statusPath)
  if let some cfgJson := configJson? then
    liftM (crossCheckComparator cmp cfgJson statusPath cfgPath chalPath solPath)
  if !liveProject.isEmpty && !cmp.challengeSource.isEmpty && !cmp.solutionSource.isEmpty then
    cmp := { cmp with
      comparatorLiveUrl := comparatorLivePermalink liveProject cmp.challengeSource cmp.solutionSource }
  return cmp

open Verso Doc Elab in
/--
Build the multi-config comparator + axiom-audit topics from the JSON manifest
named by `verso.blueprint.trust.comparatorTopics` (`""` ⇒ none). A missing or
unparsable manifest, or a topic missing its `status` (comparator) / `decls`
(axiom-audit), is a build error: a configured multi-config surface must not
vanish silently. Paths inside the manifest resolve against the build CWD, like
the single-pair options. Reads `verso.blueprint.trust.comparatorLiveProject` for
the per-topic comparator.live permalink.
-/
def elabComparatorTopics? : PartElabM (List ComparatorTopic × List AxiomAuditTopic) := do
  let opts ← Lean.getOptions
  let path := opts.get verso.blueprint.trust.comparatorTopics.name
    verso.blueprint.trust.comparatorTopics.defValue
  if path.isEmpty then return ([], [])
  unless ← System.FilePath.pathExists path do
    throwError "option 'verso.blueprint.trust.comparatorTopics' names a missing file (resolved \
      against the build directory): {path}"
  let doc ← match Json.parse (← IO.FS.readFile path) with
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
      let cmp0 ← match Json.parse (← IO.FS.readFile statusPath) with
        | .error err => throwError "could not parse {statusPath} (topic '{name}'): {err}"
        | .ok j => pure (TrustComparator.ofJson j)
      let cfgPath := str? t "config"
      let chalPath := str? t "challenge"
      let solPath := str? t "solution"
      let cmp ← attachComparatorSources cmp0 statusPath cfgPath chalPath solPath liveProject
      -- Same source enrichment (highlighting + links) as the single-pair path.
      let cmp ← liftM (enrichComparatorSources opts workspaceRoot cmp chalPath solPath cfgPath)
      let topicEntry : ComparatorTopic := { name, comparator := cmp }
      comparators := comparators ++ [topicEntry]
  return (comparators, axiomTopics)

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
  if yamlPath.isEmpty && cmpPath.isEmpty && topicsPath.isEmpty then
    return Option.none
  let mut trust : TrustData := {}
  if !yamlPath.isEmpty then
    if !(← System.FilePath.pathExists yamlPath) then
      throwError "option 'verso.blueprint.trust.formalizationYaml' names a missing file (resolved against the build directory): {yamlPath}"
    match Informal.FormalizationYaml.parse (← IO.FS.readFile yamlPath) with
    | .error err => throwError "could not parse {yamlPath}: {err}"
    | .ok doc =>
      trust := TrustData.ofFormalizationJson doc
  if !cmpPath.isEmpty then
    if !(← System.FilePath.pathExists cmpPath) then
      throwError "option 'verso.blueprint.trust.comparatorStatus' names a missing file (resolved against the build directory): {cmpPath}"
    match Json.parse (← IO.FS.readFile cmpPath) with
    | .error err => throwError "could not parse {cmpPath}: {err}"
    | .ok j => trust := { trust with comparator := Option.some (TrustComparator.ofJson j) }
  -- Embed the comparator's config JSON + Challenge/Solution Lean source verbatim on the
  -- comparator page. Unlike the two required options above, these degrade silently
  -- when their file is empty/missing (probe-and-degrade) and only attach when a
  -- comparator verdict exists.
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
    let cmp ← attachComparatorSources cmp cmpPath cfgPath chalPath solPath liveProject
    trust := { trust with comparator := Option.some cmp }
  -- Multi-config comparator + axiom-audit topics, independent of the single-pair
  -- options above (a consumer uses one scheme or the other).
  let (comparators, axiomAuditTopics) ← elabComparatorTopics?
  trust := { trust with comparators, axiomAuditTopics }
  -- Layer on the comparator-source enrichment (syntax highlighting + source links).
  -- Runs in `CoreM`; degrades to empty fields, never a build error.
  trust := (← liftM (enrichTrustData opts trust))
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
  | .ok doc => return Option.some doc

end Informal.Commands
