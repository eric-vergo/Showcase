#!/usr/bin/env bash
# Landlock sandbox self-test + loopback network canary (codex-audit CX-049).
#
# landrun is invoked with --best-effort, which silently degrades to no-sandbox on
# a Landlock-less kernel. This script turns that silent degradation into a hard
# failure: if the canary write is not denied, or a TCP connect is not denied, the
# runner image regressed and the run must not certify anything. Both controls use
# exactly the ruleset the comparator itself builds (filesystem rules only, no
# --unrestricted-*), under which go-landlock still handles the network domain
# and, with no ConnectTCP rule, denies every connect.
#
# Extracted VERBATIM from eric-vergo/OEIS-A362583-Irrationality
# .github/workflows/ci.yml (the `Landlock sandbox self-test` step), which is
# byte-identical to eric-vergo/HopfProblem's copy of it. The body below is the
# workflow step's `run:` script, dedented and otherwise unchanged.
#
# Environment: COMPARATOR_LANDRUN (the landrun binary), RUNNER_TEMP, HOME.
#
# Usage: bash ci/scripts/landlock_selftest.sh
set -euo pipefail
# Positive control: an allowed command must succeed under landrun.
"$COMPARATOR_LANDRUN" --best-effort --ro / --rw /dev -ldd -add-exec true
# Negative control: a write outside the allowed paths must be denied.
if "$COMPARATOR_LANDRUN" --best-effort --ro / --rw /dev -ldd -add-exec touch "$HOME/landlock-canary" 2>/dev/null; then
  echo "landrun failed to block a write outside the allowed paths"
  exit 1
fi
test ! -e "$HOME/landlock-canary"
# Network canary (codex-audit CX-049). The listener is started here, on
# loopback, so the assertion depends on nothing outside this runner: no
# DNS, no egress policy, no third-party endpoint whose availability can
# quietly remove a stated sandbox assertion. Both branches are hard
# failures — an unestablished positive control means landrun's denial
# was never exercised, which is not a green condition.
port=18923
mkdir -p "${RUNNER_TEMP}/canary-root"
python3 -m http.server "$port" --bind 127.0.0.1 --directory "${RUNNER_TEMP}/canary-root" \
  > "${RUNNER_TEMP}/canary-listener.log" 2>&1 &
listener_pid=$!
trap 'kill "$listener_pid" 2>/dev/null || true' EXIT
control=""
for _ in $(seq 1 50); do
  if curl -fsS --max-time 2 -o /dev/null "http://127.0.0.1:${port}/" 2>/dev/null; then
    control="up"
    break
  fi
  sleep 0.2
done
if [ -z "$control" ]; then
  echo "network canary positive control failed: the loopback listener never accepted a connection,"
  echo "so a denial inside the sandbox would prove nothing about landrun."
  cat "${RUNNER_TEMP}/canary-listener.log" || true
  exit 1
fi
echo "network canary: positive control connected unsandboxed"
if "$COMPARATOR_LANDRUN" --best-effort --ro / --rw /dev -ldd -add-exec \
     curl -fsS --max-time 5 -o /dev/null "http://127.0.0.1:${port}/" 2>/dev/null; then
  echo "landrun failed to block a TCP connect under a filesystem-only ruleset"
  exit 1
fi
echo "network canary: TCP connect denied inside the sandbox"
kill "$listener_pid" 2>/dev/null || true
wait "$listener_pid" 2>/dev/null || true
trap - EXIT
