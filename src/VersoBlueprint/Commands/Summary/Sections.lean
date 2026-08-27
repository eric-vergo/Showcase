/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Emilio J. Gallego Arias, Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Commands.Graph
import VersoBlueprint.Commands.Summary.Html
import VersoBlueprint.GraphApi
import VersoBlueprint.GraphMetrics
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.Lib.PreviewSource
import VersoBlueprint.NodeRoute
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

/-!
Section assembly and `Block.summary` registration for `blueprint_summary`.
-/

namespace Informal.Commands

open Lean Elab Command
open Informal Data Environment
open Verso Doc Html Genre Manual
open Verso.Output.Html
open Verso.Multi (AllRemotes)

private def summaryOverviewSection (data : Summary) (rows : SummaryRows) : Output.Html :=
  let showBlockers := rows.blockerCount > 0
  let showPendingInformal := !rows.pendingInformalRows.isEmpty
  let showQuickWins := !rows.quickWinRows.isEmpty
  summarySection "Overview" {{
      <div class="bp_summary_grid">
        {{summaryCard "Total entries" (toString data.totalEntries) (Option.some (statusCountsText data.totalStatus))}}
        {{summaryCard
            "Ready now"
            (toString data.coverageSplit.readyToFormalize)
            (Option.some "Entries whose next formalization step is currently unblocked.")}}
        {{summaryCard
            "Fully closed"
            (toString data.coverageSplit.fullyClosed)
            (Option.some "Local code and prerequisite closure are both complete.")}}
        {{summaryCard
            "Actionable priorities"
            (toString data.topPriorities.length)
            (Option.some "Entries ready now and already unlocking downstream work.")}}
        {{summaryOptionalWarnCard
            showBlockers
            "Current blockers"
            (toString rows.blockerCount)
            (Option.some "Missing external or incomplete Lean declarations.")}}
        {{summaryOptionalCard
            showPendingInformal
            "Missing informal coverage"
            (toString data.pendingInformalEntries.length)
            (Option.some "Entries with Lean code but missing an informal statement or proof block.")}}
        {{summaryOptionalCard
            showQuickWins
            "Quick wins"
            (toString data.quickWins.length)
            (Option.some "Actionable entries with `high` priority and `small` effort.")}}
      </div>
      {{if data.totalEntries == 0 then
          {{<p class="bp_summary_empty">"No blueprint entries were registered in the current document."</p>}}
        else .empty}}
      {{summaryOptionalCappedDetailsList
          (!rows.topPriorityRows.isEmpty)
          s!"Ready next ({data.topPriorities.length})"
          rows.topPriorityRows
          "priorities"
          "bp_summary_subsection"
          true}}
      {{summaryOptionalDetailsList
          showBlockers
          s!"Current blockers ({rows.blockerCount})"
          rows.blockerRows
          "bp_summary_subsection bp_summary_subsection_warn"
          true}}
      {{summaryOptionalDetailsList
          showPendingInformal
          s!"Missing informal coverage ({data.pendingInformalEntries.length})"
          rows.pendingInformalRows}}
    }} true

private def summaryEntryIndexSection (data : Summary) (rows : SummaryRows) : Output.Html :=
  let showDefinitionCard := data.definitions > 0
  let showPropositionCard := data.propositions > 0
  let showLemmaCard := data.lemmas > 0
  let showTheoremCard := data.theorems > 0
  let showCorollaryCard := data.corollaries > 0
  let showAxiomCard := data.axioms > 0
  let showLeanOnlyCard := data.leanOnlyEntries > 0
  let showInformalOnlyCard := data.informalOnlyEntries > 0
  let showDefinitionIndex := !rows.definitionRows.isEmpty
  let showTheoremLikeIndex := !rows.theoremLikeRows.isEmpty
  let showAxiomIndex := !rows.axiomRows.isEmpty
  let showTheoremLikeByParent := !rows.theoremLikeByParentRows.isEmpty
  if !(showDefinitionIndex || showTheoremLikeIndex || showAxiomIndex) then
    .empty
  else
    summarySection s!"Entry index ({data.totalEntries})" {{
        <div class="bp_summary_grid">
          {{summaryOptionalCard
              showDefinitionCard
              "Definitions"
              (toString data.definitions)
              (Option.some (statusCountsText data.definitionStatus))}}
          {{summaryOptionalCard
              showPropositionCard
              "Propositions"
              (toString data.propositions)
              (Option.some (statusCountsText data.propositionStatus))}}
          {{summaryOptionalCard showLemmaCard "Lemmas" (toString data.lemmas) (Option.some (statusCountsText data.lemmaStatus))}}
          {{summaryOptionalCard showTheoremCard "Theorems" (toString data.theorems) (Option.some (statusCountsText data.theoremStatus))}}
          {{summaryOptionalCard
              showCorollaryCard
              "Corollaries"
              (toString data.corollaries)
              (Option.some (statusCountsText data.corollaryStatus))}}
          {{summaryOptionalWarnCard
              showAxiomCard
              "Axiom-like entries"
              (toString data.axioms)
              (Option.some (statusCountsText data.axiomStatus))}}
          {{summaryOptionalCard showLeanOnlyCard "Lean-only entries" (toString data.leanOnlyEntries)}}
          {{summaryOptionalCard showInformalOnlyCard "Informal-only entries" (toString data.informalOnlyEntries)}}
        </div>
        {{summaryOptionalDetailsList showDefinitionIndex s!"Definition Index ({data.definitionIndex.length})" rows.definitionRows}}
        {{if showTheoremLikeIndex then
            {{<details class="bp_summary_subsection">
              <summary>s!"Theorem / Proposition / Lemma / Corollary Index ({data.theoremLikeIndex.length})"</summary>
              <ul class="bp_summary_list">
                {{rows.theoremLikeRows}}
              </ul>
              {{if showTheoremLikeByParent then
                  {{<details class="bp_summary_nested">
                    <summary>s!"By parent groups ({data.theoremLikeByParent.length})"</summary>
                    {{rows.theoremLikeByParentRows}}
                  </details>}}
                else .empty}}
            </details>}}
        else .empty}}
        {{summaryOptionalDetailsList
            showAxiomIndex
            s!"Axiom-like Index ({data.axiomIndex.length})"
            rows.axiomRows
            "bp_summary_subsection bp_summary_subsection_warn"}}
      }}

private def summaryDependencyInsightsSection (rows : SummaryRows) : Output.Html :=
  if rows.statementUsedRows.isEmpty && rows.proofUsedRows.isEmpty && rows.groupHealthRows.isEmpty then
    .empty
  else
    summarySection "Dependency insights" {{
        <div class="bp_summary_grid">
          {{summaryOptionalCard
              (!rows.statementUsedRows.isEmpty)
              "Statement-used entries"
              (toString rows.statementUsedItems.size)
              (Option.some "Entries reused in statement dependencies.")}}
          {{summaryOptionalCard
              (!rows.proofUsedRows.isEmpty)
              "Proof-used entries"
              (toString rows.proofUsedItems.size)
              (Option.some "Entries reused in proof-only dependencies.")}}
          {{summaryOptionalCard
              (!rows.groupHealthRows.isEmpty)
              "Tracked parent groups"
              (toString rows.groupHealthRows.size)
              (Option.some "Grouped health rollups for parents with more than one child entry.")}}
        </div>
        {{summaryOptionalCappedDetailsList
            (!rows.statementUsedRows.isEmpty)
            s!"Most used in statements ({rows.statementUsedItems.size})"
            rows.statementUsedRows
            "statement-used entries"}}
        {{summaryOptionalCappedDetailsList
            (!rows.proofUsedRows.isEmpty)
            s!"Most used in proofs ({rows.proofUsedItems.size})"
            rows.proofUsedRows
            "proof-used entries"}}
        {{summaryOptionalCappedDetailsList
            (!rows.groupHealthRows.isEmpty)
            s!"Group health ({rows.groupHealthRows.size})"
            rows.groupHealthRows
            "groups"}}
      }}

private def summaryMetadataSection (data : Summary) (rows : SummaryRows) : Output.Html :=
  let showQuickWins := !rows.quickWinRows.isEmpty
  let showOwnerRollups := !rows.ownerRollupRows.isEmpty
  let showTagRollups := !rows.tagRollupRows.isEmpty
  let showLinkedPrs := !rows.linkedPrRows.isEmpty
  let showMetadataAudit :=
    !rows.missingOwnerRows.isEmpty || !rows.missingEffortRows.isEmpty || !rows.untaggedRows.isEmpty
  let showMetadataCards := showQuickWins || showOwnerRollups || showTagRollups || showLinkedPrs
  if !(showMetadataCards || showMetadataAudit) then
    .empty
  else
    summarySection "Metadata" {{
        {{if showMetadataCards then
            {{<div class="bp_summary_grid">
              {{summaryOptionalCard
                  showQuickWins
                  "Quick wins"
                  (toString data.quickWins.length)
                  (Option.some "Actionable entries with `high` priority and `small` effort.")}}
              {{summaryOptionalCard
                  showOwnerRollups
                  "Owners in use"
                  (toString data.ownerRollups.length)
                  (Option.some "Distinct owners referenced by the current blueprint entries.")}}
              {{summaryOptionalCard
                  showTagRollups
                  "Tags in use"
                  (toString data.tagRollups.length)
                  (Option.some "Distinct tags currently attached to blueprint entries.")}}
              {{summaryOptionalCard
                  showLinkedPrs
                  "Linked PRs"
                  (toString data.linkedPrs.length)
                  (Option.some "Entries already linked to a review URL.")}}
            </div>}}
          else .empty}}
        {{summaryOptionalCappedDetailsList
            showQuickWins
            s!"Quick wins ({data.quickWins.length})"
            rows.quickWinRows
            "quick wins"}}
        {{summaryOptionalCappedDetailsList
            showOwnerRollups
            s!"Owner rollups ({data.ownerRollups.length})"
            rows.ownerRollupRows
            "owners"}}
        {{summaryOptionalCappedDetailsList
            showTagRollups
            s!"Tag rollups ({data.tagRollups.length})"
            rows.tagRollupRows
            "tags"}}
        {{summaryOptionalCappedDetailsList
            showLinkedPrs
            s!"Linked PRs ({data.linkedPrs.length})"
            rows.linkedPrRows
            "linked PR entries"}}
        {{if showMetadataAudit then
            {{<details class="bp_summary_subsection bp_summary_subsection_warn">
              <summary>"Metadata audit"</summary>
              <div class="bp_summary_grid">
                {{summaryOptionalWarnCard
                    (!rows.missingOwnerRows.isEmpty)
                    "Missing owner"
                    (toString data.missingOwners.length)}}
                {{summaryOptionalWarnCard
                    (!rows.missingEffortRows.isEmpty)
                    "Missing effort"
                    (toString data.missingEffort.length)}}
                {{summaryOptionalWarnCard
                    (!rows.untaggedRows.isEmpty)
                    "Untagged"
                    (toString data.untaggedEntries.length)}}
              </div>
              {{summaryOptionalCappedDetailsList
                  (!rows.missingOwnerRows.isEmpty)
                  s!"Missing owner ({data.missingOwners.length})"
                  rows.missingOwnerRows
                  "entries missing owner"
                  "bp_summary_nested"}}
              {{summaryOptionalCappedDetailsList
                  (!rows.missingEffortRows.isEmpty)
                  s!"Missing effort ({data.missingEffort.length})"
                  rows.missingEffortRows
                  "entries missing effort"
                  "bp_summary_nested"}}
              {{summaryOptionalCappedDetailsList
                  (!rows.untaggedRows.isEmpty)
                  s!"Untagged ({data.untaggedEntries.length})"
                  rows.untaggedRows
                  "untagged entries"
                  "bp_summary_nested"}}
            </details>}}
          else .empty}}
      }}

private def summaryDiagnosticsSection (data : Summary) (rows : SummaryRows) : Output.Html :=
  if !(data.showDebugDiagnostics && !rows.renderFailureRows.isEmpty) then
    .empty
  else
    summarySection "Maintainer diagnostics" {{
        <div class="bp_summary_grid">
          {{summaryWarnCard
              "Render failures"
              (toString data.renderFailures.length)
              (Option.some "External declarations that checked in Lean but failed HTML rendering.")}}
        </div>
        {{summaryCappedDetailsList
            s!"Render failures ({data.renderFailures.length})"
            rows.renderFailureRows
            "render-failure entries"
            "bp_summary_subsection bp_summary_subsection_warn"}}
      }}

private def summaryStructureSection (data : Summary) (rows : SummaryRows) : Output.Html :=
  let showHeaviestPrerequisites := !rows.heaviestPrerequisiteRows.isEmpty
  let showNoPrerequisites := !rows.noPrerequisiteRows.isEmpty
  let showNoDependents := !rows.noDependentRows.isEmpty
  let showProofDebtHotspots := !rows.proofDebtHotspotRows.isEmpty
  let showStructureCards :=
    data.coverageSplit.informalOnly > 0 ||
    data.coverageSplit.readyToFormalize > 0 ||
    data.coverageSplit.formalizedWithoutAncestors > 0 ||
    data.coverageSplit.fullyClosed > 0 ||
    data.coverageSplit.blockedOrIncomplete > 0
  if !(showStructureCards || showHeaviestPrerequisites || showNoPrerequisites ||
      showNoDependents || showProofDebtHotspots) then
    .empty
  else
    summarySection "Structure and coverage" {{
        <div class="bp_summary_grid">
          {{summaryOptionalCard
              (data.coverageSplit.informalOnly > 0)
              "Informal-only"
              (toString data.coverageSplit.informalOnly)
              (Option.some "Statements with no associated Lean code yet.")}}
          {{summaryOptionalCard
              (data.coverageSplit.readyToFormalize > 0)
              "Ready to formalize"
              (toString data.coverageSplit.readyToFormalize)
              (Option.some "Entries whose next step is currently unblocked.")}}
          {{summaryOptionalCard
              (data.coverageSplit.formalizedWithoutAncestors > 0)
              "Formalized, ancestors open"
              (toString data.coverageSplit.formalizedWithoutAncestors)
              (Option.some "Local Lean work is done, but prerequisite closure is still open.")}}
          {{summaryOptionalCard
              (data.coverageSplit.fullyClosed > 0)
              "Fully closed"
              (toString data.coverageSplit.fullyClosed)
              (Option.some "Local code and ancestor closure are both complete.")}}
          {{summaryOptionalWarnCard
              (data.coverageSplit.blockedOrIncomplete > 0)
              "Blocked or incomplete"
              (toString data.coverageSplit.blockedOrIncomplete)
              (Option.some "Entries not covered by the highlighted readiness buckets above.")}}
        </div>
        {{summaryOptionalCappedDetailsList
            showHeaviestPrerequisites
            s!"Heaviest prerequisites ({data.heaviestPrerequisites.length})"
            rows.heaviestPrerequisiteRows
            "heaviest-prerequisite entries"}}
        {{summaryOptionalCappedDetailsList
            showNoPrerequisites
            s!"No prerequisites ({data.noPrerequisites.length})"
            rows.noPrerequisiteRows
            "entries without prerequisites"}}
        {{summaryOptionalCappedDetailsList
            showNoDependents
            s!"No dependents ({data.noDependents.length})"
            rows.noDependentRows
            "entries without dependents"}}
        {{summaryOptionalCappedDetailsList
            showProofDebtHotspots
            s!"Proof debt hotspots ({data.proofDebtHotspots.length})"
            rows.proofDebtHotspotRows
            "proof-debt hotspots"
            "bp_summary_subsection bp_summary_subsection_warn"}}
      }}

/--
The six blueprint summary detail sections, composed in document order.

Factored out of `summaryBlockToHtml` so the future dashboard surface can embed
the same detail sections. The individual `summary*Section` builders stay
`private`; this exposes only their composition. The output is byte-equivalent to
inlining the six section calls directly in a parent element.
-/
def renderSummaryDetailSections (data : Summary) (rows : SummaryRows) : Output.Html := {{
    {{summaryOverviewSection data rows}}
    {{summaryEntryIndexSection data rows}}
    {{summaryDependencyInsightsSection rows}}
    {{summaryMetadataSection data rows}}
    {{summaryDiagnosticsSection data rows}}
    {{summaryStructureSection data rows}}
  }}

private def summaryBlockToHtml : BlockToHtml Manual (ReaderT AllRemotes (ReaderT ExtensionImpls (BuildLogT IO))) :=
  fun _goI _goB _id json _blocks => do
    let some data ←
        Informal.ExtensionDecode.decode?
          (α := Summary)
          json
          (fun err => s!"Malformed data in Block.summary.toHtml ({err})")
      | pure .empty
    let s ← HtmlT.state
    let previewLookupKeys := (data.previewLabels).foldl (init := ({} : Lean.NameMap String)) fun keys label =>
      match Informal.PreviewSource.traversalSelection? s label with
      | some selection => keys.insert label selection.key
      | Option.none => keys
    let ctx : SummaryHtmlContext := {
      entryHref? := fun label => Informal.TraversalIndex.Nodes.href? s label
      declHref? := fun label decl =>
        Resolve.resolveInformalDeclHref? s label decl
      previewLookupKey? := fun label => previewLookupKeys.get? label
      displayLabel := fun label => Informal.NodeRoute.friendlyEntryLabel s label
    }
    let previewPanel := Informal.HoverRender.summaryPreviewPanel
    let summaryAttrs :=
      #[("class", "bp_summary")] ++
        Informal.HoverRender.templatePreviewDescriptorAttrs
          ".bp_summary_preview_panel"
          "template.bp_summary_preview_tpl[data-bp-preview-label]"
          ".bp_summary_preview_wrap_active[data-bp-preview-label]"
          ".bp_summary_preview_panel_title"
          ".bp_summary_preview_panel_body"
          ".bp_summary_preview_panel_close"
          (allowHtmlCache := true)
    let rows ← SummaryRows.render ctx data
    pure {{
      <div {{summaryAttrs}}>
        {{previewPanel}}
        {{renderSummaryDetailSections data rows}}
      </div>
    }}

open Verso Doc Elab Genre Manual in
block_extension Block.summary (summary : Summary) where
  data := toJson summary
  traverse id _data _contents := do
    -- Record this block's page anchor so the PM hub can cross-link the standalone
    -- Blueprint Summary page without guessing its slug (mirrors `Block.formalization`).
    -- `externalTag` uniquifies the tag, so multiple summary blocks never collide; when
    -- more than one exists `SummaryPage.href?` resolves to `none` and the link is omitted.
    let path ← (·.path) <$> read
    let _ ← Verso.Genre.Manual.externalTag id path "--bp-summary"
    modify fun st => Informal.TraversalIndex.SummaryPage.saveId st id
    return none
  toTeX := none
  toHtml := some summaryBlockToHtml
  extraCss := summaryAssetBundle.css
  extraJs := summaryAssetBundle.js

/-!
Dashboard surface (`blueprint_dashboard`).

`Block.dashboard` mirrors `Block.summary` but renders the landing dashboard:
a server-rendered hero progress bar, per-chapter progress bars, status/owner/tag
chart mounts (each carrying a server-rendered fallback that progressive
enhancement augments with d3 charts), an embedded `chartData` JSON payload for
those charts, and the full summary detail sections in a collapsed `<details>`.

Its `traverse` decodes the `Summary` and writes it to the traversal-cached
`Summary` store (`Informal.TraversalIndex.Summary.saveData`); this is the only
producer for that store, so post-elaboration consumers (e.g. PM-page emission)
can read it back via `cachedSummary?`.
-/

/-- A labelled chart mount carrying its server-rendered fallback content. -/
def dashboardChartMount (chart title : String) (wide : Bool)
    (fallback : Output.Html) : Output.Html :=
  let cls := if wide then "bp_dashboard_chart bp_dashboard_chart_wide" else "bp_dashboard_chart"
  {{
    <div class={{cls}} "data-bp-chart"={{chart}}>
      <h3 class="bp_dashboard_chart_title">{{.text true title}}</h3>
      <div class="bp_dashboard_chart_fallback">
        {{fallback}}
      </div>
    </div>
  }}

/--
Drop leading token-prefix segments from a `:`-split label, never dropping the
final segment. A segment counts as a token prefix when it is non-empty and
purely alphabetic (e.g. `code`, `lem`, `def`, `thm`, `cor`). Structural
recursion on the list, so it always terminates.
-/
private def dropLabelTagPrefixes : List String → List String
  | [] => []
  | [last] => [last]
  | (seg :: rest) =>
    if seg ≠ "" && seg.all Char.isAlpha then dropLabelTagPrefixes rest
    else seg :: rest

/--
Clean a raw graph-node label for display in the reading map: drop the Lean
name-escape guillemets and any leading token-prefix tags, so a page-less
Lean-code-backed node like `code:lem:RaRalpha` reads as `RaRalpha` and
`def:noperthedron_main` as `noperthedron_main`. Pure/deterministic.
-/
private def cleanReadingMapLabel (raw : String) : String :=
  let deg := Informal.NodeRoute.stripNameEscapes raw
  String.intercalate ":" (dropLabelTagPrefixes (deg.splitOn ":"))

/--
Render a display string, inserting `<wbr>` break opportunities after each `_` and
`.` so long Lean identifiers (e.g. `Complex.norm_natCast_cpow_sub_add_one_cpow_le`)
wrap at segment boundaries in narrow columns instead of overflowing or breaking a
lone trailing character. A string with no `_`/`.` renders as a single text node, so
ordinary titles ("Lemma 7.7") keep byte-identical output. Shared by the reading map
and the worklist / Mathlib-candidate rows (`ExtraPages`).
-/
def withIdentifierBreaks (s : String) : Output.Html :=
  if s.all (fun c => c != '_' && c != '.') then .text true s
  else
    let wbr : Output.Html := {{<wbr/>}}
    let (parts, cur) := s.toList.foldl (init := ((#[] : Array Output.Html), "")) fun (parts, cur) c =>
      let cur := cur.push c
      if c == '_' || c == '.' then (parts.push (.text true cur) |>.push wbr, "")
      else (parts, cur)
    .seq (if cur.isEmpty then parts else parts.push (.text true cur))

/--
"Start here" reading map: an orienting, clickable guided reading path computed
from the master dependency graph's metrics.

* **Foundations** — roots with no prerequisites (`fanIn = 0`);
* **Critical path** — the single longest dependency chain (the development's
  spine), rendered as an ordered path;
* **Goals** — sinks nothing else depends on (`fanOut = 0`).

Each item links to the entry's node page when it has one (falling back to its
chapter anchor). Pure presentation derived from `masterGraph` + `computeGraphMetrics`.
-/
def dashboardReadingMap (state : TraverseState) : Output.Html :=
  let master := Informal.GraphApi.masterGraph state
  if master.nodes.isEmpty then .empty
  else
    let metrics := Informal.GraphMetrics.computeGraphMetrics master
    let nodeByLabel : Lean.NameMap Informal.Graph.NodeData :=
      master.nodes.foldl (init := {}) fun m n => m.insert n.label n
    -- Friendly display title for a label: the node's own title when present
    -- (e.g. "Lemma 7.7"), otherwise the cleaned raw label (token-prefix and
    -- guillemets stripped) so a raw `code:lem:…` never surfaces.
    let friendlyTitle := fun (label : Lean.Name) =>
      match nodeByLabel.find? label with
      | Option.some n => if n.title.isEmpty then cleanReadingMapLabel label.toString else n.title
      | Option.none => cleanReadingMapLabel label.toString
    -- Navigable friendly-title link to a label's node page. Only meaningful for
    -- labels that actually have a node page (`hasNodePage`).
    let nodePageLink := fun (label : Lean.Name) =>
      {{ <a href={{Informal.NodeRoute.nodePageHref label}}>{{withIdentifierBreaks (friendlyTitle label)}}</a> }}
    let cap := 12
    -- Foundations / Goals: include only entries that resolve to a node page,
    -- rendered as friendly-title links; page-less code-only nodes are dropped.
    let bulletList := fun (labels : Array Lean.Name) =>
      let withPage := labels.filter (Informal.NodeRoute.hasNodePage state ·)
      let shown := (withPage.toList.take cap).toArray
      {{ <ul class="bp_readingmap_list">{{shown.map (fun l => {{<li>{{nodePageLink l}}</li>}})}}</ul> }}
    let foundationLabels := (metrics.nodes.filter (·.fanIn == 0)).map (·.label)
    let goalLabels := (metrics.nodes.filter (·.fanOut == 0)).map (·.label)
    let spine := metrics.criticalPath
    -- Critical path: keep the full ordered spine. Steps with a node page stay
    -- friendly-title links; page-less steps render a cleaned, non-linked label.
    let spineItem := fun (label : Lean.Name) =>
      if Informal.NodeRoute.hasNodePage state label then nodePageLink label
      else {{ <span>{{withIdentifierBreaks (cleanReadingMapLabel label.toString)}}</span> }}
    let spineList : Output.Html :=
      if spine.isEmpty then
        {{<p class="bp_readingmap_col_hint">"No critical path in the current graph."</p>}}
      else
        {{ <ol class="bp_readingmap_spine">{{spine.map (fun l => {{<li>{{spineItem l}}</li>}})}}</ol> }}
    -- A blueprint that carries a proof overview has a better first step than the
    -- foundations: the shape of the argument. Omitted entirely when there is none.
    let overviewHint : Output.Html :=
      match Informal.TraversalIndex.OverviewPage.href? state with
      | Option.some href =>
        {{ <p class="bp_readingmap_intro">
             "For the shape of the whole argument before its parts, start from the "
             <a href={{href}}>"proof overview"</a> "."
           </p> }}
      | Option.none => .empty
    if foundationLabels.isEmpty && goalLabels.isEmpty && spine.isEmpty then .empty
    else {{
      <section class="bp_readingmap">
        <h2 class="bp_readingmap_title">"Start here"</h2>
        <p class="bp_readingmap_intro">
          "A guided reading path through the blueprint: start from the foundations, \
           follow the critical-path spine, and aim for the goals."
        </p>
        {{overviewHint}}
        <div class="bp_readingmap_cols">
          <div>
            <h3 class="bp_readingmap_col_title">"Foundations"</h3>
            <p class="bp_readingmap_col_hint">"Entries with no prerequisites."</p>
            {{bulletList foundationLabels}}
          </div>
          <div>
            <h3 class="bp_readingmap_col_title">"Critical path"</h3>
            <p class="bp_readingmap_col_hint">"The longest dependency chain — the spine of the development."</p>
            {{spineList}}
          </div>
          <div>
            <h3 class="bp_readingmap_col_title">"Goals"</h3>
            <p class="bp_readingmap_col_hint">"Entries nothing else depends on."</p>
            {{bulletList goalLabels}}
          </div>
        </div>
      </section>
    }}

/-- Overall formalization-progress hero: a large percentage plus a multi-segment
(closed / ready / blocked / other) progress bar. Extracted from the dashboard block
so the PM page (`ExtraPages.emitBlueprintPmPage`) renders the identical bar. -/
def dashboardHero (data : Summary) : Output.Html :=
  let total := data.totalEntries
  let closed := data.coverageSplit.fullyClosed
  let heroReady := data.coverageSplit.readyToFormalize
  let heroBlocked := data.coverageSplit.blockedOrIncomplete
  let denom := Nat.max 1 total
  let pct := closed * 100 / denom
  -- Mirror the per-chapter multi-segment breakdown (closed / ready / blocked /
  -- other). Segment widths are percentages of `max 1 total`, matching the chapter bars.
  let heroClosedPct := closed * 100 / denom
  let heroReadyPct := heroReady * 100 / denom
  let heroBlockedPct := heroBlocked * 100 / denom
  let heroOtherPct := 100 - Nat.min 100 (heroClosedPct + heroReadyPct + heroBlockedPct)
  let heroSeg := fun (cls : String) (segPct : Nat) =>
    if segPct == 0 then (.empty : Output.Html)
    else {{ <span class={{cls}} "style"={{s!"width:{segPct}%"}}></span> }}
  let heroSegs : Array Output.Html := #[
    heroSeg "bp_progress_seg bp_progress_seg_closed" heroClosedPct,
    heroSeg "bp_progress_seg bp_progress_seg_ready" heroReadyPct,
    heroSeg "bp_progress_seg bp_progress_seg_blocked" heroBlockedPct,
    heroSeg "bp_progress_seg bp_progress_seg_other" heroOtherPct
  ]
  {{
    <section class="bp_dashboard_hero">
      <div class="bp_dashboard_hero_head">
        <h2 class="bp_dashboard_title">"Formalization progress"</h2>
        <span class="bp_dashboard_hero_pct">{{.text true s!"{pct}%"}}</span>
      </div>
      <div class="bp_progress bp_progress_hero">
        <div class="bp_progress_track">
          {{heroSegs}}
        </div>
        <div class="bp_progress_legend">
          {{.text true s!"{closed} of {total} entries fully closed"}}
        </div>
      </div>
    </section>
  }}

/-- One per-chapter multi-segment progress bar (closed / ready / blocked / other).
The repeated per-bar `.bp_progress_legend` line is dropped (low signal across many
near-identical bars); the counts stay accessible via `aria-label`/`title`. Extracted
so the PM page reuses the dashboard's bar rendering verbatim. -/
def dashboardChapterBar (label : String) (cClosed cReady cBlocked cTotal : Nat) : Output.Html :=
  let cDenom := Nat.max 1 cTotal
  let cClosedPct := cClosed * 100 / cDenom
  let cReadyPct := cReady * 100 / cDenom
  let cBlockedPct := cBlocked * 100 / cDenom
  let cOtherPct := 100 - Nat.min 100 (cClosedPct + cReadyPct + cBlockedPct)
  let cSeg := fun (cls : String) (segPct : Nat) =>
    if segPct == 0 then (.empty : Output.Html)
    else {{ <span class={{cls}} "style"={{s!"width:{segPct}%"}}></span> }}
  let cSegs : Array Output.Html := #[
    cSeg "bp_progress_seg bp_progress_seg_closed" cClosedPct,
    cSeg "bp_progress_seg bp_progress_seg_ready" cReadyPct,
    cSeg "bp_progress_seg bp_progress_seg_blocked" cBlockedPct,
    cSeg "bp_progress_seg bp_progress_seg_other" cOtherPct
  ]
  let counts := s!"closed {cClosed} / ready {cReady} / blocked {cBlocked} / total {cTotal}"
  let cAria := s!"{label}: {cClosed} closed, {cReady} ready, {cBlocked} blocked of {cTotal} total"
  {{ <div class="bp_progress" role="group" "aria-label"={{cAria}} "title"={{counts}}>
      <div class="bp_progress_head">
        <span class="bp_progress_label">{{.text true label}}</span>
        <span class="bp_progress_pct">{{.text true s!"{cClosedPct}%"}}</span>
      </div>
      <div class="bp_progress_track">
        {{cSegs}}
      </div>
    </div> }}

/-- Per-chapter progress bars for a summary (the "chapters" chart fallback), or an
empty-state note when no multi-entry chapters exist. -/
def dashboardChaptersFallback (data : Summary) : Output.Html :=
  let chapterBars : Array Output.Html :=
    data.groupHealth.toArray.map fun g =>
      -- Prefer the short chapter title (resolved at emit); fall back to the long
      -- group header, then the raw parent label.
      let label :=
        if !g.title.isEmpty then g.title
        else if !g.header.isEmpty then g.header
        else toString g.parent
      dashboardChapterBar label g.closedEntries g.readyEntries g.blockedEntries g.totalEntries
  if chapterBars.isEmpty then
    {{<p class="bp_summary_empty">"No grouped chapters with multiple entries yet."</p>}}
  else
    {{<div class="bp_dashboard_chapters_list">{{chapterBars}}</div>}}

def dashboardBlockToHtml : BlockToHtml Manual (ReaderT AllRemotes (ReaderT ExtensionImpls (BuildLogT IO))) :=
  fun _goI goB _id json _blocks => do
    let some data ←
        Informal.ExtensionDecode.decode?
          (α := Summary)
          json
          (fun err => s!"Malformed data in Block.dashboard.toHtml ({err})")
      | pure .empty
    let s ← HtmlT.state
    -- The de-chromed landing dashboard renders ONLY the consumer-featured
    -- side-by-side node cards. The hero, reading map, charts, and full summary all
    -- moved to the PM page (`ExtraPages.emitBlueprintPmPage`); an unconfigured
    -- consumer (no `featured := "…"`) renders nothing here, leaving a minimal
    -- title / authors / trust-strip landing.
    let namePrefix := (Informal.TraversalIndex.DeclRegistry.namePrefix? s).getD ""
    let mut cards : Array Output.Html := #[]
    for label in data.featuredLabels do
      match ← renderFeaturedNodeCard? goB s namePrefix label with
      | some card => cards := cards.push card
      | Option.none =>
        Verso.reportWarning
          s!"blueprint_dashboard: featured node '{label}' has no cached statement preview; \
             skipping its card (is the label a blueprint node in this document?)"
    let featured : Output.Html :=
      if cards.isEmpty then .empty
      else {{ <div class="bp_dashboard_featured">{{cards}}</div> }}
    pure {{
      <div class="bp_dashboard">
        {{featured}}
      </div>
    }}

open Verso Doc Elab Genre Manual in
block_extension Block.dashboard (summary : Summary) where
  data := toJson summary
  traverse _id data _contents := do
    match ← Informal.ExtensionDecode.decode? (α := Summary) data
        (fun _ => "Malformed data in Block.dashboard.traverse") with
    | some summary =>
      modify fun state => Informal.TraversalIndex.Summary.saveData state summary
    | Option.none =>
      pure ()
    return none
  toTeX := none
  toHtml := some dashboardBlockToHtml
  extraCss := dashboardAssetBundle.css
  extraJs := dashboardAssetBundle.js

end Informal.Commands
