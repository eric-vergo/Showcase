/-
Comparator challenge fixture: the statement a verdict would certify.

Deliberately tiny and Mathlib-free so the trust-evidence tests can read, hash, and
display it without a heavyweight import.
-/

namespace TrustFixture

/-- The claim: addition on `Nat` commutes. -/
theorem add_comm_claim (m n : Nat) : m + n = n + m := by
  sorry

end TrustFixture
