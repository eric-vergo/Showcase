/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.NodePage
import VersoBlueprint.TraversalIndex
import VersoBlueprint.Commands.TrustStrip
import VersoBlueprint.GraphApi
import VersoBlueprint.GraphChecks
import VersoBlueprint.NodeRoute

/-!
Statement-comparator evidence page.

`emitBlueprintComparatorPage` is a generation-time `ExtraStep` reading the
trust-strip payload cached during traversal (`TraversalIndex.TrustData`, saved by
`Block.trustStrip`'s traverse). When a statement comparator is configured it emits a
single claim-first `comparator/` page: a verdict header (status, date, certified
theorems and their *scope*, permitted axioms, CI link), the challenge statement
("the claim"), a plain account of what the comparator does and does not check, the
one human step the reader must still perform, and a three-tier "reproduce it
yourself" section (Lean playground / comparator.live, CI record, exact local
commands pinned to the artifacts CI actually used), followed by the Solution source
and the comparator configuration. Canonical comparator documentation is linked, not
restated.

Sections probe-and-degrade *except* the claim: a comparator verdict rendered
without the statement it certifies is the one failure mode this page cannot have,
so a configured-but-unreadable challenge file is a build error and an unconfigured
one renders an explicit notice rather than silently omitting the section.

The structural `uses`-graph gate that used to live here is now
`Informal.GraphGate`, run between traversal and emission so a failing gate leaves
no rendered site on disk.
-/

namespace Informal.Commands

open Lean
open Verso Verso.Output Verso.Doc
open Verso.Genre Manual
open Verso.Output.Html

/-- Standard page shell: the reset content header (heading + optional lead paragraph)
followed by the page body. The lead `<p>` is omitted when `intro` is empty. -/
private def trustPageShell (heading intro : String) (body : Output.Html) : Output.Html :=
  let introHtml : Output.Html :=
    if intro.isEmpty then .empty
    else {{ <p class="bp_pm_page_intro">{{.text true intro}}</p> }}
  {{
    <div class="bp_summary bp_pm_page bp_trust_page">
      <header class="bp_node_page_header">
        <h1>{{.text true heading}}</h1>
        {{introHtml}}
      </header>
      {{body}}
    </div>
  }}

/-- One titled section. -/
private def trustSection (title : String) (body : Output.Html) : Output.Html :=
  {{
    <section class="bp_trust_section">
      <h2 class="bp_trust_section_title">{{.text true title}}</h2>
      {{body}}
    </section>
  }}

/-- A quiet outbound link. -/
private def trustOutLink (href label : String) : Output.Html :=
  {{ <a class="bp_trust_out_link" href={{href}} target="_blank" rel="noopener">{{.text true label}}</a> }}

/-- A code block: highlighted token markup when available (wrapped in
`<code class="hl lean">` so the shared `--verso-code-*` colors apply in both themes),
else escaped plain text.

Both branches carry a rendering-tier marker, because both are weaker than a
re-elaborated node card: the Lean blocks here are highlighted *syntactically* (the
module highlighter runs with empty info trees), and the fallback is raw text. A
reader comparing this page against a node card should be able to see that. -/
private def trustCodeBlock (extraClass htmlMarkup fallback : String) : Output.Html :=
  if htmlMarkup.isEmpty then
    {{ <pre class={{s!"bp_trust_code {extraClass}"}}>
         {{Informal.NodeCard.tierMarker (some "raw")}}{{.text true fallback}}
       </pre> }}
  else
    {{ <pre class={{s!"bp_trust_code {extraClass}"}}>
         {{Informal.NodeCard.tierMarker (some "syntactic")}}
         <code class="hl lean">{{.text false htmlMarkup}}</code>
       </pre> }}

/-! ## Comparator page -/

/-- The date part (`YYYY-MM-DD`) of an ISO-8601 timestamp; the whole string if there is no
`T` separator. -/
private def isoDateOnly (s : String) : String :=
  (s.splitOn "T").headD s

/-- Render `items` as a comma-separated run of inline `<code>` elements. Empty ⇒ `.empty`. -/
private def inlineCodeList (items : List String) : Output.Html :=
  match items with
  | [] => .empty
  | first :: rest =>
    let code (s : String) : Output.Html := {{ <code>{{.text true s}}</code> }}
    rest.foldl (init := code first) fun acc x => .seq #[acc, {{ ", " }}, code x]

/-- The verdict header: a status pill ("Verified"/success, "Configured — not yet run"/warn,
else the raw status), an optional `<time>` (from `verified_at`, date-only), and an optional
"CI verification record" link, followed by a compact `<dl>` of the certified theorem(s) and
permitted axioms (each row omitted when its data is empty). -/
private def comparatorVerdictHeader (cmp : TrustComparator) (ciUrl? : Option String)
    (theoremLikeTotal : Option Nat) : Output.Html :=
  -- "Verified" alone reads as a live claim about the site you are looking at. The
  -- verdict is a *record of a past CI run* read back from a JSON artifact, so the
  -- pill says so and dates itself.
  let pill : Output.Html :=
    if cmp.status == "verified" then
      let label :=
        if cmp.verifiedAt.isEmpty then "CI-verified"
        else s!"CI-verified {isoDateOnly cmp.verifiedAt}"
      trustBadgeHtml label "success"
        (Option.some "Recorded by the project's CI run; this page reads that run's artifact back, it does not re-run the check.")
    else if cmp.status == "configured" then trustBadgeHtml "Configured — not yet run" "warn"
    else trustBadgeHtml cmp.status
  let date : Output.Html :=
    if cmp.verifiedAt.isEmpty then .empty
    else {{ <time class="bp_trust_verdict_date" datetime={{cmp.verifiedAt}}>{{.text true (isoDateOnly cmp.verifiedAt)}}</time> }}
  let ci : Output.Html :=
    match ciUrl? with
    | some u => trustOutLink u "CI verification record"
    | none => .empty
  -- Scope, stated where the verdict is: the comparator certifies the named
  -- theorems, not the development.
  let scope : Output.Html :=
    if cmp.theoremNames.isEmpty then .empty
    else
      let k := cmp.theoremNames.length
      let noun := if k == 1 then "theorem" else "theorems"
      let text :=
        match theoremLikeTotal with
        | some n =>
          s!"Certifies {k} {noun} of the {n} theorem-like results presented here. \
             Everything else on this site is built and axiom-audited, but not comparator-certified."
        | none =>
          s!"Certifies {k} named {noun}. Everything else on this site is built and \
             axiom-audited, but not comparator-certified."
      {{ <p class="bp_trust_verdict_scope">{{.text true text}}</p> }}
  let theoremRow : Output.Html :=
    if cmp.theoremNames.isEmpty then .empty
    else {{ <div><dt>"Certified theorem(s)"</dt><dd>{{inlineCodeList cmp.theoremNames}}</dd></div> }}
  let axiomRow : Output.Html :=
    if cmp.permittedAxioms.isEmpty then .empty
    else {{ <div><dt>"Permitted axioms"</dt><dd>{{inlineCodeList cmp.permittedAxioms}}</dd></div> }}
  let toolRow : Output.Html :=
    let refs :=
      (if cmp.toolSha.isEmpty then [] else [s!"comparator {cmp.toolSha}"]) ++
      (if cmp.toolRef.isEmpty || !cmp.toolSha.isEmpty then [] else [s!"comparator {cmp.toolRef}"]) ++
      (if cmp.nanodaRef.isEmpty then [] else [s!"nanoda {cmp.nanodaRef}"]) ++
      (if cmp.landrunRef.isEmpty then [] else [s!"landrun {cmp.landrunRef}"])
    match refs with
    | [] => .empty
    | _ => {{ <div><dt>"Checked with"</dt><dd>{{inlineCodeList refs}}</dd></div> }}
  let metaHtml : Output.Html :=
    if cmp.theoremNames.isEmpty && cmp.permittedAxioms.isEmpty
        && cmp.toolSha.isEmpty && cmp.toolRef.isEmpty
        && cmp.nanodaRef.isEmpty && cmp.landrunRef.isEmpty then .empty
    else {{ <dl class="bp_trust_verdict_meta">{{.seq #[theoremRow, axiomRow, toolRow]}}</dl> }}
  {{
    <section class="bp_trust_verdict">
      <div class="bp_trust_verdict_row">{{.seq #[pill, date, ci]}}</div>
      {{scope}}
      {{metaHtml}}
    </section>
  }}

/-- The "Reproduce it yourself" section: up to three tiers, each dropped when its data is
absent. Tier 1 opens the challenge in the Lean playground (needs `playgroundUrl`); tier 2
links the CI verification record (needs a CI url); tier 3 is always present — the local shell
commands from `reproCommands`, with fallback notes when the tool version or config path are
unknown, and always the Landlock-sandbox caveat. -/
private def comparatorReproSection (cmp : TrustComparator) (ciUrl? : Option String) : Output.Html :=
  let tier1 : Option Output.Html :=
    if cmp.playgroundUrl.isEmpty then none
    else some {{
      <li>
        {{trustOutLink cmp.playgroundUrl "Open the challenge in the Lean playground"}}
        " — a zero-install check that the claim elaborates against the playground's current "
        "Mathlib. This checks the challenge statement only, not its comparison against the solution."
      </li> }}
  let tier2 : Option Output.Html :=
    match ciUrl? with
    | some u =>
      -- With the independent nanoda replay enabled, name both kernels here.
      let replayNote :=
        if cmp.enableNanoda then
          " — the exact run that produced this verdict, Lean-kernel and nanoda replays included."
        else
          " — the exact run that produced this verdict, kernel replay included."
      some {{
        <li>
          {{trustOutLink u "The CI verification record"}}
          {{.text true replayNote}}
        </li> }}
    | none => none
  let toolRefNote : Output.Html :=
    if !cmp.toolRef.isEmpty then .empty
    else {{
      <p class="bp_trust_note">
        "No comparator version is recorded here — check out the "
        {{trustOutLink "https://github.com/leanprover/comparator/tags" "comparator tag"}}
        " matching the project's " <code>"lean-toolchain"</code> " before building."
      </p> }}
  let configNote : Output.Html :=
    if !cmp.configArgPath.isEmpty then .empty
    else {{
      <p class="bp_trust_note">
        "The comparator configuration path is not recorded here; see the project README for "
        "the exact " <code>"comparator"</code> " invocation."
      </p> }}
  -- The reproduce commands are only worth printing if they are at least as strong as
  -- what CI ran. Where they are weaker, say so here rather than let the reader assume
  -- parity.
  let landrunInstallCommand : String → String := fun ref =>
    s!"go install github.com/Zouuup/landrun/cmd/landrun@{ref}"
  let nanodaPinNote : Output.Html :=
    if !cmp.enableNanoda then .empty
    else if !cmp.nanodaRef.isEmpty then .empty
    else {{
      <p class="bp_trust_note">
        "The status artifact records no nanoda revision, so the clone above is "
        <em>"unpinned"</em>
        " and will build whatever is on nanoda's default branch — not necessarily the \
         revision CI used. Check the CI run's log for the exact revision."
      </p> }}
  let landrunNote : Output.Html :=
    if cmp.landrunRef.isEmpty then
      {{
        <p class="bp_trust_note">
          "CI runs the solution inside a "
          {{trustOutLink "https://landlock.io/" "Landlock"}}
          " sandbox; the commands above do not install that sandbox, and on macOS or in a "
          "plain development shell there is no Landlock at all. The local run is therefore a "
          "kernel check without the sandbox, which is weaker than what CI performed."
        </p> }}
    else
      {{
        <p class="bp_trust_note">
          "CI additionally confines the solution in a "
          {{trustOutLink "https://landlock.io/" "Landlock"}}
          " sandbox (landrun " <code>{{.text true cmp.landrunRef}}</code>
          "). To match it on Linux, install landrun at that revision first — "
          <code>{{.text true (landrunInstallCommand cmp.landrunRef)}}</code>
          " — and re-run under it. Without that step, and always on macOS, the local run is "
          "a kernel check without the "
          "sandbox: weaker than what CI performed."
        </p> }}
  let shell : Output.Html :=
    {{ <pre class="bp_trust_code bp_trust_code_shell">{{.text true (String.intercalate "\n" (reproCommands cmp))}}</pre> }}
  let tier3 : Output.Html :=
    {{
      <li>
        "Run the check locally from a clean working directory:"
        {{shell}}
        {{.seq #[toolRefNote, configNote, nanodaPinNote, landrunNote]}}
      </li> }}
  let items := ([tier1, tier2].filterMap id) ++ [tier3]
  trustSection "Reproduce it yourself"
    {{ <ol class="bp_trust_repro">{{.seq items.toArray}}</ol> }}

/-- Body of the claim-first `comparator/` page. A verdict header, the challenge statement
("the claim"), a plain account of what the comparator does and does not check, the human step
the reader must still perform, a three-tier "reproduce it yourself" section, then the Solution
source and the comparator configuration. Each section probes-and-degrades to nothing when its
data is absent. -/
private def comparatorBody (cmp : TrustComparator) (ciUrl? : Option String)
    (theoremLikeTotal : Option Nat) (trustModelHref? : Option String) : Output.Html :=
  -- 1. Verdict header (pill + date + CI link + scope + certified theorems + axioms + tool refs).
  let verdict := comparatorVerdictHeader cmp ciUrl? theoremLikeTotal
  -- 2. "The claim": the challenge statement, verbatim, with GitHub / playground /
  --    comparator.live links.
  --
  --    This section FAILS CLOSED. A comparator verdict shown without the statement it
  --    certifies is the worst thing this page can do: the reader sees a green verdict
  --    and has no way to read what was actually proved. Where the claim is
  --    unavailable, say so loudly instead of dropping the section (the *configured*
  --    but unreadable case is already a build error in `elabTrustData?`).
  let claimSection : Output.Html :=
    if cmp.challengeSource.isEmpty then
      trustSection "The claim"
        {{
          <p class="bp_trust_prose bp_trust_prose_warning">
            "This project does not publish the challenge statement alongside its verdict. "
            "The verdict above therefore cannot be read on its own: without the statement, "
            "there is no way to tell what was certified. Consult the comparator "
            "configuration below and the project's repository for the challenge file, and "
            "treat the verdict as unconfirmed until you have read it."
          </p> }}
    else
      let ghLink : Option Output.Html :=
        if cmp.githubChallengeUrl.isEmpty then Option.none
        else Option.some (trustOutLink cmp.githubChallengeUrl "View on GitHub")
      let pgLink : Option Output.Html :=
        if cmp.playgroundUrl.isEmpty then Option.none
        else Option.some (trustOutLink cmp.playgroundUrl "Open in Lean playground (current Mathlib)")
      let liveLink : Option Output.Html :=
        if cmp.comparatorLiveUrl.isEmpty then Option.none
        else Option.some
          (trustOutLink cmp.comparatorLiveUrl "Inspect this claim on comparator.live")
      let linkItems := ([ghLink, pgLink, liveLink].filterMap id)
      let linksRow : Output.Html :=
        match linkItems with
        | [] => .empty
        | first :: rest =>
          let joined := rest.foldl (init := first) fun acc x => .seq #[acc, {{ " · " }}, x]
          {{ <p class="bp_trust_links">{{joined}}</p> }}
      -- The comparator.live link is an *inspection* link, not a second verdict: it
      -- pre-fills both sources, but the solution imports the project's own library,
      -- which the in-browser environment does not carry. Say so, so nobody reads a
      -- failed in-browser run as a failed proof.
      let liveNote : Output.Html :=
        if cmp.comparatorLiveUrl.isEmpty then .empty
        else {{
          <p class="bp_trust_note">
            "comparator.live is experimental infrastructure run by the Lean FRO. The link "
            "pre-fills this exact challenge and solution in a live Lean and Mathlib "
            "environment, so both sources can be read and edited in the browser. It does not "
            "re-run the verdict: the solution imports this project's library, which "
            "comparator.live does not provide, so the pair check there stops at that import. "
            "Full verification is the CI run linked above and the local steps below."
          </p> }}
      trustSection "The claim"
        (.seq #[linksRow,
          trustCodeBlock "bp_trust_code_lean" cmp.challengeHtml cmp.challengeSource,
          liveNote])
  -- 3. What this page certifies (static prose).
  let kernelClause : Output.Html :=
    if cmp.enableNanoda then
      {{ "Lean kernel — and, independently, the nanoda kernel, a separate reimplementation of "
         "Lean's type checker — to confirm that the solution proves exactly the challenge "
         "statements, using only the permitted axioms listed above." }}
    else
      {{ "Lean kernel to confirm that the solution proves exactly the challenge statements, using "
         "only the permitted axioms listed above." }}
  let certifiesSection : Output.Html :=
    trustSection "What this page certifies"
      {{
        <p class="bp_trust_prose">
          "The statement comparator is an independent checking tool maintained by the Lean "
          "project. It elaborates the challenge and the solution in separate environments, so the "
          "solution cannot weaken or restate the claims it is measured against, and then asks the "
          {{kernelClause}}
        </p> }}
  -- 4. What you must still check yourself (the one non-automatable step).
  let reproducedClause : Output.Html :=
    if cmp.challengeSource.isEmpty then .empty else {{ " (reproduced in full above)" }}
  let checkSection : Output.Html :=
    trustSection "What you must still check yourself"
      (.seq #[
        {{
          <p class="bp_trust_prose">
            "One step is not automatable, and the comparator does not attempt it: reading the "
            "claim. The formal statement" {{reproducedClause}} " must say what you take it to say, "
            "and its imports must bring in nothing beyond a library you already trust — here, "
            "Mathlib. A statement that quietly assumes its own conclusion, or that pulls in an "
            "axiom-bearing helper, would still pass the comparator."
          </p> }},
        {{
          <p class="bp_trust_prose_links">
            {{trustOutLink "https://github.com/leanprover/comparator" "About the statement comparator"}}
            " · "
            {{trustOutLink "https://lean-lang.org/doc/reference/latest/ValidatingProofs" "Validating proofs (Lean reference)"}}
            {{match trustModelHref? with
              | some href => Output.Html.seq #[{{ " · " }}, {{ <a href={{href}}>"Trust model and limitations"</a> }}]
              | none => Output.Html.empty}}
          </p> }}
      ])
  -- 5. Reproduce it yourself (three tiers).
  let reproSection := comparatorReproSection cmp ciUrl?
  -- 6. Solution file: the project's actual proof of the challenge statement.
  let solutionSection : Output.Html :=
    if cmp.solutionSource.isEmpty then .empty
    else
      let ghLink : Output.Html :=
        if cmp.githubSolutionUrl.isEmpty then .empty
        else {{ <p class="bp_trust_links">{{trustOutLink cmp.githubSolutionUrl "View on GitHub"}}</p> }}
      trustSection "Solution (Lean)"
        (.seq #[ghLink, trustCodeBlock "bp_trust_code_lean" cmp.solutionHtml cmp.solutionSource])
  -- 7. The comparator's configuration JSON, collapsible.
  let configSection : Output.Html :=
    if cmp.configJson.isEmpty then .empty
    else
      let cfgLink : Output.Html :=
        if cmp.githubConfigUrl.isEmpty then .empty
        else {{ <p class="bp_trust_links">{{trustOutLink cmp.githubConfigUrl "View config on GitHub"}}</p> }}
      trustSection "Comparator configuration"
        (.seq #[cfgLink,
          {{ <details class="bp_trust_disclosure">
               <summary>"Show comparator configuration"</summary>
               {{trustCodeBlock "bp_trust_code_json" cmp.configHtml cmp.configJson}}
             </details> }}])
  trustPageShell "Statement comparator" ""
    (.seq #[verdict, claimSection, certifiesSection, checkSection, reproSection, solutionSection, configSection])

/-! ## Emission -/

/-- Decode the (possibly-empty) trust payload cached during traversal. -/
private def cachedTrust? (state : TraverseState) : Option TrustData :=
  (Informal.TraversalIndex.TrustData.raw? state).bind fun json =>
    (fromJson? (α := TrustData) json).toOption

/--
`ExtraStep` that emits the claim-first `comparator/` page from the traversal-cached trust
payload, when a statement comparator is configured. Single-page mode is skipped; when no
comparator is configured it emits nothing. The CI-run link (used in the verdict header and
tier 2 of the reproduce section) prefers the status artifact's own `run_url`, falling back to
the `verso.blueprint.trust.ciRunUrl` option.
-/
def emitBlueprintComparatorPage : ExtraStep :=
  fun mode cfg state text => do
    match mode with
    | .single => pure ()
    | .multi =>
      let logger : Verso.Logger IO ← read
      match Informal.TraversalIndex.TrustData.raw? state, cachedTrust? state with
      | none, _ =>
        -- No trust payload at all: the document has no `blueprint_dashboard` block, so
        -- any `verso.blueprint.trust.*` configuration silently produced no evidence
        -- page. Removing the dashboard must not quietly remove the comparator record.
        logger.reportWarning
          "Showcase comparator page: no cached trust payload in traversal state; skipping \
           comparator/index.html. If `verso.blueprint.trust.comparatorStatus` is set, its \
           verdict is not being published (is a `blueprint_dashboard` block present?)."
      | some _, none =>
        logger.reportWarning
          "Showcase comparator page: the cached trust payload could not be decoded; \
           skipping comparator/index.html."
      | some _, some trust =>
        match trust.comparator with
        | none => pure ()
        | some cmp =>
          let ciUrl? : Option String :=
            if cmp.runUrl.isEmpty then trust.ciRunUrl else some cmp.runUrl
          -- "k of N": N counts every theorem-like node the site presents (theorems,
          -- lemmas, propositions, corollaries) — the population the certified set is
          -- a subset of.
          let theoremLikeTotal :=
            (Informal.TraversalIndex.Summary.cachedSummary? state).map fun s =>
              s.theorems + s.lemmas + s.propositions + s.corollaries
          let trustModelHref? := Informal.TraversalIndex.TrustModelPage.href? state
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            Informal.NodeRoute.comparatorPath "Statement comparator"
            (comparatorBody cmp ciUrl? theoremLikeTotal trustModelHref?)

end Informal.Commands
