# UPC-0015 Single-Owner Compact Xref Emission

Status: open
Kind: performance
Priority: high
Origin: upstream-verso
Last reviewed: 2026-08-09
Owner: none
Issue: none linked
PR: none linked
Upstream timing: as soon as possible
Removal target: none; this is a direct correction to Verso Manual HTML emission
Related cards: UPC-0001, UPC-0002, UPC-0016

## Summary

Verso Manual HTML should construct, serialize, and write each output mode's
`xref.json` once. The find-page emitter should consume the already-serialized
payload supplied by its caller, and the single serialization owner should use
`Lean.Json.compress` instead of the generic pretty printer.

## Impact

Large manuals pay for the same public xref object more than once during normal
HTML generation. The duplicate path rebuilds and rewrites `xref.json` after
the outer dispatcher has already emitted it, while `toString` constructs and
lays out a `Std.Format` tree even when the result is completely flat.

On the measured FLT generator, the xref payload was 316,430 bytes. Removing the
duplicate work reduced full-generator instructions by 15.80% and cycles by
16.35%. Compact serialization then reduced instructions by a further 16.33%
and cycles by 13.37% in a separate comparison.

## Roadmap Decision

Prepare one upstream Verso PR with two reviewable commits: first establish one
serialization owner, then switch that owner to compact serialization. Preserve
the separate measurements so each source change remains attributable. Repeat
the complete native-generator comparison on current Verso and Blueprint heads
before using the historical percentages as current release claims.

## Reproduction Status

Reproduced with the already-built native FLT Blueprint generator at FLT
revision `e4f1595` and Lean `v4.33.0-rc1`. Compilation and Lake orchestration
were excluded; startup, traversal, generation, serialization, and file writes
were included. Direct `vbp check` reported 586/586 entries for both candidates.

## Preliminary Analysis

The outer Manual `emitHtml` dispatcher calls `emitXrefsJson` before immediate
HTML emission and before saving delayed state. The single-page and multi-page
emitters then read that file and pass its contents to `emitFindHtml`, but
`emitFindHtml` calls `emitXrefsJson` again before using the supplied string.

Removing the inner call also preserves delayed and resumed rendering: delayed
generation writes the file before saving state, while resumed generation must
successfully read the file before it can render the find page. The remaining
serializer currently uses `toString`; `Json.compress` produced the same bytes
for the measured FLT value without building or laying out a format tree.

## Scope Boundary

This card owns how often the public xref value is serialized and which
semantics-preserving JSON serializer is used. UPC-0001 owns which traversal
domains are public, and UPC-0002 owns downstream lifecycle hooks around Manual
emission. Find-page design, search-index construction, and general streaming
HTML serialization are outside this card.

## Expected Behavior

- Each single-page or multi-page output mode has one `xref.json` construction,
  serialization, and write owner.
- The find page embeds the same serialized value that was written to disk.
- Immediate, delayed, and resumed generation remain valid.
- Parsed xref data and generated find behavior remain unchanged.

## Evidence

Two order-balanced counter comparisons measured the changes independently:

| Change | Control instructions | Candidate instructions | Change | Control cycles | Candidate cycles | Change |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Remove duplicate emission | 26.433B | 22.258B | -15.80% | 6.827B | 5.711B | -16.35% |
| Use compact serialization | 22.257B | 18.623B | -16.33% | 5.674B | 4.916B | -13.37% |

The preserved historical experiment records are `flt-html-next-017` and
`flt-xref-compact-018`. A current-head rerun should attach exact repository,
binary, input, and raw-run identities to the upstream PR.

The wall-time screens favored both candidates overall but ran under substantial
host variance, so their exact elapsed percentages are not acceptance
thresholds. `xref.json` was byte-identical, the generated site differed only
in its live compiled timestamp and one deferred-script ordering, and a
headless find query resolved successfully.

## Current Workaround

There is no Blueprint-local workaround for the redundant generic work. Local
profiling prototypes demonstrated both source changes. Blueprint's separate
public-domain filtering and find-page rewrite remain owned by UPC-0001.
