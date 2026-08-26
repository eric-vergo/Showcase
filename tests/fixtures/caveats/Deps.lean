/-
Chain-dependency fixture: the file the primary Challenge imports.

It carries its own `set_option`, which is the point — §A7(f)'s scan covers the whole
elaborated chain, so an override placed one file away from the Challenge is still reported.
-/

set_option maxHeartbeats 400000

namespace CaveatChain

/-- Truncated subtraction, one chain file away from the statement that reaches it. -/
def truncated (a b : Nat) : Nat := a - b

end CaveatChain
