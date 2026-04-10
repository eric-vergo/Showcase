import Lake
open Lake DSL

require verso from git "https://github.com/leanprover/verso"@"v4.28.0"
require VersoBlueprint from git "https://github.com/leanprover/verso-blueprint"@"main"

package ProjectTemplate where
  precompileModules := false
  leanOptions := #[⟨`experimental.module, true⟩]

@[default_target]
lean_lib ProjectTemplate where

lean_exe «blueprint-gen» where
  root := `ProjectTemplateMain
