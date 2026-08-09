# UPC-0018 Deferred Manual Block Term Elaboration

Status: candidate
Kind: performance
Priority: high
Origin: upstream-verso
Last reviewed: 2026-08-09
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: duplicate Blueprint directive-body elaboration during final document assembly
Related cards: UPC-0017

## Summary

Blueprint should reuse the elaborated directive-body work already performed for
preview evaluation instead of embedding the same body syntax in a deferred block
term that Lean elaborates again when the document closes. Start with a
Blueprint-local representation prototype; propose a Verso queue contract only
if that prototype demonstrates an upstream boundary.

## Impact

Carleson's 15,763-line owner module queues 1,001 document blocks. In a stable
low-load prefix sequence, `finishDoc` took 12.63s, or 26.0% of the 48.65s full
elaboration, at full size. The deferred block batch accounted for 12.01s, and
elaborating its individual block terms accounted for 11.20s.

Source attribution in a separate full run assigned 81.1% of the term batch to
Blueprint directives. Proof directives alone accounted for 52.2%, and their
time correlated strongly with body size. An intentionally invalid probe that
removed directive bodies only from the final deferred terms saved 7.40s of
directive term elaboration. This is an upper bound for reuse, not an acceptable
implementation.

## Roadmap Decision

Prototype retention of reusable private block definitions or equivalent
elaborated references alongside Blueprint's preview values. The final directive
term should refer to that retained representation instead of re-elaborating its
body syntax. Keep this card `candidate` until the prototype preserves document
reconstruction hygiene, diagnostics and source information, generated output,
and `.olean` reproducibility without an unjustified peak-memory, artifact-size,
or serialization-time regression. Escalate to a Verso API proposal only if the
behavior-preserving prototype requires a general deferred-queue contract.

## Reproduction Status

Reproduced by directly elaborating warm, valid prefixes of
`CarlesonBlueprint/Chapters/Main.lean` in the pinned `verso-carleson` reference
project with Lean `v4.33.0-rc1`. Dependency compilation, native executable
generation, traversal, and HTML rendering were excluded. Prefixes ended only at
complete top-level block boundaries and all elaborated successfully.

## Preliminary Analysis

The 25%, 50%, 75%, and 100% prefixes contained 271, 528, 757, and 1,001
deferred blocks. Full wall time and finalization were both close to linear in
block count. At full size, the deferred batch was 95.1% of `finishDoc`, and
term elaboration was 93.2% of that batch.

The duplicated Blueprint path is concrete:

1. A directive expander elaborates its body blocks.
2. Preview evaluation elaborates and evaluates the resulting terms.
3. The evaluated values are retained, but the elaborated expressions are not.
4. The returned document-block syntax embeds the same body terms.
5. Final document assembly elaborates those deferred terms again.

The prefix study rejects the earlier giant-generated-term hypothesis.
`FinishedPart.toSyntax` took at most 2.2ms, reconstruction JSON less than
0.2ms, and the outer generated definition 0.36s at full size. The suspected
quadratic `saveRefsInEnv` path took 49ms cumulatively, about 0.1% of full wall.
Moving deferred elaboration earlier would shorten the visible end-of-file pause
but would not reduce whole-module time.

## Scope Boundary

This card owns reuse of Blueprint directive-body elaboration between preview
evaluation and final document construction, plus any minimal Verso queue
contract proven necessary by that work. UPC-0017 owns external-declaration
signature conversion during incremental directive elaboration. Syntax assembly,
reconstruction JSON, the outer `VersoDoc` definition, `saveRefsInEnv`, math
lint, native generator runtime, and HTML rendering are measured non-targets for
this card.

## Expected Behavior

- Directive bodies are not elaborated twice merely to support preview data and
  final document construction.
- Document reconstruction hygiene, diagnostics, source information, and
  generated output remain equivalent.
- The resulting `.olean` is reproducible and the complete owner module still
  elaborates successfully.
- Peak RSS, `.olean` size, and `.olean` serialization time are compared with the
  same warmed baseline, and any regression is reported and justified.
- Acceptance is based on reduced complete owner-module time, not only moving
  work away from `finishDoc`.
- Any upstream API is the smallest contract demonstrated by the Blueprint
  prototype.

## Evidence

The valid-prefix sequence measured:

| Prefix | Deferred blocks | Full wall | Deferred batch | `finishDoc` | Finish share |
| --- | ---: | ---: | ---: | ---: | ---: |
| 25% | 271 | 13.16s | 2.576s | 2.709s | 20.6% |
| 50% | 528 | 23.56s | 5.179s | 5.432s | 23.1% |
| 75% | 757 | 35.29s | 7.775s | 8.169s | 23.1% |
| 100% | 1,001 | 48.65s | 12.012s | 12.628s | 26.0% |

The separate source-attribution run partitioned deferred term elaboration:

| Source block | Count | Term elaboration | Batch share |
| --- | ---: | ---: | ---: |
| `proof` directive | 159 | 7.217s | 52.2% |
| `lemma_` directive | 149 | 3.515s | 25.4% |
| Ordinary paragraph | 180 | 1.894s | 13.7% |
| TeX provenance block | 502 | 0.713s | 5.2% |
| `theorem` directive | 11 | 0.474s | 3.4% |

Absolute workstation wall times varied with host load. The useful evidence is
the within-run phase partition, valid-prefix curve, source distribution, and
controlled body-elision delta rather than a cross-run elapsed-time comparison.
The raw Carleson profiling bundle and exploratory report are maintainer-local
and untracked; the tables above are the durable summary. A behavior-preserving
prototype must publish a fresh current-head comparison, including its memory
and `.olean` artifact tradeoffs.

## Current Workaround

There is no behavior-preserving workaround. Blueprint retains the evaluated
preview values but not reusable elaborated body references, so the final
document term pays the second elaboration on every owner-module rebuild.
