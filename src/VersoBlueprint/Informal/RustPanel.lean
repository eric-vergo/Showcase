/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Emilio J. Gallego Arias, Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint.Informal.Block.Common
import VersoBlueprint.Rust

namespace Informal.Rust

open Verso.Output.Html

def codePanelHeader (data : BlockData) (numberText : String) : CodePanelHeader :=
  Informal.codePanelHeaderFor "Rust" data numberText

def fallbackCodePanelHeader : CodePanelHeader :=
  Informal.fallbackCodePanelHeaderFor "Rust"

def renderRawCodePanel
    (header : CodePanelHeader) (summaryTitle raw : String)
    (attrs : Array (String × String) := #[]) (folded : Bool := false) :
    Verso.Output.Html :=
  mkCodePanel header summaryTitle (highlightHtml raw) attrs (folded := folded)

end Informal.Rust
