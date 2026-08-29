#!/usr/bin/env python3
"""Forged-build fixtures for ci/scripts/check_site_release.py.

The Pages deploy workflow publishes the PINNED release asset, not whatever the
last run uploaded. What stands between "an operator uploaded a tarball" and "the
publish branch vouches for these bytes" is this gate, and a gate is only as good
as the trees it refuses. Each fixture here is a site that a hash-only check would
have published, and each test names the property it must be caught by:

  * the tarball's digest is not the pinned one (the operator uploaded something
    else, or the pin was edited by hand);
  * the tree was generated from a dirty worktree, or from a commit other than
    the pinned one, or from a commit that is not on the history being published;
  * an elaboration-time trust input (the comparator status record) changed on
    master after the site read it -- the published comparator page would quote a
    verdict master has replaced (the CX-075 property);
  * the declaration registry's source links name some other revision than the
    one the trust model promises (the CX-066 property);
  * the RENDERED HTML's project-local blob links name some other revision, with
    a current registry beside them -- the shape measured during the lean_quine
    adoption, where the comparator page's three "View on GitHub" links were baked
    at elaboration one commit behind and the registry-only gate passed;
  * a probe-and-degrade surface (the comparator page) is simply absent;
  * the pin is schema 1, or carries no `producer` block -- it names no CI code.

The fixtures are self-contained: a temporary git repository stands in for the
checkout, and the digests baked into the provenance record are the digests of
exactly the stub inputs written next to it.

The `--links-only` cases exercise the SAME functions through the entry point the
verify workflow's `Gates` step uses, which is the point of that mode: one
implementation, gated twice, rather than an inline copy in the workflow that
drifts from the script it was copied from.

Run: python3 ci/scripts/tests/test_check_site_release.py
     python3 -m unittest discover -s ci/scripts/tests
"""

import hashlib
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
CI_SCRIPTS = os.path.dirname(HERE)
sys.path.insert(0, CI_SCRIPTS)

import check_site_release  # noqa: E402

# The stub repository name is arbitrary; the digests depend on the stub bytes.
REPOSITORY = "eric-vergo/HopfProblem"

# A blob link into ANOTHER repository, at a revision that is deliberately never
# this build's: the gate must ignore it. Dependency checkouts (mathlib here) are
# pinned by the lockfile, so their revision is not ours to be stale about.
FOREIGN_REPOSITORY = "leanprover-community/mathlib4"
FOREIGN_REVISION = "a" * 40

# The two surfaces a real comparator page carries: project-local "View on GitHub"
# links composed at ELABORATION (Git.repositoryInfoAtRoot?), plus a link out to a
# dependency. Their revision is a parameter here precisely because it is a
# parameter in reality -- it is whatever HEAD was when the module was elaborated.
COMPARATOR_PAGE = """<html><body>
<a href="https://github.com/{repository}/blob/{revision}/comparator/Challenge.lean">View on GitHub</a>
<a href="https://github.com/{repository}/blob/{revision}/comparator/Solution.lean#L1-L20">View on GitHub</a>
<a href="https://github.com/{foreign_repository}/blob/{foreign_revision}/Mathlib/Init.lean">Mathlib</a>
</body></html>"""

PRODUCER = {
    "workflow_repository": "eric-vergo/Showcase",
    "workflow_ref": "eric-vergo/Showcase/.github/workflows/blueprint-verify.yml@refs/heads/blueprint",
    "workflow_sha": "3333333333333333333333333333333333333333",
    "run_id": "99999999999",
    "run_url": "https://github.com/eric-vergo/HopfProblem/actions/runs/99999999999",
}


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def git(repo, *args):
    return subprocess.run(
        ["git", "-C", repo] + list(args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        text=True,
    ).stdout.strip()


class Fixture:
    """A checkout, a generated tree, its tarball and its pin, all consistent."""

    def __init__(self, base):
        self.repo = os.path.join(base, "repo")
        os.makedirs(os.path.join(self.repo, "site", "trust"))
        os.makedirs(os.path.join(self.repo, "comparator"))
        self.inputs = {
            "../formalization.yaml": ("formalization-yaml", b"schema: v0.4\n"),
            "../comparator/comparator-status.json": ("comparator-status", b'{"status": "verified"}\n'),
        }
        for relative, (_role, content) in self.inputs.items():
            with open(os.path.join(self.repo, "site", relative), "wb") as handle:
                handle.write(content)
        git(self.repo, "init", "-q")
        git(self.repo, "-c", "user.name=t", "-c", "user.email=t@t", "add", ".")
        git(self.repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "subject")
        self.head = git(self.repo, "rev-parse", "HEAD")
        self.revision = self.head
        self.site = os.path.join(base, "html-multi")
        self.tarball = os.path.join(base, "site.tar.gz")
        self.pin = os.path.join(self.repo, "site", "trust", "site-build.json")

    def write_tree(self, revision=None, dirty=False, link_revision=None,
                   comparator_page=True, html_link_revision=None, html_links=True):
        revision = revision or self.revision
        link_revision = link_revision or revision
        # The HTML links and the registry links are sampled INDEPENDENTLY in
        # reality -- one at elaboration, one at emission -- so they are separate
        # parameters here, and either can be stale while the other is current.
        html_link_revision = html_link_revision or revision
        os.makedirs(os.path.join(self.site, "-verso-data"), exist_ok=True)
        os.makedirs(os.path.join(self.site, "Trust-model"), exist_ok=True)
        if comparator_page:
            os.makedirs(os.path.join(self.site, "comparator"), exist_ok=True)
            page = COMPARATOR_PAGE.format(
                repository=REPOSITORY if html_links else FOREIGN_REPOSITORY,
                revision=html_link_revision if html_links else FOREIGN_REVISION,
                foreign_repository=FOREIGN_REPOSITORY,
                foreign_revision=FOREIGN_REVISION,
            )
            self._write("comparator/index.html", page)
        self._write("index.html", "<html>index</html>")
        self._write("Trust-model/index.html", "<html>trust</html>")
        for index in range(8):
            self._write("chapter/{}.html".format(index), "<html>{}</html>".format(index))
        self._write("-verso-data/blueprint-manifest.json", "{}")
        registry = {
            "decls": [
                {
                    "name": "Mathoverflow1973.x",
                    "sourceHref": "https://github.com/{}/blob/{}/HopfProblem/A.lean#L1".format(
                        REPOSITORY, link_revision
                    ),
                }
            ]
        }
        self._write("-verso-data/decl-registry.json", json.dumps(registry))
        record = {
            "schemaVersion": 1,
            "buildRevision": {
                "commit": revision,
                "shortCommit": revision[:7],
                "dirty": dirty,
                "repositoryUrl": "https://github.com/" + REPOSITORY,
            },
            "inputs": [
                {"path": relative, "role": role, "sha256": sha256_bytes(content)}
                for relative, (role, content) in self.inputs.items()
            ],
        }
        self._write("-verso-data/trust-provenance.json", json.dumps(record))

    def _write(self, relative, text):
        path = os.path.join(self.site, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def package(self, revision=None, forge_sha=None, schema=2, producer=PRODUCER):
        revision = revision or self.revision
        with tarfile.open(self.tarball, "w:gz") as archive:
            archive.add(self.site, arcname="html-multi")
        with open(self.tarball, "rb") as handle:
            digest = sha256_bytes(handle.read())
        pin = {
            "schemaVersion": schema,
            "generationRevision": revision,
            "generatedAt": "2026-08-28T12:00:00Z",
            "release": {
                "tag": "site-20260828-" + revision[:7],
                "asset": "site-{}.tar.gz".format(revision[:7]),
                "sha256": forge_sha or digest,
                "bytes": os.path.getsize(self.tarball),
                "files": 13,
            },
            "pins": {
                "toolchain": "leanprover/lean4:v4.33.0",
                "VersoBlueprint": "9" * 40,
            },
        }
        if producer is not None:
            pin["producer"] = producer
        with open(self.pin, "w", encoding="utf-8") as handle:
            json.dump(pin, handle, indent=2)

    def add_page(self, relative, text):
        self._write(relative, text)

    def run_links_only(self, revision=None, repository=REPOSITORY):
        out = io.StringIO()
        argv = ["--links-only", "--site-root", self.site, "--repository", repository]
        if revision is not None:
            argv += ["--revision", revision]
        with redirect_stdout(out):
            code = check_site_release.main(argv)
        return code, out.getvalue()

    def run(self):
        out = io.StringIO()
        with redirect_stdout(out):
            code = check_site_release.main(
                [
                    "--pin", self.pin,
                    "--tarball", self.tarball,
                    "--site-root", self.site,
                    "--repo-root", self.repo,
                    "--head", self.head,
                    "--repository", REPOSITORY,
                    "--min-files", "5",
                ]
            )
        return code, out.getvalue()


class SiteReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="site-release-gate-")
        self.fixture = Fixture(self.tmp)

    def tearDown(self):
        import shutil

        shutil.rmtree(self.tmp, ignore_errors=True)

    def assertRefused(self, fragment):
        code, output = self.fixture.run()
        self.assertEqual(code, 1, output)
        self.assertIn("REFUSED", output)
        self.assertIn(fragment, output)

    def test_consistent_build_is_published(self):
        self.fixture.write_tree()
        self.fixture.package()
        code, output = self.fixture.run()
        self.assertEqual(code, 0, output)
        self.assertIn("is vouched for by", output)

    def test_forged_digest(self):
        self.fixture.write_tree()
        self.fixture.package(forge_sha="0" * 64)
        self.assertRefused("tarball: sha256")

    def test_dirty_worktree(self):
        self.fixture.write_tree(dirty=True)
        self.fixture.package()
        self.assertRefused("dirty")

    def test_revision_other_than_pinned(self):
        other = "f" * 40
        self.fixture.write_tree(revision=other, link_revision=other)
        self.fixture.package()  # pin names HEAD; the tree says `other`
        self.assertRefused("but the pin vouches for")

    def test_revision_not_on_history(self):
        other = "e" * 40
        self.fixture.write_tree(revision=other, link_revision=other)
        self.fixture.package(revision=other)  # pin and tree agree on a commit this history lacks
        self.assertRefused("is not on the history of")

    def test_trust_input_moved_on_master(self):
        self.fixture.write_tree()
        self.fixture.package()
        with open(os.path.join(self.fixture.repo, "comparator", "comparator-status.json"), "wb") as handle:
            handle.write(b'{"status": "failed"}\n')
        self.assertRefused("master has moved past this build")

    def test_stale_source_links(self):
        self.fixture.write_tree(link_revision="d" * 40)
        self.fixture.package()
        self.assertRefused("project-local source links do not name the generation")

    def test_missing_comparator_page(self):
        self.fixture.write_tree(comparator_page=False)
        self.fixture.package()
        self.assertRefused("tree: comparator/index.html is missing")

    # --- CX-066, second surface: the rendered HTML ---------------------------
    def test_stale_html_source_links_are_refused(self):
        """The lean_quine shape: a current registry beside a comparator page whose
        links were baked at elaboration, one commit back. This is what the
        registry-only gate published."""
        self.fixture.write_tree(html_link_revision="c" * 40)
        self.fixture.package()
        self.assertRefused("html source links:")

    def test_current_html_source_links_are_accepted_and_counted(self):
        self.fixture.write_tree()
        self.fixture.package()
        code, output = self.fixture.run()
        self.assertEqual(code, 0, output)
        self.assertIn("html source links: 2 project-local blob link(s) across 1 HTML page(s)", output)

    def test_foreign_repository_blob_links_are_ignored(self):
        """A dependency's blob link names a revision that is not ours and never
        will be; counting it would make the gate fail on every correct site."""
        self.fixture.write_tree()
        self.fixture.add_page(
            "chapter/deps.html",
            '<a href="https://github.com/{}/blob/{}/Mathlib/Order/Basic.lean">Mathlib</a>'.format(
                FOREIGN_REPOSITORY, "b" * 40
            ),
        )
        self.fixture.package()
        code, output = self.fixture.run()
        self.assertEqual(code, 0, output)
        self.assertIn("html source links: 2 project-local blob link(s)", output)

    def test_no_html_source_links_is_reported_not_refused(self):
        """Unlike the registry check, the HTML scan has no vacuity guard: a
        consumer may legitimately render no project-local blob link at all."""
        self.fixture.write_tree(html_links=False)
        self.fixture.package()
        code, output = self.fixture.run()
        self.assertEqual(code, 0, output)
        self.assertIn("html source links: none in the rendered HTML", output)

    # --- --links-only: the mode the verify workflow's Gates step invokes ------
    def test_links_only_accepts_a_consistent_tree(self):
        self.fixture.write_tree()
        code, output = self.fixture.run_links_only(self.fixture.revision)
        self.assertEqual(code, 0, output)
        self.assertIn("every project-local source link names " + self.fixture.revision, output)

    def test_links_only_refuses_stale_html(self):
        self.fixture.write_tree(html_link_revision="c" * 40)
        code, output = self.fixture.run_links_only(self.fixture.revision)
        self.assertEqual(code, 1, output)
        self.assertIn("source-link gate: REFUSED", output)
        self.assertIn("html source links:", output)

    def test_links_only_refuses_a_stale_registry(self):
        self.fixture.write_tree(link_revision="d" * 40)
        code, output = self.fixture.run_links_only(self.fixture.revision)
        self.assertEqual(code, 1, output)
        self.assertIn("project-local source links do not name the generation", output)
        self.assertIn("decl registry: 1 project-local source link(s)", output)

    def test_links_only_refuses_an_empty_registry_result(self):
        """The registry vacuity guard survives the split: a registry with no
        project-local link means the registry moved, not that there is nothing to
        check."""
        self.fixture.write_tree()
        self.fixture._write("-verso-data/decl-registry.json", json.dumps({"decls": []}))
        code, output = self.fixture.run_links_only(self.fixture.revision)
        self.assertEqual(code, 1, output)
        self.assertIn("the gate is vacuous", output)

    def test_links_only_without_a_revision_is_an_error(self):
        """A gate that ran with an empty revision would compare nothing and pass;
        the mode refuses to be invoked that way."""
        self.fixture.write_tree()
        with redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as raised:
                self.fixture.run_links_only(None)
        self.assertEqual(raised.exception.code, 2)

    # --- pin schema 2: WHICH run of WHICH CI code packaged this --------------
    def test_schema_1_pin_is_refused(self):
        """A pin this gate has no checks for is not a pin it may pass."""
        self.fixture.write_tree()
        self.fixture.package(schema=1)
        self.assertRefused("this gate understands exactly 2")

    def test_pin_without_a_producer_is_refused(self):
        """The tarball was built by a workflow in another repository; the pin has
        to name which commit of it, or `producer` establishes nothing."""
        self.fixture.write_tree()
        self.fixture.package(producer=None)
        self.assertRefused("the pin names no CI code")

    def test_pin_with_a_malformed_workflow_sha_is_refused(self):
        self.fixture.write_tree()
        forged = dict(PRODUCER, workflow_sha="333")
        self.fixture.package(producer=forged)
        self.assertRefused("producer.workflow_sha is not a full 40-hex commit")

    def test_pin_with_an_incomplete_producer_is_refused(self):
        self.fixture.write_tree()
        forged = dict(PRODUCER)
        del forged["run_url"]
        self.fixture.package(producer=forged)
        self.assertRefused("producer.run_url is missing")


if __name__ == "__main__":
    unittest.main(verbosity=2)
