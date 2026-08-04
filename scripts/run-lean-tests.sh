#!/usr/bin/env bash

set -euo pipefail

package_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$package_root"

# The Lean suite (`lake test`) is the retained verification surface. It covers the
# external-markup feature contract this fork actually supports via the
# tests/VersoBlueprintTests/BlueprintExternalMarkup.lean suite (metadata / inline /
# source-display). The former `python3 tests/integration/check_lean_run_external_markup.py`
# invocation was removed (CX-039): it exercised the generated external-markup *fragment*
# renderer that this fork deliberately dropped (CX-007), and the script is not tracked, so
# under `set -euo pipefail` it aborted the whole wrapper on a clean checkout. Re-porting the
# dropped fragment renderer is a separate feature decision, not a prerequisite here. The
# static path-resolver test (tests/harness/test_workflow_topology.py) fails if any workflow
# or wrapper again references a repository script that does not exist.
./scripts/lean-low-priority lake test
