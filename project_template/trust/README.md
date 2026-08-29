# `trust/`

Two files live here, and CI writes both. Neither is edited by hand.

- `kernel-identities.json` — the checker identities a comparator run may be authenticated
  against (codex-audit CX-064). The verification workflow bootstraps it on the first run from
  its own verifier pins, and asserts it, never rewriting it, on every run after that. Once it
  is committed, point `verso.blueprint.trust.expectedKernelIdentities` at it in
  `lakefile.lean` (with a matching `input_file` edge) so the site authenticates the identities
  a verdict records instead of rendering them as unauthenticated labels.
- `site-build.json` — the pin naming the release asset GitHub Pages serves: the revision the
  site was generated from, the release tag and asset, its SHA-256, the resolved dependency
  revisions, and which commit of the reusable workflow produced it. `deploy.yml` verifies the
  digest before a byte of the asset is unpacked, so what is served is what a run generated.

Both are committed back by `github-actions[bot]`. A change to either is what a reviewer reads
to see that a verdict, or a deployment, moved.
