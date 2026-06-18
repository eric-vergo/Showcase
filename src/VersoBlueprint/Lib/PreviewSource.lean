/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Data
import VersoBlueprint.Environment
import VersoBlueprint.PreviewCache
import VersoBlueprint.PreviewRender
import VersoBlueprint.Resolve
import VersoBlueprint.TraversalIndex

namespace Informal.PreviewSource

open Lean
open Informal Data Environment

/-!
`PreviewSource` is the shared read-side namespace for preview consumers.

Its job is to keep preview lookup details localized so callers do not decode
traversal caches or environment-side preview payloads directly.

The current split is intentionally phase-specific:

- traversal-time callers use the traversal helpers in this module when they
  need cached preview blocks or manifest lookup keys
- environment-time callers use the environment helpers when they need semantic
  preview content from `Informal.Environment.State`
- callers that need preview data for one label should still come here first,
  even though there is not yet one unified "best available preview" selector

Known exception:

- manifest construction still enumerates stored preview domains directly because
  it emits the shared browser manifest from all stored preview entries rather
  than asking for one label at a time
-/

abbrev ManualBlock := Verso.Doc.Block Verso.Genre.Manual

structure Preview where
  blocks : Array ManualBlock := #[]
  stxs : Array Syntax := #[]
deriving Inhabited, Repr

private def nonEmptyOrNone {α} (xs : Array α) : Option (Array α) :=
  if xs.isEmpty then none else some xs

private def firstNonEmptyEntry?
    (fetch : PreviewCache.Facet → Option PreviewCache.Entry) : Option PreviewCache.Entry :=
  match fetch .statement with
  | some entry =>
    if entry.blocks.isEmpty then
      match fetch .proof with
      | some proofEntry =>
        if proofEntry.blocks.isEmpty then none else some proofEntry
      | none => none
    else
      some entry
  | none =>
    match fetch .proof with
    | some entry =>
      if entry.blocks.isEmpty then none else some entry
    | none => none

def traversalEntryByKey?
    (s : Verso.Genre.Manual.TraverseState) (key : String) : Option PreviewCache.Entry :=
  Informal.TraversalIndex.TraversalPreviews.entry? s key

def traversalFacetEntry?
    (s : Verso.Genre.Manual.TraverseState)
    (label : Name)
    (facet : PreviewCache.Facet) : Option PreviewCache.Entry :=
  let key := Informal.TraversalIndex.TraversalPreviews.key label facet
  traversalEntryByKey? s key

def traversalEntry?
    (s : Verso.Genre.Manual.TraverseState) (label : Name) : Option PreviewCache.Entry := do
  firstNonEmptyEntry? (traversalFacetEntry? s label)

def traversalLookupKey?
    (s : Verso.Genre.Manual.TraverseState) (label : Name) : Option String := do
  let entry ← traversalEntry? s label
  pure <| PreviewCache.key entry.label entry.facet

def traversalPreview?
    (s : Verso.Genre.Manual.TraverseState) (label : Name) : Option Preview := do
  let entry ← traversalEntry? s label
  return { blocks := entry.blocks }

private def envFacetPreview? (node : Data.Node) (facet : PreviewCache.Facet) : Option Preview := do
  let informalData ←
    match facet with
    | .statement => node.statement
    | .proof => node.proof
  match nonEmptyOrNone informalData.previewBlocks with
  | some blocks => some { blocks }
  | none =>
    match nonEmptyOrNone informalData.elabStx with
    | some stxs => some { stxs }
    | none => none

private def firstNonEmptyPreview?
    (fetch : PreviewCache.Facet → Option Preview) : Option Preview :=
  match fetch .statement with
  | some preview =>
    if !(preview.blocks.isEmpty && preview.stxs.isEmpty) then
      some preview
    else
      fetch .proof
  | none => fetch .proof

def fromEnvironment? (env : Environment) (label : Name) : Option Preview := do
  let state := informalExt.getState env
  let node ← state.data.get? label
  firstNonEmptyPreview? (envFacetPreview? node)

def renderWidgetHtml (preview? : Option Preview) : Lean.Elab.Term.TermElabM Verso.Output.Html := do
  match preview? with
  | none => pure .empty
  | some preview =>
    if !preview.blocks.isEmpty then
      Informal.renderPreviewBlocksHtml preview.blocks
    else if !preview.stxs.isEmpty then
      Informal.renderStatementElabHtml preview.stxs
    else
      pure .empty

end Informal.PreviewSource
