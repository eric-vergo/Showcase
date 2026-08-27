"""Browser regressions for the proof-overview surface.

The overview ships zero JavaScript, which is most of what these assertions are
checking: the diagram must be four real links in server-rendered SVG, the anchors
must actually reach the cards, and both colour schemes must be driven by the
`--bp-*` tokens rather than by a runtime that recolours the canvas.

The fixture is the curated test blueprint ``proof-overview`` (the same document
``BlueprintProofOverview.lean`` asserts against), generated into this checkout's
worktree-aware test-blueprint output root.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

from support import (
    PACKAGE_ROOT,
    assert_no_runtime_errors,
    find_free_port,
    record_runtime_errors,
    wait_for_server,
)

if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from scripts.blueprint_harness_paths import canonical_test_blueprint_output_dir  # noqa: E402


SLUG = "proof-overview"
OVERVIEW_MARKER = 'class="bp_overview"'


def _overview_route(site_dir: Path) -> str:
    """Route of the generated page carrying the overview surface."""
    for html in sorted(site_dir.rglob("index.html")):
        text = html.read_text(encoding="utf-8", errors="ignore")
        if OVERVIEW_MARKER in text:
            rel = html.parent.relative_to(site_dir).as_posix()
            return "/" if rel == "." else f"/{rel}/"
    raise AssertionError(f"no generated page under {site_dir} carries {OVERVIEW_MARKER}")


@pytest.fixture(scope="module")
def overview_site() -> Path:
    output_dir = canonical_test_blueprint_output_dir(SLUG, Path(__file__))
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            sys.executable,
            "-m",
            "scripts.blueprint_test_blueprints",
            "generate-all",
            SLUG,
            "--output-root",
            str(output_dir.parent),
        ],
        cwd=PACKAGE_ROOT,
        check=True,
    )
    site_dir = output_dir / "html-multi"
    assert site_dir.is_dir(), f"expected a generated site at {site_dir}"
    return site_dir


@pytest.fixture(scope="module")
def overview_server(overview_site: Path):
    port = find_free_port()
    proc = subprocess.Popen(
        [sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"],
        cwd=overview_site,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    server_url = f"http://127.0.0.1:{port}"
    wait_for_server(server_url, proc)
    yield server_url
    proc.terminate()
    proc.wait()


@pytest.fixture
def overview_page(page, overview_server: str, overview_site: Path):
    errors = record_runtime_errors(page)
    page.goto(f"{overview_server}{_overview_route(overview_site)}")
    page.wait_for_selector("a.bp_overview_node")
    yield page, errors


class TestProofOverview:
    def test_four_milestone_boxes_render_without_console_errors(self, overview_page):
        page, errors = overview_page
        assert page.locator("a.bp_overview_node").count() == 4
        assert page.locator("section.bp_overview_card").count() == 4
        # One deliberately unwitnessed edge, drawn dashed and badged.
        assert page.locator("path.bp_overview_edge_asserted").count() == 1
        assert page.locator("span.bp_overview_badge").count() == 1
        assert_no_runtime_errors(errors)

    def test_node_click_reaches_its_card(self, overview_page):
        page, errors = overview_page
        node = page.locator("a.bp_overview_node").first
        anchor = node.get_attribute("href")
        assert anchor and anchor.startswith("#ms-")
        node.click()
        page.wait_for_function(
            "hash => window.location.hash === hash", arg=anchor
        )
        card = page.locator(f"section.bp_overview_card{anchor}")
        assert card.count() == 1
        assert card.is_visible()
        box = card.bounding_box()
        viewport = page.viewport_size
        assert box is not None and viewport is not None
        # The card the diagram points at is on screen after the jump.
        assert box["y"] < viewport["height"]
        assert_no_runtime_errors(errors)

    def test_both_colour_schemes_repaint_the_diagram(self, overview_page):
        page, errors = overview_page
        rect = page.locator("rect.bp_overview_node_box").first

        def fill_for(scheme: str) -> str:
            page.evaluate(
                "scheme => document.documentElement.setAttribute('data-bp-color-scheme', scheme)",
                scheme,
            )
            return rect.evaluate("el => getComputedStyle(el).fill")

        light = fill_for("light")
        dark = fill_for("dark")
        assert light and dark
        assert light != dark, f"node fill did not change between schemes ({light})"
        assert_no_runtime_errors(errors)
