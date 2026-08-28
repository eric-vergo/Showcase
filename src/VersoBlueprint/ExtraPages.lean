/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Std.Data.HashSet
import VersoBlueprint.DeclRegistry
import VersoBlueprint.NodePage
import VersoBlueprint.NodeRoute
import VersoBlueprint.Resolve
import VersoBlueprint.GraphApi
import VersoBlueprint.GraphMetrics
import VersoBlueprint.Commands.Summary.Html
import VersoBlueprint.Commands.Summary.Sections
import VersoBlueprint.Commands.TrustStrip

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

/--
A small pill badge reusing the global summary badge styling. `variant` selects a
semantic tint suffix (e.g. `"_success"`, `"_warn"`, `"_accent"`) so a row reads
by hue; the default empty variant is the neutral grey pill. `title?` carries an
optional full-phrase tooltip for compacted labels (accessibility).
-/
private def wlBadge (text : String) (variant : String := "") (title? : Option String := none) :
    Output.Html :=
  let cls := if variant.isEmpty then "bp_summary_badge" else s!"bp_summary_badge bp_summary_badge{variant}"
  match title? with
  | some t => {{ <span class={{cls}} title={{t}}>{{.text true text}}</span> }}
  | none => {{ <span class={{cls}}>{{.text true text}}</span> }}

/--
Humanize a raw Lean identifier for display: split snake_case / camelCase into
words and Title-Case them (`c1_c2_c3_norms` → "C1 C2 C3 Norms"). Used as the
worklist label fallback when no friendly "Kind N.N" title exists, so the scan
column never drops to a bare snake_case identifier.
-/
private def humanizeIdentifier (s : String) : String :=
  -- Split each `_`-chunk at lower→upper boundaries (camelCase), tracking the
  -- previous char so we never call the partial `String.back`.
  let splitCamel (chunk : String) : List String :=
    let step := chunk.toList.foldl (init := (([] : List String), "", (none : Option Char)))
      fun (words, cur, prev?) c =>
        match prev? with
        | some p =>
          if c.isUpper && !p.isUpper then
            (words ++ [cur], String.singleton c, some c)
          else
            (words, cur.push c, some c)
        | none => (words, cur.push c, some c)
    let (words, cur, _) := step
    if cur.isEmpty then words else words ++ [cur]
  let titleCase (w : String) : String :=
    match w.toList with
    | [] => ""
    | c :: rest => String.singleton c.toUpper ++ String.ofList rest
  let words := ((s.splitOn "_").filter (·.length > 0)).flatMap splitCamel
  String.intercalate " " (words.map titleCase)

/-- Semantic tint variant for a statement-status badge. -/
private def statementBadgeVariant (status : String) : String :=
  if status == "formalized" || status == "in Mathlib" then "_success" else ""

/-- Semantic tint variant for a proof-status badge. -/
private def proofBadgeVariant (status : String) : String :=
  if status == "Lean code incomplete" then "_warn"
  else if status == "locally formalized" || status == "locally formalized + dependencies complete" then "_success"
  else ""

/--
One worklist row: links to the entry's node page (when it has one), shows its
kind, and carries `data-*` attributes (`data-status` / `data-owner` /
`data-effort` / `data-tags`) so the client filter can toggle its `hidden` flag.
-/
private def worklistRow (state : TraverseState) (item : WorklistItem) : Output.Html :=
  let labelStr := Informal.NodeRoute.friendlyEntryLabel state item.label
  -- When no friendly "Kind N.N" title exists the label is a raw identifier; show
  -- a humanized form rather than bare snake_case/camelCase.
  let displayLabel :=
    if labelStr.toList.any (· == ' ') then labelStr else humanizeIdentifier labelStr
  let labelNode : Output.Html :=
    if Informal.NodeRoute.hasNodePage state item.label then
      {{ <a href={{Informal.NodeRoute.nodePageHref item.label}}>{{withIdentifierBreaks displayLabel}}</a> }}
    else
      {{ <span>{{withIdentifierBreaks displayLabel}}</span> }}
  -- Drop the parenthetical kind chip when the title already leads with that kind
  -- word (node display titles are often "Lemma foo", duplicating "(Lemma)").
  let leadingWord := (displayLabel.splitOn " ").headD ""
  let kindMeta : Output.Html :=
    if !item.kind.isEmpty && leadingWord.map Char.toLower == item.kind.map Char.toLower then .empty
    else {{ <span class="bp_summary_item_meta">{{.text true s!"({item.kind})"}}</span> }}
  let owner := item.ownerDisplayName.getD ""
  let effort := item.effort.getD ""
  let tagsAttr := String.intercalate " " item.tags
  -- Compact, self-evident badges: drop the redundant "statement:"/"proof:"/etc.
  -- key prefixes (the value is unambiguous) but keep the full phrase in `title`.
  let statementBadge : Output.Html :=
    wlBadge item.statementStatus (statementBadgeVariant item.statementStatus)
      (some s!"statement: {item.statementStatus}")
  let proofBadge : Output.Html :=
    if item.proofStatus.isEmpty then .empty
    else wlBadge item.proofStatus (proofBadgeVariant item.proofStatus) (some s!"proof: {item.proofStatus}")
  let ownerBadge : Output.Html :=
    if owner.isEmpty then .empty else wlBadge owner "" (some s!"owner: {owner}")
  let effortBadge : Output.Html :=
    match item.effort with | some e => wlBadge e "" (some s!"effort: {e}") | none => .empty
  let priorityBadge : Output.Html :=
    match item.priority with
    | some p =>
      let variant := if p == "high" then "_accent" else ""
      wlBadge p variant (some s!"priority: {p}")
    | none => .empty
  let tagBadges : Array Output.Html :=
    item.tags.toArray.map (fun t => wlBadge s!"#{t}" "_accent" (some s!"tag: {t}"))
  let badges : Array Output.Html :=
    #[ statementBadge, proofBadge, ownerBadge ]
      ++ tagBadges
      ++ #[ effortBadge, priorityBadge,
            wlBadge s!"↓{item.downstreamUses}" "" (some s!"downstream unlocks: {item.downstreamUses}"),
            wlBadge s!"→{item.directUses}" "" (some s!"direct uses: {item.directUses}") ]
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
        {{kindMeta}}
      </div>
      <div class="bp_summary_badge_row">{{badges}}</div>
    </li>
  }}

/--
Render a single readiness bucket as a `<details>` list, omitted if empty. The
actionable buckets open by default; a completed bucket (e.g. "Fully closed") can
start collapsed via `open? = false` so the page opens on the actionable work.
-/
private def renderBucket (state : TraverseState) (items : List WorklistItem)
    (key title : String) (open? : Bool := true) : Output.Html :=
  let bucketItems := items.filter (fun i => i.readiness == key)
  if bucketItems.isEmpty then .empty
  else
    let rows := bucketItems.toArray.map (worklistRow state)
    let sectionAttrs : Array (String × String) :=
      #[("class", "bp_worklist_bucket"), ("data-bp-worklist-bucket", key)]
    {{ <section {{sectionAttrs}}>
        {{summaryDetailsList s!"{title} ({bucketItems.length})" rows "bp_summary_subsection" open?}}
      </section> }}

/-- All readiness buckets, in canonical order, for the given items. The completed
    `closed` bucket starts collapsed so the page opens focused on actionable work. -/
private def renderWorklistBuckets (state : TraverseState) (items : List WorklistItem) : Output.Html :=
  let buckets := bucketOrder.toArray.map (fun p => renderBucket state items p.1 p.2 (open? := p.1 != "closed"))
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
  font-size: var(--bp-fs-small, 0.875rem);
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
  var bucketsRoot = root.querySelector('.bp_worklist_buckets') || root;
  var emptyEl = null;
  function setEmpty(on) {
    if (on) {
      if (!emptyEl) {
        emptyEl = document.createElement('p');
        emptyEl.className = 'bp_summary_empty';
        emptyEl.setAttribute('data-bp-worklist-empty', 'true');
        emptyEl.textContent = 'No entries match these filters.';
        bucketsRoot.appendChild(emptyEl);
      }
    } else if (emptyEl) {
      emptyEl.remove();
      emptyEl = null;
    }
  }
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
    setEmpty(shown === 0);
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

/-- A quiet trailing count line that grounds the bottom of a short roll-up. -/
private def rollupCountLine (count : Nat) : Output.Html :=
  {{ <p class="bp_pm_page_count">{{.text true s!"{count} {if count == 1 then "entry" else "entries"}"}}</p> }}

/-- Body of an owner page: rollup cards + that owner's worklist items by bucket. -/
private def ownerBody (state : TraverseState) (owner : OwnerRollupItem)
    (items : List WorklistItem) : Output.Html := {{
  <div class="bp_worklist bp_pm_page">
    <header class="bp_node_page_header">
      <p class="bp_pm_page_back">
        <a href={{Informal.NodeRoute.worklistHref}}>"← Full worklist"</a>
      </p>
      <p class="bp_pm_page_eyebrow">"Owner"</p>
      <h1>{{.text true owner.displayName}}</h1>
    </header>
    {{rollupCards owner.totalEntries owner.actionableEntries owner.quickWins owner.linkedPrs}}
    {{renderWorklistBuckets state items}}
    {{rollupCountLine owner.totalEntries}}
  </div>
}}

/-- Body of a tag page: rollup cards + that tag's worklist items by bucket. -/
private def tagBody (state : TraverseState) (tag : TagRollupItem)
    (items : List WorklistItem) : Output.Html := {{
  <div class="bp_worklist bp_pm_page">
    <header class="bp_node_page_header">
      <p class="bp_pm_page_back">
        <a href={{Informal.NodeRoute.worklistHref}}>"← Full worklist"</a>
      </p>
      <p class="bp_pm_page_eyebrow">"Tag"</p>
      <h1>{{.text true tag.tag}}</h1>
    </header>
    {{rollupCards tag.totalEntries tag.actionableEntries tag.quickWins tag.linkedPrs}}
    {{renderWorklistBuckets state items}}
    {{rollupCountLine tag.totalEntries}}
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

/--
Write two slim machine-readable progress feeds into `-verso-data`:

* `progress.json` — a stable snapshot `{schemaVersion, total, coverageSplit,
  totalStatus, pct, commit}` for dashboards / CI;
* `progress-shields.json` — a Shields.io endpoint-badge payload
  `{schemaVersion, label, message, color}`.

Both are self-contained (no network). `commit` is read from the `GIT_COMMIT`
environment variable when present and degrades to the empty string otherwise, so
the writer never shells out and stays offline-safe.
-/
private def writeProgressFeeds (mode : Manual.Mode) (cfg : Manual.Config) (summary : Summary) :
    IO Unit := do
  let outDir := cfg.destination.join (match mode with | .single => "html-single" | .multi => "html-multi")
  let dataDir := outDir.join "-verso-data"
  IO.FS.createDirAll dataDir
  let total := summary.totalEntries
  let closed := summary.coverageSplit.fullyClosed
  let denom := Nat.max 1 total
  let pct := closed * 100 / denom
  let commit := (← IO.getEnv "GIT_COMMIT").getD ""
  let progress : Json := Json.mkObj [
    ("schemaVersion", toJson (1 : Nat)),
    ("total", toJson total),
    ("coverageSplit", toJson summary.coverageSplit),
    ("totalStatus", toJson summary.totalStatus),
    ("pct", toJson pct),
    ("commit", Json.str commit)
  ]
  IO.FS.writeFile (dataDir.join "progress.json") (progress.pretty ++ "\n")
  let shields : Json := Json.mkObj [
    ("schemaVersion", toJson (1 : Nat)),
    ("label", Json.str "formalized"),
    ("message", Json.str s!"{pct}%"),
    ("color", Json.str (badgeColor pct))
  ]
  IO.FS.writeFile (dataDir.join "progress-shields.json") (shields.pretty ++ "\n")

/-! ## Audit / technical-debt page -/

/--
Run a `SummaryHtmlM` rendering action to completion in plain `IO`.

Rebuilds the minimal HTML-emit context exactly like `emitStaticBlueprintPage`
(empty `AllRemotes`, default options, link targets that also surface Lean
const → blueprint-node cross-links), so the summary row renderers produce the
same markup they do inside the dashboard block.
-/
private def runSummaryHtml (state : TraverseState) {α : Type} (act : SummaryHtmlM α) : IO α := do
  let extensionImpls : ExtensionImpls := extension_impls%
  let logger ← Verso.Logger.new
  let remotes : Verso.Multi.AllRemotes := {}
  let ctxt : Manual.TraverseContext := {}
  let htmlCtx : Verso.Doc.Html.HtmlT.Context Manual := {
    options := {}
    traverseContext := ctxt
    traverseState := state
    definitionIds := state.definitionIds ctxt
    linkTargets :=
      state.localTargets ++ remotes.remoteTargets ++ Informal.NodeRoute.blueprintNodeTargets state
    -- No inline proof-state toggles in blueprint decl rendering (see PreviewRender /
    -- ExternalDeclRender); keeps summary-surface decl spans consistent + hoverable.
    codeOptions := { inlineProofStates := false }
  }
  let (a, _) ← (act.run htmlCtx).run {} |>.run remotes |>.run extensionImpls |>.run logger
  pure a

/--
`SummaryHtmlContext` for the audit page: entry references link to the entry's
dedicated node page (falling back to its chapter anchor), and decl references
resolve to their Lean source. Hover previews are intentionally disabled (no
preview panel ships on this page).
-/
private def auditHtmlContext (state : TraverseState) : SummaryHtmlContext := {
  entryHref? := fun label =>
    if Informal.NodeRoute.hasNodePage state label then
      some (Informal.NodeRoute.nodePageHref label)
    else
      Informal.TraversalIndex.Nodes.href? state label
  declHref? := fun label decl => Informal.Resolve.resolveInformalDeclHref? state label decl
  previewLookupKey? := fun _ => none
  displayLabel := fun label => Informal.NodeRoute.friendlyEntryLabel state label
  -- No preview runtime ships on the audit page, so decl spans must not carry the
  -- inline-preview hook (cursor + inert `data-bp-preview-*`); see STY-AUDIT-13.
  declPreviews := false
}

/--
Summary cards quantifying the outstanding technical debt. A non-zero count adopts
the warn variant so the row carries at-a-glance severity; a clean zero stays
neutral.
-/
private def auditSummaryCards (data : Summary) : Output.Html :=
  let debtCard (label : String) (count : Nat) (status : String) : Output.Html :=
    if count == 0 then
      summaryCard label (toString count) (some status)
    else
      summaryWarnCard label (toString count) (some status)
  {{
  <div class="bp_summary_grid">
    {{debtCard "Sorries" data.sorryDetails.length
        "Declarations whose proof still contains `sorry`."}}
    {{debtCard "Missing declarations" data.missingLeanDecls.length
        "Referenced Lean declarations absent from the environment."}}
    {{debtCard "Axiom-like entries" data.axiomIndex.length
        "Entries discharged by an axiom rather than a proof."}}
    {{debtCard "Render failures" data.renderFailures.length
        "External declarations that checked but failed HTML rendering."}}
    {{debtCard "Proof-debt hotspots" data.proofDebtHotspots.length
        "Parents accumulating the most incomplete or missing declarations."}}
  </div>
}}

/-- The build-time axiom-audit section of the audit page.

Distinct from the "Sorries" list above it: that list is the *authored* view (nodes
whose snapshot recorded a sorry), while this is the kernel's transitive verdict from
`Lean.collectAxioms` over every wired and project declaration — it catches a theorem
whose own body is clean but which invokes a sorried helper. Reads the audit findings
cached in the trust payload; renders nothing when no audit ran. -/
private def auditAxiomSection (state : TraverseState) : Output.Html :=
  let audit? : Option Informal.AxiomAudit.Summary := do
    let j ← Informal.TraversalIndex.TrustData.raw? state
    let trust ← (fromJson? (α := Informal.Commands.TrustData) j).toOption
    trust.audit?
  match audit? with
  | none => .empty
  | some a =>
    if !a.ran then .empty
    else
      let codeList := fun (names : Array String) =>
        Output.Html.seq (names.map fun n => {{ <li><code>{{.text true n}}</code></li> }})
      let sorriedBlock : Output.Html :=
        if a.sorried.isEmpty then .empty
        else {{
          <details class="bp_summary_subsection bp_summary_subsection_warn" open="open">
            <summary>{{Informal.NodeCard.withCodeSpans s!"Incomplete proofs — `sorryAx` in the closure ({a.sorried.size})"}}</summary>
            <ul class="bp_summary_list">{{codeList a.sorried}}</ul>
          </details> }}
      let nonstandardBlock : Output.Html :=
        if a.nonstandard.isEmpty then .empty
        else
          let rows := a.nonstandard.map fun d =>
            {{ <li><code>{{.text true d.name}}</code>" — "
                 {{.text true (String.intercalate ", " d.nonstandard.toList)}}</li> }}
          {{
            <details class="bp_summary_subsection bp_summary_subsection_warn" open="open">
              <summary>{{.text true s!"Nonstandard axioms ({a.nonstandard.size})"}}</summary>
              <ul class="bp_summary_list">{{Output.Html.seq rows}}</ul>
            </details> }}
      let clean : Output.Html :=
        if !a.sorried.isEmpty || !a.nonstandard.isEmpty then .empty
        else {{
          <p class="bp_summary_empty">
            {{Informal.NodeCard.withCodeSpans
              s!"`Lean.collectAxioms` over {a.checked} declarations found no `sorryAx` in any \
                 transitive closure and no axiom beyond propext, Classical.choice, and \
                 Quot.sound."}}
          </p> }}
      let axiomList : Output.Html :=
        if a.allAxioms.isEmpty then .empty
        else {{
          <p class="bp_summary_note">
            "Axioms used across the development: "
            {{.text true (String.intercalate ", " a.allAxioms.toList)}}"."
          </p> }}
      {{
        <section class="bp_audit_axioms">
          <h2>"Kernel axiom audit"</h2>
          <p class="bp_summary_note">
            {{Informal.NodeCard.withCodeSpans
              s!"Computed at build time with `Lean.collectAxioms` over {a.checked} declarations \
                 — every declaration a blueprint node wires plus every project declaration. \
                 Unlike the sorry list above, this is transitive: a theorem that invokes a \
                 sorried helper is reported even though its own body is clean."}}
          </p>
          {{clean}}
          {{sorriedBlock}}
          {{nonstandardBlock}}
          {{axiomList}}
        </section>
      }}

/-- Body of the audit / technical-debt page. -/
private def auditBody (state : TraverseState) (data : Summary) (rows : SummaryRows) : Output.Html :=
  let warnClass := "bp_summary_subsection bp_summary_subsection_warn"
  let nothing :=
    data.sorryDetails.isEmpty && data.missingLeanDecls.isEmpty && data.axiomIndex.isEmpty &&
      data.renderFailures.isEmpty && data.proofDebtHotspots.isEmpty
  {{
    <div class="bp_summary bp_pm_page bp_audit_page">
      <header class="bp_node_page_header">
        <h1>"Audit and technical debt"</h1>
        <p class="bp_pm_page_intro">
          "Every open obligation in the blueprint in one place: sorries, missing or \
           axiom-backed declarations, render failures, and the parents carrying the most \
           proof debt. Each row links to that entry's node page."
        </p>
      </header>
      {{auditSummaryCards data}}
      {{if nothing then
          {{<p class="bp_summary_empty">
              "No outstanding sorries, missing declarations, axiom-like entries, render \
               failures, or proof-debt hotspots."
            </p>}}
        else .empty}}
      {{summaryOptionalDetailsList (!rows.sorryRows.isEmpty)
          s!"Sorries ({data.sorryDetails.length})" rows.sorryRows warnClass true}}
      {{summaryOptionalDetailsList (!rows.missingRows.isEmpty)
          s!"Missing declarations ({data.missingLeanDecls.length})" rows.missingRows warnClass true}}
      {{summaryOptionalDetailsList (!rows.axiomRows.isEmpty)
          s!"Axiom-like entries ({data.axiomIndex.length})" rows.axiomRows warnClass true}}
      {{summaryOptionalDetailsList (!rows.proofDebtHotspotRows.isEmpty)
          s!"Proof-debt hotspots ({data.proofDebtHotspots.length})" rows.proofDebtHotspotRows warnClass true}}
      {{summaryOptionalDetailsList (!rows.renderFailureRows.isEmpty)
          s!"Render failures ({data.renderFailures.length})" rows.renderFailureRows warnClass true}}
      {{auditAxiomSection state}}
    </div>
  }}

/--
`ExtraStep` that emits a first-class audit / technical-debt page at
`audit/index.html` from the traversal-cached `Summary`.

Sibling to `emitBlueprintExtraPages`: it reads the same cached `Summary`, renders
the summary debt rows (sorries / missing decls / axioms / proof-debt hotspots /
render failures) with the shared row renderers, and writes a standalone page via
`emitStaticBlueprintPage`. Single-page mode is skipped; if no `Summary` was cached
it logs and skips gracefully.
-/
def emitBlueprintAuditPage : ExtraStep :=
  fun mode cfg state text => do
    match mode with
    | .single => pure ()
    | .multi =>
      let logger : Verso.Logger IO ← read
      match Informal.TraversalIndex.Summary.cachedSummary? state with
      | none =>
        logger.reportWarning
          "Showcase audit page: no cached Summary in traversal state; skipping \
           audit/index.html (is a `blueprint_dashboard` block present?)."
      | some summary =>
        let rows ← runSummaryHtml state (SummaryRows.render (auditHtmlContext state) summary)
        Informal.NodePage.emitStaticBlueprintPage mode cfg state text
          Informal.NodeRoute.auditPath "Audit and technical debt" (auditBody state summary rows)

/-! ## Mathlib upstream-candidates page -/

/--
Friendly display title for a node label, resolved from the traversal node index
(`displayTitle`, e.g. "Lemma 3.1"); falls back to the de-guillemeted raw label.
-/
private def candidateTitle (state : TraverseState) (label : Name) : String :=
  let raw :=
    match (Informal.TraversalIndex.Nodes.data? state label).map (·.displayTitle state) with
    | some t => if t.isEmpty then label.toString else t
    | none => label.toString
  Informal.NodeRoute.stripNameEscapes raw

/--
Human-readable chapter name for a node, derived from the chapter slug embedded in
its in-chapter href (`The-Local-Theorem/#…` → `The Local Theorem`). Degrades to
the empty string when no chapter href is known.
-/
private def candidateChapter (state : TraverseState) (label : Name) : String :=
  match Informal.TraversalIndex.Nodes.href? state label with
  | none => ""
  | some href => ((href.splitOn "/").headD "").replace "-" " "

/-- Inline styling for the Mathlib upstream-candidates list. -/
private def mathlibCandidatesCss : String := r##"
.bp_mathlib_candidates_list {
  list-style: none;
  margin: 1rem 0 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
}
.bp_mathlib_candidate {
  padding: 0.7rem 0.9rem;
  background: var(--bp-color-surface-muted, #f8fafc);
  border: 1px solid var(--bp-color-border, #cbd5e1);
  border-left: 3px solid var(--bp-color-status-mathlib, #6a4fba);
  border-radius: var(--bp-radius-md, 8px);
}
.bp_mathlib_candidate_top {
  display: flex;
  flex-wrap: wrap;
  gap: 0.3rem 0.7rem;
  align-items: baseline;
}
.bp_mathlib_candidate_title { font-weight: 600; }
.bp_mathlib_candidate_chapter {
  font-size: var(--bp-fs-control, 0.82rem);
  color: var(--bp-color-text-muted, #475569);
}
.bp_mathlib_candidate_decls {
  margin: 0.35rem 0 0;
  display: flex;
  flex-wrap: wrap;
  gap: 0.3rem 0.4rem;
}
.bp_mathlib_candidate_decls code {
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: 0.8rem;
  padding: 0.05rem 0.4rem;
  background: var(--bp-color-status-mathlib-surface, rgba(106, 79, 186, 0.12));
  border-radius: var(--bp-radius-sm, 4px);
}
"##

/-- One candidate row: title (node-page link), chapter, and the Mathlib decl(s). -/
private def mathlibCandidateRow (state : TraverseState) (item : MathlibCandidateItem) :
    Output.Html :=
  let title := candidateTitle state item.label
  let chapter := candidateChapter state item.label
  let titleNode : Output.Html :=
    if Informal.NodeRoute.hasNodePage state item.label then
      {{ <a class="bp_mathlib_candidate_title"
            href={{Informal.NodeRoute.nodePageHref item.label}}>{{withIdentifierBreaks title}}</a> }}
    else
      {{ <span class="bp_mathlib_candidate_title">{{withIdentifierBreaks title}}</span> }}
  let chapterNode : Output.Html :=
    if chapter.isEmpty then .empty
    else {{ <span class="bp_mathlib_candidate_chapter">{{.text true s!"in {chapter}"}}</span> }}
  let kindNode : Output.Html :=
    if item.kind.isEmpty then .empty
    else {{ <span class="bp_mathlib_candidate_chapter">{{.text true s!"({item.kind})"}}</span> }}
  let declNodes : Array Output.Html :=
    item.mathlibDecls.toArray.map fun d => {{ <code>{{.text true d.toString}}</code> }}
  {{
    <li class="bp_mathlib_candidate">
      <div class="bp_mathlib_candidate_top">
        {{titleNode}}
        {{kindNode}}
        {{chapterNode}}
      </div>
      {{if declNodes.isEmpty then .empty
        else {{ <div class="bp_mathlib_candidate_decls">"Now in Mathlib: " {{declNodes}}</div> }}}}
    </li>
  }}

/-- Body of the Mathlib upstream-candidates page. -/
private def mathlibCandidatesBody (state : TraverseState) (summary : Summary) : Output.Html :=
  let items := summary.mathlibCandidates
  let rows := items.toArray.map (mathlibCandidateRow state)
  {{
    <div class="bp_mathlib_candidates bp_pm_page">
      <style>{{.text false mathlibCandidatesCss}}</style>
      <header class="bp_node_page_header">
        <h1>"Mathlib upstream candidates"</h1>
        <p class="bp_pm_page_intro">
          {{.text true s!"{items.length} blueprint {if items.length == 1 then "entry is" else "entries are"} now formalized in Mathlib. Each could be dropped from this project and replaced with the upstream Mathlib declaration."}}
        </p>
      </header>
      {{if items.isEmpty then
          {{<p class="bp_summary_empty">"No upstream candidates yet — no blueprint entry currently resolves entirely to Mathlib."</p>}}
        else
          {{<ul class="bp_mathlib_candidates_list">{{rows}}</ul>}}}}
    </div>
  }}

/--
`ExtraStep` that emits the Mathlib upstream-candidates page at
`mathlib-candidates/index.html` from the traversal-cached `Summary`.

Sibling to `emitBlueprintAuditPage`. The page is always emitted (with an
empty-state when there are no candidates). Single-page mode is skipped; if no
`Summary` was cached it logs and skips gracefully.
-/
def emitBlueprintMathlibCandidatesPage : ExtraStep :=
  fun mode cfg state text => do
    match mode with
    | .single => pure ()
    | .multi =>
      let logger : Verso.Logger IO ← read
      match Informal.TraversalIndex.Summary.cachedSummary? state with
      | none =>
        logger.reportWarning
          "Showcase Mathlib candidates page: no cached Summary in traversal state; skipping \
           mathlib-candidates/index.html (is a `blueprint_dashboard` block present?)."
      | some summary =>
        Informal.NodePage.emitStaticBlueprintPage mode cfg state text
          Informal.NodeRoute.mathlibCandidatesPath "Mathlib upstream candidates"
          (mathlibCandidatesBody state summary)

/-! ## Project-management (PM) hub page

The landing page is minimal (title / authors / trust strip / featured cards); the PM
hub is where the orienting overview lives: the overall progress hero, the guided
reading map, a compact hub of links to every project-management and catalog surface
(worklist / audit / candidates / modules / index / showcase summary / formalization
metadata), the next actionable tasks, per-chapter progress, the dependency-depth
histogram, and a collapsed build-provenance footer. The full per-entry summary, the
owner/tag rollups, and the coverage-split status cards are NOT duplicated here — they
live on their own standalone pages, reached via the hub links. Reuses the shared
dashboard render helpers so it themes and enhances (d3 charts) like the old
dashboard. -/

/-- Inline styling for the PM hub page: section spacing, link row, and the
dependency-depth histogram. Token-driven, so light/dark parity is inherited. -/
private def pmPageCss : String := r##"
.bp_pm_section { margin-top: var(--bp-space-6); }
.bp_pm_section_title { margin-bottom: var(--bp-space-2); }
.bp_pm_section_intro {
  margin: 0 0 var(--bp-space-4);
  color: var(--bp-color-text-muted);
  font-size: var(--bp-fs-small);
}
.bp_pm_frontier {
  margin: var(--bp-space-4) 0 0;
  color: var(--bp-color-text-muted);
  font-size: var(--bp-fs-small);
}
.bp_pm_subhead {
  margin: var(--bp-space-5) 0 var(--bp-space-2);
  font-size: var(--bp-fs-caption);
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--bp-color-text-subtle);
}
.bp_pm_links {
  margin: var(--bp-space-4) 0 0;
  display: flex;
  flex-wrap: wrap;
  gap: var(--bp-space-2) var(--bp-space-4);
  font-size: var(--bp-fs-small);
}
.bp_pm_links a { color: var(--bp-color-link); text-decoration: none; font-weight: 600; }
.bp_pm_links a:hover, .bp_pm_links a:focus-visible { text-decoration: underline; }
.bp_pm_hist { display: flex; flex-direction: column; gap: var(--bp-space-2); margin-top: var(--bp-space-3); }
.bp_pm_hist_row {
  display: grid;
  grid-template-columns: 4.5rem 1fr 2.5rem;
  align-items: center;
  gap: var(--bp-space-3);
  font-size: var(--bp-fs-small);
}
.bp_pm_hist_label { color: var(--bp-color-text-muted); font-variant-numeric: tabular-nums; }
.bp_pm_hist_track {
  height: 0.7rem;
  border-radius: var(--bp-radius-pill);
  background: var(--bp-color-surface-muted);
  border: 1px solid var(--bp-color-border-soft);
  overflow: hidden;
}
.bp_pm_hist_bar { display: block; height: 100%; background: var(--bp-color-status-ready); }
.bp_pm_hist_count { text-align: right; color: var(--bp-color-text-subtle); font-variant-numeric: tabular-nums; }
.bp_pm_build_details { margin-top: var(--bp-space-6); }
.bp_pm_build_details > summary {
  cursor: pointer;
  color: var(--bp-color-text-subtle);
  font-size: var(--bp-fs-small);
  font-weight: 600;
}
"##

/-- Whether a statement comparator is configured (from the cached trust-strip payload),
so the PM hub should link to the `comparator/` page. Reads the raw cached JSON to avoid
an import dependency on the trust-strip module. -/
private def comparatorConfigured (state : TraverseState) : Bool :=
  match Informal.TraversalIndex.TrustData.raw? state with
  | some j =>
    match j.getObjVal? "comparator" with
    | .ok Json.null => false
    | .ok _ => true
    | .error _ => false
  | none => false

/-- The PM hub's navigation row: quiet links to every project-management and catalog
surface. The Showcase Summary, Trust model, Formalization Metadata, and Statement
Comparator links are omitted when the document carries no such page (their traversal
anchors / trust payload resolve to `none`), so an unconfigured consumer degrades
gracefully rather than dead-linking. -/
private def pmHubLinks (state : TraverseState) : Output.Html :=
  -- The proof overview leads: it is the one page that says what the argument *is*
  -- before the reader meets any of its parts. Omitted when the document declares no
  -- milestones, like every other conditional link here.
  let overviewLink : Output.Html :=
    match Informal.TraversalIndex.OverviewPage.href? state with
    | some href => {{ <a href={{href}}>"Proof overview"</a> }}
    | none => .empty
  let summaryLink : Output.Html :=
    match Informal.TraversalIndex.SummaryPage.href? state with
    | some href => {{ <a href={{href}}>"Showcase summary"</a> }}
    | none => .empty
  let formalizationLink : Output.Html :=
    match Informal.TraversalIndex.FormalizationPage.href? state with
    | some href => {{ <a href={{href}}>"Formalization metadata"</a> }}
    | none => .empty
  let trustModelLink : Output.Html :=
    match Informal.TraversalIndex.TrustModelPage.href? state with
    | some href => {{ <a href={{href}}>"Trust model"</a> }}
    | none => .empty
  let comparatorLink : Output.Html :=
    if comparatorConfigured state then
      {{ <a href={{Informal.NodeRoute.comparatorHref}}>"Statement comparator"</a> }}
    else .empty
  {{
    <nav class="bp_pm_links" "aria-label"="Showcase sections">
      {{overviewLink}}
      <a href={{Informal.NodeRoute.defsHref}}>"Definitions"</a>
      <a href={{Informal.NodeRoute.theoremsHref}}>"Theorems"</a>
      <a href={{Informal.NodeRoute.worklistHref}}>"Worklist"</a>
      <a href={{Informal.NodeRoute.auditHref}}>"Audit & technical debt"</a>
      <a href={{Informal.NodeRoute.mathlibCandidatesHref}}>"Mathlib upstream candidates"</a>
      <a href={{Informal.NodeRoute.modulesHref}}>"Modules"</a>
      <a href={{Informal.NodeRoute.declIndexHref}}>"Index"</a>
      {{comparatorLink}}
      {{trustModelLink}}
      {{summaryLink}}
      {{formalizationLink}}
    </nav>
  }}

/-- One sentence per rule stating what the per-declaration-page policy excluded and what
the scale cap dropped, under the hub links they qualify — the catalog pages those links
point at are the surfaces where a reader meets a declaration with no page of its own.

`.empty` for a rule that took nothing away: a site emitting a page for every unwired
declaration says nothing, because there is nothing to disclose. -/
private def pmDeclPageCapNote (state : TraverseState) : Output.Html :=
  let policyNote : Output.Html :=
    match Informal.TraversalIndex.DeclRegistry.declPagePolicy? state with
    | none => .empty
    | some raw =>
      match (FromJson.fromJson? raw : Except String Informal.DeclRegistry.PagePolicy) with
      | .error _ => .empty
      | .ok policy =>
        {{
          <p class="bp_pm_section_intro">
            {{.text true s!"Declaration pages: {policy.instancesExcluded} instances and \
              {policy.privateExcluded} private declarations have no page of their own by \
              policy; they are still enumerated, audited and listed in the index and the \
              module tree."}}
          </p>
        }}
  let capNote : Output.Html :=
    match Informal.TraversalIndex.DeclRegistry.declPageCap? state with
    | none => .empty
    | some raw =>
      match (FromJson.fromJson? raw : Except String Informal.DeclRegistry.PageCap) with
      | .error _ => .empty
      | .ok cap =>
        {{
          <p class="bp_pm_section_intro">
            {{.text true s!"Declaration pages: {cap.emitted} of the {cap.candidates} \
              declarations this blueprint does not present as nodes; the other \
              {cap.omitted} are indexed without a page of their own \
              (verso.blueprint.declRegistry.maxDeclPages = {cap.limit})."}}
          </p>
        }}
  .seq #[policyNote, capNote]

/-- The next few actionable ("ready") worklist items as a compact preview; empty when
nothing is ready. The worklist page carries the full, filterable list. -/
private def pmSuggestedTasks (state : TraverseState) (summary : Summary) : Output.Html :=
  let ready := (summary.worklist.filter (fun i => i.readiness == "ready")).take 5
  if ready.isEmpty then .empty
  else {{
    <section class="bp_pm_section">
      <h2 class="bp_pm_section_title">"Suggested next tasks"</h2>
      <p class="bp_pm_section_intro">
        "The next actionable entries — all prerequisites satisfied. The worklist page \
         carries the full, filterable list."
      </p>
      <ul class="bp_summary_list">{{ready.toArray.map (worklistRow state)}}</ul>
    </section>
  }}

/-- The dependency-depth distribution histogram, computed from the master graph's
`GraphMetrics`. Server-rendered (no new client deps); empty when the graph has no
nodes. -/
private def pmDepthHistogram (state : TraverseState) : Output.Html :=
  let master := Informal.GraphApi.masterGraph state
  let metrics := Informal.GraphMetrics.computeGraphMetrics master
  if metrics.nodes.isEmpty then .empty
  else
    let depths := metrics.nodes.map (·.depth)
    let maxDepth := depths.foldl Nat.max 0
    let maxCount :=
      ((Array.range (maxDepth + 1)).map (fun d => (depths.filter (· == d)).size)).foldl Nat.max 1
    let histRows := (Array.range (maxDepth + 1)).map fun d =>
      let cnt := (depths.filter (· == d)).size
      let pct := cnt * 100 / maxCount
      {{ <div class="bp_pm_hist_row">
          <span class="bp_pm_hist_label">{{.text true s!"depth {d}"}}</span>
          <span class="bp_pm_hist_track">
            <span class="bp_pm_hist_bar" "style"={{s!"width:{pct}%"}}></span>
          </span>
          <span class="bp_pm_hist_count">{{.text true (toString cnt)}}</span>
        </div> }}
    {{
      <section class="bp_pm_section">
        <h2 class="bp_pm_section_title">"Dependency-depth distribution"</h2>
        <p class="bp_pm_section_intro">
          "How deep the dependency graph runs — the number of entries at each \
           longest-path depth."
        </p>
        <div class="bp_pm_hist">{{histRows}}</div>
      </section>
    }}

/-- Body of the PM hub page: overall progress hero, the guided reading map, a hub of
quick links to every section, the next actionable tasks, per-chapter progress, the
dependency-depth histogram, and a collapsed build-provenance footer — plus the offline
`bp-dashboard-data` JSON that feeds the chart mounts. The full per-entry summary now
lives on its own standalone Showcase Summary page, linked from the hub. -/
private def pmBody (state : TraverseState) (summary : Summary)
    (metadata : Informal.PreviewManifest.BuildMetadata) : Output.Html :=
  -- Resolve a short chapter title for each group's per-chapter progress bar from a
  -- representative child's in-chapter href (the group `header` is a long
  -- descriptive sentence, unusable as a bar label). Leaves `title` empty when
  -- unresolvable so the fallback (`header`) applies, and clears the transient
  -- `chapterLabel?` so it never bloats the emitted chart JSON.
  let summary := { summary with
    groupHealth := summary.groupHealth.map fun g =>
      let title := match g.chapterLabel? with
        | some l => candidateChapter state l
        | none => ""
      { g with title, chapterLabel? := none } }
  -- Escape `</script>`-style breakouts in author-supplied strings before embedding
  -- the chart JSON verbatim (mirrors the old dashboard block).
  let chartJson : String :=
    escapeJsonForScriptEmbed (Lean.Json.compress (toJson summary.chartData))
  {{
    <div class="bp_pm_page bp_pm_hub">
      <style>{{.text false pmPageCss}}</style>
      <header class="bp_node_page_header">
        <h1>"Project management"</h1>
        <p class="bp_pm_page_intro">
          "This blueprint's status in one place: overall formalization progress, a \
           guided reading map, quick links to every section, the next actionable \
           tasks, per-chapter progress, and how deep the dependency graph runs."
        </p>
      </header>
      <section class="bp_pm_section">
        {{dashboardHero summary}}
      </section>
      {{dashboardReadingMap state}}
      {{pmHubLinks state}}
      {{pmDeclPageCapNote state}}
      {{pmSuggestedTasks state summary}}
      <section class="bp_pm_section">
        <div class="bp_dashboard_charts">
          {{dashboardChartMount "chapters" "Per-chapter progress" true (dashboardChaptersFallback summary)}}
        </div>
      </section>
      {{pmDepthHistogram state}}
      <details class="bp_dashboard_detail bp_pm_build_details">
        <summary>"Build provenance"</summary>
        {{Informal.PreviewManifest.buildMetadataHtml metadata}}
      </details>
      <script type="application/json" class="bp-dashboard-data">
        {{.text false chartJson}}
      </script>
    </div>
  }}

/--
`ExtraStep` that emits the project-management hub page at `pm/index.html` from the
traversal-cached `Summary` (and `readBuildMetadata` for the build-provenance block).

Sibling to `emitBlueprintAuditPage`. Single-page mode is skipped; if no `Summary` was
cached it logs and skips gracefully.
-/
def emitBlueprintPmPage : ExtraStep :=
  fun mode cfg state text => do
    match mode with
    | .single => pure ()
    | .multi =>
      let logger : Verso.Logger IO ← read
      match Informal.TraversalIndex.Summary.cachedSummary? state with
      | none =>
        logger.reportWarning
          "Showcase PM page: no cached Summary in traversal state; skipping \
           pm/index.html (is a `blueprint_dashboard` block present?)."
      | some summary =>
        let metadata ← Informal.PreviewManifest.readBuildMetadata
        Informal.NodePage.emitStaticBlueprintPage mode cfg state text
          Informal.NodeRoute.pmPath "Project management" (pmBody state summary metadata)

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
          "Showcase extra pages: no cached Summary in traversal state; skipping \
           worklist/owner/tag pages and progress badge (is a `blueprint_dashboard` block present?)."
      | some summary =>
        -- Worklist (filterable; full server-rendered list).
        Informal.NodePage.emitStaticBlueprintPage mode cfg state text
          Informal.NodeRoute.worklistPath "Worklist" (worklistBody state summary)
        -- One page per owner rollup, filtered to that owner's worklist items.
        -- Guard against two distinct owners that sluggify to the same slug
        -- silently overwriting each other's page (mirrors the node-slug guard in
        -- `NodePage.emitBlueprintNodePages`).
        let mut seenOwnerSlugs : Std.HashSet String := {}
        for owner in summary.ownerRollups do
          let slug := Informal.NodeRoute.ownerPageSlug owner.owner
          if seenOwnerSlugs.contains slug then
            logger.reportWarning <|
              s!"Showcase owner pages: slug collision for owner {owner.owner} (slug {slug}); " ++
              "this owner page may overwrite another owner's page"
          seenOwnerSlugs := seenOwnerSlugs.insert slug
          let items := summary.worklist.filter (fun i => i.ownerDisplayName == some owner.displayName)
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            (Informal.NodeRoute.ownerPagePath owner.owner)
            s!"Owner: {owner.displayName}" (ownerBody state owner items)
        -- One page per tag rollup, filtered to that tag's worklist items.
        -- Same slug-collision guard as the owner pages above.
        let mut seenTagSlugs : Std.HashSet String := {}
        for tag in summary.tagRollups do
          let slug := Informal.NodeRoute.tagPageSlug tag.tag
          if seenTagSlugs.contains slug then
            logger.reportWarning <|
              s!"Showcase tag pages: slug collision for tag {tag.tag} (slug {slug}); " ++
              "this tag page may overwrite another tag's page"
          seenTagSlugs := seenTagSlugs.insert slug
          let items := summary.worklist.filter (fun i => i.tags.contains tag.tag)
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            (Informal.NodeRoute.tagPagePath tag.tag)
            s!"Tag: {tag.tag}" (tagBody state tag items)
        -- README progress badge + machine-readable progress feeds.
        writeProgressBadge mode cfg summary
        writeProgressFeeds mode cfg summary

end Informal.ExtraPages
