/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint.PreviewManifest
import VersoBlueprint.NodePage
import VersoBlueprint.ExtraPages
import VersoBlueprint.DeclIndex
import VersoBlueprint.DeclPage
import VersoBlueprint.Commands.TrustPages

/-!
Baked-in Blueprint entry point.

`PreviewManifest` cannot import `NodePage`/`ExtraPages` (they import it, so wiring
the node-page and project-management page steps from inside `blueprintMainWithPreviewData`
would create an import cycle). This top-level module sits above all three and
exposes `blueprintMainWithFeatures`, the one-call entry point consumers should use:
it runs the standard preview-data pipeline plus the per-node pages and the
worklist/owner/tag pages (and progress badge), so a consumer's `Main` no longer has
to assemble `extraSteps` by hand.
-/

namespace Informal.PreviewManifest

open Verso Doc
open Verso.Genre Manual

/--
Run the full Blueprint build for `text`: preview data, per-node pages, and the
project-management pages (worklist / owners / tags) and progress badge, followed by
any caller-supplied `extraSteps`.

This is the recommended entry point for Blueprint consumers (e.g. the
`verso-noperthedron` showcase). It is a thin wrapper over
`blueprintMainWithPreviewData` that prepends `emitBlueprintNodePages` and
`emitBlueprintExtraPages` to `extraSteps`, in the same order a hand-written `Main`
used. The supplied `extensionImpls` is threaded both to the preview pipeline and to
the node-page step (which highlights Lean code), so the consumer's extensions are
used throughout.
-/
def blueprintMainWithFeatures
    (text : Part Manual)
    (options : List String)
    (extensionImpls : ExtensionImpls)
    (config : RenderConfig := {})
    (extraSteps : List ExtraStep := []) : IO UInt32 :=
  -- Order matches the previously hand-written `Main`: node pages then PM pages,
  -- both after the preview-data step (which `blueprintMainWithPreviewData` prepends).
  blueprintMainWithPreviewData text options extensionImpls config
    (extraSteps :=
      Informal.NodePage.emitBlueprintNodePages extensionImpls
        :: Informal.ExtraPages.emitBlueprintExtraPages
        :: Informal.ExtraPages.emitBlueprintPmPage
        :: Informal.ExtraPages.emitBlueprintAuditPage
        :: Informal.ExtraPages.emitBlueprintMathlibCandidatesPage
        :: Informal.DeclIndex.emitBlueprintDeclIndexPages
        :: Informal.DeclPage.emitBlueprintDeclPages
        -- Neither the structural `uses`-graph gate nor the comparator-evidence
        -- freshness gate is an `ExtraStep`: both run between traversal and emission
        -- inside `emitBlueprintHtml` (`Informal.GraphGate`, `Informal.TrustFreshness`),
        -- so a failing gate leaves no rendered site behind. What *is* a step is the
        -- provenance record the gate's inputs are published as, for a CI gate to
        -- re-check against the working tree.
        :: Informal.TrustFreshness.emitTrustProvenance
        :: Informal.Commands.emitBlueprintComparatorPage
        :: extraSteps)

end Informal.PreviewManifest
