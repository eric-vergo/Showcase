# Blueprint Roadmap

Last updated: 2026-04-10

This document tracks active cleanup and follow-up work for Blueprint support in
this repository.

It is not the place for:

- operational commands and workflow details
- option and rendering reference material
- architecture explanation

Those live in
[`MAINTAINER_GUIDE.md`](./MAINTAINER_GUIDE.md),
[`MANUAL.md`](./MANUAL.md), and
[`DESIGN_RATIONALE.md`](./DESIGN_RATIONALE.md).

## Guiding Constraints

The current cleanup work should preserve these constraints:

1. keep one semantic source of truth for Blueprint data and status derivation
2. keep command, traversal, and runtime paths aligned through shared library
   APIs
3. add regression coverage before large structural splits
4. keep the public maintainer harness small, explicit, and repository-local

## Active Workstreams

### Embedded Asset Dependency Hygiene

Goal: make JS/CSS asset edits rebuild predictably instead of depending on
adjacent Lean source edits to refresh embedded `include_str` payloads.

Work:

1. replace the current fragile direct `include_str` embedding path for browser
   assets with an explicit generated-or-staged Lean dependency edge
2. apply the same fix across graph, summary, bibliography, and shared static
   web assets instead of solving it one module at a time
3. add one regression or build-level check that fails if emitted browser assets
   drift from the source files they are supposed to embed

Priority:

1. treat this as high priority, because stale embedded assets make simple UI
   fixes look much more complex than they really are
2. prefer landing this cleanup before deeper browser-runtime refactors
   accumulate on top of the current embedding model

### Elaboration-Time Asset Resolution

Goal: stop elaboration-time helper tools from depending on ad hoc package-path
guessing across root checkouts, linked worktrees, and consumer dependency
layouts.

Work:

1. replace the current Blueprint math-lint path heuristics with one Lean-side
   resolver that computes the exact asset paths before spawning `node`
2. pass explicit helper-script and KaTeX-library paths into the Node checker
   instead of hard-coding `.lake/packages/...` assumptions inside JS modules
3. add regression coverage for at least:
   root checkout, linked worktree, consumer dependency checkout, and a
   non-default Lake `packagesDir` layout
4. audit whether other elaboration-time helpers rely on similar search-path or
   package-name assumptions and consolidate them behind the same resolver

### Duplicate Identity Hardening

Goal: make duplicate Blueprint identities fail clearly instead of being accepted
locally or silently overwritten during imported-state aggregation.

Work:

1. reject invalid nested and duplicate block declarations before they mutate the
   active environment stack
2. make `Data.register` and block elaboration agree on whether a declaration was
   accepted, ignored, or rejected
3. detect imported collisions in
   `Informal.Environment.informalExt.addImportedFn` instead of silently letting
   later inserts overwrite earlier ones
4. apply the same collision policy to node labels, group labels, and author ids

Tests still needed:

1. same-module duplicate label cases in `Tests.BlueprintInformal`
2. nested invalid block cases in `Tests.BlueprintInformal`
3. cross-module duplicate labels via sibling providers plus one importing test
   module
4. cross-module duplicate groups and duplicate authors via the same pattern
5. transitive-import coverage so reexports cannot bypass collision detection

### Shared Status Semantics

Goal: remove the remaining duplicated status recomputation.

Work:

1. define a shared status record derived from `Data.Node` plus external
   declaration checks
2. route graph, summary, and local block status badges through that record
3. keep the compact UI vocabulary stable while centralizing the semantics behind
   it

### Preview API Consolidation

Goal: keep `PreviewSource` as the only retrieval abstraction visible to callers.

Work:

1. audit call sites for direct preview decoding
2. replace ad hoc decoding with shared APIs
3. keep traversal and widget adapters separate internally, but behind the same
   interface
4. consolidate widget preview cache (`elabStx`) and traversal preview cache
   (`PreviewCache.Entry`) behind one phase-safe representation
5. unify preview labels and titles behind one canonical API so graph, summary,
   and other surfaces stop mixing resolved titles, raw labels, and local
   fallbacks
6. reduce duplicated preview-domain decode logic across renderers
7. unify preview UI behavior across graph panels and summary hovers where that
   can be done without overcoupling the renderers
8. remove temporary runtime workarounds such as the graph preview handler
   `setTimeout` fallback once the underlying lifecycle is verified stable
9. evaluate a lighter browser preview-delivery path so clients do not always
   fetch and decode the full shared preview manifest when they only need a
   small number of entries

### Validation Hardening

Goal: expand the regression surface before deeper refactors.

Work:

1. add targeted regression coverage for graph previews, summary previews,
   bibliography citations/backrefs, and widget statement preview rendering
2. keep generating reference blueprint sites after boundary changes
3. prefer behavior-preserving refactors until the regression surface is broader
4. add direct regression coverage for preview-cache keying and JSON roundtrips

### Harness and External Project Support

Goal: keep the maintainer harness direct and repository-local while expanding it
carefully beyond the current baseline external reference blueprints.

Work:

1. keep the current shell wrappers thin and ergonomic
2. keep the Python harness as the single source of truth for orchestration,
   path logic, and project catalog loading
3. keep the project catalog explicit and small, with baseline external
   reference blueprints plus opt-in ephemeral GitHub checkout coverage
4. validate both root-checkout and linked-worktree flows end to end
5. stabilize output-path conventions for generation, static checks, and browser
   checks
6. add low-cost Python unit coverage for harness manifest and path logic so
   every harness change does not require a full example rebuild
7. add the minimum path and dependency override surface needed for testing a
   local `verso` checkout
8. add the minimum project override surface needed for Blueprint projects that
   live outside this repository
9. upstream a Lake improvement so updating one overridden dependency does not
   rewrite unrelated pinned transitive dependencies or require harness-side
   manifest cleanup to keep `verso` and `subverso` aligned with tracked
   reference manifests
10. add PR preview deployment that reuses the assembled reference `_site`
    artifact from CI instead of rebuilding the sites through a separate
    preview-only workflow

### Template Delivery and Client CI

Goal: provide a user-facing starter that can build and deploy a Blueprint site
to GitHub Pages, while keeping documentation and regression coverage anchored in
this repository.

Work:

1. keep a local in-repo template/example as the documentation-facing source of
   truth for project shape, authoring patterns, and generator wiring
2. add a root-level `.github/workflows/` Pages workflow plus one local CI
   script to the in-repo template so the user-facing contract is explicit and
   testable
3. add main-repository CI coverage that materializes the local template as a
   fresh standalone repository and runs that template-owned CI script end to
   end
4. keep the maintainer harness out of the user-facing template CI contract; the
   harness should validate or materialize templates, not be required by client
   repositories
5. evaluate whether to publish a separate external template repository as a
   generated or synchronized output of the local template source of truth,
   rather than maintaining two hand-edited templates
6. avoid Git submodules for template delivery unless a concrete synchronization
   problem remains unsolved by one-way export or sync automation
7. evaluate a dedicated `verso-blueprint` GitHub Action for the stable
   build-and-deploy path once the template workflow contract has settled
8. keep local smoke coverage and one real GitHub-hosted canary deployment
   separate, so routine PR validation does not depend on cross-repository Pages
   deployment

## UI Follow-Ups

These are secondary to semantic consolidation, but still worthwhile:

The default summary page now leads with overview, blockers, and next ready
work. The next summary follow-ups are about separating audiences rather than
adding more material to that default surface.

1. split `blueprint_summary` into a user-facing overview/work-queue page and a
   separate maintainer-oriented audit/dashboard page
2. keep the overview page focused on overall progress, current blockers, and
   next ready work items
3. move metadata audit, owner/tag rollups, dependency insights, and
   debt/structure analysis to the maintainer page so the default summary stays
   small on large projects
4. further reduce repeated list content after that split, so one primary list
   answers each question by default
5. use compact status chips where possible
6. consider a compact-mode toggle once the semantics are stable
7. revisit the graph page with a CSS-first layout architecture so canvas sizing
   is less runtime-driven
8. remove the graph-local TOC hide toggle and upstream any needed page-shell
   TOC/layout behavior to `verso` instead of carrying Blueprint-specific CSS
   and runtime hooks for it

## Open Bugs

No currently pinned graph-runtime bugs. Keep
`tests/browser/test_graph_layout_runtime.py` visible as the regression surface
for graph page behavior.

## Risks to Watch

1. silent divergence between local and global status rendering
2. preview regressions that compile-only checks will not catch
3. imported duplicate collisions for labels, groups, or authors
4. workflow drift across long-lived worktrees and branches
5. tracked local-worktree bookkeeping leaking into the public repository surface
6. drift between the local documented template, any exported external template,
   and the eventual GitHub Action contract
