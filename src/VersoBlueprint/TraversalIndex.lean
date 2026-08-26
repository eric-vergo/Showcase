/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Emilio J. Gallego Arias, Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean
import VersoManual
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.GroupData
import VersoBlueprint.Informal.LeanDeclPreviewKey
import VersoBlueprint.Graph
import VersoBlueprint.PreviewCache
import VersoBlueprint.Resolve
import VersoBlueprint.Rust
import VersoBlueprint.Commands.Summary.Data

/-!
Typed accessors for Blueprint's traversal-time stores.

Verso traversal domains are flexible, but raw domain names and JSON payloads are
easy to misuse. This module is the small typed facade used by renderers and
traversal hooks. Each namespace names one store and exposes only the operations
callers should need.
-/

namespace Informal.TraversalIndex

open Lean
open Verso
open Verso.Genre Manual

/--
Classification for traversal-time Blueprint stores.

This is intentionally architectural metadata rather than behavior: the current
storage backend still uses Verso traversal domains in several places, but these
roles clarify whether the stored data is meant to be semantic document state,
a render-time index, a cache, or an accumulator.
-/
inductive StoreKind where
  | semanticDomain
  | internalIndex
  | runtimeCache
  | accumulator
deriving Inhabited, Repr, BEq

structure StoreSpec where
  /-- Concrete Verso traversal-domain name used as the current backend key. -/
  name : Name
  /-- Architectural role of this store. -/
  kind : StoreKind
  /-- Functional key shape, written as documentation rather than encoded behavior. -/
  key : String
  /-- Functional value shape, including whether the value is object data or only anchor IDs. -/
  value : String
  /-- One-line purpose for human readers. -/
  summary : String
deriving Repr

/-- Failed traversal-domain object decode with caller-facing diagnostic context. -/
structure DecodeError where
  canonicalName : String
  message : String
deriving Inhabited, Repr

/-- Decoded traversal-domain object paired with its canonical storage key. -/
structure StoredEntry (α : Type) where
  canonicalName : String
  data : α
deriving Inhabited, Repr

/-- Decode one Verso traversal-domain object while preserving its canonical key for diagnostics. -/
def decodeObjectData [FromJson α] (obj : Verso.Multi.Object) :
    Except DecodeError (StoredEntry α) :=
  match fromJson? (α := α) obj.data with
  | .error err =>
      .error { canonicalName := obj.canonicalName, message := err }
  | .ok data =>
      .ok { canonicalName := obj.canonicalName, data }

/-- Decode every object in a traversal domain without discarding malformed entries. -/
def decodeDomainEntries [FromJson α] (domain : Verso.Multi.Domain) :
    Array (Except DecodeError (StoredEntry α)) :=
  domain.objects.toArray.map fun (_key, obj) => decodeObjectData obj

/-- Decode every object in a named traversal store, returning an empty array when absent. -/
def decodeStoreEntries [FromJson α] (state : TraverseState) (domainName : Name) :
    Array (Except DecodeError (StoredEntry α)) :=
  match state.domains.get? domainName with
  | none => #[]
  | some domain => decodeDomainEntries domain

private def objectData? [FromJson α]
    (state : TraverseState) (domain : Name) (canonicalName : String) : Option α := do
  let obj ← state.getDomainObject? domain canonicalName
  (fromJson? (α := α) obj.data).toOption

private def saveObjectData
    (state : TraverseState) (domain : Name) (canonicalName : String) (data : Json) : TraverseState :=
  state.saveDomainObjectData domain canonicalName data

private def saveObjectId
    (state : TraverseState) (domain : Name) (canonicalName : String)
    (id : Verso.Multi.InternalId) : TraverseState :=
  state.saveDomainObject domain canonicalName id

private def modifyObjectData
    (state : TraverseState) (domain : Name) (canonicalName : String)
    (f : Json → Json) : TraverseState :=
  state.modifyDomainObjectData domain canonicalName f

namespace Nodes

def spec : StoreSpec := {
  name := Resolve.informalDomainName
  kind := .semanticDomain
  key := "informal label"
  value := "StoredBlockData plus node anchor ids"
  summary := "Canonical traversal index for Blueprint node anchors and lightweight node metadata."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : Name) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label.toString

def storedData? (state : TraverseState) (label : Name) : Option Informal.StoredBlockData :=
  objectData? state domainName label.toString

def data? (state : TraverseState) (label : Name) : Option Informal.BlockData :=
  (storedData? state label).map (·.toBlockData)

def href? (state : TraverseState) (label : Name) : Option String :=
  Resolve.resolveDomainHref? state domainName label.toString

def saveId (state : TraverseState) (label : Name) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label.toString id

def saveData (state : TraverseState) (label : Name) (data : Json) : TraverseState :=
  saveObjectData state domainName label.toString data

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

/-- Decode every informal-node store entry, preserving per-entry decode errors. -/
def entries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry Informal.StoredBlockData)) :=
  decodeStoreEntries state domainName

end Nodes

namespace InlineCode

def spec : StoreSpec := {
  name := Resolve.informalCodeDomainName
  kind := .internalIndex
  key := "informal label"
  value := "InlineCodeData plus code-panel anchor ids and folding settings"
  summary := "Traversal-local index for Blueprint code-panel sources keyed by informal label."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : Name) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label.toString

def data? (state : TraverseState) (label : Name) : Option Informal.InlineCodeData :=
  objectData? state domainName label.toString

def href? (state : TraverseState) (label : Name) : Option String :=
  Resolve.resolveDomainHref? state domainName label.toString

def saveId (state : TraverseState) (label : Name) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label.toString id

def saveData (state : TraverseState) (label : Name) (data : Json) : TraverseState :=
  saveObjectData state domainName label.toString data

end InlineCode

namespace RustInlineCode

def spec : StoreSpec := {
  name := Informal.Rust.informalRustCodeDomain
  kind := .internalIndex
  key := "informal label"
  value := "Rust.InlineCodeData plus code-panel anchor ids and folding settings"
  summary := "Traversal-local index for Blueprint Rust code-panel sources keyed by informal label."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : Name) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label.toString

def data? (state : TraverseState) (label : Name) : Option Informal.Rust.InlineCodeData :=
  objectData? state domainName label.toString

def href? (state : TraverseState) (label : Name) : Option String :=
  Resolve.resolveDomainHref? state domainName label.toString

def saveId (state : TraverseState) (label : Name) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label.toString id

def saveData (state : TraverseState) (label : Name) (data : Informal.Rust.InlineCodeData) :
    TraverseState :=
  saveObjectData state domainName label.toString (toJson data)

end RustInlineCode

namespace ExternalMarkup

def spec : StoreSpec := {
  name := Resolve.externalMarkupDomainName
  kind := .semanticDomain
  key := "informal label"
  value := "ExternalMarkupData plus markup block anchor ids"
  summary := "Semantic index for raw external markup attachments keyed by informal label."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : Name) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label.toString

def data? (state : TraverseState) (label : Name) : Option Informal.Data.ExternalMarkupData :=
  objectData? state domainName label.toString

def saveId (state : TraverseState) (label : Name) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label.toString id

def saveData (state : TraverseState) (label : Name) (data : Json) : TraverseState :=
  saveObjectData state domainName label.toString data

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

/-- Decode every external-markup store entry, preserving per-entry decode errors. -/
def entries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry Informal.Data.ExternalMarkupData)) :=
  decodeStoreEntries state domainName

end ExternalMarkup

namespace Groups

def spec : StoreSpec := {
  name := Resolve.informalGroupDomainName
  kind := .semanticDomain
  key := "group label"
  value := "GroupBlockData declaration metadata"
  summary := "Semantic declaration index for Blueprint parent/group labels."
}

def domainName : Name := spec.name

def data? (state : TraverseState) (label : Name) : Option Informal.GroupBlockData :=
  objectData? state domainName label.toString

def saveData (state : TraverseState) (label : Name) (data : Json) : TraverseState :=
  saveObjectData state domainName label.toString data

end Groups

namespace Graphs

def spec : StoreSpec := {
  name := Resolve.graphDomainName
  kind := .runtimeCache
  key := "graph block key"
  value := "semantic GraphData plus graph block anchor ids"
  summary := "Traversal-cached Blueprint graph data finalized by GraphApi for manifest and browser consumers."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (key : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName key

def data? (state : TraverseState) (key : String) : Option Informal.Graph.GraphData :=
  objectData? state domainName key

def saveId
    (state : TraverseState) (key : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName key id

def saveData (state : TraverseState) (key : String) (data : Informal.Graph.GraphData) :
    TraverseState :=
  saveObjectData state domainName key (toJson data)

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

/-- Decode every cached graph entry, preserving per-entry decode errors. -/
def entries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry Informal.Graph.GraphData)) :=
  decodeStoreEntries state domainName

def allData (state : TraverseState) : Array Informal.Graph.GraphData :=
  entries state |>.filterMap (·.toOption.map (·.data)) |>.qsort (fun a b => a.key < b.key)

end Graphs

namespace TraversalPreviews

def spec : StoreSpec := {
  name := Resolve.informalPreviewDomainName
  kind := .runtimeCache
  key := "(informal label, preview facet)"
  value := "PreviewCache.Entry plus preview anchor ids"
  summary := "Traversal-cached statement/proof preview payloads keyed by `(label, facet)`."
}

def domainName : Name := spec.name

def key (label : Name) (facet : PreviewCache.Facet) : String :=
  PreviewCache.key label facet

def object? (state : TraverseState) (previewKey : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName previewKey

def entry? (state : TraverseState) (previewKey : String) : Option PreviewCache.Entry :=
  objectData? state domainName previewKey

def href? (state : TraverseState) (previewKey : String) : Option String :=
  Resolve.resolveDomainHref? state domainName previewKey

def hrefFor? (state : TraverseState) (label : Name) (facet : PreviewCache.Facet) :
    Option String :=
  href? state (key label facet)

def saveId
    (state : TraverseState) (previewKey : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName previewKey id

def saveData (state : TraverseState) (previewKey : String) (data : Json) : TraverseState :=
  saveObjectData state domainName previewKey data

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

/-- Decode every statement/proof traversal-preview entry, preserving per-entry decode errors. -/
def entries (state : TraverseState) :
    Array (Except DecodeError (StoredEntry PreviewCache.Entry)) :=
  decodeStoreEntries state domainName

end TraversalPreviews

namespace LeanCodePreviews

def spec : StoreSpec := {
  name := Informal.LeanDeclPreviewKey.domainName
  kind := .runtimeCache
  key := "Lean declaration name"
  value := "LeanCodePreview.Entry plus declaration-preview anchor ids"
  summary := "Traversal-cached Lean declaration preview payloads keyed by declaration name."
}

def domainName : Name := spec.name

def lookupKey (decl : Name) : String :=
  Informal.LeanDeclPreviewKey.lookupKey decl

def object? (state : TraverseState) (previewKey : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName previewKey

def saveId
    (state : TraverseState) (previewKey : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName previewKey id

def saveData (state : TraverseState) (previewKey : String) (data : Json) : TraverseState :=
  saveObjectData state domainName previewKey data

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

end LeanCodePreviews

namespace ExternalDeclAnchors

def spec : StoreSpec := {
  name := Resolve.externalRenderedDeclDomainName
  kind := .internalIndex
  key := "(informal label, canonical external declaration)"
  value := "rendered declaration row anchor ids"
  summary := "Traversal-local anchor index for rendered external declaration rows."
}

def domainName : Name := spec.name

def key (label decl : Name) : String :=
  Resolve.externalRenderedDeclTargetKey label decl

def object? (state : TraverseState) (targetKey : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName targetKey

def href? (state : TraverseState) (label decl : Name) : Option String :=
  Resolve.resolveRenderedExternalDeclHref? state label decl

/-- HTML `id` attributes for a registered rendered external-declaration row. -/
def htmlIdAttrs (state : TraverseState) (label decl : Name) : Array (String × String) :=
  match object? state (key label decl) with
  | none => #[]
  | some obj =>
    match obj.ids.toArray[0]? with
    | some targetId => state.htmlId targetId
    | none => #[]

def saveId
    (state : TraverseState) (targetKey : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName targetKey id

end ExternalDeclAnchors

namespace CitationPreviews

def spec : StoreSpec := {
  name := Resolve.citationPreviewDomainName
  kind := .runtimeCache
  key := "(citation label, citation style, locator kind, locator index)"
  value := "citation preview payload"
  summary := "Manifest-backed bibliography hover previews keyed by citation target and locator."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (previewKey : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName previewKey

def saveData (state : TraverseState) (previewKey : String) (data : Json) : TraverseState :=
  saveObjectData state domainName previewKey data

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

end CitationPreviews

namespace Bibliography

def spec : StoreSpec := {
  name := Resolve.bibliographyDomainName
  kind := .semanticDomain
  key := "citation label"
  value := "bibliography entry anchor ids"
  summary := "Semantic index for bibliography entry anchors keyed by citation label."
}

def domainName : Name := spec.name

def href? (state : TraverseState) (label : String) : Option String :=
  Resolve.resolveDomainHref? state domainName label

def saveId (state : TraverseState) (label : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label id

end Bibliography

namespace FormalizationPage

/--
Singleton key under which the formalization-metadata page anchor is indexed.
`Block.formalization`'s traversal saves the block's anchor id here so other
surfaces (the dashboard trust strip) can cross-link the page without guessing
its slug.
-/
def pageKey : String := "formalization"

def spec : StoreSpec := {
  name := Resolve.formalizationDomainName
  kind := .semanticDomain
  key := "singleton formalization key"
  value := "formalization-metadata page anchor id"
  summary := "Anchor index for the standalone formalization-metadata page (trust-strip cross-link)."
}

def domainName : Name := spec.name

def href? (state : TraverseState) : Option String :=
  Resolve.resolveDomainHref? state domainName pageKey

def saveId (state : TraverseState) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName pageKey id

end FormalizationPage

namespace TrustModelPage

/--
Singleton key under which the trust-model page anchor is indexed.
`Block.trustModel`'s traversal saves the block's anchor id here (mirroring
`FormalizationPage`) so the dashboard trust strip, the comparator page, and the PM
hub can cross-link "Trust model" without guessing its slug — and omit the link
entirely when the document carries no such page.
-/
def pageKey : String := "trustModel"

def spec : StoreSpec := {
  name := Resolve.trustModelDomainName
  kind := .semanticDomain
  key := "singleton trust-model key"
  value := "trust-model page anchor id"
  summary := "Anchor index for the standalone \"Trust model\" page (trust-strip / comparator / PM-hub cross-links)."
}

def domainName : Name := spec.name

def href? (state : TraverseState) : Option String :=
  Resolve.resolveDomainHref? state domainName pageKey

def saveId (state : TraverseState) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName pageKey id

end TrustModelPage

namespace SummaryPage

/--
Singleton key under which the blueprint-summary page anchor is indexed.
`Block.summary`'s traversal saves the block's anchor id here (mirroring
`FormalizationPage`) so other surfaces (the PM hub links) can cross-link the
standalone Showcase Summary page without guessing its slug. When a document
carries several `blueprint_summary` blocks, more than one id lands under this key
and `href?` resolves to `none` (Verso only links a single-target ref), so the
cross-link is simply omitted rather than pointing at an arbitrary block.
-/
def pageKey : String := "summary"

def spec : StoreSpec := {
  name := Resolve.summaryPageDomainName
  kind := .semanticDomain
  key := "singleton summary-page key"
  value := "showcase-summary page anchor id"
  summary := "Anchor index for the standalone Showcase Summary page (PM-hub cross-link)."
}

def domainName : Name := spec.name

def href? (state : TraverseState) : Option String :=
  Resolve.resolveDomainHref? state domainName pageKey

def saveId (state : TraverseState) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName pageKey id

end SummaryPage

namespace CitationUsages

def spec : StoreSpec := {
  name := Resolve.citationUsageDomainName
  kind := .accumulator
  key := "citation label"
  value := "CitationUsageData plus citation use-site ids"
  summary := "Traversal-local backlink accumulator for bibliography usage details."
}

def domainName : Name := spec.name

def object? (state : TraverseState) (label : String) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName label

def saveId (state : TraverseState) (label : String) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName label id

def modifyData (state : TraverseState) (label : String) (f : Json → Json) : TraverseState :=
  modifyObjectData state domainName label f

def hrefs (state : TraverseState) (label : String) : Array String :=
  Resolve.resolveDomainHrefs state domainName label

end CitationUsages

namespace Summary

/--
Singleton key under which the document's decoded blueprint `Summary` payload is
cached for post-elaboration consumers (the dashboard block traverse saves it; the
extra-page emission step reads it back).
-/
def summaryKey : String := "summary"

def spec : StoreSpec := {
  name := Name.mkSimple "Informal.Block.summary"
  kind := .runtimeCache
  key := "singleton summary key"
  value := "decoded Summary dashboard/worklist payload"
  summary := "Traversal-cached blueprint Summary payload reused by the dashboard and PM page emission."
}

def domainName : Name := spec.name

def object? (state : TraverseState) : Option Verso.Multi.Object :=
  state.getDomainObject? domainName summaryKey

def saveId (state : TraverseState) (id : Verso.Multi.InternalId) : TraverseState :=
  saveObjectId state domainName summaryKey id

def saveData (state : TraverseState) (data : Informal.Commands.Summary) : TraverseState :=
  saveObjectData state domainName summaryKey (toJson data)

/-- The cached document-wide blueprint summary, if one was saved during traversal. -/
def cachedSummary? (state : TraverseState) : Option Informal.Commands.Summary :=
  objectData? state domainName summaryKey

def domain? (state : TraverseState) : Option Verso.Multi.Domain :=
  state.domains.get? domainName

end Summary

namespace DeclRegistry

def spec : StoreSpec := {
  name := `VersoBlueprint.TraversalIndex.DeclRegistry
  kind := .accumulator
  key := "one of the fixed keys \"registry\" / \"bodies\" / \"inputs\" / \"namePrefix\""
  value := "compressed registry JSON, compressed internal proof/value-bodies JSON, or the configured decl-name prefix string"
  summary := "Carries the elaboration-time all-declarations registry (built by `blueprint_graph` when `includeAllDecls` is on) plus the internal proof/value bodies and the configured `verso.blueprint.declNamePrefix` to generation-time ExtraSteps: `emitBlueprintPreviewData` writes `-verso-data/decl-registry.json` (registry only — bodies never ship in the public JSON), `DeclPage` bakes the bodies into static decl pages, and the render surfaces read the prefix for short display names."
}

def domainName : Name := spec.name

/-- Stash the (already-compressed) registry JSON produced at elaboration time. -/
def saveRaw (state : TraverseState) (json : String) : TraverseState :=
  saveObjectData state domainName "registry" (Json.str json)

/-- Read back the compressed registry JSON, if a `blueprint_graph` block stored one. -/
def raw? (state : TraverseState) : Option String := do
  let obj ← state.getDomainObject? domainName "registry"
  obj.data.getStr?.toOption

/-- Stash the (already-compressed) internal proof/value-bodies JSON. Internal-only:
read back by the decl-page emitter; never written into the public data dir. -/
def saveBodies (state : TraverseState) (json : String) : TraverseState :=
  saveObjectData state domainName "bodies" (Json.str json)

/-- Read back the compressed internal proof/value-bodies JSON, if stored. -/
def bodiesRaw? (state : TraverseState) : Option String := do
  let obj ← state.getDomainObject? domainName "bodies"
  obj.data.getStr?.toOption

/-- Stash the non-Lean files the registry build read, as a compressed JSON array of
`Informal.TrustInputs.Input` records.

Internal-only, like the bodies: the freshness gate re-reads them before emission, and the
public `decl-registry.json` stays what it was. The registry's caveat scan is captured at
elaboration from a file Lake does not track, so without this a warm rebuild republishes the
previous scan under the previous table's version and digest (CX-062). -/
def saveInputs (state : TraverseState) (json : String) : TraverseState :=
  saveObjectData state domainName "inputs" (Json.str json)

/-- Read back the registry's recorded inputs, if a `blueprint_graph` block stored any. -/
def inputs? (state : TraverseState) : Option String := do
  let obj ← state.getDomainObject? domainName "inputs"
  obj.data.getStr?.toOption

/-- Stash the configured `verso.blueprint.declNamePrefix` (captured at elaboration
time, where `Lean.Options` exist) for the generation/render-time short-name paths. -/
def savePrefix (state : TraverseState) (pfx : String) : TraverseState :=
  saveObjectData state domainName "namePrefix" (Json.str pfx)

/-- The configured decl-name prefix, if a `blueprint_graph` block stored one. -/
def namePrefix? (state : TraverseState) : Option String := do
  let obj ← state.getDomainObject? domainName "namePrefix"
  obj.data.getStr?.toOption

/-- Stash the configured `verso.blueprint.nodePage.localGraphRadius` (captured at
elaboration) for the generation-time node/decl-page graph emitters. -/
def saveLocalGraphRadius (state : TraverseState) (radius : Nat) : TraverseState :=
  saveObjectData state domainName "localGraphRadius" (toJson radius)

/-- The configured local-graph radius, if a `blueprint_graph` block stored one
(`0` ⇒ unlimited / full closure). -/
def localGraphRadius? (state : TraverseState) : Option Nat := do
  let obj ← state.getDomainObject? domainName "localGraphRadius"
  obj.data.getNat?.toOption

end DeclRegistry

namespace TrustData

def spec : StoreSpec := {
  name := `VersoBlueprint.TraversalIndex.TrustData
  kind := .runtimeCache
  key := "singleton trust key"
  value := "raw trust-strip JSON payload (sorry count, axioms, review status, comparator verdict)"
  summary := "Carries the elaboration-time trust-strip data (`Commands.TrustData`, saved by `Block.trustStrip`'s traverse) — comparator verdict, `requireConnected`, and the build-time axiom-audit findings — to the generation-time consumers: `Informal.GraphGate` (run between traversal and emission) reads `requireConnected`, `emitBlueprintComparatorPage` reads the comparator verdict to emit the `comparator/` page, and the audit/trust-model pages report the audit summary. Absent when no `verso.blueprint.trust.*` option is configured."
}

def domainName : Name := spec.name

/-- Singleton key under which the document's trust-strip payload is cached. -/
def trustKey : String := "trust"

/-- Stash the trust-strip JSON payload (already `toJson`ed by the block). -/
def saveData (state : TraverseState) (data : Json) : TraverseState :=
  saveObjectData state domainName trustKey data

/-- Read back the cached trust-strip JSON, if a `blueprint_dashboard`/trust-strip
block saved one during traversal. -/
def raw? (state : TraverseState) : Option Json := do
  let obj ← state.getDomainObject? domainName trustKey
  some obj.data

end TrustData

/--
Code-side inventory of the traversal indexes owned by Blueprint.

This is documentation-oriented metadata: callers should still use the typed
namespaces above. The list exists so reviews of the design-rationale schema can
compare against one source location instead of rediscovering each domain name.
-/
def allSpecs : Array StoreSpec := #[
  Nodes.spec,
  InlineCode.spec,
  RustInlineCode.spec,
  ExternalMarkup.spec,
  Groups.spec,
  Graphs.spec,
  TraversalPreviews.spec,
  LeanCodePreviews.spec,
  ExternalDeclAnchors.spec,
  CitationPreviews.spec,
  Bibliography.spec,
  FormalizationPage.spec,
  TrustModelPage.spec,
  SummaryPage.spec,
  CitationUsages.spec,
  Summary.spec,
  DeclRegistry.spec,
  TrustData.spec
]

end Informal.TraversalIndex
