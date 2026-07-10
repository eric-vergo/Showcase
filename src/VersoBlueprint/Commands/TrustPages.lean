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
  single `comparator/` page showing the Challenge and Solution Lean sources and the
  comparator configuration verbatim (syntax-highlighted, with outbound source links),
  plus a link to the CI run that produced the verdict. Emits nothing when no
  comparator is configured.
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

/-- Body of the `comparator/` page: the Challenge and Solution Lean sources and the
comparator configuration, embedded verbatim (syntax-highlighted at elaboration) with
their outbound source links, plus a link to the CI run that produced the verdict. Each
block degrades to nothing when its source/file is absent. -/
private def comparatorBody (cmp : TrustComparator) (ciUrl? : Option String) : Output.Html :=
  -- Optional external link to the CI run that produced the verdict. A plain link (not a
  -- shipped asset), so it is fine under the offline constraint; omitted when neither the
  -- status artifact's `run_url` nor the `ciRunUrl` option is set.
  let ciLink : Output.Html :=
    match ciUrl? with
    | some u => {{ <p><a class="bp_trust_ci_link" href={{u}}
                     target="_blank" rel="noopener">"View CI run"</a></p> }}
    | none => .empty
  -- Challenge file: GitHub blob at the pinned commit + the Lean playground (which opens
  -- against its *current* Mathlib, not the pinned v4.31.0 toolchain).
  let challengeSection : Output.Html :=
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
      trustSection "Challenge statement (Lean)"
        (.seq #[linksRow, trustCodeBlock "bp_trust_code_lean" cmp.challengeHtml cmp.challengeSource])
  -- Solution file: the project's actual proof of the challenge statement.
  let solutionSection : Output.Html :=
    if cmp.solutionSource.isEmpty then .empty
    else
      let ghLink : Output.Html :=
        if cmp.githubSolutionUrl.isEmpty then .empty
        else {{ <p class="bp_trust_links">{{trustOutLink cmp.githubSolutionUrl "View on GitHub"}}</p> }}
      trustSection "Solution (Lean)"
        (.seq #[ghLink, trustCodeBlock "bp_trust_code_lean" cmp.solutionHtml cmp.solutionSource])
  -- The comparator's configuration JSON, collapsible.
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
    (.seq #[ciLink, challengeSection, solutionSection, configSection])

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
`ExtraStep` that emits the `comparator/` page from the traversal-cached trust payload,
when a statement comparator is configured. Single-page mode is skipped; when no
comparator is configured it emits nothing. The CI-run link prefers the status
artifact's own `run_url`, falling back to the `verso.blueprint.trust.ciRunUrl` option.
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
