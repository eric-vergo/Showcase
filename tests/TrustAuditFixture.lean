/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Opus 5 (Claude Code)
-/

/-!
The one declaration `tests/VersoBlueprintTests/TrustConsolidation.lean`'s audit-coverage
document wires: a deliberately unfinished theorem, declared unfinished in
`tests/fixtures/trust/formalization-declared-sorry.yaml`.

**It lives under its own module root on purpose.** `Informal.DeclRegistry.projectModuleRoots`
takes the root of each wired declaration's module, and the audit then enumerates every
imported module under it. A fixture inside `VersoBlueprintTests` would drag the whole test
support library into the audited set, whose own axiom footprint has nothing to do with
what that document is testing.
-/

namespace TrustAuditFixture

-- The `sorry` is the point, so its warning is expected output rather than noise.
/-- warning: declaration uses `sorry` -/
#guard_msgs in
theorem declaredSorryFixture : True := sorry

end TrustAuditFixture
