import Lake
open Lake DSL

require verso from git "https://github.com/leanprover/verso"@"v4.29.0"
require VersoBlueprint from "../../../"

package PreviewRuntimeShowcase where
  precompileModules := false
  leanOptions := #[⟨`experimental.module, true⟩]

@[default_target]
lean_lib PreviewRuntimeShowcase where

lean_exe «blueprint-gen» where
  root := `PreviewRuntimeShowcaseMain
