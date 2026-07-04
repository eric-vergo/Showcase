/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintPreviewWiring.Shared

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.LeanStatus

open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls leanStatusChipDoc
    let removedTemplateBinderJs? := findRemovedTemplatePreviewBinderJs? st
    -- The heading L∃∀N status chips (and the code-summary hover preview they
    -- hosted) are gone (clean-card 1D). Each statement now carries a status dot
    -- keyed by `data-status`: proved / containsSorry / axiomLike statuses from
    -- the inline code, and `informal` for the no-Lean statement. The `data-status`
    -- tag stays "proved" for a completed statement, but the accessible wording is
    -- kind-aware: these fixture nodes are all definitions, so the completed one
    -- reads "Lean status: formalized" (a definition has no proof to prove) rather
    -- than "proved" — see `CodeSummary.statusDotHtmlOfTag`.
    pure (
      !hasSubstr out "bp_code_link_status_proved" &&
      !hasSubstr out "bp_code_link_status_warning" &&
      !hasSubstr out "bp_code_link_status_axiom" &&
      !hasSubstr out "bp_code_link_status_absent" &&
      !hasSubstr out "bp_code_summary_preview_root" &&
      !hasSubstr out "data-bp-preview-id=\"bp-code-summary\"" &&
      hasSubstr out "class=\"bp_status_dot\"" &&
      hasSubstr out "data-status=\"proved\"" &&
      hasSubstr out "data-status=\"containsSorry\"" &&
      hasSubstr out "data-status=\"axiomLike\"" &&
      hasSubstr out "data-status=\"informal\"" &&
      hasSubstr out "role=\"img\"" &&
      hasSubstr out "aria-label=\"Lean status: formalized\"" &&
      removedTemplateBinderJs?.isNone
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.LeanStatus
