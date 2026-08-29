#!/usr/bin/env bash
# Compose the single evidence record the publish job is allowed to publish from.
#
# Everything the published status will claim is derived HERE, in the job that
# actually ran the check, from the config that was passed to the tool and from
# this run's own pins and hashes. Nothing in it is author-typed.
#
# Extracted from eric-vergo/HopfProblem .github/workflows/ci.yml (`Compose the
# comparator result record`), which is eric-vergo/OEIS-A362583-Irrationality's
# version plus `kernel_identities` (codex-audit CX-064). Three things changed on
# the way in:
#
#   * the record carries `workflow_repository` / `workflow_ref` / `workflow_sha`
#     -- WHICH CI code produced it. The pipeline is a reusable workflow now, so
#     "my CI produced this" is a claim about a commit in another repository, and
#     the publish job's validator holds all three to `job.*` values it read for
#     itself. Without them a record forged by any workflow anywhere would carry
#     exactly the fields the old validator checked.
#   * `permitted_axioms` is taken from the config WITHOUT a `// []` default and
#     the guard distinguishes ABSENT from EMPTY. `permitted_axioms: []` is a real
#     and stronger claim -- the certified theorem must reach no axiom at all --
#     and the old guard rejected it as if the key were missing.
#   * `kernel_identities[0].label` and the nanoda repository come from the
#     environment rather than being spelled inline.
#
# Environment: COMPARATOR_CONFIG, COMPARATOR_AF_UNIX_GUARD, COMPARATOR_STARTED_AT,
# COMPARATOR_FINISHED_AT, GITHUB_REPOSITORY, GITHUB_SHA, GITHUB_RUN_ID,
# COMPARATOR_TOOL_REF, COMPARATOR_TOOL_SHA, COMPARATOR_TOOL_TOOLCHAIN,
# LANDRUN_REF, NANODA_REF, NANODA_REPOSITORY, WORKFLOW_REPOSITORY, WORKFLOW_REF,
# WORKFLOW_SHA. CWD must be the consumer checkout (it reads ./lean-toolchain).
# Reads ${RUNNER_TEMP}/{hashes-before,hashes-after,probe,selftest}.json.
#
# Usage: bash ci/scripts/compose_result_record.sh <output.json>
set -euo pipefail
out="$1"

if ! diff <(jq -S . "${RUNNER_TEMP}/hashes-before.json") \
          <(jq -S . "${RUNNER_TEMP}/hashes-after.json"); then
  echo "a verification input changed during the comparator run"
  exit 1
fi

mkdir -p "$(dirname "$out")"
jq -n \
  --slurpfile cfg "$COMPARATOR_CONFIG" \
  --slurpfile pre "${RUNNER_TEMP}/hashes-before.json" \
  --slurpfile post "${RUNNER_TEMP}/hashes-after.json" \
  --slurpfile probe "${RUNNER_TEMP}/probe.json" \
  --slurpfile selftest "${RUNNER_TEMP}/selftest.json" \
  --arg config "$COMPARATOR_CONFIG" \
  --arg af_unix_guard "$COMPARATOR_AF_UNIX_GUARD" \
  --arg started_at "$COMPARATOR_STARTED_AT" \
  --arg finished_at "$COMPARATOR_FINISHED_AT" \
  --arg repository "$GITHUB_REPOSITORY" \
  --arg commit "$GITHUB_SHA" \
  --arg run_id "$GITHUB_RUN_ID" \
  --arg tool_ref "$COMPARATOR_TOOL_REF" \
  --arg tool_sha "$COMPARATOR_TOOL_SHA" \
  --arg tool_toolchain "$COMPARATOR_TOOL_TOOLCHAIN" \
  --arg toolchain "$(tr -d '[:space:]' < lean-toolchain)" \
  --arg landrun_ref "$LANDRUN_REF" \
  --arg nanoda_ref "$NANODA_REF" \
  --arg nanoda_repository "$NANODA_REPOSITORY" \
  --arg workflow_repository "$WORKFLOW_REPOSITORY" \
  --arg workflow_ref "$WORKFLOW_REF" \
  --arg workflow_sha "$WORKFLOW_SHA" \
  '($cfg[0]) as $c
   | (($c.enable_nanoda // false) == true) as $replay
   | if (($c.challenge_module // "") == "") or (($c.solution_module // "") == "") then
       error("the comparator config names no challenge_module / solution_module")
     elif (($c.theorem_names | type) != "array") or (($c.theorem_names | length) == 0) then
       error("the comparator config certifies no theorem_names")
     elif ($c | has("permitted_axioms") | not) or (($c.permitted_axioms | type) != "array") then
       # ABSENT, not empty. An empty allowlist is a stronger claim than the
       # standard three and a config is entitled to make it; a config that never
       # states the bound at all is a config this run cannot report a bound from.
       error("the comparator config declares no permitted_axioms array (an EMPTY array is allowed and means: no axiom at all)")
     else . end
   | { verdict: "verified",
       repository: $repository,
       commit: $commit,
       run_id: $run_id,
       started_at: $started_at,
       finished_at: $finished_at,
       config: $config,
       challenge_module: $c.challenge_module,
       solution_module: $c.solution_module,
       theorem_names: $c.theorem_names,
       permitted_axioms: $c.permitted_axioms,
       nanoda_replay: $replay,
       toolchain: $toolchain,
       tool_ref: $tool_ref,
       tool_sha: $tool_sha,
       tool_toolchain: $tool_toolchain,
       landrun_ref: $landrun_ref,
       nanoda_ref: $nanoda_ref,
       af_unix_guard: $af_unix_guard,
       workflow_repository: $workflow_repository,
       workflow_ref: $workflow_ref,
       workflow_sha: $workflow_sha,
       kernel_identities: [
         { label: "nanoda",
           repository: $nanoda_repository,
           source_commit: $nanoda_ref,
           executable_sha256: $post[0].nanoda,
           replayed: $replay } ],
       inputs_sha256_before: $pre[0],
       inputs_sha256_after: $post[0],
       sandbox_selftest: $selftest[0],
       sandbox_write_probe: $probe[0] }' > "$out"
cat "$out"
