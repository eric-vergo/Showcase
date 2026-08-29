# Project Template

This folder is a copyable starter Showcase project.

To inspect the generated output, copy this folder and run the local workflow
below; it writes the site to `_out/site/html-multi/`.

The goal is not to show every feature. The goal is to give you one small
project that already has the right moving parts:

- chapter files with real Showcase blocks
- a Showcase top-level file
- a generator entry point
- a local CI script for build-and-render checks
- rendered graph and summary pages
- the trust surfaces — formalization metadata, a trust model, a statement
  comparator — in the honest state a new project starts in
- two thin workflow files that call the shared verification and deploy pipeline

## File Layout

```text
project_template/
  .github/
    workflows/
      ci.yml
      deploy.yml
  .gitignore
  lakefile.lean
  lean-toolchain
  formalization.yaml
  ProjectTemplate.lean
  ProjectTemplate/
    Blueprint.lean
    Chapters/
      Addition.lean
      Multiplication.lean
      Collatz.lean
  ProjectTemplateMain.lean
  comparator/
    comparator.json
    comparator-probe.json
    comparator-status.json
    Challenge.lean
    Solution.lean
    SolutionProbe.lean
  source/
    addition-source.tex
  scripts/
    ci-pages.sh
  trust/
    README.md
```

The important files are:

- `ProjectTemplate/Chapters/Addition.lean`: the first chapter
- `ProjectTemplate/Chapters/Multiplication.lean`: the second chapter
- `ProjectTemplate/Chapters/Collatz.lean`: a separate exploratory chapter with
  the intentionally unfinished conjecture
- `ProjectTemplate/Blueprint.lean`: the Blueprint top-level file
- `ProjectTemplateMain.lean`: the rendering entry point
- `source/addition-source.tex`: a stand-in for the paper a ported project starts
  from; the addition chapter attaches its theorem to a Blueprint node and records
  this path and line range as that statement's original source
- `lakefile.lean`: the package definition, the trust options, and the Lake
  freshness edges that make an ordinary rebuild re-read the trust files
- `formalization.yaml`: the project's own metadata, to the
  `mathlib-initiative/formalization.yaml` v0.4 spec; rendered as the
  "Formalization Metadata" page and partly checked by the build-time axiom audit
- `comparator/`: the claim an independent checker is asked to certify
  (`Challenge.lean`), the proof of it (`Solution.lean`), the configuration
  (`comparator.json`), and the recorded verdict (`comparator-status.json`, which
  CI rewrites)
- `trust/`: the two files CI writes — the checker-identity pin and the site
  release pin. See `trust/README.md`
- `.github/workflows/ci.yml`: a ~50-line caller into the shared verification
  pipeline in `eric-vergo/Showcase`
- `.github/workflows/deploy.yml`: the caller that serves the pinned release on
  GitHub Pages
- `scripts/ci-pages.sh`: the local build-and-render check

> ⚠️ `comparator/SolutionProbe.lean` **writes files when it is elaborated.** It is
> the sandbox regression fixture: CI drives it through the comparator's sandbox
> and requires those writes to be refused. Never open it in an elaborating editor,
> and never build the `SolutionProbe` lib, outside a sandbox. It is deliberately
> not a default target and nothing imports it.

## What the template demonstrates

- labels that identify Blueprint nodes
- `:::definition`, `:::proposition`, `:::theorem`, and `:::proof`
- local Lean code attached to a Blueprint label
- local Rust code attached to a Blueprint label
- a statement linked to an existing Lean declaration
- an external markup attachment carrying the original source's path and line
  range, rendered with `(display := source)`
- group and author metadata
- rendered progress summary and dependency graph pages
- a separate Collatz chapter with one intentionally unfinished theorem so the
  first graph render shows an in-progress proof state
- basic math rendering in the informal text
- a `uses` graph that is connected, so the default connectivity gate passes; see
  the comment in `lakefile.lean` for when a project turns that gate off
- a homepage **trust strip** with the graph badges, the comparator's status, and
  one scope line saying what the comparator covers and what the axiom audit found
- a **Formalization Metadata** page rendered from `formalization.yaml`, where
  declared figures render as declarations with a cross-check note rather than as
  verdict badges
- a **Trust model** page separating what the build established from what the
  project asserts
- a **Statement comparator** page in the honest `configured — not yet run` state:
  the challenge and the solution are on the page, and nothing claims a run
  happened until one has
- the **build-time axiom audit** with `requireAuditClean` on. The Collatz theorem
  is `sorry`, and the build is green because `formalization.yaml` says so. Change
  its declared `sorry_count` to `0` and the build fails — that is the check

## Recommended workflow

1. Copy this folder into a new repository.
2. Rename `ProjectTemplate` to your project name (in `lakefile.lean`, including
   `verso.blueprint.subjectModuleRoots`, and in the two workflow files).
3. Keep the generator entry point and top-level file structure.
4. Replace the addition, multiplication, and Collatz chapters with your own
   content.
5. Replace `formalization.yaml` and `comparator/Challenge.lean` /
   `comparator/Solution.lean` with your project's own claim, and keep
   `comparator/comparator.json` naming it.

Typical commands:

```bash
./scripts/ci-pages.sh
```

The template is self-contained: `lakefile.lean` requires the published Showcase
(`VersoBlueprint`) fork from Git at an immutable reviewed commit, and the
committed `lake-manifest.json` locks the entire resolved dependency graph. A
fresh out-of-tree copy therefore **resolves** the reviewed dependency tree —
the eric-vergo `verso`/`subverso` forks at their pinned revisions — with no
parent checkout and no re-resolution; **do not run `lake update` first**.

`./scripts/ci-pages.sh` is the local build-and-render check. It delegates to the
project helper:

```bash
lake exe vbp build
```

`vbp build` builds the Lean library artifacts, prepares the generator file, and
then runs the generator through Lake's Lean wrapper without relying on a
separate Lake executable target.

### Moving off the pinned revisions

The committed pin is a specific reviewed Showcase commit, chosen so that a fresh
copy resolves the exact fork tree the template was validated against (offline
`marked`, VSCode-faithful highlighting). Running `lake update` re-resolves the
Git dependencies to the current branch heads and rewrites `lake-manifest.json`;
do that deliberately when you want newer fork revisions, and re-run the local
build afterwards.

The **same** Showcase commit appears in three places: the `require VersoBlueprint`
line in `lakefile.lean`, and the `uses:` ref plus `showcase_sha:` input in each of
`.github/workflows/ci.yml` and `.github/workflows/deploy.yml`. Bumping the pin
means editing all of them and then running `lake update VersoBlueprint`; the
workflow asserts its own commit against the `showcase_sha` you state, so a
half-finished bump fails loudly instead of running CI code you did not pin.

### Local development against a sibling Showcase checkout

To test the template against a sibling `verso-blueprint` checkout instead of the
pinned commit, replace the `require VersoBlueprint from git …` line with:

```lean
require VersoBlueprint from ".."
```

and run `lake update VersoBlueprint`. This override points at the in-tree fork
and is for fork development only — do not commit it. The
`scripts/check_project_template_local_override.py` helper applies exactly this
override in a scratch copy so the committed template is never modified.

`vbp build` accepts `--output <dir>`, `--serve`, and `--port <n>`, and rejects
anything else. The site is HTML only — this fork does not carry upstream's
TeX/PDF export, so there is no local PDF build.

## Continuous integration and GitHub Pages

`.github/workflows/ci.yml` and `.github/workflows/deploy.yml` are thin callers.
The pipeline they call lives in `eric-vergo/Showcase` (`ci/README.md` there is
the contract) and is the same one every blueprint consumer runs:

- a **trusted build** job that builds only the subject library and runs the
  `formalization.yaml` schema check;
- an **untrusted comparator** job, with no write token, where the challenge and
  the solution are elaborated for the first time inside a Landlock sandbox,
  behind a self-test and a denied-write probe;
- a **publish** job — the only one that can write to the repository — which
  validates the run's evidence record and commits back
  `comparator/comparator-status.json` and `trust/kernel-identities.json`;
- **site** jobs that build and render the site, run the file, offline and
  provenance gates, package a deterministic tarball, cut a release, and commit
  `trust/site-build.json`;
- a separate **deploy** workflow that verifies the release digest against that
  pin before Pages serves a byte of it.

`ci.yml` holds no Pages scope and no OIDC: the workflow that can write to the
repository and the workflow that can mint a Pages token are different files.

Depending on your repository or organization settings, you may still need to
enable GitHub Pages with GitHub Actions as the publishing source once.

## Next step

Continue with [doc/GETTING_STARTED.md](../doc/GETTING_STARTED.md).
