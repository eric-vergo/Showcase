import json
import subprocess
import sys
import urllib.request

import pytest
from playwright.sync_api import Page, expect

from support import (
    PACKAGE_ROOT,
    assert_no_runtime_errors,
    find_free_port,
    record_runtime_errors,
    wait_for_server,
)


@pytest.fixture(scope="session")
def slides_server(tmp_path_factory):
    output_dir = tmp_path_factory.mktemp("blueprint-slides-runtime")
    subprocess.run(
        ["scripts/lean-low-priority", "lake", "build", "VersoBlueprint.Slides"],
        cwd=PACKAGE_ROOT,
        check=True,
    )
    subprocess.run(
        [
            "scripts/lean-low-priority",
            "lake",
            "env",
            "lean",
            "--run",
            "tests/browser/BlueprintSlidesRuntime.lean",
            str(output_dir),
        ],
        cwd=PACKAGE_ROOT,
        check=True,
    )

    port = find_free_port()
    proc = subprocess.Popen(
        [sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1"],
        cwd=output_dir,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    server_url = f"http://127.0.0.1:{port}"
    wait_for_server(server_url, proc)
    yield server_url
    proc.terminate()
    proc.wait()


def expect_slide_link(page: Page, selector: str, original_href: str, rewritten_suffix: str) -> None:
    page.wait_for_function(
        """
        ([selector, originalHref, rewrittenSuffix]) => {
          const link = document.querySelector(selector);
          if (!(link instanceof HTMLAnchorElement)) return false;
          return link.getAttribute("data-bp-slide-href") === originalHref &&
            link.href.endsWith(rewrittenSuffix) &&
            link.target === "bp-slide-blueprint" &&
            link.rel === "noopener" &&
            link.getAttribute("data-bp-slide-link") === "blueprint";
        }
        """,
        arg=[selector, original_href, rewritten_suffix],
    )


class TestBlueprintSlidesRuntime:
    def test_generated_slides_render_static_shell_and_rewrite_links(
        self, slides_server: str, page: Page
    ):
        errors = record_runtime_errors(page)

        with urllib.request.urlopen(
            f"{slides_server}/-verso-data/blueprint-preview-manifest.json"
        ) as response:
            manifest = json.load(response)
        assert any(entry["key"] == "slides_relative--statement" for entry in manifest["previews"])

        page.goto(f"{slides_server}/")
        page.wait_for_function(
            """() => !!(window.bpSlideNodeRuntime && window.bpSlideNodeRuntime.hydrate)"""
        )

        node = page.locator(".bp_slide_node").first
        expect(node).to_have_attribute("data-bp-rendered", "static")
        expect(node).to_have_attribute("data-bp-site-base", "blueprint")
        expect(node).to_contain_text("Generated slide body")
        expect(node).not_to_contain_text("Loading Blueprint node")

        expect_slide_link(
            page,
            ".bp_slide_node_heading_link",
            "node.html",
            "/blueprint/node.html",
        )
        expect_slide_link(
            page,
            ".bp_slide_node .bp_content a",
            "body.html",
            "/blueprint/body.html",
        )
        expect_slide_link(
            page,
            ".bp_slide_group_wrap .bp_used_by_target",
            "peer.html",
            "/blueprint/peer.html",
        )

        page.evaluate("window.bpSlideNodeRuntime.hydrate(document)")
        expect_slide_link(
            page,
            ".bp_slide_node_heading_link",
            "node.html",
            "/blueprint/node.html",
        )

        assert_no_runtime_errors(errors)
