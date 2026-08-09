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

The current post-escaping FLT profile independently found the same remaining
path: `String.posOfImpl` was 7.98% of the complete native generator, split into
two nearly identical temporal bands. Removing the inner xref emission in the
earlier controlled source experiment reduced the symbol from 7.94% to 4.42%;
compact serialization moved the remainder below the 0.20% reporting threshold.

## Roadmap Decision

Prepare one upstream Verso PR with two reviewable commits: first establish one
serialization owner, then switch that owner to compact serialization. Preserve
the separate measurements so each source change remains attributable. Repeat
the complete native-generator comparison on current Verso and Blueprint heads
before using the historical percentages as current release claims.

The original local commit objects are no longer present in the current detached
Verso checkout. Reconstruct the two small source changes from the retained
experiment records and patches in a fresh upstream worktree rather than
assuming the old prototype branch is still available.

## Reproduction Status

The original source comparisons used the already-built native FLT Blueprint
generator at FLT revision `e4f1595` and Lean `v4.33.0-rc1`. The current
attribution used the accepted one-pass escaping candidate at Verso Blueprint
`dcffbd49`, FLT wrapper `52032d62`, FLT submodule `d18b5630`, and Verso
`755ccbe9`. Compilation and Lake orchestration were excluded; startup,
traversal, generation, serialization, and file writes were included. Direct
`vbp check` reported 586/586 entries for the source candidates.

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

The current generated C corroborates the source mechanism: `emitXrefsJson`
calls `Lean.Json.pretty` with width 80, and `emitFindHtml` calls
`emitXrefsJson` again. In a timing-neutral 2.743s profile, the two
`posOfImpl` bands covered 0.6--1.0s and 1.7--2.1s and had matching UTF-8
stepping, `Std.Format` layout, and raw-position-conversion signatures. Mapping
the bands to the outer and inner calls is an inference from source order,
generated C, and the prior controlled changes; the sampled call chain itself
ended at the worker.

## Scope Boundary

This card owns how often the public xref value is serialized and which
semantics-preserving JSON serializer is used. UPC-0001 owns which traversal
domains are public, and UPC-0002 owns downstream lifecycle hooks around Manual
emission. Find-page design, search-index construction, and general streaming
HTML serialization are outside this card.

The separate `-verso-docs.json` pipeline has two serialization owners of its
own. Isolated substitutions of a compact writer at either owner were measured
and rejected: instruction changes were negligible and wall evidence did not
support landing either change. Revisit that format only as a single-owner
design that removes the intermediate write/read/full-rewrite pipeline; it is
not part of this xref patch stack.

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

The local historical experiment record ids are `flt-html-next-017` and
`flt-xref-compact-018`. Their raw `_out/` bundles are not tracked repository
content; this card is the durable quantitative summary. A current-head rerun
must attach exact repository, binary, input, and raw-run identities to the
upstream PR.

The timing-neutral current profile contained 2,844 samples with no loss and
attributed 470,478,209 of approximately 5,894,099,057 sampled user cycles to
`String.posOfImpl`:

| Band from process start | Sampled cycles | Share of `posOfImpl` |
| --- | ---: | ---: |
| 0.6--1.0s | 246.8M | 52.46% |
| 1.7--2.1s | 223.7M | 47.54% |

This attribution is preserved as `flt-posof-current-003`. It supports the
already-queued xref stack and does not justify a separate substring-search
optimization.

The wall-time screens favored both candidates overall but ran under substantial
host variance, so their exact elapsed percentages are not acceptance
thresholds. `xref.json` was byte-identical, the generated site differed only
in its live compiled timestamp and one deferred-script ordering, and a
headless find query resolved successfully.

## Current Workaround

There is no Blueprint-local workaround for the redundant generic work. Local
profiling prototypes demonstrated both source changes, and their evidence is
recoverable even though the original local Git objects are gone. Blueprint's
separate public-domain filtering and find-page rewrite remain owned by
UPC-0001.
