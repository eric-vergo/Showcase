/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintMetadataPanel

open Verso
open Verso.Genre.Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

set_option doc.verso true

private def manualImpls : ExtensionImpls := extension_impls%

#docs (Genre.Manual) metadataPanelDoc "Blueprint Metadata Panel" :=
:::::::
:::author "alice" (name := "Alice Example") (url := "https://example.com/alice") (image_url := "https://example.com/alice.png")
:::

:::definition "def:meta.panel" (owner := "alice") (tags := "analysis, critical") (effort := "small") (priority := "high") (pr_url := "https://github.com/example/repo/pull/7")
Metadata panel body.
:::
:::::::

-- The two-column node card no longer inlines the statement metadata panel (the
-- T2 "bare card"): owner / tags / effort / priority / PR moved off the card to
-- the properties rail and the worklist / owner / tag pages. This guard asserts a
-- definition still renders as a card but carries none of that metadata inline,
-- and — upholding the no-avatar hard constraint at the card surface — that even
-- though the author declares an `image_url`, neither the avatar wrapper class nor
-- the external image URL (nor the owner/PR links) ever leaks onto the card. The
-- positive owner-name render alongside the same no-avatar guarantee is exercised
-- on the surviving metadata-panel surface (the slide renderer) in `BlueprintSlides`.
/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let out ← renderManualDocHtmlString manualImpls metadataPanelDoc
    pure (
      hasSubstr out "bp_card2" &&
      !hasSubstr out "class=\"bp_metadata_panel\"" &&
      !hasSubstr out "Alice Example" &&
      !hasSubstr out "class=\"bp_metadata_avatar\"" &&
      !hasSubstr out "https://example.com/alice.png" &&
      !hasSubstr out "https://example.com/alice" &&
      !hasSubstr out "https://github.com/example/repo/pull/7"
    )

end Verso.VersoBlueprintTests.BlueprintMetadataPanel
