# `ci/` — the shared CI standard for blueprint consumers

One verification pipeline, one deploy path, one copy of every gate. A consumer's
own workflows are ~30-line callers; everything they run lives here.

```
.github/workflows/blueprint-verify.yml   on: workflow_call   build → comparator → publish → site-contents → site-generate → site-release
.github/workflows/blueprint-deploy.yml   on: workflow_call   verify (digest-pinned release asset) → deploy (Pages)
ci/scripts/                              the shared gates and composers, materialised on the runner
ci/scripts/tests/                        their fixtures, run in seconds in the trusted build job
```

This replaced four hand-copied designs (a362583's 1,437-line `ci.yml`, hopf's
1,679-line near-clone, lean_quine's bespoke 79 lines, and a dead `workflow_call`
design in `project_template`). What the audit rounds bought — CX-012's trust
boundary, CX-048/049/050/051's containment chain, CX-052's record validator,
CX-064's checker-identity pin, CX-066's source-link gate, CX-075/078's
provenance gate, CX-079's single deploy predicate — now exists once, and
`tests/harness/test_blueprint_verify_topology.py` holds the workflows to it on
every push to this repository.

---

## 1. How a consumer adopts it

Two files, both pinned to the SAME Showcase commit the consumer pins for its Lake
`require VersoBlueprint` — one number to bump.

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
    paths-ignore:
      # The workflow's own commit-backs must not re-trigger it. A GITHUB_TOKEN
      # push does not fire `push:` anyway; this is the second guard.
      - 'comparator/comparator-status.json'
      - 'site/trust/kernel-identities.json'
      - 'site/trust/site-build.json'
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

# Never cancel: a cancelled run can interrupt a commit-back or a release upload.
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: false

jobs:
  blueprint:
    permissions:
      contents: write   # the status / kernel-identity / site-pin commit-backs
      actions: read     # the step-level CI deep link
    uses: eric-vergo/Showcase/.github/workflows/blueprint-verify.yml@<SHOWCASE_SHA>
    with:
      showcase_sha: "<SHOWCASE_SHA>"   # asserted == job.workflow_sha in every job
      publish_branch: main
      subject_build_target: A362583
      subject_olean_probe: .lake/build/lib/lean/A362583
      stale_olean_guard: Challenge Solution SolutionProbe
      build_check_script: scripts/check_shared_definitions.sh
      prose_pin_files: README.md formalization.yaml site/Chapters/*.lean
      comparator_tool_mode: checkout
      site_prebuild_command: lake build VersoBlueprint/statement-closure
      required_site_files: >-
        index.html -verso-data/blueprint-manifest.json -verso-data/decl-registry.json
        -verso-data/trust-provenance.json comparator/index.html Trust-model/index.html
```

### `.github/workflows/deploy.yml`

```yaml
name: Deploy

on:
  push:
    branches: [main]
    # Only the pin. A change to the workflow or its scripts without a new pin is
    # re-verified by hand, not by a run that would refuse an unchanged release.
    paths:
      - 'site/trust/site-build.json'
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: site-deploy
  cancel-in-progress: false

jobs:
  deploy:
    permissions:
      contents: read
      pages: write
      id-token: write
    uses: eric-vergo/Showcase/.github/workflows/blueprint-deploy.yml@<SHOWCASE_SHA>
    with:
      showcase_sha: "<SHOWCASE_SHA>"
      publish_branch: main
      required_site_files: >-
        index.html -verso-data/blueprint-manifest.json -verso-data/decl-registry.json
        -verso-data/trust-provenance.json comparator/index.html Trust-model/index.html
```

Note what `ci.yml` does **not** hold: no `pages:` scope and no `id-token:`. The
workflow that can write to the repository and the workflow that can mint a Pages
token are different files, called by different jobs.

**Never write `secrets: inherit`.** The pipeline needs no secret, and omitting
the block is what keeps the untrusted comparator job provably secret-free.

### What must be on disk

**Always** — `lean-toolchain`; a **committed `lake-manifest.json`** in every
directory that has a lakefile; a site package under `site_dir` whose generator
writes `site_out`.

The manifest requirement is not bookkeeping. A lakefile pins the packages its
author named; everything transitive floats. An uncommitted manifest means CI
resolves a different dependency graph than the workstation did, and the manifest
is also a cache-key input. The build job refuses to continue without it.

**When `comparator_enabled`** — `comparator_config` and `comparator_probe_config`
(the probe config differs only in `solution_module`); `comparator_challenge`;
`comparator_solution`; a `SolutionProbe` module registered as a Lake lib but
**not** a default target and imported by nothing; `kernel_identity_pins`
(bootstrapped on the first run, asserted thereafter). In `lake-dep` mode, a
`require Comparator` whose manifest `rev` is the pinned commit.

**When `trust_provenance_gate`** — `site_lakefile` must set all four
`verso.blueprint.trust.{comparatorStatus,comparatorConfig,challengeFile,solutionFile}`
options **and** carry an `input_file` edge per option in `needs`. The gate reads
both out of the lakefile and reports either as a violation; an option without its
edge is a warm-replay window (CX-075).

**`formalization.yaml` is optional** — `formalization_yaml: ""` skips the schema
check.

---

## 2. Input reference

Toggles are declared **capabilities**, never inferred from file presence: a gate
that silently skips because a file is missing is the probe-and-degrade weakness
the audit rejected, and when a gate is on, a vacuous result is a failure.

| Input | Type | Default |
|---|---|---|
| `publish_branch` | string | `main` |
| `showcase_sha` | string | `""` (unset skips the assertion) |
| `mathlib` | boolean | `true` |
| `subject_build_target` | string | **required** |
| `subject_olean_probe` | string | **required** |
| `stale_olean_guard` | string | `""` |
| `build_check_script` | string | `""` |
| `extra_build_env` | string | `""` (newline-separated `KEY=VALUE`) |
| `prose_pin_files` | string | `README.md` |
| `formalization_yaml` | string | `formalization.yaml` |
| `comparator_enabled` | boolean | `true` |
| `comparator_tool_mode` | string | `lake-dep` (or `checkout`) |
| `comparator_config` | string | `comparator/comparator.json` |
| `comparator_probe_config` | string | `comparator/comparator-probe.json` |
| `comparator_challenge` | string | `comparator/Challenge.lean` |
| `comparator_solution` | string | `comparator/Solution.lean` |
| `comparator_status` | string | `comparator/comparator-status.json` |
| `kernel_identity_pins` | string | `site/trust/kernel-identities.json` |
| `site_enabled` | boolean | `true` |
| `site_dir` | string | `site` |
| `site_out` | string | `_out/site/html-multi` |
| `site_contents_command` | string | `lake build Contents` |
| `site_generate_command` | string | `lake env lean --run Main.lean --output _out/site` |
| `site_prebuild_command` | string | `""` |
| `site_pin` | string | `site/trust/site-build.json` |
| `site_lakefile` | string | `site/lakefile.lean` |
| `required_site_files` | string | `index.html -verso-data/blueprint-manifest.json` |
| `min_site_files` | number | `50` |
| `max_site_bytes` | number | `900000000` |
| `source_link_gate` | boolean | `true` |
| `trust_provenance_gate` | boolean | `true` |
| `build_timeout_minutes` | number | `120` |
| `comparator_timeout_minutes` | number | `180` |
| `stage_timeout_minutes` | number | `120` |

Outputs: `verdict`, `site_ref`, `deployable`, `release_tag`, `release_asset`,
`release_sha256`.

`blueprint-deploy.yml` takes `publish_branch`, `showcase_sha`, `site_pin`,
`site_dir`, `site_out` (the tarball's single top-level member, default
`html-multi`), `required_site_files`, `min_site_files`, `max_site_bytes`.

### The verifier pins are NOT inputs

`LANDRUN_REF`, `NANODA_REF`, `NANODA_REPOSITORY`, `COMPARATOR_TOOL_REF`/`_SHA`,
`LEAN4EXPORT_REF`, `FORMALIZATION_SCHEMA_REF`/`_VERSION`,
`CHECK_JSONSCHEMA_VERSION` live in `blueprint-verify.yml`'s own `env:`. The
principled reason, beyond central bumping: in `lake-dep` mode the *effective*
comparator pin is the consumer's `lake-manifest.json`, so the constant's whole
job is to be **asserted against** that manifest. A consumer that could choose the
constant would be asserting it against itself, which checks nothing.

**Verifier currency is a standing invariant.** The nanoda and landrun pins must
postdate the newest Lean kernel fix, and must be re-pinned deliberately whenever a
consumer's toolchain moves.

### Per-consumer values

| | lean_quine | project_template | a362583 | hopf (later) |
|---|---|---|---|---|
| `publish_branch` | `main` | `main` | `main` | `master` |
| `mathlib` | **`false`** | **`false`** | `true` | `true` |
| `subject_build_target` | `Quine Test QuineFacts quine` | `ProjectTemplate` | `A362583` | `HopfProblem` |
| `subject_olean_probe` | `.lake/build/lib/lean/Quine.olean` | `.lake/build/lib/lean/ProjectTemplate.olean` | `.lake/build/lib/lean/A362583` | `.lake/build/lib/lean/HopfProblem` |
| `stale_olean_guard` | `Challenge Solution SolutionProbe` | `Challenge Solution SolutionProbe` | `Challenge Solution SolutionProbe` | same |
| `build_check_script` | `scripts/verify.sh` | — | `scripts/check_shared_definitions.sh` | — |
| `extra_build_env` | `PYTHONINTMAXSTRDIGITS=0` | — | — | — |
| `formalization_yaml` | `formalization.yaml` | `formalization.yaml` | (default) | (default) |
| `comparator_enabled` | `true` | (default) | `true` | `true` |
| `comparator_tool_mode` | `checkout` | `checkout` | `checkout` | `lake-dep` |
| `comparator_config` | (default) | (default) | (default) | `comparator/config.json` |
| `comparator_probe_config` | (default) | (default) | (default) | `comparator/config-probe.json` |
| `comparator_challenge` | (default) | (default) | (default) | `Challenge.lean` |
| `comparator_solution` | (default) | (default) | (default) | `Solution.lean` |
| `kernel_identity_pins` | `trust/kernel-identities.json` | `trust/kernel-identities.json` | (default) | (default) |
| `site_dir` | **`.`** | **`.`** | `site` | `site` |
| `site_lakefile` | `lakefile.lean` | `lakefile.lean` | (default) | (default) |
| `site_contents_command` | `lake build Site` | `lake build ProjectTemplate` | (default) | (default) |
| `site_generate_command` | `rm -rf _out/site && lake env lean GenSite.lean` | `rm -rf _out/site && lake exe vbp build` | (default) | (default) |
| `site_prebuild_command` | — | — | `lake build VersoBlueprint/statement-closure` | same |
| `site_pin` | `trust/site-build.json` | `trust/site-build.json` | (default) | (default) |
| `required_site_files` | read off the first real build | + `-verso-data/trust-provenance.json Dependency-Graph/ Showcase-Summary/ Formalization-Metadata/ Trust-model/ comparator/ pm/` (all `/index.html`) | + `-verso-data/decl-registry.json -verso-data/trust-provenance.json comparator/index.html Trust-model/index.html` | same |
| `min_site_files` | ~60–70 % of the observed count | `120` (of 182 observed) | (default) | (default) |
| `source_link_gate` | `true` | **`false`** (no declaration registry) | `true` | `true` |
| `trust_provenance_gate` | `true` | (default `true`) | `true` | `true` |
| `comparator_timeout_minutes` | `90` on the first nanoda attempt | — | (default) | (default) |
| `stage_timeout_minutes` | (default) | (default) | (default) | `355` |
| `build_timeout_minutes` | (default) | (default) | (default) | `150` |

`required_site_files` must be read off a real build of that consumer, never
copied: page slugs derive from page TITLES, so the summary page has been
`Blueprint-Summary/` in one fork era and `Showcase-Summary/` in another.
Guessing produces a gate that fails for the wrong reason or, worse, a gate on a
path that never existed.

`project_template` ships a complete comparator — a `sorry`-ed challenge, a
solution that proves it, a denied-write probe and both configs — with its status
artifact in the honest **`configured`** state: nothing has run yet, and every
surface says so until the first push rewrites the artifact from a run's evidence
record. That is what makes the starter a working demonstration rather than a
mock-up: a stranger who copies it gets a pipeline whose first run produces a real
verdict.

Its `source_link_gate` is the one gate off, by declaration: that gate reads the
declaration registry, and the starter does not turn on
`verso.blueprint.graph.includeAllDecls`, so there is nothing for it to check and
a vacuous pass would be worse than an honest `false`.

---

## 3. Trust topology

| job | permissions | what runs there |
|---|---|---|
| `build` | `contents: read` | pin assertions, the gate fixtures, formalization.yaml schema, the subject build, the consumer's own check. **Never** Challenge or Solution. |
| `comparator` | `contents: read` | the FIRST elaboration of Challenge and Solution, inside landrun, under the AF_UNIX guard. No write token, no OIDC, no secrets. |
| `publish` | `contents: write`, `actions: read` | validates the record against its own trusted inputs, writes the status and the identity pin, commits back. Computes the deploy predicate ONCE. Runs no Lean. |
| `site-contents` / `site-generate` | `contents: read` | elaboration, rendering, every gate, packaging. |
| `site-release` | `contents: write`, `actions: write` | the release, the pin commit-back, the deploy dispatch. |
| deploy `verify` | `contents: read`, `pages: write` | digest check, then authentication against the checkout, then the artifact upload. |
| deploy `deploy` | `pages: write`, `id-token: write` | `actions/deploy-pages`, in the `github-pages` environment. |

Every job (except the Pages deploy step, which reads nothing from a tree) checks
this repository out at `${{ job.workflow_sha }}` into `_showcase/`, asserts the
caller's `showcase_sha`, and then **stages `ci/` outside the workspace and deletes
`_showcase/`**. That last step is not tidiness: a Showcase checkout inside a
consumer's tree carries a lakefile and Lean sources, so the declaration
registry's source-path scan can take it for a sibling package root, the site
gates would walk it, and `package_site.sh` would call the worktree dirty.

The consumer is checked out **first** and Showcase second, because
`actions/checkout` cleans the directory it targets and a default-path checkout
run afterwards would remove `_showcase/`.

### Where each finding now lives

| finding | property | where |
|---|---|---|
| CX-012 | untrusted Lean never runs in a job with a write token, and never before the sandbox | `blueprint-verify.yml` job split; `stale_olean_guard`; `tests/harness/test_blueprint_verify_topology.py::TrustBoundaryTopologyTests` |
| CX-039 | every referenced script exists | `tests/harness/test_workflow_topology.py::test_reusable_workflows_reference_only_existing_ci_scripts` |
| CX-048 | the AF_UNIX guard is a gate, checked first, recorded, and required by the validator | `blueprint-verify.yml` comparator job, step 3; `validate_comparator_result.py` `--af-unix-guard` |
| CX-049 | Landlock is exercised, with a deterministic loopback network canary | `ci/scripts/landlock_selftest.sh` |
| CX-050 / CX-051 | containment is established BEFORE any repository Lean is elaborated, by workflow-owned bytes with per-run targets, classified from the filesystem | `ci/scripts/sandbox_selftest.sh`; the repository-side probe is kept as defense in depth and labelled as such |
| CX-052 | the record crosses the trust boundary through a strict, exact-key validator whose refusals are themselves tested | `ci/scripts/validate_comparator_result.py`; `ci/scripts/tests/test_validate_comparator_result.py` |
| CX-053 | the comparator tool is built on the toolchain whose kernel replays the export | `lake-dep` by construction; `checkout` by the toolchain-override step; asserted again in `publish` |
| CX-064 | the run's checker identity is authenticated against a consumer-committed pin, asserted and never rewritten | `Check the pinned checker identities`; `kernel_identity_pins` |
| CX-066 | every project-local source link names the revision the site was generated from | the `Gates` step's source-link gate; again at deploy in `check_site_release.py` |
| CX-068 | the published status names WHICH project revision was checked | `ci/scripts/compose_status_record.sh` (`repository`, `commit`) |
| CX-072 | a job that calls `lake` installs a toolchain | `publish` runs no Lean at all; the site jobs each set Lean up |
| CX-075 | elaboration-time trust inputs are re-hashed against the checkout | `ci/scripts/check_trust_provenance.py`; again at deploy |
| CX-078 | the provenance record is authenticated, not merely re-hashed as the producer listed it | same, plus its forged fixtures |
| CX-079 | the deploy predicate has ONE source | `publish.outputs.deployable`, read by the gate and by `site-release.if`; `DeployPredicateTests` |

### CX-079 is strengthened, not dropped

a362583 asserted, in a Python test, that the `DEPLOYABLE:` env value and
`deploy.if` were textually the same expression — because a job-level `if:` cannot
read the `env` context, so the predicate could not be shared by reference. Under
a reusable workflow it can: `needs` **is** available in `jobs.<id>.if`, so the
predicate is computed once in `publish` and exported as a job output that both
readers dereference. The text assertion is gone because the two spellings it held
together are gone. What replaces it asserts the stronger property: exactly one
`DEPLOYABLE:` declaration exists, its value is the publish job's output, and no
reader recomputes the predicate from the event name.

---

## 4. The scripts

| script | what it decides | tested by |
|---|---|---|
| `landlock_selftest.sh` | Landlock is really confining; a TCP connect is really denied | exercised on every comparator run; both branches are hard failures |
| `sandbox_selftest.sh` | writes from inside the sandbox are denied, with an unsandboxed positive control | same |
| `hash_inputs.sh` | the four executables and three certified sources, hashed identically either side of the run | the validator requires before == after per key |
| `compose_result_record.sh` | the single evidence record | its output is the validator's input |
| `compose_status_record.sh` | what the site quotes | `comparator_status_unchanged.sh` decides whether it is written |
| `validate_comparator_result.py` | what may become a dated verifier claim | `tests/test_validate_comparator_result.py` (19 cases) |
| `comparator_status_unchanged.sh` | whether a run has anything new to say | `tests/test_comparator_status_unchanged.sh` (23 cases) |
| `check_trust_provenance.py` | whether a generated evidence page is bound to bytes that are still there | `tests/test_trust_provenance_gate.py` (26 cases) |
| `check_site_release.py` | whether a packaged site may be served | `tests/test_check_site_release.py` (12 cases) |
| `site_offline_gates.sh` | eight off-origin asset rules | run identically at packaging and at deploy |
| `package_site.sh` | the tarball, the pin, the size report — and refuses anything the deploy gate would refuse |  `check_site_release.py` is run on its own output |

Run them all: `python3 -m unittest discover -s ci/scripts/tests` (58 tests).

Three notes on what changed when these became shared:

* **`permitted_axioms: []` is accepted.** An empty allowlist is a *stronger*
  claim than the standard three — the certified theorem reaches no axiom at all —
  and lean_quine makes it. Both the composer and the validator previously
  rejected it as if the key were missing. They now distinguish absent from empty:
  the key must be present in the checked-out config, be a list, and equal the
  record's. `theorem_names` stays non-empty; a run that certifies nothing is not
  a verdict.
* **The record carries `workflow_repository` / `workflow_ref` / `workflow_sha`.**
  With a reusable workflow, "my CI produced this" is a claim about a commit in
  another repository. The publish job reads `job.workflow_*` for itself and holds
  the record to all three.
* **The status record publishes those three too — and
  `comparator_status_unchanged.sh` deliberately does not compare them.** Bumping
  the CI code is provenance, not a different verdict; comparing it would rewrite
  every consumer's status on every workflow edit and, at hopf scale, buy a
  three-hour regeneration for a claim that did not move. Say so on the trust-model
  page: `workflow_sha` names the CI code of the run that last *changed* the
  verdict, exactly as `commit` and `run_url` already do.

### The site pin, schema 2

`package_site.sh` writes it; `check_site_release.py` accepts exactly version 2.

```json
{ "schemaVersion": 2,
  "generationRevision": "<40 hex>",
  "generatedAt": "YYYY-MM-DDTHH:MM:SSZ",
  "release": { "tag": "...", "asset": "...", "sha256": "<64 hex>", "bytes": 0, "files": 0 },
  "pins": { "<every package in the site manifest>": "<rev>", "toolchain": "leanprover/lean4:vX.Y.Z" },
  "producer": { "workflow_repository": "...", "workflow_ref": "...", "workflow_sha": "<40 hex>",
                "run_id": "...", "run_url": "..." } }
```

Version 1 had four hardcoded `pins` and no `producer`. A pin that names four of
eleven revisions describes a build nobody can reproduce, and a tarball built by a
workflow in another repository has to name which commit of it.

### Why the release path is deterministic

The tarball is built from a sorted member list with fixed metadata
(`--sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --mode=go-w`) and
`gzip -n`, so its digest is a pure function of path + content + mode. The other
half of that is `CI_RUN_URL=""` into the site build and no `-R` in the default
contents command: baking a run id into the comparator page made every run's bytes
differ, which cut a release every run. The published CI link is `run_url` from the
status record, which moves only when the verdict moves.

Three skips protect the release, cheapest first: HEAD already equals the pin's
`generationRevision` (the site jobs do not run at all); the freshly packaged
digest equals the committed one (`::notice::`, no release); and the pin
commit-back's own `git diff --cached --quiet`.

---

## 5. What this does NOT establish

* **That the tarball is a faithful generation from the pinned revision.** The
  deploy gate authenticates what the tree says about itself against the publish
  branch, not the act of generating it. Under this standard that act is a CI job
  with public logs and deterministic packaging — more than the gate proves, less
  than a reproducible build.
* **That the certified theorem reaches *exactly* the permitted axioms.** The
  comparator enforces **containment**. hopf's old CI step asserted set equality;
  that step is gone, because the same fact was being audited up to three times per
  run and "one fact, one surface" is the rule. A consumer that wants "exactly
  these" states it in its own repository test (lean_quine's `Test.lean` does).
  The site's own `verso.blueprint.trust.requireAuditClean` remains the build-time
  audit over every declaration the site presents.
* **That a `configured` status is a verdict.** It is a config and no run.
* **That the site's informal prose says what the formal statement says.** No tool
  checks that; the comparator page shows the statement verbatim so a reader can.

---

## 6. Local use

`ci/scripts/package_site.sh` **requires** the producer environment
(`WORKFLOW_REPOSITORY`, `WORKFLOW_REF`, `WORKFLOW_SHA`, `GITHUB_RUN_ID`,
`GITHUB_SERVER_URL`, `GITHUB_REPOSITORY`) and fails without it. Packaging is a CI
act under this standard: what Pages serves has to be what a run generated from a
run's checkout. A workstation invocation fails here rather than producing a pin
the deploy gate would refuse later.

Everything else runs anywhere:

```
python3 -m unittest discover -s ci/scripts/tests
bash     ci/scripts/site_offline_gates.sh <html-multi directory>
python3  ci/scripts/check_trust_provenance.py --help
python3  ci/scripts/check_site_release.py --help
```

`landlock_selftest.sh` and `sandbox_selftest.sh` are Linux-only (Landlock), and
`sandbox_selftest.sh` additionally needs a systemd user session. On macOS they
cannot run at all, which is why the first real exercise of the sandbox half of a
new consumer's pipeline is always a CI run.
