# Workflows

Three workflows, all fork-owned:

- **`ci.yml`** — this repository's own CI (upstream lineage, rewritten here). The only
  workflow that has ever run on the fork.
- **`blueprint-verify.yml`**, **`blueprint-deploy.yml`** — the reusable (`workflow_call`)
  standard a consumer's thin `ci.yml` / `deploy.yml` call by SHA. `project_template/`
  ships the callers a stranger receives; `ci/README.md` documents the contract.

## Deleted upstream workflows (2026-08-29)

`reference-blueprints.yml`, `reference-blueprints-deploy.yml` and
`backport-discipline.yml` came from `leanprover/verso-blueprint` and encoded upstream's
own policies: a reference-blueprint catalog built and deployed from `v*` release
branches, and a `pull_request_target` paired-backport rule. This fork operates neither.
Evidence at deletion: **0 runs each** across the repository's entire 21-run history, and
the fork develops on `blueprint`, not on `v*`. The first two were fork-touched only to
repair them (CX-006, CX-039/040); `backport-discipline.yml` was byte-identical to
upstream v4.33.0. The *scripts* they drove stay tracked and covered by the harness suite.

**On merging from upstream: delete them again.** A merge onto a newer upstream release
branch reintroduces all three, and `ci.yml`'s actionlint file list must stay in step
with this directory.
