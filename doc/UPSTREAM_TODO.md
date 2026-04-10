# Verso Upstream TODO

Items to upstream to `verso` once the blueprint split is stabilized.

## Highest Priority

- [ ] Upstream the `VersoManual` manual-rendering extension hook used by
  `VersoBlueprint.PreviewManifest`, so downstream executables no longer need a
  blueprint-local workaround for shared preview-manifest emission.
  - preserved branch: `ejgallego/verso-manual-extra-step-upstream-20260313`
  - PR shortcut:
    `https://github.com/ejgallego/verso/pull/new/verso-manual-extra-step-upstream-20260313`

- [ ] Decide whether page-level KaTeX preludes belong in core `verso`, and if
  so upstream a generic hook instead of keeping a Blueprint-owned mechanism.

- [ ] Provide a cleaner upstream way for elaboration-time helpers to resolve
  package-owned runtime assets without downstream packages hand-rolling module
  search-path heuristics.
  - current Blueprint pressure point:
    KaTeX math lint needs to locate both Blueprint's `static-web/katex-lint.mjs`
    and Verso's vendored `katex.mjs` during elaboration
  - current local workaround:
    resolve package roots from module locations and pass absolute paths into the
    helper process instead of assuming a fixed `.lake/packages/...` layout
  - desired upstream direction:
    either expose a stable package-root/package-asset lookup API in the
    elaboration context, or provide a Verso-owned helper entrypoint that hides
    the vendored asset layout from downstream packages

- [ ] Ask Lake maintainers to honor package overrides during `lake update`
  bootstrap, not only during manifest-based materialization.
  - confirmed on Lean `v4.29.0`
  - `loadWorkspace` passes `packageOverrides` only to `materializeDeps`, while
    `updateManifest` calls `updateAndMaterialize` without threading overrides
  - practical effect:
    `.lake/package-overrides.json` and `lake --packages ... update` do not stop
    an initial upstream clone when a fresh external project has no manifest yet
  - desired behavior:
    `lake update` should apply workspace and CLI package overrides during the
    initial dependency-resolution/materialization path as well
  - local workaround in `verso-blueprint`:
    the harness rewrites the cloned `lakefile.lean` dependency on
    `VersoBlueprint` before running `lake update`

## Hover and Rendering Follow-Ups

- [ ] Upstream the `Verso.Code.Highlighted` docstring rerender needed for
  dynamic hover content, then drop the local copy.

- [ ] Upstream the separate hover robustness guards in
  `Verso.Code.Highlighted`, since those look like general hardening rather than
  Blueprint-specific behavior.

- [ ] Add a generic wide-content page mode to `verso`, so pages such as the
  Blueprint dependency graph can opt into a wider content frame without
  carrying Blueprint-local page-shell CSS overrides.
  - current pressure points are the normal `.content-wrapper`/`main section`
    max-width rules and the ToC-aware shell layout
  - desired behavior is a page-level or section-level opt-in that widens the
    content frame while preserving the shared shell semantics
  - once this exists upstream, Blueprint should keep only graph-local layout
    CSS and a local wide-viewport regression for the graph page

## Repository Split Follow-Ups

- [ ] Move Blueprint-owned CI, release, and deploy infrastructure into the
  standalone `verso-blueprint` repository when that split is finalized.
  - current workflow copies live in `.github/workflows/`
  - current helper scripts live in `deploy/`

- [ ] Revisit the bibliography formatting cleanup in
  `VersoManual/Bibliography.lean` and decide whether it belongs upstream or
  should remain Blueprint-local.
