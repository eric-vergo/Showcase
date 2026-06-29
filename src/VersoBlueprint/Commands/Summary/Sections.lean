/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Commands.Summary.Html
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.Lib.PreviewSource
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
  traverse _id _data _contents := do
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

/-- Server-rendered fallback for the status donut: the coverage-split buckets. -/
private def dashboardStatusFallback (data : Summary) : Output.Html :=
  let cs := data.coverageSplit
  let row (label : String) (value : Nat) : Output.Html :=
    if value == 0 then .empty
    else {{
      <li>
        <span class="bp_dashboard_stat_label">{{.text true label}}</span>
        <span class="bp_dashboard_stat_value">{{.text true (toString value)}}</span>
      </li>
    }}
  let rows : Array Output.Html := #[
    row "Fully closed" cs.fullyClosed,
    row "Formalized, ancestors open" cs.formalizedWithoutAncestors,
    row "Ready to formalize" cs.readyToFormalize,
    row "Informal only" cs.informalOnly,
    row "Blocked / incomplete" cs.blockedOrIncomplete
  ]
  {{ <ul class="bp_dashboard_statlist">{{rows}}</ul> }}

/-- A labelled chart mount carrying its server-rendered fallback content. -/
private def dashboardChartMount (chart title : String) (wide : Bool)
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

def dashboardBlockToHtml : BlockToHtml Manual (ReaderT AllRemotes (ReaderT ExtensionImpls (BuildLogT IO))) :=
  fun _goI _goB _id json _blocks => do
    let some data ←
        Informal.ExtensionDecode.decode?
          (α := Summary)
          json
          (fun err => s!"Malformed data in Block.dashboard.toHtml ({err})")
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
    -- Hero: overall formalization progress = fullyClosed / max 1 total.
    let total := data.totalEntries
    let closed := data.coverageSplit.fullyClosed
    let denom := Nat.max 1 total
    let pct := closed * 100 / denom
    let heroBarStyle := s!"width:{pct}%"
    let heroCards : Output.Html := {{
      <div class="bp_summary_grid">
        {{summaryCard "Total entries" (toString total) (Option.some (statusCountsText data.totalStatus))}}
        {{summaryCard "Fully closed" (toString closed)
            (Option.some "Local code and prerequisite closure are both complete.")}}
        {{summaryCard "Ready now" (toString data.coverageSplit.readyToFormalize)
            (Option.some "Entries whose next formalization step is currently unblocked.")}}
        {{summaryOptionalWarnCard (data.coverageSplit.blockedOrIncomplete > 0)
            "Blocked / incomplete" (toString data.coverageSplit.blockedOrIncomplete)
            (Option.some "Entries not covered by the readiness buckets above.")}}
      </div>
    }}
    let hero : Output.Html := {{
      <section class="bp_dashboard_hero">
        <div class="bp_dashboard_hero_head">
          <h2 class="bp_dashboard_title">"Formalization progress"</h2>
          <span class="bp_dashboard_hero_pct">{{.text true s!"{pct}%"}}</span>
        </div>
        <div class="bp_progress bp_progress_hero">
          <div class="bp_progress_track">
            <span class="bp_progress_seg bp_progress_seg_closed" "style"={{heroBarStyle}}></span>
          </div>
          <div class="bp_progress_legend">
            {{.text true s!"{closed} of {total} entries fully closed"}}
          </div>
        </div>
        {{heroCards}}
      </section>
    }}
    -- Per-chapter progress bars (the "chapters" chart fallback).
    let chapterBars : Array Output.Html :=
      data.groupHealth.toArray.map fun g =>
        let label := if g.header.isEmpty then toString g.parent else g.header
        summaryProgressBar label g.closedEntries g.readyEntries g.blockedEntries g.totalEntries
    let chaptersFallback : Output.Html :=
      if chapterBars.isEmpty then
        {{<p class="bp_summary_empty">"No grouped chapters with multiple entries yet."</p>}}
      else
        {{<div class="bp_dashboard_chapters_list">{{chapterBars}}</div>}}
    let ownersFallback : Output.Html :=
      if rows.ownerRollupRows.isEmpty then
        {{<p class="bp_summary_empty">"No owners recorded."</p>}}
      else
        {{<ul class="bp_summary_list">{{rows.ownerRollupRows}}</ul>}}
    let tagsFallback : Output.Html :=
      if rows.tagRollupRows.isEmpty then
        {{<p class="bp_summary_empty">"No tags recorded."</p>}}
      else
        {{<ul class="bp_summary_list">{{rows.tagRollupRows}}</ul>}}
    let ownerMount : Output.Html :=
      if data.ownerRollups.isEmpty then .empty
      else dashboardChartMount "owners" "Owners" false ownersFallback
    let tagMount : Output.Html :=
      if data.tagRollups.isEmpty then .empty
      else dashboardChartMount "tags" "Tags" false tagsFallback
    let chartJson : String := Lean.Json.compress (toJson data.chartData)
    pure {{
      <div class="bp_dashboard">
        {{hero}}
        <div class="bp_dashboard_charts">
          {{dashboardChartMount "status" "Coverage by status" false (dashboardStatusFallback data)}}
          {{dashboardChartMount "chapters" "Per-chapter progress" true chaptersFallback}}
          {{ownerMount}}
          {{tagMount}}
        </div>
        <script type="application/json" class="bp-dashboard-data">
          {{.text false chartJson}}
        </script>
        <details class="bp_dashboard_detail">
          <summary>"Full blueprint summary"</summary>
          <div {{summaryAttrs}}>
            {{previewPanel}}
            {{renderSummaryDetailSections data rows}}
          </div>
        </details>
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
