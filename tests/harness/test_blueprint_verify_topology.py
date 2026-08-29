"""Static contract tests for the reusable consumer workflows.

``.github/workflows/blueprint-verify.yml`` and ``blueprint-deploy.yml`` are the
one CI pipeline every blueprint consumer runs, dispatched into repositories this
one cannot see. Nothing in a consumer's tree can hold them to their shape, and a
regression here is only visible on a run against a real project — by which point
a `contents: write` token has already been minted for it. So the properties the
codex-audit findings bought are asserted HERE, textually, in the harness suite
that gates every push.

What each test corresponds to:

* **CX-012** — the trust-boundary topology. The job that elaborates untrusted
  Lean holds `contents: read` and nothing else; the only jobs that can write are
  the ones that run no untrusted code; no job in the verify workflow holds a
  Pages scope or an OIDC token at all.
* **CX-079** — one deploy predicate. The finding was that the value handed to
  the trust-provenance gate and the value deciding whether a run deploys were
  two spellings that could not share a reference, so a text assertion held them
  together. Under a reusable workflow the predicate is a job OUTPUT, which *can*
  be referenced: these tests assert that every reader reads that one output and
  that no literal survives. That is a strengthening of the property, not a drop
  of it — the original assertion is gone because what it guarded is gone.
* **CX-048/049/050/051** — the sandbox evidence chain runs, in order, from
  scripts that exist.
* **CX-052/064** — the record validator and the checker-identity pin are called
  with the arguments that make them do their job.
* **CX-039** — a referenced script must exist (the reusable-workflow half of
  ``test_workflow_topology.py``, which deliberately skips ``workflow_call``
  files because their *consumer-side* paths cannot be resolved here; the
  ``ci/scripts/`` paths can be, because they are ours).

Parsed textually rather than with PyYAML: the harness has no third-party
dependencies and the CI ``harness-tests`` job runs under the runner's bare
``python3``. The constructs inspected (a two-space ``jobs:`` mapping, a
four-space ``permissions:`` block, ``- name:`` step headers) are simple enough to
read directly, and the parse itself is asserted by
``test_the_parser_found_the_expected_jobs``.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = PACKAGE_ROOT / ".github" / "workflows"
VERIFY = WORKFLOWS / "blueprint-verify.yml"
DEPLOY = WORKFLOWS / "blueprint-deploy.yml"

# The one spelling of the deploy predicate that any reader may use.
DEPLOYABLE_REF = "needs.publish.outputs.deployable"

# Verifier pins that must be present, and 40-hex, in the reusable workflow's own
# `env:`. A consumer that could choose these would be asserting them against
# itself; a pin that is not a full commit is not a pin.
PINNED_40HEX = ("LANDRUN_REF", "NANODA_REF", "COMPARATOR_TOOL_SHA", "LEAN4EXPORT_REF",
                "FORMALIZATION_SCHEMA_REF")


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _job_blocks(text: str) -> dict[str, str]:
    """``{job_id: block}`` for the workflow's top-level ``jobs:`` mapping.

    A job id is a two-space-indented key inside ``jobs:``; its block runs to the
    next such key (or to the end of the file).
    """
    lines = text.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if re.match(r"^jobs:\s*$", line))
    except StopIteration:  # pragma: no cover - a workflow with no jobs
        return {}
    blocks: dict[str, list[str]] = {}
    current: str | None = None
    for line in lines[start + 1:]:
        header = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if header:
            current = header.group(1)
            blocks[current] = []
            continue
        if re.match(r"^\S", line) and line.strip() and not line.startswith("#"):
            break  # a new top-level key ends `jobs:`
        if current is not None:
            blocks[current].append(line)
    return {name: "\n".join(body) for name, body in blocks.items()}


def _permissions(block: str) -> dict[str, str]:
    """The job's own ``permissions:`` mapping."""
    match = re.search(r"^    permissions:\s*$\n((?:^      \S.*$\n?)*)", block, re.MULTILINE)
    if not match:
        return {}
    out = {}
    for line in match.group(1).splitlines():
        entry = re.match(r"^      ([a-z-]+):\s*([a-z]+)", line)
        if entry:
            out[entry.group(1)] = entry.group(2)
    return out


def _step_names(block: str) -> list[str]:
    return [m.group(1).strip() for m in re.finditer(r"^      - name: (.+?)\s*$", block, re.MULTILINE)]


class WorkflowParseTests(unittest.TestCase):
    """Guard the guard: every assertion below rests on this parse."""

    def test_the_parser_found_the_expected_jobs(self) -> None:
        self.assertEqual(
            list(_job_blocks(_read(VERIFY))),
            ["build", "comparator", "publish", "site-contents", "site-generate", "site-release"],
        )
        self.assertEqual(list(_job_blocks(_read(DEPLOY))), ["verify", "deploy"])

    def test_every_job_declares_its_own_permissions(self) -> None:
        for workflow in (VERIFY, DEPLOY):
            for name, block in _job_blocks(_read(workflow)).items():
                self.assertTrue(
                    _permissions(block),
                    msg=f"{workflow.name}:{name} declares no `permissions:` of its own; it would "
                        "inherit whatever the caller granted, which is the concentration the "
                        "job split exists to avoid (CX-012).",
                )


class TrustBoundaryTopologyTests(unittest.TestCase):
    """CX-012: who may run untrusted code, and who may write."""

    def setUp(self) -> None:
        self.jobs = _job_blocks(_read(VERIFY))

    def test_the_comparator_job_is_read_only(self) -> None:
        # This is the job that elaborates code the comparator's threat model
        # treats as hostile.
        self.assertEqual(_permissions(self.jobs["comparator"]), {"contents": "read"})

    def test_only_publish_and_site_release_can_write(self) -> None:
        writers = {
            name for name, block in self.jobs.items()
            if _permissions(block).get("contents") == "write"
        }
        self.assertEqual(writers, {"publish", "site-release"})

    def test_no_job_requests_actions_write(self) -> None:
        """A caller grants `contents: write` and `actions: read`, and nothing more.

        A reusable workflow cannot raise its caller's grant: a job asking for a
        scope the caller does not hold fails the whole run at STARTUP, before any
        step. lean_quine's first live run failed exactly there -- "The nested job
        'site-release' is requesting 'actions: write', but is only allowed
        'actions: read'" -- because the deploy signal was `gh workflow run`, an
        Actions API call. It is a repository_dispatch now, which is a
        contents-scope call. Nothing here may reintroduce the larger grant: "may
        start any workflow in this repository" is not what this pipeline needs.
        """
        for name, block in self.jobs.items():
            self.assertNotEqual(
                _permissions(block).get("actions"), "write",
                msg=f"{name} requests `actions: write`; no consumer's thin caller grants it, "
                    f"so the run would fail at startup. The deploy signal is a "
                    f"repository_dispatch (contents scope), not `gh workflow run`.",
            )

    def test_the_deploy_signal_is_a_repository_dispatch(self) -> None:
        """The signal and the permission are one decision; assert them together.

        `POST /repos/{repo}/dispatches` needs `contents: write`, which site-release
        already holds for the release and the pin commit-back. GitHub starts runs
        for `repository_dispatch` and `workflow_dispatch` even when the event was
        created with a GITHUB_TOKEN -- the documented exception to the rule that
        keeps a token's own push from re-triggering CI.
        """
        block = self.jobs["site-release"]
        # Comments stripped: the step's own comment explains what it is NOT, and
        # an assertion that reads prose as code would fail on the explanation.
        code = "\n".join(
            line for line in block.splitlines() if not line.lstrip().startswith("#")
        )
        self.assertIn("repos/${GITHUB_REPOSITORY}/dispatches", code)
        self.assertIn("event_type=blueprint-site-pin", code)
        self.assertNotIn(
            "gh workflow run", code,
            msg="the deploy signal is back on the Actions API, which needs `actions: write`",
        )

    def test_the_verify_workflow_holds_no_pages_scope_and_no_oidc(self) -> None:
        # Deploying lives in blueprint-deploy.yml precisely so that the workflow
        # holding `contents: write` never holds a Pages token or an OIDC token.
        for name, block in self.jobs.items():
            perms = _permissions(block)
            self.assertNotIn("pages", perms, msg=f"{name} declares a Pages scope")
            self.assertNotIn("id-token", perms, msg=f"{name} declares an OIDC scope")

    def test_the_workflow_takes_no_secrets(self) -> None:
        text = _read(VERIFY)
        self.assertNotRegex(
            text, r"^\s{4}secrets:",
            msg="blueprint-verify.yml declares a `secrets:` block. Nothing in the pipeline "
                "needs one, and omitting it is what keeps the untrusted comparator job "
                "provably secret-free.",
        )
        self.assertNotIn("secrets.", text)

    def test_the_untrusted_job_runs_the_containment_chain_in_order(self) -> None:
        names = _step_names(self.jobs["comparator"])
        # CX-048: the AF_UNIX guard is a gate, and it runs before ANY checkout —
        # nothing untrusted is elaborated in this job without it.
        self.assertEqual(names[0], "Free up disk space")
        self.assertEqual(names[2], "Assert the AF_UNIX guard is available")
        for earlier, later in (
            # CX-049 then CX-050/051 then the certified run, in that order.
            ("Landlock sandbox self-test", "Trusted pre-run sandbox self-test"),
            ("Trusted pre-run sandbox self-test", "Hash the verification inputs (before)"),
            ("Hash the verification inputs (before)", "Run comparator"),
            ("Run comparator", "Hash the verification inputs (after)"),
            ("Hash the verification inputs (after)", "Denied-write probe (defense in depth)"),
            ("Denied-write probe (defense in depth)", "Compose the comparator result record"),
        ):
            self.assertLess(
                names.index(earlier), names.index(later),
                msg=f"`{earlier}` must run before `{later}`",
            )

    def test_the_certified_step_keeps_the_name_the_deep_link_resolves(self) -> None:
        # The publish job finds the comparator page's "View CI run" link by
        # looking this step up BY NAME across the run's jobs. Renaming it
        # silently demotes every published link to the run summary.
        self.assertIn("Run comparator", _step_names(self.jobs["comparator"]))
        self.assertIn('.name == "Run comparator"', self.jobs["publish"])


class DeployPredicateTests(unittest.TestCase):
    """CX-079: one predicate, computed once, read by reference."""

    def setUp(self) -> None:
        self.text = _read(VERIFY)
        self.jobs = _job_blocks(self.text)

    def test_publish_declares_the_predicate_as_a_job_output(self) -> None:
        self.assertIsNotNone(
            re.search(r"^    outputs:\s*$", self.jobs["publish"], re.MULTILINE),
            "the publish job declares no outputs",
        )
        self.assertIsNotNone(
            re.search(
                r"^      deployable: \$\{\{ steps\.deployable\.outputs\.deployable \}\}\s*$",
                self.jobs["publish"], re.MULTILINE,
            ),
            "the publish job does not export the predicate as `deployable`",
        )

    def test_the_gate_reads_the_predicate_by_reference(self) -> None:
        declarations = re.findall(r"^\s*DEPLOYABLE:\s*(.+?)\s*$", self.text, re.MULTILINE)
        self.assertEqual(
            len(declarations), 1,
            msg=f"expected exactly one DEPLOYABLE declaration, found {len(declarations)}",
        )
        self.assertIn(
            DEPLOYABLE_REF, declarations[0],
            msg="the value handed to the trust-provenance gate is not the publish job's "
                "`deployable` output. Under CX-079 this was two spellings held together by "
                "a text assertion; it is now one output, and every reader must read it.",
        )

    def test_site_release_gates_on_the_same_output(self) -> None:
        self.assertIn(f"{DEPLOYABLE_REF} == 'true'", self.jobs["site-release"])

    def test_no_reader_recomputes_the_predicate(self) -> None:
        # The two ways the old design spelled it. Either reappearing means a
        # second source of truth about whether a run can publish.
        for job in ("site-generate", "site-release"):
            self.assertNotIn(
                "github.event_name != 'pull_request'", self.jobs[job],
                msg=f"{job} recomputes the deploy predicate instead of reading "
                    f"{DEPLOYABLE_REF}",
            )

    def test_the_predicate_is_computed_from_the_event_once(self) -> None:
        compute = self.jobs["publish"]
        self.assertIn('id: deployable', compute)
        self.assertIn('GITHUB_EVENT_NAME" = "pull_request"', compute)


class CiCodeIdentityTests(unittest.TestCase):
    """`job.workflow_sha`: which CI code ran, asserted and recorded."""

    def setUp(self) -> None:
        self.verify_jobs = _job_blocks(_read(VERIFY))
        self.deploy_jobs = _job_blocks(_read(DEPLOY))

    def test_every_job_that_names_the_ci_code_asserts_the_caller_pin(self) -> None:
        # Including `site-release`, which runs no CI script but stamps
        # `job.workflow_sha` into a commit trailer.
        for workflow, jobs in ((VERIFY, self.verify_jobs), (DEPLOY, self.deploy_jobs)):
            for name, block in jobs.items():
                if name == "deploy":
                    continue  # deploy-pages only; it reads nothing from the tree
                self.assertIn(
                    "Assert the CI-code pin", block,
                    msg=f"{workflow.name}:{name} never asserts the caller's stated pin",
                )
                self.assertIn("SHOWCASE_SHA: ${{ inputs.showcase_sha }}", block)
                self.assertIn("WORKFLOW_SHA: ${{ job.workflow_sha }}", block)

    def test_every_job_that_runs_a_ci_script_checks_it_out_at_its_own_commit(self) -> None:
        for workflow, jobs in ((VERIFY, self.verify_jobs), (DEPLOY, self.deploy_jobs)):
            for name, block in jobs.items():
                if "$CI_DIR" not in block:
                    continue
                self.assertIn(
                    "repository: ${{ job.workflow_repository }}", block,
                    msg=f"{workflow.name}:{name} runs a CI script without checking the CI code out",
                )
                self.assertIn(
                    "ref: ${{ job.workflow_sha }}", block,
                    msg=f"{workflow.name}:{name} checks the CI code out at something other "
                        "than the commit that defines this job. `github.workflow_sha` names "
                        "the CALLER's workflow, which is not what runs here.",
                )

    def test_the_ci_code_is_staged_out_of_the_consumer_workspace(self) -> None:
        # A Showcase checkout left inside a consumer's tree is not inert: it
        # carries a lakefile and Lean sources, so the declaration registry's
        # source-path scan can take it for a sibling package root, and
        # package_site.sh would call the worktree dirty.
        for workflow, jobs in ((VERIFY, self.verify_jobs), (DEPLOY, self.deploy_jobs)):
            for name, block in jobs.items():
                if "path: _showcase" not in block:
                    continue
                self.assertIn(
                    "rm -rf _showcase", block,
                    msg=f"{workflow.name}:{name} leaves _showcase/ in the consumer workspace",
                )

    def test_the_record_carries_the_ci_code_identity(self) -> None:
        publish = self.verify_jobs["publish"]
        for flag in ("--workflow-repository", "--workflow-ref", "--workflow-sha"):
            self.assertIn(
                flag, publish,
                msg=f"the record validator is not given {flag}; a record forged by any "
                    "workflow anywhere would carry exactly the fields the old validator checked",
            )

    def test_bot_commits_name_the_ci_code_and_no_model(self) -> None:
        text = _read(VERIFY)
        self.assertNotIn(
            "Co-Authored-By", text,
            msg="a machine-authored commit-back must not name a model as co-author; the "
                "trailer is `Generated-By: showcase-ci <workflow_sha>`",
        )
        trailers = re.findall(r"Generated-By: showcase-ci \$\{WORKFLOW_SHA\}", text)
        self.assertEqual(len(trailers), 2, msg="expected the status and pin commit-backs to "
                                               "carry the Generated-By trailer")
        self.assertEqual(text.count('git config user.name "github-actions[bot]"'), 2)


class PinnedVerifierTests(unittest.TestCase):
    """The verifier pins are the workflow's, not a consumer's."""

    def setUp(self) -> None:
        self.text = _read(VERIFY)
        self.env = re.search(r"^env:\s*$\n((?:^(?:  \S.*|  #.*|)$\n)*)", self.text, re.MULTILINE)

    def test_the_pins_live_in_the_workflow_env(self) -> None:
        self.assertIsNotNone(self.env, "blueprint-verify.yml declares no top-level env:")
        block = self.env.group(1)
        for key in PINNED_40HEX:
            match = re.search(r'^  %s: "([0-9a-f]+)"' % key, block, re.MULTILINE)
            self.assertIsNotNone(match, msg=f"{key} is not pinned in the workflow's env:")
            self.assertEqual(
                len(match.group(1)), 40,
                msg=f"{key} is not a full 40-character commit; a tag or a short SHA is a "
                    "mutable pointer, and what a consumer certifies must not change because "
                    "someone upstream moved one",
            )

    def test_no_pin_is_a_consumer_input(self) -> None:
        inputs = re.search(r"^    inputs:\s*$\n(.*?)^    outputs:", self.text,
                           re.MULTILINE | re.DOTALL)
        self.assertIsNotNone(inputs)
        for key in PINNED_40HEX + ("COMPARATOR_TOOL_REF", "NANODA_REPOSITORY"):
            self.assertNotIn(
                key.lower(), inputs.group(1),
                msg=f"{key} is exposed as a consumer input. In `lake-dep` mode the effective "
                    "pin is the consumer's own manifest, so the constant's whole job is to be "
                    "asserted against it — a consumer that chose it would assert it against "
                    "itself.",
            )

    def test_every_third_party_action_is_pinned_by_commit(self) -> None:
        for workflow in (VERIFY, DEPLOY):
            for match in re.finditer(r"^\s*uses: ([^\s#]+)", _read(workflow), re.MULTILINE):
                ref = match.group(1)
                self.assertRegex(
                    ref, r"@[0-9a-f]{40}$",
                    msg=f"{workflow.name} uses `{ref}`, which is not pinned to a commit. "
                        "A marketplace major-version tag is a promise about compatibility, "
                        "not about code.",
                )


class DeployWorkflowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = _read(DEPLOY)
        self.jobs = _job_blocks(self.text)

    def test_the_environment_is_declared_inside_the_reusable_workflow(self) -> None:
        # actions/deploy-pages fails without it, and a caller cannot forget what
        # it does not have to write.
        self.assertIsNotNone(
            re.search(r"^    environment:\s*$", self.jobs["deploy"], re.MULTILINE),
            "the deploy job declares no `environment:`; actions/deploy-pages fails without it",
        )
        self.assertIn("name: github-pages", self.jobs["deploy"])

    def test_the_digest_is_checked_before_a_byte_is_unpacked(self) -> None:
        names = _step_names(self.jobs["verify"])
        self.assertLess(
            names.index("Refuse the asset unless its digest is the pinned one"),
            names.index("Unpack"),
            msg="the pinned digest must be verified before the tarball is opened; nothing "
                "below may read a byte the pin did not vouch for",
        )
        self.assertLess(
            names.index("Unpack"),
            names.index("Authenticate the build against this checkout"),
        )

    def test_only_the_deploy_job_holds_the_oidc_token(self) -> None:
        self.assertNotIn("id-token", _permissions(self.jobs["verify"]))
        self.assertEqual(
            _permissions(self.jobs["deploy"]), {"pages": "write", "id-token": "write"},
        )

    def test_deployment_is_confined_to_the_publish_branch(self) -> None:
        self.assertIn("github.ref_name == inputs.publish_branch", self.jobs["deploy"])


class GateOrderingTests(unittest.TestCase):
    """The gates run early, and the pin is a pin.

    (That every ``ci/scripts/...`` reference RESOLVES is CX-039's general rule
    and lives in ``test_workflow_topology.py``. What is asserted here is that
    this pipeline calls them in the order that makes them worth calling.)
    """

    def test_the_gate_fixtures_run_before_anything_expensive(self) -> None:
        build = _job_blocks(_read(VERIFY))["build"]
        names = _step_names(build)
        for fixture_step in (
            "Test the comparator result validator against forged records",
            "Test the status-record change detector",
            "Test the trust-provenance gate against forged records",
            "Test the site-release gate against forged builds",
        ):
            self.assertIn(fixture_step, names)
            self.assertLess(
                names.index(fixture_step), names.index("Set up Lean and build the subject"),
                msg=f"`{fixture_step}` must run before the build: the rejection behaviour of "
                    "a gate that decides what gets published is checked in seconds, before "
                    "anything expensive.",
            )

    def test_the_checker_identity_pin_is_asserted_not_refreshed(self) -> None:
        # CX-064: a pin regenerated from the same run it is supposed to
        # authenticate agrees with it by construction and checks nothing.
        publish = _job_blocks(_read(VERIFY))["publish"]
        self.assertIn("Check the pinned checker identities", _step_names(publish))
        self.assertIn("never rewrites", publish)


if __name__ == "__main__":
    unittest.main()
