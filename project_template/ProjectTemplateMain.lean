import VersoManual
import VersoBlueprint.Main
import ProjectTemplate.Blueprint

open Verso Doc
open Verso.Genre Manual

-- `blueprintMainWithFeatures` is the recommended entry point: it runs the preview-data
-- pipeline AND the generation-time steps that write the pages a blueprint site is expected to
-- have — one page per node, the project-management hub and its worklist / audit / owner / tag
-- pages, the declaration catalogue when the registry is on, the trust-provenance record, and
-- the statement-comparator evidence page. The lower-level `blueprintMainWithPreviewData` runs
-- none of them, which leaves the homepage trust strip's comparator badge pointing at a page
-- nobody wrote.
def main (args : List String) : IO UInt32 :=
  Informal.PreviewManifest.blueprintMainWithFeatures
    (%doc ProjectTemplate.Blueprint)
    args
    (extensionImpls := by exact extension_impls%)
