/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso

namespace Informal

/--
Replace Verso's document-local hover-table references with inline hover payloads.

This is for cached fragments that may be embedded in a different generated
document. The normal page renderer should keep using `data-verso-hover` plus
its page-level `-verso-docs.json`.
-/
def inlineVersoHoverAttrs
    (html : Verso.Output.Html)
    (hoverDedup : Verso.Code.Hover.Dedup Verso.Output.Html) :
    Verso.Output.Html :=
  Id.run <|
    html.visitM (tag := fun name attrs contents => do
      let mut inlineHover? : Option Verso.Output.Html := none
      let mut attrs' : Array (String × String) := #[]
      for (attr, value) in attrs do
        if attr == "data-verso-hover" then
          inlineHover? := value.toNat? >>= hoverDedup.get?
        else
          attrs' := attrs'.push (attr, value)
      let contents :=
        match inlineHover? with
        | some hoverHtml => contents ++ .tag "span" #[("class", "hover-info")] hoverHtml
        | none => contents
      pure <| some <| .tag name attrs' contents)

end Informal
