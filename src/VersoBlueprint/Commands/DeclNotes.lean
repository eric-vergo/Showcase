/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Profiling
import VersoBlueprint.TraversalIndex

/-!
`:::declNotes "Some.Decl.Name"` — authored *sidecar prose* for a declaration
**without** making it a blueprint graph node.

The body is arbitrary Verso doc blocks (prose, math, code — the same pipeline as
node informal content). The block renders **nothing** where it is written
(traverse-only): its traversed contents are stashed in the `DeclNotes` traversal
store keyed by the *full* declaration name, and the declaration-page emitter
(`DeclPage`) picks them up and renders them as the informal-statement cell — in
preference to the declaration's docstring. Duplicate keys are last-writer-wins
with a build-log warning.

Consumers place these blocks in dedicated site modules; because the block emits
no visible HTML, the parts they live in render as near-empty pages (acceptable —
the prose surfaces only on the declaration pages).
-/

namespace Informal.Commands

open Lean Elab
open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse
open Lean.Doc.Syntax

/--
Block payload for `Block.declNotes`: the fully-qualified declaration name whose
authored sidecar prose this block carries. The prose blocks themselves travel as
the block's child contents (not in this payload); the block renders nothing
inline and the decl-page emitter picks up the stored contents by this name.
-/
structure DeclNotesData where
  declName : String
deriving Inhabited, FromJson, ToJson, Quote

/--
Stored `:::declNotes` payload: the full declaration name plus its traversed
sidecar-prose blocks. Decoded by the decl-page emitter and rendered (through the
standard Manual/VBP renderer, so LaTeX and inline code work) as the informal
statement cell, preferred over the docstring. Mirrors `PreviewCache.Entry`'s
"stash traversed Manual blocks, render later" shape.
-/
structure StoredDeclNotes where
  declName : String
  blocks : Array (Verso.Doc.Block Verso.Genre.Manual) := #[]
deriving Inhabited, FromJson, ToJson

open Verso Doc Elab Genre Manual in
block_extension Block.declNotes (data : DeclNotesData) where
  data := toJson data
  traverse id data contents := do
    match ← Informal.ExtensionDecode.decode? (α := DeclNotesData) data
        (fun err => s!"Malformed data in Block.declNotes.traverse ({err})") with
    | Option.none => return Option.none
    | Option.some data =>
      let declName := data.declName
      -- Last-writer-wins with a build-log warning when a *different* block
      -- already claimed this decl name. Re-traversal of the same block (same
      -- id, later passes) neither warns nor re-registers the id.
      let existing? := Informal.TraversalIndex.DeclNotes.object? (← get) declName
      let existingIds := (existing?.map (·.ids.toArray)).getD #[]
      if !existingIds.isEmpty && !existingIds.contains id then
        Verso.reportWarning
          s!"Duplicate ':::declNotes \"{declName}\"' block; the later one's prose \
             replaces the earlier one on the declaration page."
      modify fun st =>
        let st := Informal.TraversalIndex.DeclNotes.saveData st declName
          (toJson (StoredDeclNotes.mk declName contents))
        if existingIds.contains id then st
        else Informal.TraversalIndex.DeclNotes.saveId st declName id
      return Option.none
  toTeX := none
  -- Renders nothing inline: the authored prose surfaces only on the declaration
  -- page (as the informal-statement cell). The contents are still traversed
  -- (children of this block) so their math/assets register globally.
  toHtml := some fun _goI _goB _id _data _blocks => pure .empty

end Informal.Commands

/-! ### The `:::declNotes` directive

Lives in `namespace Informal` (not `Informal.Commands`) so it is resolvable by
`:::declNotes` under the consumer's `open Informal`, matching the other blueprint
directives (`:::definition`, `:::author`, `:::proof`, …). The directive name is
its declaration name, resolved against open namespaces. -/

namespace Informal

open Lean Elab
open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse

/-- Parsed configuration for the `:::declNotes` directive: the positional
declaration-name string plus its syntax (for diagnostics). -/
structure DeclNotesConfig where
  declName : String
  declNameSyntax : Syntax := Syntax.missing

section
variable [Monad m] [MonadError m]

def DeclNotesConfig.parse : ArgParse m DeclNotesConfig :=
  (fun (nameArg : Verso.ArgParse.WithSyntax String) =>
    { declName := nameArg.val.trimAscii.toString, declNameSyntax := nameArg.syntax })
    <$> .positional `name (.withSyntax .string)

instance : FromArgs DeclNotesConfig m where
  fromArgs := DeclNotesConfig.parse

end

private def declNotesExpanderImpl : DirectiveExpanderOf DeclNotesConfig
  | cfg, contents => do
    if cfg.declName.isEmpty then
      logErrorAt cfg.declNameSyntax
        m!"':::declNotes' needs a non-empty fully-qualified declaration name"
    let contents ← contents.mapM elabBlock
    let data : Informal.Commands.DeclNotesData := { declName := cfg.declName }
    ``(Verso.Doc.Block.other (Informal.Commands.Block.declNotes $(quote data)) #[$contents,*])

@[directive] def «declNotes» : DirectiveExpanderOf DeclNotesConfig
  | cfg, contents => do
    Profile.withDocElab "directive" "declNotes" <|
      declNotesExpanderImpl cfg contents

end Informal
