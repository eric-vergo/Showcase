import Init

/-!
CX-044: a chain dependency that does NOT elaborate under its own header.

`Lean.Json` is unknown to a file importing only `Init`. The primary Challenge beside it
imports `Lean`, so a tool that loads the whole chain's imports at once and carries one
environment forward accepts this file — and reports a completed closure over a file the
comparator's own import discipline would reject.
-/

namespace LaterImportSuperset

def value : Lean.Json := Lean.Json.null

end LaterImportSuperset
