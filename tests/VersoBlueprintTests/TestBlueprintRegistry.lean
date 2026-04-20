/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintImportedDuplicates.Direct
import VersoBlueprintTests.BlueprintImportedDuplicates.Transitive
import VersoBlueprintTests.BlueprintLinkHover
import VersoBlueprintTests.BlueprintMetadataPanel
import VersoBlueprintTests.BlueprintPreviewSource.Provider
import VersoBlueprintTests.BlueprintPreviewWiring.Shared
import VersoBlueprintTests.BlueprintPreviewWiring.StateShowcase
import VersoBlueprintTests.BlueprintRustCode
import VersoBlueprintTests.BlueprintSummaryLinks.Shared
import VersoBlueprintTests.BlueprintTexMacros

namespace Verso.VersoBlueprintTests.TestBlueprintRegistry

open Verso
open Verso.Genre.Manual
open Lean

structure CuratedTestBlueprint where
  slug : String
  title : String
  category : String
  summary : String
  tags : Array String := #[]
  doc : Doc.VersoDoc Genre.Manual

def manualImpls : ExtensionImpls := extension_impls%

def curatedTestBlueprints : Array CuratedTestBlueprint := #[
  {
    slug := "hover-link"
    title := "Hover Link Doc"
    category := "Preview"
    summary := "Inline reference and bibliography hover coverage."
    tags := #["hover", "inline", "citation"]
    doc := Verso.VersoBlueprintTests.BlueprintLinkHover.hoverLinkDoc
  },
  {
    slug := "hover-uses-dedup"
    title := "Hover Uses Dedup Doc"
    category := "Preview"
    summary := "Repeated uses-links against the same target without duplicate templates."
    tags := #["hover", "inline", "uses"]
    doc := Verso.VersoBlueprintTests.BlueprintLinkHover.hoverUsesDedupDoc
  },
  {
    slug := "hover-cite-only"
    title := "Hover Cite Only Doc"
    category := "Preview"
    summary := "Bibliography-only inline hover coverage."
    tags := #["hover", "inline", "citation"]
    doc := Verso.VersoBlueprintTests.BlueprintLinkHover.hoverCiteOnlyDoc
  },
  {
    slug := "widget-preview"
    title := "Blueprint Widget Preview"
    category := "Preview"
    summary := "Widget-side TeX prelude and preview rendering checks."
    tags := #["preview", "widget", "tex"]
    doc := Verso.VersoBlueprintTests.BlueprintTexMacros.widgetPreviewDoc
  },
  {
    slug := "rust-inline-preview"
    title := "Rust Attachment Showcase"
    category := "Code"
    summary := "Inline Rust attachment rendering with simple syntax coloring."
    tags := #["rust", "inline", "code"]
    doc := Verso.VersoBlueprintTests.BlueprintRustCode.rustCatalogDoc
  },
  {
    slug := "metadata-panel"
    title := "Blueprint Metadata Panel"
    category := "Metadata"
    summary := "Owner, tags, effort, priority, and PR metadata rendering."
    tags := #["metadata", "summary"]
    doc := Verso.VersoBlueprintTests.BlueprintMetadataPanel.metadataPanelDoc
  },
  {
    slug := "direct-imported-duplicates"
    title := "Direct Imported Duplicates"
    category := "Imports"
    summary := "Duplicate imported node, group, and author diagnostics."
    tags := #["imports", "providers", "diagnostics"]
    doc := Verso.VersoBlueprintTests.BlueprintImportedDuplicates.Direct.directImportedDuplicateDoc
  },
  {
    slug := "transitive-imported-duplicates"
    title := "Transitive Imported Duplicates"
    category := "Imports"
    summary := "Duplicate imported diagnostics through a reexport chain."
    tags := #["imports", "providers", "diagnostics"]
    doc := Verso.VersoBlueprintTests.BlueprintImportedDuplicates.Transitive.transitiveImportedDuplicateDoc
  },
  {
    slug := "imported-preview-source"
    title := "Imported Preview Source"
    category := "Imports"
    summary := "Imported preview bodies and cross-module preview source coverage."
    tags := #["imports", "preview", "providers"]
    doc := Verso.VersoBlueprintTests.BlueprintPreviewSource.Provider.importedPreviewSourceDoc
  },
  {
    slug := "state-showcase"
    title := "Blueprint Graph State Showcase"
    category := "Graph"
    summary := "Complete graph-state matrix with graph and summary pages."
    tags := #["graph", "summary", "state"]
    doc := Verso.VersoBlueprintTests.BlueprintPreviewWiring.StateShowcase.stateShowcaseDoc
  },
  {
    slug := "external-summary-links"
    title := "External Summary Links"
    category := "Summary"
    summary := "Summary links for external Lean declarations."
    tags := #["summary", "external", "lean"]
    doc := Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared.externalSummaryLinksDoc
  },
  {
    slug := "summary-blockers"
    title := "Summary Blockers"
    category := "Summary"
    summary := "Missing declarations and incomplete Lean declarations in summary views."
    tags := #["summary", "lean", "blockers"]
    doc := Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared.summaryBlockersDoc
  },
  {
    slug := "summary-triage"
    title := "Summary Triage"
    category := "Summary"
    summary := "Summary rollups by owner, tags, parent, and triage metadata."
    tags := #["summary", "metadata", "triage"]
    doc := Verso.VersoBlueprintTests.BlueprintSummaryLinks.Shared.summaryTriageDoc
  },
  {
    slug := "preview-wiring"
    title := "Blueprint Preview Wiring"
    category := "Runtime"
    summary := "Core graph and summary preview runtime wiring."
    tags := #["preview", "runtime", "graph", "summary"]
    doc := Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.previewWiringDoc
  },
  {
    slug := "used-by-preview"
    title := "Blueprint Used-By Preview Wiring"
    category := "Relationships"
    summary := "Used-by chips and preview panel behavior."
    tags := #["relationships", "used-by", "preview"]
    doc := Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.usedByPreviewDoc
  },
  {
    slug := "used-by-single-preview"
    title := "Blueprint Used-By Single Preview Wiring"
    category := "Relationships"
    summary := "Single reverse-dependency used-by rendering."
    tags := #["relationships", "used-by"]
    doc := Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.usedBySinglePreviewDoc
  },
  {
    slug := "lean-status-chip"
    title := "Blueprint Lean Status Chip Wiring"
    category := "Summary"
    summary := "Lean status chip rendering for proved, sorry, axiom, and absent code."
    tags := #["summary", "status", "lean"]
    doc := Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.leanStatusChipDoc
  },
  {
    slug := "lean-code-link-preview"
    title := "Blueprint Lean Code Link Preview Wiring"
    category := "Preview"
    summary := "Inline Lean declaration preview links inside the summary."
    tags := #["preview", "inline", "lean"]
    doc := Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.leanCodeLinkPreviewDoc
  },
  {
    slug := "group-preview"
    title := "Blueprint Group Preview Wiring"
    category := "Relationships"
    summary := "Declared group chips and group preview panel interactions."
    tags := #["relationships", "group", "preview"]
    doc := Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.groupPreviewDoc
  },
  {
    slug := "missing-group-preview"
    title := "Blueprint Missing Group Preview Wiring"
    category := "Relationships"
    summary := "Fallback behavior for undeclared groups."
    tags := #["relationships", "group", "fallback"]
    doc := Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.missingGroupPreviewDoc
  },
  {
    slug := "single-declared-group"
    title := "Blueprint Single Declared Group Wiring"
    category := "Relationships"
    summary := "Declared group with only one member."
    tags := #["relationships", "group"]
    doc := Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared.singleDeclaredGroupDoc
  }
]

def findCuratedTestBlueprint? (slug : String) : Option CuratedTestBlueprint :=
  curatedTestBlueprints.find? (·.slug == slug)

structure CuratedTestBlueprintMeta where
  slug : String
  title : String
  category : String
  summary : String
  tags : Array String
  kind : String
deriving ToJson

def CuratedTestBlueprint.meta (doc : CuratedTestBlueprint) : CuratedTestBlueprintMeta :=
  {
    slug := doc.slug
    title := doc.title
    category := doc.category
    summary := doc.summary
    tags := doc.tags
    kind := "curated_doc"
  }

end Verso.VersoBlueprintTests.TestBlueprintRegistry
