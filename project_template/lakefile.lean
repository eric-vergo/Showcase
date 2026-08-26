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
-- Local fork development: to test the template against a sibling `verso-blueprint` checkout
-- instead of the pinned commit, swap the git require below for a relative path require (see
-- project_template/README.md, "Local development against a sibling Showcase checkout"), or run
-- scripts/check_project_template_local_override.py, which applies that override in a scratch
-- copy without touching the committed template. Do not commit the path override.
require VersoBlueprint from git "https://github.com/eric-vergo/Showcase.git"@"0c463f2d5c96286f8861feda6a3d21637c5d9268"

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
  leanOptions := #[⟨`experimental.module, true⟩]

@[default_target]
lean_lib ProjectTemplate where

-- The Blueprint generator entry point. `lake exe vbp build` locates it by this exact name
-- (`workspace.findLeanExe? "blueprint-gen"`), builds the library, and runs it to render the site.
lean_exe «blueprint-gen» where
  root := `ProjectTemplateMain
