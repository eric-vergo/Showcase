(function () {
  function setText(root, selector, text) {
    const node = root.querySelector(selector);
    if (node) node.textContent = text;
  }

  function appendTextNode(parent, tagName, className, text) {
    const node = document.createElement(tagName);
    if (className) node.className = className;
    node.textContent = text;
    parent.appendChild(node);
    return node;
  }

  function appendFact(parent, label, value) {
    if (value === null || typeof value === "undefined" || value === "" || value === 0) return;
    const fact = appendTextNode(parent, "span", "bp_custom_render_client_fact", "");
    appendTextNode(fact, "strong", "", label);
    fact.appendChild(document.createTextNode(" " + value));
  }

  function appendPreviewMeta(parent, text) {
    if (!text) return;
    appendTextNode(parent, "span", "", text);
  }

  function previewKeyFor(api, example) {
    return api.previewKey(example.dataset.bpPreviewLabel, example.dataset.bpPreviewFacet);
  }

  function expectedOk(example) {
    return example.dataset.bpExpectOk !== "false";
  }

  function writeResultAttrs(example, result) {
    example.dataset.bpPreviewKey = result.key || "";
    example.dataset.bpRenderOk = result.ok ? "true" : "false";
    example.dataset.bpExpectedOk = expectedOk(example) ? "true" : "false";
    example.dataset.bpRenderReason = result.reason || "";
    example.dataset.bpCanonicalPreview = result.canonicalHtml ? "true" : "false";
    example.dataset.bpCanonicalSourceHref = result.canonicalSourceHref || "";
    if (result.manifestEntry) {
      example.dataset.bpManifestLabel = result.manifestEntry.label || "";
      example.dataset.bpManifestFacet = result.manifestEntry.facet || "";
      example.dataset.bpManifestHref = result.manifestEntry.href || "";
      example.dataset.bpManifestTitle = result.manifestEntry.title || "";
    }
  }

  function renderPreviewHeader(example, result) {
    const target = example.querySelector("[data-bp-custom-client-preview-header]");
    if (!target) return;
    target.replaceChildren();
    if (example.dataset.bpCustomClientExample === "render-canonical-preview-into" && result.ok) {
      target.hidden = true;
      return;
    }
    target.hidden = false;
    const entry = result.manifestEntry;
    if (!entry) {
      appendTextNode(
        target,
        "div",
        "bp_custom_render_client_preview_title",
        result.key || "Preview unavailable"
      );
      appendTextNode(
        target,
        "div",
        "bp_custom_render_client_preview_meta",
        result.reason || "not available"
      );
      return;
    }

    const title = document.createElement(entry.href ? "a" : "span");
    title.className = "bp_custom_render_client_preview_title";
    title.textContent = entry.title || result.key;
    if (entry.href) title.href = entry.href;
    target.appendChild(title);

    const meta = appendTextNode(target, "div", "bp_custom_render_client_preview_meta", "");
    appendPreviewMeta(meta, entry.kind);
    appendPreviewMeta(meta, entry.facet ? "facet " + entry.facet : "");
    appendTextNode(meta, "code", "", result.key || "");
  }

  function renderManifestSummary(example, result) {
    const target = example.querySelector("[data-bp-custom-client-summary]");
    if (!target) return;
    target.replaceChildren();
    if (example.dataset.bpCustomClientExample === "render-canonical-preview-into" && result.ok) {
      target.hidden = true;
      return;
    }
    target.hidden = false;
    if (!result.ok && !result.manifestEntry) {
      appendFact(target, "Status", result.reason || "not available");
      return;
    }
    const entry = result.manifestEntry;
    if (!entry) return;
    const facts = appendTextNode(target, "div", "bp_custom_render_client_facts", "");
    appendFact(facts, "Key", result.key);
    appendFact(facts, "Kind", entry.kind);
    appendFact(facts, "Facet", entry.facet);
    appendFact(facts, "Label", entry.label);
    appendFact(facts, "Group", entry.group ? entry.group.title : "");
    appendFact(facts, "Statement uses", Array.isArray(entry.statementUses) ? entry.statementUses.length : 0);
    appendFact(facts, "Proof uses", Array.isArray(entry.proofUses) ? entry.proofUses.length : 0);
    appendFact(facts, "Used by", Array.isArray(entry.usedBy) ? entry.usedBy.length : 0);
    appendFact(facts, "Code previews", Array.isArray(entry.leanCodePreviewKeys) ? entry.leanCodePreviewKeys.length : 0);
  }

  async function renderExample(api, example) {
    const body = example.querySelector("[data-bp-custom-client-body]");
    if (!body) return null;
    const key = previewKeyFor(api, example);
    const exampleName = example.dataset.bpCustomClientExample;
    let result;
    if (exampleName === "render-preview-into") {
      result = await api.renderPreviewInto(body, key);
    } else if (exampleName === "render-canonical-preview-into") {
      result = await api.renderCanonicalPreviewInto(body, key);
    } else {
      throw new Error("Unknown custom render client example: " + exampleName);
    }
    writeResultAttrs(example, result);
    renderPreviewHeader(example, result);
    renderManifestSummary(example, result);
    return result;
  }

  async function bindClient(api, root) {
    if (!(root instanceof HTMLElement)) return;
    if (root.dataset.bpCustomClientBound === "true") return;
    root.dataset.bpCustomClientBound = "true";
    root.dataset.bpCustomClientStatus = "loading";
    setText(root, "[data-bp-custom-client-status-text]", "Loading");
    try {
      const examples = Array.from(root.querySelectorAll("[data-bp-custom-client-example]"));
      if (examples.length === 0) {
        throw new Error("Custom render client root has no preview examples");
      }
      const results = await Promise.all(examples.map(function (example) {
        return renderExample(api, example);
      }));
      const ok = results.every(function (result, index) {
        return result && result.ok === expectedOk(examples[index]);
      });
      root.dataset.bpCustomClientStatus = ok ? "ready" : "error";
      setText(root, "[data-bp-custom-client-status-text]", ok ? "Ready" : "Incomplete");
    } catch (err) {
      root.dataset.bpCustomClientStatus = "error";
      root.dataset.bpCustomClientError = err && err.message ? err.message : String(err);
      setText(root, "[data-bp-custom-client-status-text]", "Error");
    }
  }

  function bindAll(api) {
    document.querySelectorAll("[data-bp-custom-render-client]").forEach(function (root) {
      bindClient(api, root);
    });
  }

  window.VersoBlueprint.onRenderReady(function (api) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () {
        bindAll(api);
      });
    } else {
      bindAll(api);
    }
  });
})();
