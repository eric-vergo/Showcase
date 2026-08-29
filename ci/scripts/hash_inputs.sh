#!/usr/bin/env bash
# The input-hash manifest, computed identically before and after the certified run.
#
# One script, run immediately before and immediately after the comparator, so the
# two manifests are computed the same way and a difference can only mean the
# machinery or the certified sources changed mid-flight. The publish job's
# validator requires the two manifests to agree per key and re-derives the three
# SOURCE digests from its own checkout, so a manifest that drops a binary, or adds
# a fourth "source", is a different check than the one being published.
#
# Extracted from eric-vergo/OEIS-A362583-Irrationality .github/workflows/ci.yml
# (`Prepare the input-hash manifest script`) and eric-vergo/HopfProblem's
# byte-identical copy. The two differed in exactly two `emit` lines -- where the
# comparator binary lives (checked-out tool vs Lake dependency) and where the
# solution file lives -- so both are read from the environment here instead.
#
# Environment (all absolute paths unless noted):
#   COMPARATOR_BIN         the comparator executable that ran
#   COMPARATOR_LEAN4EXPORT the lean4export executable it drove
#   COMPARATOR_LANDRUN     the landrun binary
#   COMPARATOR_NANODA      the nanoda_bin binary
#   GITHUB_WORKSPACE       the consumer checkout
#   COMPARATOR_CONFIG      the config, relative to GITHUB_WORKSPACE
#   COMPARATOR_CHALLENGE   the challenge source, relative to GITHUB_WORKSPACE
#   COMPARATOR_SOLUTION    the solution source, relative to GITHUB_WORKSPACE
#
# Usage: bash ci/scripts/hash_inputs.sh <output.json>
set -euo pipefail
out="$1"
pairs="${out}.pairs"
: > "$pairs"
emit() { printf '%s\t%s\n' "$1" "$(sha256sum "$2" | cut -d' ' -f1)" >> "$pairs"; }
emit comparator        "${COMPARATOR_BIN}"
emit lean4export       "${COMPARATOR_LEAN4EXPORT}"
emit landrun           "${COMPARATOR_LANDRUN}"
emit nanoda            "${COMPARATOR_NANODA}"
emit comparator_config "${GITHUB_WORKSPACE}/${COMPARATOR_CONFIG}"
emit challenge_lean    "${GITHUB_WORKSPACE}/${COMPARATOR_CHALLENGE}"
emit solution_lean     "${GITHUB_WORKSPACE}/${COMPARATOR_SOLUTION}"
jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add' "$pairs" > "$out"
rm -f "$pairs"
cat "$out"
