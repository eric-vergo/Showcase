/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

/-!
Guard-presence fixtures, in their own module so the scan can be run against real
`ConstantInfo` types rather than against hand-built expressions.

Four shapes, one per state the guard tri-state has to distinguish:

- `guarded` carries `b ≤ a`, whose head is one of the shapes the table lists for truncated
  subtraction. The scan may say a guard-shaped hypothesis *occurs*, and nothing more.
- `guardedElsewhere` is CX-059: a `≠ 0` hypothesis about a variable that is not the
  divisor. The presence scan sees `Ne` and cannot tell that it is about something else,
  which is exactly why the copy for this state says it did not relate the hypothesis to
  the flagged operand.
- `unguarded` carries no hypothesis at all.
- `noGuardShape` uses a symbol the table records no guard for (`Nat.sqrt` is a floor, not
  an edge case a hypothesis could rule out), so nothing is looked for.
-/

namespace VersoBlueprintTests.CaveatFixture

/-- Truncated subtraction, reached only through here. -/
def gap (a b : Nat) : Nat := a - b

/-- Division by zero, reached only through here. -/
def ratio (a b : Nat) : Nat := a / b

/-- What the statements name; nothing about it looks like an edge case. -/
def score (a b : Nat) : Nat := gap a b + ratio a b

/-- The §A7(a) root, in-process: its type names `score`, `Nat` and equality, and nothing
that any table lists. What the traversal reaches through `score` is the whole point. -/
theorem scoreZero : score 0 0 = 0 := rfl

/-- A relevant guard: the subtrahend is bounded. -/
theorem guarded (a b : Nat) (h : b ≤ a) : gap a b + b = a := Nat.sub_add_cancel h

/-- CX-059: a guard-shaped hypothesis about a variable that is not the divisor. -/
theorem guardedElsewhere (a b c : Nat) (_h : c ≠ 0) : ratio a b = a / b := rfl

/-- No hypothesis at all. -/
theorem unguarded (a b : Nat) : score a b = gap a b + ratio a b := rfl

/-- A symbol the table records no guard shape for. -/
theorem noGuardShape (n : Nat) : Nat.sqrt n = Nat.sqrt n := rfl

end VersoBlueprintTests.CaveatFixture
