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
    -- the inline code, and `informal` for the no-Lean statement.
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
      hasSubstr out "aria-label=\"Lean status: proved\"" &&
      removedTemplateBinderJs?.isNone
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.LeanStatus
