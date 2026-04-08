import Lake
open Lake DSL

-- While the split is in progress, the extracted blueprint package depends on
-- the parent repo root, which remains a checkout of Verso.
-- require verso from "../verso"
require verso from git "https://github.com/leanprover/verso"@"v4.29.0"
require proofwidgets from git "https://github.com/leanprover-community/ProofWidgets4"@"v0.0.92"

package VersoBlueprint where
  precompileModules := false
  leanOptions := #[⟨`experimental.module, true⟩]

-- Blueprint core library.
@[default_target]
lean_lib VersoBlueprint where
  srcDir := "src"
  roots := #[`VersoBlueprint]

@[default_target, test_driver]
lean_lib VersoBlueprintTests where
  srcDir := "tests"
  roots := #[`VersoBlueprintTests]

lean_exe «blueprint-test-docs» where
  root := `BlueprintTestDocsMain
  srcDir := "tests"
  supportInterpreter := true
