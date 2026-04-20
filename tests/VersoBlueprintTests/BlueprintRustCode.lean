/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.Blueprint.Support

namespace Verso.VersoBlueprintTests.BlueprintRustCode

open Verso
open Verso.Genre.Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support

private def manualImpls : ExtensionImpls := extension_impls%

set_option doc.verso true

#docs (Genre.Manual) rustInlineDoc "Rust Inline Doc" :=
:::::::
:::definition "rust_inline"
Inline Rust attachment.

```rust "rust_inline"
pub fn inline_add(x: i32, y: i32) -> i32 {
    x + y
}
```
:::
:::::::

#docs (Genre.Manual) rustInvalidDoc "Rust Invalid Doc" :=
:::::::
:::definition "rust_invalid"
Broken Rust attachment.

```rust "rust_invalid"
pub fn broken( -> i32 { 1 }
```
:::
:::::::

/-- info: true -/
#guard_msgs in
#eval! do
  let out ← renderManualDocHtmlString manualImpls rustInlineDoc
  pure <|
    hasSubstr out "Inline Rust attachment." &&
    !hasSubstr out "inline_add" &&
    !hasSubstr out "bp_code_link_label\">Rust"

/-- info: true -/
#guard_msgs in
#eval! do
  let out ← renderManualDocHtmlString manualImpls rustInvalidDoc
  pure <|
    hasSubstr out "Broken Rust attachment." &&
    !hasSubstr out "pub fn broken" &&
    !hasSubstr out "bp_code_link_label\">Rust"

end Verso.VersoBlueprintTests.BlueprintRustCode
