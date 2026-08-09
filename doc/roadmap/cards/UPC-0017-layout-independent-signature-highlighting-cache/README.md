# UPC-0017 Layout-Independent Signature Highlighting Cache

Status: candidate
Kind: performance
Priority: high
Origin: upstream-verso
Last reviewed: 2026-08-09
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: duplicate layout-independent classification during external declaration rendering
Related cards: UPC-0014, UPC-0016, UPC-0018

## Summary

Verso and SubVerso should make the layout-independent facts used while
highlighting declaration signatures reusable between narrow and wide layouts
without changing layout-local token identities, hover targets, or serialized
`Highlighted` data unexpectedly.

## Impact

Carleson's 15,763-line Blueprint owner module contains 214 attached external
declaration references. Snapshot construction took 48.91s, or 33.3% of one
profiled full elaboration, and declaration rendering accounted for 46.24s of
that work. `Verso.Genre.Manual.Signature.forName` alone took 26.10s.

Within signature construction, converting the wide and narrow tagged layouts
to `SubVerso.Highlighting.Highlighted` took 14.10s and 13.80s. Sharing the
existing signature cache made whichever conversion ran second about three
times faster, exposing a controlled 7.3--8.3s opportunity, roughly 5--6% of
the instrumented full-module wall time.

## Roadmap Decision

Discuss the token-identity contract with Verso/SubVerso maintainers before
preparing a production patch. The naive shared-cache prototype is rejected
because cache hits consume fewer fresh names and change serialized local token
identifiers. Promote this card to `open` once the reusable cache contents and
canonical identity boundary are agreed.

## Reproduction Status

Reproduced in the pinned `verso-carleson` reference project at
`CarlesonBlueprint/Chapters/Main.lean`, using Lean `v4.33.0-rc1`. The source
contained 214 declaration references, 212 of them unique, so caching only by
declaration name inside the file would not provide meaningful reuse.

## Preliminary Analysis

`Signature.forName` pretty-prints a declaration, lays it out at narrow and
wide widths, tags both layouts, and converts each tagged value to highlighted
data with a fresh `SubVerso.Highlighting.SigCache`. The cache contains constant
signature and context facts that are useful to both layouts, but it also
affects fresh-name consumption.

In order-controlled experiments, wide-then-narrow took 10.90s and 3.57s;
narrow-then-wide took 12.20s and 3.91s. The second conversion cost 32--33% of
the first regardless of order. Displayed signature text matched for six
representative declarations, but serialized local identifiers changed, for
example from `_uniq.3599` to `_uniq.3597`.

## Scope Boundary

This card owns reuse between the two layouts of one declaration signature.
UPC-0014 owns portable hover-fragment transfer after highlighted rendering.
UPC-0016 owns generic HTML escaping in the later serialization path, and
UPC-0018 owns reuse of Blueprint directive-body elaboration during final
document construction. Persistent cross-run caches, browser startup, and
declaration-name caches across unrelated references are outside this card.

## Expected Behavior

- Constant-signature classification and other layout-independent facts are
  computed once per declaration.
- Narrow and wide rendering retain stable, documented token identities.
- Serialized highlighted data, token links, and hover behavior are covered by
  focused tests before performance acceptance.
- The second layout shows the predicted cost reduction in the representative
  Carleson owner-module workload.

## Evidence

| Cache order | First conversion | Second conversion | Total signature | Full wall |
| --- | ---: | ---: | ---: | ---: |
| Wide, then narrow | 10.90s | 3.57s | 16.12s | 130.06s |
| Narrow, then wide | 12.20s | 3.91s | 17.82s | 137.93s |

Absolute wall time varied substantially with host load; the within-run order
reversal is the useful causal evidence. The naive prototype is not
behavior-preserving and is evidence for co-design, not a landing candidate.
The raw Carleson profiling bundle is maintainer-local and untracked; this table
is its durable summary. A future implementation must publish a fresh
current-head comparison together with serialized-data and browser validation.

## Current Workaround

Blueprint preserves behavior by accepting two independent highlighted
conversions for every rendered external declaration signature. No unsafe cache
sharing is enabled.
