import Lake
open Lake DSL

-- Our Verso fork, which self-hosts `marked` for offline / strict-CSP viewing instead of
-- loading it from a CDN. Required before verso-slides' transitive (upstream) verso so this
-- fork wins resolution. Git-pinned to the eric-vergo fork's `blueprint` branch so published
-- consumers (the A362583 showcase) and standalone clones resolve the same fork tree.
require verso from git "https://github.com/eric-vergo/verso.git"@"blueprint"
-- SubVerso fork for VSCode-faithful highlighting (const type/function split + bracket-pair depth).
-- Root-level require so it wins over verso's transitive subverso pin and all manifests stay
-- consistent; points at the same eric-vergo/subverso `blueprint` branch verso itself requires.
require subverso from git "https://github.com/eric-vergo/subverso.git"@"blueprint"
require «verso-slides» from git "https://github.com/leanprover/verso-slides"@"v4.33.0"
require proofwidgets from git "https://github.com/leanprover-community/ProofWidgets4"@"v0.0.104"

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

-- Blueprint skeleton generator. Loads a *subject* module with `importModules` at
-- runtime (hence `supportInterpreter`), so it is run from the presentation repository
-- whose Lake workspace supplies the module's oleans on LEAN_PATH:
--   lake exe showcase-gen --module <Module> --out .
@[default_target]
lean_exe «showcase-gen» where
  root := `VersoBlueprint.ShowcaseGenMain
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
    `VersoBlueprintTests.BlueprintDeclPages,
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
    `VersoBlueprintTests.BlueprintSharedChrome,
    `VersoBlueprintTests.BlueprintSubjectRoots,
    `VersoBlueprintTests.Sha256,
    `VersoBlueprintTests.ShowcaseGen,
    `VersoBlueprintTests.TrustEvidence,
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
