/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Opus 5 (Claude Code)
-/

import VersoBlueprintTests.Blueprint.Support

/-!
The proof-overview ("milestones") layer.

The document below is also the curated test blueprint `proof-overview`, so the
same fixture that these assertions run against is the one a human eyeballs in both
colour schemes.

The two *error* fixtures live in sibling modules rather than here. Milestones are
registered in an environment extension shared by every `#docs` in a module, so a
deliberately broken overview declared beside this one would re-report its defect
from every later `blueprint_overview` in the file.
-/

namespace Verso.VersoBlueprintTests.BlueprintProofOverview

open Verso
open Verso.Genre.Manual
open Lean
open Informal
open Informal.Milestones
open Verso.VersoBlueprintTests.Blueprint.Support

set_option doc.verso true

private def manualImpls : ExtensionImpls := extension_impls%

/-- The part of `s` after the first occurrence of `needle` (the whole string when
absent). Used to scope an assertion to the overview surface on a page that also
carries a dependency graph. -/
private def sliceAfter (s needle : String) : String :=
  match s.splitOn needle with
  | _ :: rest@(_ :: _) => String.intercalate needle rest
  | _ => s

/-
Eight nodes in a dependency chain plus an auxiliary side branch, grouped into four
milestones:

* `ms:po.a` → `ms:po.b` → `ms:po.c` is witnessed at every step by the node chain;
* `ms:po.d` also declares `uses := "ms:po.a"`, and its nodes depend on nothing in
  `ms:po.a` — that edge is the deliberately author-asserted one. The headline node
  depends on the auxiliary branch, which is what keeps the `uses` graph connected
  (the graph gate requires that of a generated site) while leaving the milestone
  edge pointing the other way, and so still unwitnessed;
* `thm:po.shared` belongs to two milestones, which must NOT count as a witness.
-/
-- The one author-asserted edge warns by design; the guard keeps errors visible.
#guard_msgs(error, drop info, drop warning) in
#docs (Genre.Manual) proofOverviewDoc "Proof Overview" :=
:::::::

:::definition "def:po.base"
The base object.
:::

:::theorem "thm:po.step1" (uses := "def:po.base")
The first consequence of the base object.
:::

:::theorem "thm:po.step2" (uses := "thm:po.step1")
The second consequence.
:::

:::theorem "thm:po.step3" (uses := "thm:po.step2")
The third consequence.
:::

:::theorem "thm:po.shared" (uses := "thm:po.step2")
A result two milestones both claim.
:::

:::theorem "thm:po.top" (uses := "thm:po.step3, thm:po.shared, thm:po.aux1")
The headline result, which also leans on the auxiliary construction.
:::

:::definition "def:po.aux"
An auxiliary construction, independent of the base object.
:::

:::theorem "thm:po.aux1" (uses := "def:po.aux")
A fact about the auxiliary construction.
:::

:::milestone "ms:po.a" (title := "Foundations") (members := "def:po.base, thm:po.step1")
The base object and the first fact about it.
:::

:::milestone "ms:po.b" (title := "The middle") (paper := "§3") (uses := "ms:po.a") (members := "thm:po.step2, thm:po.shared")
Everything the argument needs before the final ascent.
:::

:::milestone "ms:po.c" (title := "The summit") (row := 2) (uses := "ms:po.b") (members := "thm:po.step3, thm:po.shared, thm:po.top")
The headline result and the step that reaches it.
:::

:::milestone "ms:po.d" (title := "Auxiliary machinery") (uses := "ms:po.a") (members := "def:po.aux, thm:po.aux1")
Machinery the write-up leans on, whose Lean development is independent.
:::

{blueprint_graph}

{blueprint_overview}
:::::::

/- ## The rendered surface -/

private def overviewHtml : IO String := do
  let out ← renderManualDocHtmlString manualImpls proofOverviewDoc
  pure out

-- Four milestones, four boxes; the one unwitnessed edge is dashed exactly once;
-- every card carries an anchor; and the whole surface ships without a line of
-- JavaScript.
/-- info: (4, 1, true, true) -/
#guard_msgs in
#eval
  show IO (Nat × Nat × Bool × Bool) from do
    let out ← overviewHtml
    let surface := sliceAfter out "class=\"bp_overview\""
    return (
      countSubstr out "class=\"bp_overview_node\"",
      -- Counted on the surface, not on the whole page: the class also names a rule in
      -- the stylesheet, which every emitted page carries.
      countSubstr surface "bp_overview_edge_asserted",
      hasSubstr out "id=\"ms-po-a\"" && hasSubstr out "id=\"ms-po-d\"",
      !hasSubstr surface "<script")

-- The unwitnessed edge says so where the claim is made, and the surface reports
-- what the build actually established rather than grading it.
/-- info: (true, true, true) -/
#guard_msgs in
#eval
  show IO (Bool × Bool × Bool) from do
    let out ← overviewHtml
    return (
      hasSubstr out "author-asserted",
      hasSubstr out "1 author-asserted.",
      hasSubstr out "4 milestones cover 8 of this blueprint's 8 nodes")

-- Author-supplied metadata reaches the card: title, paper reference, and the
-- three-segment member meter.
/-- info: (true, true, true) -/
#guard_msgs in
#eval
  show IO (Bool × Bool × Bool) from do
    let out ← overviewHtml
    return (
      hasSubstr out "Foundations" && hasSubstr out "Auxiliary machinery",
      hasSubstr out "§3",
      hasSubstr out "bp_overview_meter_label")

-- The stylesheet rides the site-wide `extraCss` channel, and no `.mjs` is added.
/-- info: (true, true) -/
#guard_msgs in
#eval
  show IO (Bool × Bool) from do
    let (_html, st) ← renderManualDocHtmlStringAndState manualImpls proofOverviewDoc
    return (hasExtraCss st ".bp_overview_node_box", !hasExtraJs st "bp_overview")

/- ## Rows -/

private def ms (label : String) (uses : Array String) (row? : Option Nat := none) : Milestone :=
  { label := Name.mkSimple label
    title := label
    row?
    uses := uses.map Name.mkSimple }

-- A chain gets consecutive rows; a pin that agrees with the dependencies is kept.
/-- info: (0, 1, 2) -/
#guard_msgs in
#eval
  match Milestones.rows #[ms "a" #[], ms "b" #["a"], ms "c" #["b"] (row? := some 2)] with
  | .ok rows => (rows.getD `a 0, rows.getD `b 0, rows.getD `c 0)
  | .error _ => (99, 99, 99)

-- A pin below a dependency is a defect, not a layout to silently re-lay.
/-- info: true -/
#guard_msgs in
#eval
  match Milestones.rows #[ms "a" #[], ms "b" #["a"] (row? := some 0)] with
  | .ok _ => false
  | .error msg => (msg.splitOn "pins row 0").length > 1

-- A cycle cannot be laid out in rows at all.
/-- info: true -/
#guard_msgs in
#eval
  match Milestones.rows #[ms "x" #["y"], ms "y" #["x"]] with
  | .ok _ => false
  | .error msg => (msg.splitOn "cycle").length > 1

/- ## Witnesses -/

private def gnode (label : Name) : Informal.Graph.NodeData :=
  { label, title := label.toString, displayLabel := label.toString, previewKey := ""
    visual := default }

/-- `c` depends on `b` depends on `a`; `z` depends on nothing. -/
private def witnessGraph : Informal.Graph.GraphData :=
  { nodes := #[gnode `a, gnode `b, gnode `c, gnode `z]
    edges := #[{ source := `a, target := `b }, { source := `b, target := `c }] }

private def withMembers (label : String) (members : Array Name) : Milestone :=
  { label := Name.mkSimple label, title := label, members }

-- A transitive dependency path is a witness; a merely shared member is not.
/-- info: (true, true) -/
#guard_msgs in
#eval
  let anc := Milestones.ancestorIndex witnessGraph #[`a, `b, `c, `z]
  let low := withMembers "low" #[`a]
  let high := withMembers "high" #[`c]
  let overlapA := withMembers "overlapA" #[`b, `z]
  let overlapB := withMembers "overlapB" #[`z]
  ((Milestones.witness? anc high low).isSome,
   (Milestones.witness? anc overlapA overlapB).isNone)

-- The tally the overview prints and the tally the trust-model page prints are one
-- function.
/-- info: (3, 1, 1, 1) -/
#guard_msgs in
#eval
  let e := fun (t : WitnessTier) => ({ source := `s, target := `t, tier := t } : EdgeVerdict)
  let a := Milestones.auditOf 2 9 5 #[e .presented, e .projectDecls, e .asserted] true
  (a.edges, a.witnessedPresented, a.witnessedProjectDecls, a.asserted)

end Verso.VersoBlueprintTests.BlueprintProofOverview
