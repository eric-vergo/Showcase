#!/usr/bin/env python3
"""Forged-record fixtures for ci/scripts/check_trust_provenance.py (CX-078, CX-079).

The publish job's provenance gate is what stands between a warm-cache site build
and a published evidence page bound to bytes nobody read (CX-075). An earlier
version of it re-hashed whatever the producer listed, which authenticates bytes
against the producer's own claims and nothing else: an unknown schema, an absent
or arbitrary generation revision, and a required role label attached to the
wrong configured file all passed (CX-078). A gate is only as good as the records
it refuses, so each fixture here is a provenance document that the weaker gate
waved through, and each test names the property it must be caught by.

The fixtures are self-contained: the stub comparator files are written into a
temporary tree by `setUpClass`, the digests baked into the JSON are the digests
of exactly those bytes, and the configuration they are checked against is
`lakefile-fixture.lean` next to them.

That last part is a deliberate change from the a362583 original, which checked
every case against the live `site/lakefile.lean`. This suite now lives in the CI
repository and is shared by every consumer, so it cannot read any one consumer's
tree. The coupling the original enforced -- that the consumer still configures
all four comparator options and still declares an `input_file` edge for each --
is not lost: the gate reads the CONSUMER's lakefile on every CI run, in the
site-generate job, against that consumer's own checkout, and reports a missing
option or edge as a violation there. What is checked here is that the gate
refuses what it must, which is the part fixtures can establish.

The second half is the CX-079 event matrix. Dirty provenance is admissible only
for an artifact that cannot deploy, so the matrix is keyed on the deploy
predicate rather than on the event name. The original also asserted that the
predicate handed to the gate was textually `deploy.if`; under the reusable
workflow the predicate is computed ONCE, as a job output
(`needs.publish.outputs.deployable`), read by both the gate and `site-release`,
so the two spellings CX-079 had to hold together no longer exist. What replaced
that assertion is `tests/harness/test_blueprint_verify_topology.py`, which holds
the workflow to the single-source form.

Run: python3 ci/scripts/tests/test_trust_provenance_gate.py
     python3 -m unittest discover -s ci/scripts/tests
"""

import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
CI_SCRIPTS = os.path.dirname(HERE)
sys.path.insert(0, CI_SCRIPTS)

import check_trust_provenance as gate  # noqa: E402

LAKEFILE = os.path.join(HERE, "lakefile-fixture.lean")

# The commit the fixtures stamp; the gate is handed this as the independently
# sampled generation revision.
COMMIT = "2222222222222222222222222222222222222222"

# The exact bytes the fixture digests were computed from, at the paths the site
# configures (relative to the site build's CWD, which is what the record uses).
STUBS = {
    "../comparator/comparator-status.json":
        '{\n  "status": "verified",\n  "theorem_names": ["Challenge.irrational_stub"]\n}\n',
    "../comparator/comparator.json":
        '{\n  "solution_module": "Solution",\n  "theorem_names": ["Challenge.irrational_stub"]\n}\n',
    "../comparator/Challenge.lean": "-- trust-provenance fixture: challenge stub\n",
    "../comparator/Solution.lean": "-- trust-provenance fixture: solution stub\n",
    "../formalization.yaml": 'version: "0.4"\n',
}


class GateFixtures(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="trust-provenance-")
        # The record's paths escape the site directory exactly as the real ones
        # do, so the fixture tree has to have a site directory to escape from.
        cls.root = os.path.join(cls.tmp, "site")
        os.makedirs(cls.root)
        for rel, text in STUBS.items():
            path = os.path.join(cls.root, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)
        with open(LAKEFILE, encoding="utf-8") as handle:
            cls.lakefile = handle.read()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def run_gate(self, fixture, deployable=True, event="push", revision=COMMIT):
        """Run the gate on a fixture and return (violations, printed output)."""
        with open(os.path.join(HERE, fixture), encoding="utf-8") as handle:
            record = json.load(handle)
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            violations = gate.check(
                record, self.lakefile, revision, deployable, event, self.root
            )
        return violations, buffer.getvalue()

    def assertRejected(self, fixture, needle, **kwargs):
        violations, _ = self.run_gate(fixture, **kwargs)
        self.assertTrue(violations, "{} was accepted".format(fixture))
        blob = " ".join("{} {}".format(w, m) for w, m in violations.items)
        self.assertIn(needle, blob)

    def assertAccepted(self, fixture, **kwargs):
        violations, _ = self.run_gate(fixture, **kwargs)
        if violations:
            self.fail(
                "{} was rejected: {}".format(
                    fixture,
                    "; ".join("{}: {}".format(w, m) for w, m in violations.items),
                )
            )

    # --- the honest record ------------------------------------------------

    def test_valid_record_passes(self):
        """The shape the current producer emits, against its configured inputs."""
        self.assertAccepted("provenance-valid.json")

    def test_valid_record_carries_a_generic_extra_role(self):
        """An extra role is allowed -- and is not one of the four obligations."""
        with open(os.path.join(HERE, "provenance-valid.json"), encoding="utf-8") as h:
            roles = {e["role"] for e in json.load(h)["inputs"]}
        self.assertIn("formalization-yaml", roles)
        self.assertTrue(set(gate.REQUIRED_ROLE_OPTIONS) < roles)

    # --- CX-078: record authentication ------------------------------------

    def test_future_schema_is_refused(self):
        """A document this gate has no checks for is not a document it may pass."""
        self.assertRejected("provenance-forged-schema.json", "authenticates version 1 only")

    def test_arbitrary_revision_is_refused(self):
        """A well-formed commit that is not the generating one."""
        self.assertRejected("provenance-forged-revision.json", "is not the one it was built from")

    def test_absent_revision_is_refused(self):
        """The case that used to print "site stamped an unrecorded commit" and exit 0."""
        self.assertRejected("provenance-forged-no-revision.json", "no 'buildRevision' key")

    def test_aliased_role_is_refused(self):
        """The `challenge` obligation discharged by the Solution's path and digest.

        Every digest in this record is honest and every required label is
        present: only the binding is wrong, which is exactly what a gate keyed on
        the set of role strings cannot see.
        """
        self.assertRejected("provenance-forged-alias.json", "does not discharge the obligation")

    def test_duplicate_role_is_refused(self):
        """Two records for one obligation leaves which one was used undecidable."""
        self.assertRejected("provenance-forged-duplicate.json", "records carry the role challenge")

    def test_malformed_digest_is_refused(self):
        """A digest that cannot be a digest is not a mismatch to report, it is a forgery."""
        self.assertRejected("provenance-forged-digest.json", "not 64 lowercase hex characters")

    def test_unexpected_record_key_is_refused(self):
        """A field this schema does not define must not ride along unexamined."""
        self.assertRejected("provenance-forged-unknown-key.json", "unexpected key 'verified'")

    def test_null_dirty_is_refused(self):
        """"Could not tell" is not "was clean", on any event."""
        self.assertRejected("provenance-forged-null-dirty.json", "has not established that it was")
        self.assertRejected(
            "provenance-forged-null-dirty.json", "has not established that it was",
            deployable=False, event="pull_request",
        )

    def test_changed_bytes_are_refused(self):
        """The original CX-075 check still holds: the file moved under the capture."""
        path = os.path.join(self.root, "../comparator/Challenge.lean")
        with open(path, encoding="utf-8") as handle:
            original = handle.read()
        try:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(original + "-- edited after the capture\n")
            self.assertRejected("provenance-valid.json", "and is")
        finally:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(original)

    def test_missing_file_is_refused(self):
        path = os.path.join(self.root, "../comparator/Solution.lean")
        with open(path, encoding="utf-8") as handle:
            original = handle.read()
        try:
            os.remove(path)
            self.assertRejected("provenance-valid.json", "cannot be read from this checkout")
        finally:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(original)

    def test_absent_recorded_input_that_now_exists_is_refused(self):
        """CX-077: a path the capture found nothing at, with something at it now."""
        with open(os.path.join(HERE, "provenance-valid.json"), encoding="utf-8") as h:
            record = json.load(h)
        for entry in record["inputs"]:
            if entry["role"] == "formalization-yaml":
                entry["sha256"] = ""
                entry["state"] = "absent"
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            violations = gate.check(record, self.lakefile, COMMIT, True, "push", self.root)
        self.assertTrue(violations)
        blob = " ".join(m for _, m in violations.items)
        self.assertIn("recorded as absent and exists in this checkout", blob)

    def test_required_role_recorded_as_absent_is_refused(self):
        """A comparator page cannot be evidence about a file that was not there."""
        with open(os.path.join(HERE, "provenance-valid.json"), encoding="utf-8") as h:
            record = json.load(h)
        for entry in record["inputs"]:
            if entry["role"] == "challenge":
                entry["sha256"] = ""
                entry["state"] = "absent"
        os.remove(os.path.join(self.root, "../comparator/Challenge.lean"))
        try:
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                violations = gate.check(record, self.lakefile, COMMIT, True, "push", self.root)
            blob = " ".join(m for _, m in violations.items)
            self.assertIn("cannot be evidence about a file that was not there", blob)
        finally:
            with open(os.path.join(self.root, "../comparator/Challenge.lean"), "w") as handle:
                handle.write(STUBS["../comparator/Challenge.lean"])

    # --- the configuration this gate binds to -----------------------------

    def test_configuration_supplies_all_four_comparator_inputs(self):
        """The gate's paths come from the lakefile, so the lakefile must supply them."""
        violations = gate.Violations()
        configured = gate.parse_configured_paths(self.lakefile, violations)
        self.assertFalse(violations.items, "the fixture lakefile stopped configuring an input")
        self.assertEqual(set(configured), set(gate.REQUIRED_ROLE_OPTIONS))

    def test_every_configured_input_has_a_lake_edge(self):
        """Every configured option carries the `input_file` edge Lake needs (CX-075)."""
        violations = gate.Violations()
        configured = gate.parse_configured_paths(self.lakefile, violations)
        gate.check_lake_input_edges(self.lakefile, configured, violations)
        self.assertFalse(
            violations.items,
            "; ".join("{}: {}".format(w, m) for w, m in violations.items),
        )

    def test_wrong_configured_path_is_refused(self):
        """Repoint an option and the honest record stops discharging its obligation.

        This is the consumer-side regression in miniature: the gate binds each
        role to the CONFIGURED path, so moving one without moving the record is a
        refusal rather than a silently different page.
        """
        moved = self.lakefile.replace(
            '"../comparator/Challenge.lean"', '"../comparator/Challenge2.lean"'
        )
        self.assertNotEqual(moved, self.lakefile)
        with open(os.path.join(HERE, "provenance-valid.json"), encoding="utf-8") as h:
            record = json.load(h)
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            violations = gate.check(record, moved, COMMIT, True, "push", self.root)
        blob = " ".join(m for _, m in violations.items)
        self.assertIn("does not discharge the obligation", blob)

    # --- CX-079: the event matrix -----------------------------------------
    #
    # Keyed on deployability, not on the event name. `deployable` is exactly the
    # value `deploy.if` evaluates to, which test_deploy_predicate_is_coupled
    # holds the workflow to.

    def test_clean_deployable_run_passes(self):
        self.assertAccepted("provenance-valid.json", deployable=True, event="push")

    def test_dirty_deployable_push_is_refused(self):
        self.assertRejected(
            "provenance-dirty.json", "can deploy", deployable=True, event="push"
        )

    def test_dirty_deployable_dispatch_is_refused(self):
        """The CX-079 witness: dispatch is deployable, so it owes a clean tree."""
        self.assertRejected(
            "provenance-dirty.json", "can deploy",
            deployable=True, event="workflow_dispatch",
        )

    def test_dirty_nondeploying_pull_request_is_allowed_and_says_so(self):
        """The refreshed status file is deliberately uncommitted on a PR."""
        violations, output = self.run_gate(
            "provenance-dirty.json", deployable=False, event="pull_request"
        )
        self.assertFalse(violations.items)
        self.assertIn("does not deploy", output)

    def test_clean_nondeploying_run_passes(self):
        self.assertAccepted("provenance-valid.json", deployable=False, event="pull_request")

    def test_no_deployable_event_is_admitted_with_dirty_provenance(self):
        """The obligation stated directly, over every event the workflow declares."""
        for event in ("push", "pull_request", "workflow_dispatch"):
            for deployable in (True, False):
                violations, _ = self.run_gate(
                    "provenance-dirty.json", deployable=deployable, event=event
                )
                if deployable:
                    self.assertTrue(
                        violations,
                        "dirty provenance accepted on a deployable {} run".format(event),
                    )

    def test_the_fixture_lakefile_is_a_complete_configuration(self):
        """The fixture must configure all four roles and declare all four edges.

        Not a consumer coupling -- a fixture coupling. If this file stopped
        configuring an option, every "accepted" case below would start passing
        for the wrong reason (a role the gate never required).
        """
        violations = gate.Violations()
        configured = gate.parse_configured_paths(self.lakefile, violations)
        gate.check_lake_input_edges(self.lakefile, configured, violations)
        self.assertFalse(
            violations.items,
            "; ".join("{}: {}".format(w, m) for w, m in violations.items),
        )
        self.assertEqual(set(configured), set(gate.REQUIRED_ROLE_OPTIONS))

    def test_a_lakefile_that_stops_configuring_a_role_is_reported(self):
        """The consumer-side regression the gate exists to catch, on every run."""
        dropped = self.lakefile.replace(
            '\u27e8`weak.verso.blueprint.trust.solutionFile, "../comparator/Solution.lean"\u27e9,\n',
            "",
        )
        self.assertNotEqual(dropped, self.lakefile)
        violations = gate.Violations()
        gate.parse_configured_paths(dropped, violations)
        blob = " ".join(m for _, m in violations.items)
        self.assertIn("no verso.blueprint.trust.solutionFile option is set", blob)

    def test_a_configured_role_without_a_lake_edge_is_reported(self):
        """CX-075's convenience half: an option with no `input_file` is a
        warm-replay window, and the gate has to say so."""
        no_edge = self.lakefile.replace(
            'input_file comparatorChallenge where\n  path := "../comparator/Challenge.lean"\n',
            "",
        )
        self.assertNotEqual(no_edge, self.lakefile)
        violations = gate.Violations()
        configured = gate.parse_configured_paths(no_edge, violations)
        gate.check_lake_input_edges(no_edge, configured, violations)
        blob = " ".join(m for _, m in violations.items)
        self.assertIn("has no `input_file` target", blob)


if __name__ == "__main__":
    unittest.main(verbosity=2)
