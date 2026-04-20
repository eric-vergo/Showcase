/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Data

namespace Informal.Rust

open Lean

structure InlineCodeData where
  raw : String
deriving Repr, Inhabited, DecidableEq, ToJson, FromJson

open Syntax in
instance : Quote InlineCodeData where
  quote data := mkCApp ``InlineCodeData.mk #[quote data.raw]

end Informal.Rust
