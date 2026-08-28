/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint
import VersoManual

/-!
A milestone whose `members` name something that is not a blueprint node.

That is a defect and fails `lake build` — the alternative is a proof overview that
silently omits part of what its author said it covers. The error is reported once,
at the `{blueprint_overview}` that consults the milestones, and the build recovers
so a single run reports every defect rather than the first one.

Deliberately its own module: milestones live in an environment extension shared by
every document in a module, so a broken fixture beside a good one would re-report
itself from the good one's overview too.
-/

open Verso
open Verso.Genre.Manual
open Informal

set_option doc.verso true

namespace Verso.VersoBlueprintTests.BlueprintProofOverview.Phantom

/--
error: Milestone ms:phantom lists member 'def:phantom.nope', which is not a blueprint node label
-/
#guard_msgs(error, drop info, drop warning) in
#docs (Genre.Manual) proofOverviewPhantomDoc "Proof Overview Phantom Member" :=
:::::::

:::definition "def:phantom.real"
A node that exists.
:::

:::milestone "ms:phantom" (title := "Phantom") (members := "def:phantom.real, def:phantom.nope")
A milestone that claims a node the blueprint does not have.
:::

{blueprint_overview}
:::::::

end Verso.VersoBlueprintTests.BlueprintProofOverview.Phantom
