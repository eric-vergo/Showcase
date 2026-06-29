/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.TraversalIndex

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
private def stripNameEscapes (s : String) : String :=
  s.foldl (init := "") fun acc c =>
    if c == '«' || c == '»' || c == '‹' || c == '›' then acc else acc.push c

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
  let slug := (stripNameEscapes s).sluggify.toString
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
