# Verso Upstream Backlog

Last reviewed: 2026-06-05

This file is the repository's local "Verso upstream backlog": a queue of
changes that would be better solved in upstream `verso`, Lake, or Lean once the
Blueprint split stabilizes.

When a maintainer or agent says "add this to the Verso upstream backlog" or
"register this in the Verso upstream backlog", the default meaning is:

- record the item here

That phrase does not authorize opening or editing upstream GitHub issues or
pull requests unless that upstream write action is explicitly requested.

## Triage Rules

1. Keep concrete upstream asks here; keep Blueprint-local implementation work in
   [`ROADMAP.md`](./ROADMAP.md).
2. Prefer one item per upstream API or behavior change.
3. Record the local workaround that can be removed when the upstream work lands.
4. Link an upstream issue or PR when one exists, but do not create or mutate
   upstream GitHub state unless explicitly asked.

## Manual Rendering and Cross-References

- [ ] Support private or filtered xref-domain export for Manual HTML output.
  - upstream issue:
    `leanprover/verso#840`
  - current Blueprint workaround:
    `PreviewManifest.publicXrefJson` filters traversal domains after traversal,
    and `PreviewManifest.filterPublicXrefOutput` rewrites `xref.json` plus the
    generated find page after Verso HTML emission
  - desired upstream behavior:
    extensions should be able to mark domains as public xref data or private
    traversal-local storage before `xref.json` and the find page are emitted
  - secondary upstream improvement:
    emit compressed/minified `xref.json` when appropriate

- [ ] Add Manual HTML extension hooks around traversal and emission.
  - current Blueprint workaround:
    `PreviewManifest.blueprintMain` mirrors Verso's top-level single-page and
    multi-page dispatcher while still delegating to Verso traversal and HTML
    emitters
  - needed hook shape:
    a post-traversal/pre-HTML-emission transform for `TraverseState` and
    `HtmlAssets`, plus a way to customize the xref payload used by both
    `xref.json` and the find page
  - still-useful lower-priority hook:
    a post-emit extra step for downstream files such as Blueprint's shared
    preview manifest
  - preserved branch:
    `ejgallego/verso-manual-extra-step-upstream-20260313`
  - PR shortcut:
    `https://github.com/ejgallego/verso/pull/new/verso-manual-extra-step-upstream-20260313`

- [ ] Add a generic wide-content page mode for Manual pages.
  - current Blueprint workaround:
    graph pages carry Blueprint-local page-shell CSS/runtime behavior to escape
    the normal `.content-wrapper` / `main section` max-width assumptions
  - desired upstream behavior:
    a page-level or section-level opt-in that widens the content frame while
    preserving the shared Manual shell and ToC semantics
  - removable Blueprint code:
    graph-specific page-shell overrides that are not about graph layout itself

## Runtime Assets and Browser Rendering

- [ ] Add a Verso Slides `Block.ofHtml` constructor.
  - current Blueprint workaround:
    `VersoBlueprint.Slides.slidesMainWithBlueprintRenderer` supplies a local
    `GenreHtml Slides IO` instance so `{blueprint_node}` blocks render from the
    Blueprint preview manifest before the HTML document is serialized; because
    `VersoSlides.slidesMain` owns both rendering and file emission, Blueprint
    also mirrors the small config-asset plan and write loop
  - desired upstream behavior:
    downstream packages should be able to elaborate a slide block to an
    already-rendered HTML body, while reusing the upstream `slidesMain` asset
    validation and output writer
  - removable Blueprint code:
    local `SlideAssetPayload`, `recordSlideAsset`, `collectSlideAssets`, and
    the copied `slidesMain` output loop in `VersoBlueprint.Slides`

- [ ] Decide whether page-level KaTeX preludes belong in core `verso`.
  - current Blueprint workaround:
    Blueprint owns page-level math assets and prelude injection for Blueprint
    math surfaces
  - desired upstream behavior:
    either a generic Manual hook for page-level math preludes or an explicit
    decision that downstream packages should continue owning this layer

- [ ] Upstream the `Verso.Code.Highlighted` docstring rerender performance fix.
  - current Blueprint workaround:
    `PreviewManifest.patchHighlightedDocstringStartupJs` rewrites generated
    highlighted-code JavaScript to read docstring source via `textContent`
  - desired upstream change:
    use `textContent || ""` instead of layout-sensitive `innerText` when
    reading `code.docstring, pre.docstring` before `marked.parse`
  - rationale:
    these nodes contain raw markdown source and often live under hidden
    `.hover-info` containers; `innerText` can be slow and can return empty text
    for hidden payloads
  - observed Blueprint impact:
    the Noperthedron `The-Local-Theorem` reference page dropped from a roughly
    14 second highlighted-code startup task to under 0.5 seconds after the
    local rewrite
  - upstream code points at Verso commit
    `7ae82ac2ae54ae5dcc9948a701669e9b596e5cae`:
    - `src/verso/Verso/Code/Highlighted.lean#L1377-L1384`
    - `src/verso/Verso/Code/Highlighted.lean#L1460-L1467`

- [ ] Upstream the separate `Verso.Code.Highlighted` hover robustness guards.
  - current Blueprint pressure point:
    Blueprint generated pages exercise hidden and dynamically hydrated hover
    payloads more heavily than normal pages
  - desired upstream behavior:
    highlighted-code hover rendering should tolerate missing or delayed DOM
    nodes without downstream packages patching the emitted asset

## Elaboration and Directive APIs

- [ ] Provide an upstream way to resolve package-owned runtime assets during
  elaboration.
  - current Blueprint workaround:
    `MathLint.lean` walks upward from module source or `.olean` locations to
    recover package roots for `static-web/katex-lint.mjs` and Verso's vendored
    KaTeX module
  - desired upstream behavior:
    expose stable package-root/package-asset lookup in the elaboration context,
    or provide a Verso-owned helper entry point that hides vendored asset
    layout from downstream packages
  - local coverage already in place:
    fresh consumer smoke tests cover root checkouts, dependency checkouts, and
    non-default Lake `packagesDir`

- [ ] Support list-valued directive arguments in Verso.
  - current Blueprint workaround:
    `DirectiveArgParsing.splitCommaSeparatedList` splits directive-string
    options such as `(lean := "...")`, `(uses := "...")`, and
    `(tags := "...")` by comma
  - desired upstream behavior:
    directive parsers can accept real list-valued arguments without downstream
    packages inventing ad hoc string splitting

## Lake and Package Management

- [ ] Honor package overrides during `lake update` bootstrap.
  - confirmed locally on Lean `v4.29.0`
  - current limitation:
    `loadWorkspace` passes `packageOverrides` only to `materializeDeps`, while
    `updateManifest` calls `updateAndMaterialize` without threading overrides
  - practical effect:
    `.lake/package-overrides.json` and `lake --packages ... update` do not stop
    an initial upstream clone when a fresh external project has no manifest yet
  - desired behavior:
    `lake update` should apply workspace and CLI package overrides during the
    initial dependency-resolution/materialization path
  - current Blueprint workaround:
    the harness rewrites cloned `lakefile.lean` dependencies before running
    `lake update`

## Manual Content Cleanup

- [ ] Revisit bibliography formatting in `VersoManual/Bibliography.lean`.
  - current Blueprint question:
    decide whether the local bibliography formatting cleanup belongs upstream
    or should remain Blueprint-specific
  - desired outcome:
    either upstream a general formatting improvement or document why Blueprint
    should keep a local presentation layer
