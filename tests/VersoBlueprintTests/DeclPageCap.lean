/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint.DeclIndex
import VersoBlueprint.DeclRegistry

/-!
The per-declaration-page scale cap (`verso.blueprint.declRegistry.maxDeclPages`).

At project scale the registry INDEX is cheap and the per-declaration PAGE is not, so a
site with tens of thousands of declarations spends its whole generation writing pages
almost nobody opens. The cap keeps the pages worth having and indexes the rest — the
third of the genre's honest scale caps, and held to the same rule as the other two:
degrade, label, never hide the degradation.

What is checked here:

* **Unset ⇒ nothing happens.** `maxDeclPages = 0` returns the entries it was given,
  unchanged and byte-identical through `toJson`, with no cap record.
* **Selection.** The declarations that keep a page are the highest-fan-in unwired ones,
  ties broken by name so two builds of one commit agree. A declaration a blueprint node
  presents is untouched, because its canonical page is its node page and it was never a
  `decl/` page candidate in the first place.
* **No dangling href.** `DeclRoute.canonicalHref?` — the one function every linking
  surface goes through — is `none` for exactly the declarations whose page was dropped,
  and `pageOmittedOverCap` separates that state from a wired declaration, which has a
  node page and needs no `decl/` one.
* **The rendered row.** The index row for a dropped declaration carries the neutral
  `bp_summary_badge` pill and its source link, and no `<a href>` into the `decl/` route;
  the row for a kept one still links to its page.
* **Non-binding caps do not report.** A registry larger than the cap whose candidates
  still fit under it is left alone and records nothing, so the counts on the PM hub and
  the trust model never describe a degradation that did not happen.
-/

namespace Verso.VersoBlueprintTests.DeclPageCap

open Lean
open Informal.DeclRegistry

private def hasSubstr (s needle : String) : Bool := (s.splitOn needle).length > 1

/-! ## A registry as elaboration leaves it -/

/-- Skeleton entry; the tests vary only the fields the cap reads. -/
private def entry (name : String) (usedBy : Array String) : Entry := {
  name
  kind := "Theorem"
  moduleName := "Example.Defs"
  sourcePath := "Example/Defs.lean"
  range? := some { pos := { line := 10, column := 0 }, endPos := { line := 12, column := 4 } }
  signatureText := "True"
  signatureHtml? := none
  status := "proved"
  usedBy
  shortName := name
  sourceHref? := some "https://github.com/eric-vergo/Example/blob/abc/Example/Defs.lean#L10-L12"
  declHref? := some (Informal.NodeRoute.declPageHref name)
}

/-- A declaration a blueprint node presents: node page, no `decl/` page, ever. -/
private def presented : Entry :=
  { entry "Example.headline" #[] with
      nodeLabels := #["thm:headline"]
      nodeHref? := some "node/thm-headline/"
      declHref? := none
      authored := true }

/-- Four unwired declarations, fan-in 5 / 3 / 3 / 0. The two fan-in-3 entries are the
tie the selection has to break by name. -/
private def hub : Entry := entry "Example.hub" #["a", "b", "c", "d", "e"]
private def midA : Entry := entry "Example.midA" #["a", "b", "c"]
private def midB : Entry := entry "Example.midB" #["a", "b", "c"]
private def leaf : Entry := entry "Example.leaf" #[]

private def entries : Array Entry := #[presented, leaf, midB, hub, midA]

/-! ## Unset ⇒ byte-identical output -/

-- `0` is unlimited: the entries come back as they went in, and nothing is recorded.
/-- info: true -/
#guard_msgs in
#eval
  let r := applyDeclPageCap 0 entries
  let out : Array Entry := r.1
  let cap? : Option PageCap := r.2
  (toJson out).compress == (toJson entries).compress && cap?.isNone

-- A cap the registry does not exceed is also a no-op.
/-- info: true -/
#guard_msgs in
#eval
  let r := applyDeclPageCap 99 entries
  let out : Array Entry := r.1
  let cap? : Option PageCap := r.2
  (toJson out).compress == (toJson entries).compress && cap?.isNone

-- A cap the *registry* exceeds but the page *candidates* do not is still a no-op: there
-- are 5 entries and a cap of 4, but only 4 of them would ever get a `decl/` page.
/-- info: true -/
#guard_msgs in
#eval
  let r := applyDeclPageCap 4 entries
  let out : Array Entry := r.1
  let cap? : Option PageCap := r.2
  (toJson out).compress == (toJson entries).compress && cap?.isNone

/-! ## Selection -/

-- Cap 2: the two highest-fan-in unwired declarations keep their pages. `midA` and `midB`
-- tie at fan-in 3, so neither displaces `hub`, and the tie itself is broken by name.
/-- info: (true, true, true, true) -/
#guard_msgs in
#eval
  let out : Array Entry := (applyDeclPageCap 2 entries).1
  let of := fun n => (out.find? (·.name == n)).map DeclRoute.hasDeclPage
  (of "Example.hub" == some true,
   of "Example.midA" == some true,
   of "Example.midB" == some false,
   of "Example.leaf" == some false)

-- The presented declaration is untouched: still its node page, still no `decl/` page,
-- and still not counted as a page the cap took away.
/-- info: (some "node/thm-headline/", false, false) -/
#guard_msgs in
#eval
  let out : Array Entry := (applyDeclPageCap 2 entries).1
  let e := (out.find? (·.name == "Example.headline")).getD default
  (DeclRoute.canonicalHref? e, DeclRoute.hasDeclPage e, DeclRoute.pageOmittedOverCap e)

-- The recorded counts describe the candidates, not the registry: four declarations have
-- no blueprint node, two of them keep a page, two do not.
/-- info: some (2, 2, 4, 2) -/
#guard_msgs in
#eval
  let cap? : Option PageCap := (applyDeclPageCap 2 entries).2
  cap?.map fun c => (c.limit, c.emitted, c.candidates, c.omitted)

-- Selection is a function of the entries, not of their order.
/-- info: true -/
#guard_msgs in
#eval
  let shuffled : Array Entry := #[midA, hub, presented, midB, leaf]
  let kept := fun (es : Array Entry) =>
    ((applyDeclPageCap 2 es).1.filter DeclRoute.hasDeclPage).map (·.name)
  (kept entries).qsort (· < ·) == (kept shuffled).qsort (· < ·)

/-! ## No dangling href -/

-- The one function every linking surface goes through is `none` for exactly the dropped
-- declarations, and `pageOmittedOverCap` says which state that is.
/-- info: (none, true, some "decl/Example___hub/", false) -/
#guard_msgs in
#eval
  let out : Array Entry := (applyDeclPageCap 2 entries).1
  let dropped := (out.find? (·.name == "Example.leaf")).getD default
  let kept := (out.find? (·.name == "Example.hub")).getD default
  (DeclRoute.canonicalHref? dropped, DeclRoute.pageOmittedOverCap dropped,
   DeclRoute.canonicalHref? kept, DeclRoute.pageOmittedOverCap kept)

/-! ## The rendered index row -/

-- A dropped declaration's row: the neutral pill, the source link, and no link into the
-- `decl/` route anywhere in the row.
/-- info: (true, true, true, false) -/
#guard_msgs in
#eval
  let out : Array Entry := (applyDeclPageCap 2 entries).1
  let row := (Informal.DeclIndex.declRowHtml true ((out.find? (·.name == "Example.leaf")).getD default)).asString
  (hasSubstr row "bp_summary_badge bp_decl_row_nopage",
   hasSubstr row "no page (over cap)",
   hasSubstr row "bp_decl_row_source",
   hasSubstr row "href=\"decl/")

-- A kept declaration's row still links to its page, with no pill.
/-- info: (true, false, false) -/
#guard_msgs in
#eval
  let out : Array Entry := (applyDeclPageCap 2 entries).1
  let row := (Informal.DeclIndex.declRowHtml true ((out.find? (·.name == "Example.hub")).getD default)).asString
  (hasSubstr row "href=\"decl/Example___hub/\"",
   hasSubstr row "no page (over cap)",
   hasSubstr row "bp_decl_row_source")

-- Uncapped, the row is byte-for-byte the row that existed before the cap did: the two
-- new cells render as nothing at all, leaving signature and status adjacent with no
-- separating whitespace. This is what "option unset ⇒ unchanged output" means at the
-- level the site is written from.
/-- info: true -/
#guard_msgs in
#eval
  let row := (Informal.DeclIndex.declRowHtml true leaf).asString
  hasSubstr row "</code><span class=\"bp_decl_row_status\""

-- Uncapped, every unwired row is a link and no row carries the pill — the shape the
-- existing catalog pages have today.
/-- info: true -/
#guard_msgs in
#eval
  let rows := entries.map fun e => (Informal.DeclIndex.declRowHtml true e).asString
  rows.all (fun r => !hasSubstr r "no page (over cap)") &&
    hasSubstr (rows[1]!) "href=\"decl/Example___leaf/\""

end Verso.VersoBlueprintTests.DeclPageCap
