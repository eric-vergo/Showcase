/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Slides
import Verso.Doc.Concrete
import VersoBlueprintTests.Blueprint.Support

open VersoSlides

namespace Verso.VersoBlueprintTests.BlueprintSlides

open Verso.VersoBlueprintTests.Blueprint.Support

#docs (Slides) blueprintNodeSlideFixture "Blueprint Node Slide" :=
:::::::
# Example Blueprint Node

{blueprint_node "addition_assoc" (siteBase := "blueprint")}
:::::::

/-- info: true -/
#guard_msgs in
#eval
  let js := Informal.Slides.blueprintSlidesJs
  hasSubstr js "bp_extra_slot_group" &&
    hasSubstr js "bp_extra_slot_uses" &&
    hasSubstr js "bp_extra_slot_code" &&
    hasSubstr js "bp_extra_slot_used_by" &&
    hasSubstr js "bp_extras_with_uses" &&
    appearsBefore js "renderGroupChip(entry)" "renderUsesChip(dependencyEntries(entry))" &&
    appearsBefore js "renderUsesChip(dependencyEntries(entry))" "renderCodeStatusChip(entry, codeCount)" &&
    appearsBefore js "renderCodeStatusChip(entry, codeCount)" "renderUsedByChip(usedBy)"

end Verso.VersoBlueprintTests.BlueprintSlides
