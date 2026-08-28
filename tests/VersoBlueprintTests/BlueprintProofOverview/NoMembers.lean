/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint
import VersoManual

/-!
A milestone that lists no members at all.

Not an error: a waypoint an author has not yet populated is a legitimate state, and
the overview still lays it out. But it covers nothing, so it can never witness an
edge, and every edge incident to it comes out author-asserted — a page of numbers
that look like an authoring mistake somewhere else entirely.

It is also the exact signature of the one trap this syntax has: a Verso directive
reads its arguments from its opening line, so a `(members := …)` wrapped onto a
continuation line silently becomes body prose. Both warnings are captured below,
because the pair is what an author actually sees.

Its own module for the same reason as the phantom-member and cycle fixtures:
milestones live in an environment extension shared by every document in a module.
-/

open Verso
open Verso.Genre.Manual
open Informal

set_option doc.verso true

namespace Verso.VersoBlueprintTests.BlueprintProofOverview.NoMembers

/--
warning: Milestone ms:nomembers.empty lists no members — its edges can never be witnessed; if the `(members := …)` argument was wrapped onto a continuation line, put it on the directive's opening line
---
warning: proof overview: 1 milestone edge(s) have no dependency path between the two milestones' nodes, so they are shown as author-asserted: ms:nomembers.empty → ms:nomembers.real
-/
#guard_msgs(error, warning, drop info) in
#docs (Genre.Manual) proofOverviewNoMembersDoc "Proof Overview No Members" :=
:::::::

:::definition "def:nomembers.base"
A node that exists.
:::

:::milestone "ms:nomembers.real" (title := "Populated") (members := "def:nomembers.base")
A milestone that says what it is made of.
:::

:::milestone "ms:nomembers.empty" (title := "Empty") (uses := "ms:nomembers.real")
A milestone whose members never reached the directive's opening line.
:::

{blueprint_overview}
:::::::

end Verso.VersoBlueprintTests.BlueprintProofOverview.NoMembers
