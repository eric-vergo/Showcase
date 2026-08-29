#!/usr/bin/env python3
"""Run the status-record change detector's shell fixtures under unittest.

`test_comparator_status_unchanged.sh` is a shell suite because the thing it
tests is a shell script and the fixtures are jq derivations of one base record.
This wrapper exists so that `python3 -m unittest discover -s ci/scripts/tests`
runs every suite in this directory rather than three of the four -- a suite that
only runs when someone remembers to invoke it is a suite that stops running.

The workflow still invokes the shell file directly (in the trusted build job, in
seconds); this is the discovery path, not a replacement.
"""

import os
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SUITE = os.path.join(HERE, "test_comparator_status_unchanged.sh")


class ComparatorStatusDetectorShellSuite(unittest.TestCase):
    def test_shell_fixtures_pass(self):
        result = subprocess.run(
            ["bash", SUITE],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
            text=True,
        )
        self.assertEqual(
            result.returncode,
            0,
            "ci/scripts/tests/test_comparator_status_unchanged.sh failed:\n"
            + result.stdout,
        )
        # Guard the guard: a suite that silently stopped deriving fixtures would
        # exit 0 having checked nothing.
        self.assertIn("failure(s)", result.stdout)
        self.assertNotIn("0 check(s)", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
