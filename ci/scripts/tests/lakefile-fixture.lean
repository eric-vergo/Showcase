/-
A stand-in for a consumer's site lakefile, for the trust-provenance gate's
fixtures (ci/scripts/tests/test_trust_provenance_gate.py).

The gate reads the four `verso.blueprint.trust.*` comparator options and the
matching Lake `input_file` edges out of the consumer's lakefile at run time,
rather than restating them, so the fixtures need a lakefile to read. This one is
deliberately MINIMAL and deliberately NOT a real consumer's file: the suite lives
in the CI repository and must not depend on any particular consumer's tree.

The paths are the `../comparator/...` shape a nested site package uses (a362583,
hopf), because that is the shape whose `..` segments `normalize_path` must keep.
The live coupling -- that a REAL consumer still configures all four options and
still declares all four edges -- is enforced on every CI run, by the workflow,
against that consumer's own checkout.
-/
import Lake
open Lake DSL

package Contents where
  leanOptions := #[
    ⟨`weak.verso.blueprint.trust.formalizationYaml, "../formalization.yaml"⟩,
    ⟨`weak.verso.blueprint.trust.comparatorStatus, "../comparator/comparator-status.json"⟩,
    ⟨`weak.verso.blueprint.trust.comparatorConfig, "../comparator/comparator.json"⟩,
    ⟨`weak.verso.blueprint.trust.challengeFile, "../comparator/Challenge.lean"⟩,
    ⟨`weak.verso.blueprint.trust.solutionFile, "../comparator/Solution.lean"⟩,
    ⟨`weak.verso.blueprint.trust.requireAuditClean, true⟩
  ]

input_file comparatorStatus where
  path := "../comparator/comparator-status.json"

input_file comparatorConfig where
  path := "../comparator/comparator.json"

input_file comparatorChallenge where
  path := "../comparator/Challenge.lean"

input_file comparatorSolution where
  path := "../comparator/Solution.lean"

@[default_target]
lean_lib Contents where
  needs := #[`@/comparatorStatus, `@/comparatorConfig,
             `@/comparatorChallenge, `@/comparatorSolution]
