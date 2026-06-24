  // Runtime-local diagnostics and page-local template capture.

  export function previewDebugEnabled() {
    try {
      return window.localStorage.getItem("bp-debug-preview") === "1";
    } catch (_err) {
      return false;
    }
  }

  export function previewDebugLabel(node) {
    if (!(node instanceof Element)) return String(node);
    const parts = [node.tagName.toLowerCase()];
    const cls = (node.getAttribute("class") || "").trim();
    const pid = (node.getAttribute("data-bp-preview-id") || "").trim();
    const pkey = (node.getAttribute("data-bp-preview-key") || "").trim();
    const title = (node.getAttribute("data-bp-preview-title") || "").trim();
    if (cls) parts.push("." + cls.replaceAll(" ", "."));
    if (pid) parts.push("pid=" + pid);
    if (pkey) parts.push("pkey=" + pkey);
    if (title) parts.push("title=" + title);
    return parts.join(" ");
  }

  export function previewDebug(eventName, payload) {
    if (!previewDebugEnabled()) return;
    try {
      console.log("[bp-preview]", eventName, payload || {});
    } catch (_err) {}
  }

  export function collectPreviewTemplates(root, selector, keyAttr) {
    const map = new Map();
    if (!(root instanceof Element || root instanceof Document)) return map;
    if (typeof selector !== "string" || selector.length === 0) return map;
    const keyName =
      typeof keyAttr === "string" && keyAttr.length > 0
        ? keyAttr
        : "data-bp-preview-label";
    root.querySelectorAll(selector).forEach(function (tpl) {
      if (!(tpl instanceof Element)) return;
      const label = tpl.getAttribute(keyName) || "";
      let html = "";
      if (tpl instanceof HTMLTemplateElement) {
        const content = tpl.content.cloneNode(true);
        if (content instanceof DocumentFragment) {
          const wrapper = document.createElement("div");
          wrapper.appendChild(content);
          html = (wrapper.innerHTML || "").trim();
        }
      }
      if (!html) {
        html = (tpl.innerHTML || "").trim();
      }
      if (label && html) {
        map.set(label, html);
      }
    });
    return map;
  }

  export function readHtml(entry) {
    if (typeof entry === "string") {
      return entry;
    }
    if (entry && typeof entry === "object" && typeof entry.html === "string") {
      return entry.html;
    }
    return "";
  }

  export function escapeHtml(text) {
    return String(text || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  export const previewRuntimeBase = {
    previewDebugEnabled,
    previewDebugLabel,
    previewDebug,
    collectPreviewTemplates,
    readHtml,
    escapeHtml
  };
