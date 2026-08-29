#!/usr/bin/env python3
"""Authenticate a generated site's trust-provenance record before publishing it.

The blueprint's trust surfaces are captured at ELABORATION from four files Lake
does not otherwise track -- the comparator status artifact, its config, the
Challenge and the Solution -- and quoted into an `.olean`. Change only those and
rebuild, and a warm `site/.lake` republishes the entire prior evidence page
under the new build's revision, internally consistent and invisible on the page
(codex-audit CX-075). The generator re-reads and re-digests every recorded input
before emission and fails closed; this script is the same comparison run
independently by CI against the CHECKOUT, so a regression in the generator's own
gate does not take the check with it.

Running that comparison over whatever the producer happened to list, however,
authenticates bytes against the producer's own claims and nothing else
(codex-audit CX-078). Nothing below is taken from the record on faith:

  * the schema version must be exactly the one this script understands, and the
    document's shape must be exactly what that schema defines;
  * the revision the site stamped itself with must equal the revision CI
    independently sampled from the generating worktree -- passed in, never read
    back out of the record;
  * the dirty flag must be a real boolean, and must be false for any run that
    can deploy (codex-audit CX-079);
  * each of the four comparator roles must appear EXACTLY ONCE and name the
    canonical path this consumer configured, parsed here out of the consumer's
    site lakefile (`--lakefile`) rather than restated;
  * every recorded input, comparator role or not, is re-hashed against the
    checkout, including the ones the capture recorded as ABSENT -- a file that
    has since appeared at such a path is a stale transition like any other
    (codex-audit CX-077).

Additional generic trust roles (formalization.yaml, a Palomar bundle, a caveat
table) stay allowed under that same per-record schema, but a role label alone
can never satisfy one of the four comparator obligations.

This consumer publishes ONE comparator, so a role is required to be unique
outright. A multi-topic consumer would key the required set by `(topic, role)`
instead; that is a different contract and this script does not pretend to it.

Every violation is collected and printed; the exit status is 1 if there is any.

Python 3.9-compatible on purpose: it runs on the hosted runner and on the
maintainer's machine.

This is the one copy, shared by every consumer of the reusable workflow
(`.github/workflows/blueprint-verify.yml`, the site-generate job). Nothing in it
hard-codes a consumer's layout: the lakefile, the record and the root the
recorded paths resolve against all arrive as arguments.

Run: python3 ci/scripts/check_trust_provenance.py --help
"""

import argparse
import hashlib
import json
import os
import re
import sys

# The schema this script understands, exactly. It is `provenanceSchemaVersion`
# in the fork's `VersoBlueprint.TrustFreshness`. A fork that changes the document
# bumps that number, and this constant moves with it in a commit that also says
# what changed -- which is the point of pinning it rather than accepting "at
# least".
SUPPORTED_SCHEMA_VERSION = 1

# The exact document shape. Unknown keys are rejected as firmly as missing ones:
# a record shaped by a future producer must not slip a field past a gate that
# does not know to look at it.
DOCUMENT_KEYS = {"schemaVersion", "buildRevision", "inputs"}
REVISION_KEYS = {"commit", "shortCommit", "dirty", "repositoryUrl"}
# `state` and `topic` are written only when they have something to say (absent
# inputs, multi-topic comparators), so they are optional -- but nothing else is.
INPUT_REQUIRED_KEYS = {"role", "path", "sha256"}
INPUT_OPTIONAL_KEYS = {"state", "topic"}

# `Informal.TrustInputs.stateAbsent`: the capture found no file at this path.
STATE_ABSENT = "absent"

# The comparator obligations, mapped to the `verso.blueprint.trust.*` option
# that configures each one. The role strings are `Informal.TrustInputs.role*`;
# the option names are read out of site/lakefile.lean at run time, so the path
# side of this map is never restated here and cannot drift from what the site
# actually built with.
REQUIRED_ROLE_OPTIONS = {
    "comparator-status": "comparatorStatus",
    "comparator-config": "comparatorConfig",
    "challenge": "challengeFile",
    "solution": "solutionFile",
}

SHA256_RE = re.compile(r"\A[0-9a-f]{64}\Z")
COMMIT_RE = re.compile(r"\A[0-9a-f]{40}\Z")

# `⟨`weak.verso.blueprint.trust.challengeFile, "../comparator/Challenge.lean"⟩`
OPTION_RE = re.compile(
    r"weak\.verso\.blueprint\.trust\.([A-Za-z]+)\s*,\s*\"([^\"]*)\""
)
# `input_file comparatorChallenge where` + `path := "../comparator/Challenge.lean"`.
# `\s+` spans the line break rather than requiring one, so the one-line spelling
# is read the same as the indented one.
INPUT_FILE_RE = re.compile(r"input_file\s+\S+\s+where\s+path\s*:=\s*\"([^\"]*)\"")


class Violations:
    """Collect every failure rather than stopping at the first."""

    def __init__(self):
        self.items = []

    def add(self, where, message):
        self.items.append((where, message))

    def __bool__(self):
        return bool(self.items)

    def report(self, stream=sys.stdout):
        for where, message in self.items:
            print("  {}: {}".format(where, message), file=stream)


def normalize_path(value):
    """Compare paths as path COMPONENTS, dropping `.` and empty segments.

    `..` segments are kept: this site's trust options are relative to the site
    build's CWD and legitimately escape it, and collapsing them here would let
    two different files compare equal.
    """
    segments = [s for s in value.replace("\\", "/").split("/") if s not in ("", ".")]
    return "/".join(segments)


def parse_configured_paths(lakefile_text, v, label="lakefile"):
    """The canonical comparator paths this consumer configured.

    Read from the lakefile rather than hardcoded so the gate checks the site's
    own configuration; an option that stops being set is itself a regression the
    gate should catch, since the evidence page silently degrades without it.
    """
    found = {}
    for option, value in OPTION_RE.findall(lakefile_text):
        found.setdefault(option, value)
    configured = {}
    for role, option in sorted(REQUIRED_ROLE_OPTIONS.items()):
        if option not in found:
            v.add(
                label,
                "no verso.blueprint.trust.{} option is set, so the evidence page is"
                " no longer bound to a {} file at all".format(option, role),
            )
            continue
        configured[role] = found[option]
    return configured


def check_lake_input_edges(lakefile_text, configured, v, label="lakefile"):
    """Every configured comparator input must also carry a Lake `input_file` edge.

    The edge is what makes an ordinary `lake build Contents` re-elaborate the
    capture when one of these files changes, so the generator's fail-closed stop
    stays a backstop rather than the workflow (CX-075). Repointing an option
    without moving its edge restores exactly the warm-replay window this gate
    exists for, and does it quietly. Extra edges are fine -- this is a subset
    check, not an equality one.
    """
    edges = {normalize_path(p) for p in INPUT_FILE_RE.findall(lakefile_text)}
    for role, path in sorted(configured.items()):
        if normalize_path(path) not in edges:
            v.add(
                label,
                "the {} input ({}) has no `input_file` target, so Lake tracks no read"
                " of it and a warm rebuild would not re-elaborate the capture".format(
                    role, path
                ),
            )


def check_document_shape(record, v):
    """Exact top-level shape and schema version."""
    if not isinstance(record, dict):
        v.add("document", "the provenance record is not a JSON object")
        return False
    unexpected = set(record) - DOCUMENT_KEYS
    missing = DOCUMENT_KEYS - set(record)
    for key in sorted(missing):
        v.add("document", "no '{}' key".format(key))
    for key in sorted(unexpected):
        v.add(
            "document",
            "unexpected key '{}'; this producer writes a document this gate does not"
            " know how to authenticate".format(key),
        )
    version = record.get("schemaVersion")
    # `isinstance(True, int)` is True in Python, and a bool here is a malformed
    # record, not version 1.
    if isinstance(version, bool) or not isinstance(version, int):
        v.add("schemaVersion", "is {!r}, not an integer".format(version))
    elif version != SUPPORTED_SCHEMA_VERSION:
        v.add(
            "schemaVersion",
            "is {}; this gate authenticates version {} only. Update"
            " SUPPORTED_SCHEMA_VERSION in this script together with the checks the new"
            " schema needs -- do not widen it to accept both.".format(
                version, SUPPORTED_SCHEMA_VERSION
            ),
        )
    return not missing and not unexpected


def check_revision(record, build_revision, deployable, event, v):
    """The site's own stamp, against the revision CI sampled from the worktree.

    Both sides describe the same generating checkout, so this is an equality
    check with no tolerance: a site that stamps a different commit than the one
    it was generated from names a revision a reader cannot reproduce it from.
    """
    revision = record.get("buildRevision")
    if not isinstance(revision, dict):
        v.add(
            "buildRevision",
            "is {!r}, not an object; a record with no revision establishes nothing"
            " about which checkout produced this site".format(revision),
        )
        return
    for key in sorted(REVISION_KEYS - set(revision)):
        v.add("buildRevision", "no '{}' key".format(key))
    for key in sorted(set(revision) - REVISION_KEYS):
        v.add("buildRevision", "unexpected key '{}'".format(key))

    commit = revision.get("commit")
    if not isinstance(commit, str) or not COMMIT_RE.match(commit):
        v.add(
            "buildRevision.commit",
            "is {!r}, not a full 40-character commit; the site stamped nothing this"
            " gate can compare".format(commit),
        )
    elif commit != build_revision:
        v.add(
            "buildRevision.commit",
            "is {} but this site was generated from {}; the published stamp names a"
            " revision that is not the one it was built from".format(
                commit, build_revision
            ),
        )

    short = revision.get("shortCommit")
    if short is not None:
        if not isinstance(short, str) or not short or not commit or not isinstance(commit, str):
            v.add("buildRevision.shortCommit", "is {!r}".format(short))
        elif not commit.startswith(short):
            v.add(
                "buildRevision.shortCommit",
                "is {} which is not a prefix of {}".format(short, commit),
            )

    url = revision.get("repositoryUrl")
    if url is not None and not isinstance(url, str):
        v.add("buildRevision.repositoryUrl", "is {!r}, not a string".format(url))

    dirty = revision.get("dirty")
    if not isinstance(dirty, bool):
        # `null` is what the fork writes when it could not tell. A gate that
        # treats "could not tell" as clean is not enforcing a clean-tree policy.
        v.add(
            "buildRevision.dirty",
            "is {!r}; a run that could not determine whether its worktree was clean"
            " has not established that it was".format(dirty),
        )
    elif dirty:
        if deployable:
            v.add(
                "buildRevision.dirty",
                "the site was generated from a worktree with uncommitted changes and"
                " this {} run can deploy, so it would publish bytes that are in no"
                " commit and that its own stamp does not contain".format(event),
            )
        else:
            print(
                "trust-provenance gate: worktree dirty on a non-deploying {} run"
                " (the refreshed status file is deliberately left uncommitted"
                " there); this artifact is not publishable and does not deploy.".format(
                    event
                )
            )


def check_input_shape(entry, index, v):
    """One record's own schema. Applies to every role, required or extra."""
    where = "inputs[{}]".format(index)
    if not isinstance(entry, dict):
        v.add(where, "is {!r}, not an object".format(entry))
        return None
    for key in sorted(INPUT_REQUIRED_KEYS - set(entry)):
        v.add(where, "no '{}' key".format(key))
    for key in sorted(set(entry) - INPUT_REQUIRED_KEYS - INPUT_OPTIONAL_KEYS):
        v.add(where, "unexpected key '{}'".format(key))

    role, path, digest = entry.get("role"), entry.get("path"), entry.get("sha256")
    if not isinstance(role, str) or not role:
        v.add(where, "role is {!r}".format(role))
    if not isinstance(path, str) or not path:
        v.add(where, "path is {!r}".format(path))
    if not isinstance(digest, str):
        v.add(where, "sha256 is {!r}, not a string".format(digest))

    state = entry.get("state")
    if state is not None and state != STATE_ABSENT:
        v.add(
            where,
            "state is {!r}; the only state this schema defines is {!r}".format(
                state, STATE_ABSENT
            ),
        )
    topic = entry.get("topic")
    if topic is not None and (not isinstance(topic, str) or not topic):
        v.add(where, "topic is {!r}".format(topic))

    if isinstance(digest, str):
        if state == STATE_ABSENT:
            if digest:
                v.add(
                    where,
                    "records the path as absent but carries the digest {}; an absent"
                    " file has no bytes to have hashed".format(digest),
                )
        elif not SHA256_RE.match(digest):
            v.add(where, "sha256 is {!r}, not 64 lowercase hex characters".format(digest))

    if not isinstance(role, str) or not isinstance(path, str):
        return None
    return (role, path, state)


def recheck_input(entry, index, root, v):
    """Re-hash one recorded path against the checkout.

    Absent is a claim like any other: the capture said there was no file here,
    so a file here now means the capture describes a tree this one is not.
    """
    where = "inputs[{}]".format(index)
    path, digest = entry.get("path"), entry.get("sha256")
    role = entry.get("role", "?")
    if not isinstance(path, str) or not path:
        return
    resolved = os.path.join(root, path)
    absent = entry.get("state") == STATE_ABSENT
    if absent:
        if os.path.exists(resolved):
            v.add(
                where,
                "{} ({}) was recorded as absent and exists in this checkout; the"
                " evidence page was built without bytes that are there now".format(
                    path, role
                ),
            )
        return
    try:
        with open(resolved, "rb") as handle:
            got = hashlib.sha256(handle.read()).hexdigest()
    except OSError as err:
        v.add(where, "{} ({}) cannot be read from this checkout: {}".format(path, role, err))
        return
    if isinstance(digest, str) and SHA256_RE.match(digest) and got != digest:
        v.add(
            where,
            "{} ({}) was elaborated from {} and is {} here".format(path, role, digest, got),
        )


def check_required_roles(entries, configured, v):
    """Exactly one record per comparator role, at the path this site configured.

    Keyed on the role, then checked against the configured path -- so a record
    that carries the right label and the wrong file is caught, which is what
    makes this a binding rather than a name check. Extra roles are untouched
    here: they were validated as records above, and no label of theirs can stand
    in for one of these four.
    """
    by_role = {}
    for index, entry in entries:
        by_role.setdefault(entry[0], []).append((index, entry))
    for role in sorted(REQUIRED_ROLE_OPTIONS):
        if role not in configured:
            continue  # already reported against the lakefile
        want = normalize_path(configured[role])
        occurrences = by_role.get(role, [])
        if not occurrences:
            v.add(
                "inputs",
                "no {} input was recorded; the evidence page is bound to less than it"
                " looks bound to".format(role),
            )
            continue
        if len(occurrences) > 1:
            v.add(
                "inputs",
                "{} records carry the role {}: {}. This consumer publishes one"
                " comparator, so which of them the page was built from is undecidable".format(
                    len(occurrences),
                    role,
                    ", ".join(sorted(e[1][1] for e in occurrences)),
                ),
            )
            continue
        index, (_, path, state) = occurrences[0]
        if normalize_path(path) != want:
            v.add(
                "inputs[{}]".format(index),
                "the {} role names {} but this site configures {}; a role label"
                " attached to a different file does not discharge the obligation".format(
                    role, path, configured[role]
                ),
            )
        if state == STATE_ABSENT:
            v.add(
                "inputs[{}]".format(index),
                "the {} input was recorded as absent; a comparator page cannot be"
                " evidence about a file that was not there".format(role),
            )


def check(record, lakefile_text, build_revision, deployable, event, root,
          lakefile_label="lakefile"):
    v = Violations()
    configured = parse_configured_paths(lakefile_text, v, lakefile_label)
    check_lake_input_edges(lakefile_text, configured, v, lakefile_label)
    if not check_document_shape(record, v):
        return v
    check_revision(record, build_revision, deployable, event, v)

    raw = record.get("inputs")
    if not isinstance(raw, list) or not raw:
        v.add(
            "inputs",
            "the published site records no trust inputs. Either the"
            " verso.blueprint.trust.* options stopped being set, or the payload stopped"
            " recording what it was read from -- both silently weaken the evidence page.",
        )
        return v

    parsed = []
    for index, entry in enumerate(raw):
        shape = check_input_shape(entry, index, v)
        if shape is not None:
            parsed.append((index, shape))
            recheck_input(entry, index, root, v)
    check_required_roles(parsed, configured, v)
    return v


def build_parser():
    p = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    p.add_argument("--provenance", required=True, help="the generated -verso-data/trust-provenance.json")
    p.add_argument("--lakefile", required=True,
                   help="the consumer's site lakefile, the configuration of record")
    p.add_argument(
        "--build-revision",
        required=True,
        help="the commit CI independently sampled from the generating worktree",
    )
    p.add_argument(
        "--deployable",
        required=True,
        choices=("true", "false"),
        help="whether this run's artifact can reach Pages; the reusable workflow computes"
             " this ONCE, as the publish job's `deployable` output, and both this gate and"
             " the site-release job read that one value (codex-audit CX-079)",
    )
    p.add_argument("--event", required=True, help="the triggering event, for the message only")
    p.add_argument(
        "--root",
        default=".",
        help="directory the recorded relative paths resolve against (the site build's CWD)",
    )
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    with open(args.lakefile, encoding="utf-8") as handle:
        lakefile_text = handle.read()
    try:
        with open(args.provenance, encoding="utf-8") as handle:
            record = json.load(handle)
    except (OSError, ValueError) as err:
        print("trust-provenance gate: {} is unreadable: {}".format(args.provenance, err))
        return 1

    v = check(
        record,
        lakefile_text,
        args.build_revision,
        args.deployable == "true",
        args.event,
        args.root,
        args.lakefile,
    )
    if v:
        print("trust-provenance gate: the published comparator evidence is not")
        print("authenticated against this checkout.")
        v.report()
        print("A digest that disagrees means the page was rendered from a cached elaboration")
        print("of different bytes: re-elaborate the site's Contents library")
        print("(`lake build Contents -R`) and regenerate, rather than publishing a verdict")
        print("beside a statement this build never read. Anything else above is a record")
        print("this gate cannot authenticate, which is not a record it may pass.")
        return 1
    inputs = record.get("inputs") or []
    revision = record.get("buildRevision") or {}
    # Say which tree it was, not which tree the happy path assumes: this line is
    # read as the gate's summary, and a dirty non-deploying artifact that reports
    # itself clean is the gate telling the same kind of story it exists to stop.
    print(
        "trust-provenance gate: {} trust input(s) match this checkout; the four"
        " comparator roles each name their configured path; site stamped {} ({}).".format(
            len(inputs),
            revision.get("commit"),
            "clean" if revision.get("dirty") is False else "dirty, non-deploying",
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
