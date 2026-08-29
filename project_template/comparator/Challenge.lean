/-!
# The comparator challenge

The claim an independent checker is asked to certify, stated on its own. It imports nothing,
so a reader can see the whole statement without reading this project: the trusted closure of
the claim is exactly what is written here.

A challenge module STATES; it never proves. Every theorem in it ends in `sorry`, which is why
this module is registered as a Lake lib and is deliberately not a default target: `lake build`
must never elaborate it. `comparator/Solution.lean` re-declares the same statement, verbatim,
and proves it.

When you copy this template, replace the theorem below with your project's headline claim and
keep the two files in step: the statement in `Solution.lean` must be byte-identical to the one
here, and `comparator/comparator.json` must name it under `theorem_names`.
-/

namespace Challenge

/-- Addition on the natural numbers is associative. -/
theorem add_assoc (a b c : Nat) : a + b + c = a + (b + c) := sorry

end Challenge
