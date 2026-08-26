# Palomar registry fixtures

Inputs for `tests/VersoBlueprintTests/Registry.lean`. Every file here exists to make one
of the identity rules fail visibly if it is ever relaxed.

## `bundle/`

A cached bundle in the shape the `verso.blueprint.trust.palomarBundle` option reads: the
registry's `recent.json` projection together with the `entries/<id>-v<version>.json`
records it names. Seven rows, six records, one of each interesting case:

| record | what it is |
|---|---|
| `…-08-01-000001` | this project's repository, a challenge digest nothing displays |
| `…-08-02-000002` | **wrong repo**: the right digest under somebody else's repository |
| `…-08-03-000003` | **same repo, wrong digest**: project-level provenance at most |
| `…-08-04-000004` | **URL spoof**: the repository URL and the digest appear only in `title` and `abstract`; `source` and `verification` name something else |
| `…-08-05-000005` | **missing entry file**: a projection row whose record is not in the bundle |
| `…-08-06-000006` | **future schema**: `schema_version: 4`, which this build does not read |
| `…-08-07-000007` | the record bound to `claim/Challenge.lean`'s bytes |

Rows 5 and 6 are counted as unresolved and can never match. Neither is a build error: a
bundle fetched from a live registry legitimately contains records written to a schema this
build has no rules for.

## `claim/`

A comparator record whose `challenge_sha256` is the SHA-256 of `claim/Challenge.lean`
beside it, so the displayed bytes are bound to the verdict — the precondition for a
claim-level registry match. `…-000007` registers exactly those bytes. Refresh both digests
together if the challenge is ever edited:

```bash
shasum -a 256 tests/fixtures/palomar/claim/{Challenge.lean,comparator.json}
```

## `entry.json`

The other form of the option: one immutable entry JSON, configured directly.

## `configured-status.json` and `mismatched-entry.json` (CX-065)

The audit's own hostile pair, verbatim. The status is `configured` — the comparator has not
run — at commit `bbbb…`; the record registers commit `aaaa…` and the directory
`an/unrelated/project/path`. Only the repository and the challenge digest agree, and under
the earlier rule that was enough for the certifying claim sentence and a strip badge.

Each half is disqualifying on its own, and the unit tests beside the render fixture separate
them: a record of a different revision is a record of something else, and a verdict that has
not run certifies nothing for any record to be about.

## `malformed/recent.json`

A bundle whose root document does not parse. A configured input that is broken is a build
error, unlike an individual unreadable record.

## `projection-only/recent.json`

The projection with no records beside it. Its rows carry a repository and a commit and
still identify nothing, because the challenge digest lives in the record — which is the
same reason the feed below is never identity evidence.

## `feed.xml`

The registry's public feed, whose `description` contains this project's repository URL and
the matching challenge digest as *text*. Nothing in the fork reads it. The test asserts
that pointing the bundle option at it fails rather than matching anything.
