import Lake
open Lake DSL

-- Our Verso fork (self-hosts `marked`), pinned as a ROOT-level direct require. This is required
-- because verso-slides transitively pins upstream leanprover/verso@v4.31.0, which otherwise wins
-- resolution (a root direct require overrides transitive ones). A fork branch also isn't in
-- Lake's prebuilt cache, so it is built from source and picks up the marked change.
require verso from git "https://github.com/eric-vergo/verso"@"viewer-integration"

-- Build the bundled example against the in-repo blueprint package.
require VersoBlueprint from ".."

package ProjectTemplate where
  precompileModules := false
  leanOptions := #[⟨`experimental.module, true⟩]

@[default_target]
lean_lib ProjectTemplate where

lean_exe «blueprint-gen» where
  root := `ProjectTemplateMain
