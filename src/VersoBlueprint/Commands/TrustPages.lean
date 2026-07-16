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
Statement-comparator page + `uses`-graph build gate.

Two generation-time `ExtraStep`s that read the trust-strip payload cached during
traversal (`TraversalIndex.TrustData`, saved by `Block.trustStrip`'s traverse):

- `emitBlueprintGraphGate` — the structural `uses`-graph build gate. Acyclicity is
  an unconditional hard fail; connectivity fails the build unless
  `verso.blueprint.trust.requireConnected` is false (a deliberately multi-topic
  blueprint). A built site has therefore passed these checks. Skipped for an empty
  graph and in single-page mode.
- `emitBlueprintComparatorPage` — when a statement comparator is configured, emits a
  single claim-first `comparator/` page: a verdict header (status, date, certified
  theorems, permitted axioms, CI link), the challenge statement ("the claim"), a plain
  account of what the comparator does and does not check, the one human step the reader
  must still perform, and a three-tier "reproduce it yourself" section (Lean playground,
  CI record, exact local commands), followed by the Solution source and the comparator
  configuration. Canonical comparator documentation is linked, not restated. Every
  section probes-and-degrades: absent data drops its section rather than failing. Emits
  nothing when no comparator is configured.
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
else escaped plain text. -/
private def trustCodeBlock (extraClass htmlMarkup fallback : String) : Output.Html :=
  if htmlMarkup.isEmpty then
    {{ <pre class={{s!"bp_trust_code {extraClass}"}}>{{.text true fallback}}</pre> }}
  else
    {{ <pre class={{s!"bp_trust_code {extraClass}"}}><code class="hl lean">{{.text false htmlMarkup}}</code></pre> }}

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
private def comparatorVerdictHeader (cmp : TrustComparator) (ciUrl? : Option String) : Output.Html :=
  let pill : Output.Html :=
    if cmp.status == "verified" then trustBadgeHtml "Verified" "success"
    else if cmp.status == "configured" then trustBadgeHtml "Configured — not yet run" "warn"
    else trustBadgeHtml cmp.status
  let date : Output.Html :=
    if cmp.verifiedAt.isEmpty then .empty
    else {{ <time class="bp_trust_verdict_date" datetime={{cmp.verifiedAt}}>{{.text true (isoDateOnly cmp.verifiedAt)}}</time> }}
  let ci : Output.Html :=
    match ciUrl? with
    | some u => trustOutLink u "CI verification record"
    | none => .empty
  let theoremRow : Output.Html :=
    if cmp.theoremNames.isEmpty then .empty
    else {{ <div><dt>"Certified theorem(s)"</dt><dd>{{inlineCodeList cmp.theoremNames}}</dd></div> }}
  let axiomRow : Output.Html :=
    if cmp.permittedAxioms.isEmpty then .empty
    else {{ <div><dt>"Permitted axioms"</dt><dd>{{inlineCodeList cmp.permittedAxioms}}</dd></div> }}
  let metaHtml : Output.Html :=
    if cmp.theoremNames.isEmpty && cmp.permittedAxioms.isEmpty then .empty
    else {{ <dl class="bp_trust_verdict_meta">{{.seq #[theoremRow, axiomRow]}}</dl> }}
  {{
    <section class="bp_trust_verdict">
      <div class="bp_trust_verdict_row">{{.seq #[pill, date, ci]}}</div>
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
  let landrunNote : Output.Html :=
    {{
      <p class="bp_trust_note">
        "On Linux the comparator runs the solution inside a Landlock sandbox; on macOS or in a "
        "plain development shell it runs without that sandbox (see the project README)."
      </p> }}
  let shell : Output.Html :=
    {{ <pre class="bp_trust_code bp_trust_code_shell">{{.text true (String.intercalate "\n" (reproCommands cmp))}}</pre> }}
  let tier3 : Output.Html :=
    {{
      <li>
        "Run the check locally from a clean working directory:"
        {{shell}}
        {{.seq #[toolRefNote, configNote, landrunNote]}}
      </li> }}
  let items := ([tier1, tier2].filterMap id) ++ [tier3]
  trustSection "Reproduce it yourself"
    {{ <ol class="bp_trust_repro">{{.seq items.toArray}}</ol> }}

/-- Body of the claim-first `comparator/` page. A verdict header, the challenge statement
("the claim"), a plain account of what the comparator does and does not check, the human step
the reader must still perform, a three-tier "reproduce it yourself" section, then the Solution
source and the comparator configuration. Each section probes-and-degrades to nothing when its
data is absent. -/
private def comparatorBody (cmp : TrustComparator) (ciUrl? : Option String) : Output.Html :=
  -- 1. Verdict header (pill + date + CI link + certified theorems + permitted axioms).
  let verdict := comparatorVerdictHeader cmp ciUrl?
  -- 2. "The claim": the challenge statement, verbatim, with GitHub + Lean-playground links.
  let claimSection : Output.Html :=
    if cmp.challengeSource.isEmpty then .empty
    else
      let ghLink : Option Output.Html :=
        if cmp.githubChallengeUrl.isEmpty then Option.none
        else Option.some (trustOutLink cmp.githubChallengeUrl "View on GitHub")
      let pgLink : Option Output.Html :=
        if cmp.playgroundUrl.isEmpty then Option.none
        else Option.some (trustOutLink cmp.playgroundUrl "Open in Lean playground (current Mathlib)")
      let linkItems := ([ghLink, pgLink].filterMap id)
      let linksRow : Output.Html :=
        match linkItems with
        | [] => .empty
        | first :: rest =>
          let joined := rest.foldl (init := first) fun acc x => .seq #[acc, {{ " · " }}, x]
          {{ <p class="bp_trust_links">{{joined}}</p> }}
      trustSection "The claim"
        (.seq #[linksRow, trustCodeBlock "bp_trust_code_lean" cmp.challengeHtml cmp.challengeSource])
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

/-! ## `uses`-graph build gate -/

open Informal.Graph in
/-- Friendly display text for a graph node label (used in gate failure messages):
enriched node title, else the short display label, else the de-escaped raw label. -/
private def graphNodeText (master : GraphData) (label : Lean.Name) : String :=
  match master.nodes.find? (·.label == label) with
  | some node =>
    let t := node.title.trim
    if !t.isEmpty then t
    else if !node.displayLabel.isEmpty then node.displayLabel
    else Informal.NodeRoute.stripNameEscapes label.toString
  | none => Informal.NodeRoute.stripNameEscapes label.toString

/-- Decode the (possibly-empty) trust payload cached during traversal. -/
private def cachedTrust? (state : TraverseState) : Option TrustData :=
  (Informal.TraversalIndex.TrustData.raw? state).bind fun json =>
    (fromJson? (α := TrustData) json).toOption

/--
`ExtraStep` build gate: a structural `uses`-graph violation FAILS the site build, so a
built site has passed. Acyclicity always hard-gates; connectivity gates unless
`verso.blueprint.trust.requireConnected` (default true, read from the cached trust
payload) is false. Skipped for an empty graph and in single-page mode.
-/
def emitBlueprintGraphGate : ExtraStep :=
  fun mode _cfg state _text => do
    match mode with
    | .single => pure ()
    | .multi =>
      let master := Informal.GraphApi.masterGraph state
      let checks := Informal.GraphChecks.run master
      let requireConnected := ((cachedTrust? state).map (·.requireConnected)).getD true
      unless checks.graphEmpty do
        unless checks.acyclic.ok do
          let cyc := String.intercalate " → " (checks.acyclic.cycle.map (graphNodeText master)).toList
          throw <| IO.userError s!"Blueprint uses-graph check FAILED (acyclicity): a dependency cycle was detected among: {cyc}. Remove the cyclic `uses` edges."
        unless checks.connected.ok || !requireConnected do
          let strag := String.intercalate ", " (checks.connected.stragglers.map (graphNodeText master)).toList
          throw <| IO.userError s!"Blueprint uses-graph check FAILED (connectivity): the `uses` graph has {checks.connected.componentCount} disconnected components. Nodes outside the main component: {strag}. Connect them to the main development, or set verso.blueprint.trust.requireConnected := false for a deliberately multi-topic blueprint."

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
      let trust? := cachedTrust? state
      match trust?.bind (·.comparator) with
      | none => pure ()
      | some cmp =>
        let ciUrl? : Option String :=
          if cmp.runUrl.isEmpty then trust?.bind (·.ciRunUrl) else some cmp.runUrl
        Informal.NodePage.emitStaticBlueprintPage mode cfg state text
          Informal.NodeRoute.comparatorPath "Statement comparator" (comparatorBody cmp ciUrl?)

end Informal.Commands
