import json
import re
import urllib.request

from playwright.sync_api import expect, Page

from support import assert_no_runtime_errors, record_runtime_errors


class TestPreviewRuntimeRegressions:
    def test_public_xref_excludes_internal_blueprint_indexes(self, server: str):
        with urllib.request.urlopen(f"{server}/xref.json") as response:
            data = json.load(response)

        def has_domain(name: str) -> bool:
            return name in data or ("\u00ab" + name + "\u00bb") in data

        assert has_domain("Verso.Genre.Manual.section")
        assert has_domain("Informal.Block.informal")
        assert has_domain("Informal.Block.group")

        excluded = [
            "Informal.Block.informalCode",
            "Informal.Block.informalPreview",
            "Informal.Block.externalRenderedDecl",
            "Informal.Inline.bpCite.usages",
            "Informal.LeanCodePreview",
            "Informal.inlinePreview.store",
        ]
        assert not any(has_domain(name) for name in excluded)

        with urllib.request.urlopen(f"{server}/find/index.html") as response:
            find_html = response.read().decode("utf-8")
        for name in excluded:
            assert name not in find_html

    def test_highlighted_docstrings_read_text_content_without_layout_flush(self, server: str):
        with urllib.request.urlopen(f"{server}/Blueprint-Summary/") as response:
            html = response.read().decode("utf-8")

        assert "const str = d.innerText;" not in html
        assert 'const str = d.textContent || "";' in html

    def test_external_declaration_docstrings_render_markdown(self, server: str, page: Page):
        page.goto(f"{server}/Code-Panels/")

        doc_def = page.locator(
            '[data-decl="PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedDefinition"]'
        ).first
        expect(doc_def).to_have_count(1)
        expect(doc_def).to_have_attribute("data-kind", "def")
        expect(doc_def.locator(".bp_external_decl_header_status").first).to_contain_text("complete")
        doc_def_header = doc_def.locator(".bp_external_decl_kicker").first
        expect(doc_def_header.locator(".bp_external_decl_kind").first).to_contain_text("def")
        expect(doc_def_header.locator("code")).to_have_count(0)
        expect(doc_def_header.locator(".bp_external_decl_header_meta")).to_have_count(0)
        expect(doc_def.locator(".bp_external_decl_body > div.docstring").first).to_contain_text(
            "The first documented preview definition"
        )

        unsafe_def = page.locator(
            '[data-decl="PreviewRuntimeShowcase.CodePanelDecls.previewExternalUnsafeDefinition"]'
        ).first
        expect(unsafe_def).to_have_attribute("data-kind", "def")
        unsafe_header = unsafe_def.locator(".bp_external_decl_kicker").first
        expect(unsafe_header.locator(".bp_external_decl_kind").first).to_contain_text("def")
        expect(unsafe_header.locator(".bp_external_decl_header_meta").first).to_contain_text(
            "unsafe"
        )
        expect(unsafe_header.locator("code")).to_have_count(0)

        doc_fun = page.locator(
            '[data-decl="PreviewRuntimeShowcase.CodePanelDecls.previewDocstringedFunction"]'
        ).first
        expect(doc_fun).to_have_count(1)
        fun_doc = doc_fun.locator(".bp_external_decl_body > div.docstring").first
        expect(fun_doc).to_contain_text("Adds a small preview offset")
        expect(fun_doc.locator("code").first).to_contain_text("n")

        decl = page.locator(
            '[data-decl="PreviewRuntimeShowcase.CodePanelDecls.PreviewFreyPackage.ofCounterexample"]'
        ).first
        expect(decl).to_have_count(1)

        doc = decl.locator(".bp_external_decl_body > div.docstring").first
        expect(doc).to_be_visible()
        expect(doc).to_contain_text("Given a counterexample")
        expect(doc.locator("code").first).to_contain_text("a^p + b^p = c^p")
        expect(decl.locator(".bp_external_decl_body > pre.docstring")).to_have_count(0)

        stage = page.locator('[data-decl="PreviewRuntimeShowcase.CodePanelDecls.PreviewStage"]').first
        expect(stage).to_have_attribute("data-kind", "inductive")
        expect(stage.locator(".bp_external_decl_header_status").first).to_contain_text("complete")
        expect(stage.locator(".bp_external_decl_kind").first).to_contain_text("inductive")
        expect(stage.locator(".bp_external_decl_kicker").first).to_contain_text("2 constructors")
        expect(stage.locator(".bp_external_decl_body").first).to_contain_text("Constructors")
        expect(stage.locator(".bp_external_decl_body").first).to_contain_text("The initial stage")
        expect(stage.locator(".bp_external_decl_source_path").first).to_have_attribute(
            "href",
            re.compile(
                r"https://github\.com/leanprover/verso-blueprint/blob/[0-9a-f]{40}/tests/test_blueprints/preview_runtime_showcase/PreviewRuntimeShowcase/Chapters/CodePanels\.lean#L\d+-L\d+$"
            ),
        )

        cls = page.locator('[data-decl="PreviewRuntimeShowcase.CodePanelDecls.PreviewFold"]').first
        expect(cls).to_have_attribute("data-kind", "class")
        expect(cls.locator(".bp_external_decl_header_status").first).to_contain_text("complete")
        expect(cls.locator(".bp_external_decl_kind").first).to_contain_text("class")
        expect(cls.locator(".bp_external_decl_kicker").first).to_contain_text("2 methods")
        expect(cls.locator(".bp_external_decl_body").first).to_contain_text("Methods")
        expect(cls.locator(".bp_external_decl_body").first).to_contain_text("The neutral preview value")

    def test_inline_docstringed_constructs_showcase(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Code-Panels/")

        body = page.locator("body")
        expect(body).to_contain_text("PanelInlineDocstringedStructure")
        expect(body).to_contain_text("Inline package docstring used to compare literate Lean")
        expect(body).to_contain_text("dependent-looking field")
        expect(body).to_contain_text("PanelInlineDocstringedStage")
        expect(body).to_contain_text("Inline workflow stage docstring used to compare")
        expect(body).to_contain_text("A follow-up inline stage carrying a counter.")
        expect(body).to_contain_text("PanelInlineMixedConfig")
        expect(body).to_contain_text("PanelInlineMixedState")
        expect(body).to_contain_text("PanelInlineMixedFold")
        expect(body).to_contain_text("Inline mixed fold class docstring.")

        structure_name = page.locator("#PanelInlineDocstringedStructure").first
        expect(structure_name).to_have_count(1)
        page.wait_for_function(
            """() => !!document.querySelector("#PanelInlineDocstringedStructure")?._tippy"""
        )
        assert page.evaluate("(el) => !!el._tippy", structure_name.element_handle())

        inline_code = structure_name.locator("xpath=ancestor::code[1]")
        expect(inline_code.locator(".doc-comment.token").first).to_contain_text("/--")
        expect(inline_code.locator("div.docstring")).to_have_count(0)
        expect(inline_code.locator("pre.docstring")).to_have_count(0)

        structure_name.hover()
        hover = page.locator(".tippy-box").last
        expect(hover).to_contain_text("PanelInlineDocstringedStructure")
        expect(hover.locator("li").first).to_contain_text("The field")
        expect(hover.locator("code").filter(has_text="left").first).to_be_visible()
        expect(hover.locator("strong").filter(has_text="Bold text").first).to_be_visible()
        assert not any("cloneNode" in err for err in errors), "\n".join(errors)

    def test_used_by_panel_loads_manifest_only_when_opened(self, server: str, page: Page):
        attempts = {"count": 0}

        def count_manifest_fetch(route):
            attempts["count"] += 1
            route.continue_()

        page.route("**/-verso-data/blueprint-preview-manifest.json", count_manifest_fetch)
        page.goto(f"{server}/Preview-Relationships/")
        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()
        page.locator('.bp_wrapper[title="used_target"] .bp_used_by_wrap').first.wait_for()
        page.wait_for_timeout(250)

        status = page.evaluate(
            """() => {
                const utils = window.bpPreviewUtils;
                return utils.readSharedPreviewManifestStatus();
            }"""
        )
        assert attempts["count"] == 0
        assert status["state"] == "idle"

        page.locator('.bp_wrapper[title="used_target"] .bp_used_by_chip').first.hover()
        page.wait_for_function(
            """() => {
                const utils = window.bpPreviewUtils;
                return utils.readSharedPreviewManifestStatus().state === "ready";
            }"""
        )
        assert attempts["count"] == 1

    def test_code_summary_preview_opens_from_keyboard_focus_for_nonlink_trigger(
        self, server: str, page: Page
    ):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Preview-Relationships/")

        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()

        trigger = page.locator(
            '.bp_wrapper[title="used_target"] .bp_extra_slot_code .bp_code_summary_preview_wrap_active'
        ).first
        expect(trigger).to_have_count(1)
        expect(trigger).to_have_attribute("tabindex", "0")

        trigger.focus()

        panel = page.locator(
            '.bp_wrapper[title="used_target"] .bp_extra_slot_code .bp_code_summary_preview_panel'
        ).first
        expect(panel).to_be_visible()
        expect(panel.locator(".bp_code_summary_preview_title")).to_have_text("used_target")
        expect(panel.locator(".bp_code_decl_item")).to_have_count(1)
        expect(panel.locator(".bp_code_decl_item").first).to_contain_text("Nat.add")

        bbox = panel.bounding_box()
        viewport = page.viewport_size
        assert bbox is not None
        assert viewport is not None
        assert bbox["x"] >= 0
        assert bbox["y"] >= 0
        assert bbox["x"] + bbox["width"] <= viewport["width"]
        assert bbox["y"] + bbox["height"] <= viewport["height"]

        assert_no_runtime_errors(errors)

    def test_blueprint_summary_decl_link_hover_loads_manifest_backed_code_preview(
        self, server: str, page: Page
    ):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Blueprint-Summary/")

        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()
        page.locator("details").evaluate_all("els => els.forEach(el => { el.open = true; })")

        trigger = page.locator(
            '.bp_summary_decl_list .bp_inline_preview_ref[data-bp-preview-key^="Informal.LeanCodePreview"]'
        ).first
        expect(trigger).to_have_count(1)
        trigger.scroll_into_view_if_needed()
        trigger.hover()

        panel = page.locator("#bp-inline-preview-panel")
        body = panel.locator(".bp_inline_preview_panel_body")

        expect(panel).to_be_visible()
        expect(panel.locator(".bp_inline_preview_panel_title")).to_have_text(re.compile(r"^Lean declaration "))

        page.wait_for_function(
            """
            () => {
              const body = document.querySelector("#bp-inline-preview-panel .bp_inline_preview_panel_body");
              if (!body) return false;
              const html = body.innerHTML || "";
              const text = body.textContent || "";
              return html.trim().length > 0 && text.trim().length > 0;
            }
            """
        )

        assert body.inner_text().strip()
        assert body.inner_html().strip()

        assert_no_runtime_errors(errors)

    def test_exact_manifest_keys_keep_statement_and_proof_previews_distinct(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Preview-Relationships/")

        previews = page.evaluate(
            """async () => {
                const utils = window.bpPreviewUtils;
                const statement = await utils.loadSharedPreviewEntry("preview_facets--statement");
                const proof = await utils.loadSharedPreviewEntry("preview_facets--proof");
                return {
                    statement: {
                        html: utils.readPreviewTemplate(statement),
                        label: statement ? statement.label : null,
                        facet: statement ? statement.facet : null,
                        href: statement ? statement.href : null
                    },
                    proof: {
                        html: utils.readPreviewTemplate(proof),
                        label: proof ? proof.label : null,
                        facet: proof ? proof.facet : null,
                        href: proof ? proof.href : null
                    }
                };
            }"""
        )

        assert "Proof facet marker" in previews["proof"]["html"]
        assert "Proof facet marker" not in previews["statement"]["html"]
        assert "Statement facet marker" in previews["statement"]["html"]
        assert previews["statement"]["label"] == "preview_facets"
        assert previews["statement"]["facet"] == "statement"
        assert previews["proof"]["label"] == "preview_facets"
        assert previews["proof"]["facet"] == "proof"
        assert previews["statement"]["href"].startswith("Preview-Relationships/")
        assert "#--informal-preview-" in previews["statement"]["href"]
        assert previews["proof"]["href"] == previews["statement"]["href"]
        assert "bp_label_preview_tpl" not in page.content()

        assert_no_runtime_errors(errors)

    def test_summary_preview_retries_after_manifest_fetch_failure(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        attempts = {"count": 0}

        def fail_once(route):
            attempts["count"] += 1
            if attempts["count"] == 1:
                route.fulfill(
                    status=503,
                    body="preview manifest temporarily unavailable",
                    content_type="application/json",
                )
            else:
                route.continue_()

        page.route("**/-verso-data/blueprint-preview-manifest.json", fail_once)
        page.goto(f"{server}/Blueprint-Summary/")

        manifest = page.evaluate(
            """async () => {
                const utils = window.bpPreviewUtils;
                const trigger = document.querySelector(
                    ".bp_summary_preview_wrap_active[data-bp-preview-key]"
                );
                const previewKey =
                    trigger instanceof Element
                        ? (trigger.getAttribute("data-bp-preview-key") || "").trim()
                        : "";
                const first = await utils.loadSharedPreviewEntry(previewKey);
                const statusAfterFirst = utils.readSharedPreviewManifestStatus();
                const second = await utils.loadSharedPreviewEntry(previewKey);
                const statusAfterSecond = utils.readSharedPreviewManifestStatus();
                return {
                    previewKey: previewKey,
                    firstHtml: utils.readPreviewTemplate(first),
                    secondHtml: utils.readPreviewTemplate(second),
                    statusAfterFirst: statusAfterFirst,
                    statusAfterSecond: statusAfterSecond
                };
            }"""
        )

        assert manifest["previewKey"]
        assert manifest["firstHtml"] == ""
        assert manifest["statusAfterFirst"]["state"] == "error"
        assert "503" in manifest["statusAfterFirst"]["lastError"]
        assert "<p" in manifest["secondHtml"]
        assert manifest["statusAfterSecond"]["state"] == "ready"
        assert manifest["statusAfterSecond"]["attempts"] >= 2
        assert attempts["count"] > 1
        assert_no_runtime_errors(errors)

    def test_used_by_panel_loads_manifest_backed_preview(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Preview-Relationships/")

        wrap = page.locator('.bp_wrapper[title="used_target"] .bp_used_by_wrap').first
        expect(wrap).to_have_count(1)
        assert "bp_used_by_preview_fallback_tpl" not in page.content()

        chip = wrap.locator(".bp_used_by_chip").first
        chip.hover()

        expect(wrap.locator(".bp_used_by_item.bp_used_by_item_active")).to_have_count(1)

        body = wrap.locator(".bp_used_by_preview_body")
        page.wait_for_function(
            "(el) => !!el && el.innerHTML.includes('<p')",
            arg=body.element_handle(),
        )
        expect(body).to_contain_text("Statement depends on")

        assert_no_runtime_errors(errors)

    def test_bibliography_hover_does_not_throw_and_opens_panel(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Inline-Hover-Previews/")

        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()

        trigger = page.locator(
            '.bp_inline_preview_ref[data-bp-preview-title="Bibliography: preview.showcase.cite"]'
        ).first
        expect(trigger).to_have_count(1)
        assert "bp_inline_preview_tpl" not in page.content()

        trigger.hover()

        panel = page.locator("#bp-inline-preview-panel")
        expect(panel).to_be_visible()
        body = panel.locator(".bp_inline_preview_panel_body")
        expect(body).to_contain_text("Preview showcase citation")
        expect(body).to_contain_text("Locator")

        assert_no_runtime_errors(errors)

    def test_nested_inline_subhover_uses_child_panel(self, server: str, page: Page):
        errors = record_runtime_errors(page)
        page.goto(f"{server}/Inline-Hover-Previews/")

        page.locator("body[data-bp-inline-preview-bound='1']").wait_for()

        outer = page.locator(
            '.bp_inline_preview_ref[data-bp-preview-key="nested_outer--statement"]'
        ).first
        expect(outer).to_have_count(1)

        outer.hover()

        main_panel = page.locator("#bp-inline-preview-panel")
        expect(main_panel).to_be_visible()

        nested = main_panel.locator(
            '.bp_inline_preview_panel_body .bp_inline_preview_ref[data-bp-preview-key="nested_inner--statement"]'
        ).first
        expect(nested).to_have_count(1)

        nested.hover()

        child_panel = page.locator("#bp-inline-preview-child-panel")
        expect(child_panel).to_be_visible()
        expect(child_panel.locator(".bp_inline_preview_panel_body")).to_contain_text(
            "Nested inner preview definition."
        )
        expect(main_panel.locator(".bp_inline_preview_panel_body")).to_contain_text(
            "Outer theorem refers to"
        )

        assert_no_runtime_errors(errors)
