/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Profiling
import VersoBlueprint.Source.Metadata
import VersoBlueprint.TraversalIndex

open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse
open Lean Elab

namespace Informal.Source

structure DocumentConfig where
  id : String
  idSyntax : Syntax := Syntax.missing
deriving Inhabited

section
variable [Monad m] [MonadError m]

def DocumentConfig.parse : ArgParse m DocumentConfig :=
  (fun (idArg : Verso.ArgParse.WithSyntax String) =>
    {
      id := idArg.val
      idSyntax := idArg.syntax
    }) <$> .positional `id (.withSyntax .string)

instance : FromArgs DocumentConfig m where
  fromArgs := DocumentConfig.parse

end

block_extension Block.sourceDocument (document : Document) where
  data := toJson document
  traverse _id data _contents := do
    let some document ← Informal.ExtensionDecode.decode? (α := Document) data
        (fun err => s!"Malformed source document data ({err}): {data}")
      | return none
    match Informal.TraversalIndex.SourceDocuments.data? (← get) document.id with
    | some existing =>
        unless existing == document do
          Verso.reportError s!"Source document '{document.id}' was declared more than once with conflicting metadata"
    | none =>
        modify fun st => Informal.TraversalIndex.SourceDocuments.saveData st document.id document
    return none
  toTeX := some <| fun _ _ _ _ _ => pure .empty
  toHtml :=
    open Verso.Doc.Html in
    some <| fun _ _ _ _ _ => pure .empty

private def sourceDocumentMetadataTerm
    (cfg : DocumentConfig) (contents : Array (TSyntax `block)) :
    DocElabM (Option (TSyntax `term)) := do
  let leading ← Metadata.splitLeadingMetadata contents
  match leading.term? with
  | none =>
      logErrorAt cfg.idSyntax m!"Source document '{cfg.id}' requires one leading metadata block"
      pure none
  | some term =>
      if !leading.body.isEmpty then
        logErrorAt cfg.idSyntax m!"Source document '{cfg.id}' must contain exactly one metadata block and no visible body"
      pure (some term)

private def sourceDocumentExpanderImpl : DirectiveExpanderOf DocumentConfig
  | cfg, contents => do
    let some metadataTerm ← sourceDocumentMetadataTerm cfg contents
      | ``(Block.concat #[])
    let metadata ← Metadata.evalDocumentMetadata metadataTerm
    let document := metadata.toDocument cfg.id
    let validationErrors := Document.validationErrors document
    for error in validationErrors do
      logErrorAt cfg.idSyntax m!"Source document '{cfg.id}' is invalid: {toString error}"
    ``(Block.other (Block.sourceDocument $(quote document)) #[])

def sourceDocumentDirective : DirectiveExpanderOf DocumentConfig
  | cfg, contents => do
    Profile.withDocElab "directive" "source_document" <|
      sourceDocumentExpanderImpl cfg contents

end Informal.Source

namespace Informal

@[directive]
def source_document : DirectiveExpanderOf Source.DocumentConfig :=
  Source.sourceDocumentDirective

end Informal
