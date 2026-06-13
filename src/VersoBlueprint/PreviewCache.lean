/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoManual
import VersoBlueprint.Data

namespace Informal.PreviewCache

open Lean

inductive Facet where
  | statement
  | proof
deriving Inhabited, Repr, BEq, ToJson, FromJson

def Facet.suffix : Facet → String
  | .statement => "statement"
  | .proof => "proof"

def Facet.ofInProgressKind : Informal.Data.InProgressKind → Facet
  | .statement _ => .statement
  | .proof => .proof

def key (label : Name) (facet : Facet) : String :=
  s!"{label}--{facet.suffix}"

/--
Preview payload stored during traversal.
`blocks` are already in the Manual genre and can be rendered by later HTML consumers.

This is a traversal-phase cache, not the canonical semantic node record. The
interactive widget path still reads syntax from `Environment.InProgress`
because it needs elaboration-time data before Manual preview blocks are
available.
-/
structure Entry where
  label : Name
  facet : Facet
  blocks : Array (Verso.Doc.Block Verso.Genre.Manual) := #[]
  /-- HTML-cache keys for associated Lean declaration previews. -/
  leanCodePreviewKeys : Array String := #[]
deriving Inhabited, Repr, ToJson, FromJson

def Entry.ofBlocks (label : Name) (facet : Facet)
    (blocks : Array (Verso.Doc.Block Verso.Genre.Manual))
    (leanCodePreviewKeys : Array String := #[]) : Entry :=
  { label, facet, blocks, leanCodePreviewKeys }

end Informal.PreviewCache
