/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean
import Std.Data.HashMap
import Std.Data.HashSet
import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.ProvedStatus
import VersoBlueprint.Environment
import VersoBlueprint.Graph
import VersoBlueprint.ExternalRefSnapshot
import VersoBlueprint.ExternalDeclRender
import VersoBlueprint.NodeCard
import VersoBlueprint.NodeRoute
import VersoBlueprint.JunkValues
import VersoBlueprint.TrustInputs

/-!
# Declaration registry

Persists a per-declaration record for **every** in-project declaration — including
those the blueprint never wires — so later features (the metadata rail, index and
module pages) can present, cross-link, and reverse-index the full formalization,
not just the authored blueprint nodes.

The registry is built at elaboration time (where the `Environment` is available)
and serialized into `-verso-data/decl-registry.json` at generation time via the
`blueprint_graph` block-data → traversal-state → `ExtraStep` path (see
`Commands/Graph.lean` and `PreviewManifest.emitBlueprintPreviewData`). It is gated
on `verso.blueprint.graph.includeAllDecls` — the same opt-in that populates the
all-declarations dependency graph, since both are the "track every declaration"
feature family. Consumers without the flag pay nothing and see no behavior change.

The project-module enumeration (`projectModuleRoots` / `enumerateProjectDecls`) is
shared with the all-decls graph augmentation. It normally harvests the project
boundary from authored `(lean := …)` references; a consumer whose formalization
arrives as a Lake/git dependency names its modules directly instead, via
`verso.blueprint.subjectModuleRoots`. The registry is the more inclusive
consumer: it tracks every project declaration including `private` helpers
(`includePrivate := true`), whereas the graph drops private helpers to stay
readable. Both agree on the public declaration set and on the project boundary.

Schema v2 additionally carries per-entry `shortName` (the configured project
prefix — `verso.blueprint.declNamePrefix` — stripped), `isPrivate`, the rendered
`docstringHtml?`, the unwired decl-page `declHref?`, the `sourceHref?` source
link, and the longest-path `depth?`/`height?` metrics, plus a top-level
`namePrefix` for client-side name shortening. The heavy proof/value **bodies**
are deliberately NOT part of the public JSON: `buildDeclRegistry` returns them as
a separate `Bodies` artifact carried only through the internal traversal store
(`TraversalIndex.DeclRegistry`, key `"bodies"`) to the decl-page emitter, where
they are baked into static HTML.

One field is deliberately *not* finished at elaboration: a `sourceHref?` into the
project's own repository would name the revision the registry was elaborated at, and a
warm `.lake` replays this artifact across commits — so it would go on naming that
revision under a build stamp that had moved (CX-066). Such an entry carries
`sourceRepoPath?` instead, and `Registry.withResolvedSourceLinks` composes the URL at
emission from the single revision record the build stamp also reads. Links into
dependency checkouts are pinned by the lockfile and stay resolved where they are built.
-/

namespace Informal.DeclRegistry

open Lean Meta
open Informal.Environment (informalExt)

register_option verso.blueprint.declNamePrefix : String := {
  defValue := ""
  descr := "Project namespace prefix (e.g. \"A362583\") stripped from declaration names wherever they display (catalog rows, metadata rail, graph labels, page outline, search); the fully-qualified name is kept on declaration pages and hover titles. Empty disables shortening."
}

/-- The configured `verso.blueprint.declNamePrefix` (empty ⇒ no shortening). -/
def configuredNamePrefix (opts : Lean.Options) : String :=
  opts.get verso.blueprint.declNamePrefix.name verso.blueprint.declNamePrefix.defValue

register_option verso.blueprint.declRegistry.fullElabMaxDecls : Nat := {
  defValue := 1500
  descr := "Declaration-count cap above which the registry SKIPS the per-entry full (statement + proof) re-elaboration from source — the dominant time/memory cost at large scale. Above the cap the cheaper source paths still run: signatures re-elaborate to the `signature` tier and proof bodies fall back to `syntactic` highlighting, both recorded in the registry as such rather than as the re-elaborated (`reelab`) tier. `0` ⇒ unlimited (never skip). Below the cap behavior is unchanged."
}

/-- The configured `verso.blueprint.declRegistry.fullElabMaxDecls` (0 ⇒ unlimited). -/
def configuredFullElabMaxDecls (opts : Lean.Options) : Nat :=
  opts.get verso.blueprint.declRegistry.fullElabMaxDecls.name
    verso.blueprint.declRegistry.fullElabMaxDecls.defValue

register_option verso.blueprint.declRegistry.maxDeclPages : Nat := {
  defValue := 0
  descr := "Cap on how many per-declaration (`decl/<slug>/`) pages this site emits. The registry INDEX is cheap and always covers every declaration; the per-declaration PAGE is not, so at large scale emitting one for every unwired declaration dominates a whole site generation. Above the cap the pages go to the declarations most of the library depends on (highest `usedBy` fan-in, ties by name); the rest stay in the registry, the catalog pages, the module tree, and the properties rail, but get no page of their own — and every surface that would have linked to one says so instead of dead-linking. Declarations a blueprint node presents are never affected: their canonical page is their node page, which this cap does not touch. `0` ⇒ unlimited (a page for every unwired declaration, the pre-cap behavior)."
}

/-- The configured `verso.blueprint.declRegistry.maxDeclPages` (0 ⇒ unlimited). -/
def configuredMaxDeclPages (opts : Lean.Options) : Nat :=
  opts.get verso.blueprint.declRegistry.maxDeclPages.name
    verso.blueprint.declRegistry.maxDeclPages.defValue

register_option verso.blueprint.declRegistry.pageExcludeInstances : Bool := {
  defValue := false
  descr := "Whether instance declarations are denied a per-declaration (`decl/<slug>/`) page. Of everything a library-scale registry enumerates, an instance's page is the one that carries the least: a generated name nobody looks up, a signature the reader meets through the class it instantiates, and thousands of them. This is a policy on the reading surface, not on the registry: excluded instances stay enumerated, audited, indexed, in the module tree, in the properties rail and in the dependency graph exactly as they were — what they lose is a page of their own, and every surface that would have linked to one says why instead of dead-linking. Declarations a blueprint node presents are never affected. `false` ⇒ a page for every unwired instance (the pre-policy behavior)."
}

/-- The configured `verso.blueprint.declRegistry.pageExcludeInstances`. -/
def configuredPageExcludeInstances (opts : Lean.Options) : Bool :=
  opts.get verso.blueprint.declRegistry.pageExcludeInstances.name
    verso.blueprint.declRegistry.pageExcludeInstances.defValue

register_option verso.blueprint.declRegistry.pageExcludePrivate : Bool := {
  defValue := false
  descr := "Whether `private` declarations are denied a per-declaration (`decl/<slug>/`) page. A private declaration is one the library itself does not export, and its page is a reading surface for something the project has said is internal; it also already has the thinnest page of any declaration, since private declarations are kept out of every dependency graph and so their pages carry no local graph at all. Like the instance rule, this is a policy on the reading surface only: excluded declarations stay in the registry, the catalogs, the module tree, the audit counts and the rail. `false` ⇒ a page for every unwired private declaration (the pre-policy behavior)."
}

/-- The configured `verso.blueprint.declRegistry.pageExcludePrivate`. -/
def configuredPageExcludePrivate (opts : Lean.Options) : Bool :=
  opts.get verso.blueprint.declRegistry.pageExcludePrivate.name
    verso.blueprint.declRegistry.pageExcludePrivate.defValue

register_option verso.blueprint.nodePage.localGraphRadius : Nat := {
  defValue := 2
  descr := "Radius (in dependency hops) of the localized dependency graph drawn on each node/decl page. The page graph is the radius-k neighborhood of the focus declaration in both directions (ancestors and descendants), not the full transitive closure — at large scale a headline declaration's full ancestor closure is most of the library, which is both slow to render and useless to read. `0` ⇒ unlimited (the full closure, the pre-cap behavior). Neighborhoods whose full closure already lies within the radius render identically."
}

/-- The configured `verso.blueprint.nodePage.localGraphRadius` (0 ⇒ unlimited, i.e.
the full ancestor ∪ self ∪ descendant closure). -/
def configuredLocalGraphRadius (opts : Lean.Options) : Nat :=
  opts.get verso.blueprint.nodePage.localGraphRadius.name
    verso.blueprint.nodePage.localGraphRadius.defValue

register_option verso.blueprint.nodePage.localGraphMaxNodes : Nat := {
  defValue := 0
  descr := "Node-count cap on the localized dependency graph drawn on each node/decl page. The radius-k neighborhood is expanded breadth-first, hop by hop, and stops admitting declarations once it holds this many (the focus declaration counts); the page then says how many declarations within the radius were left out. `0` ⇒ unlimited. At scale a hub declaration's radius-2 neighborhood is thousands of nodes and a multi-megabyte page; this bounds the page without changing the registry or the whole-site graph."
}

/-- The configured `verso.blueprint.nodePage.localGraphMaxNodes` (0 ⇒ unlimited, i.e.
every declaration within the radius). -/
def configuredLocalGraphMaxNodes (opts : Lean.Options) : Nat :=
  opts.get verso.blueprint.nodePage.localGraphMaxNodes.name
    verso.blueprint.nodePage.localGraphMaxNodes.defValue

register_option verso.blueprint.declPage.localGraphCompleteOnly : Bool := {
  defValue := false
  descr := "Whether a DECLARATION page draws its localized dependency graph only when it can draw the whole neighborhood the radius admits. Under `verso.blueprint.nodePage.localGraphMaxNodes` a hub declaration's graph is a breadth-first prefix of its neighborhood: the largest single payload on the page, and an arbitrary slice of a relation the properties rail's Uses / Used by lists already carry in full and exactly. With this on, such a page omits the graph section entirely rather than drawing the prefix; a page whose neighborhood fits draws it as before. NODE pages are unaffected — they are the curated surface and their graphs are the point. `false` ⇒ draw the truncated graph under the line that says how much it left out (the pre-option behavior)."
}

/-- The configured `verso.blueprint.declPage.localGraphCompleteOnly`. -/
def configuredLocalGraphCompleteOnly (opts : Lean.Options) : Bool :=
  opts.get verso.blueprint.declPage.localGraphCompleteOnly.name
    verso.blueprint.declPage.localGraphCompleteOnly.defValue

register_option verso.blueprint.declPage.sidebarToc : Bool := {
  defValue := true
  descr := "Whether declaration pages carry the book's sidebar table of contents. A `decl/<slug>/` page is reached from a catalog row, a graph node or the command palette, and it already carries the top nav and its own breadcrumb; the chapter ToC beside it is the part of its frame its readers do not use, and it is rebuilt into every one of the pages. Node, chapter and project-management pages are unaffected. `true` ⇒ the sidebar on declaration pages too (the pre-option behavior)."
}

/-- The configured `verso.blueprint.declPage.sidebarToc`. -/
def configuredDeclPageSidebarToc (opts : Lean.Options) : Bool :=
  opts.get verso.blueprint.declPage.sidebarToc.name
    verso.blueprint.declPage.sidebarToc.defValue

-- The subject-module machinery (`verso.blueprint.subjectModuleRoots`) lives in
-- `ExternalRefSnapshot`, which needs it for dependency source resolution and which
-- this module imports; re-exported here, where its main consumers are.
export Informal (configuredSubjectModuleRoots isProjectModule)

/-! ## Serializable schema -/

/-- One binder of a declaration's signature (from `forallTelescope`). -/
structure Param where
  name : String
  /-- Pretty-printed binder type. -/
  type : String
  /-- Binder visibility: `default`, `implicit`, `strictImplicit`, or `instImplicit`. -/
  binderInfo : String
deriving Inhabited, Repr, ToJson, FromJson

/-- A 1-based source position (line/column) mirroring `Lean.Position`. -/
structure Pos where
  line : Nat
  column : Nat
deriving Inhabited, Repr, ToJson, FromJson

/-- A declaration's full source range (1-based lines). -/
structure Range where
  pos : Pos
  endPos : Pos
deriving Inhabited, Repr, ToJson, FromJson

/-- One registry record: everything known about a single project declaration. -/
structure Entry where
  /-- Fully-qualified declaration name. -/
  name : String
  /-- Blueprint node kind (`Definition`/`Theorem`/…) derived from the `ConstantInfo`. -/
  kind : String
  /-- Module the declaration lives in. -/
  moduleName : String
  /-- Project-relative source path (e.g. `A362583/Defs.lean`). -/
  sourcePath : String
  /-- Full declaration source range, when the declaration ranges are known. -/
  range? : Option Range
  /-- Plain-text pretty-printed type signature (lightweight fallback). -/
  signatureText : String
  /-- Self-contained highlighted-signature HTML (inner token markup only; the
  consumer wraps it). `none` when the signature could not be rendered. -/
  signatureHtml? : Option String
  /-- Structured binders from `forallTelescope`. -/
  params : Array Param := #[]
  /-- Project-scoped const-level dependencies in the declaration's type. -/
  statementDeps : Array String := #[]
  /-- Project-scoped const-level dependencies in the declaration's value/proof. -/
  proofDeps : Array String := #[]
  /-- Const-level reverse edges: project declarations that use this one (in either
  their type or value), computed once over the full project declaration set. -/
  usedBy : Array String := #[]
  /-- Blueprint node label(s) formalizing this declaration; empty ⇒ unwired. -/
  nodeLabels : Array String := #[]
  /-- Root-relative href of this declaration's blueprint node page (`node/{slug}/`),
  from its first node label; `none` ⇒ unwired (no node page). Lets the metadata rail
  link a re-pointed wired declaration to its page without recomputing the slug
  client-side. Resolved against the page `<base href>` (the site root). -/
  nodeHref? : Option String := none
  /-- Proof/completeness status tag (`proved`/`missing`/`axiomLike`/`containsSorry`). -/
  status : String
  /-- Whether the declaration is wired to a blueprint node. -/
  authored : Bool := false
  /-- Short display name: the configured project prefix stripped (see
  `NodeCard.shortDeclName`); equals `name` when no prefix is configured / matched. -/
  shortName : String := ""
  /-- Whether the declaration is `private` (de-mangled for display; kept out of
  every dependency graph, including the synthesized decl-page local graphs). -/
  isPrivate : Bool := false
  /-- Whether the declaration is registered as an instance (`Meta.isInstanceCore`
  over the environment's instance extension, asked of the canonical name).

  Recorded for every declaration whether or not the site excludes instances from
  the page policy: the registry describes the library, and the policy
  (`verso.blueprint.declRegistry.pageExcludeInstances`) reads it. The catalog rows
  and the graph are unchanged by it. -/
  isInstance : Bool := false
  /-- Rendered docstring HTML (markdown + `$…$` math, raw HTML disabled — safe
  for the metadata rail's `innerHTML`); `none` when the declaration has no
  docstring. -/
  docstringHtml? : Option String := none
  /-- Root-relative href of this declaration's own page (`decl/{slug}/`), set for
  an **unwired** declaration whose page this build actually emits — wired
  declarations' canonical page stays their node page.

  So an entry has *at most* one of `nodeHref?`/`declHref?`, and exactly one unless
  this site gave it no page: an unwired entry with neither is a declaration left
  indexed but page-less, either by the page policy
  (`pageExcludeInstances`/`pageExcludePrivate`) or by the
  `verso.blueprint.declRegistry.maxDeclPages` scale cap. `DeclRoute.noPageReason?`
  says which.
  Ask `DeclRoute.hasDeclPage` / `DeclRoute.canonicalHref?` rather than reading this
  field or recomputing a slug — a guessed href is a confident link to a page that
  was never emitted. -/
  declHref? : Option String := none
  /-- Source link (consumer template or automatic GitHub blob URL, the same builder as
  `Data.ExternalRef.sourceHref?`); `none` when underivable.

  In the *elaboration-time* registry this holds only links that name no revision of
  this project's — a consumer template's output, or a blob URL into a lockfile-pinned
  dependency checkout. A declaration in the project's own repository arrives here as
  `sourceRepoPath?` and acquires its URL in `Registry.withResolvedSourceLinks`, so what
  the **published** artifact carries is always the whole set. -/
  sourceHref? : Option String := none
  /-- For a file in the project's **own** repository: its path relative to that
  repository's root, with no revision attached.

  Internal, and the one field of this structure that never reaches
  `-verso-data/decl-registry.json`: `withResolvedSourceLinks` consumes it into
  `sourceHref?` and clears it, mirroring how the proof/value `Bodies` stay out of the
  public JSON. It exists because the registry is built at elaboration and replayed from
  a warm `.lake` across commits, so a revision recorded here would go on naming the
  tree it was elaborated against after the build stamp had moved on (CX-066). -/
  sourceRepoPath? : Option String := none
  /-- Longest dependency-chain length below this declaration (0 = no project
  deps), over the project decl graph; `none` when unresolvable (cycle). -/
  depth? : Option Nat := none
  /-- Longest dependent-chain length above this declaration (0 = no project
  dependents); `none` when unresolvable (cycle). -/
  height? : Option Nat := none
  /-- Kernel axiom footprint (`Lean.collectAxioms`) — the same closure
  `#print axioms` reports. Sorted; empty means "audited, no axioms". `sorryAx`
  here is transitive evidence of an incomplete proof and is reflected in
  `status` (`containsSorry`) even when nothing in this declaration's own body
  carries a literal `sorry`. -/
  axioms : Array String := #[]
  /-- Which pipeline produced `signatureHtml?` — `"reelab"` / `"signature"` /
  `"delaborated"`; `none` when no signature was rendered. Emitted in the registry
  JSON as `sigTier`; not marked on the page. -/
  sigTier? : Option String := none
  /-- Which pipeline produced this declaration's proof/value body HTML —
  `"reelab"` / `"syntactic"` / `"raw"`; `none` when no body was captured. -/
  proofTier? : Option String := none
  /-- The caveat scan over this declaration's own statement (schema v3).

  **`none` is the not-scanned state**, and it is a different thing from a scan that
  matched nothing: a v2 registry has no scan at all, a build with
  `verso.blueprint.trust.statementCaveats` off did not look, and a `completed-zero`
  report looked and found nothing in a table it names. Consumers branch on all three
  rather than treating absence as an empty result.

  Coverage is deliberately the shallow one — this declaration's type constants plus one
  instance hop — and the report says so in the words the surface repeats. The deep
  meaning-closure scan is the certified-claim surface's, not the registry's. -/
  scan? : Option Informal.JunkValues.ScanReport := none
deriving Inhabited, Repr, ToJson, FromJson

/-- The full declaration registry artifact.

Schema v3 added each entry's optional `scan` (the caveat report). An entry that was not
scanned omits the key, so a v3 artifact from a build with the caveat surface off was
byte-identical to a v2 one apart from this number.

Schema v4 adds each entry's `isInstance`, which — like `isPrivate` beside it — is always
written. That is what the version number is for: the key is present on every entry of a
v4 artifact and on none of a v3 one, and a reader can tell which it has without probing.
The page policy that reads it (`pageExcludeInstances`) changes no other key: an entry it
denies a page loses `declHref`, exactly as the scale cap's does.

The published shape is unchanged by the CX-066 source-link binding: `sourceHref` is
still one resolved URL per entry, composed at emission rather than at elaboration, and
the internal `sourceRepoPath` it is composed from is cleared before serialization. A
clean build at one revision therefore emits exactly the bytes it emitted before. -/
structure Registry where
  schemaVersion : Nat := 4
  /-- The configured `verso.blueprint.declNamePrefix`, for client-side (runtime)
  name shortening of names that arrive outside the registry. Empty ⇒ none. -/
  namePrefix : String := ""
  declCount : Nat := 0
  decls : Array Entry := #[]
deriving Inhabited, Repr, ToJson, FromJson

/--
What the per-declaration-page scale cap
(`verso.blueprint.declRegistry.maxDeclPages`) did, when it did anything.

Carried through the traversal store rather than through `decl-registry.json`: the
public artifact needs no new key for this, because the cap is already visible in it
as the absent `declHref` on the declarations that lost their page. Present only when
the cap actually dropped pages, so a build below the cap stores nothing and the
surfaces stay word-for-word what they were.
-/
structure PageCap where
  /-- The configured `verso.blueprint.declRegistry.maxDeclPages`. -/
  limit : Nat := 0
  /-- Declaration pages this build emitted (equal to `limit` whenever the cap bound). -/
  emitted : Nat := 0
  /-- Declarations whose canonical page would be a `decl/` page — the unwired ones.
  Declarations a blueprint node presents are not counted: their canonical page is
  their node page, which the cap never touches. -/
  candidates : Nat := 0
deriving Inhabited, Repr, ToJson, FromJson, DecidableEq, Quote

/-- Declarations that lost their page to the cap. -/
def PageCap.omitted (cap : PageCap) : Nat := cap.candidates - cap.emitted

/--
What the per-declaration-page *policy*
(`verso.blueprint.declRegistry.pageExcludeInstances` /
`pageExcludePrivate`) did, when it did anything.

The policy runs before the scale cap and is a different kind of decision: the cap is a
budget that ranks declarations against each other, the policy is a statement about which
declarations are worth a page at all. The two compose in one direction — a declaration
the policy excluded is not a candidate the cap ranks — and are reported separately,
because "there was no room for this page" and "this kind of declaration does not get a
page here" are not the same disclosure.

Carried through the traversal store beside `PageCap`, for the same reason: what it did
is already visible in `decl-registry.json` as the absent `declHref`, so the public
artifact needs no new key for it. Present only when the policy actually excluded
something, so a build that turned it on and matched nothing stores nothing and the
surfaces stay word-for-word what they were.
-/
structure PagePolicy where
  /-- The configured `verso.blueprint.declRegistry.pageExcludeInstances`. -/
  excludeInstances : Bool := false
  /-- The configured `verso.blueprint.declRegistry.pageExcludePrivate`. -/
  excludePrivate : Bool := false
  /-- Unwired declarations denied a page because they are instances. -/
  instancesExcluded : Nat := 0
  /-- Unwired declarations denied a page because they are `private`. Disjoint from
  `instancesExcluded`: a private instance is counted once, under the instance rule. -/
  privateExcluded : Nat := 0
  /-- Declaration pages the policy leaves — the unwired declarations still eligible for
  one, which is exactly the set `applyDeclPageCap` then ranks. -/
  pages : Nat := 0
deriving Inhabited, Repr, ToJson, FromJson, DecidableEq, Quote

/-- Declarations the policy denied a page, by either rule. -/
def PagePolicy.excluded (p : PagePolicy) : Nat := p.instancesExcluded + p.privateExcluded

/-- Whether the page policy denies a declaration with these two properties a page of its
own. The decision itself, shared by `buildEntry` (which applies it per declaration) and
by the surfaces that explain it. -/
def policyExcludesPage (excludeInstances excludePrivate isInstance isPrivate : Bool) : Bool :=
  (excludeInstances && isInstance) || (excludePrivate && isPrivate)

/--
Record what the page policy did to a finished entry array — the entries as `buildEntry`
left them, *before* the scale cap runs.

`none` when neither rule is on, and also when both are on and neither matched: the
surfaces that report this exist to disclose a degradation, and there is nothing to
disclose about a policy that took nothing away. The counts are read back off the entries
rather than accumulated during the build so that they describe the artifact that shipped.
-/
def summarizePagePolicy (excludeInstances excludePrivate : Bool) (entries : Array Entry) :
    Option PagePolicy :=
  if !excludeInstances && !excludePrivate then none
  else
    let policy := entries.foldl (init := { excludeInstances, excludePrivate : PagePolicy })
      fun p e =>
        if e.declHref?.isSome then { p with pages := p.pages + 1 }
        else if !e.nodeLabels.isEmpty then p
        else if excludeInstances && e.isInstance then
          { p with instancesExcluded := p.instancesExcluded + 1 }
        else if excludePrivate && e.isPrivate then
          { p with privateExcluded := p.privateExcluded + 1 }
        else p
    if policy.excluded == 0 then none else some policy

/-- One captured proof/value body (the source after the top-level `:=`) for a
project declaration, keyed by its (de-mangled) fully-qualified name. `html?` is
the syntactically-highlighted token markup, `text?` the raw source fallback. -/
structure Body where
  name : String
  html? : Option String := none
  text? : Option String := none
deriving Inhabited, Repr, ToJson, FromJson

/--
The internal proof/value-bodies artifact: one `Body` per project declaration with
a capturable `:= …` body. **Never emitted into the public
`decl-registry.json`** — it is carried only through the traversal store
(`TraversalIndex.DeclRegistry`, key `"bodies"`) to the decl-page emitter
(`DeclPage`), which bakes each body into that declaration's static page. Sizes
are capped at capture time (`rawBodyCap`/`highlightBodyCap`).
-/
structure Bodies where
  schemaVersion : Nat := 1
  bodies : Array Body := #[]
deriving Inhabited, Repr, ToJson, FromJson

/-- Cap (in characters) on a captured raw proof/value body; larger bodies are
dropped entirely (the decl page degrades to its quiet placeholder). -/
def rawBodyCap : Nat := 100_000

/-- Cap (in characters) on a body eligible for syntactic highlighting; larger
bodies keep only the escaped raw source. -/
def highlightBodyCap : Nat := 40_000

/-! ## The per-declaration-page scale cap -/

/--
Apply the per-declaration-page cap to a finished entry array, returning the entries
with `declHref?` cleared on everything that lost its page, plus the record of what
was dropped (`none` when nothing was).

Which declarations keep a page:

* **Presented by a blueprint node.** Vacuously safe, and deliberately so: a presented
  declaration's canonical page is its *node* page, so it is never a `decl/` page
  candidate in the first place (`buildEntry` sets `declHref?` only when `nodeLabels`
  is empty). The same holds for every declaration named in a milestone member list,
  in `featured` dashboard cards, or in a `formalization.yaml` alignment row: those all
  name blueprint *labels*, whose declarations are wired by construction. So the cap
  cannot take a page away from anything the blueprint presents — not because it
  filters them out, but because they were never in the set it filters.
* **Not excluded by the page policy.** Same mechanism: a declaration the policy
  (`pageExcludeInstances` / `pageExcludePrivate`) denied a page arrives here with
  `declHref?` already cleared, so it is not a candidate and does not count toward
  what the cap reports.
* **The rest of the budget, by fan-in.** The remaining `limit` pages go to the
  candidates the most other declarations depend on (`usedBy` size, computed in the
  registry's pass 1), ties broken by name so the selection is deterministic across
  builds.

The cap binds only when it would actually drop something: a registry larger than
`limit` whose *candidates* still fit under it is left alone, so the reported counts
never describe a degradation that did not happen.
-/
def applyDeclPageCap (limit : Nat) (entries : Array Entry) :
    Array Entry × Option PageCap :=
  if limit == 0 || entries.size ≤ limit then (entries, none)
  else
    let candidates := entries.filter (·.declHref?.isSome)
    if candidates.size ≤ limit then (entries, none)
    else
      let ranked := candidates.qsort fun a b =>
        if a.usedBy.size == b.usedBy.size then a.name < b.name
        else a.usedBy.size > b.usedBy.size
      let keep : Std.HashSet String :=
        (ranked.extract 0 limit).foldl (fun s e => s.insert e.name) {}
      let capped := entries.map fun e =>
        if e.declHref?.isSome && !keep.contains e.name then { e with declHref? := none } else e
      (capped, some { limit, emitted := limit, candidates := candidates.size })

/-!
## Where a declaration's page is

The single place every surface asks whether a declaration has a page of its own, and
which page to link to. Before the scale cap, `declHref?.isSome` was the same thing as
"unwired", and several surfaces open-coded it; with the cap it is not, and a surface
that guesses a `decl/<slug>/` href from a name will confidently link to a page that
was never emitted. So the question has one answer, here.
-/

namespace DeclRoute

/-- Whether this declaration has a page of its own at `decl/<slug>/`.

False both for a declaration a blueprint node presents (its canonical page is that
node page) and for one this site gave no page. `pageOmitted` separates the two. -/
def hasDeclPage (e : Entry) : Bool := e.declHref?.isSome

/-- The page this declaration lives on: its blueprint node page when it has one, else
its own `decl/` page, else nothing at all — which is exactly the page-less case. -/
def canonicalHref? (e : Entry) : Option String := e.nodeHref? <|> e.declHref?

/-- Whether this declaration has no page of its own: unwired (so its page would have
been a `decl/` page) and without one. Distinguishes the degradation from a wired
declaration, which has a node page and needs no `decl/` one.

*Why* there is no page — the page policy or the scale cap — is `noPageReason?`, which
needs the policy record the entry alone does not carry. -/
def pageOmitted (e : Entry) : Bool := e.nodeLabels.isEmpty && e.declHref?.isNone

/-- Why an unwired declaration has no page of its own on this site. -/
inductive NoPage where
  /-- The `maxDeclPages` scale cap ranked it out of the budget. -/
  | overCap
  /-- Policy: it is an instance and this site excludes instances. -/
  | isInstance
  /-- Policy: it is `private` and this site excludes private declarations. -/
  | isPrivate
deriving Inhabited, Repr, DecidableEq

/-- Why this declaration has no page, or `none` when it has one (or is wired and needs
none).

The policy is checked first and in the order the two rules are applied, so the answer is
the rule that actually removed the page: with `excludeInstances` on, an instance never
reached the cap, and reporting it as over-cap would name a decision that was never made
about it. Everything left over is the cap, which is the only other way `declHref?` gets
cleared. -/
def noPageReason? (policy : PagePolicy) (e : Entry) : Option NoPage :=
  if !pageOmitted e then none
  else if policy.excludeInstances && e.isInstance then some .isInstance
  else if policy.excludePrivate && e.isPrivate then some .isPrivate
  else some .overCap

end DeclRoute

/-! ## Binding source links to the build's revision -/

/--
Give every project-local entry the source link it publishes, at `rev` — the revision
this site build describes itself by, and the same record the build stamp names.

This is where a declaration in the project's own repository acquires a revision at all.
Composing it here rather than at elaboration is the fix for CX-066: the registry is
built once and replayed from a warm `.lake` across commits, so a URL minted at
elaboration keeps naming the tree it was elaborated against while the stamp beside it
advances — a site presenting two different revisions as one provenance. Bound here, the
trust page's "\"View source\" links point at the commit the site was built from" holds
by construction, for the same reason the two values cannot differ: there is only one.

The line anchor is recomputed from the entry's own `range?`, and `sourceRepoPath?` is
cleared: it is elaboration-side bookkeeping and never appears in the published JSON.
Entries whose link was already final (a consumer template, a pinned dependency
checkout) pass through untouched — their revision is not this build's to move. A build
with no GitHub remote or no `HEAD` to name resolves to no link rather than to a guessed
one, which is the same way every other probe here degrades.
-/
def Registry.withResolvedSourceLinks (rev : Informal.Git.BuildRevision)
    (registry : Registry) : Registry :=
  { registry with
    decls := registry.decls.map fun e =>
      let fragment :=
        match e.range? with
        | some r => Informal.sourceLineFragment r.pos.line r.endPos.line
        | none => ""
      { e with
        sourceHref? := Informal.resolveSourceHref? rev e.sourceRepoPath? fragment e.sourceHref?
        sourceRepoPath? := none } }

/--
Decode the traversal-stored registry and bind its source links to this build's revision.

The one route from the stored artifact to a registry with publishable source links; the
revision comes from `RuntimeCache.currentBuildRevision`, probed once per process and
shared with the build stamp.
-/
def resolveStoredRegistry (raw : String) : IO (Except String Registry) := do
  let rev ← Informal.RuntimeCache.currentBuildRevision
  let decoded : Except String Registry := do
    let json ← Json.parse raw
    FromJson.fromJson? json
  pure <| decoded.map (Registry.withResolvedSourceLinks rev)

/-! ## Project boundary + enumeration (shared with the all-decls graph) -/

/--
Whether a declaration's source path belongs to the *project* rather than a vendored
dependency.

The boundary is the workspace tree — the consumer's own directory or a sibling
package one level up (the monorepo root) — matching Wave 1's sibling-package source
scan (`workspaceModuleSourcePath?`). Vendored dependency sources under
`.lake/packages/` are excluded, so an authored `(lean := …)` reference that happens
to point at a Mathlib/std declaration does not drag that whole namespace into the
project graph/registry.
-/
def isProjectSourcePath (workspaceRoot : System.FilePath) (p : String) : Bool :=
  if (p.splitOn "/.lake/").length > 1 then
    -- Vendored dependency source: not part of the project.
    false
  else
    let sep := System.FilePath.pathSeparator.toString
    let underPrefix := fun (base : String) =>
      let pre := if base.endsWith sep then base else base ++ sep
      p == base || p.startsWith pre
    let root := workspaceRoot.toString
    -- The sibling-package root (one level up) covers the consumer's own subtree.
    let parent := (workspaceRoot.parent.map (·.toString)).getD root
    underPrefix parent || underPrefix root

/--
The project's module-name roots.

When `verso.blueprint.subjectModuleRoots` is set, those roots *are* the answer: the
automatic harvest is skipped entirely. That is the supported configuration for a
consumer whose Lean content lives in a Lake/git dependency — its sources are under
`.lake/packages/`, hence outside the workspace by every boundary test here, so the
harvest can never find them.

Otherwise the roots are harvested from the modules containing authored
`(lean := …)` declarations whose source lives inside the project (see
`isProjectSourcePath`). Reading the blueprint environment extension lets authored
declarations define which namespaces count as "the project" — whether the
formalization is the consumer's own package or a sibling package. This is the fix
for the sibling-package no-op: the original harvest accepted only `.inWorkspace`
provenance, which is empty when the formalization is a separate package (all such
declarations are `.outWorkspace`).
-/
def projectModuleRoots : CoreM NameSet := do
  let env ← getEnv
  let configured := configuredSubjectModuleRoots (← getOptions)
  if !configured.isEmpty then
    for root in configured do
      unless env.header.moduleNames.any (Informal.moduleUnderRoot root) do
        if ← liftM (Informal.RuntimeCache.claimSubjectRootWarning (toString root)) then
          logWarning m!"verso.blueprint.subjectModuleRoots names `{root}`, which matches no \
            imported module; its declarations will be missing from the registry, the \
            all-declarations graph, and the declaration pages."
    return configured.foldl (init := ({} : NameSet)) (·.insert ·)
  let st := informalExt.getState env
  let workspaceRoot ← Informal.workspaceRoot
  return st.data.foldl (init := ({} : NameSet)) fun acc _label node =>
    node.externalRefs.foldl (init := acc) fun acc ref =>
      match ref.provenance.moduleName?, ref.provenance.sourcePath? with
      | some moduleName, some sourcePath =>
        if isProjectSourcePath workspaceRoot sourcePath then
          let r := moduleName.getRoot
          if r.isAnonymous then acc else acc.insert r
        else
          acc
      | _, _ => acc

/--
Every definition/theorem/inductive-like declaration in the project's own modules,
paired with its (canonical, possibly private-mangled) `ConstantInfo` name and
defining module.

Compiler-internal byproducts (equational lemmas, `match_`/`proof_` auxiliaries,
recursors, projections' internals, …) are filtered via `isInternalDetail` *and*
`Lean.isAutoDeclOrPrivate_Internal`, both applied to the *user-facing* name so a
`private` user declaration survives while its own internal byproducts do not.

`isInternalDetail` alone is not enough: it recognises the `_`-prefixed and
macro-scoped families, but v4.32 also generates plenty of unprefixed companions —
`f.congr_simp` for every definition, and for every structure a `ctorIdx`,
`casesOn`, `recOn`, `noConfusion`, `noConfusionType`, `mk.inj`, `mk.injEq`,
`mk.sizeOf_spec`. Those are indistinguishable from hand-written declarations by
name shape, and a corpus with one structure in it acquired thirteen of them, each
of which would otherwise become a registry entry, a graph node, a declaration page
and (for a generated blueprint) a prose slot for someone to write about
`PaletteBlockCertificate.mk.injEq`. `isAutoDeclOrPrivate_Internal` is Lean's own
notion of "generated, not written" — it consults `isReservedName` and the
inductive/constructor suffix families — and it keeps genuine structure projections
(`c.palette`, `c.label`), which are real API.

`includePrivate := false` (the all-decls graph) keeps the graph readable by
dropping `private` helpers; `includePrivate := true` (the declaration registry)
tracks every project declaration per the "track every declaration" directive. The
returned name is always the canonical (private-mangled) environment name, so
`ConstantInfo` lookup and const-level dependency matching stay exact; callers
de-mangle for display via `privateToUserName?`.
-/
def enumerateProjectDecls (roots : NameSet) (includePrivate : Bool := false) :
    CoreM (Array (Name × ConstantInfo × Name)) := do
  let env ← getEnv
  let moduleNames := env.header.moduleNames
  let moduleData := env.header.moduleData
  let mut decls : Array (Name × ConstantInfo × Name) := #[]
  let mut seen : NameSet := {}
  for i in [0:moduleData.size] do
    let modName := (moduleNames[i]?).getD Name.anonymous
    if !isProjectModule roots modName then continue
    for cname in moduleData[i]!.constNames do
      let cname := cname.eraseMacroScopes
      if seen.contains cname then continue
      -- Judge internal-ness on the user-facing name so `private` user declarations
      -- survive (when requested) but their compiler byproducts never do.
      let userName := if includePrivate then (privateToUserName? cname).getD cname else cname
      if userName.isInternalDetail then continue
      if ← Lean.isAutoDeclOrPrivate_Internal userName then continue
      match env.find? cname with
      | some cinfo =>
        if (Informal.Data.ConstantInfo.blueprintNodeKind? cinfo).isSome then
          decls := decls.push (cname, cinfo, modName)
          seen := seen.insert cname
      | none => pure ()
  return decls

/-! ## Per-declaration record construction -/

private def binderInfoTag : BinderInfo → String
  | .default => "default"
  | .implicit => "implicit"
  | .strictImplicit => "strictImplicit"
  | .instImplicit => "instImplicit"

/-- Strip Lean's inaccessible-name dagger (`✝`, optionally trailed by superscript
hygiene digits like `✝¹`) from pretty-printed text. A declaration's type prints
references to a *private* constant with this marker (e.g. `A362583.t✝`); it must
never reach `signatureText`, since `✝` is not valid Lean syntax and therefore both
breaks the purely-syntactic signature highlight (`highlightProofSourceHtml?`, which
re-parses the text) — leaving `signatureHtml?` empty — and reads as visual noise in
the plain-text fallback. Removing it yields the plain qualified name; superscripts
elsewhere (not directly after a dagger) are preserved. -/
private def stripInaccessibleDagger (s : String) : String :=
  let isSuper : Char → Bool := fun c => "⁰¹²³⁴⁵⁶⁷⁸⁹".toList.contains c
  (s.foldl (fun (st : String × Bool) c =>
      let (acc, dropping) := st
      if c == '✝' then (acc, true)
      else if dropping && isSuper c then (acc, true)
      else (acc.push c, false))
    ("", false)).1

private def provedStatusTag : Data.ProvedStatus → String
  | .proved => "proved"
  | .missing => "missing"
  | .axiomLike => "axiomLike"
  | .containsSorry _ => "containsSorry"

/-- Structured binders of a declaration's type via `forallTelescope`. -/
private def declParams (type : Expr) : MetaM (Array Param) :=
  forallTelescope type fun xs _body =>
    xs.mapM fun x => do
      let ld ← x.fvarId!.getDecl
      let tyStr := stripInaccessibleDagger (← ppExpr ld.type).pretty
      pure {
        name := ld.userName.toString
        type := tyStr
        binderInfo := binderInfoTag ld.binderInfo
      }

/--
Longest-path lengths over a DAG given as dependency adjacency (`adj[i]` = the
node indices `i` depends on): `some d` where `d` is the longest chain strictly
below node `i` (0 when it has no deps). Kahn-style: a node's length is final
once all its deps are resolved; nodes stuck on a dependency cycle (possible for
mutually-recursive declarations) resolve to `none` rather than a wrong value.
-/
private partial def longestPathLengths (adj : Array (Array Nat)) : Array (Option Nat) := Id.run do
  let n := adj.size
  let mut rev : Array (Array Nat) := Array.replicate n #[]
  for i in [0:n] do
    for d in adj[i]! do
      rev := rev.modify d (·.push i)
  let mut remaining : Array Nat := adj.map (·.size)
  let mut dist : Array Nat := Array.replicate n 0
  let mut finished : Array Bool := Array.replicate n false
  let mut queue : Array Nat := #[]
  for i in [0:n] do
    if remaining[i]! == 0 then queue := queue.push i
  let mut qi := 0
  while qi < queue.size do
    let i := queue[qi]!
    qi := qi + 1
    finished := finished.set! i true
    for j in rev[i]! do
      if dist[j]! < dist[i]! + 1 then
        dist := dist.set! j (dist[i]! + 1)
      let r := remaining[j]! - 1
      remaining := remaining.set! j r
      if r == 0 then queue := queue.push j
  return (Array.range n).map fun i => if finished[i]! then some dist[i]! else none

/-- Build the full registry record for one project declaration. `sourcePath?` and
`ranges?` are resolved by the caller (shared with the body-capture pass so the
per-module source file is read once); `depth?`/`height?` come from the global
longest-path computation over the project decl graph. -/
private def buildEntry (workspaceRoot : System.FilePath) (namePrefix : String)
    (leanNameLabels : NameMap (Array Data.Label)) (usedByNames : Array Name)
    (name : Name) (cinfo : ConstantInfo) (moduleName : Name)
    (sourcePath? : Option System.FilePath) (ranges? : Option DeclarationRanges)
    (statementDeps proofDeps : Array Name)
    (depth? height? : Option Nat)
    (caveatIndex? : Option Informal.JunkValues.Index)
    (sigSourceHtml? : Option String := none)
    (sigTier? proofTier? : Option String := none) : MetaM Entry := do
  let range? : Option Range := ranges?.map fun r =>
    { pos := { line := r.range.pos.line, column := r.range.pos.column }
      endPos := { line := r.range.endPos.line, column := r.range.endPos.column } }
  let sourcePath : String :=
    match sourcePath? with
    | some p => elegantSourcePath workspaceRoot (some moduleName) p
    | none => (toString moduleName).replace "." "/" ++ ".lean"
  -- De-mangle private declarations to their user-facing name for all display fields;
  -- dependency edges are computed against the canonical (mangled) names, so this must
  -- be applied uniformly to `name`, deps, and `usedBy` to keep cross-references valid.
  let display := fun (n : Name) => ((privateToUserName? n).getD n).toString
  let signatureText := stripInaccessibleDagger (← ppExpr cinfo.type).pretty
  -- Highlighted signature (syntactic + semantic when info is available); degrade to
  -- `none` on any failure so registry construction never fails on an odd signature.
  -- `private` declarations skip `Signature.forName` (it embeds the leading declaration
  -- name, which would surface the internal `_private.…` mangling) and instead fall
  -- back to a purely syntactic highlight of the pretty-printed type; consumers degrade
  -- further to an escaped `<pre>` of `signatureText` when that parse fails too.
  -- Prefer the verbatim-source signature (full hovers + the author's exact layout,
  -- resolved by the caller from local source) for both public and private decls.
  -- Fall back to the delaborated `Signature.forName` (public) / syntactic type
  -- highlight (private) when no local-source signature is available.
  let signatureHtml? ←
    match sigSourceHtml? with
    | some html => pure (some html)
    | none =>
      if isPrivateName name then
        highlightProofSourceHtml? signatureText
      else
        try
          pure (some ((← Verso.Genre.Manual.Signature.forName name).wide |> renderHighlightedSelfContainedHtml))
        catch _ =>
          pure none
  -- Which pipeline actually produced the signature markup above (the caller
  -- reports the source-re-elaboration tier when it had one). Private decls fall
  -- back to a purely syntactic highlight; public ones to the delaborated form.
  let sigTier? : Option String :=
    match sigTier?, signatureHtml? with
    | some t, _ => some t
    | none, none => none
    | none, some _ => if isPrivateName name then some "syntactic" else some "delaborated"
  -- Kernel axiom audit (layer A, registry side): the transitive axiom closure.
  -- `sorryAx` in it means the proof is incomplete even when this declaration's own
  -- body carries no literal `sorry`, so it upgrades the reported status.
  let axioms ← Informal.declAxiomNames name
  let directStatus :=
    Informal.Data.ConstantInfo.blueprintProvedStatus cinfo (allowOpaque := true)
  let status :=
    if axioms.contains (toString Informal.sorryAxiomName) then
      match directStatus with
      | .containsSorry _ | .axiomLike => directStatus
      | _ => Data.ProvedStatus.containsSorry #[{ location := .proof }]
    else directStatus
  let params ← declParams cinfo.type
  -- Blueprint labels are keyed by the referenced name; authored decls are public, but
  -- fall back to the de-mangled name for robustness.
  let labels :=
    let byCanon := leanNameLabels.getD name #[]
    if byCanon.isEmpty then leanNameLabels.getD ((privateToUserName? name).getD name) #[] else byCanon
  let nodeLabels := labels.map fun l => (l : Name).toString
  -- Root-relative node-page href from the first label, matching the node-page and
  -- xref slug scheme (`node/{slug}/`); `none` for unwired declarations.
  let nodeHref? : Option String :=
    labels[0]?.map fun l => s!"node/{Informal.NodeRoute.nodePageSlug (l : Name)}/"
  let displayName := display name
  -- Instance-hood, from the environment's instance extension. Asked of the canonical
  -- (possibly `_private.…`-mangled) name, which is what the extension is keyed by.
  let isInstance := Lean.Meta.isInstanceCore (← getEnv) name
  let isPrivate := isPrivateName name
  -- Unwired declarations get their own `decl/{slug}/` page (see `DeclPage`); wired
  -- ones keep their node page as the canonical page, so exactly one href is set.
  -- The page policy subtracts from the unwired set before the scale cap ever sees it:
  -- an excluded declaration keeps every other field it has — it is in the registry, the
  -- catalogs, the audit and the graph — and loses only the page, which is what
  -- `declHref?` is.
  let opts ← getOptions
  let excludedByPolicy :=
    policyExcludesPage (configuredPageExcludeInstances opts) (configuredPageExcludePrivate opts)
      isInstance isPrivate
  let declHref? : Option String :=
    if nodeLabels.isEmpty && !excludedByPolicy then
      some (Informal.NodeRoute.declPageHref displayName)
    else none
  -- Docstring, rendered once here (markdown + math, raw HTML disabled) so the
  -- metadata rail can inject it without a client-side renderer.
  let docs? ← findDocString? (← getEnv) name
  let docstringHtml? := docstringHtmlString? docs?
  -- Source link via the same classifier the external-ref snapshot uses. A file in the
  -- project's own repository keeps only its repository-relative path: this registry is
  -- replayed from `.lake` across commits, and the revision is emission's to supply.
  let sourceLink? ←
    liftM <| sourceLinkFor? opts workspaceRoot (some moduleName) sourcePath?
      (ranges?.map (·.range))
  let sourceRepoPath? : Option String :=
    match sourceLink? with
    | some (.project relPath) => some relPath
    | _ => none
  let sourceHref? : Option String :=
    match sourceLink? with
    | some (.fixed url) => some url
    | _ => none
  return {
    name := displayName
    kind := toString ((Informal.Data.ConstantInfo.blueprintNodeKind? cinfo).getD Data.NodeKind.definition)
    moduleName := moduleName.toString
    sourcePath
    range?
    signatureText
    signatureHtml?
    params
    statementDeps := statementDeps.map display
    proofDeps := proofDeps.map display
    usedBy := usedByNames.map display
    nodeLabels
    nodeHref?
    status := provedStatusTag status
    authored := !nodeLabels.isEmpty
    shortName := Informal.NodeCard.shortDeclName namePrefix displayName
    isPrivate
    isInstance
    docstringHtml?
    declHref?
    sourceHref?
    sourceRepoPath?
    depth?
    height?
    axioms
    sigTier?
    proofTier?
    -- The shallow scan, over this declaration's own type. `none` when the caveat surface
    -- is off, which the consumers render as not-scanned rather than as no findings.
    scan? := caveatIndex?.map (Informal.JunkValues.scanDeclType (← getEnv) · cinfo.type)
  }

/--
Build the declaration registry over the whole project — plus the internal
proof/value `Bodies` artifact — or empty artifacts when there are no project
modules (e.g. the flag is off, or no authored declaration has a resolvable
project source).

Reverse (`usedBy`) edges are computed once here over the full project declaration
set from the same project-scoped const dependencies (`projectConstDeps`) that the
graph augmentation uses; clients read them directly rather than recomputing.
`depth?`/`height?` come from one longest-path pass over the same edges. Body
capture reads each module's source file **once** (per-module file-content cache)
and slices every declaration's `:= …` body out of the cached content, with size
caps (`rawBodyCap`/`highlightBodyCap`) so a pathological body can never balloon
the store.
-/
def buildDeclRegistry :
    CoreM (Registry × Bodies × Array Informal.TrustInputs.Input × Option PageCap ×
      Option PagePolicy) := do
  let env ← getEnv
  let st := informalExt.getState env
  let workspaceRoot ← Informal.workspaceRoot
  let namePrefix := configuredNamePrefix (← getOptions)
  let fullElabMaxDecls := configuredFullElabMaxDecls (← getOptions)
  let maxDeclPages := configuredMaxDeclPages (← getOptions)
  let pageExcludeInstances := configuredPageExcludeInstances (← getOptions)
  let pageExcludePrivate := configuredPageExcludePrivate (← getOptions)
  let roots ← projectModuleRoots
  if roots.isEmpty then
    return ({}, {}, #[], none, none)
  -- The caveat table, read once for the whole registry. A configured override that is
  -- unusable is a build error here as it is on the trust path: the two surfaces answer to
  -- one switch and one table, and a registry that silently fell back to the bundled table
  -- would name a version the consumer did not configure.
  let caveatsOn := Informal.JunkValues.caveatsEnabled (← getOptions)
  let opts ← getOptions
  let caveatPath := if caveatsOn then Informal.JunkValues.tableOverridePath opts else ""
  let caveatTable? : Option Informal.JunkValues.Table ←
    if caveatsOn then
      match ← Informal.JunkValues.loadTableWithOverride caveatPath with
      | .error err =>
        if caveatPath.isEmpty then
          throwError "the caveat table this fork ships is unusable: {err}"
        else
          throwError "option 'verso.blueprint.trust.junkValueTable' {err}"
      | .ok (t, override?) =>
        -- A configured override whose keys name nothing here is a broken configuration,
        -- not a table that found nothing (CX-060).
        if let some override := override? then
          if let some reason :=
              Informal.JunkValues.overrideUnusableReason? env caveatPath override then
            throwError "option 'verso.blueprint.trust.junkValueTable' {reason}"
        pure (some t)
    else pure none
  -- Resolved against the environment this scan runs in, so a key that could not have
  -- matched is reported as such rather than as silence.
  let caveatIndex? : Option Informal.JunkValues.Index := caveatTable?.map (·.indexIn env)
  -- What this registry build read that Lake does not track. The caveat-table override is
  -- the only such file, and it is why this record exists: the per-entry scan below is
  -- quoted into the `blueprint_graph` block's `.olean`, so editing only the override
  -- leaves the previous scan — its behaviour sentences, its table version and digest —
  -- for a warm rebuild to republish (CX-062). `Informal.TrustFreshness` re-reads these
  -- before anything is written. Probed after the load, so a missing file is still the
  -- loader's own build error rather than an IO exception.
  let mut registryInputs : Array Informal.TrustInputs.Input := #[]
  if caveatTable?.isSome then
    if let some i ←
        Informal.TrustInputs.Input.probe? Informal.TrustInputs.roleCaveatTable caveatPath then
      registryInputs := registryInputs.push i
  -- The registry tracks every project declaration, `private` helpers included (the
  -- all-decls graph keeps them out to stay readable — see `enumerateProjectDecls`).
  let decls ← enumerateProjectDecls roots (includePrivate := true)
  -- Scale cap (c): above `fullElabMaxDecls` the per-entry full (statement + proof)
  -- re-elaboration from source — ~one real elaboration per theorem/def, the dominant
  -- time/memory cost — is skipped. The signature then re-elaborates on the cheaper
  -- signature-only path (`signature` tier) and the proof body falls back to syntactic
  -- highlighting (`syntactic` tier), both recorded as such. `0` ⇒ never skip.
  let skipFullElab := fullElabMaxDecls > 0 && decls.size > fullElabMaxDecls
  let projectDeclSet : NameSet := decls.foldl (init := {}) fun acc (n, _, _) => acc.insert n
  let leanNameLabels := st.leanNameLabels
  -- Pass 1 (pure): forward const-level deps per declaration + the reverse index.
  let mut fwd : Array (Array Name × Array Name) := #[]
  let mut usedBy : NameMap (Array Name) := {}
  for (n, ci, _) in decls do
    let (typeDeps, valueDeps) := Informal.Graph.projectConstDeps projectDeclSet n ci
    fwd := fwd.push (typeDeps, valueDeps)
    for dep in typeDeps ++ valueDeps do
      let cur := usedBy.getD dep #[]
      if !cur.contains n then
        usedBy := usedBy.insert dep (cur.push n)
  -- Longest-path metrics over the project decl graph (indices into `decls`).
  let idxOf : Std.HashMap Name Nat := Id.run do
    let mut m : Std.HashMap Name Nat := {}
    for i in [0:decls.size] do
      m := m.insert (decls[i]!).1 i
    return m
  let depAdj : Array (Array Nat) := fwd.map fun (typeDeps, valueDeps) =>
    (typeDeps ++ valueDeps).foldl (init := (#[] : Array Nat)) fun acc dep =>
      match idxOf.get? dep with
      | some j => if acc.contains j then acc else acc.push j
      | none => acc
  let depths := longestPathLengths depAdj
  let revAdj : Array (Array Nat) := Id.run do
    let mut rev : Array (Array Nat) := Array.replicate depAdj.size #[]
    for i in [0:depAdj.size] do
      for j in depAdj[i]! do
        rev := rev.modify j (·.push i)
    return rev
  let heights := longestPathLengths revAdj
  -- Pass 2: signatures, params, ranges, source paths, bodies. Each entry runs in a
  -- fresh `MetaM` (matching the external-ref snapshot path) so a failed signature
  -- render on one declaration cannot bleed metavariable state into the next.
  let mut entries : Array Entry := #[]
  let mut bodies : Array Body := #[]
  let mut fileCache : Std.HashMap String (Option String) := {}
  -- Coverage counters for the full-declaration (statement + proof) re-elaboration:
  -- attempts (theorems/defs with local source) and successes, reported below.
  let mut fullDeclAttempts : Nat := 0
  let mut fullDeclOk : Nat := 0
  for i in [0:decls.size] do
    let (n, ci, modName) := decls[i]!
    let (typeDeps, valueDeps) := fwd[i]!
    let ranges? ← findDeclarationRanges? n
    let sourcePath? ← sourcePathForModule? workspaceRoot modName
    -- Per-module cached file content, read once and shared by the verbatim-source
    -- signature highlight and the proof/value body capture below (degrades to no
    -- content on any read failure — both consumers fall back).
    let content? : Option String ←
      match sourcePath? with
      | none => pure none
      | some p => do
        let key := p.toString
        match fileCache.get? key with
        | some cached => pure cached
        | none => do
          let read? : Option String ←
            try
              pure (some (← IO.FS.readFile p))
            catch _ =>
              pure none
          fileCache := fileCache.insert key read?
          pure read?
    -- Full-declaration re-elaboration (statement + proof body) from verbatim source:
    -- one real elaboration yielding both the signature highlight and a semantically
    -- highlighted proof body. Only for theorems/defs with local source; degrades to
    -- `none` on failure (signature then via the `opaque` path, body via the syntactic
    -- path), so no declaration is double-elaborated.
    let fullDecl? : Option (SubVerso.Highlighting.Highlighted ×
        Option SubVerso.Highlighting.Highlighted) ←
      if skipFullElab then pure none
      else match content?, ranges? with
      | some content, some ranges =>
        if Informal.isFullReelabCandidate ci then
          fullDeclAttempts := fullDeclAttempts + 1
          let r ← Informal.highlightDeclFromSource? n content ranges.range
          if r.isSome then fullDeclOk := fullDeclOk + 1
          pure r
        else pure none
      | _, _ => pure none
    -- Verbatim-source signature (full hovers + the author's exact layout) when the
    -- declaration has an elaboratable `binders : type` signature and local source.
    -- Prefer the full-decl re-elaboration's signature; else re-elaborate just the
    -- signature as an `opaque`. Degrades to `none` (→ delaborated `Signature.forName`
    -- in `buildEntry`) on any parse/elaboration failure.
    let sigSourceHtml? : Option String ←
      match fullDecl? with
      | some (sigHl, _) => pure (some (Informal.renderHighlightedSelfContainedHtml sigHl))
      | none =>
        match content?, ranges? with
        | some content, some ranges =>
          if Informal.isStatementSignatureCandidate ci then
            match ← Informal.highlightStatementFromSource? n content ranges.range with
            | some hl => pure (some (Informal.renderHighlightedSelfContainedHtml hl))
            | none => pure none
          else pure none
        | _, _ => pure none
    -- Rendering tier for the signature, decided exactly where the fallback chain
    -- above resolved (`buildEntry` fills in the delaborated/syntactic fallback when
    -- neither source path produced markup).
    let sigTier? : Option String :=
      match fullDecl?, sigSourceHtml? with
      | some _, _ => some "reelab"
      | none, some _ => some "signature"
      | none, none => none
    -- Proof/value body, from the per-module cached file content (degrades to no
    -- body on any read/slice failure — the decl page shows its quiet placeholder).
    -- Captured *before* the entry so the entry can record which tier produced it.
    let bodyText? : Option String :=
      match content?, ranges? with
      | some content, some ranges =>
        (Informal.proofSourceFromContent? content ranges.range).filter (·.length ≤ rawBodyCap)
      | _, _ => none
    let bodyHtml? : Option String ←
      match bodyText? with
      | none => pure none
      | some src =>
        -- Prefer the fully re-elaborated proof body (real hovers); else syntactic.
        match fullDecl? with
        | some (_, some bodyHl) => pure (some (Informal.renderHighlightedSelfContainedHtml bodyHl))
        | _ =>
          if src.length ≤ highlightBodyCap then highlightProofSourceHtml? src else pure none
    -- Body tier: the size caps above silently drop highlighting (>40k chars) or the
    -- whole body (>100k); recording the tier makes that visible on the page.
    let proofTier? : Option String :=
      match bodyText? with
      | none => none
      | some _ =>
        match fullDecl? with
        | some (_, some _) => some "reelab"
        | _ => if bodyHtml?.isSome then some "syntactic" else some "raw"
    -- Re-baseline the heartbeat budget per entry (`withCurrHeartbeats`): the whole
    -- registry runs in ONE `CoreM` lift of the `{blueprint_graph}` command, whose
    -- `initHeartbeats` is fixed for the lift — without a reset, the loop's own
    -- accumulated spend (`ppExpr`, `Signature.forName`, …, over hundreds of decls)
    -- would eventually trip a later entry's `whnf` budget check.
    let entry ← withCurrHeartbeats <|
      (buildEntry workspaceRoot namePrefix leanNameLabels (usedBy.getD n #[])
        n ci modName sourcePath? ranges? typeDeps valueDeps
        depths[i]! heights[i]! caveatIndex? sigSourceHtml? sigTier? proofTier?).run'
    entries := entries.push entry
    match bodyText? with
    | some src => bodies := bodies.push { name := entry.name, html? := bodyHtml?, text? := some src }
    | none => pure ()
  if skipFullElab then
    logInfo s!"declaration registry: {decls.size} decls exceeds \
      verso.blueprint.declRegistry.fullElabMaxDecls={fullElabMaxDecls}; skipped per-entry \
      full re-elaboration (signatures on the signature tier, proof bodies syntactic)"
  else if fullDeclAttempts > 0 then
    logInfo s!"full-decl re-elaboration: {fullDeclOk}/{fullDeclAttempts} succeeded"
  -- Page policy: which declarations are worth a page at all. Applied per entry in
  -- `buildEntry` (it is a property of the declaration, not of the set), summarized here
  -- over the finished entries — before the cap, whose candidate set it has already
  -- narrowed.
  let declPagePolicy? := summarizePagePolicy pageExcludeInstances pageExcludePrivate entries
  if let some policy := declPagePolicy? then
    logInfo s!"declaration pages: policy excluded {policy.instancesExcluded} instances \
      and {policy.privateExcluded} private declarations; {policy.pages} declarations \
      remain eligible for a page of their own"
  -- Scale cap (e): above `maxDeclPages` only the highest-fan-in unwired declarations
  -- keep a `decl/` page of their own. The registry itself still carries every
  -- declaration — the index is cheap, the per-declaration page is not — so the catalog
  -- pages, module tree, and properties rail are unchanged; what the dropped entries
  -- lose is `declHref?`, which is what every linking surface reads.
  let (cappedEntries, declPageCap?) := applyDeclPageCap maxDeclPages entries
  if let some cap := declPageCap? then
    logInfo s!"declaration pages: {cap.candidates} declarations have no blueprint node, \
      which exceeds verso.blueprint.declRegistry.maxDeclPages={cap.limit}; emitting pages \
      for the {cap.emitted} with the highest fan-in and indexing the other \
      {cap.omitted} without a page"
  return (
    { schemaVersion := 4, namePrefix, declCount := cappedEntries.size, decls := cappedEntries },
    { bodies },
    registryInputs,
    declPageCap?,
    declPagePolicy?)

end Informal.DeclRegistry
