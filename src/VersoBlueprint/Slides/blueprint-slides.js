(function () {
  if (window.bpSlideNodeRuntime) return;

  function trimSlashes(text, side) {
    let value = String(text || "");
    if (side === "left" || side === "both") value = value.replace(/^\/+/, "");
    if (side === "right" || side === "both") value = value.replace(/\/+$/, "");
    return value;
  }

  function readBlueprintBaseUrl(node) {
    if (node instanceof Element) {
      const local = (node.getAttribute("data-bp-site-base") || "").trim();
      if (local) return local;
      const host = node.closest("[data-bp-site-base]");
      if (host instanceof Element) {
        const hostBase = (host.getAttribute("data-bp-site-base") || "").trim();
        if (hostBase) return hostBase;
      }
    }
    const runtimeBase =
      window.bpSlideNodeRuntimeConfig &&
      typeof window.bpSlideNodeRuntimeConfig.blueprintBaseUrl === "string"
        ? window.bpSlideNodeRuntimeConfig.blueprintBaseUrl
        : "";
    return runtimeBase.trim();
  }

  function rememberBlueprintBaseUrl(node) {
    const baseUrl = readBlueprintBaseUrl(node);
    if (!baseUrl) return "";
    if (!window.bpSlideNodeRuntimeConfig) window.bpSlideNodeRuntimeConfig = {};
    window.bpSlideNodeRuntimeConfig.blueprintBaseUrl = baseUrl;
    return baseUrl;
  }

  function resolveBlueprintHref(href, baseUrl) {
    const raw = String(href || "").trim();
    if (!raw || raw.startsWith("#")) return raw;
    if (/^[a-z][a-z0-9+.-]*:/i.test(raw) || raw.startsWith("//")) return raw;
    const base = String(baseUrl || "").trim();
    if (!base) return raw;
    return trimSlashes(base, "right") + "/" + trimSlashes(raw, "left");
  }

  function prepareBlueprintLinks(root, baseUrl) {
    if (!(root instanceof Element)) return;
    root.querySelectorAll("a[href]").forEach(function (link) {
      if (!(link instanceof HTMLAnchorElement)) return;
      const raw = (
        link.getAttribute("data-bp-slide-href") ||
        link.getAttribute("href") ||
        ""
      ).trim();
      if (!raw || raw.startsWith("#")) return;
      link.setAttribute("data-bp-slide-href", raw);
      link.href = resolveBlueprintHref(raw, baseUrl);
      link.target = "bp-slide-blueprint";
      link.rel = "noopener";
      link.setAttribute("data-bp-slide-link", "blueprint");
    });
  }

  function hideSlidePreviewPanels() {
    document
      .querySelectorAll("#bp-inline-preview-panel, #bp-inline-preview-child-panel, .bp_preview_panel")
      .forEach(function (panel) {
        if (!(panel instanceof HTMLElement)) return;
        panel.hidden = true;
        panel.style.left = "";
        panel.style.top = "";
      });
  }

  function hydrate(root, previewUtils) {
    const scope = root && typeof root.querySelectorAll === "function" ? root : document;
    scope.querySelectorAll(".bp_slide_node").forEach(function (node) {
      if (!(node instanceof Element)) return;
      const baseUrl = rememberBlueprintBaseUrl(node);
      prepareBlueprintLinks(node, baseUrl);
      previewUtils.hydrate(node);
    });
  }

  function hydrateWhenReady(root) {
    return new Promise(function (resolve) {
      window.VersoBlueprint.onRenderReady(function (previewUtils) {
        hydrate(root, previewUtils);
        resolve();
      });
    });
  }

  function registerPreviewHydrator(previewUtils) {
    previewUtils.registerPreviewHydrator("slideBlueprintLinks", function (root) {
      if (!(root instanceof Element)) return;
      prepareBlueprintLinks(root, readBlueprintBaseUrl(root));
    });
  }

  function start(previewUtils) {
    registerPreviewHydrator(previewUtils);
    hydrate(document, previewUtils);
    if (window.Reveal && typeof window.Reveal.on === "function") {
      window.Reveal.on("slidechanged", function (event) {
        hideSlidePreviewPanels();
        hydrate(event.currentSlide || document, previewUtils);
      });
      window.Reveal.on("ready", function (event) {
        hydrate(event.currentSlide || document, previewUtils);
      });
    }
  }

  window.VersoBlueprint.onRenderReady(function (previewUtils) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () {
        start(previewUtils);
      });
    } else {
      start(previewUtils);
    }
  });

  window.bpSlideNodeRuntime = { hydrate: hydrateWhenReady };
})();
