import json
import subprocess
import sys
import urllib.request
from pathlib import Path

import pytest
from playwright.sync_api import Page, expect

from support import (
    PACKAGE_ROOT,
    assert_no_runtime_errors,
    find_free_port,
    record_runtime_errors,
    wait_for_server,
)
from scripts.blueprint_harness_references import (
    maybe_rewrite_in_repo_blueprint_dependency,
    restore_tracked_project_manifest,
    snapshot_tracked_project_manifest,
)
from scripts.blueprint_harness_utils import lean_low_priority_command, rebuild_embedded_asset_owners


def generate_project_template_preview_data(output_dir: Path) -> tuple[Path, Path]:
    project_dir = PACKAGE_ROOT / "project_template"
    manifest_snapshot = snapshot_tracked_project_manifest(project_dir)
    rewritten_lakefile, original_lakefile_text = maybe_rewrite_in_repo_blueprint_dependency(
        project_dir,
        PACKAGE_ROOT,
    )
    try:
        subprocess.run(
            lean_low_priority_command(PACKAGE_ROOT, "lake", "update"),
            cwd=project_dir,
            check=True,
        )
        subprocess.run(
            lean_low_priority_command(PACKAGE_ROOT, "lake", "build", "ProjectTemplate"),
            cwd=project_dir,
            check=True,
        )
        subprocess.run(
            lean_low_priority_command(
                PACKAGE_ROOT,
                "lake",
                "env",
                "lean",
                "--run",
                "ProjectTemplateMain.lean",
                "--output",
                str(output_dir),
                "--without-html-single",
                "--with-html-multi",
            ),
            cwd=project_dir,
            check=True,
        )
        data_dir = output_dir / "html-multi" / "-verso-data"
        manifest_path = data_dir / "blueprint-manifest.json"
        html_cache_path = data_dir / "blueprint-html-cache.json"
        assert manifest_path.exists()
        assert html_cache_path.exists()
        return manifest_path, html_cache_path
    finally:
        if rewritten_lakefile is not None and original_lakefile_text is not None:
            rewritten_lakefile.write_text(original_lakefile_text, encoding="utf-8")
        restore_tracked_project_manifest(manifest_snapshot)


@pytest.fixture(scope="session")
def slides_server(tmp_path_factory):
    output_dir = tmp_path_factory.mktemp("blueprint-slides-runtime")
    manifest_path, html_cache_path = generate_project_template_preview_data(
        output_dir / "project-template-blueprint"
    )
    rebuild_embedded_asset_owners(PACKAGE_ROOT)
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
            str(manifest_path),
            str(html_cache_path),
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
            f"{slides_server}/-verso-data/blueprint-manifest.json"
        ) as response:
            manifest = json.load(response)
        with urllib.request.urlopen(
            f"{slides_server}/-verso-data/blueprint-html-cache.json"
        ) as response:
            html_cache = json.load(response)
        html_by_key = {entry["key"]: entry["html"] for entry in html_cache["entries"]}
        assert "traverseState" not in manifest
        collatz_entry = next(
            entry
            for entry in manifest["previews"]
            if entry["key"] == "collatz_step--statement"
        )
        assert {entry["label"] for entry in collatz_entry["uses"]} == {
            "addition_spec",
            "multiplication_spec",
        }
        assert [entry["label"] for entry in collatz_entry["usedBy"]] == ["collatz_conjecture"]
        assert collatz_entry["group"]["label"] == "collatz_core"
        assert len(collatz_entry["leanCodePreviewKeys"]) == 2
        assert collatz_entry["codeData"]
        assert "blocks" not in collatz_entry
        assert "html" not in collatz_entry
        assert "bp_math inline" in html_by_key[collatz_entry["key"]]
        code_entries = [
            entry
            for entry in manifest["previews"]
            if entry["key"] in collatz_entry["leanCodePreviewKeys"]
        ]
        assert len(code_entries) == 2
        assert all("leanCode" not in entry for entry in code_entries)
        assert all("class=\"hl lean block\"" in html_by_key[entry["key"]] for entry in code_entries)

        page.goto(f"{slides_server}/")
        page.wait_for_function(
            """() => !!(window.bpSlideNodeRuntime && window.bpSlideNodeRuntime.hydrate)"""
        )

        node = page.locator(".bp_slide_node").first
        expect(node).to_have_attribute("data-bp-rendered", "static")
        expect(node).to_have_attribute("data-bp-site-base", "blueprint")
        expect(node).to_contain_text("The Collatz step")
        expect(node).to_contain_text("n / 2")
        expect(node).to_contain_text("3 * n + 1")
        expect(node).not_to_contain_text("Loading Blueprint node")
        expect(node.locator(".bp_content .bp_math.inline")).to_have_count(3)
        expect(node.locator(".bp_extra_slot_group .bp_relation_chip")).to_have_text("group")
        expect(node.locator(".bp_extra_slot_uses .bp_relation_chip")).to_have_text("uses 2")
        expect(node.locator(".bp_extra_slot_code .bp_code_link")).to_have_count(1)
        expect(node.locator(".bp_extra_slot_used_by .bp_relation_chip")).to_have_text("used by 1")
        assert node.locator(".bp_extras > .bp_extra_slot").evaluate_all(
            """slots => slots.map(slot => {
              if (slot.classList.contains("bp_extra_slot_group")) return "group";
              if (slot.classList.contains("bp_extra_slot_uses")) return "uses";
              if (slot.classList.contains("bp_extra_slot_used_by")) return "used-by";
              if (slot.classList.contains("bp_extra_slot_code")) return "code";
              return "unknown";
            })"""
        ) == ["group", "uses", "used-by", "code"]
        assert node.locator(".bp_extras").evaluate(
            """extras => getComputedStyle(extras).gridTemplateAreas"""
        ) == '"group uses used code"'
        chip_boxes = node.locator(
            ".bp_extra_slot_group .bp_relation_chip,"
            ".bp_extra_slot_uses .bp_relation_chip,"
            ".bp_extra_slot_used_by .bp_relation_chip,"
            ".bp_extra_slot_code .bp_code_link"
        ).evaluate_all(
            """chips => chips.map(chip => {
              const box = chip.getBoundingClientRect();
              return { top: box.top, height: box.height };
            })"""
        )
        assert max(box["top"] for box in chip_boxes) - min(box["top"] for box in chip_boxes) < 1
        assert max(box["height"] for box in chip_boxes) - min(box["height"] for box in chip_boxes) < 1
        code_chip = node.locator(".bp_extra_slot_code .bp_code_summary_preview_wrap_active")
        expect(code_chip).to_have_count(1)
        code_chip.hover()
        code_panel = page.locator(".bp_code_summary_preview_panel").first
        expect(code_panel).to_be_visible()
        expect(code_panel.locator(".bp_code_summary_preview_title")).to_have_text("collatz_step")
        expect(code_panel.locator(".bp_code_hover_label")).to_have_text(
            "Associated Lean declarations"
        )
        expect(code_panel.locator(".bp_code_decl_item")).to_have_count(2)
        decl_items = code_panel.locator(".bp_code_decl_item").all_inner_texts()
        assert any("collatzStep" in item and "[complete]" in item for item in decl_items)
        assert any(
            "collatzTerminatesAtOne" in item and "[complete]" in item
            for item in decl_items
        )
        code_panel_metrics = code_panel.evaluate(
            """panel => {
              const panelBox = panel.getBoundingClientRect();
              const bodyBox = panel.querySelector(".bp_code_summary_preview_body").getBoundingClientRect();
              const item = panel.querySelector(".bp_code_decl_item");
              const itemBox = item.getBoundingClientRect();
              const code = item.querySelector("code");
              return {
                panelRight: panelBox.right,
                viewportWidth: window.innerWidth,
                itemLeft: itemBox.left,
                itemRight: itemBox.right,
                bodyLeft: bodyBox.left,
                bodyRight: bodyBox.right,
                codeFontSize: parseFloat(getComputedStyle(code).fontSize)
              };
            }"""
        )
        assert code_panel_metrics["panelRight"] <= code_panel_metrics["viewportWidth"] - 8
        assert code_panel_metrics["itemLeft"] >= code_panel_metrics["bodyLeft"]
        assert code_panel_metrics["itemRight"] <= code_panel_metrics["bodyRight"] + 1
        assert code_panel_metrics["codeFontSize"] >= 12
        expect(page.locator("#bp-inline-preview-panel")).to_be_hidden()
        expect(node.locator(".bp_code_panel_wrapper .bp_code_progress")).to_have_count(1)
        expect(
            node.locator(".bp_code_panel_wrapper .bp_code_progress_segment_ok")
        ).to_have_count(2)
        expect(node.locator(".bp_slide_code_body code.hl.lean.block")).to_have_count(1)
        assert node.locator(".bp_slide_code_body .keyword.token").count() >= 2
        expect(node.locator(".bp_slide_code_body")).to_contain_text("collatzStep")

        expect_slide_link(
            page,
            ".bp_slide_node_heading_link",
            "Collatz/#--informal-preview-collatz_step--statement",
            "/blueprint/Collatz/#--informal-preview-collatz_step--statement",
        )
        expect_slide_link(
            page,
            ".bp_slide_node .bp_content a[title='multiplication_spec']",
            "Multiplication/#--informal-preview-multiplication_spec--statement",
            "/blueprint/Multiplication/#--informal-preview-multiplication_spec--statement",
        )
        expect_slide_link(
            page,
            ".bp_extra_slot_group .bp_relation_target",
            "Collatz/#--informal-preview-collatz_conjecture--statement",
            "/blueprint/Collatz/#--informal-preview-collatz_conjecture--statement",
        )
        expect_slide_link(
            page,
            ".bp_extra_slot_used_by .bp_relation_target",
            "Collatz/#--informal-preview-collatz_conjecture--statement",
            "/blueprint/Collatz/#--informal-preview-collatz_conjecture--statement",
        )

        page.evaluate("window.bpSlideNodeRuntime.hydrate(document)")
        expect_slide_link(
            page,
            ".bp_slide_node_heading_link",
            "Collatz/#--informal-preview-collatz_step--statement",
            "/blueprint/Collatz/#--informal-preview-collatz_step--statement",
        )

        assert_no_runtime_errors(errors)
