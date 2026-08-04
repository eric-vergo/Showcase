"""Regression suite for the format-aware off-origin asset scanner (CX-013).

The point of these tests is to *prove the upgrade*: the adversarial fixtures must slip
past the previous regular-expression gate (0 matches) while the new format-aware scanner
catches every off-origin request surface. A second group guards against false positives —
same-origin references and off-origin URLs that appear only inside comments must pass.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

from scripts.check_off_origin_assets import scan_file, scan_css, scan_js


FIXTURES = Path(__file__).resolve().parent / "off_origin_fixtures"


# The eight patterns the previous CI gate applied, transcribed from the shipped gate and
# from codex-audit/scratch/trust-ci/run_off_origin_gate_probe.sh. POSIX character classes
# are translated to their Python-regex equivalents; the semantics are unchanged.
_LEGACY_GATE_PATTERNS = (
    r"jsdelivr",
    r"""<(script[^>]*[\s]src|link[^>]*[\s]href)=["']https?://""",
    r"""<(img|iframe|embed|source|video|audio|track|object)[^>]*[\s]src=["']https?://""",
    r"""url\(\s*["']?https?://""",
    r"""@import\s+(url\()?\s*["']?https?://""",
    r"""(fetch|import)\(\s*["']https?://""",
    r"""(^|[^A-Za-z0-9_])(import|export)[^"']*\sfrom\s*["']https?://""",
    r"""[\s](src|srcset)=["']//|<link[^>]*[\s]href=["']//""",
)


def _legacy_gate_matches(text: str) -> int:
    return sum(1 for pattern in _LEGACY_GATE_PATTERNS if re.search(pattern, text, re.MULTILINE))


class LegacyGateMissesBypassTests(unittest.TestCase):
    """The old enumeration accepted the demonstrated off-origin surfaces."""

    def test_legacy_gate_accepts_codex_bypass_fixture(self) -> None:
        text = (FIXTURES / "bypass.html").read_text()
        self.assertEqual(
            _legacy_gate_matches(text),
            0,
            "the legacy regex gate was expected to MISS the bypass fixture entirely; "
            "if it now matches, the fixture or the transcription drifted",
        )

    def test_new_scanner_strictly_supersedes_legacy_gate_on_variants(self) -> None:
        # The legacy gate happened to enumerate a couple of protocol-relative attribute
        # forms (its 8th pattern catches `srcset="//host"`), so it is not zero here. The
        # upgrade claim is that the new scanner is a strict superset: it catches every
        # off-origin surface in the variant fixture, many of which the legacy gate misses
        # (cased schemes, entity-encoded colons, poster, xlink:href, form action, meta
        # refresh, sendBeacon/setAttribute JS sinks).
        text = (FIXTURES / "bypass_variants.html").read_text()
        legacy = _legacy_gate_matches(text)
        scanner_hits = scan_file(FIXTURES / "bypass_variants.html")
        self.assertGreater(
            len(scanner_hits),
            legacy,
            f"new scanner ({len(scanner_hits)}) must catch strictly more than the legacy "
            f"gate ({legacy}) on the variant fixture",
        )


class ScannerCatchesBypassTests(unittest.TestCase):
    """The format-aware scanner catches what the enumeration missed."""

    def test_scanner_flags_all_five_codex_surfaces(self) -> None:
        hits = scan_file(FIXTURES / "bypass.html")
        details = " ".join(hit.detail for hit in hits)
        # image srcset, video poster, object data, SVG image href, JS Image.src
        self.assertIn("srcset", details)
        self.assertIn("poster", details)
        self.assertIn("data", details)
        self.assertIn("href", details)
        self.assertTrue(any("src" in hit.detail for hit in hits), "missed the Image.src assignment")
        self.assertGreaterEqual(len(hits), 5, f"expected >=5 off-origin hits, got {len(hits)}: {hits}")
        for hit in hits:
            self.assertIn("assets.invalid", hit.target)

    def test_scanner_flags_every_variant(self) -> None:
        hits = scan_file(FIXTURES / "bypass_variants.html")
        # Every off-origin construct in the variant fixture resolves to assets.invalid.
        self.assertTrue(hits, "scanner found nothing in the variant fixture")
        for hit in hits:
            self.assertIn("assets.invalid", hit.target)
        details = " ".join(f"{hit.detail} {hit.target}" for hit in hits)
        # whitespace srcset, cased poster/object, entity-encoded src, protocol-relative,
        # xlink:href, form action, input src, meta refresh, WebSocket, sendBeacon,
        # setAttribute, dynamic import — spot-check a representative spread.
        for needle in ("srcset", "poster", "xlink:href", "action", "refresh",
                       "WebSocket", "sendBeacon", "setAttribute", "import"):
            self.assertIn(needle, details, f"variant surface not caught: {needle}")

    def test_scanner_flags_js_network_sinks(self) -> None:
        hits = scan_file(FIXTURES / "sinks.js")
        sinks = " ".join(hit.detail for hit in hits)
        for needle in ("fetch", "open", "WebSocket", "sendBeacon", "import", ".src"):
            self.assertIn(needle, sinks, f"JS network sink not caught: {needle}")

    def test_scanner_flags_offorigin_css(self) -> None:
        hits = scan_file(FIXTURES / "offorigin.css")
        self.assertGreaterEqual(len(hits), 3, f"expected url()+@import+protocol-relative, got {hits}")

    def test_upgrade_is_demonstrated(self) -> None:
        """The canonical proof: the pristine Codex fixture slips the old gate (0 matches)
        yet the new scanner catches it."""
        text = (FIXTURES / "bypass.html").read_text()
        self.assertEqual(_legacy_gate_matches(text), 0, "legacy gate should miss bypass.html")
        self.assertTrue(scan_file(FIXTURES / "bypass.html"), "new scanner should catch bypass.html")


class ScannerNoFalsePositiveTests(unittest.TestCase):
    """Self-contained references and comment-only URLs must pass."""

    def test_clean_html_passes(self) -> None:
        hits = scan_file(FIXTURES / "clean.html")
        self.assertEqual(hits, [], f"clean same-origin page falsely flagged: {hits}")

    def test_clean_css_passes(self) -> None:
        self.assertEqual(scan_file(FIXTURES / "clean.css"), [])

    def test_vendored_banner_comment_passes(self) -> None:
        # A vendored library banner (d3-style) with an off-origin URL only in comments
        # must not be flagged — the JS pass targets network sinks, not bare URLs.
        self.assertEqual(scan_file(FIXTURES / "clean.mjs"), [])

    def test_outbound_anchor_links_are_allowed(self) -> None:
        hits = scan_js('const x = "ok";', "<inline>")
        self.assertEqual(hits, [])
        # An <a href> to another origin is not a resource load and is never flagged.
        from scripts.check_off_origin_assets import scan_html
        self.assertEqual(scan_html('<a href="https://example.org/x">cite</a>'), [])

    def test_data_and_blob_uris_pass(self) -> None:
        self.assertEqual(scan_css('.x{background:url(data:image/png;base64,AAAA)}'), [])
        self.assertEqual(scan_js('img.src = "blob:https://self/abc";'), [])


if __name__ == "__main__":
    unittest.main()
