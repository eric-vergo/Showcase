/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint
import VersoBlueprintTests.Blueprint.Support
import VersoManual

open Lean
open Verso Genre Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintTexSource

private def texSourceRaw? (sources : Array (String × Informal.Data.TexSource)) (slot : String) : Option String :=
  sources.findSome? fun entry =>
    if entry.1 == slot then
      some entry.2.raw.trimAscii.toString
    else
      none

#docs (Manual) texSourceDoc "TeX Source" :=
:::::::
:::theorem "tex.source"
Statement body.
:::

```tex "tex.source"
\begin{theorem}\label{thm:tex-source}
For every natural number $n$, adding zero on the right leaves it unchanged.
\end{theorem}
```
:::::::

#docs (Manual) unlabeledTexSourceDoc "Unlabeled TeX Source" :=
:::::::
:::theorem "tex.unlabeled.anchor"
Anchor statement.
:::

```tex
\begin{theorem}
An unlabeled witness should stay hidden and should not create a Blueprint node.
\end{theorem}
```
:::::::

#docs (Manual) texWitnessDoc "TeX Witness" :=
:::::::
```tex "tex.witness"
\begin{theorem}\label{thm:tex-witness}
A tex-only witness can introduce a Blueprint node while porting.
\end{theorem}
```
:::::::

#docs (Manual) texMultiWitnessDoc "TeX Witness Slots" :=
:::::::
```tex "tex.multi" (slot := statement)
\begin{theorem}\label{thm:tex-multi}
Statement witness.
\end{theorem}
```

```tex "tex.multi" (slot := "proof")
\begin{proof}
Proof witness.
\end{proof}
```
:::::::

/--
error: Label «tex.duplicate» already has an associated TeX witness in slot 'proof'
-/
#guard_msgs in
#docs (Manual) duplicateTexSlotDoc "Duplicate TeX Witness Slot" :=
:::::::
```tex "tex.duplicate" (slot := proof)
\begin{proof}
First proof witness.
\end{proof}
```

```tex "tex.duplicate" (slot := "proof")
\begin{proof}
Second proof witness.
\end{proof}
```
:::::::

/-- info: true -/
#guard_msgs in
#eval
  show CoreM Bool from do
    let state := Informal.Environment.informalExt.getState (← getEnv)
    let some node := state.data.get? (Name.mkSimple "tex.source")
      | pure false
    let some unlabeledAnchor := state.data.get? (Name.mkSimple "tex.unlabeled.anchor")
      | pure false
    let some witness := state.data.get? (Name.mkSimple "tex.witness")
      | pure false
    let some multi := state.data.get? (Name.mkSimple "tex.multi")
      | pure false
    let storedSource := texSourceRaw? node.texSources Informal.Data.defaultTexSourceSlot |>.getD ""
    let witnessSource := texSourceRaw? witness.texSources Informal.Data.defaultTexSourceSlot |>.getD ""
    let multiStatementSource := texSourceRaw? multi.texSources "statement" |>.getD ""
    let multiProofSource := texSourceRaw? multi.texSources "proof" |>.getD ""
    pure <|
      node.kind == .theorem &&
      node.statement.isSome &&
      hasSubstr storedSource "\\begin{theorem}" &&
      hasSubstr storedSource "\\label{thm:tex-source}" &&
      hasSubstr storedSource "\\end{theorem}" &&
      unlabeledAnchor.kind == .theorem &&
      unlabeledAnchor.statement.isSome &&
      unlabeledAnchor.texSources.isEmpty &&
      witness.statement.isNone &&
      witness.proof.isNone &&
      hasSubstr witnessSource "\\begin{theorem}" &&
      hasSubstr witnessSource "\\label{thm:tex-witness}" &&
      hasSubstr witnessSource "\\end{theorem}" &&
      multi.statement.isNone &&
      multi.proof.isNone &&
      hasSubstr multiStatementSource "Statement witness." &&
      hasSubstr multiProofSource "Proof witness."

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let texOut ← renderManualDocHtmlString extension_impls% texSourceDoc
    let unlabeledOut ← renderManualDocHtmlString extension_impls% unlabeledTexSourceDoc
    let witnessOut ← renderManualDocHtmlString extension_impls% texWitnessDoc
    let multiOut ← renderManualDocHtmlString extension_impls% texMultiWitnessDoc
    pure <|
      !hasSubstr texOut "\\begin{theorem}" &&
      !hasSubstr texOut "thm:tex-source" &&
      !hasSubstr texOut "adding zero on the right leaves it unchanged" &&
      !hasSubstr unlabeledOut "\\begin{theorem}" &&
      !hasSubstr unlabeledOut "unlabeled witness should stay hidden" &&
      !hasSubstr witnessOut "\\begin{theorem}" &&
      !hasSubstr witnessOut "thm:tex-witness" &&
      !hasSubstr witnessOut "tex-only witness can introduce a Blueprint node" &&
      !hasSubstr multiOut "Statement witness." &&
      !hasSubstr multiOut "Proof witness."

end Verso.VersoBlueprintTests.BlueprintTexSource
