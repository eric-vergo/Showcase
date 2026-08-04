# UPC-0005 Verso Slides Extra Head

Status: resolved
Kind: upstream-api
Priority: medium
Origin: upstream-verso-slides
Last reviewed: 2026-07-16
Owner: none
Issue: none linked
PR: https://github.com/leanprover/verso-slides/pull/59
Upstream timing: none
Removal target: none; the post-RC commit pin has been removed
Related cards: UPC-0004, UPC-0006

## Summary

Verso Slides needed module-script/head injection support so Blueprint slide decks
could load normal ESM preview runtime files.

## Impact

Without Slides `extraHead`, Blueprint had to carry a de-ESMified slide runtime
path. With upstream support, slide decks can use the same ESM preview runtime
shape as normal Blueprint pages.

## Roadmap Decision

Resolved. Matching `verso-slides` release tags from v4.32.0 onward include
`Config.extraHead`, and Blueprint follows the active Lean release line's normal
Slides pin.

## Reproduction Status

Covered by Blueprint slide-deck generation and browser validation.

## Preliminary Analysis

The needed API was an upstream Slides `Config.extraHead` hook. That hook lets
Blueprint inject the slide-specific ESM entrypoint without changing the Slides
writer.

## Scope Boundary

This card covered only head injection. Structured asset declaration remains
UPC-0004, while reuse of the upstream Slides traversal/render/output pipeline
remains UPC-0006.

## Expected Behavior

Blueprint slide decks write normal preview ESM support files, load a
slide-specific runtime entrypoint, pass the preview renderer explicitly to slide
hydration, and avoid a de-ESMified `blueprint-slides.js` bundle.

## Evidence

- Upstream PR: https://github.com/leanprover/verso-slides/pull/59
- Upstream status: `Config.extraHead` is present in matching `verso-slides`
  release tags from v4.32.0 onward.
- Local release pin: `lakefile.lean` follows the checkout's active release line.

## Current Workaround

None. Blueprint loads the slide runtime through `Config.extraHead` from the
normal matching `verso-slides` release.
