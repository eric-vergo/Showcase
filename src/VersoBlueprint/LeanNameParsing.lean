/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.StringParsing

namespace Informal.LeanNameParsing

open Lean

/-- Trim leading/trailing ASCII whitespace from a Lean name fragment. -/
private def normalize (s : String) : String :=
  StringParsing.trimAscii s

/-- Parse a Lean declaration name using Lean's standard `String.toName` parser. -/
private def parse? (s : String) : Option Name :=
  let s := normalize s
  if s.isEmpty then
    none
  else
    let n := s.toName
    if n.isAnonymous then none else some n

/-- Like `parse?`, but returns an error string preserving prior caller behavior. -/
def parseE (s : String) : Except String Name :=
  let normalized := normalize s
  if normalized.isEmpty then
    .error "empty name"
  else
    match parse? normalized with
    | some n => .ok n
    | none => .error s!"invalid Lean name '{normalized}'"

/--
Temporary workaround for directive args:
`(lean := "...")` currently receives a single string, so we split on commas.
TODO: remove this when Verso supports list-valued directive arguments.
-/
def splitCommaSeparatedList (s : String) : Array String :=
  StringParsing.splitCommaSeparatedList s

end Informal.LeanNameParsing
