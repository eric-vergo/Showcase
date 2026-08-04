/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean
import Std.Data.HashMap
import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.ProvedStatus
import VersoBlueprint.Environment
import VersoBlueprint.Graph
import VersoBlueprint.ExternalRefSnapshot
import VersoBlueprint.ExternalDeclRender
import VersoBlueprint.NodeCard
import VersoBlueprint.NodeRoute

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
  /-- Rendered docstring HTML (markdown + `$…$` math, raw HTML disabled — safe
  for the metadata rail's `innerHTML`); `none` when the declaration has no
  docstring. -/
  docstringHtml? : Option String := none
  /-- Root-relative href of this declaration's own page (`decl/{slug}/`), set
  **iff unwired** — wired declarations' canonical page stays their node page, so
  every entry has exactly one of `nodeHref?`/`declHref?`. -/
  declHref? : Option String := none
  /-- Source link (consumer template or automatic GitHub blob URL, the same
  builder as `Data.ExternalRef.sourceHref?`); `none` when underivable. -/
  sourceHref? : Option String := none
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
  `"delaborated"`; `none` when no signature was rendered. See
  `Informal.NodeCard.tierMarker`. -/
  sigTier? : Option String := none
  /-- Which pipeline produced this declaration's proof/value body HTML —
  `"reelab"` / `"syntactic"` / `"raw"`; `none` when no body was captured. -/
  proofTier? : Option String := none
deriving Inhabited, Repr, ToJson, FromJson

/-- The full declaration registry artifact. -/
structure Registry where
  schemaVersion : Nat := 2
  /-- The configured `verso.blueprint.declNamePrefix`, for client-side (runtime)
  name shortening of names that arrive outside the registry. Empty ⇒ none. -/
  namePrefix : String := ""
  declCount : Nat := 0
  decls : Array Entry := #[]
deriving Inhabited, Repr, ToJson, FromJson

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
  -- Unwired declarations get their own `decl/{slug}/` page (see `DeclPage`); wired
  -- ones keep their node page as the canonical page, so exactly one href is set.
  let declHref? : Option String :=
    if nodeLabels.isEmpty then some (Informal.NodeRoute.declPageHref displayName) else none
  -- Docstring, rendered once here (markdown + math, raw HTML disabled) so the
  -- metadata rail can inject it without a client-side renderer.
  let docs? ← findDocString? (← getEnv) name
  let docstringHtml? := docstringHtmlString? docs?
  -- Source link via the same builder the external-ref snapshot uses.
  let sourceHref? ←
    liftM <| sourceLinkHref? (← getOptions) workspaceRoot (some moduleName) sourcePath?
      (ranges?.map (·.range))
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
    isPrivate := isPrivateName name
    docstringHtml?
    declHref?
    sourceHref?
    depth?
    height?
    axioms
    sigTier?
    proofTier?
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
def buildDeclRegistry : CoreM (Registry × Bodies) := do
  let env ← getEnv
  let st := informalExt.getState env
  let workspaceRoot ← Informal.workspaceRoot
  let namePrefix := configuredNamePrefix (← getOptions)
  let roots ← projectModuleRoots
  if roots.isEmpty then
    return ({}, {})
  -- The registry tracks every project declaration, `private` helpers included (the
  -- all-decls graph keeps them out to stay readable — see `enumerateProjectDecls`).
  let decls ← enumerateProjectDecls roots (includePrivate := true)
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
      match content?, ranges? with
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
        depths[i]! heights[i]! sigSourceHtml? sigTier? proofTier?).run'
    entries := entries.push entry
    match bodyText? with
    | some src => bodies := bodies.push { name := entry.name, html? := bodyHtml?, text? := some src }
    | none => pure ()
  if fullDeclAttempts > 0 then
    logInfo s!"full-decl re-elaboration: {fullDeclOk}/{fullDeclAttempts} succeeded"
  return (
    { schemaVersion := 2, namePrefix, declCount := entries.size, decls := entries },
    { bodies })

end Informal.DeclRegistry
