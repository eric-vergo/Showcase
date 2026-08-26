/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

/-!
A closure fixture with a known shape, in its own module so the walk can be told to treat
it as the challenge chain (a chain's declarations otherwise have no defining module at
all, which is a property of the subprocess environment and not reproducible in-process).

The shape each test leans on:

- `wrap` — a definition whose value names a **frontier** constant (`Nat.succ`), so the
  walk expands the definition and stops at the constant.
- `Tree` — an inductive whose constructor types name it back, which is the **cycle** the
  seen-set has to survive.
- `size` — a recursive definition, so the walk also meets the machinery Lean generates
  for it (`brecOn`, matchers) and has something to flag as auxiliary.
- `size_nonneg` — the **root**: a theorem whose statement names `size` and `Tree`, and
  whose proof names something the walk must never reach, since theorem values are not
  traversed.
-/

namespace VersoBlueprintTests.ClosureFixture

/-- Expanded through its value, which names a frontier constant. -/
def wrap (n : Nat) : Nat := Nat.succ n

/-- Expanded through its constructor types, which name it back. -/
inductive Tree where
  | leaf
  | node (left right : Tree)

/-- Recursive, so the walk also meets the recursion machinery. -/
def size : Tree → Nat
  | .leaf => wrap 0
  | .node l r => size l + size r

/-- The root. `Nat.zero_le` is named only by the proof, so it must not appear in the
closure of the statement. -/
theorem size_nonneg (t : Tree) : 0 ≤ size t := Nat.zero_le (size t)

end VersoBlueprintTests.ClosureFixture
