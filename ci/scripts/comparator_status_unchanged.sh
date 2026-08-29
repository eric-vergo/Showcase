#!/usr/bin/env bash
# Does a freshly composed comparator status record say anything new?
#
# The publish job (.github/workflows/blueprint-verify.yml) composes a status
# record from every run's evidence. Rewriting the committed one unconditionally
# would stamp a new `commit`, `verified_at` and `run_url` into the file on every
# push -- including pushes that touched nothing the comparator looked at. That
# file is an ELABORATION-TIME trust input of the blueprint site: its freshness
# edge is an `input_file` dependency, so every rewrite invalidates the site's
# warm build and costs a full regeneration (~3 h at hopf scale) for a verdict
# that did not move.
#
# So the publish job asks this script first. The question it answers is narrow
# and deliberately not "are the two files identical": it is whether the VERDICT,
# the INPUT HASHES and the VERIFIER IDENTITIES agree. Those are the fields that
# make a verdict what it is. The fields excluded are exactly the run-provenance
# ones -- `commit`, `verified_at`, `run_url`, `note`, and (since the pipeline
# became a reusable workflow) `workflow_repository` / `workflow_ref` /
# `workflow_sha`. Bumping the CI code is provenance, not a different verdict; if
# it were compared, every edit to the shared workflow would rewrite every
# consumer's status file and, at hopf scale, buy a three-hour regeneration for a
# claim that did not move. The consequence is worth saying out loud on the trust
# model page: `workflow_sha` in the committed record names the CI code of the run
# that last CHANGED the verdict, exactly as `commit` and `run_url` already do.
# That is the point:
# re-verifying identical bytes with identical verifiers is not new information
# about the mathematics, so the committed record keeps naming the last commit at
# which those bytes were verified, and the hashes it carries let a reader
# confirm the current tree still holds the same bytes.
#
# `tool_ref` is excluded because it is a human-readable NAME for `tool_sha`, and
# the build job's "Assert the comparator tool pin" step fails unless the tag
# still resolves to that commit -- so the sha stands for both. The challenge and
# solution MODULE names and the config path are excluded because they are read
# out of the comparator config, whose digest (`config_sha256`) is compared.
#
# Comparison is strict JSON equality over the compared key set, computed by jq,
# not a text diff: key order, whitespace and unrelated keys must not decide
# whether a site rebuild is owed.
#
#   usage: bash ci/scripts/comparator_status_unchanged.sh COMMITTED CANDIDATE
#
#   exit 0  unchanged -- the committed record already states this verdict for
#           these inputs and these verifiers; do not rewrite it
#   exit 1  changed -- refresh and commit back. A committed file that is absent,
#           unreadable, not a JSON object, or missing any compared field counts
#           as changed: this script only ever suppresses a rewrite on positive
#           evidence that one is unnecessary
#   exit 2  usage error
#
# Every doubt therefore resolves toward rewriting, which is the pre-existing
# behaviour; the saving is claimed only where the evidence is explicit.
#
# Tested by ci/scripts/tests/test_comparator_status_unchanged.sh, in the trusted
# build job, in seconds.

set -uo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: bash $0 COMMITTED CANDIDATE" >&2
  exit 2
fi

committed="$1"
candidate="$2"

if [ ! -f "$candidate" ]; then
  echo "$0: candidate record '$candidate' does not exist" >&2
  exit 2
fi

if [ ! -f "$committed" ]; then
  echo "comparator status: no committed record at '$committed' yet; this run is new information."
  exit 1
fi

# `--slurpfile` fails loudly on unparsable input, which is the "invalid counts
# as changed" branch below rather than a job failure.
verdict="$(
  jq -r -n \
    --slurpfile committed "$committed" \
    --slurpfile candidate "$candidate" \
    '
    # The verdict, the input hashes and the verifier identities -- and nothing
    # about which run observed them. `nanoda_ref` is part of the projection
    # exactly when a nanoda replay is claimed, mirroring the status refresh,
    # which deletes the key when it is not.
    def project:
      { status,
        config_sha256, challenge_sha256, solution_sha256, challenge_chain,
        theorem_names, permitted_axioms,
        tool_sha, tool_toolchain, landrun_ref, nanoda_replay, kernel_identities
      }
      + (if .nanoda_replay == true then { nanoda_ref } else {} end);

    ($committed[0]) as $old
    | ($candidate[0]) as $new
    | if ($old | type) != "object" then
        "the committed record is not a JSON object"
      elif ($new | type) != "object" then
        "the candidate record is not a JSON object"
      else
        ($old | project) as $o
        | ($new | project) as $n
        | ([$o | to_entries[] | select(.value == null) | .key]) as $absent
        | if ($absent | length) > 0 then
            "the committed record carries no " + ($absent | join(", "))
          else
            ([($n | keys[]), ($o | keys[])] | unique) as $keys
            | [$keys[] | select($o[.] != $n[.])] as $diff
            | if ($diff | length) == 0 then "unchanged"
              else "changed: " + ($diff | join(", "))
              end
          end
      end
    ' 2>&1
)" || {
  echo "comparator status: cannot read '$committed' as JSON (${verdict}); treating the verdict as changed."
  exit 1
}

if [ "$verdict" = "unchanged" ]; then
  exit 0
fi

echo "comparator status: ${verdict}."
exit 1
