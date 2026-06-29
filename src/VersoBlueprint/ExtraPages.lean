/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.NodePage
import VersoBlueprint.NodeRoute
import VersoBlueprint.Commands.Summary.Html

/-!
Project-management surfaces emitted as standalone static pages, plus the README
progress badge.

`emitBlueprintExtraPages` is the `ExtraStep` that reads the document-wide
`Summary` cached during traversal (`Informal.TraversalIndex.Summary.cachedSummary?`,
populated by the dashboard block) and emits:

* a filterable **worklist** page (`worklist/index.html`) — the full per-entry
  worklist grouped by readiness bucket, server-rendered, with a progressive
  client-side filter that only ever *hides* rows;
* one **owner** page per owner rollup (`owners/<slug>/index.html`) — that owner's
  worklist items plus the owner rollup card, build-time static, zero-JS;
* one **tag** page per tag rollup (`tags/<slug>/index.html`) — same, filtered by
  tag;
* a self-contained shields-style **progress badge** SVG
  (`-verso-data/progress-badge.svg`).

All pages reuse the shared `emitStaticBlueprintPage` chrome and the `bp_summary_*`
/ `bp_progress_*` design tokens (registered globally via the summary/dashboard
block `extraCss`), so they theme and degrade exactly like the rest of the site.
If no `Summary` was cached (e.g. no dashboard block in the document) the step
logs and skips gracefully rather than crashing.
-/

namespace Informal.ExtraPages

open Lean
open Verso Verso.Output Verso.Doc
open Verso.Genre Manual
open Informal.Commands
open Verso.Output.Html

/-! ## Worklist row + bucket rendering (shared by worklist / owner / tag pages) -/

/-- Ordered readiness buckets: `(readiness key, display title)`. -/
private def bucketOrder : List (String × String) := [
  ("ready", "Ready next"),
  ("blocked", "Blocked"),
  ("localOnly", "Formalized, ancestors open"),
  ("informalOnly", "Informal only"),
  ("closed", "Fully closed")
]

/-- A small pill badge reusing the global summary badge styling. -/
private def wlBadge (text : String) : Output.Html :=
  {{ <span class="bp_summary_badge">{{.text true text}}</span> }}

/--
One worklist row: links to the entry's node page (when it has one), shows its
kind, and carries `data-*` attributes (`data-status` / `data-owner` /
`data-effort` / `data-tags`) so the client filter can toggle its `hidden` flag.
-/
private def worklistRow (state : TraverseState) (item : WorklistItem) : Output.Html :=
  let labelStr := item.label.toString
  let labelNode : Output.Html :=
    if Informal.NodeRoute.hasNodePage state item.label then
      {{ <a href={{Informal.NodeRoute.nodePageHref item.label}}><code>{{.text true labelStr}}</code></a> }}
    else
      {{ <code>{{.text true labelStr}}</code> }}
  let owner := item.ownerDisplayName.getD ""
  let effort := item.effort.getD ""
  let tagsAttr := String.intercalate " " item.tags
  let proofBadge : Output.Html :=
    if item.proofStatus.isEmpty then .empty else wlBadge s!"proof: {item.proofStatus}"
  let ownerBadge : Output.Html :=
    if owner.isEmpty then .empty else wlBadge s!"owner: {owner}"
  let effortBadge : Output.Html :=
    match item.effort with | some e => wlBadge s!"effort: {e}" | none => .empty
  let priorityBadge : Output.Html :=
    match item.priority with | some p => wlBadge s!"priority: {p}" | none => .empty
  let tagBadges : Array Output.Html := item.tags.toArray.map (fun t => wlBadge s!"#{t}")
  let badges : Array Output.Html :=
    #[ wlBadge s!"statement: {item.statementStatus}", proofBadge, ownerBadge ]
      ++ tagBadges
      ++ #[ effortBadge, priorityBadge,
            wlBadge s!"downstream unlocks: {item.downstreamUses}",
            wlBadge s!"direct uses: {item.directUses}" ]
  let liAttrs : Array (String × String) := #[
    ("class", "bp_summary_item bp_worklist_item"),
    ("data-bp-worklist-row", "true"),
    ("data-status", item.readiness),
    ("data-owner", owner),
    ("data-effort", effort),
    ("data-tags", tagsAttr)
  ]
  {{
    <li {{liAttrs}}>
      <div class="bp_summary_item_top">
        <span class="bp_summary_item_head">{{labelNode}}</span>
        <span class="bp_summary_item_meta">{{.text true s!"({item.kind})"}}</span>
      </div>
      <div class="bp_summary_badge_row">{{badges}}</div>
    </li>
  }}

/-- Render a single readiness bucket as a `<details>` list, omitted if empty. -/
private def renderBucket (state : TraverseState) (items : List WorklistItem)
    (key title : String) : Output.Html :=
  let bucketItems := items.filter (fun i => i.readiness == key)
  if bucketItems.isEmpty then .empty
  else
    let rows := bucketItems.toArray.map (worklistRow state)
    let sectionAttrs : Array (String × String) :=
      #[("class", "bp_worklist_bucket"), ("data-bp-worklist-bucket", key)]
    {{ <section {{sectionAttrs}}>
        {{summaryDetailsList s!"{title} ({bucketItems.length})" rows "bp_summary_subsection" true}}
      </section> }}

/-- All readiness buckets, in canonical order, for the given items. -/
private def renderWorklistBuckets (state : TraverseState) (items : List WorklistItem) : Output.Html :=
  let buckets := bucketOrder.toArray.map (fun p => renderBucket state items p.1 p.2)
  {{ <div class="bp_worklist_buckets">{{buckets}}</div> }}

/-! ## Worklist page (filterable) -/

/-- Distinct non-empty strings, preserving first-seen order. -/
private def distinctPreserveOrder (xs : List String) : List String :=
  (xs.foldl (init := (#[] : Array String)) fun acc x =>
    if x.isEmpty || acc.contains x then acc else acc.push x).toList

/-- One labelled `<select>` filter control with an "all" option. -/
private def filterSelect (key display allLabel : String) (options : List (String × String)) :
    Output.Html :=
  let allOpts : List (String × String) := ("", allLabel) :: options
  let optNodes := allOpts.toArray.map (fun p =>
    {{ <option value={{p.1}}>{{.text true p.2}}</option> }})
  {{ <label class="bp_worklist_filter">
      <span class="bp_worklist_filter_label">{{.text true display}}</span>
      <select {{#[("data-bp-filter", key)]}}>{{optNodes}}</select>
    </label> }}

/-- Inline styling for the worklist filter bar (themes via `--bp-color-*`). -/
private def worklistCss : String := r##"
.bp_worklist_filters {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem 0.9rem;
  align-items: end;
  margin: 0 0 1rem;
  padding: 0.75rem 1rem;
  background: var(--bp-color-surface-muted, #f8fafc);
  border: 1px solid var(--bp-color-border, #cbd5e1);
  border-radius: var(--bp-radius-md, 8px);
}
.bp_worklist_filter {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  font-size: 0.8rem;
  color: var(--bp-color-text-muted, #334155);
}
.bp_worklist_filter_label { font-weight: 600; }
.bp_worklist_filter select {
  font: inherit;
  padding: 0.2rem 0.4rem;
  color: var(--bp-color-text, #111827);
  background: var(--bp-color-surface, #ffffff);
  border: 1px solid var(--bp-color-border, #cbd5e1);
  border-radius: var(--bp-radius-sm, 4px);
}
.bp_worklist_count {
  margin-left: auto;
  align-self: center;
  font-size: 0.85rem;
  color: var(--bp-color-text-muted, #334155);
}
.bp_worklist_bucket[hidden],
.bp_worklist_item[hidden] { display: none; }
"##

/--
Vendored, dependency-free filter script (progressive enhancement).

It reveals the (initially `hidden`) filter bar, then on every `<select>` change
toggles each row's `hidden` flag from the `data-*` attributes — it never adds
rows, so the full server-rendered list is intact and usable with JS disabled.
Empty buckets are collapsed and a live "N of M shown" count is updated.
-/
private def worklistJs : String := r##"
(function () {
  var script = document.currentScript;
  var root = script ? script.closest('.bp_worklist') : document.querySelector('.bp_worklist');
  if (!root) return;
  var filters = root.querySelector('[data-bp-worklist-filters]');
  if (filters) { filters.hidden = false; }
  var selects = Array.prototype.slice.call(root.querySelectorAll('[data-bp-filter]'));
  var rows = Array.prototype.slice.call(root.querySelectorAll('[data-bp-worklist-row]'));
  var buckets = Array.prototype.slice.call(root.querySelectorAll('[data-bp-worklist-bucket]'));
  var countEl = root.querySelector('[data-bp-worklist-count]');
  function apply() {
    var crit = {};
    selects.forEach(function (s) { crit[s.getAttribute('data-bp-filter')] = s.value; });
    var shown = 0;
    rows.forEach(function (r) {
      var ok = true;
      if (crit.status && r.getAttribute('data-status') !== crit.status) ok = false;
      if (ok && crit.owner && r.getAttribute('data-owner') !== crit.owner) ok = false;
      if (ok && crit.effort && r.getAttribute('data-effort') !== crit.effort) ok = false;
      if (ok && crit.tag) {
        var tags = (r.getAttribute('data-tags') || '').split(/\s+/);
        if (tags.indexOf(crit.tag) === -1) ok = false;
      }
      r.hidden = !ok;
      if (ok) shown++;
    });
    buckets.forEach(function (b) {
      b.hidden = !b.querySelector('[data-bp-worklist-row]:not([hidden])');
    });
    if (countEl) { countEl.textContent = shown + ' of ' + rows.length + ' shown'; }
  }
  selects.forEach(function (s) { s.addEventListener('change', apply); });
  apply();
})();
"##

/-- Body of the filterable worklist page. -/
private def worklistBody (state : TraverseState) (summary : Summary) : Output.Html :=
  let items := summary.worklist
  let statusOptions := bucketOrder.filter (fun p => items.any (fun i => i.readiness == p.1))
  let ownerOptions := (distinctPreserveOrder (items.filterMap (·.ownerDisplayName))).map (fun o => (o, o))
  let tagOptions := (distinctPreserveOrder (items.foldr (fun i acc => i.tags ++ acc) [])).map (fun t => (t, t))
  let effortOptions := (distinctPreserveOrder (items.filterMap (·.effort))).map (fun e => (e, e))
  let filtersAttrs : Array (String × String) := #[
    ("class", "bp_worklist_filters"),
    ("data-bp-worklist-filters", "true"),
    ("hidden", "hidden")
  ]
  let filters : Output.Html := {{
    <div {{filtersAttrs}}>
      {{filterSelect "status" "Status" "All statuses" statusOptions}}
      {{filterSelect "owner" "Owner" "All owners" ownerOptions}}
      {{filterSelect "tag" "Tag" "All tags" tagOptions}}
      {{filterSelect "effort" "Effort" "All efforts" effortOptions}}
      <span class="bp_worklist_count" {{#[("data-bp-worklist-count", "true")]}}></span>
    </div>
  }}
  {{
    <div class="bp_worklist bp_pm_page">
      <style>{{.text false worklistCss}}</style>
      <header class="bp_node_page_header">
        <h1>"Worklist"</h1>
        <p class="bp_pm_page_intro">
          {{.text true s!"All {items.length} blueprint entries, grouped by readiness. Filters narrow the list by status, owner, tag, or effort."}}
        </p>
      </header>
      {{filters}}
      {{renderWorklistBuckets state items}}
      <script>{{.text false worklistJs}}</script>
    </div>
  }}

/-! ## Owner / tag pages (build-time static, zero-JS) -/

/-- Rollup summary cards shared by owner and tag pages. -/
private def rollupCards (totalEntries actionableEntries quickWins linkedPrs : Nat) : Output.Html := {{
  <div class="bp_summary_grid">
    {{summaryCard "Entries" (toString totalEntries)}}
    {{summaryCard "Actionable" (toString actionableEntries)
        (some "Entries whose next formalization step is currently unblocked.")}}
    {{summaryCard "Quick wins" (toString quickWins)
        (some "Actionable entries with high priority and small effort.")}}
    {{summaryCard "Linked PRs" (toString linkedPrs)
        (some "Entries already linked to a review URL.")}}
  </div>
}}

/-- Body of an owner page: rollup cards + that owner's worklist items by bucket. -/
private def ownerBody (state : TraverseState) (owner : OwnerRollupItem)
    (items : List WorklistItem) : Output.Html := {{
  <div class="bp_worklist bp_pm_page">
    <header class="bp_node_page_header">
      <h1>{{.text true s!"Owner: {owner.displayName}"}}</h1>
      <p class="bp_pm_page_back">
        <a href={{Informal.NodeRoute.worklistHref}}>"← Full worklist"</a>
      </p>
    </header>
    {{rollupCards owner.totalEntries owner.actionableEntries owner.quickWins owner.linkedPrs}}
    {{renderWorklistBuckets state items}}
  </div>
}}

/-- Body of a tag page: rollup cards + that tag's worklist items by bucket. -/
private def tagBody (state : TraverseState) (tag : TagRollupItem)
    (items : List WorklistItem) : Output.Html := {{
  <div class="bp_worklist bp_pm_page">
    <header class="bp_node_page_header">
      <h1>{{.text true s!"Tag: {tag.tag}"}}</h1>
      <p class="bp_pm_page_back">
        <a href={{Informal.NodeRoute.worklistHref}}>"← Full worklist"</a>
      </p>
    </header>
    {{rollupCards tag.totalEntries tag.actionableEntries tag.quickWins tag.linkedPrs}}
    {{renderWorklistBuckets state items}}
  </div>
}}

/-! ## Progress badge SVG -/

/-- Color-grade the badge fill by percentage (shields convention). -/
private def badgeColor (pct : Nat) : String :=
  if pct ≥ 90 then "#4c1"
  else if pct ≥ 75 then "#97ca00"
  else if pct ≥ 50 then "#a4a61d"
  else if pct ≥ 30 then "#dfb317"
  else if pct ≥ 15 then "#fe7d37"
  else "#e05d44"

/--
A self-contained shields-style "formalized | NN%" badge.

Single-quoted XML attributes keep it interpolatable without escaping. It has no
external references (gradient/clip ids are internal, font-family is generic), so
it is fully offline-safe.
-/
private def progressBadgeSvg (summary : Summary) : String :=
  let total := summary.totalEntries
  let closed := summary.coverageSplit.fullyClosed
  let denom := Nat.max 1 total
  let pct := closed * 100 / denom
  let label := "formalized"
  let value := s!"{pct}%"
  let labelW := 74
  let valueW := value.length * 8 + 14
  let totalW := labelW + valueW
  let color := badgeColor pct
  let labelX := labelW / 2
  let valueX := labelW + valueW / 2
  let aria := s!"{label}: {value}"
  s!"<svg xmlns='http://www.w3.org/2000/svg' width='{totalW}' height='20' role='img' aria-label='{aria}'>\
<title>{aria}</title>\
<linearGradient id='bpb-s' x2='0' y2='100%'>\
<stop offset='0' stop-color='#bbb' stop-opacity='.1'/>\
<stop offset='1' stop-opacity='.1'/>\
</linearGradient>\
<clipPath id='bpb-r'><rect width='{totalW}' height='20' rx='3' fill='#fff'/></clipPath>\
<g clip-path='url(#bpb-r)'>\
<rect width='{labelW}' height='20' fill='#555'/>\
<rect x='{labelW}' width='{valueW}' height='20' fill='{color}'/>\
<rect width='{totalW}' height='20' fill='url(#bpb-s)'/>\
</g>\
<g fill='#fff' text-anchor='middle' \
font-family='Verdana,Geneva,DejaVu Sans,sans-serif' font-size='11'>\
<text x='{labelX}' y='15' fill='#010101' fill-opacity='.3'>{label}</text>\
<text x='{labelX}' y='14'>{label}</text>\
<text x='{valueX}' y='15' fill='#010101' fill-opacity='.3'>{value}</text>\
<text x='{valueX}' y='14'>{value}</text>\
</g>\
</svg>\n"

/-- Write the progress badge into the output `-verso-data` dir as `progress-badge.svg`. -/
private def writeProgressBadge (mode : Manual.Mode) (cfg : Manual.Config) (summary : Summary) :
    IO Unit := do
  let outDir := cfg.destination.join (match mode with | .single => "html-single" | .multi => "html-multi")
  let dataDir := outDir.join "-verso-data"
  IO.FS.createDirAll dataDir
  IO.FS.writeFile (dataDir.join "progress-badge.svg") (progressBadgeSvg summary)

/-! ## The ExtraStep -/

/--
`ExtraStep` that emits the project-management pages (worklist / owners / tags)
and the progress badge from the traversal-cached `Summary`.

Registered in the consumer's `extraSteps` after `emitBlueprintNodePages`; it is
self-contained (reads only `state`), so its position relative to the
preview-data step does not matter for correctness. Single-page mode is skipped.
If no `Summary` was cached, it logs a warning and skips without crashing.
-/
def emitBlueprintExtraPages : ExtraStep :=
  fun mode cfg state text => do
    match mode with
    | .single => pure ()
    | .multi =>
      let logger : Verso.Logger IO ← read
      match Informal.TraversalIndex.Summary.cachedSummary? state with
      | none =>
        logger.reportWarning
          "Blueprint extra pages: no cached Summary in traversal state; skipping \
           worklist/owner/tag pages and progress badge (is a `blueprint_dashboard` block present?)."
      | some summary =>
        -- Worklist (filterable; full server-rendered list).
        Informal.NodePage.emitStaticBlueprintPage mode cfg state text
          Informal.NodeRoute.worklistPath "Worklist" (worklistBody state summary)
        -- One page per owner rollup, filtered to that owner's worklist items.
        for owner in summary.ownerRollups do
          let items := summary.worklist.filter (fun i => i.ownerDisplayName == some owner.displayName)
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            (Informal.NodeRoute.ownerPagePath owner.owner)
            s!"Owner: {owner.displayName}" (ownerBody state owner items)
        -- One page per tag rollup, filtered to that tag's worklist items.
        for tag in summary.tagRollups do
          let items := summary.worklist.filter (fun i => i.tags.contains tag.tag)
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            (Informal.NodeRoute.tagPagePath tag.tag)
            s!"Tag: {tag.tag}" (tagBody state tag items)
        -- README progress badge.
        writeProgressBadge mode cfg summary

end Informal.ExtraPages
