# UPC-0018 Large Manual Document Assembly Scaling

Status: candidate
Kind: performance
Priority: high
Origin: upstream-verso
Last reviewed: 2026-08-09
Owner: none
Issue: none linked
PR: none linked
Upstream timing: none
Removal target: none until the responsible document-representation boundary is identified
Related cards: UPC-0017

## Summary

Verso should scale predictably when finalizing a very large `#doc`. Before
proposing an API or representation change, split and measure syntax assembly,
reconstruction-data construction, and elaboration of the generated
`VersoDoc` definition across valid document prefixes.

## Impact

Carleson's 15,763-line, 732,292-byte owner module spends roughly one quarter of
its full elaboration wall time in final document assembly, independently of
the per-directive external-declaration rendering tracked by UPC-0017. The
resulting `.olean` is about 41 MiB, and measured peak RSS was approximately
5.2 GiB.

One structured profile attributed 67.69s, or 27.9% of full wall, to the final
`addLastBlockCmd` path. A less contended nested run measured 36.20s, or 24.7%
of full wall. The stable result is the phase share, not either absolute time.

## Roadmap Decision

Treat this as a joint attribution task rather than an implementation request.
Build valid 25%, 50%, 75%, and 100% document prefixes; split
`FinishedPart.toVersoDoc` into its major operations; and determine whether the
cost is linear construction with a large constant or a pathological generated
term shape. Promote the card to `open` only after the responsible upstream
boundary and expected replacement are concrete.

## Reproduction Status

Reproduced by directly elaborating the warm owner module
`CarlesonBlueprint/Chapters/Main.lean` in the pinned `verso-carleson` reference
project with Lean `v4.33.0-rc1`. Dependency compilation, native executable
generation, traversal, and HTML rendering were excluded.

## Preliminary Analysis

Of the 67.69s final-assembly phase in the structured trace, 42.82s was
application-argument elaboration, 10.13s application-term elaboration, and
7.01s `let` elaboration. Together these deeply nested term operations account
for 88.6% of the phase. This is consistent with constructing and elaborating
one large generated `VersoDoc` definition, but does not yet establish the
asymptotic behavior.

Verso's incremental block path also contains a source note that
`saveRefsInEnv` pushes info leaves a quadratic number of times. The current
trace does not isolate that function. The prefix experiment should time it,
but the card must not present it as the established owner without that
evidence.

## Scope Boundary

This card owns final assembly of the accumulated Manual document. UPC-0017
owns external-declaration signature conversion during incremental directive
elaboration. Math lint, imported dependency compilation, native generator
runtime, and generic Lean compiler work are outside this card unless the
prefix study attributes the phase to them.

## Expected Behavior

- Valid document-prefix fixtures establish the observed scaling curve.
- Timers partition syntax assembly, reconstruction JSON, generated-definition
  elaboration, and any measured reference-info propagation without overlap.
- The upstream discussion identifies whether the correction belongs in Verso's
  document representation, its elaborator, or Lean's handling of the generated
  term shape.
- Any candidate is accepted against the complete owner-module elaboration, not
  only a synthetic term.

## Evidence

| Profile | Final assembly | Full-wall share | Dominant nested operations |
| --- | ---: | ---: | --- |
| Structured full-wall trace | 67.69s | 27.9% | application arguments, applications, and `let` elaboration |
| Nested directive/render trace | 36.20s | 24.7% | final `elabVersoLastBlock` document assembly |

Math lint took about 4.0s, or 2.4% of a representative source-aware run, and
is not the main explanation. Individual directive time did not worsen with
source position, so the final accumulated term remains a separate scaling
question.

## Current Workaround

There is no local workaround. Carleson elaborates the complete generated
document term and pays the final-assembly cost on every owner-module rebuild.
