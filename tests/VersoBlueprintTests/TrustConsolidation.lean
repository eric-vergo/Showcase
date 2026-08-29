/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint
import TrustAuditFixture
import VersoBlueprintTests.Blueprint.Support
import VersoManual

/-!
One fact, one surface.

The same soundness facts used to be asserted several times per site, from one
computation, in wording that drifted between the copies: the axiom audit rendered as a
strip badge, a trust-model row and two blocks on the audit page; the comparator's scope
sentence appeared on the strip and on the comparator page; verifier currency was assessed
on the trust-model page and on the comparator page. Each duplicate is a place the story
can go wrong on its own, and two of them were wrong when this consolidation started.

This suite pins where each fact now lives, in every state — including the states that
report *nothing*, which are the ones a consolidation is most likely to make silent:

* the **strip** carries one scope line (comparator coverage · audit outcome) and no axiom
  badge, in six comparator states × the audit's five;
* the **formalization page** renders declared figures as declarations with an explicit
  cross-check annotation, never as verdict badges;
* the **audit page** carries the audit's findings and points at the verdict rather than
  restating it;
* the **trust-model table** is that verdict, and says what the record actually is for a
  status that certified nothing;
* the **comparator page** is the one home of verifier currency.

Plus the coverage bug that made the strict audit gate unusable for an honestly
in-progress project (F3): a *declared* sorry now counts as declared.
-/

namespace Verso.VersoBlueprintTests.TrustConsolidation

open Lean
open Verso Genre Manual
open Informal Informal.Commands
open Verso.VersoBlueprintTests.Blueprint.Support

/-! ## Fixtures -/

private def cleanAudit : Informal.AxiomAudit.Summary :=
  { checked := 312, ran := true }

private def dirtyAudit : Informal.AxiomAudit.Summary :=
  { checked := 312, ran := true, sorried := #["A.foo"], clean := false }

private def nonstandardAudit : Informal.AxiomAudit.Summary :=
  { checked := 312, ran := true, clean := false
    nonstandard := #[{ name := "A.bar", nonstandard := #["A.myAxiom"] }] }

private def bothAudit : Informal.AxiomAudit.Summary :=
  { checked := 312, ran := true, clean := false, sorried := #["A.foo"]
    nonstandard := #[{ name := "A.bar", nonstandard := #["A.myAxiom"] }] }

private def emptyAudit : Informal.AxiomAudit.Summary := { checked := 0, ran := false }

private def cmpOf (status : String) : TrustComparator :=
  { status, verifiedAt := "2026-08-04T00:00:00Z", reportedAt := "2026-07-01T00:00:00Z"
    theoremNames := ["A.thm"] }

/-- The strip as a page renders it: graph checks absent, a trust-model page present, and a
site with 45 theorem-like results. -/
private def strip (t : TrustData) (trustModelHref? : Option String := some "Trust-model/") :
    String :=
  (trustStripHtml t Option.none trustModelHref? (some 45)).asString

/-! ## The strip: one scope line, no axiom badge

Six comparator states. The three that were already right are byte-identical; the three
that were not said "certifies" for a verdict that had certified nothing (F1).
-/

/-- info: true -/
#guard_msgs in
#eval
  let s := fun st => strip { comparator := some (cmpOf st), audit? := some cleanAudit }
  hasSubstr (s "verified") "certifies 1 theorem of 45" &&
  hasSubstr (s "reported-upstream") "reported verified upstream: 1 theorem of 45" &&
  hasSubstr (s "verified-local") "verified locally, not in CI: 1 theorem of 45" &&
  -- F1: configured has not run, and a failing record is a record.
  hasSubstr (s "configured") "configured but not yet run: names 1 theorem of 45" &&
  hasSubstr (s "failed") "recorded with status failed, not certified: names 1 theorem of 45" &&
  hasSubstr (s "error") "recorded with status error, not certified: names 1 theorem of 45" &&
  -- Only the verdict that certified something says so.
  countSubstr (s "configured") "certifies" == 0 &&
  countSubstr (s "failed") "certifies" == 0 &&
  countSubstr (s "reported-upstream") "certifies" == 0

-- The audit's own clause, in every state the payload can be in.
/-- info: true -/
#guard_msgs in
#eval
  let s := fun (a : Option Informal.AxiomAudit.Summary) =>
    strip { comparator := some (cmpOf "verified"), audit? := a }
  hasSubstr (s (some cleanAudit))
    "all 312 audited declarations are kernel-built and axiom-audited: no sorryAx, \
     no axiom beyond propext, Classical.choice, Quot.sound" &&
  hasSubstr (s (some dirtyAudit))
    "312 audited declarations kernel-built and axiom-audited; 1 carries sorryAx in its closure" &&
  hasSubstr (s (some nonstandardAudit))
    "312 audited declarations kernel-built and axiom-audited: no sorryAx, but 1 uses an \
     axiom beyond propext, Classical.choice, Quot.sound" &&
  hasSubstr (s (some bothAudit))
    "312 audited declarations kernel-built and axiom-audited; 1 carries sorryAx in its \
     closure and 1 uses an axiom beyond propext, Classical.choice, Quot.sound" &&
  -- The two states that report nothing say so rather than going quiet: a strip that
  -- omitted the audit when none ran would look the same whether the project was audited
  -- and clean or never audited at all.
  hasSubstr (s (some emptyAudit)) "the axiom audit found no declarations to check" &&
  hasSubstr (s Option.none) "no build-time axiom audit ran" &&
  -- Population wording: the audit enumerates wired + project declarations, which is not
  -- everything the site presents.
  countSubstr (s (some cleanAudit)) "presented declarations" == 0

-- Flag tiers, and the link to the canonical row.
/-- info: true -/
#guard_msgs in
#eval
  let clean := strip { audit? := some cleanAudit }
  let dirty := strip { audit? := some dirtyAudit }
  let nonstd := strip { audit? := some nonstandardAudit }
  let noAudit := strip { comparator := some (cmpOf "verified") }
  let unlinked := strip { audit? := some dirtyAudit } Option.none
  -- A clean audit is quiet; a finding takes an accent token.
  !hasSubstr clean "bp_trust_strip_scope_flag" &&
  hasSubstr dirty "bp_trust_strip_scope_flag_error" &&
  hasSubstr nonstd "bp_trust_strip_scope_flag_warn" &&
  hasSubstr noAudit "bp_trust_strip_scope_flag_warn" &&
  -- The clause links to the trust-model row that carries the badge and the exclusions.
  hasSubstr clean "<a class=\"bp_trust_strip_scope_audit\" href=\"Trust-model/#bp-trust-audit\">" &&
  -- …and when it is flagged, both classes sit on that one `<a>`. The colour comes from
  -- the compound selector `a.bp_trust_strip_scope_audit.bp_trust_strip_scope_flag_*`,
  -- since the link's own `color: inherit` outranks a bare flag class; a flag moved to a
  -- wrapper, or a flag class emitted without the audit class beside it, renders muted.
  -- The cascade is not testable from here — the markup the rule keys on is.
  hasSubstr dirty
    "<a class=\"bp_trust_strip_scope_audit bp_trust_strip_scope_flag_error\" \
     href=\"Trust-model/#bp-trust-audit\">" &&
  hasSubstr nonstd
    "<a class=\"bp_trust_strip_scope_audit bp_trust_strip_scope_flag_warn\" \
     href=\"Trust-model/#bp-trust-audit\">" &&
  -- No trust-model page ⇒ a plain span, not a dead link.
  hasSubstr unlinked "<span class=\"bp_trust_strip_scope_audit" &&
  !hasSubstr unlinked "href=\"Trust-model/"

-- The badge set: comparator (0 or 1), graph, registry. Never an axiom badge, never the
-- two accent cross-links.
/-- info: true -/
#guard_msgs in
#eval
  let s := fun st => strip { comparator := some (cmpOf st), audit? := some dirtyAudit }
  let auditOnly := strip { audit? := some cleanAudit }
  countSubstr (s "verified") "<a class=\"bp_summary_badge" == 1 &&
  countSubstr (s "configured") "<a class=\"bp_summary_badge" == 1 &&
  -- The audit badge is gone in every state, including the two that used to be red/amber.
  countSubstr (s "verified") "axiom audit:" == 0 &&
  countSubstr (s "configured") "axiom audit:" == 0 &&
  countSubstr auditOnly "axiom audit:" == 0 &&
  -- `accent` belongs to the locally-verified tier alone now that the cross-links are gone.
  hasSubstr (s "verified-local") "bp_summary_badge_accent" &&
  !hasSubstr (s "verified") "bp_summary_badge_accent" &&
  !hasSubstr (s "verified") "formalization.yaml" &&
  !hasSubstr (s "verified") "trust model"

-- Render condition. An audit that ran is a signal on its own — the minimal starter, with
-- no comparator and no graph, still gets a strip. Nothing at all still renders nothing.
/-- info: true -/
#guard_msgs in
#eval
  let auditOnly := strip { audit? := some cleanAudit }
  hasSubstr auditOnly "bp_trust_strip" &&
  -- …and no empty badge row taking a gap in the flex layout.
  !hasSubstr auditOnly "<div class=\"bp_summary_badge_row\"></div>" &&
  strip {} == "" &&
  strip { reviewStatus := "agent-reviewed" } == "" &&
  -- An audit that found nothing to check is not a signal by itself.
  strip { audit? := some emptyAudit } == ""

/-! ## The trust-model table: the canonical verdicts

The comparator row summed every topic's theorem names whatever their status and then said
"A CI run reported that each solution proves exactly its named challenge statement(s)" —
on a site where no run had happened. This page is the one a reader comes to for the
boundary, so it uses the same predicate and vocabulary as the strip (CX-042).
-/

private def topicOf (name status : String) (thms : List String) : ComparatorTopic :=
  { name, comparator := { cmpOf status with theoremNames := thms } }

private def tableHtml (t : TrustData) : String :=
  (machineCheckedSection {} (some t) {} false).asString

/-- info: true -/
#guard_msgs in
#eval
  let configured := tableHtml { comparator := some (cmpOf "configured") }
  let upstream := tableHtml { comparator := some (cmpOf "reported-upstream") }
  let verified := tableHtml { comparator := some (cmpOf "verified") }
  hasSubstr configured "but has not run" &&
  !hasSubstr configured "A CI run" &&
  hasSubstr upstream "Transcribed from records published by" &&
  !hasSubstr upstream "A CI run" &&
  -- A transcribed record is provenance, not a fault: neutral tier, not warn.
  hasSubstr upstream "<span class=\"bp_summary_badge\">reported upstream</span>" &&
  hasSubstr verified "A CI run" &&
  -- The tail that asserted the audit's outcome inside the comparator's row is gone from
  -- all three; the audit has its own row directly above.
  !hasSubstr configured "built and audited but not comparator-certified" &&
  !hasSubstr upstream "built and audited but not comparator-certified" &&
  !hasSubstr verified "built and audited but not comparator-certified" &&
  hasSubstr verified "the axiom-audit row above says what the build checked"

-- Multi-topic: one verified of three. The certified count is 2 (the verified topic's
-- names), not 4 (every topic's).
/-- info: true -/
#guard_msgs in
#eval
  let mixed := tableHtml
    { comparators :=
        [topicOf "A" "verified" ["A.t1", "A.t2"],
         topicOf "B" "configured" ["B.t1"],
         topicOf "C" "reported-upstream" ["C.t1"]] }
  let allConfigured := tableHtml
    { comparators :=
        [topicOf "A" "configured" ["A.t1"], topicOf "B" "configured" ["B.t1", "B.t2"]] }
  hasSubstr mixed "across 1 of 3 comparator configs" &&
  hasSubstr mixed "(2 certified theorems in total)" &&
  hasSubstr mixed "configured but not yet run or reported verified upstream" &&
  !hasSubstr mixed "(4 certified theorems in total)" &&
  -- Nothing certified: the row says that, rather than describing a run that never was.
  hasSubstr allConfigured "No CI run recorded here certified anything" &&
  !hasSubstr allConfigured "A CI run reported" &&
  hasSubstr allConfigured "0/2 configs"

-- The rows other surfaces address by fragment.
/-- info: true -/
#guard_msgs in
#eval
  let html := tableHtml { comparator := some (cmpOf "verified"), audit? := some cleanAudit }
  hasSubstr html "id=\"bp-trust-kernel\"" &&
  hasSubstr html "id=\"bp-trust-audit\"" &&
  hasSubstr html "id=\"bp-trust-graph\"" &&
  hasSubstr html "id=\"bp-trust-comparator\""

-- With no audit at all, the audit row names the page whose declared figures a reader
-- would otherwise take for checked ones.
/-- info: true -/
#guard_msgs in
#eval
  hasSubstr (tableHtml {}) "including the declared figures on the formalization-metadata page"

/-! ## The comparator page

Its scope paragraph had the same F1 defect as the strip's, and asserted "axiom-audited"
from a function that never sees the audit (F5). Verifier currency is now rendered here and
only here, once per verdict.
-/

private def pageHtml (cmp : TrustComparator) : String :=
  (comparatorBody cmp (some "https://ci.example/run/1") (some 45) Option.none).asString

/-- info: true -/
#guard_msgs in
#eval
  let configured := pageHtml (cmpOf "configured")
  let failed := pageHtml (cmpOf "failed")
  let verified := pageHtml (cmpOf "verified")
  hasSubstr configured "the comparator is configured but has not run, so nothing here is certified" &&
  !hasSubstr configured "Certifies" &&
  hasSubstr failed "recorded with status 'failed'; not a certification" &&
  !hasSubstr failed "Certifies" &&
  hasSubstr verified "Certifies 1 theorem of the 45" &&
  -- F5: the page states the comparator's scope and points at the build's own record
  -- rather than asserting a computation it does not read.
  !hasSubstr verified "axiom-audited" &&
  !hasSubstr configured "axiom-audited" &&
  hasSubstr verified "what the build itself checked is on the Trust model page"

-- Currency renders once per verdict, on the page that carries the verdict.
/-- info: true -/
#guard_msgs in
#eval
  let withCurrency :=
    ({ cmpOf "verified" with
        nanodaRef := "1111111111111111111111111111111111111111"
        expectedIdentities :=
          #[{ label := "nanoda", repository := "https://github.com/ammkrn/nanoda_lib"
              sourceCommit := "1111111111111111111111111111111111111111" }] }).withCurrency
      Informal.KernelAdvisories.builtinTable
  let html := pageHtml withCurrency
  countSubstr html "class=\"bp_trust_currency\"" == 1 &&
  -- The clause that ages the hand-maintained table travels with the assessment.
  hasSubstr html "Advisory table last updated"

-- Permitted axioms. `[]` is the STRONGEST allowlist a record can state — the certified
-- theorem's closure may contain no axiom at all — and the row used to be omitted for any
-- empty list, so the strongest claim published as silence, indistinguishable from a
-- record that never mentioned axioms. ABSENT is not EMPTY on the reading side either.
/-- info: true -/
#guard_msgs in
#eval
  let ofStatus := fun (j : String) =>
    pageHtml (TrustComparator.ofJson ((Json.parse j).toOption.getD Json.null))
  let stated := ofStatus r##"{"status": "verified", "theorem_names": ["A.thm"],
    "permitted_axioms": []}"##
  let silent := ofStatus r##"{"status": "verified", "theorem_names": ["A.thm"]}"##
  let listed := ofStatus r##"{"status": "verified", "theorem_names": ["A.thm"],
    "permitted_axioms": ["propext"]}"##
  hasSubstr stated "Permitted axioms" &&
  hasSubstr stated "none — the solution may use no axiom at all" &&
  -- A record that never declared the key claims nothing, so the page claims nothing.
  !hasSubstr silent "Permitted axioms" &&
  -- A stated list still renders as the list, and never as the empty-allowlist sentence.
  hasSubstr listed "<code>propext</code>" &&
  !hasSubstr listed "no axiom at all"

/-! ## The audit page: findings, not a second verdict -/

/-- info: true -/
#guard_msgs in
#eval
  let clean := (Informal.ExtraPages.auditAxiomFindings (some cleanAudit)
    (some "Trust-model/")).asString
  let dirty := (Informal.ExtraPages.auditAxiomFindings (some bothAudit)
    (some "Trust-model/")).asString
  let none' := (Informal.ExtraPages.auditAxiomFindings Option.none
    (some "Trust-model/")).asString
  let unconfigured := (Informal.ExtraPages.auditAxiomFindings Option.none Option.none).asString
  -- The verdict has one home, and this page points at it.
  hasSubstr clean "href=\"Trust-model/#bp-trust-audit\"" &&
  !hasSubstr clean "Kernel axiom audit" &&
  !hasSubstr clean "found no `sorryAx`" &&
  !hasSubstr clean "Axioms used across the development" &&
  -- What only this page can carry: the names.
  hasSubstr dirty "Transitive <code>sorryAx</code> in closure (1)" &&
  hasSubstr dirty "A.foo" &&
  hasSubstr dirty "Nonstandard axioms (1)" &&
  hasSubstr dirty "A.bar" &&
  hasSubstr none' "Trust-model/#bp-trust-audit" &&
  -- A consumer with no trust surface at all renders exactly what it did before: nothing.
  unconfigured == ""

/-! ## The formalization page: declarations, annotated

Declared figures used to render as `bp_summary_badge_success` / `_error` / `_warn` chips —
the same green a comparator verdict wears. They are now plain fields, and each section
says whether anything in this build compared them with the environment.
-/

private def emptyState : TraverseState := TraverseState.initialize default

private def yamlFixture : Json :=
  (Json.parse (r##"{"version":"v0.4",
    "status":{"sorry_count":0,"sorry_in_definitions":0,
      "axioms":["propext","Classical.choice","Quot.sound"],
      "main_results":[{"declaration":"A.thm","file":"A/Main.lean","sorry_count":0,
        "axioms":["propext"]}]},
    "review":{"status":"agent-reviewed"},
    "alignment":{"statements":[{"source":"Theorem 1","lean":"A.thm","module":"A.Main",
      "status":"proved"}]}}"##)).toOption.getD Json.null

private def rendered (cross : CrossCheck) : String :=
  (renderFormalization emptyState yamlFixture false cross).asString

/-- info: true -/
#guard_msgs in
#eval
  let checked := rendered (.checked cleanAudit)
  let other := rendered .otherDocument
  let notRun := rendered .notRun
  hasSubstr checked "data-bp-crosscheck=\"checked\"" &&
  hasSubstr checked "Cross-checked: this build's" &&
  hasSubstr checked "over 312 declarations" &&
  hasSubstr checked "would have failed this build" &&
  hasSubstr other "data-bp-crosscheck=\"other-document\"" &&
  hasSubstr other "was given a different" &&
  hasSubstr notRun "data-bp-crosscheck=\"not-run\"" &&
  hasSubstr notRun "no build-time axiom audit ran for this build"

-- No verdict tier anywhere on the page, in any state — and the fields are labelled as
-- what they are.
/-- info: true -/
#guard_msgs in
#eval
  let all := [rendered (.checked cleanAudit), rendered .otherDocument, rendered .notRun]
  all.all (fun h =>
    !hasSubstr h "bp_summary_badge_success" &&
    !hasSubstr h "bp_summary_badge_error" &&
    !hasSubstr h "bp_summary_badge_warn" &&
    -- The alignment status is a word the author typed, not a badge.
    hasSubstr h "<td>proved</td>" &&
    hasSubstr h "Declared sorry count" &&
    hasSubstr h "Declared axioms" &&
    -- `review.status` is never checked by anything, so its note does not vary.
    hasSubstr h "Declared by the project; no build step checks it.")

-- What the cross-check does *not* cover is named, not left to be inferred.
/-- info: true -/
#guard_msgs in
#eval
  let checked := rendered (.checked cleanAudit)
  let unfinished :=
    (renderFormalization emptyState
      ((Json.parse "{\"status\":{\"sorry_count\":2}}").toOption.getD Json.null)
      false (.checked cleanAudit)).asString
  hasSubstr checked "<code>sorry_in_definitions</code> is declared only" &&
  hasSubstr unfinished "A non-zero sorry count is declared, not cross-checked" &&
  !hasSubstr checked "A non-zero sorry count is declared, not cross-checked"

/-! ## F3: a declared sorry is declared

`claimedSorried` was populated only on the *contradiction* path (`sorry_count: 0` against a
`sorryAx` closure), so the honest case — a document declaring the sorry it has — fell
through to the "dirty but unclaimed" pass and was reported as undeclared. Under
`verso.blueprint.trust.requireAuditClean` that is a build **error**, which made the strict
gate unusable for exactly the projects most likely to want it: the deliberately
in-progress ones.

`TrustAuditFixture.declaredSorryFixture` is wired to a blueprint node, so the audit
enumerates it; the fixture `formalization.yaml` declares its sorry. **This document
elaborating at all is the test.**
-/

set_option verso.blueprint.trust.formalizationYaml
  "tests/fixtures/trust/formalization-declared-sorry.yaml"
set_option verso.blueprint.trust.requireAuditClean true

#docs (Manual) auditCoverageDoc "Audit Coverage" :=
:::::::
:::theorem "audit.coverage.declared" (lean := "TrustAuditFixture.declaredSorryFixture")
A deliberately unfinished statement, declared unfinished in `formalization.yaml`.
:::

{blueprint_dashboard}
:::::::

-- And the strip tells the truth about it: the sorry is declared, so the build ran — but
-- the declaration is still dirty, and the scope line flags it rather than reporting a
-- clean audit because the paperwork was in order.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let html ← renderManualDocHtmlString extension_impls% auditCoverageDoc
  return hasSubstr html "carries sorryAx in its closure" &&
    hasSubstr html "bp_trust_strip_scope_flag_error" &&
    !hasSubstr html "axiom audit:"

end Verso.VersoBlueprintTests.TrustConsolidation
