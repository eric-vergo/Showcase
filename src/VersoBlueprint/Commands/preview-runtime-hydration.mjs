  // Runtime-local registries. Keep these private and expose behavior through
  // the render API instead of growing new window globals.
  export const previewHydrators = new Map();
  let bindTemplatePreviewDescriptorsImpl = function (_root) { return []; };

  // Hydration extension points and math rendering.

  export function setTemplatePreviewDescriptorBinder(fn) {
    bindTemplatePreviewDescriptorsImpl = typeof fn === "function"
      ? fn
      : function (_root) { return []; };
  }

  export function hydrateRenderedPreview(root, options) {
    const opts = options && typeof options === "object" ? options : {};
    if (!(root instanceof Element || root instanceof Document)) return false;
    if (opts.hydrate !== false) {
      bindTemplatePreviewDescriptorsImpl(root);
      runPreviewHydrators(root);
    }
    if (opts.renderMath !== false) {
      renderBlueprintMath(root);
    }
    return true;
  }

  export function renderBlueprintMath(root) {
    if (!(root instanceof Element || root instanceof Document)) return;
    if (typeof katex !== "object" || typeof katex.render !== "function") return;
    const resolvePrelude = function (m) {
      if (!(m instanceof Element)) return "";
      const table =
        window.bpTexPreludeTable && typeof window.bpTexPreludeTable === "object"
          ? window.bpTexPreludeTable
          : {};
      const preludeId = (m.getAttribute("data-bp-tex-prelude-id") || "").trim();
      if (preludeId && typeof table[preludeId] === "string") {
        return table[preludeId].trim();
      }
      const fallback = m.getAttribute("data-bp-tex-prelude");
      return typeof fallback === "string" ? fallback.trim() : "";
    };
    const renderAll = function (selector, displayMode) {
      root.querySelectorAll(selector).forEach(function (m) {
        if (!(m instanceof Element)) return;
        if (m.getAttribute("data-bp-math-rendered") === "1") return;
        try {
          const tex = m.textContent || "";
          const prelude = resolvePrelude(m);
          const renderInput = prelude ? prelude + "\n" + tex : tex;
          katex.render(renderInput, m, { throwOnError: false, displayMode: displayMode });
          m.setAttribute("data-bp-math-rendered", "1");
        } catch (_err) {}
      });
    };
    renderAll(".bp_math.inline", false);
    renderAll(".bp_math.display", true);
  }

  export function registerPreviewHydrator(name, fn) {
    if (typeof name !== "string" || name.length === 0) return;
    if (typeof fn !== "function") return;
    previewHydrators.set(name, fn);
  }

  export function runPreviewHydrators(root) {
    if (!(root instanceof Element || root instanceof Document)) return;
    previewHydrators.forEach(function (fn) {
      if (typeof fn !== "function") return;
      try {
        fn(root);
      } catch (_err) {}
    });
  }

  export const previewRuntimeHydration = {
    previewHydrators,
    setTemplatePreviewDescriptorBinder,
    hydrateRenderedPreview,
    renderBlueprintMath,
    registerPreviewHydrator,
    runPreviewHydrators
  };

export default previewRuntimeHydration;
