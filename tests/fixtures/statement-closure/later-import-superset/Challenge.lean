import Lean
import Dep

/-!
The later file whose `import Lean` the dependency must not be allowed to borrow.
-/

namespace LaterImportSuperset

theorem root : value = Lean.Json.null := rfl

end LaterImportSuperset
