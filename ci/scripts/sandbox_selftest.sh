#!/usr/bin/env bash
# Trusted pre-run containment evidence (codex-audit CX-050 / CX-051).
#
# Containment has to be established BEFORE the repository's own Lean is
# elaborated: a probe that runs afterwards cannot retroactively protect the
# boundary the first elaboration already crossed (CX-050), and a probe that IS a
# repository file is not independent evidence -- a fixture edited to print the
# expected words while attempting nothing satisfies every acceptance predicate
# (CX-051).
#
# This script is neither. Everything it runs is written HERE, by the CI code,
# into a scratch package outside the checkout; the package imports only core Lean
# (no repository modules, no Mathlib); its two write targets and its denial
# sentinel are randomised per run and baked into the heredoc, so no repository
# content can name or forge them; and the outcome is classified from OS-level
# facts -- do the target files exist? -- with an unsandboxed positive control
# first, proving the fixture really does write when nothing stops it. A run that
# fails without the sentinel is a run that proved nothing, and fails the job.
#
# The landrun invocation is the comparator's own, argument for argument
# (leanprover/comparator Main.lean, buildLandrunArgs + safeLakeBuild at the
# pinned commit), with the scratch package in place of the project, and it is
# wrapped in the same systemd-run AF_UNIX guard as the real run.
#
# Extracted VERBATIM from eric-vergo/OEIS-A362583-Irrationality
# .github/workflows/ci.yml (the `Trusted pre-run sandbox self-test` step). The
# eric-vergo/HopfProblem copy differs only in one comment paragraph; this is the
# a362583 wording, which records the incident that produced the PATH handling.
# The body below is the workflow step's `run:` script, dedented and otherwise
# unchanged.
#
# Environment: COMPARATOR_AF_UNIX_GUARD (must be "active"), COMPARATOR_LANDRUN,
# RUNNER_TEMP, HOME. CWD must be the consumer checkout (it reads ./lean-toolchain
# and resolves `lean --print-prefix` from there). Writes ${RUNNER_TEMP}/selftest.json,
# ${RUNNER_TEMP}/selftest-unsandboxed.log and ${RUNNER_TEMP}/selftest-sandboxed.log.
#
# Usage: bash ci/scripts/sandbox_selftest.sh
set -euo pipefail
test "${COMPARATOR_AF_UNIX_GUARD}" = "active"
nonce="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
scratch="${RUNNER_TEMP}/sandbox-selftest"
target_a="${RUNNER_TEMP}/selftest-canary-a-${nonce}"
target_b="${HOME}/selftest-canary-b-${nonce}"
rm -rf "$scratch" "$target_a" "$target_b"
mkdir -p "$scratch/.lake"
cp lean-toolchain "$scratch/lean-toolchain"
cat > "$scratch/lakefile.toml" <<'TOML'
name = "selftest"
defaultTargets = ["SelfTest"]

[[lean_lib]]
name = "SelfTest"
TOML
# Unquoted heredoc: the two target paths and the sentinel are expanded
# into the source at generation time. Keep the body free of $ and
# backticks so nothing else is expanded.
cat > "$scratch/SelfTest.lean" <<LEAN
import Lean.Elab.Command

namespace SelfTest

private def targets : Array String :=
  #["${target_a}", "${target_b}"]

private def tryWrite (target : String) : IO Bool := do
  try
    IO.FS.writeFile (System.FilePath.mk target) "sandbox self-test write"
    return true
  catch _ =>
    return false

private def attemptEscape : IO (Array String) := do
  let mut written : Array String := #[]
  for target in targets do
    if (← tryWrite target) then
      written := written.push target
  return written

end SelfTest

run_cmd do
  let written ← SelfTest.attemptEscape
  if written.isEmpty then
    throwError "SELFTEST_WRITES_DENIED_${nonce}"
  else
    IO.println "SELFTEST_WRITES_ACCEPTED_${nonce}"
LEAN
cat "$scratch/SelfTest.lean"

# 1. Resolve the toolchain the way the real run resolves it. The
#    comparator is launched as `lake env <comparator> <config>` (see
#    "Run comparator" below), so by the time it calls
#    osexec.LookPath("lake") its PATH already starts with
#    <leanPrefix>/bin: the binary it sandboxes is the TOOLCHAIN lake,
#    which its own `--rox <leanPrefix>` rule covers, and so is
#    everything that lake goes on to exec.
#
#    This matters because landrun's `-add-exec` adds only the ONE
#    resolved command binary to --rox (cmd/landrun/main.go at the
#    pinned LANDRUN_REF: `binary, err := osexec.LookPath(args[0])`,
#    then `readOnlyExecutablePaths = append(..., binary)` under
#    `if c.Bool("add-exec")`). `--ro /` grants read, never exec. An
#    earlier version of this step left PATH alone, so args[0]
#    resolved to the elan shim at ~/.elan/bin/lake; the shim was
#    execable, the toolchain lake it proxies to was not, and the run
#    died in 17ms with `Permission denied (os error 13)` before
#    reaching any elaboration — which the "certifies nothing" gate
#    below correctly failed the job on. Name the toolchain binary
#    explicitly and put its bin dir first, as `lake env` does.
lean_prefix="$(cd "$scratch" && lean --print-prefix)"
lake_bin="${lean_prefix}/bin/lake"
if [ ! -x "$lake_bin" ]; then
  echo "no lake at ${lake_bin}: the toolchain layout changed, and resolving lake through"
  echo "PATH would sandbox the elan shim instead of the binary it proxies to."
  exit 1
fi
git_location="$(command -v git)"
sandbox_path="${lean_prefix}/bin:${PATH}"
echo "self-test toolchain: ${lake_bin}"

# 2. Positive control, unsandboxed, with the same binary and the same
#    PATH as the sandboxed run below, so the sandbox is the only
#    difference between them. Without this control the sandboxed run
#    cannot distinguish "the writes were refused" from "the fixture
#    never attempted them".
pos="${RUNNER_TEMP}/selftest-unsandboxed.log"
set +e
( cd "$scratch" && PATH="$sandbox_path" LEAN_ABORT_ON_PANIC=1 \
    "$lake_bin" build SelfTest ) > "$pos" 2>&1
pos_rc=$?
set -e
cat "$pos"
if [ ! -e "$target_a" ] || [ ! -e "$target_b" ]; then
  echo "self-test positive control failed (exit ${pos_rc}): the probe did not write both targets"
  echo "outside any sandbox, so a later denial would prove nothing."
  exit 1
fi
if ! grep -q "SELFTEST_WRITES_ACCEPTED_${nonce}" "$pos"; then
  echo "self-test positive control failed: the acceptance sentinel was not emitted"
  exit 1
fi
rm -f "$target_a" "$target_b"
echo "self-test positive control: both writes succeeded outside the sandbox"

# 3. The same bytes, through the full wrapper. Clearing .lake/build is
#    what forces re-elaboration: a warm build directory is exactly how
#    CX-012 turned the sandboxed build into a no-op. lake-manifest.json
#    and .lake itself stay, as they do in the real project checkout.
#    PATH is set on systemd-run rather than only forwarded, because
#    landrun resolves args[0] against its OWN environment before
#    applying the sandbox.
rm -rf "$scratch/.lake/build"
sand="${RUNNER_TEMP}/selftest-sandboxed.log"
set +e
systemd-run --user --pipe --wait --collect \
  -p RestrictAddressFamilies=~AF_UNIX \
  --working-directory "$scratch" \
  -E PATH="$sandbox_path" \
  -E HOME="$HOME" \
  -E LEAN_ABORT_ON_PANIC=1 \
  -- "$COMPARATOR_LANDRUN" --best-effort --ro / --rw /dev -ldd -add-exec \
       --env PATH --env HOME --env LEAN_ABORT_ON_PANIC \
       --ro "$scratch" --rwx "$scratch/.lake" \
       --rox "$lean_prefix" --rox "$git_location" \
       -- "$lake_bin" build SelfTest > "$sand" 2>&1
sand_rc=$?
set -e
cat "$sand"
for target in "$target_a" "$target_b"; do
  if [ -e "$target" ]; then
    echo "SANDBOX BREACH: the pre-run self-test wrote ${target} from inside the sandbox"
    exit 1
  fi
done
if [ "$sand_rc" -eq 0 ]; then
  echo "SANDBOX BREACH: the pre-run self-test elaborated successfully inside the sandbox"
  exit 1
fi
if grep -q "SELFTEST_WRITES_ACCEPTED_${nonce}" "$sand"; then
  echo "SANDBOX BREACH: the pre-run self-test reported an accepted write inside the sandbox"
  exit 1
fi
if ! grep -q "SELFTEST_WRITES_DENIED_${nonce}" "$sand"; then
  echo "the sandboxed self-test failed without reaching the write attempt (exit ${sand_rc}):"
  echo "no containment conclusion can be drawn, so this run certifies nothing."
  echo "if the log shows a permission error on exec rather than on a write, the ruleset"
  echo "no longer covers the toolchain this step resolved (${lake_bin}); compare it against"
  echo "buildLandrunArgs / safeLakeBuild in the pinned comparator before touching the gates."
  exit 1
fi
echo "pre-run self-test OK: elaboration-time writes denied inside the sandbox (exit ${sand_rc})"
jq -n --arg tier "pre-run-trusted" --argjson rc "$sand_rc" \
      --arg a "$target_a" --arg b "$target_b" \
  '{tier: $tier, exit_code: $rc, denied: true, sentinel_observed: true, targets: [$a, $b]}' \
  > "${RUNNER_TEMP}/selftest.json"
rm -rf "$scratch"
