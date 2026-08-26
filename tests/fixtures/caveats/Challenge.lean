/-
Caveat fixture: the zeta shape (§A7(a)).

The certified statement mentions no total-function convention at all. Its *meaning* reaches
three of them, each hidden one wrapper deep: truncated subtraction on `ℕ` through `gap`,
division by zero through `ratio`, and both of those again through `score`, which is the
only thing the theorem names.

A scan over the root's type constants would find nothing here and report a clean result.
That is the whole reason the scan rides the meaning traversal instead.

`set_option maxRecDepth` at the top, and one inside a comment and one inside a string
below, give the lexical half of the scan something to get right.
-/

set_option maxRecDepth 700

namespace CaveatFixture

-- set_option maxHeartbeats 1 in
/- set_option debug.byAsSorry true -/

/-- Truncated subtraction, reached only through here. -/
def gap (a b : Nat) : Nat := a - b

/-- Division by zero, reached only through here. -/
def ratio (a b : Nat) : Nat := a / b

/-- What the statement names. Nothing about it looks like an edge case. -/
def score (a b : Nat) : Nat := gap a b + ratio a b

/-- A string that mentions the scanner's keyword without setting anything. -/
def note : String := "set_option maxHeartbeats 400000"

/-- The root. Its type names `score`, `Nat` and equality, and nothing else. -/
theorem score_zero : score 0 0 = 0 := rfl

end CaveatFixture
