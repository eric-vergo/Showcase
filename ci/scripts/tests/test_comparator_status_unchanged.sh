#!/usr/bin/env bash
# Fixtures for ci/scripts/comparator_status_unchanged.sh.
#
# That script decides whether the publish job rewrites the committed comparator
# status record. Getting it wrong is expensive in both directions: too eager and
# every push re-stamps an elaboration-time trust input and buys a ~3 h site
# regeneration for nothing; too lazy and a genuinely different verdict, a
# changed certified source or a swapped verifier binary keeps the old record's
# reassuring text. So each case below is a pair of records and the answer the
# script owes it.
#
# The pairs are built here from one base record, so the fixtures cannot drift
# away from the shape the publish job actually composes without this file being
# edited too. Like the validator's forged-record suite, this runs in the trusted
# `build` job, in seconds, before anything expensive.
#
# Run: bash ci/scripts/tests/test_comparator_status_unchanged.sh
#      (or, through unittest discovery, test_comparator_status_unchanged.py)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_SCRIPTS="$(cd "${HERE}/.." && pwd)"
SCRIPT="${CI_SCRIPTS}/comparator_status_unchanged.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/comparator-status-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

failures=0
checks=0

# A status record of exactly the shape the publish job composes. The digests are
# plausible-looking constants; nothing here hashes a real file, because what is
# under test is the comparison, not the hashing.
cat > "${TMP}/base.json" <<'JSON'
{
  "status": "verified",
  "repository": "eric-vergo/HopfProblem",
  "commit": "1111111111111111111111111111111111111111",
  "config": "comparator/config.json",
  "challenge_module": "Challenge",
  "solution_module": "Solution",
  "theorem_names": ["Mathoverflow1973.mathoverflow_1973"],
  "permitted_axioms": ["propext", "Classical.choice", "Quot.sound"],
  "verified_at": "2026-08-01T00:00:00Z",
  "run_url": "https://github.com/eric-vergo/HopfProblem/actions/runs/1#step:20:1",
  "tool_ref": "v4.33.0",
  "tool_sha": "3927ad383f208ae977c340a91c48ac9b497d2097",
  "tool_toolchain": "leanprover/lean4:v4.33.0",
  "landrun_ref": "811cfff51ceaf3d9843708aa6d22e9b84ccac8b4",
  "nanoda_replay": true,
  "workflow_repository": "eric-vergo/Showcase",
  "workflow_ref": "eric-vergo/Showcase/.github/workflows/blueprint-verify.yml@refs/heads/blueprint",
  "workflow_sha": "3333333333333333333333333333333333333333",
  "kernel_identities": [
    {
      "label": "nanoda",
      "repository": "https://github.com/ammkrn/nanoda_lib",
      "source_commit": "05055695879dfebb6628a67da88ceca6cd6b0421",
      "executable_sha256": "bb0244fe85a846f1577eadff0d710e6e97c381d0d585fbb831f307fb3f971dfe",
      "replayed": true
    }
  ],
  "config_sha256": "2c911530b1233e07e5e9031f74a5ad884630b5dcc74210de899cc2e2b6830a6b",
  "challenge_sha256": "9b0cbe638ce7b1bb879e633a01a8915fdb292619967dadc56158a4f7ba091c3b",
  "solution_sha256": "0ac7023a21c7a4fa38b6c3e65f8acb6a666fb43034aae0f960feea9872951cc5",
  "challenge_chain": [
    { "path": "Challenge.lean", "sha256": "9b0cbe638ce7b1bb879e633a01a8915fdb292619967dadc56158a4f7ba091c3b" }
  ],
  "nanoda_ref": "05055695879dfebb6628a67da88ceca6cd6b0421",
  "note": "Verified in CI by leanprover/comparator v4.33.0 ..."
}
JSON

# derive NAME FILTER -- a variant of the base record.
derive() {
  local name="$1" filter="$2"
  jq "$filter" "${TMP}/base.json" > "${TMP}/${name}.json"
}

# expect WANT COMMITTED CANDIDATE DESCRIPTION
expect() {
  local want="$1" committed="$2" candidate="$3" description="$4"
  local output status
  checks=$((checks + 1))
  output="$(bash "$SCRIPT" "$committed" "$candidate" 2>&1)"
  status=$?
  if [ "$status" -eq "$want" ]; then
    printf 'ok   %s\n' "$description"
  else
    printf 'FAIL %s\n     wanted exit %s, got %s: %s\n' "$description" "$want" "$status" "$output"
    failures=$((failures + 1))
  fi
}

# --- the case this whole mechanism exists for ----------------------------------
# A later run of the same verdict over the same bytes with the same verifiers.
# Only the run provenance differs -- which is exactly what must NOT force a
# rewrite, because rewriting it invalidates the site's trust-input freshness
# edge and buys a three-hour regeneration for no new claim.
derive same-hashes-committed '
  .commit = "2222222222222222222222222222222222222222"
  | .verified_at = "2026-07-01T00:00:00Z"
  | .run_url = "https://github.com/eric-vergo/HopfProblem/actions/runs/7#step:20:1"
  | .note = "Verified in CI by leanprover/comparator v4.33.0 (an earlier run) ..."
'
expect 0 "${TMP}/same-hashes-committed.json" "${TMP}/base.json" \
  "same hashes, different run provenance => skip the rewrite"

# Unrelated keys, key order and whitespace must not decide a site rebuild: the
# comparison is JSON equality over the compared fields, not a text diff.
jq -S '. + {some_future_key: "ignored"}' "${TMP}/same-hashes-committed.json" \
  | tr -d '\n' > "${TMP}/same-hashes-reordered.json"
expect 0 "${TMP}/same-hashes-reordered.json" "${TMP}/base.json" \
  "reordered keys, no newlines and an unknown key => still skip"

# --- CI-code provenance is provenance, not a verdict ---------------------------
# The pipeline is a reusable workflow, so the status record now names WHICH CI
# code produced it. Those three fields are deliberately outside the projection:
# if they were compared, every edit to the shared workflow would rewrite every
# consumer status file -- and, at hopf scale, buy a three-hour regeneration for a
# claim that did not move. `workflow_sha` therefore names the CI code of the run
# that last CHANGED the verdict, exactly as `commit` and `run_url` already do.
derive newer-workflow-code '
  .workflow_sha = "4444444444444444444444444444444444444444"
  | .workflow_ref = "eric-vergo/Showcase/.github/workflows/blueprint-verify.yml@refs/heads/blueprint"
  | .commit = "2222222222222222222222222222222222222222"
  | .run_url = "https://github.com/eric-vergo/HopfProblem/actions/runs/8#step:20:1"
'
expect 0 "${TMP}/newer-workflow-code.json" "${TMP}/base.json"   "the shared workflow was bumped, nothing else => skip the rewrite"

# The other half of the same claim: a bump of the CI code must not SUPPRESS a
# rewrite that a verifier change owes. The projection still compares landrun,
# nanoda and the tool, so a run that moved both refreshes.
derive newer-workflow-and-verifier '
  .workflow_sha = "4444444444444444444444444444444444444444"
  | .landrun_ref = "0000000000000000000000000000000000000000"
'
expect 1 "${TMP}/base.json" "${TMP}/newer-workflow-and-verifier.json"   "the CI code AND a verifier moved => still refresh"

# --- anything the verdict actually rests on ------------------------------------
derive changed-solution '.solution_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"'
expect 1 "${TMP}/base.json" "${TMP}/changed-solution.json" \
  "the certified solution was edited => refresh"

derive changed-challenge '
  .challenge_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
  | .challenge_chain[0].sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
'
expect 1 "${TMP}/base.json" "${TMP}/changed-challenge.json" \
  "the certified challenge was edited => refresh"

derive changed-config '.config_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"'
expect 1 "${TMP}/base.json" "${TMP}/changed-config.json" \
  "the comparator config was edited => refresh"

derive changed-chain-path '.challenge_chain[0].path = "comparator/Challenge.lean"'
expect 1 "${TMP}/base.json" "${TMP}/changed-chain-path.json" \
  "the challenge chain was re-rooted => refresh"

derive changed-status '.status = "failed"'
expect 1 "${TMP}/base.json" "${TMP}/changed-status.json" \
  "the verdict itself changed => refresh"

derive changed-theorems '.theorem_names = ["Mathoverflow1973.something_else"]'
expect 1 "${TMP}/base.json" "${TMP}/changed-theorems.json" \
  "a different theorem was certified => refresh"

derive changed-axioms '.permitted_axioms = ["propext"]'
expect 1 "${TMP}/base.json" "${TMP}/changed-axioms.json" \
  "the permitted axioms changed => refresh"

# --- the verifiers -------------------------------------------------------------
derive changed-tool '.tool_sha = "0000000000000000000000000000000000000000"'
expect 1 "${TMP}/base.json" "${TMP}/changed-tool.json" \
  "the comparator tool was re-pinned => refresh"

derive changed-tool-toolchain '.tool_toolchain = "leanprover/lean4:v4.34.0"'
expect 1 "${TMP}/base.json" "${TMP}/changed-tool-toolchain.json" \
  "the tool built on a different toolchain => refresh"

derive changed-landrun '.landrun_ref = "0000000000000000000000000000000000000000"'
expect 1 "${TMP}/base.json" "${TMP}/changed-landrun.json" \
  "landrun was re-pinned => refresh"

derive changed-nanoda '
  .nanoda_ref = "0000000000000000000000000000000000000000"
  | .kernel_identities[0].source_commit = "0000000000000000000000000000000000000000"
'
expect 1 "${TMP}/base.json" "${TMP}/changed-nanoda.json" \
  "nanoda was re-pinned => refresh"

# The digest of the binary that actually replayed the export. It moves with the
# runner image, so it is published as run evidence rather than pinned -- but a
# different program did the checking, and the record must say so.
derive changed-identity-digest '.kernel_identities[0].executable_sha256 = "cc" + ("0" * 62)'
expect 1 "${TMP}/base.json" "${TMP}/changed-identity-digest.json" \
  "a different nanoda executable replayed the export => refresh"

derive dropped-replay '.nanoda_replay = false | del(.nanoda_ref)'
expect 1 "${TMP}/base.json" "${TMP}/dropped-replay.json" \
  "the independent replay was switched off => refresh"

# --- a committed record that cannot be trusted to agree ------------------------
expect 1 "${TMP}/absent.json" "${TMP}/base.json" \
  "no committed record yet => refresh"

printf 'not json at all\n' > "${TMP}/invalid.json"
expect 1 "${TMP}/invalid.json" "${TMP}/base.json" \
  "an unparsable committed record => refresh"

printf '[1, 2, 3]\n' > "${TMP}/array.json"
expect 1 "${TMP}/array.json" "${TMP}/base.json" \
  "a committed record that is not an object => refresh"

derive truncated 'del(.kernel_identities)'
expect 1 "${TMP}/truncated.json" "${TMP}/base.json" \
  "a committed record missing a compared field => refresh"

# A record written by an older workflow that never recorded the chain: absent is
# not "agrees", or the statement-closure binding would silently keep an old one.
derive no-chain 'del(.challenge_chain)'
expect 1 "${TMP}/no-chain.json" "${TMP}/base.json" \
  "a committed record predating challenge_chain => refresh"

# --- the script's own contract -------------------------------------------------
expect 2 "${TMP}/base.json" "${TMP}/absent.json" \
  "a missing candidate record is a usage error, not an answer"

printf '\n%s check(s), %s failure(s)\n' "$checks" "$failures"
[ "$failures" -eq 0 ] || exit 1
