/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.TraversalIndex
import VersoBlueprint.Informal.Block.Store

/-!
Per-node page routing.

This is the single source of truth for the URL of a Blueprint node page. It is
intentionally a tiny, low-level module so that it can be imported by both
`GraphApi` (which re-points graph node hrefs) and `PreviewManifest` (which
re-points the public xref permalinks) without introducing an import cycle with
the node-page emitter in `NodePage`.

All routes are **root-relative without a leading slash** so that they resolve
against each page's `<base href>` — the same convention the existing graph URLs
use. Never emit these into DOT/JSON payloads with a leading slash. The xref
permalink rewrite (in `emitPublicXref`) is the one place that intentionally uses
a leading slash, because `find.js` strips it before resolving against `<base>`.
-/

namespace Informal.NodeRoute

open Lean
open Verso Verso.Multi
open Verso.Genre Manual

/--
Strip the Lean `Name`-escape guillemets (`«…»`, `‹…›`) that `Name.toString`
inserts around components that are not valid identifiers (e.g. blueprint labels
like `«thm:foo»`). Removing the wrapping markers *before* sluggifying turns the
ugly `_FLQQ_thm___foo_FLQQ_` slug into the readable `thm___foo`. The unique inner
label content is preserved, so distinct labels stay distinct. Pure/deterministic.
-/
def stripNameEscapes (s : String) : String :=
  s.foldl (init := "") fun acc c =>
    if c == '«' || c == '»' || c == '‹' || c == '›' then acc else acc.push c

/--
Transliterate Greek letters to their ASCII names (`χ` → `chi`, `α` → `alpha`, …)
*before* sluggifying, so identifiers built from Greek letters — e.g. the Dirichlet
character `χ` in `A362583.χ_natCast_eq_ite` — get a readable slug
(`A362583___chi_natCast_eq_ite`) instead of the run of underscores the catch-all
`sluggify` emits for a non-ASCII code point. Any letter outside the table is left
untouched for `sluggify` to handle. Pure/deterministic; distinct names stay distinct
(and the emitter's `usedSlugs` guard catches the vanishingly rare collision).
-/
def transliterateGreek (s : String) : String :=
  s.foldl (init := "") fun acc c =>
    match c with
    | 'α' => acc ++ "alpha"   | 'β' => acc ++ "beta"    | 'γ' => acc ++ "gamma"
    | 'δ' => acc ++ "delta"   | 'ε' => acc ++ "epsilon" | 'ζ' => acc ++ "zeta"
    | 'η' => acc ++ "eta"     | 'θ' => acc ++ "theta"   | 'ι' => acc ++ "iota"
    | 'κ' => acc ++ "kappa"   | 'λ' => acc ++ "lambda"  | 'μ' => acc ++ "mu"
    | 'ν' => acc ++ "nu"      | 'ξ' => acc ++ "xi"      | 'ο' => acc ++ "omicron"
    | 'π' => acc ++ "pi"      | 'ρ' => acc ++ "rho"     | 'σ' => acc ++ "sigma"
    | 'ς' => acc ++ "sigma"   | 'τ' => acc ++ "tau"     | 'υ' => acc ++ "upsilon"
    | 'φ' => acc ++ "phi"     | 'χ' => acc ++ "chi"     | 'ψ' => acc ++ "psi"
    | 'ω' => acc ++ "omega"
    | 'Α' => acc ++ "Alpha"   | 'Β' => acc ++ "Beta"    | 'Γ' => acc ++ "Gamma"
    | 'Δ' => acc ++ "Delta"   | 'Ε' => acc ++ "Epsilon" | 'Ζ' => acc ++ "Zeta"
    | 'Η' => acc ++ "Eta"     | 'Θ' => acc ++ "Theta"   | 'Ι' => acc ++ "Iota"
    | 'Κ' => acc ++ "Kappa"   | 'Λ' => acc ++ "Lambda"  | 'Μ' => acc ++ "Mu"
    | 'Ν' => acc ++ "Nu"      | 'Ξ' => acc ++ "Xi"      | 'Ο' => acc ++ "Omicron"
    | 'Π' => acc ++ "Pi"      | 'Ρ' => acc ++ "Rho"     | 'Σ' => acc ++ "Sigma"
    | 'Τ' => acc ++ "Tau"     | 'Υ' => acc ++ "Upsilon" | 'Φ' => acc ++ "Phi"
    | 'Χ' => acc ++ "Chi"     | 'Ψ' => acc ++ "Psi"     | 'Ω' => acc ++ "Omega"
    | _   => acc.push c

/--
Slug for a node-page directory derived from the canonical label string.

Pure and deterministic: identical inputs always produce identical slugs, so the
graph re-point (`GraphApi.enrichNode`), the xref re-point (`emitPublicXref`), and
the node-page emitter all agree without sharing any state. Collisions between two
distinct labels that sluggify identically are detected and reported by the
emitter; they are vanishingly rare for unique dotted Lean `Name`s.

For readability (NODE-1) the Lean name-escape guillemets are dropped before
sluggify, and any escape tokens an upstream slugger might already have produced
(`_FLQQ_`/`_FRQQ_`/`_FLQ_`/`_FRQ_`) are stripped after. Only the wrapping markers
are removed, so uniqueness across distinct labels is preserved (verified to have
zero collisions across the showcase's node labels).
-/
def nodePageSlugOfString (s : String) : String :=
  let slug := (transliterateGreek (stripNameEscapes s)).sluggify.toString
  slug
    |>.replace "_FLQQ_" ""
    |>.replace "_FRQQ_" ""
    |>.replace "_FLQ_" ""
    |>.replace "_FRQ_" ""

/-- Slug for a node-page directory derived from an informal node label. -/
def nodePageSlug (label : Name) : String :=
  nodePageSlugOfString label.toString

/--
Root-relative href (no leading slash) to a node page. Resolves against the
per-page `<base href>`; safe to emit into DOT/JSON graph payloads.
-/
def nodePageHref (label : Name) : String :=
  "node/" ++ nodePageSlug label ++ "/"

/-- Multi-page output path for a node page: `node/<slug>/index.html`. -/
def nodePagePath (label : Name) : Verso.Multi.Path :=
  #["node", nodePageSlug label]

/-!
Project-management page routes (worklist / owners / tags).

These share the same root-relative, leading-slash-free convention as the node
routes so that they resolve against each page's `<base href>` at any output
depth. They are the single source of truth shared by the dashboard cross-links
(`Commands/Summary/Sections.lean`) and the extra-page emitter
(`ExtraPages.lean`), so both agree on every URL without sharing state.
-/

/-- Root-relative href (no leading slash) to the worklist page. -/
def worklistHref : String := "worklist/"

/-- Multi-page output path for the worklist page: `worklist/index.html`. -/
def worklistPath : Verso.Multi.Path := #["worklist"]

/-- Root-relative href (no leading slash) to the audit / technical-debt page. -/
def auditHref : String := "audit/"

/-- Multi-page output path for the audit page: `audit/index.html`. -/
def auditPath : Verso.Multi.Path := #["audit"]

/-- Root-relative href (no leading slash) to the Mathlib upstream-candidates page. -/
def mathlibCandidatesHref : String := "mathlib-candidates/"

/-- Multi-page output path for the candidates page: `mathlib-candidates/index.html`. -/
def mathlibCandidatesPath : Verso.Multi.Path := #["mathlib-candidates"]

/-- Root-relative href (no leading slash) to the project-management (PM) hub page. -/
def pmHref : String := "pm/"

/-- Multi-page output path for the PM hub page: `pm/index.html`. -/
def pmPath : Verso.Multi.Path := #["pm"]

/-- Root-relative href (no leading slash) to the statement-comparator page. -/
def comparatorHref : String := "comparator/"

/-- Multi-page output path for the comparator page: `comparator/index.html`. -/
def comparatorPath : Verso.Multi.Path := #["comparator"]

/-!
Declaration-catalog page routes (Definitions / Theorems / alphabetical Index /
Modules). Same root-relative, leading-slash-free convention as the routes above so
they resolve against each page's `<base href>`. They are the single source of truth
shared by the top-nav strip (`Commands/top-nav.mjs`, via the site root) and the
catalog-page emitter (`DeclIndex.lean`), and are chosen to avoid colliding with the
existing `node/` / `worklist/` / `owners/` / `tags/` / `find/` / `audit/` /
`mathlib-candidates/` / `Formalization-Metadata/` slugs.
-/

/-- Root-relative href (no leading slash) to the Definitions catalog page. -/
def defsHref : String := "defs/"
/-- Multi-page output path for the Definitions catalog: `defs/index.html`. -/
def defsPath : Verso.Multi.Path := #["defs"]

/-- Root-relative href (no leading slash) to the Theorems catalog page. -/
def theoremsHref : String := "theorems/"
/-- Multi-page output path for the Theorems catalog: `theorems/index.html`. -/
def theoremsPath : Verso.Multi.Path := #["theorems"]

/-- Root-relative href (no leading slash) to the alphabetical declaration index. -/
def declIndexHref : String := "decl-index/"
/-- Multi-page output path for the alphabetical index: `decl-index/index.html`. -/
def declIndexPath : Verso.Multi.Path := #["decl-index"]

/-- Root-relative href (no leading slash) to the module-tree page. -/
def modulesHref : String := "modules/"
/-- Multi-page output path for the module tree: `modules/index.html`. -/
def modulesPath : Verso.Multi.Path := #["modules"]

/-!
Per-declaration page routes (`decl/<slug>/`).

One page per **unwired** registry declaration (wired declarations' canonical page
stays their node page). The slug is derived from the fully-qualified (de-mangled)
declaration name, so it never collides with the label-derived `node/` slugs and
stays deterministic across the emitters: the registry (`DeclRegistry.buildEntry`
populates `Entry.declHref?`), the all-decls graph (supporting-node hrefs), the
catalog rows (`DeclIndex`), and the page emitter (`DeclPage`) all agree without
sharing state. Same root-relative, leading-slash-free convention as above.
-/

/-- Slug for a declaration page, derived from the fully-qualified declaration name. -/
def declPageSlug (declName : String) : String :=
  nodePageSlugOfString declName

/-- Root-relative href (no leading slash) to a declaration page. -/
def declPageHref (declName : String) : String :=
  "decl/" ++ declPageSlug declName ++ "/"

/-- Multi-page output path for a declaration page: `decl/<slug>/index.html`. -/
def declPagePath (declName : String) : Verso.Multi.Path :=
  #["decl", declPageSlug declName]

/-- Slug for an owner page, derived from the owner's canonical `Name`. -/
def ownerPageSlug (owner : Name) : String :=
  nodePageSlugOfString owner.toString

/-- Root-relative href (no leading slash) to an owner page. -/
def ownerPageHref (owner : Name) : String :=
  "owners/" ++ ownerPageSlug owner ++ "/"

/-- Multi-page output path for an owner page: `owners/<slug>/index.html`. -/
def ownerPagePath (owner : Name) : Verso.Multi.Path :=
  #["owners", ownerPageSlug owner]

/-- Slug for a tag page, derived from the tag string. -/
def tagPageSlug (tag : String) : String :=
  nodePageSlugOfString tag

/-- Root-relative href (no leading slash) to a tag page. -/
def tagPageHref (tag : String) : String :=
  "tags/" ++ tagPageSlug tag ++ "/"

/-- Multi-page output path for a tag page: `tags/<slug>/index.html`. -/
def tagPagePath (tag : String) : Verso.Multi.Path :=
  #["tags", tagPageSlug tag]

/--
Whether `label` has a dedicated node page. Node pages are emitted for every
informal node (statement-facet) recorded in the traversal node index, so this is
exactly "is there an informal node for this label".
-/
def hasNodePage (state : TraverseState) (label : Name) : Bool :=
  (Informal.TraversalIndex.Nodes.data? state label).isSome

/--
Drop leading token-prefix segments from a `:`-split label, never dropping the
final segment. A segment counts as a token prefix when it is non-empty and purely
alphabetic (e.g. `code`, `lem`, `def`, `thm`, `cor`). Structural recursion on the
list, so it always terminates.
-/
private def dropLabelTagPrefixes : List String → List String
  | [] => []
  | [last] => [last]
  | (seg :: rest) =>
    if seg ≠ "" && seg.all Char.isAlpha then dropLabelTagPrefixes rest
    else seg :: rest

/--
Clean a raw graph-node/label string for display: drop the Lean name-escape
guillemets and any leading token-prefix tags, so a page-less Lean-code-backed
node like `code:lem:RaRalpha` reads as `RaRalpha` and `def:noperthedron_main` as
`noperthedron_main`. Pure/deterministic; mirrors the dashboard reading map.
-/
def cleanLabelForDisplay (raw : String) : String :=
  String.intercalate ":" (dropLabelTagPrefixes ((stripNameEscapes raw).splitOn ":"))

/--
Friendly display label for an entry, shared by every PM/summary/audit surface so
they read the same as the dashboard reading map: the node's resolved display
title (e.g. "Lemma 7.7") when available, otherwise the cleaned raw label (with
guillemets and token-prefix tags stripped). Pure/deterministic.
-/
def friendlyEntryLabel (state : TraverseState) (label : Name) : String :=
  match (Informal.TraversalIndex.Nodes.data? state label).map (·.displayTitle state) with
  | some t => if t.isEmpty then cleanLabelForDisplay label.toString else t
  | none => cleanLabelForDisplay label.toString

/-!
Lean const → blueprint-node cross-links.

`blueprintNodeTargets` builds a `Code.LinkTargets` whose `const` arm maps a Lean
declaration to the node page of the blueprint entry that formalizes it. It is
injected into the genre render config (`linkTargets`) alongside the ordinary
`localTargets`/`remoteTargets`, so a const that is *both* a Lean declaration and a
blueprint node renders the existing multi-link `data-verso-links` menu — no client
JS change is needed.

The decl→label index is rebuilt purely from the traversal state (no environment
access at emit time): inline-defined declarations come from the per-label
`InlineCode` store (each `InlineCodeData` carries its label plus the names it
defines), and external `(lean := "…")` declarations come from the
`ExternalDeclAnchors` store, whose object keys encode the owning `(label, decl)`
pair. Both sources degrade safely: an entry only yields a link when the resolved
label actually `hasNodePage`.
-/

private def pushNameUnique (names : Array Name) (n : Name) : Array Name :=
  if names.contains n then names else names.push n

private def addDeclLabel (m : Lean.NameMap (Array Name)) (decl label : Name) :
    Lean.NameMap (Array Name) :=
  let decl := decl.eraseMacroScopes
  m.insert decl (pushNameUnique (m.getD decl #[]) label)

/-- Parse one `"{len}:{str}"` length-prefixed token, returning it and the rest. -/
private def readLenPrefixed (cs : List Char) : Option (String × List Char) := do
  let digits := cs.takeWhile Char.isDigit
  let rest := cs.dropWhile Char.isDigit
  match rest with
  | ':' :: rest' =>
    let n ← (String.ofList digits).toNat?
    let taken := rest'.take n
    if taken.length == n then some (String.ofList taken, rest'.drop n) else none
  | _ => none

/--
Parse an `ExternalDeclAnchors` object key (`"{n}:{label}|{m}:{decl}"`, see
`Resolve.externalRenderedDeclTargetKey`) back into its `(label, decl)` pair.
-/
private def parseExternalAnchorKey (key : String) : Option (Name × Name) := do
  let (labelStr, rest) ← readLenPrefixed key.toList
  match rest with
  | '|' :: rest2 =>
    let (declStr, _) ← readLenPrefixed rest2
    some (labelStr.toName, declStr.toName)
  | _ => none

/-- Decl → node-labels index, rebuilt purely from the traversal state. -/
def declNodeLabels (state : TraverseState) : Lean.NameMap (Array Name) := Id.run do
  let mut m : Lean.NameMap (Array Name) := {}
  -- Inline-defined declarations (literate ```lean blocks).
  for entry in Informal.TraversalIndex.decodeStoreEntries (α := Informal.InlineCodeData)
      state Informal.TraversalIndex.InlineCode.domainName do
    if let .ok stored := entry then
      let data := stored.data
      for decl in data.definedDefs ++ data.definedTheorems do
        m := addDeclLabel m decl.name data.label
  -- External `(lean := "…")` declarations: keys encode (label, decl).
  if let some dom := state.domains.get? Informal.TraversalIndex.ExternalDeclAnchors.domainName then
    for (key, _obj) in dom.objects.toArray do
      if let some (label, decl) := parseExternalAnchorKey key then
        m := addDeclLabel m decl label
  return m

/--
Link targets mapping a Lean const to the blueprint node page(s) that formalize it.

Pairs with `TraverseState.localTargets`/`AllRemotes.remoteTargets` in the genre
render config. Only the `const` arm is populated; all other arms keep their empty
defaults.
-/
def blueprintNodeTargets (state : TraverseState) : Verso.Code.LinkTargets Manual.TraverseContext :=
  let declMap := declNodeLabels state
  { const := fun name _ctxt =>
      let name := name.eraseMacroScopes
      (declMap.getD name #[]).filterMap fun label =>
        if hasNodePage state label then
          some {
            shortDescription := "blueprint"
            description := s!"Blueprint entry for {name}"
            href := nodePageHref label }
        else none }

end Informal.NodeRoute
