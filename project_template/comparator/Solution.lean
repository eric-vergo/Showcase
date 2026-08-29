/-!
# The solution to the comparator challenge

The same statement as `comparator/Challenge.lean`, proved. The comparator checks that the two
statements are equal, that the proof kernel-checks, and that its axiom closure stays inside the
`permitted_axioms` of `comparator/comparator.json`.

This module must NOT import the challenge: importing it would let the solution inherit the
challenge's `sorry` rather than re-state the claim. It re-declares the statement instead, and
the comparator compares the two.

A real project's solution imports its own library and transports the library theorem onto the
restated claim — for example `import MyProject` and then
`theorem Challenge.thm : … := MyProject.thm`. This starter's claim is a Lean core lemma, so it
imports nothing at all.
-/

namespace Challenge

/-- Addition on the natural numbers is associative. -/
theorem add_assoc (a b c : Nat) : a + b + c = a + (b + c) := Nat.add_assoc a b c

end Challenge
