/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoSlides
import Verso.Doc.Elab
import VersoBlueprint.Graft.Node

namespace Informal.Slides

open Lean
open Verso Doc Elab

public abbrev BlueprintSlideNode := Informal.Graft.BlueprintNode
public abbrev BlueprintNodeConfig := Informal.Graft.BlueprintNodeConfig

namespace BlueprintSlideNode

def fromAttrs? (attrs : Array (String × String)) : Option BlueprintSlideNode :=
  Informal.Graft.BlueprintNode.fromAttrs? attrs

end BlueprintSlideNode

namespace BlueprintNodeConfig

def toSlideNode (cfg : BlueprintNodeConfig) : BlueprintSlideNode :=
  cfg.toNode

end BlueprintNodeConfig

public meta def blueprintNodeBlock (cfg : BlueprintNodeConfig) : DocElabM Term := do
  let node := cfg.toSlideNode
  let attrs := node.toAttrs
  let fallback := node.fallbackText
  ``(Verso.Doc.Block.other (VersoSlides.BlockExt.wrap $(quote attrs))
      #[Verso.Doc.Block.para #[Verso.Doc.Inline.text $(quote fallback)]])

end Informal.Slides
