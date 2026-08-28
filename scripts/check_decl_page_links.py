#!/usr/bin/env python3
"""Assert that every link into a generated site's `decl/` route has a page behind it.

The per-declaration-page scale cap (`verso.blueprint.declRegistry.maxDeclPages`) makes
"is there a page for this declaration" a build-time decision rather than a property of
the name, and the failure mode it introduces is silent: a surface that composes a
`decl/<slug>/` href from a declaration name still produces a plausible link, and the
reader finds out it was wrong by getting a 404. The genre answers the question in one
place (`Informal.DeclRegistry.DeclRoute.hasDeclPage`); this is the check that nothing
went around it.

Scope: `href="decl/<slug>/"`-shaped references in the emitted HTML and in the
`-verso-data/*.json` payloads the client navigates by (the command palette's
`decl-search.json`, the graph node hrefs). Every referenced slug must have a
`decl/<slug>/index.html`.

Usage:

    python3 scripts/check_decl_page_links.py <site-root>

where `<site-root>` is a generated `html-multi` directory. Exits non-zero and lists the
dangling references when any target is missing.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# `decl/<slug>/` as it appears in an href attribute, in a JSON string, or in a DOT
# `URL="…"` attribute. Slugs are produced by `NodeRoute.declPageSlug`, so they never
# contain a quote, a slash, or whitespace.
DECL_REF = re.compile(r'decl/([A-Za-z0-9_\-.À-￿]+)/')

# Files worth scanning: the pages themselves plus the data payloads the runtime follows.
SCANNED_SUFFIXES = (".html", ".json", ".mjs")


def referenced_slugs(site_root: Path) -> dict[str, set[str]]:
    """Map each referenced decl slug to the files that reference it."""
    refs: dict[str, set[str]] = {}
    for path in sorted(site_root.rglob("*")):
        if not path.is_file() or path.suffix not in SCANNED_SUFFIXES:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for slug in DECL_REF.findall(text):
            refs.setdefault(slug, set()).add(str(path.relative_to(site_root)))
    return refs


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    site_root = Path(argv[1]).resolve()
    if not site_root.is_dir():
        print(f"[decl-page-links] not a directory: {site_root}", file=sys.stderr)
        return 2

    decl_root = site_root / "decl"
    emitted = (
        {child.name for child in decl_root.iterdir() if (child / "index.html").is_file()}
        if decl_root.is_dir()
        else set()
    )
    refs = referenced_slugs(site_root)

    dangling = {slug: files for slug, files in refs.items() if slug not in emitted}
    if dangling:
        print(
            f"[decl-page-links] {len(dangling)} declaration slug(s) are linked but have "
            f"no page under {decl_root}:",
            file=sys.stderr,
        )
        for slug in sorted(dangling):
            where = ", ".join(sorted(dangling[slug])[:4])
            print(f"  decl/{slug}/  <- {where}", file=sys.stderr)
        return 1

    print(
        f"[decl-page-links] ok: {len(refs)} referenced slug(s), {len(emitted)} page(s) "
        f"emitted, 0 dangling"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
