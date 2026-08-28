/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint
import VersoManual

/-!
Milestones that depend on each other in a circle.

Rows are longest-path depth, so a cycle has no layout; and an overview whose
waypoints each rest on the other is not a proof sketch anybody can read. Reported
as an error, then recovered from with a flat layout so the rest of the build's
diagnostics still reach the author in one run.

Its own module for the same reason as the phantom-member fixture.
-/

open Verso
open Verso.Genre.Manual
open Informal

set_option doc.verso true

namespace Verso.VersoBlueprintTests.BlueprintProofOverview.Cycle

/--
error: Milestone dependencies contain a cycle; the proof overview cannot be laid out in rows
-/
#guard_msgs(error, drop info, drop warning) in
#docs (Genre.Manual) proofOverviewCycleDoc "Proof Overview Cycle" :=
:::::::

:::definition "def:cycle.x"
One node.
:::

:::definition "def:cycle.y"
Another node.
:::

:::milestone "ms:cycle.x" (title := "X") (uses := "ms:cycle.y") (members := "def:cycle.x")
A waypoint that rests on the next one.
:::

:::milestone "ms:cycle.y" (title := "Y") (uses := "ms:cycle.x") (members := "def:cycle.y")
Which rests on the first one.
:::

{blueprint_overview}
:::::::

end Verso.VersoBlueprintTests.BlueprintProofOverview.Cycle
