/-
Comparator solution fixture: a proof of the challenge statement.

Re-declares the challenge's name rather than importing it, mirroring the layout the
comparator expects of a real solution module.
-/

namespace TrustFixture

/-- The claim, proved. -/
theorem add_comm_claim (m n : Nat) : m + n = n + m :=
  Nat.add_comm m n

end TrustFixture
