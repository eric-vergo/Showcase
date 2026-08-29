import Lake
open Lake DSL

-- This starter builds against the published Showcase (VersoBlueprint) fork, pinned to an
-- immutable reviewed commit. A fresh copy therefore resolves the exact reviewed dependency
-- tree — the self-hosted `marked` (offline / strict-CSP rendering) and the VSCode-faithful
-- highlighting classification — with no network re-resolution. The committed
-- `lake-manifest.json` locks the whole graph, so `lake build` / `lake exe vbp build` works
-- from a fresh out-of-tree copy with NO `lake update` first.
--
-- Showcase transitively supplies the eric-vergo `verso` and `subverso` forks: its own lakefile
-- declares them ahead of `verso-slides`, so the forks win resolution over verso-slides'
-- upstream `leanprover/verso` pin (the offline / self-hosted-`marked` invariant). The template
-- does not re-declare them, which keeps their manifest entries inherited from Showcase.
--
-- The SAME commit is pinned by `.github/workflows/{ci,deploy}.yml`, which call Showcase's
-- reusable verification and deploy workflows. One number to bump: move the pin here, run
-- `lake update VersoBlueprint`, and change the two `uses:` refs and `showcase_sha:` values.
--
-- Local fork development: to test the template against a sibling `verso-blueprint` checkout
-- instead of the pinned commit, swap the git require below for a relative path require (see
-- project_template/README.md, "Local development against a sibling Showcase checkout"), or run
-- scripts/check_project_template_local_override.py, which applies that override in a scratch
-- copy without touching the committed template. Do not commit the path override.
require VersoBlueprint from git "https://github.com/eric-vergo/Showcase.git"@"6dd4a5f812d0f4338dc432c5efebf8ce47e260a0"

package ProjectTemplate where
  precompileModules := false
  -- Two graph gates run on every render. Acyclicity is unconditional. Connectivity is on by
  -- default: the build fails if the `uses` edges leave the graph in more than one piece, which
  -- is how an orphan — a statement nothing depends on and that depends on nothing — is caught
  -- before it ships. These chapters are wired so the check passes; keep it that way rather than
  -- silencing it, because the first thing a reader asks of a Blueprint graph is where a node
  -- sits in it. The escape hatch is for a Blueprint that deliberately covers several unrelated
  -- topics and so has no single connected graph to gate on (acyclicity still gates):
  --   ⟨`verso.blueprint.trust.requireConnected, false⟩
  leanOptions := #[
    ⟨`experimental.module, true⟩,
    -- The declarations the build-time axiom audit enumerates. Without it the audit sees only
    -- the declarations a node wires with `(lean := …)` — here two Lean core lemmas — and would
    -- report a clean audit that says nothing about this project's own code. Naming the module
    -- root makes the audit (and, for projects that turn it on, the declaration registry) cover
    -- the chapters' own Lean blocks. Set it to your library's root when you copy this.
    ⟨`weak.verso.blueprint.subjectModuleRoots, "ProjectTemplate"⟩,
    -- The trust surfaces. Each option names a file this build reads at ELABORATION and renders
    -- verbatim: the project's formalization.yaml (the "Formalization Metadata" page), the
    -- comparator's recorded verdict and the configuration it was produced from, and the
    -- Challenge/Solution sources the verdict is about (the "Statement comparator" page). The
    -- paths resolve against the build CWD, which for this template is the package directory.
    --
    -- They ship here in the honest state a new project starts in: a comparator that is
    -- CONFIGURED and has not run. The status artifact says `configured`, the strip badge and
    -- the comparator page say "not yet run", and the first CI run rewrites the artifact from
    -- its own evidence record.
    ⟨`weak.verso.blueprint.trust.formalizationYaml, "formalization.yaml"⟩,
    ⟨`weak.verso.blueprint.trust.comparatorStatus, "comparator/comparator-status.json"⟩,
    ⟨`weak.verso.blueprint.trust.comparatorConfig, "comparator/comparator.json"⟩,
    ⟨`weak.verso.blueprint.trust.challengeFile, "comparator/Challenge.lean"⟩,
    ⟨`weak.verso.blueprint.trust.solutionFile, "comparator/Solution.lean"⟩,
    -- Recommended. The build-time axiom audit runs `Lean.collectAxioms` over every declaration
    -- named above and reports the ones whose transitive closure carries `sorryAx` or an axiom
    -- beyond {propext, Classical.choice, Quot.sound}. By default such a finding is a warning
    -- plus a flagged clause on the site; this option makes it a build error.
    --
    -- The Collatz chapter's theorem is deliberately unfinished, and this template still builds
    -- with the gate on, because `formalization.yaml` DECLARES that sorry (`sorry_count: 1`,
    -- and again on the `collatz_conjecture` main result). A declared incompleteness is
    -- covered; an undeclared one fails the build. Change that declaration to `0` and this
    -- build stops, which is the check working.
    ⟨`weak.verso.blueprint.trust.requireAuditClean, true⟩
    -- Not set here, deliberately: `verso.blueprint.trust.expectedKernelIdentities` pins the
    -- checker identities a comparator run may be authenticated against (CX-064). A
    -- configured-but-missing path is a build error, and `trust/kernel-identities.json` does
    -- not exist until the first CI run bootstraps it. Add
    --   ⟨`weak.verso.blueprint.trust.expectedKernelIdentities, "trust/kernel-identities.json"⟩,
    -- together with an `input_file` edge for it, once that file is committed.
  ]

-- The trust surfaces are captured at ELABORATION from the files the options above name, and
-- none of them is a Lean module, so Lake otherwise tracks no read of them: edit only the
-- comparator status, its config, the Challenge, the Solution or formalization.yaml, rebuild,
-- and a warm `.olean` republishes the entire prior evidence page — old verdict beside the old
-- statement, internally consistent — under the new build's revision (codex-audit CX-075). An
-- `input_file` hashes each into the library's extra-dep job trace, which Lake mixes into every
-- module's `depTrace`, so an ordinary `lake build` re-elaborates the capture when one of them
-- changes.
--
-- Three things here are load-bearing, per the recipe in the fork's
-- `VersoBlueprint.TrustFreshness` module docs:
--   * `needs`, never `extraDepTargets` — for a named-kind declaration (which `input_file` is)
--     Lake resolves `extraDepTargets` through a branch that neither builds the target nor
--     contributes a trace, i.e. a silent no-op;
--   * `path` is relative to the PACKAGE directory (here the same directory the trust options
--     resolve against, because this site IS the package root);
--   * `text` stays at its default `false` — `text := true` normalizes line endings before
--     hashing, so a CRLF↔LF change would move the generator's byte digest without moving
--     Lake's trace, giving a build that fails the freshness gate and cannot be fixed by
--     rebuilding.
input_file formalizationYaml where
  path := "formalization.yaml"

input_file comparatorStatus where
  path := "comparator/comparator-status.json"

input_file comparatorConfig where
  path := "comparator/comparator.json"

input_file comparatorChallenge where
  path := "comparator/Challenge.lean"

input_file comparatorSolution where
  path := "comparator/Solution.lean"

@[default_target]
lean_lib ProjectTemplate where
  needs := #[`@/formalizationYaml, `@/comparatorStatus, `@/comparatorConfig,
             `@/comparatorChallenge, `@/comparatorSolution]

-- The comparator modules, registered as Lake libs so CI can build them BY NAME inside its
-- sandbox — and deliberately NOT default targets, so a bare `lake build` in a trusted job can
-- never elaborate them. Lean elaboration is arbitrary code execution: the first elaboration of
-- a Challenge or a Solution belongs inside the comparator's Landlock sandbox, in a job with no
-- write token (codex-audit CX-012).
--
-- ⚠️ `comparator/SolutionProbe.lean` WRITES FILES when it is elaborated. That is its purpose:
-- CI drives it through the same sandbox wrapper as the real solution and requires the writes
-- to be refused. Never open it in an elaborating editor outside a sandbox.
lean_lib Challenge where
  srcDir := "comparator"

lean_lib Solution where
  srcDir := "comparator"

lean_lib SolutionProbe where
  srcDir := "comparator"

-- The Blueprint generator entry point. `lake exe vbp build` locates it by this exact name
-- (`workspace.findLeanExe? "blueprint-gen"`), builds the library, and runs it to render the site.
lean_exe «blueprint-gen» where
  root := `ProjectTemplateMain
