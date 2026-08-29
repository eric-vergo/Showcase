# Trust-evidence fixtures

Two fixtures live here.

## `formalization-declared-sorry.yaml`

A project that is honest about being unfinished, for
`tests/VersoBlueprintTests/TrustConsolidation.lean`'s audit-coverage document. It
declares `sorry_count: 1` for `TrustAuditFixture.declaredSorryFixture` (a theorem in
`tests/TrustAuditFixture.lean`, deliberately under its own module root so the audit
enumerates it and nothing else), and the document sets
`verso.blueprint.trust.requireAuditClean true`.

**The document elaborating is the test.** `AxiomAudit.run` used to record a declaration
as "claimed sorried" only on the *contradiction* path — `sorry_count: 0` against a
`sorryAx` closure — so the honest case fell through to the "dirty but unclaimed" pass
and was reported as undeclared, which under the strict gate is a build error. That made
the gate unusable for exactly the projects most likely to want it. A declared sorry is
now covered; change the fixture's `sorry_count` to `0` and the build fails, which is the
contradiction check still working.

## `comparator-status.json` and friends

A minimal comparator record for `tests/VersoBlueprintTests/TrustEvidence.lean`.

`comparator-status.json` is deliberately shaped to exercise the two rules the
CX-011 / CX-014 audit findings produced:

- **Content binding.** It carries `config_sha256`, `challenge_sha256`, and
  `solution_sha256` over the exact bytes of the three files beside it, so the site
  build's digest check has something to verify. Editing any of those files without
  refreshing its digest is a build error — that is the check working, not a broken
  fixture. Refresh with:

  ```bash
  shasum -a 256 tests/fixtures/trust/{comparator.json,Challenge.lean,Solution.lean}
  ```

- **Chain binding.** It carries `challenge_chain` — the ordered `{path, sha256}` of every
  file the run elaborated — over the same `Challenge.lean` bytes. That is what a statement
  closure is bound to: `statement-closure` hashes the files it reads, and the closure may
  be presented as adjacent to the verdict only when those digests match this list, in this
  order. The digest is the same one as `challenge_sha256`, so the refresh command below
  covers both.

- **Pinned identities.** `kernel-identities.json` is the *consumer* half of the
  identity check (CX-064): it pins the nanoda revision this fixture's workflow would
  have built, and the status record's `nanoda_ref` is authenticated by agreeing with
  it. Drop the pin and the same record renders as an unauthenticated label with
  currency `unknown`, which is the degradation the option is documented to have.

- **Run evidence.** It records `nanoda_ref` but *no* `nanoda_replay`, while
  `comparator.json` sets `enable_nanoda: true`. That is the legacy shape CX-011 is
  about: configuration says a future run will replay, the run record says nothing,
  and the page must therefore make no past-tense second-kernel claim.
