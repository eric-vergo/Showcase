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
import VersoBlueprint.PreviewManifest

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
    | some href => {{ " " <a class="bp_trust_source_link" href={{href}} target="_blank" rel="noopener">"source"</a> }}
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

/-- A quiet link to the machine-readable audit artifact, shown on each evidence page
(relative, offline-safe). -/
private def auditJsonLink : Output.Html :=
  {{ <p class="bp_trust_links">
       <a class="bp_trust_out_link" href={{trustAuditJsonHref}}>"Machine-readable audit (trust-audit.json)"</a>
     </p> }}

/-- A code block on a trust page: highlighted token markup when available (wrapped in
`<code class="hl lean">` so the shared `--verso-code-*` colors apply in both themes),
else escaped plain text. -/
private def trustCodeBlock (extraClass htmlMarkup fallback : String) : Output.Html :=
  if htmlMarkup.isEmpty then
    {{ <pre class={{s!"bp_trust_code {extraClass}"}}>{{.text true fallback}}</pre> }}
  else
    {{ <pre class={{s!"bp_trust_code {extraClass}"}}><code class="hl lean">{{.text false htmlMarkup}}</code></pre> }}

/-- Embed one check's machine-checkable JSON slice — the same object written to
`trust-audit.json` — on its evidence page: pretty-printed, JSON-highlighted (reusing
the comparator page's `bp_trust_code_json` embed styling), and collapsible. `none`
when the check produced no JSON object (e.g. an empty graph). -/
private def checkJsonSection (checkJson? : Option Json) : Output.Html :=
  match checkJson? with
  | none => .empty
  | some j =>
    let pretty := j.pretty
    trustSection "Machine-checkable evidence"
      (.seq #[
        {{ <p>"This check's entry in "<code>"trust-audit.json"</code>", verbatim (id, title,
            verdict, method, and evidence):"</p> }},
        {{ <details class="bp_trust_disclosure">
             <summary>"Show JSON"</summary>
             {{trustCodeBlock "bp_trust_code_json" (highlightJsonHtml pretty).asString pretty}}
           </details> }}])

private def sorriesBody (trust : TrustData) (links : String → DeclLinks)
    (checkJson? : Option Json) : Output.Html :=
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
    (.seq #[trustSection "Evidence" evidence, trustSection "How to reproduce" repro,
      checkJsonSection checkJson?, auditJsonLink])

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

/-- One row of the explicit critical-axiom name-check. `present` is the *bad*
outcome, so the verdict badge is green (`ok`) exactly when the axiom is absent. -/
private def criticalAxiomRow (collected : List String) (name desc : String) : Output.Html :=
  let present := collected.contains name
  {{ <li class="bp_trust_badge_row">
       {{verdictBadge (!present) (if present then "present" else "not present")}}
       <span><code>{{.text true name}}</code>" — "{{.text true desc}}</span>
     </li> }}

/-- Item 2: an explicit name-check of the collected axiom set for the axioms that
would weaken the kernel guarantee, plus the compiled-evaluation caveat. Absent when
no main result was independently checked. -/
private def criticalAxiomSection (trust : TrustData) : Output.Html :=
  let computed := trust.axiomEvidence.filter (·.computed)
  if computed.isEmpty then .empty
  else
    let collected := (computed.flatMap (·.kernelAxioms)).eraseDups
    let rows : Array Output.Html := #[
      criticalAxiomRow collected "sorryAx"
        "the kernel primitive behind every `sorry`; if present, a proof gap was admitted as an axiom.",
      criticalAxiomRow collected "Lean.ofReduceBool"
        "the axiom `native_decide` relies on; if present, a proof trusts compiled (native) evaluation rather than the kernel.",
      criticalAxiomRow collected "Lean.ofReduceNat"
        "a companion native-reduction axiom; if present, the same compiled-evaluation trust applies." ]
    trustSection "Critical axiom check"
      (.seq #[
        {{ <p>"The collected axiom set is checked by name for the axioms that would weaken the
            kernel guarantee. Each is reported present or absent:"</p> }},
        {{ <ul class="bp_trust_list">{{rows}}</ul> }},
        {{ <p class="bp_trust_note">"Note: "<code>"@[implemented_by]"</code>", "
            <code>"@[extern]"</code>", and "<code>"partial"</code>" affect only compiled
            evaluation, not kernel-checked "<code>"Prop"</code>" soundness — they cannot
            introduce an axiom or change which theorems are provable."</p> }} ])

private def axiomsBody (trust : TrustData) (links : String → DeclLinks)
    (checkJson? : Option Json) : Output.Html :=
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
    (.seq #[trustSection "Evidence" verdict, breakdown, criticalAxiomSection trust,
      glossSection, trustSection "How to reproduce" repro, checkJsonSection checkJson?, auditJsonLink])

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
              target="_blank" rel="noopener">"View CI run"</a></p> }}
  -- The comparator's configuration + the challenge Lean statement, embedded
  -- verbatim (read at build time) and syntax-highlighted so a skeptic can inspect
  -- exactly what was checked. Both degrade to nothing when their option/file is
  -- absent, and to escaped plain text when highlighting was unavailable.
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
  let challengeSection : Output.Html :=
    if cmp.challengeSource.isEmpty then .empty
    else
      -- Outbound links: GitHub blob at the pinned commit, and the Lean playground
      -- (which opens against its *current* Mathlib, not the pinned v4.31.0 toolchain).
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
        else {{ <p class="bp_trust_links">{{trustOutLink cmp.githubSolutionUrl "View on GitHub"}}</p> }}
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
      configSection, challengeSection, solutionSection, trustSection "How to reproduce" repro,
      auditJsonLink])

/-! ## Structural `uses`-graph evidence pages -/

open Informal.Graph in
/-- Friendly display text for a graph node label: enriched node title, else the short
display label, else the de-escaped raw label. -/
private def graphNodeText (master : GraphData) (label : Lean.Name) : String :=
  match master.nodes.find? (·.label == label) with
  | some node =>
    let t := node.title.trim
    if !t.isEmpty then t
    else if !node.displayLabel.isEmpty then node.displayLabel
    else Informal.NodeRoute.stripNameEscapes label.toString
  | none => Informal.NodeRoute.stripNameEscapes label.toString

open Informal.Graph in
/-- One node entry in a cycle / straggler list, linking to the node page when it has one. -/
private def graphNodeItem (master : GraphData) (state : TraverseState) (label : Lean.Name) :
    Output.Html :=
  let txt := graphNodeText master label
  if Informal.NodeRoute.hasNodePage state label then
    {{ <li><a class="bp_trust_decl_link" href={{Informal.NodeRoute.nodePageHref label}}>{{.text true txt}}</a></li> }}
  else {{ <li>{{.text true txt}}</li> }}

open Informal.Graph Informal.GraphChecks in
private def graphAcyclicityBody (master : GraphData) (r : AcyclicityResult)
    (state : TraverseState) (checkJson? : Option Json) : Output.Html :=
  let evidence : Output.Html :=
    if r.ok then
      {{ <p>{{verdictBadge true "acyclic"}}" A build-time traversal of the dependency graph — "
          <strong>{{.text true s!"{r.nodeCount}"}}</strong>" nodes, "
          <strong>{{.text true s!"{r.edgeCount}"}}</strong>" edges — found "<strong>"no cycle"</strong>".
          Every node's dependencies admit a consistent topological reading order."</p> }}
    else
      let items := r.cycle.map (graphNodeItem master state)
      .seq #[
        {{ <p>{{verdictBadge false "cycle detected"}}" The dependency graph contains a directed
            cycle among the following nodes, so no consistent reading order exists:"</p> }},
        {{ <ul class="bp_trust_list">{{items}}</ul> }} ]
  let method : Output.Html :=
    {{ <ul>
        <li>"Every "<code>"uses"</code>" edge authored in the blueprint is collected into one
          directed dependency graph."</li>
        <li>"A depth-first traversal looks for a back edge — an edge into a node already on the
          current path — which is exactly a cycle."</li>
        <li>"This is a structural check on the graph's shape, independent of the Lean kernel and
          of whether any proof is complete. A violation fails the site build."</li>
      </ul> }}
  trustPageShell "Graph acyclicity"
    "The blueprint's dependency graph must be acyclic: no node may depend, directly or transitively, on itself. This is checked at every site build, and a violation fails the build — so a built site has passed."
    (.seq #[trustSection "Evidence" evidence, trustSection "Method" method,
      checkJsonSection checkJson?, auditJsonLink])

open Informal.Graph Informal.GraphChecks in
private def graphConnectivityBody (master : GraphData) (r : ConnectivityResult)
    (state : TraverseState) (required : Bool) (checkJson? : Option Json) : Output.Html :=
  let evidence : Output.Html :=
    if r.ok then
      {{ <p>{{verdictBadge true "connected"}}" All "
          <strong>{{.text true s!"{r.nodeCount}"}}</strong>" nodes form a "
          <strong>"single weakly-connected component"</strong>": every entry is tied, through some
          chain of dependencies, to the main development — no orphaned islands."</p> }}
    else
      let items := r.stragglers.map (graphNodeItem master state)
      let head : Output.Html :=
        if required then
          {{ <p>{{verdictBadge false s!"{r.componentCount} components"}}" The graph splits into "
              <strong>{{.text true s!"{r.componentCount}"}}</strong>" disconnected components. The
              largest holds "<strong>{{.text true s!"{r.mainComponentSize}"}}</strong>" nodes; the
              following are outside it:"</p> }}
        else
          {{ <p>{{trustBadge "warn" s!"{r.componentCount} parts"}}" This blueprint is intentionally
              multi-topic ("<code>"requireConnected"</code>" is off), so connectivity is reported
              for information only. The graph has "
              <strong>{{.text true s!"{r.componentCount}"}}</strong>" components; the largest holds "
              <strong>{{.text true s!"{r.mainComponentSize}"}}</strong>" nodes, and the following are
              outside it:"</p> }}
      .seq #[head, {{ <ul class="bp_trust_list">{{items}}</ul> }} ]
  let method : Output.Html :=
    {{ <ul>
        <li>"Dependency edges are treated as undirected and the graph's connected components are
          computed."</li>
        <li>"A single component means every node is reachable from the featured results; any extra
          component is orphaned material not tied to the main development."</li>
        <li>{{.text true (if required then
            "Structural check, independent of the kernel and of proof completeness. A violation fails the site build."
          else
            "Structural check, independent of the kernel and of proof completeness. Reported for information; not enforced for this deliberately multi-topic blueprint.")}}</li>
      </ul> }}
  let intro :=
    if required then
      "The blueprint's dependency graph must form a single weakly-connected component: every node connects to the component containing the featured results. This is checked at every site build, and a violation fails the build."
    else
      "This blueprint is deliberately multi-topic, so connectivity is reported for information rather than enforced. A coherent single-development blueprint would require one connected component."
  trustPageShell "Graph connectivity" intro
    (.seq #[trustSection "Evidence" evidence, trustSection "Method" method,
      checkJsonSection checkJson?, auditJsonLink])

/-! ## Reproducibility: dependency pins from the lake manifest -/

/-- One significant dependency pin read from `lake-manifest.json`. -/
structure DepPin where
  name : String
  /-- Short revision (`inputRev@shortSha`), or `local path (…)` for a path dep. -/
  version : String
  url : Option String := none
deriving Inhabited

/-- Read the significant dependency pins (Mathlib + the verso forks + subverso) from the
consumer's `lake-manifest.json`. Offline, build-time; degrades to `#[]` when the manifest
is absent or unparsable. -/
private def readTrustDepPins : IO (Array DepPin) := do
  let cwd ← IO.currentDir
  let path := cwd / "lake-manifest.json"
  unless ← path.pathExists do return #[]
  match Json.parse (← IO.FS.readFile path) with
  | .error _ => return #[]
  | .ok j =>
    let pkgs := (j.getObjValAs? (Array Json) "packages").toOption.getD #[]
    let interest : List String :=
      ["mathlib", "Mathlib", "verso", "VersoBlueprint", "verso-blueprint", "subverso",
       "«verso-slides»", "verso-slides"]
    return pkgs.filterMap fun p =>
      let name := (p.getObjValAs? String "name").toOption.getD ""
      if !interest.contains name then none
      else
        let typ := (p.getObjValAs? String "type").toOption.getD ""
        let url := (p.getObjValAs? String "url").toOption
        let version :=
          if typ == "path" then
            match (p.getObjValAs? String "dir").toOption with
            | some d => s!"local path ({d})"
            | none => "local path"
          else
            let rev := (p.getObjValAs? String "rev").toOption.getD ""
            let shortRev := if rev.length ≤ 12 then rev else (rev.take 12).copy
            let inputRev := (p.getObjValAs? String "inputRev").toOption.getD ""
            if inputRev.isEmpty || inputRev == rev then shortRev
            else s!"{inputRev}@{shortRev}"
        some { name, version, url }

/-! ## Verification-overview page (all automated checks) -/

/-- A links row on the overview page, joined with middots. -/
private def linkRow (items : Array Output.Html) : Output.Html :=
  match items.toList with
  | [] => .empty
  | first :: rest =>
    let joined := rest.foldl (init := first) fun acc x => .seq #[acc, {{ " · " }}, x]
    {{ <p class="bp_trust_links">{{joined}}</p> }}

/-- One check card on the overview page: title + verdict badge, a plain-language
description of what it proves (and does not prove), and its links. `ok?` is `none`
for an "unknown / not independently computed" verdict. -/
private def overviewCard (title verdictText : String) (ok? : Option Bool)
    (desc : Output.Html) (links : Array Output.Html) : Output.Html :=
  let badge : Output.Html :=
    match ok? with
    | some b => verdictBadge b verdictText
    | none => trustBadge "warn" verdictText
  {{ <div class="bp_trust_axiom_card">
       <div class="bp_trust_axiom_head">{{.text true title}}" "{{badge}}</div>
       {{desc}}
       {{linkRow links}}
     </div> }}

open Informal.GraphChecks in
private def checksOverviewBody (trust? : Option TrustData) (checks : Results)
    (metadata : Informal.PreviewManifest.BuildMetadata) (deps : Array DepPin)
    (requireConnected : Bool) : Output.Html :=
  -- The CI run that produced these checks (item 2, consumer-supplied via
  -- `verso.blueprint.trust.ciRunUrl`); `none` on a local build ⇒ no CI links.
  let ciRunUrl : Option String := trust?.bind (·.ciRunUrl)
  -- An arrow-free "CI run" link for a check card, when a CI run URL is available.
  let ciLink : Option String → Array Output.Html := fun url? =>
    match url? with
    | some u => #[({{ <a class="bp_trust_out_link" href={{u}} target="_blank" rel="noopener">"CI run"</a> }} : Output.Html)]
    | none => #[]
  -- Comparator card.
  let comparatorCard : Output.Html :=
    match trust?.bind (·.comparator) with
    | none => .empty
    | some cmp =>
      let ok? := if cmp.status == "verified" then some true else none
      let verdictText := if cmp.status.isEmpty then "unknown" else cmp.status
      let desc :=
        {{ <p>"Replays the project's certified theorem in the Lean kernel and checks — via an
            independent tool — that the formal statement encodes the intended informal claim. "
            <em>"Proves"</em>": the statement being proved is the one meant. "<em>"Does not
            prove"</em>": the wider informal narrative, only the named statement(s)."</p> }}
      -- Prefer the shared CI run URL; fall back to the status artifact's own `run_url`.
      let cmpCiUrl := ciRunUrl.orElse fun _ => if cmp.runUrl.isEmpty then none else some cmp.runUrl
      overviewCard "Statement comparator (kernel replay)" verdictText ok? desc
        (#[({{ <a class="bp_trust_out_link" href={{trustComparatorHref}}>"Evidence"</a> }} : Output.Html)]
          ++ ciLink cmpCiUrl)
  -- Transitive axiom audit card.
  let axiomsCard : Output.Html :=
    let computed := (trust?.map (·.axiomEvidence)).getD [] |>.filter (·.computed)
    if computed.isEmpty && ((trust?.map (·.axioms)).getD []).isEmpty then .empty
    else
      let collected := (computed.flatMap (·.kernelAxioms)).eraseDups
      let nonstd := Informal.Commands.nonstandardAxioms collected
      let ok? := if computed.isEmpty then none else some nonstd.isEmpty
      let verdictText :=
        if computed.isEmpty then "declared only"
        else if nonstd.isEmpty then "standard axioms only"
        else s!"{nonstd.length} nonstandard"
      let desc :=
        {{ <p>"Recomputes, with "<code>"Lean.collectAxioms"</code>", the full transitive axiom set
            each main result depends on. "<em>"Proves"</em>": no custom or nonstandard axiom (and
            no "<code>"sorryAx"</code>"/native-reduction axiom) underlies the proofs. "<em>"Does
            not prove"</em>": that the standard axioms themselves are consistent — that is assumed,
            as in all of Mathlib."</p> }}
      overviewCard "Transitive axiom audit" verdictText ok? desc
        (#[({{ <a class="bp_trust_out_link" href={{trustAxiomsHref}}>"Evidence"</a> }} : Output.Html)]
          ++ ciLink ciRunUrl)
  -- Sorry scan card.
  let sorriesCard : Output.Html :=
    match trust? with
    | none => .empty
    | some trust =>
      if !(trust.sorryCount.isSome || trust.sorryScanRan) then .empty
      else
        let ok? := if trust.sorryScanRan then some (trust.sorryDecls.length == 0) else none
        let verdictText :=
          if trust.sorryScanRan then
            let n := trust.sorryDecls.length
            s!"{n} {if n == 1 then "sorry" else "sorries"}"
          else "declared only"
        let desc :=
          {{ <p>"Scans every elaborated declaration in the project namespace for "<code>"sorryAx"</code>",
              the primitive behind every "<code>"sorry"</code>". "<em>"Proves"</em>": no proof gap was
              admitted. "<em>"Does not prove"</em>": anything about declarations outside the project
              namespace."</p> }}
        overviewCard "Sorry scan" verdictText ok? desc
          (#[({{ <a class="bp_trust_out_link" href={{trustSorriesHref}}>"Evidence"</a> }} : Output.Html)]
            ++ ciLink ciRunUrl)
  -- Graph structural cards.
  let graphCards : Output.Html :=
    if checks.graphEmpty then .empty
    else
      let acDesc :=
        {{ <p>"Depth-first check that the authored "<code>"uses"</code>" graph has no directed cycle.
            "<em>"Proves"</em>": the dependencies admit a consistent reading order. "<em>"Does not
            prove"</em>": anything about proof content — it is purely structural."</p> }}
      let coDesc :=
        {{ <p>"Checks that the "<code>"uses"</code>" graph is a single weakly-connected component.
            "<em>"Proves"</em>": no entry is orphaned from the main development. "<em>"Does not
            prove"</em>": anything about proof content — it is purely structural."</p> }}
      .seq #[
        overviewCard "Graph acyclicity" (if checks.acyclic.ok then "acyclic" else "cycle")
          (some checks.acyclic.ok) acDesc
          (#[({{ <a class="bp_trust_out_link" href={{trustGraphAcyclicHref}}>"Evidence"</a> }} : Output.Html)]
            ++ ciLink ciRunUrl),
        overviewCard "Graph connectivity"
          (if checks.connected.ok then "connected"
           else if requireConnected then "split" else s!"{checks.connected.componentCount} parts (informational)")
          (if checks.connected.ok then some true else if requireConnected then some false else none)
          coDesc
          (#[({{ <a class="bp_trust_out_link" href={{trustGraphConnectedHref}}>"Evidence"</a> }} : Output.Html)]
            ++ ciLink ciRunUrl) ]
  -- Reproducibility section.
  let depItems : Array Output.Html := deps.map fun d =>
    let ver : Output.Html :=
      match d.url with
      | some u => {{ <a class="bp_trust_out_link" href={{u}} target="_blank" rel="noopener"><code>{{.text true d.version}}</code></a> }}
      | none => {{ <code>{{.text true d.version}}</code> }}
    {{ <li><strong>{{.text true d.name}}</strong>" — "{{ver}}</li> }}
  let toolInfo := (trust?.map (·.comparatorToolInfo)).getD ""
  let repro : Output.Html :=
    .seq #[
      {{ <p>"Toolchain: "<code>{{.text true metadata.leanToolchain}}</code>"."</p> }},
      (if depItems.isEmpty then .empty else
        .seq #[{{ <p class="bp_trust_axiom_label">"Dependency pins (from lake-manifest.json)"</p> }},
               {{ <ul class="bp_trust_list">{{depItems}}</ul> }}]),
      (if toolInfo.isEmpty then .empty else
        {{ <p>"External comparator tooling: "<code>{{.text true toolInfo}}</code>"."</p> }}),
      Informal.PreviewManifest.buildMetadataHtml metadata ]
  trustPageShell "Verification"
    "Every automated check this site runs, in one place: what each one proves, what it does not, and where to see the evidence. If the site built, the structural graph checks passed."
    (.seq #[
      trustSection "Automated checks"
        (.seq #[comparatorCard, axiomsCard, sorriesCard, graphCards]),
      trustSection "Reproducibility" repro,
      auditJsonLink])

/-! ## Machine-readable trust-audit artifact -/

private def jsonCheck (id title verdict method : String) (evidence : Json) : Json :=
  Json.mkObj [("id", Json.str id), ("title", Json.str title), ("verdict", Json.str verdict),
    ("method", Json.str method), ("evidence", evidence)]

open Informal.GraphChecks in
/-- The per-check JSON objects (id/title/verdict/method/evidence), built once and
shared between the `trust-audit.json` artifact and the per-check evidence-page embeds
(so each page shows exactly the slice the audit file records for it). Order matches
the audit file. -/
private def trustCheckJsons (trust? : Option TrustData) (checks : Results)
    (requireConnected : Bool) : Array Json := Id.run do
  let mut checkArr : Array Json := #[]
  -- Comparator.
  if let some cmp := trust?.bind (·.comparator) then
    let verdict := if cmp.status == "verified" then "pass" else "unknown"
    checkArr := checkArr.push <| jsonCheck "comparator" "Statement comparator (kernel replay)"
      verdict "Independent kernel replay of the certified theorem + statement comparison."
      (Json.mkObj [("status", Json.str cmp.status), ("verifiedAt", Json.str cmp.verifiedAt),
        ("theoremNames", toJson cmp.theoremNames), ("runUrl", Json.str cmp.runUrl)])
  -- Axioms.
  let computed := (trust?.map (·.axiomEvidence)).getD [] |>.filter (·.computed)
  if !(computed.isEmpty && ((trust?.map (·.axioms)).getD []).isEmpty) then
    let collected := (computed.flatMap (·.kernelAxioms)).eraseDups
    let nonstd := Informal.Commands.nonstandardAxioms collected
    let verdict := if computed.isEmpty then "unknown" else if nonstd.isEmpty then "pass" else "fail"
    let critical := Json.mkObj [
      ("sorryAx", Json.bool (collected.contains "sorryAx")),
      ("Lean.ofReduceBool", Json.bool (collected.contains "Lean.ofReduceBool")),
      ("Lean.ofReduceNat", Json.bool (collected.contains "Lean.ofReduceNat"))]
    checkArr := checkArr.push <| jsonCheck "axioms" "Transitive axiom audit" verdict
      "Lean.collectAxioms over each formalization.yaml main_result."
      (Json.mkObj [("computed", Json.bool !computed.isEmpty), ("collected", toJson collected),
        ("nonstandard", toJson nonstd), ("critical", critical)])
  -- Sorries.
  if let some trust := trust? then
    if trust.sorryCount.isSome || trust.sorryScanRan then
      let verdict :=
        if !trust.sorryScanRan then "unknown"
        else if trust.sorryDecls.length == 0 then "pass" else "fail"
      checkArr := checkArr.push <| jsonCheck "sorries" "Sorry scan" verdict
        "Scan of the project namespace for declarations using sorryAx."
        (Json.mkObj [("scanRan", Json.bool trust.sorryScanRan),
          ("count", toJson (if trust.sorryScanRan then trust.sorryDecls.length else trust.sorryCount.getD 0)),
          ("sorryDecls", toJson trust.sorryDecls)])
  -- Graph checks.
  unless checks.graphEmpty do
    checkArr := checkArr.push <| jsonCheck "graph-acyclicity" "Graph acyclicity"
      (if checks.acyclic.ok then "pass" else "fail")
      "Depth-first cycle detection over the authored uses graph."
      (Json.mkObj [("ok", Json.bool checks.acyclic.ok),
        ("cycle", toJson (checks.acyclic.cycle.map (·.toString))),
        ("nodeCount", toJson checks.acyclic.nodeCount), ("edgeCount", toJson checks.acyclic.edgeCount)])
    checkArr := checkArr.push <| jsonCheck "graph-connectivity" "Graph connectivity"
      (if checks.connected.ok then "pass" else if requireConnected then "fail" else "unknown")
      "Weakly-connected-component computation over the authored uses graph."
      (Json.mkObj [("ok", Json.bool checks.connected.ok),
        ("enforced", Json.bool requireConnected),
        ("componentCount", toJson checks.connected.componentCount),
        ("mainComponentSize", toJson checks.connected.mainComponentSize),
        ("stragglers", toJson (checks.connected.stragglers.map (·.toString)))])
  return checkArr

/-- Look up one check's JSON object by its `id`, as written by `trustCheckJsons`. -/
private def findCheckJson (checkArr : Array Json) (id : String) : Option Json :=
  checkArr.find? fun j => (j.getObjValAs? String "id").toOption == some id

open Informal.GraphChecks in
/-- Build the `-verso-data/trust-audit.json` payload (item 3). Timestamps use the
build-time `compiledAt` from build metadata (a `date -u` shell read), never a
nonexistent Lean `Date.now`. Reuses `trustCheckJsons` so the artifact and the
per-check page embeds never drift. -/
private def trustAuditJson (trust? : Option TrustData) (checks : Results)
    (metadata : Informal.PreviewManifest.BuildMetadata) (deps : Array DepPin)
    (requireConnected : Bool) : Json := Id.run do
  let checkArr := trustCheckJsons trust? checks requireConnected
  -- Per-declaration axiom/sorry evidence.
  let declsObj : Json := Json.mkObj <|
    (trust?.map (·.axiomEvidence)).getD [] |>.map fun ev =>
      (ev.declaration, Json.mkObj [
        ("computed", Json.bool ev.computed),
        ("kernelAxioms", toJson ev.kernelAxioms),
        ("declaredAxioms", toJson ev.declaredAxioms),
        ("usesSorryAx", Json.bool (ev.kernelAxioms.contains "sorryAx"))])
  let depsJson : Json := toJson <| deps.map fun d =>
    Json.mkObj [("name", Json.str d.name), ("version", Json.str d.version),
      ("url", match d.url with | some u => Json.str u | none => Json.null)]
  return Json.mkObj [
    ("schemaVersion", toJson (1 : Nat)),
    ("generatedAt", Json.str metadata.compiledAt),
    ("toolchain", Json.str metadata.leanToolchain),
    ("dependencies", depsJson),
    ("checks", toJson checkArr),
    ("decls", declsObj)]

/--
`ExtraStep` that emits one trust-evidence page per configured badge under
`trust/`, from the traversal-cached trust payload.

Sibling to `emitBlueprintAuditPage`: single-page mode is skipped, and when no
trust data was cached (no `verso.blueprint.trust.*` option is set) it emits
nothing. The set of emitted pages is independent of the trust strip's badges: the
strip carries only the review/comparator verdicts, whereas every configured check
(sorries, axioms, review, comparator, and the structural graph checks) gets its own
evidence page, all reachable from the "All checks" verification-overview page.
-/
def emitBlueprintTrustPages : ExtraStep :=
  fun mode cfg state text => do
    match mode with
    | .single => pure ()
    | .multi =>
      let master := Informal.GraphApi.masterGraph state
      let checks := Informal.GraphChecks.run master
      -- Decode the (possibly-empty) trust payload cached during traversal.
      let trust? : Option TrustData :=
        (Informal.TraversalIndex.TrustData.raw? state).bind fun json =>
          (fromJson? (α := TrustData) json).toOption
      let requireConnected := (trust?.map (·.requireConnected)).getD true
      -- Per-check JSON slices, built once and shared between the audit artifact and the
      -- per-check evidence-page embeds (`findCheckJson` by id).
      let checkArr := trustCheckJsons trust? checks requireConnected
      -- Build gate (item 1): a structural `uses`-graph violation FAILS the build. If the
      -- site built, these checks passed. Acyclicity always gates; connectivity gates when
      -- `verso.blueprint.trust.requireConnected` (default true). Skipped for an empty graph.
      unless checks.graphEmpty do
        unless checks.acyclic.ok do
          let cyc := String.intercalate " → " (checks.acyclic.cycle.map (graphNodeText master)).toList
          throw <| IO.userError s!"Blueprint uses-graph check FAILED (acyclicity): a dependency cycle was detected among: {cyc}. Remove the cyclic `uses` edges."
        unless checks.connected.ok || !requireConnected do
          let strag := String.intercalate ", " (checks.connected.stragglers.map (graphNodeText master)).toList
          throw <| IO.userError s!"Blueprint uses-graph check FAILED (connectivity): the `uses` graph has {checks.connected.componentCount} disconnected components. Nodes outside the main component: {strag}. Connect them to the main development, or set verso.blueprint.trust.requireConnected := false for a deliberately multi-topic blueprint."
      -- Registry-backed cross-links (theorem → node/decl page + GitHub source);
      -- the empty lookup when the registry was not emitted (degrades to plain text).
      let links := registryLinks (Informal.TraversalIndex.DeclRegistry.raw? state)
      -- Structural-graph evidence pages (whenever a graph exists).
      unless checks.graphEmpty do
        Informal.NodePage.emitStaticBlueprintPage mode cfg state text
          trustGraphAcyclicPath "Graph acyclicity"
          (graphAcyclicityBody master checks.acyclic state (findCheckJson checkArr "graph-acyclicity"))
        Informal.NodePage.emitStaticBlueprintPage mode cfg state text
          trustGraphConnectedPath "Graph connectivity"
          (graphConnectivityBody master checks.connected state requireConnected
            (findCheckJson checkArr "graph-connectivity"))
      -- Verification-overview page + machine-readable audit artifact (item 3/4/5),
      -- whenever there is either a graph or trust data to report.
      if !checks.graphEmpty || trust?.isSome then
        let metadata ← Informal.PreviewManifest.readBuildMetadata
        let deps ← readTrustDepPins
        Informal.NodePage.emitStaticBlueprintPage mode cfg state text
          trustChecksPath "Verification" (checksOverviewBody trust? checks metadata deps requireConnected)
        let outDir := cfg.destination.join (match mode with | .single => "html-single" | .multi => "html-multi")
        let dataDir := outDir.join "-verso-data"
        IO.FS.createDirAll dataDir
        IO.FS.writeFile (dataDir.join trustAuditJsonFilename)
          ((trustAuditJson trust? checks metadata deps requireConnected).pretty ++ "\n")
      -- Per-badge evidence pages — existing behavior, gated on configured trust data.
      match trust? with
      | none => pure ()
      | some trust =>
        if trust.sorryCount.isSome || trust.sorryScanRan then
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            trustSorriesPath "Sorries" (sorriesBody trust links (findCheckJson checkArr "sorries"))
        if !trust.axioms.isEmpty || (trust.axiomEvidence.any (·.computed)) then
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            trustAxiomsPath "Axioms" (axiomsBody trust links (findCheckJson checkArr "axioms"))
        if !trust.reviewStatus.isEmpty then
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            trustReviewPath "Review status" (reviewBody trust.reviewStatus)
        if let some cmp := trust.comparator then
          Informal.NodePage.emitStaticBlueprintPage mode cfg state text
            trustComparatorPath "Statement comparator" (comparatorBody cmp)

end Informal.Commands
