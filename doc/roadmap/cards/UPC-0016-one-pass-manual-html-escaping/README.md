# UPC-0016 One-Pass HTML Escaping

Status: open
Kind: performance
Priority: high
Origin: upstream-verso
Last reviewed: 2026-08-09
Owner: none
Issue: none linked
PR: none linked
Upstream timing: as soon as possible
Removal target: none; this is a direct optimization of Verso's HTML serializer
Related cards: UPC-0015, UPC-0017

## Summary

Verso's HTML serializer should escape text and attribute strings with one
Unicode-character fold that pushes ordinary characters and the required entity
characters directly into an owned output string. This preserves existing bytes
while avoiding successive whole-string `String.replace` passes and their
intermediate copies.

## Impact

In the corrected current FLT comparison, one-pass escaping reduced median full
native-generator wall time from 3.046s to 2.770s (-9.05%). Median instructions
fell 17.95% and cycles fell 13.87%. The specialized HTML replacement worker was
4.65% self cycles before the change and absent afterward; the two replacement
loops were replaced by escaping loops totaling 0.65% self cycles.

Carleson's external-declaration renderer supplies an independent large-input
reason to land and remeasure this generic change. In a heavily contended but
internally partitioned run, its compact and hover `Html.asString` calls took
24.22s, or 87.5% of the renderer's non-signature HTML/output work. A lower-load
run had the same broad shape, so current Carleson owner-module validation should
accompany the FLT result without treating the contended absolute time as a
baseline.

## Roadmap Decision

Migrate the retained candidate into a clean upstream Verso worktree, retain the
existing focused Unicode guards, and expand them to cover ASCII, no-escape,
adjacent-escape, and multiple-escape cases. Rerun the complete native FLT
generator and the Carleson external-declaration workload against current heads.
Treat byte equivalence and predicted hotspot movement as hard acceptance
requirements; report elapsed time as noisy workstation evidence rather than a
stable threshold.

## Reproduction Status

The accepted comparison used fresh baseline and candidate closures built from
Verso Blueprint `dcffbd49`, FLT wrapper `52032d62`, FLT submodule `d18b5630`,
Verso `755ccbe9`, and Lean `v4.33.0-rc1`. Compilation and Lake orchestration
were excluded; the already-built native generator included startup, traversal,
generation, serialization, and file writes.

An earlier comparison accidentally paired a stale baseline with a rebuilt
candidate and is superseded. The corrected result rebuilt the complete affected
closure on both sides and verified executable identities before measurement.

## Preliminary Analysis

Escaped text currently performs one full replacement for `<` and another for
`>`. Attribute values similarly replace `&` and then `"`. Each pass searches,
slices, joins, and copies strings. The retained candidate implements private
`escapeText` and `escapeAttr` helpers using `String.foldl`. They thread an owned
output through direct `String.push` operations for both ordinary and entity
characters. `Html.asString`, `Html.format`, and attribute serialization all use
the helpers.

Generated C contains direct `lean_string_push` chains in the two loops and no
HTML-specialized replacement-worker call. Unlike an earlier prototype design,
the accepted implementation has no preliminary escape search and rebuilds even
strings that need no escaping; the card must not claim a no-allocation fast
path that the retained source does not implement.

## Scope Boundary

This card owns behavior-preserving text and attribute escaping in
`Verso.Output.Html`. It does not own xref JSON generation (UPC-0015), signature
highlighting (UPC-0017), find/search page generation, or changes to which
characters Verso escapes.

Two broader `Html.asString` rewrites were also measured on the actual Carleson
render trees and rejected. A fragment-array builder took 8.01s and a unique
string accumulator took 7.78s, versus 7.73s for the existing serializer, with
byte-identical output. Those experiments do not weaken the one-pass escaping
candidate: they replace tree serialization, whereas this card removes repeated
replacement passes inside the existing serializer.

## Expected Behavior

- `Html.asString` and `Html.format` preserve existing text-escaping semantics
  and bytes.
- Attribute serialization preserves existing attribute-escaping semantics and
  bytes.
- Each input is traversed once by the escaping helper and does not allocate one
  complete intermediate string per escaped character class.
- Focused ASCII, Unicode, adjacent, multiple, and no-escape cases pass.
- Representative FLT and Carleson output remains equivalent.

## Evidence

The corrected eight-pair wall comparison measured:

| Metric | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Median wall | 3.046s | 2.770s | -9.05% |
| Mean wall | 3.046s | 2.739s | -10.07% |
| Paired median |  |  | -0.326s |

Six of eight pairs favored the candidate, one was effectively tied, and one
favored the baseline. A separate six-pair counter comparison measured:

| Counter median | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Cycles | 7.137B | 6.147B | -13.87% |
| Instructions | 29.731B | 24.395B | -17.95% |
| Branches | 7.633B | 6.320B | -17.21% |
| Branch misses | 15.155M | 13.930M | -8.08% |
| Cache references | 177.807M | 162.864M | -8.40% |
| Cache misses | 13.872M | 14.516M | +4.64% |

The counters were multiplexed at about 83% coverage and scaled by `perf`.
Focused public-API guards, `lake build Tests.Html`, the full Verso `lake test`,
and direct `vbp check` with 586/586 manifest and cache entries all passed.
Baseline and candidate FLT sites were byte-identical except for the live
compiled timestamp. The local experiment record id is
`flt-html-escape-current-002`; its raw `_out/` bundle is not tracked repository
content, so the upstream PR must attach a fresh current-head comparison.

## Current Workaround

No downstream workaround can remove this generic serializer cost. The accepted
prototype and patch are retained only in local profiling state and must be
reconstructed in a clean upstream Verso worktree rather than published from the
reproducibility checkout.
