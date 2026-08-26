/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import Verso.Output.Html
import VersoBlueprint.JunkValues
import VersoBlueprint.NodeCard

/-!
"Known caveat patterns" — the reader-facing half of the caveat scan.

One renderer, two surfaces: the comparator page's certified panels and the declaration
pages. They differ in heading level and in what their scan covered, and in nothing else,
because the sentence a reader needs is the same sentence in both places.

What the copy may say is decided entirely by the report's status, and the five statuses say
five different things:

- **completed-zero** — the table was consulted and matched nothing. The sentence names the
  table's version and digest and then says, in as many words, that this is not evidence
  that no caveat applies. A silent absence here would read as a clean bill.
- **completed-with-hits** — rows, and the same non-exhaustiveness sentence underneath them,
  so the list never reads as the complete list.
- **partial** — the walk was capped. Whatever was found is a lower bound and is phrased as
  one; nothing beyond the cap was examined.
- **unavailable** — the scan could not run, and the reason is printed.
- **disabled** — the scan was switched off. Reachable only at the subprocess boundary, where
  a job carrying no table is told so rather than served an empty result.

Two things this surface never does. It never calls a hit a defect: the fixed lead sentence
is the first thing on the block and it says so. And it never says a statement is *guarded* —
the guard scan is a presence check over binder heads, it relates nothing to the flagged
operand, and each of the three guard sentences below says what it actually established.
-/

namespace Informal.CaveatsRender

open Verso.Output
open Verso.Output.Html
open Informal.JunkValues

/-! ## Copy -/

/-- The fixed lead. Every rendering of this block opens with it. -/
def headerCopy : String :=
  "Caveats to check, not findings of error: these symbols have total-function conventions a \
   reader can misread."

/-- The section heading. -/
def sectionTitle : String := "Known caveat patterns"

private def plural (n : Nat) (one many : String) : String := if n == 1 then one else many

/-- The sentence that keeps a zero-match scan from reading as a clean bill. -/
def completedZeroCopy (version digest : String) : String :=
  s!"No matches in the configured partial table (version {version}, digest {digest}); this \
     is not evidence that no total-function caveat applies."

/-- The same point, under a list of hits: the list is what one partial table knows. -/
def partialTableCopy (version digest : String) : String :=
  s!"The table is partial (version {version}, digest {digest}): a symbol it does not list is \
     a symbol nobody looked for."

/-- What the walk actually looked at, in the engine's own words. -/
private def coverageCopy (coverage : String) : String :=
  if coverage.isEmpty then "" else s!"Scanned: {coverage}."

/-- The three guard sentences. None of them says "guarded". -/
def guardCopy (guard hint : String) : String :=
  if guard == guardCandidatePresent then
    "A guard-shaped hypothesis occurs; this presence scan did not relate it to the flagged \
     operand."
  else if guard == guardNotDetected then
    let base :=
      "No hypothesis of the guarding shape was detected. This is a presence check: the \
       statement may be guarded another way, or may not need a guard."
    if hint.isEmpty then base else s!"{base} A guard would look like: {hint}"
  else
    "No guard shape is recorded for this symbol, so nothing was looked for."

/-- Where the match happened, for a reader who wants to go and look. -/
private def findingProvenance (f : Finding) : String :=
  let where_ :=
    if f.matchedVia == f.symbol then s!"Matched as `{f.symbol}`"
    else s!"Matched through `{f.matchedVia}`"
  let place :=
    if f.origin.isEmpty then ""
    else s!" in {f.origin}, {f.depth} {plural f.depth "edge" "edges"} from the statement"
  let table :=
    if f.provenance.isEmpty then "" else s!" Table entry provenance: {f.provenance}."
  s!"{where_}{place}.{table}"

/-! ## Markup -/

private def noteP (text : String) : Html :=
  if text.isEmpty then .empty else {{ <p class="bp_caveats_note">{{.text true text}}</p> }}

/-- Backtick spans become `<code>`, matching every other prose surface on the trust pages:
these sentences are about Lean names, and rendering them as literal backticks would be the
one place on the site that does not. -/
private def prose (text : String) : Html := Informal.NodeCard.withCodeSpans text

private def findingRow (f : Finding) : Html :=
  {{
    <li class="bp_caveats_row">
      <code class="bp_caveats_symbol">{{.text true f.symbol}}</code>
      <p class="bp_caveats_behavior">{{prose f.behavior}}</p>
      <p class="bp_caveats_guard" "data-guard"={{f.guard}}>
        {{prose (guardCopy f.guard f.guardHint)}}
      </p>
      <p class="bp_caveats_provenance">{{prose (findingProvenance f)}}</p>
    </li>
  }}

private def findingList (hits : Array Finding) : Html :=
  if hits.isEmpty then .empty
  else {{ <ul class="bp_caveats_list">{{.seq (hits.map findingRow)}}</ul> }}

/-- The `set_option` subsection. Rendered whenever an option scan ran, including when it
found nothing — "we looked and found none" and "we did not look" are different facts. -/
private def optionSection (r : ScanReport) : Html :=
  if r.optionScanFiles.isEmpty then .empty
  else
    let allowlist := String.intercalate ", " trustRelevantOptions.toList
    let files := String.intercalate ", " r.optionScanFiles.toList
    let n := r.optionOverrides.size
    let body : Html :=
      if r.optionOverrides.isEmpty then
        {{ <p class="bp_caveats_behavior">{{.text true
             s!"No configuration override was found in the \
                {r.optionScanFiles.size} chain \
                {plural r.optionScanFiles.size "file" "files"} scanned."}}</p> }}
      else
        .seq #[
          {{ <p class="bp_caveats_behavior">{{.text true
               s!"Configuration override present: the chain sets {n} of the options this site \
                  reports on. An override is a configuration fact, not a finding of \
                  error."}}</p> }},
          {{ <ul class="bp_caveats_options_list">
               {{.seq (r.optionOverrides.map fun o =>
                 {{
                   <li class="bp_caveats_option">
                     <code class="bp_caveats_symbol">{{.text true o.option}}</code>
                     <code class="bp_caveats_option_value">{{.text true o.value}}</code>
                     <span class="bp_caveats_option_where">{{.text true
                       s!"{o.file}:{o.line}:{o.column} · {o.scope} scope"}}</span>
                   </li>
                 }})}}
             </ul> }}]
    {{
      <section class="bp_caveats_options">
        <h4 class="bp_caveats_subtitle">"Configuration overrides"</h4>
        {{body}}
        {{noteP s!"Files scanned: {files}. Options reported: {allowlist}. An option outside \
          that list was not looked for."}}
      </section>
    }}

/-- The body of the block for one report: everything under the heading. -/
def body (r : ScanReport) : Html :=
  let version := r.tableVersion
  let digest := r.tableDigest
  let lead : Html := {{ <p class="bp_caveats_lead">{{.text true headerCopy}}</p> }}
  if r.status == statusUnavailable then
    .seq #[{{ <p class="bp_caveats_behavior">{{.text true
      s!"No caveat scan is available here{if r.reason.isEmpty then "." else s!": {r.reason}."}"
      }}</p> }}]
  else if r.status == statusDisabled then
    .seq #[{{ <p class="bp_caveats_behavior">{{.text true
      s!"The caveat scan is switched off for this site, so no symbols were looked \
         for{if r.reason.isEmpty then "." else s!" ({r.reason})."}"}}</p> }}]
  else if r.status == statusCompletedZero then
    .seq #[lead,
      {{ <p class="bp_caveats_behavior">{{.text true (completedZeroCopy version digest)}}</p> }},
      noteP (coverageCopy r.coverage),
      optionSection r]
  else if r.status != statusPartial && r.status != statusCompletedWithHits then
    -- A report from a newer schema than this build reads. Naming the state and stopping is
    -- the only honest option: guessing which of the five it resembles would put a sentence
    -- under a verdict this build cannot read.
    {{ <p class="bp_caveats_behavior">{{.text true
         s!"This build does not recognize the caveat-scan state '{r.status}' recorded here, so \
            it reports nothing about it."}}</p> }}
  else
    let n := r.hits.size
    let headline :=
      if r.status == statusPartial then
        s!"The walk reached this site's configured cap before finishing, so this is a lower \
           bound: {n} {plural n "match" "matches"} among the declarations that were reached. \
           Symbols beyond the cap were not examined."
      else
        s!"{n} {plural n "symbol" "symbols"} in the configured table {plural n "occurs" "occur"} \
           in what this statement means."
    .seq #[lead,
      {{ <p class="bp_caveats_behavior">{{.text true headline}}</p> }},
      findingList r.hits,
      noteP (partialTableCopy version digest),
      noteP (coverageCopy r.coverage),
      optionSection r]

/--
The whole block, heading included, or `.empty`.

`none` is the not-scanned state — a registry entry from before this feature, or a build with
the surface switched off — and renders nothing at all, so a page without the feature is the
page it was before. `headingTag` is the surface's, since this block is a subsection of a
comparator panel and a top-level section of a declaration page.
-/
def render (r? : Option ScanReport) (headingTag : String := "h3") : Html :=
  match r? with
  | none => .empty
  | some r =>
    if r.status.isEmpty then .empty
    else
      let heading := Html.tag headingTag #[("class", "bp_caveats_title")] (.text true sectionTitle)
      {{ <section class="bp_caveats">{{heading}}{{body r}}</section> }}

/-! ## Consumer-declared characterizations -/

/--
The characterizations a consumer declared, labelled as theirs.

Rendered as one project-level section rather than repeated per claim: a sidecar is a
statement about the project's declarations, not about one verdict. The file it came from and
the digest of the bytes read are printed, because "consumer-declared" is only a useful label
if a reader can find the file that declared it.
-/
def characterizationsBody (cs : Characterizations)
    (siteHref : String → Option String := fun _ => none) : Html :=
  if cs.entries.isEmpty then .empty
  else
    let row := fun (c : Characterization) =>
      let name : Html := {{ <code class="bp_caveats_symbol">{{.text true c.decl}}</code> }}
      let linked : Html :=
        match siteHref c.decl with
        | some href => {{ <a class="bp_caveats_link" href={{href}}>{{name}}</a> }}
        | none => name
      let reference : Html :=
        if c.reference.isEmpty then .empty
        else {{ <p class="bp_caveats_provenance">{{prose
             s!"Established by: `{c.reference}`."}}</p> }}
      let note : Html :=
        if c.note.isEmpty then .empty
        else {{ <p class="bp_caveats_provenance">{{prose c.note}}</p> }}
      {{
        <li class="bp_caveats_row">
          {{linked}}
          <p class="bp_caveats_behavior">{{prose c.statement}}</p>
          {{reference}}
          {{note}}
        </li>
      }}
    .seq #[
        {{ <p class="bp_caveats_lead">
          "Consumer-declared characterization: each row is the project's own statement of what "
          "one of its definitions is pinned down by. Nothing here was checked by this site or "
          "by the verifier — the correspondence between a definition and the property claimed "
          "to characterize it is exactly the kind of claim a reader has to check."
        </p> }},
        {{ <ul class="bp_caveats_list">{{.seq (cs.entries.map row)}}</ul> }},
        noteP s!"Declared in {cs.path} (digest {cs.digest})."]

/-! ## Styling

Design tokens only, so both themes come for free. The block reuses the trust surfaces'
register: quiet hairline rows, a monospace symbol chip, muted provenance text. The guard
line is deliberately **not** colour-coded by state — colouring `candidate-present` green
would be the visual form of the sentence this surface refuses to write.
-/

def css : String := r##"
.bp_caveats {
  margin-top: var(--bp-space-5);
}

/* Inside a trust-page section the heading is the section's own, so the block starts
   flush. */
.bp_trust_section > .bp_caveats {
  margin-top: 0;
}

.bp_caveats_title {
  margin: 0 0 var(--bp-space-2);
  font-size: var(--bp-fs-small, 0.875rem);
  font-weight: 600;
  color: var(--bp-color-text-strong);
}

.bp_caveats_subtitle {
  margin: 0 0 var(--bp-space-2);
  font-size: var(--bp-fs-caption, 0.78rem);
  font-weight: 600;
  color: var(--bp-color-text-faint);
}

.bp_caveats_lead {
  margin: 0 0 var(--bp-space-3);
  font-size: var(--bp-fs-caption, 0.78rem);
  line-height: 1.6;
  color: var(--bp-color-text-muted);
}

.bp_caveats_behavior {
  margin: 0 0 var(--bp-space-2);
  font-size: var(--bp-fs-caption, 0.78rem);
  line-height: 1.6;
  color: var(--bp-color-text);
}

.bp_caveats_note {
  margin: var(--bp-space-2) 0 0;
  font-size: var(--bp-fs-badge, 0.72rem);
  line-height: 1.6;
  color: var(--bp-color-text-faint);
}

.bp_caveats_list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--bp-space-3);
}

.bp_caveats_row {
  padding: var(--bp-space-3);
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-md);
  background: var(--bp-color-surface-subtle);
}

.bp_caveats_symbol {
  display: inline-block;
  margin-bottom: var(--bp-space-2);
  padding: 0.05rem var(--bp-space-2);
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-pill);
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: var(--bp-fs-badge, 0.72rem);
  color: var(--bp-color-text-strong);
  overflow-wrap: anywhere;
}

.bp_caveats_link {
  text-decoration: none;
}

.bp_caveats_link:hover .bp_caveats_symbol {
  border-color: var(--bp-color-border-strong);
}

/* Deliberately one colour for all three guard states: a presence check is not a verdict,
   and a green line would say what the sentence refuses to. */
.bp_caveats_guard,
.bp_caveats_provenance {
  margin: 0;
  font-size: var(--bp-fs-badge, 0.72rem);
  line-height: 1.6;
  color: var(--bp-color-text-faint);
}

.bp_caveats_guard {
  margin-bottom: var(--bp-space-1);
}

.bp_caveats_behavior code,
.bp_caveats_guard code,
.bp_caveats_provenance code,
.bp_caveats_note code {
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  font-size: 0.95em;
  color: var(--bp-color-text-strong);
}

.bp_caveats_options {
  margin-top: var(--bp-space-4);
}

.bp_caveats_options_list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--bp-space-1);
}

.bp_caveats_option {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: var(--bp-space-2);
  font-size: var(--bp-fs-caption, 0.78rem);
}

.bp_caveats_option .bp_caveats_symbol {
  margin-bottom: 0;
}

.bp_caveats_option_value {
  font-family: var(--font-mono-ui, ui-monospace, "SF Mono", Menlo, Consolas, monospace);
  color: var(--bp-color-text-muted);
}

.bp_caveats_option_where {
  color: var(--bp-color-text-faint);
  font-size: var(--bp-fs-badge, 0.72rem);
}
"##

end Informal.CaveatsRender
