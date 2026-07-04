/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
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
shared with the all-decls graph augmentation. The registry is the more inclusive
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
The project's module-name roots: the roots of the modules containing authored
`(lean := …)` declarations whose source lives inside the project (see
`isProjectSourcePath`).

Reads the blueprint environment extension, so authored declarations define which
namespaces count as "the project" — whether the formalization is the consumer's own
package or a sibling package. This is the fix for the sibling-package no-op: the
original harvest accepted only `.inWorkspace` provenance, which is empty when the
formalization is a separate package (all such declarations are `.outWorkspace`).
-/
def projectModuleRoots : CoreM NameSet := do
  let env ← getEnv
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
recursors, projections' internals, …) are filtered via `isInternalDetail`, applied
to the *user-facing* name so a `private` user declaration survives while its own
internal byproducts do not.

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
    if !roots.contains modName.getRoot then continue
    for cname in moduleData[i]!.constNames do
      let cname := cname.eraseMacroScopes
      if seen.contains cname then continue
      -- Judge internal-ness on the user-facing name so `private` user declarations
      -- survive (when requested) but their compiler byproducts never do.
      let userName := if includePrivate then (privateToUserName? cname).getD cname else cname
      if userName.isInternalDetail then continue
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
      let tyStr := (← ppExpr ld.type).pretty
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
    (depth? height? : Option Nat) : MetaM Entry := do
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
  let signatureText := (← ppExpr cinfo.type).pretty
  -- Highlighted signature (syntactic + semantic when info is available); degrade to
  -- `none` on any failure so registry construction never fails on an odd signature.
  -- `private` declarations skip `Signature.forName` (it embeds the leading declaration
  -- name, which would surface the internal `_private.…` mangling) and instead fall
  -- back to a purely syntactic highlight of the pretty-printed type; consumers degrade
  -- further to an escaped `<pre>` of `signatureText` when that parse fails too.
  let signatureHtml? ←
    if isPrivateName name then
      highlightProofSourceHtml? signatureText
    else
      try
        pure (some ((← Verso.Genre.Manual.Signature.forName name).wide |> renderHighlightedSelfContainedHtml))
      catch _ =>
        pure none
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
    status := provedStatusTag (Informal.Data.ConstantInfo.blueprintProvedStatus cinfo (allowOpaque := true))
    authored := !nodeLabels.isEmpty
    shortName := Informal.NodeCard.shortDeclName namePrefix displayName
    isPrivate := isPrivateName name
    docstringHtml?
    declHref?
    sourceHref?
    depth?
    height?
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
  for i in [0:decls.size] do
    let (n, ci, modName) := decls[i]!
    let (typeDeps, valueDeps) := fwd[i]!
    let ranges? ← findDeclarationRanges? n
    let sourcePath? ← sourcePathForModule? workspaceRoot modName
    let entry ← (buildEntry workspaceRoot namePrefix leanNameLabels (usedBy.getD n #[])
      n ci modName sourcePath? ranges? typeDeps valueDeps
      depths[i]! heights[i]!).run'
    entries := entries.push entry
    -- Proof/value body, from the per-module cached file content (degrades to no
    -- body on any read/slice failure — the decl page shows its quiet placeholder).
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
    let bodyText? : Option String :=
      match content?, ranges? with
      | some content, some ranges =>
        (Informal.proofSourceFromContent? content ranges.range).filter (·.length ≤ rawBodyCap)
      | _, _ => none
    match bodyText? with
    | some src =>
      let bodyHtml? ←
        if src.length ≤ highlightBodyCap then highlightProofSourceHtml? src else pure none
      bodies := bodies.push { name := entry.name, html? := bodyHtml?, text? := some src }
    | none => pure ()
  return (
    { schemaVersion := 2, namePrefix, declCount := entries.size, decls := entries },
    { bodies })

end Informal.DeclRegistry
