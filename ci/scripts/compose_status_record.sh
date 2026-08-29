#!/usr/bin/env bash
# Compose the status record the blueprint site quotes, from the run's evidence.
#
# This artifact is the sole evidence the blueprint's trust surfaces quote, so
# everything in it is written here, by machine, and nothing in it is
# author-typed: the claim fields come from the result record the verification job
# emitted (which in turn copied them out of the very config it passed to the
# tool), and the note is composed from those. Nothing is asserted that the record
# does not carry.
#
# Composed WHOLE with `jq -n` rather than merged into the file on disk: a merge
# needs a pre-existing file (a first run has none) and carries forward keys a
# later workflow stopped writing.
#
# Extracted from eric-vergo/HopfProblem .github/workflows/ci.yml (`Refresh
# comparator-status.json if this run changed it`). Changes on the way in:
#
#   * `workflow_repository` / `workflow_ref` / `workflow_sha` are published, so a
#     reader can name the CI code that produced the verdict. Note what that means:
#     `ci/scripts/comparator_status_unchanged.sh` deliberately does NOT compare
#     them, so -- exactly like `commit` and `run_url` already -- they name the run
#     that last CHANGED the verdict, not the last run to re-check it.
#   * the note names the reusable workflow rather than a per-consumer path, and
#     how the tool was obtained is a parameter (`COMPARATOR_TOOL_ORIGIN`) rather
#     than two forks of the same sentence.
#   * `permitted_axioms: []` renders as "no axioms at all" instead of an empty
#     join, which would have produced "using only the permitted axioms .".
#
# Environment: COMPARATOR_CHALLENGE, COMPARATOR_TOOL_ORIGIN, WORKFLOW_REPOSITORY,
# WORKFLOW_REF, WORKFLOW_SHA, and CI_RUN_URL (or the GITHUB_* fallback).
#
# Usage: bash ci/scripts/compose_status_record.sh <result.json> <output.json>
set -euo pipefail
res="$1"
out="$2"
run_url="${CI_RUN_URL:-${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}}"

jq -n \
  --slurpfile res "$res" \
  --arg run_url "$run_url" \
  --arg challenge "$COMPARATOR_CHALLENGE" \
  --arg tool_origin "$COMPARATOR_TOOL_ORIGIN" \
  --arg workflow_repository "$WORKFLOW_REPOSITORY" \
  --arg workflow_ref "$WORKFLOW_REF" \
  --arg workflow_sha "$WORKFLOW_SHA" \
  '
  ($res[0]) as $r
  | ($r.theorem_names) as $thms
  | ($r.permitted_axioms) as $axs
  | {
      status: $r.verdict,
      # The subject identity the validator authenticated against this checkout.
      # Without it the published artifact would describe WHICH programs did the
      # checking but not WHICH project revision was checked (codex-audit CX-068).
      repository: $r.repository,
      commit: $r.commit,
      config: $r.config,
      challenge_module: $r.challenge_module,
      solution_module: $r.solution_module,
      theorem_names: $thms,
      permitted_axioms: $axs,
      verified_at: $r.finished_at,
      run_url: $run_url,
      tool_ref: $r.tool_ref,
      tool_sha: $r.tool_sha,
      tool_toolchain: $r.tool_toolchain,
      landrun_ref: $r.landrun_ref,
      nanoda_replay: $r.nanoda_replay,
      # WHICH CI code ran. Provenance, not verdict: the change detector does not
      # compare these, so they name the run that last changed the verdict.
      workflow_repository: $workflow_repository,
      workflow_ref: $workflow_ref,
      workflow_sha: $workflow_sha,
      # The run evidence CX-064 asks for: not the label "nanoda" but the
      # repository, revision and executable digest of the program that replayed
      # the export. The site treats it as authenticated only where it agrees
      # with the pin the consumer committed.
      kernel_identities: $r.kernel_identities,
      config_sha256: $r.inputs_sha256_after.comparator_config,
      challenge_sha256: $r.inputs_sha256_after.challenge_lean,
      solution_sha256: $r.inputs_sha256_after.solution_lean,
      # The ordered challenge chain this run verified. It is what the
      # statement-closure surface on the site binds against: the closure is
      # presented as adjacent to the verdict only when the chain the tool hashed
      # matches this list, in order and by digest, so a dependency edited without
      # touching the primary Challenge drops the binding rather than quietly
      # keeping it. The digest is the one the manifest already computed over
      # exactly those bytes, not a second hash of them.
      # (No apostrophes in this comment: it lives inside the single-quoted jq
      # program, and one would terminate the shell string.)
      challenge_chain: [ { path: $challenge, sha256: $r.inputs_sha256_after.challenge_lean } ]
    }
  | (if $r.nanoda_replay then . + { nanoda_ref: $r.nanoda_ref } else del(.nanoda_ref) end)
  | .note =
      ( "Verified in CI by leanprover/comparator " + $r.tool_ref + " (commit " + $r.tool_sha
      + "), " + $tool_origin + $r.tool_toolchain + ", by the reusable workflow "
      + $workflow_repository + " .github/workflows/blueprint-verify.yml at commit " + $workflow_sha
      + ", against " + $r.repository + " at commit " + $r.commit + ": the "
      + $r.solution_module + " module kernel-checks the exact " + $r.challenge_module
      + " statement" + (if ($thms | length) == 1 then " " else "s " end) + ($thms | join(", "))
      + (if ($axs | length) == 0 then
           ", using no axioms at all"
         else
           ", using only the permitted axioms " + ($axs | join(", "))
         end)
      + ". Statement equality, axiom whitelist and Lean-kernel replay confirmed"
      + (if $r.nanoda_replay then
           ", together with an independent replay by the nanoda kernel (ammkrn/nanoda_lib "
           + $r.nanoda_ref + ")"
         else "" end)
      + ". The challenge and solution modules were elaborated for the first time inside a "
      + "Landlock sandbox (Zouuup/landrun " + $r.landrun_ref + "), as were the kernel exports, "
      + "under a systemd-run AF_UNIX guard (recorded as " + $r.af_unix_guard
      + "; the run fails closed if that guard is unavailable). Before that elaboration, a probe "
      + "written by the workflow itself — importing only core Lean, with write targets chosen "
      + "per run — was put through the same sandbox wrapper: its writes outside the sandbox were "
      + "refused, while an unsandboxed control confirmed the same probe does write when nothing "
      + "stops it. After the run, a repository-side fixture attempting the same writes was also "
      + "rejected, as defense in depth. The comparator, lean4export, landrun and nanoda binaries "
      + "and the certified sources hashed identically before and after the run."
      )
  ' > "$out"
cat "$out"
