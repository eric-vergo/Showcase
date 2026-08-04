/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Emilio J. Gallego Arias, Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Verso.Output.Html

namespace VersoBlueprint.Html

open Verso.Output

/--
Escape plain text for insertion into HTML text content.

This intentionally returns raw escaped text because the current Verso
`Html.text true` renderer escapes `<` and `>` but not `&`. Use this helper only
for text content that must preserve literal ampersands faithfully.
-/
def escapeText (text : String) : String :=
  ((text.replace "&" "&amp;").replace "<" "&lt;").replace ">" "&gt;"

/-- Plain HTML text content escaped with `escapeText`. -/
def text (text : String) : Html :=
  Verso.Output.Html.text false <| escapeText text

end VersoBlueprint.Html
