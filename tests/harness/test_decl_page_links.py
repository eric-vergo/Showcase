"""Regression suite for the generated-site decl-page link gate.

The per-declaration-page scale cap (`verso.blueprint.declRegistry.maxDeclPages`) makes
"does this declaration have a page" a build-time decision, and the way that goes wrong is
quiet: a surface composes a `decl/<slug>/` href from a name, the link looks fine, and the
reader gets a 404. `scripts/check_decl_page_links.py` is the site-level gate against that,
and these tests hold it to both halves of its job — it must catch a reference with no page
behind it, and it must not cry wolf on a site where every reference resolves.
"""

from __future__ import annotations

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from scripts.check_decl_page_links import main, referenced_slugs


def _site(root: Path, *, pages: tuple[str, ...], index_html: str, data_json: str = "[]") -> None:
    """Lay out a minimal generated site: some emitted decl pages plus the files that
    reference them (a page and a `-verso-data` payload)."""
    for slug in pages:
        page_dir = root / "decl" / slug
        page_dir.mkdir(parents=True)
        (page_dir / "index.html").write_text("<html>page</html>", encoding="utf-8")
    (root / "index.html").write_text(index_html, encoding="utf-8")
    data_dir = root / "-verso-data"
    data_dir.mkdir(exist_ok=True)
    (data_dir / "decl-search.json").write_text(data_json, encoding="utf-8")


class DeclPageLinkGateTests(unittest.TestCase):
    def test_passes_when_every_reference_has_a_page(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _site(
                root,
                pages=("Example___hub", "Example___midA"),
                index_html='<a href="decl/Example___hub/">hub</a>',
                data_json='[{"href":"decl/Example___midA/"}]',
            )
            self.assertEqual(main(["check", str(root)]), 0)

    def test_catches_an_href_with_no_page(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _site(
                root,
                pages=("Example___hub",),
                index_html='<a href="decl/Example___hub/">hub</a>'
                '<a href="decl/Example___leaf/">leaf</a>',
            )
            self.assertEqual(main(["check", str(root)]), 1)

    def test_catches_a_dangling_reference_in_a_data_payload(self) -> None:
        """The command palette navigates by `decl-search.json`, so a stale entry there is
        as broken as a stale `<a href>` — and is invisible to an HTML-only scan."""
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _site(
                root,
                pages=("Example___hub",),
                index_html='<a href="decl/Example___hub/">hub</a>',
                data_json='[{"href":"decl/Example___leaf/"}]',
            )
            self.assertEqual(main(["check", str(root)]), 1)

    def test_over_cap_row_markup_is_not_a_reference(self) -> None:
        """What an over-cap row emits — the name as text, the neutral pill, a source link —
        must not read as a decl reference, or the gate would fail the very build that is
        behaving correctly."""
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _site(
                root,
                pages=("Example___hub",),
                index_html=(
                    '<li class="bp_decl_row"><button class="bp_decl_row_name">leaf</button>'
                    '<span class="bp_summary_badge bp_decl_row_nopage">no page (over cap)</span>'
                    '<a class="bp_decl_row_source" href="https://example.invalid/x">source</a>'
                    '<a href="decl/Example___hub/">hub</a></li>'
                ),
            )
            self.assertEqual(main(["check", str(root)]), 0)

    def test_a_site_with_no_decl_route_at_all_is_clean(self) -> None:
        """Consumers without `includeAllDecls` emit no registry and no `decl/` directory;
        the gate must pass rather than treat the absent route as a failure."""
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "index.html").write_text("<html>no decls here</html>", encoding="utf-8")
            self.assertEqual(main(["check", str(root)]), 0)

    def test_reference_scan_reports_where_each_slug_came_from(self) -> None:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            _site(
                root,
                pages=("Example___hub",),
                index_html='<a href="decl/Example___hub/">hub</a>',
                data_json='[{"href":"decl/Example___hub/"}]',
            )
            refs = referenced_slugs(root)
            self.assertEqual(set(refs), {"Example___hub"})
            self.assertEqual(
                refs["Example___hub"],
                {"index.html", "-verso-data/decl-search.json"},
            )


if __name__ == "__main__":
    unittest.main()
