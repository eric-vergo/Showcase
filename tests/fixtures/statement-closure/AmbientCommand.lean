/-
Ambient-only *command macro* (§A2): no imports, and Verso's `#docs`, which is in scope
wherever the site elaborates and absent from a fresh `Init`-only environment. The
subprocess must refuse this too — a chain that only parses because the host happened to
import the right macros is not the chain the verifier checked.
-/

#docs (Verso.Genre.Manual) ambientDoc "Ambient" :=
:::
Text.
:::
