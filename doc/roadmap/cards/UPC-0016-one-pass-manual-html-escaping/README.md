# UPC-0016 One-Pass Manual HTML Escaping

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
Related cards: UPC-0015

## Summary

Verso's Manual HTML serializer should escape text and attribute strings in one
UTF-8 traversal, preserving the existing output bytes while avoiding
successive whole-string `String.replace` passes and their intermediate copies.

## Impact

Blueprint reference projects emit multi-megabyte pages with many text and
attribute fragments. In an FLT page-rendering sample, the specialized
`String.Slice.replace` worker reached from `Html.asString` was the largest
self-cost at 11.16%, accompanied by slicing, allocation, append, UTF-8
extraction, reference-counting, and `memmove` costs.

The retained one-pass prototype reduced full native-generator instructions by
16.70% and cycles by 15.31%. Its post-change profile removed the original
replacement worker from `Html.asString`; the new escaping loops together
accounted for about 0.47% self cycles.

## Roadmap Decision

Migrate the retained prototype into a clean upstream Verso worktree, add
focused serializer tests, and rerun the complete native FLT generator against
current heads. Treat byte equivalence and predicted hotspot movement as hard
acceptance requirements; report elapsed time as noisy workstation evidence,
not as a stable threshold.

## Reproduction Status

Reproduced with the already-built native FLT Blueprint generator at FLT
revision `e4f1595` and Lean `v4.33.0-rc1`. Verso HTML tests passed, direct
`vbp check` reported 586/586 entries, and generated output was byte-identical
except for the live compiled timestamp.

## Preliminary Analysis

Escaped text currently performs one full replacement for `<` and another for
`>`. Attribute values similarly replace `&` and then `"`. Each pass searches,
slices, joins, and copies strings. The prototype first finds whether an escape
is needed so the common no-escape case returns the original string. When an
escape is present, one raw-position traversal appends untouched chunks and the
required entity strings to an owned output.

Generated C threads the owned output through `lean_string_push` operations and
does not retain the repeated replacement path. The source change is local to
HTML text and attribute escaping, but its tests must cover ASCII, multibyte
UTF-8, adjacent escapes, multiple escapes, and strings needing no escape.

## Scope Boundary

This card owns behavior-preserving text and attribute escaping in
`Verso.Output.Html`. It does not own xref JSON generation (UPC-0015), generic
streaming or builder-based serialization, find/search page generation, or
changes to which characters Verso escapes.

## Expected Behavior

- `Html.asString` and the corresponding formatted-text path preserve existing
  escaping semantics and bytes.
- Strings that need no escaping are returned without rebuilding them.
- Strings that need escaping are scanned once and do not allocate one complete
  intermediate string per escaped character class.
- Existing HTML tests and representative Blueprint output remain equivalent.

## Evidence

The four-pair counter comparison produced:

| Counter | Baseline median | Candidate median | Change |
| --- | ---: | ---: | ---: |
| Instructions | 31.737B | 26.436B | -16.70% |
| Cycles | 7.783B | 6.591B | -15.31% |

The preserved historical experiment record is `flt-html-escape-016`. A
current-head rerun should attach exact repository, binary, input, and raw-run
identities to the upstream PR.

An initial four-pair wall screen moved from 3.161s to 2.648s (-16.2%). A larger
run under heavier host variance moved from 4.525s to 4.305s (-4.9%) and favored
the baseline in three of eight pairs. The counter reduction and sampled
hotspot removal support the mechanism; the exact wall percentage remains
unresolved.

## Current Workaround

No downstream workaround can remove this generic serializer cost. A prototype
is preserved locally in FLT's detached Verso dependency and must be migrated
rather than edited or published from that reproducibility checkout.
