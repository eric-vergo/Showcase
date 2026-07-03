/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.Elab.Command
import Verso
import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Commands.Summary.Collect
import VersoBlueprint.Commands.Summary.Render
import VersoBlueprint.Commands.TrustStrip

namespace Informal.Commands

open Lean Elab Command
open Informal Data Environment

open Verso Doc Elab Syntax in
def mkSummaryPart (stx : Syntax) (endPos : String.Pos.Raw) : PartElabM FinishedPart := do
  let titlePreview := "Blueprint Summary"
  let titleInlines ← `(inline | "Blueprint Summary")
  let expandedTitle ← #[titleInlines].mapM (elabInline ·)
  let metadata : Option (TSyntax `term) := some (← `(term| { number := false }))
  let summary ← buildSummary
  if verso.blueprint.debug.commands.get (← Lean.getOptions) then
    logInfo m!"Blueprint summary for {summary.totalEntries} entries"
  let block ← ``(Verso.Doc.Block.other (Informal.Commands.Block.summary $(quote summary)) #[])
  let subParts := #[]
  pure <| FinishedPart.mk stx stx expandedTitle titlePreview metadata #[block] subParts endPos

open Verso Doc Elab Syntax PartElabM in
@[part_command Lean.Doc.Syntax.command]
public meta def blueprintSummaryCmd : PartCommand
  | stx@`(block|command{blueprint_summary}) => do
    let endPos := stx.getTailPos?.get!
    closePartsUntil 1 endPos
    addPart (← mkSummaryPart stx endPos)
  | _ => (Lean.Elab.throwUnsupportedSyntax : PartElabM Unit)

open Verso Doc Elab Syntax PartElabM in
/--
Inline dashboard command.

Unlike `blueprint_summary` (which splits off its own page via
`closePartsUntil`/`addPart`), this adds a `Block.dashboard` to the *current*
part with `addBlock`. Placed at the top of the root `#doc` body it renders into
`index.html`, making the dashboard the landing page.
-/
@[part_command Lean.Doc.Syntax.command]
public meta def blueprintDashboardCmd : PartCommand
  | `(block|command{blueprint_dashboard}) => do
    let summary ← buildSummary
    if verso.blueprint.debug.commands.get (← Lean.getOptions) then
      logInfo m!"Blueprint dashboard for {summary.totalEntries} entries"
    -- Trust strip (additive): only when the `verso.blueprint.trust.*` options
    -- name artifacts; unconfigured consumers render the dashboard unchanged.
    if let some trust ← elabTrustData? then
      PartElabM.addBlock (← ``(Verso.Doc.Block.other (Informal.Commands.Block.trustStrip $(quote trust)) #[]))
    PartElabM.addBlock (← ``(Verso.Doc.Block.other (Informal.Commands.Block.dashboard $(quote summary)) #[]))
  | _ => (Lean.Elab.throwUnsupportedSyntax : PartElabM Unit)

end Informal.Commands
