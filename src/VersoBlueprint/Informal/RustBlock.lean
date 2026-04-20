/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Environment
import VersoBlueprint.Informal.Code
import VersoBlueprint.Profiling
import VersoBlueprint.Rust

open Verso Doc Elab
open Verso.Genre Manual
open Lean Lean.Elab

namespace Informal

private def rustImpl : CodeBlockExpanderOf Informal.CodeConfig
  | cfg, contents => do
    Environment.registerRustCode cfg.label { raw := contents.getString }
    ``(Block.concat #[])

@[code_block]
def rust : CodeBlockExpanderOf Informal.CodeConfig
  | cfg, contents => do
    Profile.withDocElab "code_block" "rust" <| rustImpl cfg contents

end Informal
