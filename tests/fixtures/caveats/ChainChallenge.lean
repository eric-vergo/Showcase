import Deps

/-
The primary Challenge of a two-file chain. Its statement names `wrapped`; `wrapped` names
`truncated`, which lives in the other file and is where the table symbol is.
-/

set_option maxRecDepth 512

namespace CaveatChain

/-- What the statement names. -/
def wrapped (a b : Nat) : Nat := truncated a b

/-- The root. -/
theorem wrapped_zero : wrapped 0 0 = 0 := rfl

end CaveatChain
