#!/usr/bin/env bash
#
# check-header-provenance.sh — recurrence guard for codex-audit finding CX-004.
#
# Fork-original .lean files must not carry the upstream copyright-header template
# (a "Copyright (c) ... Lean FRO LLC" notice with a sole non-Eric author). New files
# are frequently created from an upstream file's template, headers included, which
# silently misattributes authorship and copyright — exactly what CX-004 recorded.
#
# Lineage is decided by git, not by guesswork: a .lean file that first appears on
# this fork (added or renamed relative to the upstream v4.32.0 baseline) with no
# upstream counterpart is fork-original, and its Authors line must name Eric Vergo.
# Upstream-lineage files legitimately keep their Lean FRO / upstream author notices
# (with the fork's contributors appended where the fork modified them), so they are
# NOT flagged.
#
# Runs locally and in CI. In CI the checkout must have full history (fetch-depth: 0)
# so the baseline commit is present.
set -euo pipefail

# Upstream/v4.32.0 — an ancestor of the fork branch, so present in any full clone.
BASE="51ebcae4b3133f407807e581178d2dcc705ac683"

cd "$(git rev-parse --show-toplevel)"

if ! git cat-file -e "${BASE}^{commit}" 2>/dev/null; then
  echo "check-header-provenance: baseline ${BASE} not present." >&2
  echo "  In CI, check out with fetch-depth: 0 so history reaches the baseline." >&2
  exit 2
fi

# Fork-original .lean files: added OR renamed since the baseline, under src/ or tests/,
# excluding the deliberately header-less trust fixtures. (Portable to bash 3.2, so no
# `mapfile`; a while-read loop over the git output instead.)
bad=0
checked=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in tests/fixtures/*) continue ;; esac
  [ -f "$f" ] || continue
  checked=$((checked + 1))
  # Author line(s) inside the leading /- ... -/ header block.
  authors="$(head -n 8 "$f" | grep -iE '^Authors?:' || true)"
  if ! printf '%s' "$authors" | grep -q 'Eric Vergo'; then
    echo "MISSING fork attribution (CX-004): $f"
    echo "    header author line: ${authors:-<none>}"
    bad=1
  fi
done <<EOF
$(git diff --diff-filter=AR --find-renames --name-only "${BASE}...HEAD" -- 'src/**/*.lean' 'tests/**/*.lean')
EOF

if [ "$bad" -ne 0 ]; then
  echo ""
  echo "FAIL: fork-original .lean file(s) carry the upstream header template."
  echo "      Correct them per codex-audit/responses/CX-004.md (fork-original files are"
  echo "      'Copyright (c) 2026 Eric Vergo' with Eric Vergo named in Authors)."
  exit 1
fi

echo "OK: every fork-original .lean file carries fork attribution (${checked} checked)."
