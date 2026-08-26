import Verso
import VersoManual
import VersoBlueprint

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Addition" =>

:::group "addition_core"
Core statements about addition on natural numbers.
:::

:::author "project_author" (name := "Project Author")
:::

:::definition "addition_spec" (parent := "addition_core")
We write $`a + b` for the result of adding $`b` to $`a`.
This starter Blueprint begins with the most basic sanity checks around that
operation.
:::

:::theorem "addition_right_identity" (parent := "addition_core") (owner := "project_author") (tags := "starter, arithmetic") (effort := "small") (priority := "high")
For every natural number $`n`, adding zero on the right leaves it unchanged:
$`n + 0 = n`.
This is the first sanity check for {uses "addition_spec"}[].
:::

:::proof "addition_right_identity"
Induct on $`n`. The base case is immediate and the inductive step unfolds one
successor on each side.
:::

```lean "addition_right_identity"
theorem nat_add_zero_right (n : Nat) : n + 0 = n := by
  simp
```

A project ported from an existing paper or set of notes can keep the original
wording next to the statement it became, together with the place it was read
from. The attachment below records the file and the line range in
`source/addition-source.tex`; both travel with the node in the exported
Blueprint manifest. `(display := source)` makes the witness visible on the
rendered page — the default is `hidden`, which is what a large port normally
wants.

```tex "addition_right_identity" (slot := statement) (path := "source/addition-source.tex") (start_line := 3) (start_character := 0) (end_line := 6) (end_character := 0) (display := source)
\begin{theorem}\label{thm:addition-right-identity}
For every natural number $n$, adding zero on the right leaves it unchanged.
\end{theorem}
```

:::theorem "addition_assoc" (parent := "addition_core") (lean := "Nat.add_assoc")
For all natural numbers $`a`, $`b`, and $`c`, addition is associative:
$`(a + b) + c = a + (b + c)`.
This is another consequence of {uses "addition_spec"}[].
:::

:::proof "addition_assoc"
Lean already provides this theorem as `Nat.add_assoc`, so this Blueprint entry
links to an existing declaration instead of restating the code locally.
:::

:::definition "addition_runtime_note" (parent := "addition_core")
Some projects keep implementation notes or helper snippets next to the informal
statement surface. Blueprint can attach a small Rust block for that purpose.
The helper below computes the sum specified in {uses "addition_spec"}[].
:::

```rust "addition_runtime_note"
pub fn add_preview(x: i32, y: i32) -> i32 {
    x + y
}
```
