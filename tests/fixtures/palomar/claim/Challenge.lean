/-
Comparator challenge fixture for the registry surface: the statement a registered
verdict would certify.

Deliberately tiny and Mathlib-free, like `tests/fixtures/trust/Challenge.lean`. Its
SHA-256 is recorded both in `comparator-status.json` beside it (so the displayed bytes
are bound to the verdict) and in the Palomar record
`../bundle/entries/PALOMAR-2026-08-07-000007-v1.json` (so the registration is bound to
the same bytes). Editing this file without refreshing both digests is a build error —
that is the binding working.
-/

namespace RegistryFixture

/-- The claim: multiplication on `Nat` commutes. -/
theorem mul_comm_claim (m n : Nat) : m * n = n * m := by
  sorry

end RegistryFixture
