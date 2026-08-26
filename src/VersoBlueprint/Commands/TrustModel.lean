/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Commands.TrustStrip
import VersoBlueprint.GraphApi
import VersoBlueprint.GraphChecks
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.MathLint
import VersoBlueprint.NodeCard
import VersoBlueprint.NodeRoute
import VersoBlueprint.TraversalIndex

/-!
`blueprint_trust_model` — the standalone "Trust model" page.

Usage: `{blueprint_trust_model}`, optionally
`{blueprint_trust_model (proseDisclosure := "…")}`.

A site that presents formal proofs invites a reader to believe things. This page
says, in one place, exactly which of those beliefs a machine established and which
ones a human asserted — and what the machine-established ones actually rest on.

Six sections:

1. **What is machine-checked here** — a table built from *this build's* data: the
   toolchain, the axiom audit's findings, the structural graph gates, and the
   comparator verdict with its explicit scope. Nothing is restated from
   `formalization.yaml`; every row is either run evidence or marked absent. Where the
   build carries a registry surface, a closing paragraph says what a Palomar
   registration establishes (a digest identity) and what it does not (a verification).
2. **What is not machine-checked** — chiefly the informal↔formal correspondence,
   which is a human obligation no part of this stack discharges, plus the
   rendering-tier legend and the source-link caveats.
3. **What you are trusting** — the concrete artifacts, by revision where known.
4. **Why independent verification, and its limits** — including the 2026 Lean
   kernel soundness bug and the fact that a stale second checker shared it.
5. **Verifier currency** — the policy, and the honest gap that remains.
6. **How this exposition was produced** — the automation disclosure from
   `formalization.yaml`'s `automation` section plus the consumer's own note.

Follows the `blueprint_formalization` pattern: its own numberless part, emitted
wherever the command appears, with a `TraversalIndex` slot so the trust strip,
comparator page, and PM hub link it by resolved anchor rather than a guessed slug.
The part title is exactly **"Trust model"** (the emitted route is `Trust-model/`).
-/

namespace Informal.Commands

open Lean Elab Command
open Verso Doc Html Genre Manual
open Verso.Output.Html

/-- Block payload for `Block.trustModel`. The live trust/audit/graph data is read
from the traversal state at render time; only the elaboration-time extras travel
here. -/
structure TrustModelData where
  /-- Consumer-supplied disclosure about how the *prose* on this site was produced
  (`(proseDisclosure := "…")`). Rendered verbatim in section 6, after whatever
  `formalization.yaml`'s `automation` section says about the *formalization*. Empty
  ⇒ omitted. -/
  proseDisclosure : String := ""
  /-- The `automation` section of the project's `formalization.yaml`, as compressed
  JSON, captured at elaboration (the page cannot read files at render time).
  `"null"` ⇒ the project declares no automation. -/
  automationJson : String := "null"
  /-- Lean toolchain the site was built with (`Lean.versionString`), captured at
  elaboration. -/
  leanVersion : String := ""
  /-- Mathlib revision from the consumer's `lake-manifest.json`, when resolvable.
  Empty ⇒ the page points at the manifest instead of naming a revision. -/
  mathlibRev : String := ""
  /-- Whether `verso.blueprint.math.lint` is on for this build. A reader deserves to
  know whether the KaTeX check ran at all. -/
  mathLintEnabled : Bool := false
deriving Inhabited, FromJson, ToJson, Quote

def trustModelCss := include_str "trust-model.css"

private def trustModelSummaryCss := include_str "summary.css"

/-- The page reuses the summary badge classes and the trust-page section shell. -/
def trustModelAssetBundle : BlueprintAssetBundle :=
  blueprintCssAssetBundle [trustModelSummaryCss, trustModelCss]

/-! ### Rendering helpers -/

private def section' (title : String) (body : Array Output.Html) : Output.Html :=
  {{
    <section class="bp_trust_section bp_trustmodel_section">
      <h2 class="bp_trust_section_title">{{.text true title}}</h2>
      {{body}}
    </section>
  }}

private def prose (text : String) : Output.Html :=
  {{ <p class="bp_trust_prose">{{Informal.NodeCard.withCodeSpans text}}</p> }}

private def outLink (href label : String) : Output.Html :=
  {{ <a class="bp_trust_out_link" href={{href}} target="_blank" rel="noopener">{{.text true label}}</a> }}

/-- One row of the machine-checked table: what was checked, the verdict badge, and
what the verdict does *not* cover. -/
private def checkRow (what : String) (verdict : Output.Html) (detail : String) : Output.Html :=
  {{
    <tr>
      <td class="bp_trustmodel_what">{{.text true what}}</td>
      <td class="bp_trustmodel_verdict">{{verdict}}</td>
      <td class="bp_trustmodel_detail">{{Informal.NodeCard.withCodeSpans detail}}</td>
    </tr>
  }}

private def notCheckedBadge : Output.Html :=
  trustBadgeHtml "not checked" "warn"

/-- A statement closure this build computed, if any — the single-pair comparator's first,
otherwise the first topic that has one. One is enough: this page describes what the
closure surface *is*, and the per-claim particulars belong on the comparator page beside
the claim they are about. -/
private def closureOnTrustData? (trust? : Option TrustData) : Option StatementClosure := do
  let trust ← trust?
  match trust.comparator.bind (·.closure?) with
  | Option.some c => Option.some c
  | Option.none => (trust.comparators.findSome? (·.comparator.closure?))

/-! ### Section 1 — what this build actually checked -/

/--
What a Palomar registration establishes on this site, and what it does not.

The page enumerates machine-established evidence and human-asserted evidence, and a
registry record is neither of the things a reader will assume on sight: a claim-bound
match *is* machine-established, but what it establishes is a digest identity with an
immutable third-party snapshot, not a second verification. Said here rather than only on
the cards, because this is the page a reader comes to for the boundary.

Rendered only where the build actually carries a registry surface — matched records, or a
permalink the consumer supplied. A site with no registration has nothing to qualify, and
inventing a row about an absent surface would be the same defect in the other direction.
-/
private def registryProse (trust? : Option TrustData) : Output.Html :=
  match trust? with
  | Option.none => .empty
  | Option.some trust =>
    let claimBound := trust.claimRegistryEntries
    if claimBound.isEmpty && trust.registryEntry?.isNone && trust.registryLink.isEmpty then
      .empty
    else
      let boundLine :=
        match claimBound with
        | [] =>
          "No record this build matched is bound to a claim this page presents; what it \
           matched is weaker, and is described below."
        | [_] => "One record is bound to a claim this page presents."
        | es => s!"{es.length} records are bound to claims this page presents."
      .seq #[
        {{ <h3 class="bp_trustmodel_subtitle">"Registry records"</h3> }},
        prose
          s!"A Palomar registration is a record that a project was submitted at one revision \
             and that the registry accepted it. {boundLine} A bound match is a digest \
             identity and nothing beyond one: the record's immutable `challenge_sha256` \
             equals the digest of the challenge statement displayed here, and the verifying \
             run recorded that same digest — so the record and the claim are demonstrably \
             about the same bytes.",
        prose
          s!"{Informal.Palomar.honestyNote} Nothing in a registration re-ran the kernel or \
             the comparator, and this build did not either; it compared digests. A weaker \
             row says less again: a match on the repository alone, or on a digest the \
             verifying run never recorded, is provenance about the project and is bound to \
             no statement on this page, and a registry permalink the site's author pasted in \
             was not checked at all — nothing established that the record behind it exists, \
             describes this project, or concerns any claim here. Those appear as cards on \
             the statement comparator page, never as a verdict."]

private def machineCheckedSection (data : TrustModelData) (trust? : Option TrustData)
    (checks : Informal.GraphChecks.Results) (autoDepsActive : Bool) : Output.Html :=
  let audit? := trust?.bind (·.audit?)
  let cmp? := trust?.bind (·.comparator)
  -- Kernel / toolchain.
  --
  -- This row used to badge "every declaration" unconditionally. It cannot: the site
  -- renders Lean it never elaborated — the comparator page's claim and solution blocks
  -- are files read verbatim and coloured syntactically, with no dependency edge forcing
  -- them through the kernel — and an unconditional green badge over that is a coverage
  -- claim the build does not support. The row is now measured from the same audit data as
  -- the axiom row, and names its own exclusions.
  let kernelExclusion :=
    " Excluded: code shown with the `≈` (syntactic) or `⌁` (raw) marker — including the \
      statement comparator page's claim and solution blocks — is source text this build read \
      and coloured, not source it elaborated. Nothing in this row covers those blocks; their \
      evidence is the comparator verdict, with its own date. See the rendering-tier legend \
      below."
  let kernelNotMeasured :=
    checkRow "Kernel type-checking" notCheckedBadge
      ("This build enumerated no declarations (no dashboard block, so nothing walked the \
        environment), so no kernel-coverage count can be shown. Whatever this site imported \
        was necessarily elaborated to be imported, but that is not a measurement and this \
        row will not present it as one." ++ kernelExclusion)
  let kernelRow :=
    match audit? with
    | Option.some a =>
      if a.ran then
        checkRow "Kernel type-checking"
          (trustBadgeHtml
            (if a.checked == 1 then "1 declaration" else s!"{a.checked} declarations") "success")
          (s!"The {a.checked} declaration(s) this build enumerated — those wired to blueprint \
              nodes, plus every declaration the registry finds in the project's own modules — \
              were present in the environment this site was generated from, so the Lean \
              {data.leanVersion} kernel accepted them during this build. That is a check of \
              the proofs, not of whether the statements say what you want." ++ kernelExclusion)
      else kernelNotMeasured
    | Option.none => kernelNotMeasured
  -- Axiom audit.
  let auditRow :=
    match audit? with
    | Option.none =>
      checkRow "Axiom audit" notCheckedBadge
        "No axiom audit ran for this build (the site carries no dashboard block, so \
         `Lean.collectAxioms` was never invoked). Treat any sorry-freedom claim elsewhere on \
         this site as author-asserted."
    | Option.some a =>
      if !a.ran then
        checkRow "Axiom audit" notCheckedBadge
          "The audit found no declarations in scope, so nothing was checked."
      else if !a.sorried.isEmpty then
        checkRow "Axiom audit"
          (trustBadgeHtml s!"{a.sorried.size} incomplete" "error")
          s!"`Lean.collectAxioms` over {a.checked} declarations found `sorryAx` in the \
             transitive closure of {a.sorried.size} of them. Those proofs are incomplete, \
             directly or through a helper."
      else if !a.nonstandard.isEmpty then
        checkRow "Axiom audit"
          (trustBadgeHtml s!"{a.nonstandard.size} nonstandard" "warn")
          s!"`Lean.collectAxioms` over {a.checked} declarations found no `sorryAx`, but \
             {a.nonstandard.size} declaration(s) depend on axioms beyond propext, \
             Classical.choice, and Quot.sound."
      else
        checkRow "Axiom audit"
          (trustBadgeHtml s!"{a.checked} clean" "success")
          s!"`Lean.collectAxioms` over {a.checked} declarations: no `sorryAx` anywhere in any \
             transitive closure, and no axiom beyond propext, Classical.choice, and \
             Quot.sound. This subsumes transitive sorry detection — a theorem invoking a \
             sorried lemma is caught even though its own body is clean."
  -- Structural graph gates.
  let graphRow :=
    if checks.graphEmpty then
      checkRow "Dependency-graph structure" notCheckedBadge
        "This document renders no dependency graph, so the structural gates had nothing to \
         check."
    else
      let verdict :=
        if checks.acyclic.ok && checks.connected.ok then
          trustBadgeHtml "acyclic, connected" "success"
        else if checks.acyclic.ok then
          trustBadgeHtml s!"{checks.connected.componentCount} components" "warn"
        else trustBadgeHtml "cyclic" "error"
      let edgeProvenance :=
        if autoDepsActive then
          " The *edges themselves* are machine-derived from the Lean terms — the project's \
            const-level dependency graph — with any hand-authored `uses` edges merged in; \
            see below."
        else
          " The *edges themselves* are author-asserted — see below."
      checkRow "Dependency-graph structure" verdict
        (s!"The authored `uses` graph ({checks.acyclic.nodeCount} nodes, \
           {checks.acyclic.edgeCount} {if checks.acyclic.edgeCount == 1 then "edge" else "edges"}) \
           was gated before this site was written: no \
           dependency cycle, no unresolvable `uses` label." ++ edgeProvenance)
  -- Comparator.
  let comparators := (trust?.map (·.comparators)).getD []
  let comparatorRow :=
    if !comparators.isEmpty then
      -- Multi-config trust surface: aggregate across the configured topics.
      let m := comparators.length
      let k := (comparators.map (·.comparator.theoremNames.length)).foldl (· + ·) 0
      let verifiedCount := (comparators.filter (·.comparator.status == "verified")).length
      let verdict :=
        if verifiedCount == m then
          trustBadgeHtml (if k == 1 then "1 theorem" else s!"{k} theorems") "success"
        else trustBadgeHtml s!"{verifiedCount}/{m} configs" "warn"
      checkRow "Independent statement comparator" verdict
        s!"A CI run reported that each solution proves exactly its named challenge \
           statement(s), across {m} comparator {if m == 1 then "config" else "configs"} \
           ({k} certified {if k == 1 then "theorem" else "theorems"} in total). This page reads \
           those runs' artifacts back; it does not re-run the checks. Scope is the named \
           theorems only — everything else here is built and audited but not \
           comparator-certified."
    else match cmp? with
    | Option.none =>
      checkRow "Independent statement comparator" notCheckedBadge
        "This project configures no statement comparator, so no theorem here has been \
         independently re-checked against a separately-elaborated challenge statement."
    | Option.some cmp =>
      let k := cmp.theoremNames.length
      let verdict :=
        if cmp.status == "verified" then
          trustBadgeHtml (if k == 1 then "1 theorem" else s!"{k} theorems") "success"
        else trustBadgeHtml cmp.status "warn"
      let toolNote :=
        if !cmp.toolSha.isEmpty then s!" using comparator {cmp.toolSha}"
        else if !cmp.toolRef.isEmpty then s!" using comparator {cmp.toolRef} (a mutable tag)"
        else ""
      checkRow "Independent statement comparator" verdict
        s!"A CI run{toolNote} reported that the solution proves exactly the named challenge \
           statement(s). This page reads that run's artifact back; it does not re-run the \
           check. Scope is the named theorems only — everything else here is built and \
           audited but not comparator-certified."
  -- Math lint.
  let lintRow :=
    if data.mathLintEnabled then
      checkRow "Mathematical notation (KaTeX)"
        (trustBadgeHtml "enabled" "success")
        "Every inline and display formula was parsed by KaTeX at build time. This checks that \
         the notation renders, not that it is mathematically apt."
    else
      checkRow "Mathematical notation (KaTeX)" notCheckedBadge
        "KaTeX validation is disabled for this build (`verso.blueprint.math.lint`), so \
         malformed formulas would not have been reported."
  section' "What is machine-checked here" #[
    prose
      "Everything in this table is a property of the build that produced the page you are \
       reading. Nothing here is copied from a metadata file; where a check did not run, the \
       row says so rather than being omitted.",
    {{
      <div class="bp_trustmodel_table_wrap">
        <table class="bp_trustmodel_table">
          <thead><tr><th>"Check"</th><th>"This build"</th><th>"What it does not cover"</th></tr></thead>
          <tbody>{{.seq #[kernelRow, auditRow, graphRow, comparatorRow, lintRow]}}</tbody>
        </table>
      </div>
    }},
    registryProse trust?
  ]

/-! ### Section 2 — the limits -/

private def tierLegendRow (glyph label explanation : String) : Output.Html :=
  {{
    <tr>
      <td class="bp_trustmodel_glyph">{{.text true glyph}}</td>
      <td class="bp_trustmodel_what">{{.text true label}}</td>
      <td class="bp_trustmodel_detail">{{Informal.NodeCard.withCodeSpans explanation}}</td>
    </tr>
  }}

private def notMachineCheckedSection (trust? : Option TrustData) (autoDepsActive : Bool) :
    Output.Html :=
  -- CX-033: the edge-provenance subsection tells the truth for this build's graph
  -- mode. With autoDeps (`includeAllDecls`) the rendered edges are machine-derived
  -- from the Lean terms, so the "author's mental model" caveat does not apply; only
  -- the hand-authored case gets the author-asserted wording.
  let edgeSubtitle : String :=
    if autoDepsActive then "Machine-derived dependency edges" else "Authored dependency edges"
  let edgeProse : Output.Html :=
    if autoDepsActive then
      prose
        "The dependency graph's edges are derived from the Lean terms: for each declaration \
         they come from the constants it actually mentions (statement and proof), read from the \
         elaborated environment during this build, with any hand-authored `uses` edges merged \
         in and winning on conflict. So the graph is a faithful picture of the code's \
         term-level dependency structure rather than the author's assertion. The one caveat is \
         that a term-level dependency is not the same as a mathematical one: the Lean proof may \
         reach a fact by a different route than the informal argument, so read the graph as the \
         code's dependencies, not the narrative's."
    else
      prose
        "The dependency graph's edges are declared by the author with `uses`, not derived from \
         the Lean terms. The build gates their structure (no cycles, no dangling labels) and \
         compares them against the constants each declaration actually mentions, reporting \
         divergence as a build warning — but an edge that exists only in the author's mind, or a \
         real dependency the author did not draw, is a presentation defect the gates do not \
         reject."
  let edgeNote : Output.Html :=
    match trust?.bind (·.edgeAudit?) with
    | Option.none => .empty
    | Option.some e =>
      if e.nodesChecked == 0 then .empty
      else
        {{
          <p class="bp_trust_note">
            {{.text true
              s!"This build compared {e.nodesChecked} node(s) against their Lean terms: \
                 {e.inferredUndeclared.size} dependency edge(s) present in the code are not \
                 drawn in the graph, and {e.declaredNotInferred.size} drawn edge(s) do not \
                 appear in the code (informal-level edges — a mathematical dependency the \
                 Lean proof reaches by another route)."}}
          </p> }}
  -- The closure surface does not move the unmovable step; it measures it. Said here, in
  -- the section that admits the step exists, and only when a closure was actually
  -- computed — a site without the surface reads exactly as it did before.
  let closureProse : Output.Html :=
    match closureOnTrustData? trust? with
    | Option.none => .empty
    | Option.some c =>
      let boundClause :=
        if c.provenance == "chain" then
          "For each certified claim, the comparator page lists the declarations that \
           statement's meaning depends on — computed from the exact challenge files the \
           verifying run recorded, elaborated in a fresh environment holding only their \
           declared imports, and marked as bound to that run only when the bytes match \
           digest for digest."
        else if c.provenance == "chain-unbound" then
          "For each certified claim, the comparator page lists the declarations that \
           statement's meaning depends on. That list is computed from the challenge files \
           as they stand in this build, and nothing ties them to the run the verdict came \
           from; the page says so where the list is."
        else if c.provenance == "claim-decls" then
          "For each certified claim, the comparator page lists the declarations a statement's \
           meaning depends on. Here that list was computed from subject declarations the \
           project's manifest aligned with the certified statements rather than from the \
           challenge file itself, which is a weaker thing, and the page says so where the \
           list is."
        else
          "The comparator page is configured to list, for each certified claim, the \
           declarations that statement's meaning depends on; it reports there why it could \
           not."
      .seq #[
        prose boundClause,
        prose
          "That list does not check the correspondence and cannot. What it does is put a \
           number on the step above: it says how much reading the unmovable residue actually \
           is, and which declarations it consists of. A short list means the statement can \
           be checked in a sitting; a long one means checking it is a real piece of work \
           that has not been done for you. Reaching the site's configured cap is reported as \
           an incomplete list rather than as a count, because a lower bound and a total are \
           not the same claim."]
  -- The caveat surface belongs in the same section for the same reason: it is about
  -- reading the statement, and it is emphatically not a check. Rendered only where a scan
  -- actually ran, and worded so that neither a hit nor a silence reads as a verdict.
  let caveatProse : Output.Html :=
    match (trust?.bind (·.comparator)).bind (·.caveats?) with
    | Option.none => .empty
    | Option.some scan =>
      if scan.status.isEmpty then .empty
      else
        .seq #[
          {{ <h3 class="bp_trustmodel_subtitle">"Known caveat patterns"</h3> }},
          prose
            "Lean's functions are total, so an expression that looks undefined has a value \
             anyway: `a - b` on the naturals is `0` when `b` exceeds `a`, `x / 0` is `0`, the \
             cardinality of an infinite set is `0`. A statement can therefore be true for a \
             reason its reader did not intend. The comparator page lists the symbols of this \
             kind that occur in what each certified statement means.",
          prose
            s!"That list is not a finding of error, and it is not exhaustive. It is matched \
               against a partial hand-maintained table (version {scan.tableVersion}, digest \
               {scan.tableDigest}); a symbol the table does not list is a symbol nobody \
               looked for, and a scan that matched nothing has established nothing. Where a \
               row reports that a guard-shaped hypothesis occurs, that is a presence check \
               over the statement's binders: it did not relate the hypothesis to the flagged \
               operand, and no row anywhere says a statement is guarded."]
  section' "What is not machine-checked" #[
    {{ <h3 class="bp_trustmodel_subtitle">"The informal ↔ formal correspondence"</h3> }},
    prose
      "This is the important one. Every node on this site places an informal statement beside \
       a Lean declaration, and nothing anywhere in this stack checks that the two say the same \
       thing. The side-by-side layout is an affordance for human audit — it puts the prose and \
       the code where you can compare them — not a verification of their agreement. The same \
       applies with more force to informal proofs: a `:::proof` block is free prose with no \
       relation to the Lean proof term beside it.",
    prose
      "If the Lean statement is a faithful rendering of the informal one, then the machine \
       checks above tell you the theorem is proved. If it is not, they tell you nothing you \
       care about. Reading the formal statement is the step that cannot be delegated.",
    closureProse,
    caveatProse,
    {{ <h3 class="bp_trustmodel_subtitle">{{.text true edgeSubtitle}}</h3> }},
    edgeProse,
    edgeNote,
    {{ <h3 class="bp_trustmodel_subtitle">"How the Lean code on this page was rendered"</h3> }},
    prose
      "Code blocks are produced by different pipelines, and they do not carry the same \
       evidence. Each block is marked in its top-right corner:",
    {{
      <div class="bp_trustmodel_table_wrap">
        <table class="bp_trustmodel_table">
          <tbody>{{.seq #[
            tierLegendRow "⟲" "Re-elaborated from source"
              "The declaration was elaborated again from the project's source text during the \
               site build, so its tokens carry checked semantic information and its layout is \
               exactly what the author wrote.",
            tierLegendRow "≈" "Signature-only, or syntactic"
              "Either the statement alone was re-elaborated (the proof was not re-run), or the \
               text was parsed and coloured without elaboration. Token meanings are not \
               checked.",
            tierLegendRow "⌁" "Pretty-printed or raw"
              "Rendered from the compiled declaration rather than the source file, or shown as \
               plain text. Layout, notation, and implicit arguments may differ from the file \
               you would read on GitHub.",
            tierLegendRow "!" "Source newer than the compiled build"
              "The source file changed after the artifact the status was read from was \
               compiled, so the displayed text and the reported status may disagree."]}}
          </tbody>
        </table>
      </div>
    }},
    prose
      "A downgrade between tiers happens silently — a re-elaboration can exceed its time \
       budget, or reference names that are not in scope outside their module. Marking the \
       tier is what makes that visible.",
    {{ <h3 class="bp_trustmodel_subtitle">"Source links"</h3> }},
    prose
      "\"View source\" links point at the commit the site was built from. They are constructed \
       from the local git checkout, so if that checkout had uncommitted changes the link \
       resolves to a commit that is not quite what was built; the build stamp marks such a \
       build as dirty."
  ]

/-! ### Section 3 — the trusted base -/

private def trustingSection (data : TrustModelData) (trust? : Option TrustData) : Output.Html :=
  let cmp? := trust?.bind (·.comparator)
  let item (label detail : String) : Output.Html :=
    {{ <li><strong>{{.text true label}}</strong>" — "{{.text true detail}}</li> }}
  let mathlibItem :=
    if data.mathlibRev.isEmpty then
      item "Mathlib" "at the revision recorded in this project's lake-manifest.json."
    else
      item "Mathlib" s!"at revision {data.mathlibRev}, together with everything Mathlib itself \
        depends on."
  let comparatorItems : Array Output.Html :=
    match cmp? with
    | Option.none => #[]
    | Option.some cmp =>
      let toolItem :=
        if !cmp.toolSha.isEmpty then
          #[item "The statement comparator" s!"at commit {cmp.toolSha}, and the GitHub Actions \
              runner that executed it."]
        else if !cmp.toolRef.isEmpty then
          #[item "The statement comparator"
              s!"at tag {cmp.toolRef} — a mutable reference: the tag can be moved, and no \
                 commit hash was recorded, so \"the tool CI ran\" is not pinned down."]
        else #[]
      -- Run evidence, not configuration: a project that switches the independent kernel
      -- on today does not thereby add nanoda to what a past verdict rested on.
      -- The semantic accessor, never the raw compatibility field: one canonical record
      -- means every surface names the same revision.
      let nanodaRef := cmp.recordedKernelRef "nanoda"
      let nanodaItem :=
        if cmp.replayedWithNanoda && !nanodaRef.isEmpty then
          #[item "nanoda" s!"at revision {nanodaRef}, as the independent kernel the run \
              recorded."]
        else #[]
      -- Confinement is claimed only for the step the record covers. Elaborating Lean runs
      -- arbitrary code, so the first elaboration of the untrusted solution is the
      -- security-relevant moment, and the status artifact does not say whether it happened
      -- inside the sandbox or in an earlier prebuild step.
      let landrunItem :=
        if cmp.landrunRef.isEmpty then #[]
        else #[item "landrun" s!"at revision {cmp.landrunRef}, as the sandbox the comparator \
                 replay ran under. That covers the replay; if CI built the solution before \
                 invoking the comparator, the solution's first elaboration — which is \
                 arbitrary code execution — happened outside the sandbox, and the run record \
                 does not distinguish the two orders."]
      toolItem ++ nanodaItem ++ landrunItem
  section' "What you are trusting" (#[
    prose
      "The checks above are only as good as the things that performed them. Concretely, this \
       site asks you to trust:",
    {{
      <ul class="bp_trustmodel_list">
        {{item "The Lean kernel" s!"version {data.leanVersion} — the program that accepted \
           every proof here. See the next section on why that is not a closed question."}}
        {{mathlibItem}}
        {{.seq comparatorItems}}
        {{item "GitHub Actions" "as the environment the verification ran in, and its logs as an \
           honest record of what happened there."}}
        {{item "GitHub Pages" "as the host serving these files unmodified."}}
      </ul>
    }}
  ])

/-! ### Section 4 — why independence, and its limits -/

private def independenceSection : Output.Html :=
  section' "Why independent verification — and what it does not settle" #[
    prose
      "A proof accepted by the Lean kernel is accepted by one program. If that program has a \
       soundness bug, everything it accepted inherits it. Re-checking the same proof with a \
       second, independently written kernel is the standard defence: two implementations are \
       unlikely to share a bug.",
    prose
      "That defence is weaker than it sounds, and 2026 showed exactly how. A kernel soundness \
       bug (Lean issue #14576) was found by way of an AI-assisted \"disproof\" of the Collatz \
       conjecture that the kernel accepted. The same artifact was replayed against nanoda, an \
       independent reimplementation — and nanoda accepted it too, not because the two share a \
       design, but because the nanoda build being used was a week old and had its own, \
       separate bug. Two independent checkers agreed, and both were wrong.",
    prose
      "The lesson is that independence and currency are different properties, and you need \
       both. A second kernel pinned to a revision from before a soundness fix is a second \
       opinion from the past.",
    {{
      <p class="bp_trust_prose_links">
        {{outLink "https://github.com/leanprover/lean4/issues/14576" "Lean issue #14576"}}
        " · "
        {{outLink "https://lean-lang.org/doc/reference/latest/ValidatingProofs" "Validating proofs (Lean reference)"}}
      </p>
    }}
  ]

/-! ### Section 5 — verifier currency

Driven by the same assessments the comparator page renders (`TrustComparator.currency`,
computed at elaboration from the recorded revisions against the fork's advisory table), so
the two surfaces cannot disagree about whether a pin is current. One line per verifier
build any verdict on this site names — every comparator config, not only the first — and
the self-aging clause under all of them, because a verdict read off a hand-maintained
table is a claim about the table.
-/

/-- Every currency assessment this site computed, labelled by the config that produced it
(empty label ⇒ the single-pair surface, which has no topic name). -/
private def currencyRowsOf (trust? : Option TrustData) : Array (String × VerifierCurrency) :=
  match trust? with
  | Option.none => #[]
  | Option.some trust =>
    let single : Array (String × VerifierCurrency) :=
      match trust.comparator with
      | Option.some cmp => cmp.currency.map fun r => ("", r)
      | Option.none => #[]
    trust.comparators.foldl (init := single) fun acc topic =>
      acc ++ topic.comparator.currency.map fun r => (topic.name, r)

private def currencySection (trust? : Option TrustData) : Output.Html :=
  let rows := currencyRowsOf trust?
  let comparators : List TrustComparator :=
    match trust? with
    | Option.none => []
    | Option.some trust =>
      (trust.comparator.toList) ++ trust.comparators.map (·.comparator)
  -- Which Lean release a run's kernel was is recorded in one place only: the comparator's
  -- own toolchain field. A record without it leaves the primary kernel's currency
  -- unassessable, which is a gap worth naming rather than an absence worth passing over.
  let toolchainRecorded := comparators.any fun c => !c.toolToolchain.isEmpty
  -- The payload's own field, not a row's: the clause that ages the table is exactly what
  -- a page with nothing to assess still owes the reader.
  let advisoriesUpdated :=
    let fromPayload := (trust?.map (·.advisoriesUpdated)).getD ""
    if fromPayload.isEmpty then ((rows[0]?).map (·.2.advisoriesUpdated)).getD ""
    else fromPayload
  let item (label detail : String) : Output.Html :=
    {{ <li><strong>{{.text true label}}</strong>" — "{{.text true detail}}</li> }}
  let verdictWord (r : VerifierCurrency) : String :=
    if r.verdict == "stale" then "not current" else r.verdict
  let rowItems : Array Output.Html := rows.map fun (topic, r) =>
    let label :=
      let tool := if r.tool == "lean4" then "Lean toolchain" else r.tool
      if topic.isEmpty then s!"{tool}: {verdictWord r}"
      else s!"{tool} ({topic}): {verdictWord r}"
    item label r.detail
  let assessed : Array Output.Html :=
    if rows.isEmpty then
      #[prose
          (if comparators.isEmpty then
            "This site publishes no statement-comparator verdict, so there is no recorded \
             verifier build here whose currency could be assessed."
           else
            "No verdict on this site records a verifier build to assess: no revision for an \
             independent kernel, and no Lean release for the comparator that produced the \
             verdict. A configuration that enables a second kernel is not such a record — it \
             describes the next run — so there is nothing here whose currency this site could \
             check."),
        {{ <p class="bp_trust_note">{{.text true (currencyAgingClause advisoriesUpdated)}}</p> }}]
    else
      #[prose
          "Against the advisories this site records, the builds behind its verdicts stand as \
           follows. `current` means the recorded revision is one the table resolves as \
           carrying every fix it knows of; `unknown` means the table settled nothing, in \
           either direction, and is not a clean bill.",
        {{ <ul class="bp_trustmodel_list">{{.seq rowItems}}</ul> }},
        {{ <p class="bp_trust_note">{{.text true (currencyAgingClause advisoriesUpdated)}}</p> }}]
  let gap :=
    let toolchainGap :=
      if toolchainRecorded then ""
      else
        " no verdict here records which Lean release the comparator was built on, so the \
         currency of the primary kernel — the one that accepted every proof on this site — \
         cannot be assessed at all;"
    s!"Known gap: no scheduled re-verification job;{toolchainGap} no binding between a \
       displayed verdict and a specific CI run beyond the recorded URL; and the advisory \
       table above is maintained by hand rather than tracked from upstream."
  section' "Verifier currency" (#[
    prose
      "Pinning a verifier by revision and keeping a verifier current are in tension. A pinned \
       verifier gives a reproducible result: anyone can re-run exactly what CI ran. A current \
       verifier gives a result that reflects every soundness fix known today. A single run \
       cannot do both.",
    prose
      "So the pin is reported, and then measured against a list of soundness advisories this \
       fork maintains by hand. A revision the list resolves as carrying every fix is current; \
       a revision it resolves as predating one is not, whatever date the run carries; and a \
       revision it cannot place — or a checker the record never bound to a program — is \
       unknown, which is a fact about this list rather than about the verifier."
  ] ++ assessed ++ #[
    prose
      "The policy this project follows is to pin for reproducibility and to re-verify against \
       current tooling on a schedule, reporting both. The scheduled re-verification is not yet \
       implemented — the verdict shown on this site is a pinned one only, and nothing here \
       re-checks it against today's kernels. This is tracked as future work rather than \
       presented as done.",
    {{ <p class="bp_trust_note">{{.text true gap}}</p> }}
  ])

/-! ### Section 6 — how this was produced -/

private def automationSection (data : TrustModelData) : Output.Html :=
  let doc := (Json.parse data.automationJson).toOption.getD Json.null
  let strField? := fun (j : Json) (k : String) =>
    match (j.getObjVal? k).toOption with
    | Option.some (Json.str s) =>
      if s.trimAscii.toString.isEmpty then Option.none else Option.some s
    | _ => Option.none
  let methods : Array Json :=
    match (doc.getObjVal? "methods").toOption with
    | Option.some (Json.arr a) => a
    | _ => #[]
  let methodItems : Array Output.Html := methods.map fun m =>
    let name := (strField? m "method").getD "automated method"
    let framework := (strField? m "framework").map (fun f => s!" ({f})") |>.getD ""
    let models :=
      match (m.getObjVal? "models").toOption with
      | Option.some (Json.arr a) =>
        let names := a.filterMap fun v => match v with | Json.str s => some s | _ => none
        if names.isEmpty then "" else s!" — models: {String.intercalate ", " names.toList}"
      | _ => ""
    {{ <li>{{.text true s!"{name}{framework}{models}"}}</li> }}
  let formalizationPart : Array Output.Html :=
    if methodItems.isEmpty then
      #[prose
          "This project's formalization.yaml declares no automation, so the Lean development \
           here is recorded as human-written."]
    else
      #[prose
          "This project's formalization.yaml records that parts of the Lean development were \
           produced with automated assistance:",
        {{ <ul class="bp_trustmodel_list">{{methodItems}}</ul> }},
        prose
          "Automated or not, every declaration went through the same kernel and the same audit \
           as the rest of the site. Automation changes who wrote the proof, not what checked it."]
  let prosePart : Array Output.Html :=
    if data.proseDisclosure.trimAscii.toString.isEmpty then #[]
    else #[
      {{ <h3 class="bp_trustmodel_subtitle">"The exposition"</h3> }},
      prose data.proseDisclosure,
      prose
        "Prose is the one part of this site nothing checks. Read it as commentary on the \
         formal statements, and read the formal statements themselves before relying on them."
    ]
  section' "How this was produced" (formalizationPart ++ prosePart)

/-- Render the whole trust-model page. -/
def renderTrustModel (st : TraverseState) (data : TrustModelData) : Output.Html :=
  let trust? : Option TrustData :=
    (Informal.TraversalIndex.TrustData.raw? st).bind fun j =>
      (fromJson? (α := TrustData) j).toOption
  let checks := Informal.GraphChecks.run (Informal.GraphApi.masterGraph st)
  -- CX-033: the all-declarations registry is written only when
  -- `verso.blueprint.graph.includeAllDecls` is on, which is exactly the mode where
  -- the rendered dependency graph's edges are machine-derived from the Lean
  -- const-level dependencies (autoDeps) rather than hand-authored `uses`. Its
  -- presence in the traversal store is a faithful signal that the graph the reader
  -- sees is machine-derived, so the provenance wording must not call it
  -- "author-asserted".
  let autoDepsActive := (Informal.TraversalIndex.DeclRegistry.raw? st).isSome
  {{
    <div class="bp_trustmodel">
      <p class="bp_trustmodel_lead">
        "This site presents formal mathematics. Some of what it shows you was established by a \
         machine and some of it was asserted by a person, and the two look alike on the page. \
         This is the separation."
      </p>
      {{machineCheckedSection data trust? checks autoDepsActive}}
      {{notMachineCheckedSection trust? autoDepsActive}}
      {{trustingSection data trust?}}
      {{independenceSection}}
      {{currencySection trust?}}
      {{automationSection data}}
    </div>
  }}

open Verso Doc Elab Genre Manual in
block_extension Block.trustModel (data : TrustModelData) where
  data := toJson data
  traverse id _data _contents := do
    let path ← (·.path) <$> read
    let _ ← Verso.Genre.Manual.externalTag id path "--bp-trust-model"
    modify fun st => Informal.TraversalIndex.TrustModelPage.saveId st id
    return none
  toTeX := none
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI _goB _id data _blocks => do
      let some data ← Informal.ExtensionDecode.decode? (α := TrustModelData) data
          (fun err => s!"Malformed data in Block.trustModel.toHtml ({err})")
        | pure .empty
      let st ← HtmlT.state
      pure (renderTrustModel st data)
  extraCss := trustModelAssetBundle.css
  extraJs := trustModelAssetBundle.js

open Verso.ArgParse in
structure BlueprintTrustModelConfig where
  proseDisclosure : Option String := none

open Verso.ArgParse in
instance : FromArgs BlueprintTrustModelConfig Verso.Doc.Elab.PartElabM where
  fromArgs := BlueprintTrustModelConfig.mk <$> .named' `proseDisclosure true

/-- The `mathlib` revision recorded in the consumer's `lake-manifest.json`, if
resolvable. Best-effort: an unreadable or differently-shaped manifest yields `""`
and the page points at the manifest instead of naming a revision. -/
private def mathlibRevFromManifest? : IO String := do
  try
    let path : System.FilePath := "lake-manifest.json"
    unless ← path.pathExists do return ""
    let some j := (Json.parse (← IO.FS.readFile path)).toOption | return ""
    let some (Json.arr pkgs) := (j.getObjVal? "packages").toOption | return ""
    for p in pkgs do
      if (p.getObjValAs? String "name").toOption == some "mathlib" then
        return (p.getObjValAs? String "rev").toOption.getD ""
    return ""
  catch _ =>
    return ""

open Verso Doc Elab Syntax in
def mkTrustModelPart (stx : Syntax) (endPos : String.Pos.Raw) (data : TrustModelData) :
    PartElabM FinishedPart := do
  -- The title is load-bearing: the emitted route is derived from it (`Trust-model/`)
  -- and consumers' CI gates test for that path.
  let titlePreview := "Trust model"
  let titleInlines ← `(inline | "Trust model")
  let expandedTitle ← #[titleInlines].mapM (elabInline ·)
  let metadata : Option (TSyntax `term) := some (← `(term| { number := false }))
  let block ← ``(Verso.Doc.Block.other
    (Informal.Commands.Block.trustModel $(quote data)) #[])
  pure <| FinishedPart.mk stx stx expandedTitle titlePreview metadata #[block] #[] endPos

open Verso Doc Elab Syntax PartElabM in
@[part_command Lean.Doc.Syntax.command]
public meta def blueprintTrustModelCmd : PartCommand
  | stx@`(block|command{blueprint_trust_model $args*}) => do
    let cfg ← Verso.ArgParse.parseThe BlueprintTrustModelConfig (← parseArgs args)
    let opts ← Lean.getOptions
    -- The `automation` section of formalization.yaml, when the project configures one.
    let automationJson : String ←
      match ← elabFormalizationDoc? with
      | Option.none => pure "null"
      | Option.some doc =>
        match (doc.getObjVal? "automation").toOption with
        | Option.some a => pure a.compress
        | Option.none => pure "null"
    let data : TrustModelData := {
      proseDisclosure := cfg.proseDisclosure.getD ""
      automationJson
      leanVersion := Lean.versionString
      mathlibRev := ← mathlibRevFromManifest?
      mathLintEnabled := Informal.MathLint.enabled opts
    }
    let endPos := stx.getTailPos?.get!
    closePartsUntil 1 endPos
    addPart (← mkTrustModelPart stx endPos data)
  | _ => (Lean.Elab.throwUnsupportedSyntax : PartElabM Unit)

end Informal.Commands
