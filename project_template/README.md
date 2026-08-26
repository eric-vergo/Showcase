# Project Template

This folder is a copyable starter Showcase project.

To inspect the generated output, copy this folder and run the local workflow
below; it writes the site to `_out/site/html-multi/`.

The goal is not to show every feature. The goal is to give you one small
project that already has the right moving parts:

- a GitHub Pages workflow under `.github/workflows/`
- chapter files with real Showcase blocks
- a Showcase top-level file
- a generator entry point
- a local CI script for build-and-render checks
- rendered graph and summary pages

## File Layout

```text
project_template/
  .github/
    workflows/
      blueprint-pages.yml
      pages.yml
  .gitignore
  lakefile.lean
  lean-toolchain
  ProjectTemplate.lean
  ProjectTemplate/
    Blueprint.lean
    Chapters/
      Addition.lean
      Multiplication.lean
      Collatz.lean
  ProjectTemplateMain.lean
  source/
    addition-source.tex
  scripts/
    ci-pages.sh
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
- `lakefile.lean`: the package definition
- `.github/workflows/blueprint-pages.yml`: copyable reusable Pages workflow
  used by the template
- `.github/workflows/pages.yml`: thin caller into the local reusable workflow
  that builds and deploys the generated HTML to GitHub Pages
- `scripts/ci-pages.sh`: the local command that the Pages workflow runs

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

## Recommended workflow

1. Copy this folder into a new repository.
2. Rename `ProjectTemplate` to your project name.
3. Keep the generator entry point and top-level file structure.
4. Replace the addition, multiplication, and Collatz chapters with your own
   content.

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

`./scripts/ci-pages.sh` is the same local build-and-render check that the
included GitHub Pages workflow runs. It delegates to the project helper:

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
build afterwards. Bumping the pin to a newer Showcase commit is a matter of
editing the commit hash in `lakefile.lean` and then running
`lake update VersoBlueprint`.

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

## GitHub Pages

The template includes `.github/workflows/pages.yml`.
It also includes `.github/workflows/blueprint-pages.yml`.

- on pull requests, it builds the Blueprint site and uploads the Pages artifact
- on pushes to `main`, it deploys `_out/site/html-multi` to GitHub Pages

Depending on your repository or organization settings, you may still need to
enable GitHub Pages with GitHub Actions as the publishing source once.

## Next step

Continue with [doc/GETTING_STARTED.md](../doc/GETTING_STARTED.md).
