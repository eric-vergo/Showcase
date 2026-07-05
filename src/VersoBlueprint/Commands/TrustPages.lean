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

/-! ## Per-badge page bodies -/

private def sorriesBody (n : Nat) : Output.Html :=
  let evidence : Output.Html :=
    if n == 0 then
      {{ <p>"This formalization is "<strong>"sorry-free"</strong>": no declaration in the
          project admits a goal with "<code>"sorry"</code>". Every stated result is backed by a
          complete, kernel-checked proof."</p> }}
    else
      {{ <p>"The formalization currently reports "<strong>{{.text true s!"{n}"}}</strong>" "
          {{.text true (if n == 1 then "sorry" else "sorries")}}". A "<code>"sorry"</code>" admits
          a goal without proving it, so those results are not yet fully established."</p> }}
  let repro : Output.Html :=
    {{ <ul>
        <li>"Search the sources for the token, for example "<code>"grep -rn 'sorry' ."</code>"
          from the project root."</li>
        <li>"Build the project: Lean prints a "<code>"declaration uses 'sorry'"</code>" warning
          for every declaration that still contains one, so a clean build has none."</li>
      </ul> }}
  trustPageShell "Sorries"
    "A sorry is a placeholder that admits a proof goal without discharging it. A development with zero sorries has no such gaps."
    (.seq #[trustSection "Evidence" evidence, trustSection "How to reproduce" repro])

private def axiomsBody (axioms : List String) : Output.Html :=
  let nonstandard := axioms.filter (fun a => !standardAxioms.contains a)
  let standardUsed := axioms.filter (fun a => standardAxioms.contains a)
  let verdict : Output.Html :=
    if nonstandard.isEmpty then
      {{ <p>"Every axiom this development relies on is one of Lean/Mathlib's three "
          <strong>"standard"</strong>" axioms (below). No custom or nonstandard axiom is used, so
          the proofs rest only on the foundations every kernel-checked Mathlib result shares."</p> }}
    else
      {{ <p>"This development uses "<strong>{{.text true s!"{nonstandard.length}"}}</strong>"
          axiom(s) beyond the three standard ones. Nonstandard axioms are listed separately below
          so they can be scrutinised."</p> }}
  let standardSection : Output.Html :=
    trustSection "Standard axioms used"
      (if standardUsed.isEmpty then {{ <p>"None recorded."</p> }} else codeItemList standardUsed)
  let nonstandardSection : Output.Html :=
    if nonstandard.isEmpty then .empty
    else trustSection "Nonstandard axioms" (codeItemList nonstandard)
  let repro : Output.Html :=
    {{ <ul>
        <li>"In Lean, run "<code>"#print axioms <theorem>"</code>" on any of the project's main
          theorems: the kernel prints the complete set of axioms that theorem transitively
          depends on."</li>
        <li>"The three standard axioms are "<code>"propext"</code>", "<code>"Classical.choice"</code>",
          and "<code>"Quot.sound"</code>"."</li>
      </ul> }}
  trustPageShell "Axioms"
    "The theorems here depend only on the axioms listed below. Lean's kernel records every axiom a proof transitively uses, so this set is exhaustive."
    (.seq #[trustSection "Evidence" verdict, standardSection, nonstandardSection,
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
  -- verbatim (read at build time) so a skeptic can inspect exactly what was
  -- checked. Both degrade to nothing when their option/file is absent.
  let configSection : Output.Html :=
    if cmp.configJson.isEmpty then .empty
    else trustSection "Comparator configuration"
      {{ <details class="bp_trust_disclosure">
           <summary>"Show comparator configuration"</summary>
           <pre class="bp_trust_code bp_trust_code_json">{{.text true cmp.configJson}}</pre>
         </details> }}
  let challengeSection : Output.Html :=
    if cmp.challengeSource.isEmpty then .empty
    else trustSection "Challenge statement (Lean)"
      {{ <p>"The exact Lean statement the comparator checks the formalization against:"</p>
         <pre class="bp_trust_code bp_trust_code_lean">{{.text true cmp.challengeSource}}</pre> }}
  let repro : Output.Html :=
    {{ <ul>
        <li>"Re-run the statement comparator against the project's "<code>"comparator.json"</code>"
          specification; it re-derives the verdict published here."</li>
      </ul> }}
  trustPageShell "Statement comparator"
    "An independent tool checks that the formal statements proved here really do encode the intended mathematical claims — guarding against a correct proof of the wrong statement."
    (.seq #[trustSection "Evidence" (.seq #[verdict, ciLink]), theorems, note,
      configSection, challengeSection, trustSection "How to reproduce" repro])

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
          if let some n := trust.sorryCount then
            Informal.NodePage.emitStaticBlueprintPage mode cfg state text
              trustSorriesPath "Sorries" (sorriesBody n)
          if !trust.axioms.isEmpty then
            Informal.NodePage.emitStaticBlueprintPage mode cfg state text
              trustAxiomsPath "Axioms" (axiomsBody trust.axioms)
          if !trust.reviewStatus.isEmpty then
            Informal.NodePage.emitStaticBlueprintPage mode cfg state text
              trustReviewPath "Review status" (reviewBody trust.reviewStatus)
          if let some cmp := trust.comparator then
            Informal.NodePage.emitStaticBlueprintPage mode cfg state text
              trustComparatorPath "Statement comparator" (comparatorBody cmp)

end Informal.Commands
