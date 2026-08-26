# Trust-evidence fixtures

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

- **Run evidence.** It records `nanoda_ref` but *no* `nanoda_replay`, while
  `comparator.json` sets `enable_nanoda: true`. That is the legacy shape CX-011 is
  about: configuration says a future run will replay, the run record says nothing,
  and the page must therefore make no past-tense second-kernel claim.
