#!/usr/bin/env python3
"""Validate a comparator result record before anything is published from it.

The comparator job (.github/workflows/blueprint-verify.yml) runs untrusted Lean
and holds no write token; the publish job holds the only `contents: write` token
and turns that job's `comparator-result.json` into the consumer's comparator
status artifact, which the blueprint site quotes as dated verifier evidence. The
artifact therefore crosses a trust boundary, and codex-audit CX-052 showed that a
validator which checks only the verdict, the commit and three post-run hashes
accepts a record whose repository, run identity, verifier references, toolchain,
pre-run manifest and probe details are forged.

This script is the strict gate on that boundary. Nothing here is taken from the
record on faith: every field is compared against a value the publish job derives
from its own trusted context -- workflow constants passed on the command line,
the checked-out comparator config, the GitHub context, and the checked-out
sources re-hashed here. Unknown keys are rejected as firmly as missing ones, so
a record shaped by a future workflow cannot smuggle a field past a validator
that does not know to look at it.

This is the one copy, shared by every consumer of the reusable workflow. It is
eric-vergo/HopfProblem's version (which already carried `kernel_identities` --
the run's own record of WHICH nanoda executable replayed the export, codex-audit
CX-064, validated against the manifest digest of the same binary so the identity
and the hash manifest cannot disagree about the program that ran); the
a362583 copy it supersedes had neither. Nothing here hard-codes a consumer's
layout: the certified source paths arrive as `--hash-file` arguments.

Two things this shared version adds:

  * `workflow_repository` / `workflow_ref` / `workflow_sha` -- WHICH CI code
    produced the record. The pipeline is a reusable workflow now, so "my CI
    produced this" is a claim about a commit in another repository. The publish
    job passes the `job.workflow_*` values it read for itself; a record naming a
    fork of the CI repository, another branch, or a right-shaped SHA of some
    other commit is rejected here rather than republished as evidence.
  * `permitted_axioms: []` is ACCEPTED. An empty allowlist is a stronger claim
    than the standard three -- the certified theorem must reach no axiom at all
    -- and lean_quine makes it. What is required is that the key be PRESENT in
    the checked-out config, be a list, and equal the record's; absence is still a
    rejection. `theorem_names` stays non-empty: a run that certifies nothing is
    not a verdict.

Every violation is collected and printed; the exit status is 1 if there is any.

Python 3.9-compatible on purpose: it runs on the hosted runner and on the
maintainer's machine.
"""

import argparse
import datetime
import hashlib
import json
import re
import sys

# The exact shape of a result record. `Compose the comparator result record` in
# ci.yml writes these keys and only these; adding one there means adding it
# here, which is the point.
RESULT_KEYS = {
    "verdict",
    "repository",
    "commit",
    "run_id",
    "started_at",
    "finished_at",
    "config",
    "challenge_module",
    "solution_module",
    "theorem_names",
    "permitted_axioms",
    "nanoda_replay",
    "toolchain",
    "tool_ref",
    "tool_sha",
    "tool_toolchain",
    "landrun_ref",
    "nanoda_ref",
    "af_unix_guard",
    # WHICH CI code produced this record (the reusable workflow's own identity).
    "workflow_repository",
    "workflow_ref",
    "workflow_sha",
    "kernel_identities",
    "inputs_sha256_before",
    "inputs_sha256_after",
    "sandbox_selftest",
    "sandbox_write_probe",
}

# The four executables whose identity the run rests on, and the three certified
# sources. Both sets are exact: a manifest that drops the nanoda binary, or adds
# a fourth "source", is a different check than the one being published.
BINARY_KEYS = {"comparator", "lean4export", "landrun", "nanoda"}
SOURCE_KEYS = {"comparator_config", "challenge_lean", "solution_lean"}
MANIFEST_KEYS = BINARY_KEYS | SOURCE_KEYS

SELFTEST_KEYS = {"tier", "exit_code", "denied", "targets", "sentinel_observed"}
PROBE_KEYS = {"config", "exit_code", "denied", "tier"}
IDENTITY_KEYS = {"label", "repository", "source_commit", "executable_sha256", "replayed"}

SHA256_RE = re.compile(r"\A[0-9a-f]{64}\Z")
REVISION_RE = re.compile(r"\A[0-9a-f]{40}\Z")
TIMESTAMP_FORMAT = "%Y-%m-%dT%H:%M:%SZ"

# A finished_at may legitimately sit a little past the validator's clock (the
# two jobs read different machines' clocks); a lot past is not a run window.
FUTURE_SKEW_SECONDS = 120


class Violations:
    """Collect every failure rather than stopping at the first."""

    def __init__(self):
        self.items = []

    def add(self, field, message):
        self.items.append((field, message))

    def __bool__(self):
        return bool(self.items)


def check_exact_keys(v, where, obj, expected):
    """Require `obj` to be a mapping whose key set is exactly `expected`."""
    if not isinstance(obj, dict):
        v.add(where, "expected an object, got {}".format(type(obj).__name__))
        return False
    got = set(obj.keys())
    for key in sorted(expected - got):
        v.add(where, "missing key '{}'".format(key))
    for key in sorted(got - expected):
        v.add(where, "unexpected key '{}'".format(key))
    return got == expected


def check_equal(v, field, got, want):
    if got != want:
        v.add(field, "record has {!r}, expected {!r}".format(got, want))


def parse_timestamp(v, field, value):
    if not isinstance(value, str):
        v.add(field, "expected a string timestamp, got {}".format(type(value).__name__))
        return None
    try:
        parsed = datetime.datetime.strptime(value, TIMESTAMP_FORMAT)
    except ValueError:
        v.add(field, "{!r} is not a UTC timestamp of the form {}".format(value, TIMESTAMP_FORMAT))
        return None
    return parsed.replace(tzinfo=datetime.timezone.utc)


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 16), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_repo(url):
    """Repository URL in the form the comparison uses: lower-cased, no trailing
    `.git` or `/`. The same normalization the blueprint applies when it decides
    whether a recorded identity agrees with the site's pin."""
    if not isinstance(url, str):
        return url
    url = url.strip().lower()
    if url.endswith(".git"):
        url = url[:-4]
    if url.endswith("/"):
        url = url[:-1]
    return url


def validate_manifests(v, record):
    """Exact key sets, well-formed digests, and before == after per file."""
    before = record.get("inputs_sha256_before")
    after = record.get("inputs_sha256_after")
    before_ok = check_exact_keys(v, "inputs_sha256_before", before, MANIFEST_KEYS)
    after_ok = check_exact_keys(v, "inputs_sha256_after", after, MANIFEST_KEYS)
    if not (before_ok and after_ok):
        return
    for key in sorted(MANIFEST_KEYS):
        for which, manifest in (("before", before), ("after", after)):
            value = manifest[key]
            if not isinstance(value, str) or not SHA256_RE.match(value):
                v.add(
                    "inputs_sha256_{}.{}".format(which, key),
                    "{!r} is not a lowercase hex sha256".format(value),
                )
        # The manifests are computed by one script run twice around the
        # certified run. A difference means the machinery or the certified
        # sources changed mid-flight, so the two halves of the run did not check
        # the same thing.
        if before[key] != after[key]:
            v.add(
                "inputs_sha256.{}".format(key),
                "input changed during the run: before {} != after {}".format(before[key], after[key]),
            )


def validate_file_hashes(v, record, hash_files):
    """Re-derive the certified sources' digests from the publishing checkout."""
    provided = set(hash_files.keys())
    for key in sorted(SOURCE_KEYS - provided):
        v.add("--hash-file", "no file given for certified source '{}'".format(key))
    for key in sorted(provided - SOURCE_KEYS):
        v.add("--hash-file", "'{}' is not a certified source key".format(key))
    after = record.get("inputs_sha256_after")
    if not isinstance(after, dict):
        return
    for key in sorted(provided & SOURCE_KEYS):
        path = hash_files[key]
        try:
            got = sha256_file(path)
        except OSError as exc:
            v.add("inputs_sha256_after.{}".format(key), "cannot read {}: {}".format(path, exc))
            continue
        want = after.get(key)
        if want != got:
            v.add(
                "inputs_sha256_after.{}".format(key),
                "record has {!r}, {} hashes to {}".format(want, path, got),
            )


def validate_config_derived(v, record, config):
    """The claim fields must be the checked-out config's, not the record's own."""
    check_equal(v, "challenge_module", record.get("challenge_module"), config.get("challenge_module"))
    check_equal(v, "solution_module", record.get("solution_module"), config.get("solution_module"))
    check_equal(v, "theorem_names", record.get("theorem_names"), config.get("theorem_names"))
    check_equal(v, "permitted_axioms", record.get("permitted_axioms"), config.get("permitted_axioms"))
    check_equal(v, "nanoda_replay", record.get("nanoda_replay"), bool(config.get("enable_nanoda", False)))
    for field in ("challenge_module", "solution_module"):
        value = record.get(field)
        if not isinstance(value, str) or not value:
            v.add(field, "must be a non-empty string, got {!r}".format(value))
    # A run that certifies no theorem is not a verdict.
    names = record.get("theorem_names")
    if not isinstance(names, list) or not names:
        v.add("theorem_names", "must be a non-empty list, got {!r}".format(names))
    # `permitted_axioms: []` is a REAL and stronger claim -- the certified
    # theorem reaches no axiom at all -- so emptiness is not a defect here. What
    # must hold is that the CHECKED-OUT config states the bound (absence is not
    # emptiness: a config that never states it is one this record cannot have
    # been checked against) and that the record repeats it exactly, which the
    # `check_equal` above already enforces.
    if "permitted_axioms" not in config:
        v.add(
            "permitted_axioms",
            "the checked-out comparator config declares no permitted_axioms; an EMPTY"
            " list is allowed and means 'no axiom at all', but the bound has to be stated",
        )
    axioms = record.get("permitted_axioms")
    if not isinstance(axioms, list):
        v.add("permitted_axioms", "must be a list, got {!r}".format(axioms))


def validate_timestamps(v, record, now, max_age_seconds):
    started = parse_timestamp(v, "started_at", record.get("started_at"))
    finished = parse_timestamp(v, "finished_at", record.get("finished_at"))
    if started is None or finished is None:
        return
    if finished < started:
        v.add("finished_at", "the run finished ({}) before it started ({})".format(
            record["finished_at"], record["started_at"]))
    horizon = now + datetime.timedelta(seconds=FUTURE_SKEW_SECONDS)
    if finished > horizon:
        v.add("finished_at", "{} is in the future relative to the publishing job ({})".format(
            record["finished_at"], now.strftime(TIMESTAMP_FORMAT)))
    floor = now - datetime.timedelta(seconds=max_age_seconds)
    if started < floor:
        v.add("started_at", "{} is older than the {}s run window ending {}".format(
            record["started_at"], max_age_seconds, now.strftime(TIMESTAMP_FORMAT)))


def validate_selftest(v, record, expected_tier):
    """The trusted pre-run containment evidence (CX-050/CX-051)."""
    block = record.get("sandbox_selftest")
    if not check_exact_keys(v, "sandbox_selftest", block, SELFTEST_KEYS):
        return
    check_equal(v, "sandbox_selftest.tier", block["tier"], expected_tier)
    check_equal(v, "sandbox_selftest.denied", block["denied"], True)
    check_equal(v, "sandbox_selftest.sentinel_observed", block["sentinel_observed"], True)
    exit_code = block["exit_code"]
    if not isinstance(exit_code, int) or isinstance(exit_code, bool) or exit_code == 0:
        v.add("sandbox_selftest.exit_code", "expected a non-zero integer, got {!r}".format(exit_code))
    targets = block["targets"]
    if not isinstance(targets, list) or len(targets) != 2 or not all(
        isinstance(t, str) and t for t in targets
    ):
        v.add("sandbox_selftest.targets", "expected two non-empty target paths, got {!r}".format(targets))


def validate_probe(v, record, expected_config, expected_tier):
    """The repository-side fixture, kept as defense in depth (CX-051)."""
    block = record.get("sandbox_write_probe")
    if not check_exact_keys(v, "sandbox_write_probe", block, PROBE_KEYS):
        return
    check_equal(v, "sandbox_write_probe.config", block["config"], expected_config)
    check_equal(v, "sandbox_write_probe.denied", block["denied"], True)
    check_equal(v, "sandbox_write_probe.tier", block["tier"], expected_tier)
    exit_code = block["exit_code"]
    if not isinstance(exit_code, int) or isinstance(exit_code, bool) or exit_code == 0:
        v.add("sandbox_write_probe.exit_code", "expected a non-zero integer, got {!r}".format(exit_code))


def validate_kernel_identities(v, record, nanoda_repository, nanoda_ref):
    """The run's own record of WHICH checker executable replayed the export.

    codex-audit CX-064: a checker LABEL establishes nothing, and neither does a
    well-formed digest on its own -- a producer who types sixty-four hex
    characters into a field named `executable_sha256` earns whatever tier reads
    the field. Two independent things make this record worth publishing, and
    only one of them lives here.

    Here: the identity must agree with THIS job's own trusted constants (the
    workflow's `NANODA_REF` and the canonical repository) and with the hash
    manifest the same run wrote -- `executable_sha256` must be the very digest
    the manifest recorded for the nanoda binary, so the two encodings of "which
    program ran" cannot disagree.

    Elsewhere: the blueprint site compares the same record against a pin the
    site author committed (`verso.blueprint.trust.expectedKernelIdentities`,
    `site/trust/kernel-identities.json`), which is the second source the finding
    actually asked for. Nothing in this file or in that comparison re-runs a
    checker or hashes a binary out of band.
    """
    identities = record.get("kernel_identities")
    if not isinstance(identities, list) or len(identities) != 1:
        v.add("kernel_identities", "expected exactly one identity record, got {!r}".format(identities))
        return
    entry = identities[0]
    if not check_exact_keys(v, "kernel_identities[0]", entry, IDENTITY_KEYS):
        return
    check_equal(v, "kernel_identities[0].label", entry["label"], "nanoda")
    if normalize_repo(entry["repository"]) != normalize_repo(nanoda_repository):
        v.add(
            "kernel_identities[0].repository",
            "record has {!r}, expected {!r}".format(entry["repository"], nanoda_repository),
        )
    check_equal(v, "kernel_identities[0].source_commit", entry["source_commit"], nanoda_ref)
    if not REVISION_RE.match(str(entry["source_commit"])):
        v.add(
            "kernel_identities[0].source_commit",
            "{!r} is not a full 40-character lowercase hex revision".format(entry["source_commit"]),
        )
    digest = entry["executable_sha256"]
    if not isinstance(digest, str) or not SHA256_RE.match(digest):
        v.add(
            "kernel_identities[0].executable_sha256",
            "{!r} is not a lowercase hex sha256".format(digest),
        )
    else:
        after = record.get("inputs_sha256_after")
        recorded = after.get("nanoda") if isinstance(after, dict) else None
        if digest != recorded:
            v.add(
                "kernel_identities[0].executable_sha256",
                "identity names {} but the post-run manifest hashed the nanoda binary to {!r}".format(
                    digest, recorded),
            )
    check_equal(v, "kernel_identities[0].replayed", entry["replayed"], record.get("nanoda_replay"))


def validate(record, config, args, hash_files, now):
    v = Violations()

    check_exact_keys(v, "<record>", record, RESULT_KEYS)
    if not isinstance(record, dict):
        return v

    check_equal(v, "verdict", record.get("verdict"), "verified")
    check_equal(v, "repository", record.get("repository"), args.repository)
    check_equal(v, "commit", record.get("commit"), args.commit)
    check_equal(v, "run_id", record.get("run_id"), args.run_id)
    check_equal(v, "config", record.get("config"), args.config_path)
    check_equal(v, "toolchain", record.get("toolchain"), args.toolchain)
    check_equal(v, "tool_ref", record.get("tool_ref"), args.tool_ref)
    check_equal(v, "tool_sha", record.get("tool_sha"), args.tool_sha)
    check_equal(v, "tool_toolchain", record.get("tool_toolchain"), args.tool_toolchain)
    check_equal(v, "landrun_ref", record.get("landrun_ref"), args.landrun_ref)
    check_equal(v, "nanoda_ref", record.get("nanoda_ref"), args.nanoda_ref)
    check_equal(v, "af_unix_guard", record.get("af_unix_guard"), args.af_unix_guard)

    # WHICH CI code produced this record. The publish job reads `job.workflow_*`
    # for itself and passes those values; nothing here is taken from the record.
    # A well-formed SHA is what a forger has for free -- naming the commit this
    # job is actually running from is not.
    check_equal(v, "workflow_repository", record.get("workflow_repository"), args.workflow_repository)
    check_equal(v, "workflow_ref", record.get("workflow_ref"), args.workflow_ref)
    check_equal(v, "workflow_sha", record.get("workflow_sha"), args.workflow_sha)
    if not REVISION_RE.match(str(record.get("workflow_sha"))):
        v.add(
            "workflow_sha",
            "{!r} is not a full 40-character lowercase hex revision".format(
                record.get("workflow_sha")),
        )

    validate_config_derived(v, record, config)
    validate_manifests(v, record)
    validate_file_hashes(v, record, hash_files)
    validate_timestamps(v, record, now, args.max_age_seconds)
    validate_selftest(v, record, args.selftest_tier)
    validate_probe(v, record, args.probe_config, args.probe_tier)
    validate_kernel_identities(v, record, args.nanoda_repository, args.nanoda_ref)
    return v


def parse_hash_files(pairs):
    out = {}
    for pair in pairs:
        if "=" not in pair:
            raise SystemExit("--hash-file expects KEY=PATH, got {!r}".format(pair))
        key, path = pair.split("=", 1)
        out[key] = path
    return out


def build_parser():
    p = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    p.add_argument("--result", required=True, help="the comparator-result.json to validate")
    p.add_argument("--config-file", required=True, help="the CHECKED-OUT comparator config to derive claims from")
    p.add_argument("--config-path", required=True, help="the config path the record must name")
    p.add_argument("--probe-config", required=True, help="the config path the defense-in-depth probe must name")
    p.add_argument("--repository", required=True)
    p.add_argument("--run-id", required=True)
    p.add_argument("--commit", required=True)
    p.add_argument("--toolchain", required=True)
    p.add_argument("--tool-ref", required=True)
    p.add_argument("--tool-sha", required=True)
    p.add_argument("--tool-toolchain", required=True)
    p.add_argument("--landrun-ref", required=True)
    p.add_argument("--nanoda-ref", required=True)
    p.add_argument("--nanoda-repository", required=True,
                   help="the repository the nanoda identity record must name")
    p.add_argument("--workflow-repository", required=True,
                   help="job.workflow_repository -- the repository holding the CI code")
    p.add_argument("--workflow-ref", required=True,
                   help="job.workflow_ref -- the full ref of the workflow file that ran")
    p.add_argument("--workflow-sha", required=True,
                   help="job.workflow_sha -- the commit of the workflow file that ran")
    p.add_argument("--af-unix-guard", required=True)
    p.add_argument("--selftest-tier", required=True)
    p.add_argument("--probe-tier", required=True)
    p.add_argument("--now", required=True, help="the publishing job's UTC clock, %%Y-%%m-%%dT%%H:%%M:%%SZ")
    p.add_argument("--max-age-seconds", required=True, type=int)
    p.add_argument(
        "--hash-file",
        action="append",
        default=[],
        metavar="KEY=PATH",
        help="re-derive inputs_sha256_after[KEY] from PATH; required for every certified source",
    )
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    hash_files = parse_hash_files(args.hash_file)

    try:
        now = datetime.datetime.strptime(args.now, TIMESTAMP_FORMAT).replace(
            tzinfo=datetime.timezone.utc
        )
    except ValueError:
        raise SystemExit("--now {!r} is not of the form {}".format(args.now, TIMESTAMP_FORMAT))

    with open(args.result, "r", encoding="utf-8") as handle:
        record = json.load(handle)
    with open(args.config_file, "r", encoding="utf-8") as handle:
        config = json.load(handle)

    v = validate(record, config, args, hash_files, now)
    if v:
        print("comparator result record REJECTED ({} violation(s)):".format(len(v.items)))
        for field, message in v.items:
            print("  {}: {}".format(field, message))
        return 1
    print("comparator result record accepted: every published field matches this job's trusted inputs.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
