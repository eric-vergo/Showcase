/-
Ambient-only *term* (§A2): no imports, and a reference to a declaration that exists in the
environment a Verso site elaborates in but not in a fresh `Init`-only one. The subprocess
must refuse to elaborate this; a branched-from-ambient environment would accept it and
report a closure over a statement the verifier never saw.
-/

theorem ambientOnly : Informal.Sha256.hexOfString "" = "" := sorry
