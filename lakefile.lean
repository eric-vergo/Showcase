import Lake
open Lake DSL

-- Our Verso fork, which self-hosts `marked` for offline / strict-CSP viewing instead of
-- loading it from a CDN. Required before verso-slides' transitive (upstream) verso so this
-- fork wins resolution. Local-wired to the sibling working tree (matching blueprint/) so the
-- forked verso + subverso build together from source and stay consistent for standalone builds.
require verso from "../verso"
-- SubVerso fork (sibling working tree) for VSCode-faithful highlighting (const type/function split
-- + bracket-pair depth). Root-level require so it wins over verso's transitive subverso pin and all
-- manifests stay consistent (see consistent-subverso-manifests.yml).
require subverso from "../subverso"
require «verso-slides» from git "https://github.com/leanprover/verso-slides.git"@"v4.31.0"
require proofwidgets from git "https://github.com/leanprover-community/ProofWidgets4"@"v0.0.98"

package VersoBlueprint where
  precompileModules := false
  leanOptions := #[⟨`experimental.module, true⟩]

-- Blueprint core library.
@[default_target]
lean_lib VersoBlueprint where
  srcDir := "src"
  roots := #[`VersoBlueprint]

@[default_target]
lean_exe «vbp» where
  root := `VersoBlueprint.VbpMain
  srcDir := "src"
  supportInterpreter := true

@[default_target, test_driver]
lean_lib VersoBlueprintTests where
  srcDir := "tests"
  roots := #[
    `VersoBlueprintTests.Blueprint.Support,
    `VersoBlueprintTests.BlueprintAssets,
    `VersoBlueprintTests.BlueprintAutoDeps,
    `VersoBlueprintTests.BlueprintAttribute,
    `VersoBlueprintTests.BlueprintCodeRenderMatrix,
    `VersoBlueprintTests.BlueprintImportedDuplicates.Direct,
    `VersoBlueprintTests.BlueprintImportedDuplicates.ProviderA,
    `VersoBlueprintTests.BlueprintImportedDuplicates.ProviderB,
    `VersoBlueprintTests.BlueprintImportedDuplicates.Reexport,
    `VersoBlueprintTests.BlueprintImportedDuplicates.Transitive,
    `VersoBlueprintTests.BlueprintExternalHeadingStatus,
    `VersoBlueprintTests.BlueprintFormalization,
    `VersoBlueprintTests.BlueprintGraft,
    `VersoBlueprintTests.BlueprintGraph,
    `VersoBlueprintTests.BlueprintHeaderExtras,
    `VersoBlueprintTests.BlueprintInformal,
    `VersoBlueprintTests.BlueprintInlinePrecision,
    `VersoBlueprintTests.BlueprintLinkHover,
    `VersoBlueprintTests.BlueprintMainWrapper,
    `VersoBlueprintTests.BlueprintMathLint,
    `VersoBlueprintTests.BlueprintMetadataPanel,
    `VersoBlueprintTests.BlueprintNumbering,
    `VersoBlueprintTests.BlueprintSlides,
    `VersoBlueprintTests.BlueprintPreviewPanels,
    `VersoBlueprintTests.BlueprintPreviewSchema,
    `VersoBlueprintTests.BlueprintPreviewSource,
    `VersoBlueprintTests.BlueprintPreviewWiring,
    `VersoBlueprintTests.BlueprintRustCode,
    `VersoBlueprintTests.BlueprintSummaryLinks,
    `VersoBlueprintTests.BlueprintSummaryStatus,
    `VersoBlueprintTests.BlueprintTexMacros,
    `VersoBlueprintTests.BlueprintExternalMarkup,
    `VersoBlueprintTests.ExternalDeclRender,
    `VersoBlueprintTests.RuntimeCache,
    `VersoBlueprintTests.TestBlueprintRegistryMeta,
    `VersoBlueprintTests.TestBlueprintRegistryChecks,
    `VersoBlueprintTests.TestBlueprintRegistryCoverage,
    `VersoBlueprintTests.Vbp
  ]

lean_lib VersoBlueprintTestDocs where
  srcDir := "tests"
  roots := #[`VersoBlueprintTests.TestBlueprintRegistry]

lean_exe «blueprint-test-docs» where
  root := `BlueprintTestDocsMain
  srcDir := "tests"
  supportInterpreter := true
