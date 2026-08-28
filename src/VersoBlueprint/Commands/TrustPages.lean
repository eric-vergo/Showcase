/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Std.Data.HashMap
import VersoManual
import VersoBlueprint.NodePage
import VersoBlueprint.TraversalIndex
import VersoBlueprint.Commands.TrustStrip
import VersoBlueprint.Commands.StatementClosurePanel
import VersoBlueprint.DeclRegistry
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

/--
Currency of the verifier builds this record names, under the verdict that rests on them.

A pinned verifier is reproducible and ages, and the page has no way to tell those apart
for the reader except by saying which one it is looking at. One sentence per build, the
advisories it was measured against, and — always, whatever the verdicts — the clause that
ages the table itself: a fix published after the table was last revised is invisible
here, and a reader who is not told that will read silence as a clean bill.

A record naming no verifier build renders nothing at all, exactly as before.
-/
private def currencyNote (cmp : TrustComparator) : Output.Html :=
  if cmp.currency.isEmpty then .empty
  else
    let rows : Array Output.Html := cmp.currency.map fun c =>
      let rowClass :=
        if c.verdict == "stale" then "bp_trust_currency_row bp_trust_currency_stale"
        else "bp_trust_currency_row"
      let advisories : Array Output.Html := c.advisories.map fun a =>
        let dateText := if a.advisoryDate.isEmpty then "" else s!"{a.advisoryDate} — "
        let link : Output.Html :=
          if a.url.isEmpty then .empty
          else .seq #[{{ " " }}, trustOutLink a.url "Advisory"]
        -- The ancestry statement is worth its length in exactly one state: a real
        -- revision the table could not place. Where the label was never bound to a
        -- program, or the reference moves, resolving ancestry answers a question the
        -- record has not earned yet.
        let ancestry : Output.Html :=
          if c.reason != "unresolved" || a.state != "unresolved" || a.ancestry.isEmpty then .empty
          else {{ <span class="bp_trust_currency_ancestry">{{.text true a.ancestry}}</span> }}
        {{ <li>{{.text true (dateText ++ a.summary)}}{{link}}{{ancestry}}</li> }}
      let advisoryList : Output.Html :=
        if advisories.isEmpty then .empty
        else {{ <ul class="bp_trust_currency_advisories">{{.seq advisories}}</ul> }}
      {{
        <div class={{rowClass}}>
          <p class="bp_trust_currency_detail">{{.text true c.detail}}</p>
          {{advisoryList}}
        </div> }}
    let updated := (cmp.currency[0]?).map (·.advisoriesUpdated) |>.getD ""
    {{
      <div class="bp_trust_currency">
        {{.seq rows}}
        <p class="bp_trust_note">{{.text true (currencyAgingClause updated)}}</p>
      </div> }}

/-- The verdict header: a status pill ("CI-verified"/success, "Configured — not yet run"/warn,
"Reported upstream"/neutral, else the raw status), an optional `<time>`, and an optional
"CI verification record" link, followed by a compact `<dl>` of the certified theorem(s),
permitted axioms, and what the run was checked with (each row omitted when its data is
empty).

The date follows the status: `verified_at` dates a run this project's CI performed, and a
transcribed upstream record has no such run, so it shows the upstream record's own
`reported_at` or no date at all. -/
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
    else if cmp.isLocalVerdict then
      -- The checkers ran, so not the warning tier; nowhere near CI, so not the success
      -- tier. The date is this project's own `verified_at` and means the run happened.
      let label :=
        if cmp.verifiedAt.isEmpty then "Verified locally — not CI"
        else s!"Verified locally {isoDateOnly cmp.verifiedAt} — not CI"
      trustBadgeHtml label "accent" (Option.some cmp.localVerdictNote)
    else if cmp.isReportedUpstream then
      -- Neutral tier and the upstream's own date, if it recorded one. Nothing here was
      -- verified by this site's CI, so nothing here may borrow `verified_at`'s meaning.
      let label :=
        if cmp.reportedAt.isEmpty then "Reported upstream"
        else s!"Reported upstream {isoDateOnly cmp.reportedAt}"
      trustBadgeHtml label "" (Option.some cmp.reportedUpstreamNote)
    else trustBadgeHtml cmp.status
  let dateSource := if cmp.isReportedUpstream then cmp.reportedAt else cmp.verifiedAt
  let date : Output.Html :=
    if dateSource.isEmpty then .empty
    else {{ <time class="bp_trust_verdict_date" datetime={{dateSource}}>{{.text true (isoDateOnly dateSource)}}</time> }}
  let ci : Output.Html :=
    match ciUrl? with
    -- A locally-run verdict has no run record, and the site-wide CI URL is not one:
    -- offering it here would let a reader follow a link that did not produce this
    -- verdict and conclude that something did.
    | some u => if cmp.isLocalVerdict then .empty else trustOutLink u "CI verification record"
    | none => .empty
  -- Scope, stated where the verdict is: the comparator certifies the named
  -- theorems, not the development.
  let scope : Output.Html :=
    if cmp.theoremNames.isEmpty then .empty
    else
      let k := cmp.theoremNames.length
      let noun := if k == 1 then "theorem" else "theorems"
      let text :=
        if cmp.isReportedUpstream then
          -- "Certifies" is a claim about a check that happened. This one happened
          -- elsewhere, so the sentence says what it is instead.
          match theoremLikeTotal with
          | some n =>
            s!"Names {k} {noun} of the {n} theorem-like results presented here as verified \
               upstream. Nothing on this site re-checked them."
          | none =>
            s!"Names {k} {noun} as verified upstream. Nothing on this site re-checked them."
        else if cmp.isLocalVerdict then
          -- Something was certified; the sentence has to say by whom, because the party
          -- that ran the checkers is the party publishing this page.
          match theoremLikeTotal with
          | some n =>
            s!"A run on the presenter's own machine certified {k} {noun} of the {n} \
               theorem-like results presented here. No CI run re-checked it, and everything \
               else on this site is built and axiom-audited but not comparator-certified."
          | none =>
            s!"A run on the presenter's own machine certified {k} named {noun}. No CI run \
               re-checked it, and everything else on this site is built and axiom-audited \
               but not comparator-certified."
        else
          match theoremLikeTotal with
          | some n =>
            s!"Certifies {k} {noun} of the {n} theorem-like results presented here. \
               Everything else on this site is built and axiom-audited, but not comparator-certified."
          | none =>
            s!"Certifies {k} named {noun}. Everything else on this site is built and \
               axiom-audited, but not comparator-certified."
      {{ <p class="bp_trust_verdict_scope">{{.text true text}}</p> }}
  let localNote : Output.Html :=
    if !cmp.isLocalVerdict then .empty
    else {{ <p class="bp_trust_note">{{.text true cmp.localVerdictNote}}
              " The kernels really ran; what is absent is the provenance a CI record carries — \
               an isolated environment, and a run anyone can open."</p> }}
  let reportedNote : Output.Html :=
    if !cmp.isReportedUpstream then .empty
    else {{ <p class="bp_trust_note">{{.text true cmp.reportedUpstreamNote}}
              " Read it as provenance, not as verification performed here."</p> }}
  let theoremRow : Output.Html :=
    if cmp.theoremNames.isEmpty then .empty
    else {{ <div><dt>"Certified theorem(s)"</dt><dd>{{inlineCodeList cmp.theoremNames}}</dd></div> }}
  let axiomRow : Output.Html :=
    if cmp.permittedAxioms.isEmpty then .empty
    else {{ <div><dt>"Permitted axioms"</dt><dd>{{inlineCodeList cmp.permittedAxioms}}</dd></div> }}
  let toolRow : Output.Html :=
    -- "Checked with" is a statement about the linked run, so a checker appears here only
    -- when the run recorded that it replayed, recorded which revision, and recorded
    -- enough to authenticate the name. A `nanoda_ref` beside a record that never says the
    -- replay happened pins a revision, not a second check; a label the comparator was
    -- told to print is not a program at all, and belongs in the table below with its
    -- provenance rather than in a row of things that checked this proof.
    let kernelRefs :=
      (cmp.assuredKernels.filterMap fun k =>
        let ref := cmp.recordedKernelRef k
        if ref.isEmpty then none else some s!"{k} {ref}").toList
    let refs :=
      (if cmp.toolSha.isEmpty then [] else [s!"comparator {cmp.toolSha}"]) ++
      (if cmp.toolRef.isEmpty || !cmp.toolSha.isEmpty then [] else [s!"comparator {cmp.toolRef}"]) ++
      kernelRefs ++
      (if cmp.landrunRef.isEmpty then [] else [s!"landrun {cmp.landrunRef}"])
    match refs with
    | [] => .empty
    | _ => {{ <div><dt>"Checked with"</dt><dd>{{inlineCodeList refs}}</dd></div> }}
  -- The tool reads the project's oleans, which carry a compiler stamp, so which Lean
  -- release the tool was built on is part of what ran — and of what a reader must
  -- reproduce.
  let toolchainRow : Output.Html :=
    if cmp.toolToolchain.isEmpty then .empty
    else {{ <div><dt>"Tool built on"</dt><dd>{{inlineCodeList [cmp.toolToolchain]}}</dd></div> }}
  let metaHtml : Output.Html :=
    if cmp.theoremNames.isEmpty && cmp.permittedAxioms.isEmpty
        && cmp.toolSha.isEmpty && cmp.toolRef.isEmpty && cmp.toolToolchain.isEmpty
        && (cmp.recordedKernelRef "nanoda").isEmpty && cmp.kernelRefs.isEmpty
        && cmp.landrunRef.isEmpty then .empty
    else {{ <dl class="bp_trust_verdict_meta">{{.seq #[theoremRow, axiomRow, toolRow, toolchainRow]}}</dl> }}
  {{
    <section class="bp_trust_verdict">
      <div class="bp_trust_verdict_row">{{.seq #[pill, date, ci]}}</div>
      {{scope}}
      {{localNote}}
      {{reportedNote}}
      {{metaHtml}}
      {{currencyNote cmp}}
    </section>
  }}


/-- What the run's record authenticates about one labeled checker, as a cell: the
program, or the fact that nothing names it. -/
private def kernelIdentityCell (cmp : TrustComparator) (label : String) :
    String × Output.Html :=
  let ref := cmp.recordedKernelRef label
  let argvNote : Output.Html :=
    match (cmp.identityFor? label).map (·.commandArgv) with
    | some argv =>
      match argv[0]? with
      | some exe => {{ " · ran " <code>{{.text true exe}}</code> }}
      | none => .empty
    | none => .empty
  match cmp.kernelIdentityTier label with
  | "named" =>
    let record? := cmp.identityFor? label
    let commit := (record?.map (·.sourceCommit)).getD ""
    let digest := (record?.map (·.executableSha256)).getD ""
    ("", {{ <code>{{.text true commit}}</code> " · binary " <code>{{.text true digest}}</code>
            " · agrees with the identity this site pinned" }})
  | "bound" =>
    let record? := cmp.identityFor? label
    let repo := (record?.map (·.repository)).getD ""
    let commit := (record?.map (·.sourceCommit)).getD ""
    let digest := (record?.map (·.executableSha256)).getD ""
    let repoText := if repo.isEmpty then "an unrecorded repository" else repo
    ("bp_trust_axiom_warn",
      {{ "built from " {{.text true repoText}} " at " <code>{{.text true commit}}</code>
         " · binary " <code>{{.text true digest}}</code>
         " — not a checker this site knows by that name" }})
  | "ci-built" =>
    -- The legacy pair pins a revision. Whether that revision ran is the run cell's
    -- business, and this cell must not answer it for a record that stayed silent.
    if cmp.recordedReplay? label == some true then
      ("", {{ "built by the run's CI from " <code>{{.text true ref}}</code>
              " — the record carries no digest of the binary that ran" }})
    else
      ("", {{ "revision " <code>{{.text true ref}}</code>
              " recorded — a pin, not a check" }})
  | _ =>
    let refNote : Output.Html :=
      if ref.isEmpty then .empty
      else {{ " (revision " <code>{{.text true ref}}</code> " recorded separately, not bound to it)" }}
    ("bp_trust_axiom_warn",
      .seq #[{{ "not authenticated" }}, refNote, argvNote])

/-- A compact per-checker table, rendered whenever this verdict mentions a checker at all.

There is no one-row shortcut. A single checker is the ordinary deployment shape, not a
degenerate case, and every state this table exists to show is invisible without it: that
the configured checker has no run record, that the run recorded a decline, that a checker
the configuration has since dropped nonetheless ran, and — behind an authenticated
success — which executable the "Checked with" row is naming. A one-row table is cheap;
the states it carries are not recoverable from anywhere else on the page.

Each row states what the *run record* says, which for a checker the configuration merely
enables is nothing, and for a bare label is nothing about what ran. The configuration
column is the other half: it is where a checker enabled after the fact, or dropped since,
becomes visible per checker rather than only for nanoda. -/
private def kernelTableSection? (cmp : TrustComparator) : Option Output.Html :=
  let kernels := cmp.mentionedKernels
  if kernels.isEmpty then none
  else
    let rows : Array Output.Html := kernels.map fun k =>
      let named := cmp.kernelIdentityTier k == "named" || cmp.kernelIdentityTier k == "ci-built"
      let checkerCell : Output.Html :=
        if named then {{ <code>{{.text true k}}</code> }}
        else {{ "external checker labeled " <code>{{.text true k}}</code> }}
      let (replayText, replayClass) :=
        match cmp.recordedReplay? k with
        | some true => ("replayed", if named then "bp_trust_axiom_ok" else "bp_trust_axiom_warn")
        | some false => ("not replayed", "bp_trust_axiom_warn")
        | none => ("not recorded", "")
      let verdict := ((cmp.identityFor? k).map (·.verdict)).getD ""
      let replayHtml : Output.Html :=
        if verdict.isEmpty then {{ {{.text true replayText}} }}
        else {{ {{.text true replayText}} " — " {{.text true verdict}} }}
      let (identityClass, identityHtml) := kernelIdentityCell cmp k
      -- Configuration vs run, per checker: the generic drift the nanoda-only prose used
      -- to be the sole reporter of.
      let configured := cmp.configuredKernels.contains k
      let configText := if configured then "enabled" else "not enabled"
      let (configClass, configHtml) : String × Output.Html :=
        match cmp.kernelConfigDrift? k with
        | some _ =>
          ("bp_trust_axiom_warn",
            {{ {{.text true configText}} " — changed since this verdict" }})
        | none => ("", {{ {{.text true configText}} }})
      {{
        <tr>
          <td>{{checkerCell}}</td>
          <td class={{replayClass}}>{{replayHtml}}</td>
          <td class={{identityClass}}>{{identityHtml}}</td>
          <td class={{configClass}}>{{configHtml}}</td>
        </tr>
      }}
    some <| trustSection "External checkers"
      (.seq #[
        {{
          <div class="bp_trust_table_wrap">
            <table class="bp_trust_kernel_table">
              <thead><tr><th>"Checker"</th><th>"In the linked run"</th><th>"Identity"</th>
                <th>"In the configuration"</th></tr></thead>
              <tbody>{{.seq rows}}</tbody>
            </table>
          </div>
        }},
        {{
          <p class="bp_trust_note">
            "The comparator names an external checker by a key its configuration chooses, "
            "runs the command that key points at, and reads exit status zero as acceptance. "
            "A label is therefore display text: only a run record that binds a source "
            "revision to the digest of the executable it invoked says which program ran — "
            "and it says so as the producing CI's own assertion, which this site displays "
            "and does not verify. A checker the configuration enables but the record does "
            "not mention describes the next run, and a revision typed beside a label pins "
            "nothing. Where the two columns disagree, the configuration has changed since "
            "this verdict: the run record is what happened, the configuration is what would "
            "happen now."
          </p> }}])

/-- The "Reproduce it yourself" section: up to three tiers, each dropped when its data is
absent. Tier 1 opens the challenge in the Lean playground (needs `playgroundUrl`); tier 2
links the CI verification record (needs a CI url, and never for a locally-run verdict, which
that url did not produce); tier 3 is always present — the local shell
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
    -- The same reason the verdict header withholds it: a locally-run verdict has no run
    -- record, and the site-wide CI URL did not produce this one. Calling it "the exact run
    -- that produced this verdict" here would contradict, elsewhere on the same page, the
    -- sentence saying no run record links it.
    match (if cmp.isLocalVerdict then none else ciUrl?) with
    | some u =>
      -- What the *linked run* did, from its own record. The current configuration's
      -- `enable_nanoda` describes the next run and says nothing about this one.
      let replayNote :=
        if cmp.replayedWithNanoda then
          " — the exact run that produced this verdict, Lean-kernel replay included; its own \
            record additionally names a nanoda replay."
        else
          " — the exact run that produced this verdict, Lean-kernel replay included."
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
  -- Pinning the verifiers and leaving the subject on a moving branch reproduces the tools
  -- but not the bytes they checked. Say which of the two the commands above are.
  let subjectPinNote : Output.Html :=
    if cmp.repository.isEmpty && cmp.repoUrl.isEmpty then .empty
    else if !cmp.commit.isEmpty then
      {{
        <p class="bp_trust_note">
          "The project is checked out at " <code>{{.text true cmp.commit}}</code>
          " — the revision the recorded run verified — so the pinned verifiers above see the "
          "same Challenge, Solution and configuration bytes that run did."
        </p> }}
    else
      {{
        <p class="bp_trust_note">
          "The recorded run's subject revision is not recorded here, so these commands run "
          "against the repository's current default branch: a rerun against today's tree, not "
          "an exact reproduction of the run above. Compare the digests on this page with the "
          "files you check out before reading the result as the same check."
        </p> }}
  -- The comparator reads the project's oleans, and oleans carry a compiler stamp: a tool
  -- built on its own toolchain is a different program from the one that produced this
  -- verdict. Say which of the two the commands above build.
  let toolchainNote : Output.Html :=
    if !cmp.toolToolchain.isEmpty then
      {{
        <p class="bp_trust_note">
          "The run behind this verdict rebuilt the comparator on this project's toolchain — "
          <code>{{.text true cmp.toolToolchain}}</code>
          " — because the tool reads oleans that carry a compiler stamp, and the replay then "
          "runs on the kernel of the release this project pins. The commands above write that "
          "toolchain into the tool checkout before building it, as the run did."
        </p> }}
    else if cmp.toolRef.isEmpty && cmp.toolSha.isEmpty then .empty
    else
      {{
        <p class="bp_trust_note">
          "This verdict's record does not say which Lean toolchain the comparator itself was "
          "built with, so the commands above build the tool on its own — which need not be "
          "the toolchain the recorded run used. Since the tool reads oleans that carry a "
          "compiler stamp, treat the local run as a check of your own build rather than an "
          "exact replay of the one above."
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
    else if !(cmp.recordedKernelRef "nanoda").isEmpty then .empty
    else {{
      <p class="bp_trust_note">
        "The status artifact records no nanoda revision, so the clone above is "
        <em>"unpinned"</em>
        " and will build whatever is on nanoda's default branch — not necessarily the \
         revision CI used. Check the CI run's log for the exact revision."
      </p> }}
  -- Sandbox coverage is claimed only for the step the run record covers. Elaborating
  -- Lean is arbitrary code execution, so *when* the solution was first elaborated is the
  -- security-relevant question, and a status artifact recording a landrun revision does
  -- not answer it: a pipeline that prebuilds the solution to warm its cache elaborates it
  -- before the confined replay begins. Until the run record distinguishes the two, say
  -- exactly that rather than implying end-to-end confinement.
  let landrunNote : Output.Html :=
    if cmp.landrunRef.isEmpty then
      {{
        <p class="bp_trust_note">
          "This verdict's record names no "
          {{trustOutLink "https://landlock.io/" "Landlock"}}
          " sandbox, so nothing here says the solution was confined when CI elaborated or "
          "replayed it. The local commands above install no sandbox either, and on macOS or "
          "in a plain development shell there is no Landlock at all."
        </p> }}
    else
      {{
        <p class="bp_trust_note">
          "CI ran the comparator replay under "
          {{trustOutLink "https://landlock.io/" "Landlock"}}
          " (landrun " <code>{{.text true cmp.landrunRef}}</code>
          "). That confinement covers the replay step, and elaborating Lean is arbitrary "
          "code execution: if the project's CI builds the solution before invoking the "
          "comparator — a common arrangement, since it lets the sandboxed build reuse the "
          "cache — the solution's first elaboration happened outside the sandbox. The run "
          "record does not distinguish the two orders, so read the sandbox as covering the "
          "replay only. To match it locally on Linux, install landrun at that revision — "
          <code>{{.text true (landrunInstallCommand cmp.landrunRef)}}</code>
          " — and re-run under it; without that step, and always on macOS, the local run is "
          "a kernel check with no sandbox at all."
        </p> }}
  let shell : Output.Html :=
    {{ <pre class="bp_trust_code bp_trust_code_shell">{{.text true (String.intercalate "\n" (reproCommands cmp))}}</pre> }}
  let tier3 : Output.Html :=
    {{
      <li>
        "Run the check locally from a clean working directory:"
        {{shell}}
        {{.seq #[subjectPinNote, toolRefNote, toolchainNote, configNote, nanodaPinNote, landrunNote]}}
      </li> }}
  let items := ([tier1, tier2].filterMap id) ++ [tier3]
  trustSection "Reproduce it yourself"
    {{ <ol class="bp_trust_repro">{{.seq items.toArray}}</ol> }}

/-- Render a list of artifact names as prose ("the claim, the solution and the
configuration"). Empty ⇒ `""`. -/
private def andList : List String → String
  | [] => ""
  | [a] => a
  | [a, b] => s!"{a} and {b}"
  | a :: rest => s!"{a}, {andList rest}"

/--
What ties the source shown on this page to the verdict above it: recorded digests, or
nothing but a filename.

The distinction is the whole point. A digest recorded by the verifying run and re-checked
here against the displayed bytes rules out substitution; a matching name and path shape do
not, because names are identifiers rather than content. The page states which of the two
it has, per artifact, and never describes the second as if it were the first.
-/
private def contentBindingNote (cmp : TrustComparator) : Output.Html :=
  let bound := cmp.contentBound
  let unbound := cmp.contentUnbound
  if bound.isEmpty && unbound.isEmpty then .empty
  else
    let boundSentence : Output.Html :=
      if bound.isEmpty then .empty
      else
        {{ {{.text true
              s!"This build hashed the bytes it displays for {andList bound} and required \
                 them to equal the SHA-256 digests the verifying run recorded. A \
                 disagreement fails the build, so what you are reading is byte-for-byte \
                 what was checked."}} }}
    let unboundSentence : Output.Html :=
      if unbound.isEmpty then .empty
      else
        let pronoun := if unbound.length == 1 then "it is" else "they are"
        {{ {{.text true
              s!" This verdict's record carries no digest for {andList unbound}, so {pronoun} \
                 tied to it by file name and path shape only — identifiers, not contents. \
                 A same-named file stating something else would be displayed here without \
                 tripping any check. Follow the repository links above to read the source at \
                 the pinned commit."}} }}
    {{ <p class="bp_trust_note">{{.seq #[boundSentence, unboundSentence]}}</p> }}

/--
Replay claims the record *can* name, attributed to the record that names them (CX-064).

The strongest thing a status artifact can say about a second checker is that it was built
from some revision and that the binary invoked had some digest. Both are the producing CI's
own assertions: nothing on this site fetched that revision, built it, or hashed the
executable, and no oracle available here could. So the sentence names the record as its
source and says what was not done, rather than claiming that a second kernel independently
checked this proof.

A `ci-built` record does not even carry the digest — it is a revision the run's CI says it
built the checker from — and is worded accordingly.
-/
private def recordedKernelNote (cmp : TrustComparator) : Output.Html :=
  let assured := cmp.assuredKernels
  if assured.isEmpty then .empty
  else
    let phrase := fun (k : String) =>
      match cmp.identityFor? k with
      | some rec =>
        if cmp.kernelIdentityTier k == "named" then
          s!"{k}, built from {rec.sourceCommit}, binary {rec.executableSha256}"
        else s!"{k}, built by the run's CI from {cmp.recordedKernelRef k}"
      | none => s!"{k}, built by the run's CI from {cmp.recordedKernelRef k}"
    let subject := if assured.size == 1 then "a replay by" else "replays by"
    {{ <p class="bp_trust_note">
         {{.text true s!"The linked run's record additionally names {subject} \
            {andList (assured.map phrase).toList}, and each of those identities agrees with \
            one this site's author pinned from the verifying workflow. That agreement is \
            what \"authenticated\" means here, and it is all it means: nothing on this page \
            re-ran the checker, fetched that revision, or hashed the binary against it. \
            Read it as two sources agreeing about what was invoked, not as an attestation \
            that it ran."}}
       </p> }}

/--
Replay claims this page must present as unnamed: the run says something ran and accepted,
and nothing this site can check says what program that was.

Stated rather than dropped, because the comparator's own output will have called it by
whatever name the configuration chose.

One sentence per *reason*, because since CX-064 there are three of them and they are not
the same statement. Describing a well-formed-but-unpinned record as one that "does not
bind the label to a source revision and executable digest" would be false of the record on
the page — the digest is right there — so each group says what is actually the matter with
it. `unnamedReplayReason` computes the split beside `kernelIdentityTier`, so the copy
cannot drift from the tier.
-/
private def unnamedCheckerNote (cmp : TrustComparator) : Output.Html :=
  let claims := cmp.unnamedReplayClaims
  if claims.isEmpty then .empty
  else
    let subject := fun (ks : Array String) =>
      if ks.size == 1 then "a checker labeled" else "checkers labeled"
    -- Shared by all three: the label is display text the configuration chose.
    let lead := " accepted the solution. The comparator takes that label from its \
       configuration and runs whatever command the label points at, treating exit status \
       zero as acceptance, and "
    let note := fun (ks : Array String) (tail : String) =>
      if ks.isEmpty then Output.Html.empty
      else
        {{ <p class="bp_trust_note">
             "The run also reports that " {{.text true (subject ks)}} " "
             {{inlineCodeList ks.toList}}
             {{.text true (lead ++ tail ++ " Nothing above counts it as a second kernel.")}}
           </p> }}
    .seq #[
      note (cmp.unnamedReplayClaimsFor "unbound")
        "this record does not bind the label to a source revision and executable digest — \
         so what ran is not established here.",
      note (cmp.unnamedReplayClaimsFor "unpinned")
        "the record names a source revision and executable digest, but this site holds no \
         pinned identity for that checker, so they are the producer's own statement and \
         what ran is not established here.",
      note (cmp.unnamedReplayClaimsFor "pin-mismatch")
        "the record names a source revision and executable digest that disagree with the \
         identity this site's author pinned, so what ran is not established here — the \
         build reports which field disagrees."]

/--
What the linked run recorded about the independent kernel replay, and whether the
comparator configuration has changed since.

Never derived from `enable_nanoda`: that field says what the *next* run will do.
-/
private def nanodaEvidenceNote (cmp : TrustComparator) : Output.Html :=
  let unrecorded : Output.Html :=
    if cmp.nanodaReplayRecorded then .empty
    else if cmp.enableNanoda then
      {{ <p class="bp_trust_note">
           "The comparator configuration in this repository enables an independent nanoda "
           "kernel replay, but this verdict's record predates the field that says whether the "
           "run performed one. Nothing here claims a second kernel checked this verdict; the "
           "next run will record it."
         </p> }}
    else .empty
  let drift : Output.Html :=
    match cmp.nanodaConfigDrift? with
    | some true =>
      {{ <p class="bp_trust_note">
           "The comparator configuration has changed since this verdict: it now enables an "
           "independent nanoda kernel replay, and the linked run recorded that it performed "
           "none. The reproduce commands below describe the current configuration, not the "
           "run above."
         </p> }}
    | some false =>
      {{ <p class="bp_trust_note">
           "The comparator configuration has changed since this verdict: the linked run "
           "recorded an independent nanoda kernel replay, and the configuration no longer "
           "enables one. The reproduce commands below describe the current configuration, "
           "not the run above."
         </p> }}
    | none => .empty
  .seq #[unrecorded, drift]

/-! ## Registry records

A registration is a record that a repository at a revision was submitted somewhere and
accepted. What this page adds to it is the one thing a reader cannot check by following the
link: whether the record is about the claim on this page. That question has exactly one
answer this fork will give — the record's immutable challenge digest is the digest of the
displayed statement, the verifying run recorded that digest too, and the record itself came
from a configured bundle this build can re-read — and every weaker relation is rendered as
what it is, in prose, under a match basis printed as data.
-/

/-- What one match establishes, in the register the rest of the page uses.

The basis is not the whole of it: a record that agreed on everything a binding needs, but
which this build read over the network, is not bound to the claim (`isClaimLevel`,
CX-076). It gets its own sentence rather than one of the weaker bases' — saying "the
repository name is all we had to compare" about a record whose digest agreed exactly would
be false in the other direction. -/
private def registryMatchSentence (e : RegistryEntry) : String :=
  if Informal.Palomar.claimLevelBases.contains e.matchBasis && !e.isClaimLevel then
    s!"Palomar entry {e.label} records a challenge whose digest is the digest of the \
       statement above, under a verdict that recorded that digest — but its bytes are not \
       among the inputs this build recorded, so nothing can re-read them to check that this \
       is still what the registry holds. It is not bound to the claim shown here: read it \
       as provenance about the project."
  else
  match e.matchBasis with
  | "repo+digest" =>
    s!"Palomar entry {e.label} records this claim: the digest of the statement above is the \
       challenge digest the registry verified, the verifying run recorded that digest too, \
       and the repository the record names is this project's."
  | "digest" =>
    s!"Palomar entry {e.label} records this claim: the digest of the statement above is the \
       challenge digest the registry verified, and the verifying run recorded that digest \
       too. This site could not compare repositories with the record, so the digest is the \
       whole of the binding."
  | "digest-not-verified" =>
    s!"Palomar entry {e.label} records a challenge whose digest is the digest of the \
       statement above, and this verdict recorded that digest too — but the verdict is not a \
       comparator success, so there is no certified claim for the registration to be about. \
       Read it as provenance about the project."
  | "digest-identity-mismatch" =>
    let what := if e.matchNote.isEmpty then "" else s!" ({e.matchNote})"
    s!"Palomar entry {e.label} records a challenge whose digest is the digest of the \
       statement above, but its own source identity disagrees with this verdict's{what}. Two \
       records of the same bytes under different provenance are not one claim, so this is \
       not bound to the claim shown here: read it as provenance about the project."
  | "digest-unbound" =>
    s!"Palomar entry {e.label} records a challenge whose digest is the digest of the bytes \
       shown on this page — but this verdict records no digest of its own, so the \
       registration is not bound to the claim shown here. Read it as provenance about the \
       project."
  | _ =>
    s!"Palomar entry {e.label} registers this repository. It is not bound to the claim shown \
       here: the repository name is all this site and the record had in common to compare."

/-- One registry record, as a card: what matched, on what, and where the record came from. -/
def registryCardHtml (e : RegistryEntry) : Output.Html :=
  let row (label : String) (value : Output.Html) : Output.Html :=
    {{ <div><dt>{{.text true label}}</dt><dd>{{value}}</dd></div> }}
  let titleRow : Output.Html :=
    if e.title.isEmpty then .empty
    else row "Title" {{ {{.text true e.title}} }}
  let registeredRow : Output.Html :=
    if e.recordedAt.isEmpty then .empty
    else row "Registered" {{ <time datetime={{e.recordedAt}}>{{.text true (isoDateOnly e.recordedAt)}}</time> }}
  let sourceText : Output.Html :=
    {{ <code>{{.text true e.sourceRepo}}</code> " at " <code>{{.text true e.sourceCommit}}</code> }}
  let sourceRow : Output.Html :=
    if e.sourceRepo.isEmpty then .empty
    else if e.treeUrl.isEmpty then row "Registered source" sourceText
    else row "Registered source" {{ <a href={{e.treeUrl}}>{{sourceText}}</a> }}
  let digestRow : Output.Html :=
    if e.challengeSha256.isEmpty then .empty
    else row "Challenge digest" {{ <code>{{.text true e.challengeSha256}}</code> }}
  let basisRow := row "Match basis" {{ <code>{{.text true e.matchBasis}}</code> }}
  let verifiedRow : Output.Html :=
    if e.workflowUrl.isEmpty then .empty
    else row "Registry verification" (trustOutLink e.workflowUrl
      (if e.verifiedAt.isEmpty then "Registry workflow run"
       else s!"Registry workflow run, {isoDateOnly e.verifiedAt}"))
  let provenance : Output.Html :=
    if e.provenance.isEmpty then .empty
    else {{ <p class="bp_trust_note">{{.text true s!"Matched against {e.provenance}."}}</p> }}
  -- Where a record came from is ordinarily the bundle's business, not one record's — except
  -- for a probed one, whose origin is the reason it can never be claim-level. A bundle
  -- unioned from a cache and a probe has records of both kinds, and this is the only place
  -- a reader can tell which is which (CX-076).
  let networkOrigin : Output.Html :=
    if !Informal.Palomar.isProbeOrigin e.recordOrigin then .empty
    else
      {{ <p class="bp_trust_note">{{.text true
           s!"These bytes were fetched from {e.recordOrigin} while this build ran. A record \
              read over the network is not a file this build records or can re-read, so it \
              is never bound to a claim on this page — only to the project."}}</p> }}
  {{
    <div class="bp_trust_registry" "data-bp-registry-basis"={{e.matchBasis}}>
      <p class="bp_trust_prose">{{.text true (registryMatchSentence e)}}</p>
      <dl class="bp_trust_verdict_meta">
        {{.seq #[titleRow, registeredRow, sourceRow, digestRow, basisRow, verifiedRow]}}
      </dl>
      <p class="bp_trust_note">{{.text true Informal.Palomar.honestyNote}}</p>
      {{networkOrigin}}
      {{provenance}}
    </div>
  }}

/-- The author-supplied permalink, rendered as a link and labelled as unchecked.

Not a badge and not a card: nothing about this URL was verified, so it gets the plainest
markup on the page. -/
def registryLinkHtml (url : String) : Output.Html :=
  {{
    <p class="bp_trust_registry_link" "data-bp-registry-basis"="consumer-link">
      {{.text true (Informal.Palomar.consumerLinkNote ++ ": ")}}
      <a href={{url}} rel="nofollow">{{.text true url}}</a>
    </p>
  }}

/-- How many unread records are listed before the rest are counted instead. A registry
projection is bounded but a bundle need not be, and a page that turns into a list of skipped
files has stopped being a diagnostic. -/
private def maxUnreadListed : Nat := 8

/-- The records this build could not read, named.

Deliberately not a verdict of any kind, and deliberately not negative: an unread record is
not an absent one, this build compared nothing against these rows, and a projection that
does not mention a project is no evidence about whether the registry does. What the section
establishes is only that matching did *not* consider everything the bundle named — the one
thing a reader cannot otherwise tell from a page that shows a record, or from one that shows
none. -/
def registryBundleReportHtml (r : RegistryBundleReport) : Output.Html :=
  let listed := r.unresolved.take maxUnreadListed
  let remaining := r.unresolved.length - listed.length
  let row (u : UnresolvedRecord) : Output.Html :=
    let origin := if u.source.isEmpty then Output.Html.empty
      else {{ " (" {{.text true u.source}} ")" }}
    {{ <li><code>{{.text true u.label}}</code>{{origin}} " — " {{.text true u.reason}}</li> }}
  let more : Output.Html :=
    if remaining == 0 then .empty
    else
      {{ <li>{{.text true s!"… and {remaining} further \
        {if remaining == 1 then "row" else "rows"} this build could not read."}}</li> }}
  let n := r.unresolved.length
  {{
    <div class="bp_trust_registry_bundle" "data-bp-registry-unread"={{toString n}}>
      <p class="bp_trust_prose">{{.text true
        s!"This build matched against {r.provenance}."}}</p>
      <p class="bp_trust_prose">{{.text true
        s!"{if n == 1 then "The row" else "The rows"} below named a record this build could \
           not read, so {if n == 1 then "it was" else "they were"} never compared against \
           anything on this page. That says nothing about whether \
           {if n == 1 then "it concerns" else "they concern"} this project: an unread record \
           is not an absent one, and a bounded projection that does not mention a project is \
           not a registry that does not."}}</p>
      <ul class="bp_trust_registry_unread">{{.seq ((listed.map row).toArray.push more)}}</ul>
    </div>
  }}

/-- The registry section, or nothing at all.

Nothing at all is the ordinary case: a configured bundle that matched nothing renders no
section, because a bounded projection of a registry that does not mention this project is
not evidence that the registry does not.

The bundle report is separate from all of that, and appears on its own whenever there is one
— including under a matched record, and including where nothing matched and there is no card
to hang it on. -/
def registrySection? (entry? : Option RegistryEntry) (link : String := "")
    (bundle? : Option RegistryBundleReport := Option.none) : Output.Html :=
  let bundleSection : Output.Html :=
    match bundle? with
    | Option.none => .empty
    | Option.some r => trustSection "Registry bundle" (registryBundleReportHtml r)
  let matched : Output.Html :=
    match entry?, link.isEmpty with
    | Option.none, true => .empty
    | Option.none, false => trustSection "Registry link" (registryLinkHtml link)
    | Option.some e, true => trustSection "Registry record" (registryCardHtml e)
    | Option.some e, false =>
      trustSection "Registry record" (.seq #[registryCardHtml e, registryLinkHtml link])
  .seq #[matched, bundleSection]

/-- Body of the claim-first `comparator/` page. A verdict header, the challenge statement
("the claim"), a plain account of what the comparator does and does not check, the human step
the reader must still perform, a three-tier "reproduce it yourself" section, then the Solution
source and the comparator configuration. Each section probes-and-degrades to nothing when its
data is absent.

Public so tests can render the page's markup from a `TrustComparator` directly: the
run-evidence and content-binding rules this body enforces are the point of the page,
and asserting them through a generated site would test the `ExtraStep` plumbing
instead. -/
def comparatorPanelInner (cmp : TrustComparator) (ciUrl? : Option String)
    (theoremLikeTotal : Option Nat) (trustModelHref? : Option String)
    (closureCtx : StatementClosurePanel.Context := {}) : Output.Html :=
  -- 1. Verdict header (pill + date + CI link + scope + certified theorems + axioms + tool
  --    refs), plus the per-kernel table when more than one kernel is in play.
  let verdict := comparatorVerdictHeader cmp ciUrl? theoremLikeTotal
  let kernelSection := (kernelTableSection? cmp).getD .empty
  -- The claim section is the one place the challenge chain's own declarations are printed,
  -- so it carries the id the statement closure's reading list points its challenge-origin
  -- rows at. Anchored only when there is a source to anchor to.
  let claimAnchor :=
    if cmp.challengeSource.isEmpty || !StatementClosurePanel.needsClaimAnchor cmp then ""
    else if closureCtx.idSuffix.isEmpty then "bp-trust-claim"
    else s!"bp-trust-claim-{closureCtx.idSuffix}"
  let closureCtx := { closureCtx with claimAnchor }
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
          contentBindingNote cmp,
          liveNote])
        (id? := if claimAnchor.isEmpty then Option.none else Option.some claimAnchor)
  -- 3. What this page certifies (static prose).
  --    The second-kernel clause is *run evidence* (`nanoda_replay`), not configuration:
  --    an author who switches `enable_nanoda` on must not thereby make a past verdict
  --    claim a replay it never had.
  -- One clause, whatever the record says about second kernels. The tier a record earns is
  -- a reading of that record's own fields, so it licenses attribution and not assertion:
  -- what the second kernel did belongs in the note below, in the producing CI's voice
  -- (CX-064).
  let kernelClause : Output.Html :=
    {{ "Lean kernel to confirm that the solution proves exactly the challenge statements, using "
       "only the permitted axioms listed above." }}
  let certifiesSection : Output.Html :=
    trustSection "What this page certifies"
      (.seq #[
        {{
          <p class="bp_trust_prose">
            "The statement comparator is an independent checking tool maintained by the Lean "
            "project. It elaborates the challenge and the solution in separate environments, so the "
            "solution cannot weaken or restate the claims it is measured against, and then asks the "
            {{kernelClause}}
          </p> }},
        recordedKernelNote cmp,
        unnamedCheckerNote cmp,
        nanodaEvidenceNote cmp])
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
  -- The statement closure sits between the claim and the prose about it: a reader who has
  -- just read the statement is the reader who wants to know what reading it committed
  -- them to. Renders nothing at all unless the closure surface is configured.
  let closureSection := StatementClosurePanel.render cmp closureCtx
  -- The caveats follow the closure for the same reason and in the same voice: having been
  -- told what the statement means, a reader is told which of those meanings have a
  -- convention that can be misread. `.empty` when nothing was scanned.
  let caveatsSection : Output.Html :=
    match cmp.caveats? with
    | Option.none => .empty
    | Option.some r =>
      if r.status.isEmpty then .empty
      else trustSection Informal.CaveatsRender.sectionTitle
        {{ <div class="bp_caveats">{{Informal.CaveatsRender.body r}}</div> }}
  -- The registration, when one is bound to *this* claim. Last: it is provenance about the
  -- record, and everything above it is the check itself.
  let registryPanel := registrySection? cmp.registryEntry?
  .seq #[verdict, kernelSection, claimSection, closureSection, caveatsSection, certifiesSection,
    checkSection, reproSection, solutionSection, configSection, registryPanel]

/--
The consumer's characterization sidecar, as one page-level section.

Page-level rather than per-panel: a sidecar is a set of statements about the project's
declarations, not about one verdict, and repeating it under every topic would say the same
thing more times without saying it about anything more specific. `.empty` when none is
configured. -/
def characterizationsSection (cs? : Option Informal.JunkValues.Characterizations)
    (closureCtx : StatementClosurePanel.Context) : Output.Html :=
  match cs? with
  | Option.none => .empty
  | Option.some cs =>
    if cs.entries.isEmpty then .empty
    else
      trustSection "Consumer-declared characterizations"
        {{ <div class="bp_caveats">
             {{Informal.CaveatsRender.characterizationsBody cs closureCtx.siteHref}}
           </div> }}

/-- The single-comparator page: the panel body inside the page shell. -/
def comparatorBody (cmp : TrustComparator) (ciUrl? : Option String)
    (theoremLikeTotal : Option Nat) (trustModelHref? : Option String)
    (closureCtx : StatementClosurePanel.Context := {})
    (characterizations? : Option Informal.JunkValues.Characterizations := Option.none)
    (projectRegistry? : Option RegistryEntry := Option.none) (registryLink : String := "")
    (registryBundle? : Option RegistryBundleReport := Option.none) :
    Output.Html :=
  trustPageShell "Statement comparator" ""
    (.seq #[
      comparatorPanelInner cmp ciUrl? theoremLikeTotal trustModelHref? closureCtx,
      characterizationsSection characterizations? closureCtx,
      registrySection? projectRegistry? registryLink registryBundle?])

/-! ## Multi-config trust surface -/

/-- One config-less axiom-audit panel: a named declaration set, each declaration
with its kernel-audited axiom closure and a per-set verdict. Certifies only "these
declarations use exactly these axioms" — no Challenge/Solution pair. -/
def axiomAuditPanel (topic : AxiomAuditTopic) : Output.Html :=
  let anySorry := topic.decls.any (·.sorried)
  let anyNonstandard := topic.decls.any (fun d => !d.nonstandard.isEmpty)
  let n := topic.decls.length
  let declNoun := if n == 1 then "declaration" else "declarations"
  let verdict :=
    if anySorry then
      trustBadgeHtml s!"{(topic.decls.filter (·.sorried)).length} incomplete" "error"
    else if anyNonstandard then
      trustBadgeHtml s!"{(topic.decls.filter (fun d => !d.nonstandard.isEmpty)).length} nonstandard" "warn"
    else
      trustBadgeHtml s!"{n} clean" "success"
  let intro :=
    if anySorry then
      s!"`Lean.collectAxioms` over {n} {declNoun} found `sorryAx` in at least one transitive \
         closure: those proofs are incomplete."
    else if anyNonstandard then
      s!"`Lean.collectAxioms` over {n} {declNoun}: no `sorryAx`, but at least one depends on an \
         axiom beyond propext, Classical.choice, and Quot.sound."
    else
      s!"`Lean.collectAxioms` over {n} {declNoun}: no `sorryAx` anywhere in any transitive \
         closure, and no axiom beyond propext, Classical.choice, and Quot.sound."
  let rows : Array Output.Html := (topic.decls.map fun d =>
    let axiomList := if d.axioms.isEmpty then "(none)" else ", ".intercalate d.axioms
    let cellClass :=
      if d.sorried then "bp_trust_axiom_bad"
      else if !d.nonstandard.isEmpty then "bp_trust_axiom_warn"
      else "bp_trust_axiom_ok"
    {{
      <tr>
        <td><code>{{.text true d.name}}</code></td>
        <td class={{cellClass}}>{{.text true axiomList}}</td>
      </tr>
    }}).toArray
  trustSection topic.name
    (.seq #[
      {{ <p class="bp_trust_verdict_row">{{verdict}}</p> }},
      {{ <p class="bp_trust_prose">{{Informal.NodeCard.withCodeSpans intro}}</p> }},
      {{
        <div class="bp_trust_table_wrap">
          <table class="bp_trust_axiom_table">
            <thead><tr><th>"Declaration"</th><th>"Axiom closure"</th></tr></thead>
            <tbody>{{.seq rows}}</tbody>
          </table>
        </div>
      }}])

/-- The multi-config comparator page: an aggregate verdict header, then one
first-class certified panel per comparator topic (reusing the single-panel body)
plus one panel per config-less axiom-audit topic. `comparatorBody`'s honesty
rules apply per panel; the header aggregates across them.

**The headline counts `verified` topics only** — the same predicate as the
dashboard's aggregate badge. It used to sum the theorem names of every topic, so a
project whose configs had all merely been *configured*, or whose verdicts had been
transcribed from someone else's records, was told it presented that many
"independently comparator-certified" theorems. The other topics are still counted,
in a clause that says what they actually are. -/
def comparatorsPageBody (comparators : List ComparatorTopic)
    (axiomTopics : List AxiomAuditTopic) (ciUrl? : Option String)
    (theoremLikeTotal : Option Nat) (trustModelHref? : Option String)
    (closureCtx : StatementClosurePanel.Context := {})
    (characterizations? : Option Informal.JunkValues.Characterizations := Option.none)
    (projectRegistry? : Option RegistryEntry := Option.none) (registryLink : String := "")
    (registryBundle? : Option RegistryBundleReport := Option.none) :
    Output.Html :=
  let m := comparators.length
  let cfgNoun := if m == 1 then "comparator config" else "comparator configs"
  let verified := comparators.filter (·.comparator.status == "verified")
  let others := comparators.filter (·.comparator.status != "verified")
  let v := verified.length
  let k := (verified.map (·.comparator.theoremNames.length)).foldl (· + ·) 0
  let j := (others.map (·.comparator.theoremNames.length)).foldl (· + ·) 0
  let thmNoun := if k == 1 then "theorem" else "theorems"
  let jNoun := if j == 1 then "theorem" else "theorems"
  let jVerb := if j == 1 then "is" else "are"
  -- What the uncertified topics are, in their own words rather than in the
  -- certified sentence's.  Shared with the dashboard strip's aggregate scope line
  -- (`uncertifiedStatusPhrase`) so the two surfaces cannot describe one set of topics
  -- two different ways.
  let statusPhrase := uncertifiedStatusPhrase others
  let acrossPhrase := if v == m then s!"across {m} {cfgNoun}" else s!"across {v} of {m} {cfgNoun}"
  let scopeText :=
    if k == 0 then
      let lead :=
        match theoremLikeTotal with
        | some n => s!"This site presents no independently comparator-certified theorems of its \
            {n} theorem-like statements."
        | none => "This site presents no independently comparator-certified theorems."
      if j == 0 then lead
      else s!"{lead} Its {m} {cfgNoun} name {j} {jNoun} that {jVerb} {statusPhrase}."
    else
      let lead :=
        match theoremLikeTotal with
        | some n => s!"This site presents {k} independently comparator-certified {thmNoun} of {n} \
            theorem-like statements, {acrossPhrase}."
        | none => s!"This site presents {k} independently comparator-certified {thmNoun}, \
            {acrossPhrase}."
      if others.isEmpty then lead
      else if j == 0 then
        let oNoun := if others.length == 1 then "config" else "configs"
        s!"{lead} Its other {others.length} {oNoun} name no theorems."
      else
        s!"{lead} A further {j} {jNoun} {jVerb} {statusPhrase}, which this site does not present \
           as certified."
  let axiomNote :=
    if axiomTopics.isEmpty then Output.Html.empty
    else
      let a := axiomTopics.length
      let setNoun := if a == 1 then "declaration set" else "declaration sets"
      let setVerb := if a == 1 then "carries" else "carry"
      {{ <p class="bp_trust_prose">{{.text true
        s!"Below the comparator panels, {a} additional {setNoun} {setVerb} a kernel axiom audit \
           ({(axiomTopics.map (·.decls.length)).foldl (· + ·) 0} declarations) with no \
           Challenge/Solution pair — each certifies only its declarations' axiom closure."}}
      </p> }}
  let header : Output.Html :=
    {{
      <section class="bp_trust_section bp_trust_multi_header">
        <p class="bp_trust_prose">{{.text true scopeText}}</p>
        {{axiomNote}}
      </section>
    }}
  -- Each panel's element ids are suffixed by its position, so a multi-topic page's
  -- reading lists anchor into their own claim rather than the first one on the page.
  let comparatorPanels : Array Output.Html := comparators.toArray.zipIdx.map fun (topic, i) =>
    let panelCtx := { closureCtx with idSuffix := toString (i + 1) }
    {{
      <section class="bp_trust_topic">
        <h2 class="bp_trust_topic_title">{{.text true topic.name}}</h2>
        {{comparatorPanelInner topic.comparator ciUrl? theoremLikeTotal trustModelHref? panelCtx}}
      </section>
    }}
  let axiomPanels : Array Output.Html := (axiomTopics.map axiomAuditPanel).toArray
  trustPageShell "Statement comparator" ""
    (.seq (#[header] ++ comparatorPanels ++ axiomPanels
      ++ #[characterizationsSection characterizations? closureCtx,
        registrySection? projectRegistry? registryLink registryBundle?]))

/-! ## Emission -/

/-- Decode the (possibly-empty) trust payload cached during traversal. -/
private def cachedTrust? (state : TraverseState) : Option TrustData :=
  (Informal.TraversalIndex.TrustData.raw? state).bind fun json =>
    (fromJson? (α := TrustData) json).toOption

/--
Where this site publishes each declaration it knows about, read from the traversal-cached
registry.

The registry is the only thing that knows which page a declaration has — wired
declarations keep their node page, unwired ones get a `decl/` page — so a name it does not
carry resolves to nothing and the reading list renders that row unlinked. Guessing a decl
slug from a name would produce a confident link to a page that was never emitted, which is
the one outcome worse than no link. Empty when the all-declarations registry is off. -/
private def registrySiteHrefs (state : TraverseState) : String → Option String :=
  let table : Std.HashMap String String :=
    match Informal.TraversalIndex.DeclRegistry.raw? state with
    | none => {}
    | some raw =>
      match (do
          let j ← Json.parse raw
          (FromJson.fromJson? j : Except String Informal.DeclRegistry.Registry)) with
      | .error _ => {}
      | .ok registry =>
        registry.decls.foldl (init := {}) fun m e =>
          match e.nodeHref? <|> e.declHref? with
          | some href => m.insert e.name href
          | none => m
  fun name => table[name]?

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
        -- "k of N": N counts every theorem-like node the site presents (theorems,
        -- lemmas, propositions, corollaries) — the population the certified set is
        -- a subset of.
        let theoremLikeTotal :=
          (Informal.TraversalIndex.Summary.cachedSummary? state).map fun s =>
            s.theorems + s.lemmas + s.propositions + s.corollaries
        let trustModelHref? := Informal.TraversalIndex.TrustModelPage.href? state
        -- The CI-run link for a topic prefers that topic's own status `run_url`,
        -- falling back to the shared `ciRunUrl` option.
        let ciFor (cmp : TrustComparator) : Option String :=
          if cmp.runUrl.isEmpty then trust.ciRunUrl else some cmp.runUrl
        let closureCtx : StatementClosurePanel.Context :=
          { siteHref := registrySiteHrefs state }
        let body? : Option Output.Html :=
          if !trust.comparators.isEmpty || !trust.axiomAuditTopics.isEmpty then
            -- Multi-config trust surface: one certified panel per topic + aggregate.
            -- The per-topic CI link falls back to the first topic's run_url.
            let ciUrl? :=
              (trust.comparators.head?.map (fun t => ciFor t.comparator)).getD trust.ciRunUrl
            some (comparatorsPageBody trust.comparators trust.axiomAuditTopics ciUrl?
              theoremLikeTotal trustModelHref? closureCtx trust.characterizations?
              trust.registryEntry? trust.registryLink trust.registryBundle?)
          else match trust.comparator with
            | Option.none => Option.none
            | Option.some cmp =>
              Option.some
                (comparatorBody cmp (ciFor cmp) theoremLikeTotal trustModelHref? closureCtx
                  trust.characterizations? trust.registryEntry? trust.registryLink
                  trust.registryBundle?)
        match body? with
        | Option.none => pure ()
        | Option.some body =>
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            Informal.NodeRoute.comparatorPath "Statement comparator" body

end Informal.Commands
