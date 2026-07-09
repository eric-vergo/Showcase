/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.NodePage
import VersoBlueprint.TraversalIndex
import VersoBlueprint.Commands.TrustStrip

/-!
Trust-evidence pages.

Each dashboard trust badge (sorries / axioms / review / comparator) links to a
generated evidence page under `trust/`. `emitBlueprintTrustPages` is the
generation-time `ExtraStep` that materialises those pages: it reads the
trust-strip payload cached during traversal (`TraversalIndex.TrustData`, saved by
`Block.trustStrip`'s traverse), and emits one page per **configured** badge, each
spelling out (a) what the badge means, (b) the concrete evidence drawn from the
configured artifacts (`formalization.yaml` + comparator status), and (c) how a
skeptic can reproduce the check themselves.

It degrades exactly like the other extra-page steps: single-page mode is skipped,
and when no trust data was cached (no `verso.blueprint.trust.*` option was
configured) it emits nothing at all.
-/

namespace Informal.Commands

open Lean
open Verso Verso.Output Verso.Doc
open Verso.Genre Manual
open Verso.Output.Html

/-- Standard page shell for a trust-evidence page: the reset content header plus a
lead paragraph, followed by the page-specific evidence body. -/
private def trustPageShell (heading intro : String) (body : Output.Html) : Output.Html :=
  {{
    <div class="bp_summary bp_pm_page bp_trust_page">
      <header class="bp_node_page_header">
        <h1>{{.text true heading}}</h1>
        <p class="bp_pm_page_intro">{{.text true intro}}</p>
      </header>
      {{body}}
    </div>
  }}

/-- One titled evidence/how-to section. -/
private def trustSection (title : String) (body : Output.Html) : Output.Html :=
  {{
    <section class="bp_trust_section">
      <h2 class="bp_trust_section_title">{{.text true title}}</h2>
      {{body}}
    </section>
  }}

/-- A `<ul>` of `<code>`-wrapped names (axioms / theorem names). -/
private def codeItemList (items : List String) : Output.Html :=
  let lis : Array Output.Html := (items.map fun s => {{ <li><code>{{.text true s}}</code></li> }}).toArray
  {{ <ul class="bp_trust_list">{{lis}}</ul> }}

/-! ## Cross-links from the declaration registry

The evidence pages cross-link each named theorem to its blueprint node/decl page and
its GitHub source. Those hrefs live in the declaration registry (emitted when
`verso.blueprint.graph.includeAllDecls` is on); we read them from the traversal store
at generation time and degrade to name-only text when the registry is absent. -/

/-- The internal page href and GitHub source href for one declaration, from the
registry. Both optional (degrade to plain text / no link). -/
structure DeclLinks where
  pageHref : Option String := none
  sourceHref : Option String := none

/-- Build a declaration-name → `DeclLinks` lookup from the registry JSON (read from the
traversal store). Returns the empty lookup when the registry was not emitted or fails to
parse. -/
private def registryLinks (rawRegistry? : Option String) : String → DeclLinks :=
  match rawRegistry? with
  | some raw =>
    match Json.parse raw with
    | .ok j =>
      let decls := (j.getObjValAs? (Array Json) "decls").toOption.getD #[]
      let pairs : List (String × DeclLinks) := decls.toList.filterMap fun e =>
        (e.getObjValAs? String "name").toOption.map fun name =>
          let page := (e.getObjValAs? String "nodeHref").toOption.orElse fun _ =>
            (e.getObjValAs? String "declHref").toOption
          let src := (e.getObjValAs? String "sourceHref").toOption
          (name, ({ pageHref := page, sourceHref := src } : DeclLinks))
      fun n => (pairs.lookup n).getD {}
    | .error _ => fun _ => {}
  | _ => fun _ => {}

/-- Render a declaration name as a link to its blueprint page when known, else plain
`<code>`; optionally followed by a quiet GitHub source link. -/
private def declNameWithLinks (name : String) (links : DeclLinks) : Output.Html :=
  let nameHtml : Output.Html :=
    match links.pageHref with
    | some href => {{ <a class="bp_trust_decl_link" href={{href}}><code>{{.text true name}}</code></a> }}
    | _ => {{ <code>{{.text true name}}</code> }}
  let src : Output.Html :=
    match links.sourceHref with
    | some href => {{ " " <a class="bp_trust_source_link" href={{href}} target="_blank" rel="noopener">"source ↗"</a> }}
    | _ => .empty
  {{ <span class="bp_trust_decl">{{nameHtml}}{{src}}</span> }}

/-- Whether two axiom name lists denote the same set (order/duplication-insensitive). -/
private def axiomSetsAgree (kernel declared : List String) : Bool :=
  kernel.all declared.contains && declared.all kernel.contains

/-! ## Per-badge page bodies -/

/-- A small status badge, styled locally by `trust-strip.css` (so it renders correctly
on the standalone evidence pages without depending on the dashboard's summary.css).
`variant` is one of `"ok"`/`"warn"`/`"err"`. -/
private def trustBadge (variant text : String) : Output.Html :=
  {{ <span class={{s!"bp_trust_badge bp_trust_badge_{variant}"}}>{{.text true text}}</span> }}

/-- A ✓/⚠ verdict badge. -/
private def verdictBadge (ok : Bool) (text : String) : Output.Html :=
  trustBadge (if ok then "ok" else "warn") text

private def sorriesBody (trust : TrustData) (links : String → DeclLinks) : Output.Html :=
  let n := trust.sorryCount.getD 0
  let kernelCount := trust.sorryDecls.length
  -- Kernel-derived verdict when the scan ran, cross-checked against the YAML count.
  let evidence : Output.Html :=
    if trust.sorryScanRan then
      let agree := kernelCount == n
      let head : Output.Html :=
        if kernelCount == 0 then
          {{ <p>"A build-time scan of every declaration in the project namespace found "
              <strong>"no use of "<code>"sorryAx"</code></strong>" — the kernel primitive every "
              <code>"sorry"</code>" elaborates to. This "<strong>"sorry-free"</strong>" verdict is
              computed directly from the elaborated declarations, not read from a file."</p> }}
        else
          {{ <p>"A build-time scan found "<strong>{{.text true s!"{kernelCount}"}}</strong>"
              declaration(s) in the project namespace whose type or value uses "<code>"sorryAx"</code>"."</p> }}
      let crosscheck : Output.Html :=
        {{ <p>{{verdictBadge agree
                (if agree then s!"kernel-derived count {kernelCount} matches formalization.yaml"
                 else s!"kernel-derived count {kernelCount} differs from declared {n}")}}</p> }}
      let listing : Output.Html :=
        if trust.sorryDecls.isEmpty then .empty
        else
          let rows : Array Output.Html := (trust.sorryDecls.map fun d =>
            {{ <li>{{declNameWithLinks d (links d)}}</li> }}).toArray
          {{ <ul class="bp_trust_list">{{rows}}</ul> }}
      .seq #[head, crosscheck, listing]
    else
      -- No project namespace configured: present the YAML count honestly as *declared*.
      {{ <p>"The project "<em>"declares"</em>" "<strong>{{.text true s!"{n}"}}</strong>" "
          {{.text true (if n == 1 then "sorry" else "sorries")}}" in its "
          <code>"formalization.yaml"</code>". This count was "<strong>"not"</strong>" independently
          computed at site build (no project namespace was configured via "
          <code>"verso.blueprint.declNamePrefix"</code>")."</p> }}
  let repro : Output.Html :=
    {{ <ul>
        <li>"The site build scans the elaborated environment for declarations whose body uses "
          <code>"sorryAx"</code>" (the kernel primitive backing every "<code>"sorry"</code>"),
          restricted to the project namespace."</li>
        <li>"To check by hand: build the project — Lean prints a "<code>"declaration uses 'sorry'"</code>"
          warning for each remaining one — or run "<code>"#print axioms <theorem>"</code>", which lists "
          <code>"sorryAx"</code>" iff the proof transitively depends on a sorry."</li>
      </ul> }}
  trustPageShell "Sorries"
    "A sorry admits a proof goal without discharging it. A development with zero sorries has no such gaps — and this page derives that count from the kernel, not from a declared number."
    (.seq #[trustSection "Evidence" evidence, trustSection "How to reproduce" repro])

/-- One-sentence, mathematician-facing gloss of the three standard axioms. -/
private def standardAxiomGloss : Output.Html :=
  {{ <dl class="bp_trust_gloss">
      <dt><code>"propext"</code></dt>
      <dd>"Propositional extensionality: two propositions that imply each other are equal."</dd>
      <dt><code>"Classical.choice"</code></dt>
      <dd>"The axiom of choice: every nonempty type has a (noncomputable) distinguished element."</dd>
      <dt><code>"Quot.sound"</code></dt>
      <dd>"Soundness of quotients: elements related by a quotient's relation are identified in the quotient."</dd>
    </dl> }}

/-- One card of per-theorem kernel axiom evidence. -/
private def axiomEvidenceCard (ev : AxiomEvidence) (links : DeclLinks) : Output.Html :=
  let header := {{ <div class="bp_trust_axiom_head">{{declNameWithLinks ev.declaration links}}</div> }}
  if !ev.computed then
    {{ <div class="bp_trust_axiom_card">
        {{header}}
        <p>{{verdictBadge false "declared (not independently computed at site build)"}}</p>
        {{if ev.declaredAxioms.isEmpty then .empty else
            (.seq #[{{ <p class="bp_trust_axiom_label">"Declared axioms"</p> }},
                    codeItemList ev.declaredAxioms])}}
      </div> }}
  else
    let nonstd := Informal.Commands.nonstandardAxioms ev.kernelAxioms
    let agree := axiomSetsAgree ev.kernelAxioms ev.declaredAxioms
    let statusRow : Output.Html :=
      {{ <p class="bp_trust_badge_row">
          {{if nonstd.isEmpty then verdictBadge true "standard axioms only"
            else trustBadge "err" s!"{nonstd.length} nonstandard axiom(s)"}}
          {{if ev.declaredAxioms.isEmpty then .empty
            else verdictBadge agree (if agree then "matches formalization.yaml" else "differs from formalization.yaml")}}
        </p> }}
    let nonstdSection : Output.Html :=
      if nonstd.isEmpty then .empty
      else .seq #[{{ <p class="bp_trust_axiom_label">"Nonstandard axioms"</p> }}, codeItemList nonstd]
    let kernelSection : Output.Html :=
      .seq #[{{ <p class="bp_trust_axiom_label">"Kernel-computed axioms"</p> }},
        (if ev.kernelAxioms.isEmpty then {{ <p>"None — this result is axiom-free."</p> }}
         else codeItemList ev.kernelAxioms)]
    {{ <div class="bp_trust_axiom_card">
        {{header}}
        {{statusRow}}
        {{kernelSection}}
        {{nonstdSection}}
      </div> }}

private def axiomsBody (trust : TrustData) (links : String → DeclLinks) : Output.Html :=
  -- Prefer the kernel-computed evidence for the headline verdict when any main result
  -- was independently checked, so the page never claims "standard only" while a
  -- per-theorem card below shows a nonstandard axiom; fall back to the declared set.
  let computed := trust.axiomEvidence.filter (·.computed)
  let kernelNonstd :=
    (computed.flatMap (fun ev => Informal.Commands.nonstandardAxioms ev.kernelAxioms)).eraseDups
  let nonstandard :=
    if computed.isEmpty then Informal.Commands.nonstandardAxioms trust.axioms else kernelNonstd
  let basis := if computed.isEmpty then "declared" else "kernel-computed"
  let verdict : Output.Html :=
    if nonstandard.isEmpty then
      {{ <p>"Every "{{.text true basis}}" axiom this development relies on is one of Lean/Mathlib's three "
          <strong>"standard"</strong>" axioms. No custom or nonstandard axiom is used, so the proofs
          rest only on the foundations every kernel-checked Mathlib result shares."</p> }}
    else
      {{ <p>"The "{{.text true basis}}" axiom sets include "
          <strong>{{.text true s!"{nonstandard.length}"}}</strong>" axiom(s) beyond the three
          standard ones — listed with the relevant theorem below so they can be scrutinised."</p> }}
  -- Per-theorem kernel breakdown (Item 7): each main result's kernel-computed axiom set,
  -- cross-checked against the declared set. Absent when no main results were configured.
  let breakdown : Output.Html :=
    if trust.axiomEvidence.isEmpty then .empty
    else
      let cards : Array Output.Html := (trust.axiomEvidence.map fun ev =>
        axiomEvidenceCard ev (links ev.declaration)).toArray
      trustSection "Per-theorem kernel breakdown" (.seq cards)
  let glossSection := trustSection "What the standard axioms mean" standardAxiomGloss
  let repro : Output.Html :=
    {{ <ul>
        <li>"Each theorem's axiom set above is computed at site build with "<code>"Lean.collectAxioms"</code>"
          — the same walk "<code>"#print axioms <theorem>"</code>" performs — over the elaborated proof."</li>
        <li>"The three standard axioms are "<code>"propext"</code>", "<code>"Classical.choice"</code>",
          and "<code>"Quot.sound"</code>"; anything else is flagged as nonstandard."</li>
      </ul> }}
  trustPageShell "Axioms"
    "The theorems here depend only on the axioms below. Lean's kernel records every axiom a proof transitively uses, and this page recomputes that set at build time rather than trusting a declared list."
    (.seq #[trustSection "Evidence" verdict, breakdown, glossSection,
      trustSection "How to reproduce" repro])

private def reviewBody (status : String) : Output.Html :=
  let evidence : Output.Html :=
    {{ <p>"The project records its human-review status as "<strong>{{.text true status}}</strong>".
        This reflects a manual reading of the statements and proofs; the kernel independently
        checks that every proof is correct regardless of review status."</p> }}
  let repro : Output.Html :=
    {{ <ul>
        <li>"The review status is declared in the project's "<code>"formalization.yaml"</code>"
          under its "<code>"review"</code>" section."</li>
      </ul> }}
  trustPageShell "Review status"
    "Whether the formalization has been read and checked by a human, over and above the kernel's mechanical check."
    (.seq #[trustSection "Evidence" evidence, trustSection "How to reproduce" repro])

/-- A code block on a trust page: highlighted token markup when available (wrapped in
`<code class="hl lean">` so the shared `--verso-code-*` colors apply in both themes),
else escaped plain text. -/
private def trustCodeBlock (extraClass htmlMarkup fallback : String) : Output.Html :=
  if htmlMarkup.isEmpty then
    {{ <pre class={{s!"bp_trust_code {extraClass}"}}>{{.text true fallback}}</pre> }}
  else
    {{ <pre class={{s!"bp_trust_code {extraClass}"}}><code class="hl lean">{{.text false htmlMarkup}}</code></pre> }}

/-- A quiet outbound link on a trust page. -/
private def trustOutLink (href label : String) : Output.Html :=
  {{ <a class="bp_trust_out_link" href={{href}} target="_blank" rel="noopener">{{.text true label}}</a> }}

private def comparatorBody (cmp : TrustComparator) : Output.Html :=
  let verdict : Output.Html :=
    if cmp.status == "verified" then
      let whenTxt := if cmp.verifiedAt.isEmpty then "" else s!" (checked at {cmp.verifiedAt})"
      {{ <p>"An independent statement comparator has "<strong>"verified"</strong>" that the formal
          theorem statements match the intended informal claims"{{.text true whenTxt}}"."</p> }}
    else if cmp.status == "configured" then
      {{ <p>"A statement comparator is "<strong>"configured"</strong>" for this project but has not
          yet produced a verified verdict."</p> }}
    else
      {{ <p>"Comparator status: "<strong>{{.text true cmp.status}}</strong>"."</p> }}
  let theorems : Output.Html :=
    if cmp.theoremNames.isEmpty then .empty
    else trustSection "Checked theorems" (codeItemList cmp.theoremNames)
  let note : Output.Html :=
    if cmp.note.isEmpty then .empty
    else trustSection "Note" {{ <p>{{.text true cmp.note}}</p> }}
  -- Optional external link to the CI run that produced the verdict. A plain
  -- link (not a shipped asset), so it is fine under the offline constraint;
  -- omitted when the status artifact carries no `run_url`.
  let ciLink : Output.Html :=
    if cmp.runUrl.isEmpty then .empty
    else {{ <p><a class="bp_trust_ci_link" href={{cmp.runUrl}}
              target="_blank" rel="noopener">"View CI run →"</a></p> }}
  -- The comparator's configuration + the challenge Lean statement, embedded
  -- verbatim (read at build time) and syntax-highlighted so a skeptic can inspect
  -- exactly what was checked. Both degrade to nothing when their option/file is
  -- absent, and to escaped plain text when highlighting was unavailable.
  let configSection : Output.Html :=
    if cmp.configJson.isEmpty then .empty
    else
      let cfgLink : Output.Html :=
        if cmp.githubConfigUrl.isEmpty then .empty
        else {{ <p class="bp_trust_links">{{trustOutLink cmp.githubConfigUrl "View config on GitHub ↗"}}</p> }}
      trustSection "Comparator configuration"
        (.seq #[cfgLink,
          {{ <details class="bp_trust_disclosure">
               <summary>"Show comparator configuration"</summary>
               {{trustCodeBlock "bp_trust_code_json" cmp.configHtml cmp.configJson}}
             </details> }}])
  let challengeSection : Output.Html :=
    if cmp.challengeSource.isEmpty then .empty
    else
      -- Outbound links: GitHub blob at the pinned commit, and the Lean playground
      -- (which opens against its *current* Mathlib, not the pinned v4.31.0 toolchain).
      let ghLink : Option Output.Html :=
        if cmp.githubChallengeUrl.isEmpty then Option.none
        else Option.some (trustOutLink cmp.githubChallengeUrl "View on GitHub ↗")
      let pgLink : Option Output.Html :=
        if cmp.playgroundUrl.isEmpty then Option.none
        else Option.some (trustOutLink cmp.playgroundUrl "Open in Lean playground (current Mathlib) ↗")
      let linkItems := ([ghLink, pgLink].filterMap id)
      let linksRow : Output.Html :=
        match linkItems with
        | [] => .empty
        | first :: rest =>
          let joined := rest.foldl (init := first) fun acc x => .seq #[acc, {{ " · " }}, x]
          {{ <p class="bp_trust_links">{{joined}}</p> }}
      trustSection "Challenge statement (Lean)"
        (.seq #[
          {{ <p>"The exact Lean statement the comparator checks the formalization against:"</p> }},
          linksRow,
          trustCodeBlock "bp_trust_code_lean" cmp.challengeHtml cmp.challengeSource])
  -- The Solution file: the project's actual proof of the challenge statement, rendered
  -- the same way as the challenge (highlighted source + GitHub blob link at the pinned
  -- commit). Degrades to nothing when the `solutionFile` option/file is absent.
  let solutionSection : Output.Html :=
    if cmp.solutionSource.isEmpty then .empty
    else
      let ghLink : Output.Html :=
        if cmp.githubSolutionUrl.isEmpty then .empty
        else {{ <p class="bp_trust_links">{{trustOutLink cmp.githubSolutionUrl "View on GitHub ↗"}}</p> }}
      trustSection "Solution (Lean)"
        (.seq #[
          {{ <p>"The project's Lean proof that discharges the challenge statement:"</p> }},
          ghLink,
          trustCodeBlock "bp_trust_code_lean" cmp.solutionHtml cmp.solutionSource])
  let repro : Output.Html :=
    {{ <ul>
        <li>"Re-run the statement comparator against the project's "<code>"comparator.json"</code>"
          specification; it re-derives the verdict published here."</li>
      </ul> }}
  trustPageShell "Statement comparator"
    "An independent tool checks that the formal statements proved here really do encode the intended mathematical claims — guarding against a correct proof of the wrong statement."
    (.seq #[trustSection "Evidence" (.seq #[verdict, ciLink]), theorems, note,
      configSection, challengeSection, solutionSection, trustSection "How to reproduce" repro])

/--
`ExtraStep` that emits one trust-evidence page per configured badge under
`trust/`, from the traversal-cached trust payload.

Sibling to `emitBlueprintAuditPage`: single-page mode is skipped, and when no
trust data was cached (no `verso.blueprint.trust.*` option is set) it emits
nothing. The emitted pages mirror the badge set in `trustStripHtml`, so a badge
and its evidence page always appear together.
-/
def emitBlueprintTrustPages : ExtraStep :=
  fun mode cfg state text => do
    match mode with
    | .single => pure ()
    | .multi =>
      match Informal.TraversalIndex.TrustData.raw? state with
      | none => pure ()
      | some json =>
        match fromJson? (α := TrustData) json with
        | .error _ => pure ()
        | .ok trust =>
          -- Registry-backed cross-links (theorem → node/decl page + GitHub source);
          -- the empty lookup when the registry was not emitted (degrades to plain text).
          let links := registryLinks (Informal.TraversalIndex.DeclRegistry.raw? state)
          if trust.sorryCount.isSome then
            Informal.NodePage.emitStaticBlueprintPage mode cfg state text
              trustSorriesPath "Sorries" (sorriesBody trust links)
          if !trust.axioms.isEmpty then
            Informal.NodePage.emitStaticBlueprintPage mode cfg state text
              trustAxiomsPath "Axioms" (axiomsBody trust links)
          if !trust.reviewStatus.isEmpty then
            Informal.NodePage.emitStaticBlueprintPage mode cfg state text
              trustReviewPath "Review status" (reviewBody trust.reviewStatus)
          if let some cmp := trust.comparator then
            Informal.NodePage.emitStaticBlueprintPage mode cfg state text
              trustComparatorPath "Statement comparator" (comparatorBody cmp)

end Informal.Commands
