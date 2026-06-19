(function () {
  if (window.VersoBlueprint && window.VersoBlueprint.render) return;

  const previewHydrators = new Map();

  // Debug and local-template utilities.

  function previewDebugEnabled() {
    try {
      return window.localStorage.getItem("bp-debug-preview") === "1";
    } catch (_err) {
      return false;
    }
  }

  function previewDebugLabel(node) {
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

  function previewDebug(eventName, payload) {
    const entry = {
      at: Date.now(),
      event: eventName,
      payload: payload || {}
    };
    try {
      if (!Array.isArray(window.bpPreviewTrace)) {
        window.bpPreviewTrace = [];
      }
      window.bpPreviewTrace.push(entry);
      if (window.bpPreviewTrace.length > 200) {
        window.bpPreviewTrace.splice(0, window.bpPreviewTrace.length - 200);
      }
    } catch (_err) {}
    if (!previewDebugEnabled()) return;
    try {
      console.log("[bp-preview]", eventName, payload || {});
    } catch (_err) {}
  }

  function collectPreviewTemplates(root, selector, keyAttr) {
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

  function readHtml(entry) {
    if (typeof entry === "string") {
      return entry;
    }
    if (entry && typeof entry === "object" && typeof entry.html === "string") {
      return entry.html;
    }
    return "";
  }

  function escapeHtml(text) {
    return String(text || "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  // Manifest and rendered-fragment cache stores.

  function blueprintDataUrl(filename) {
    const safeFilename = String(filename || "").trim();
    if (!safeFilename) return "-verso-data/";
    try {
      const url = new URL(window.location.href);
      const markers = ["/html-multi/", "/html-single/"];
      for (const marker of markers) {
        const idx = url.pathname.indexOf(marker);
        if (idx >= 0) {
          const rootPath = url.pathname.slice(0, idx + marker.length);
          return rootPath + "-verso-data/" + safeFilename;
        }
      }
    } catch (_err) {}
    return "-verso-data/" + safeFilename;
  }

  function fetchBlueprintJson(url) {
    return fetch(url).then(function (resp) {
      if (!resp.ok) {
        throw new Error("HTTP " + resp.status + " while loading " + url);
      }
      return resp.json();
    });
  }

  function decodeBlueprintKeyedEntries(data, spec) {
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      throw new Error(spec.objectMessage);
    }
    const entries = data[spec.arrayField];
    if (!Array.isArray(entries)) {
      throw new Error(spec.missingArrayMessage);
    }
    const map = new Map();
    entries.forEach(function (entry, index) {
      if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
        throw new Error(spec.entryName + " " + index + " must be an object");
      }
      const key = typeof entry.key === "string" ? entry.key.trim() : "";
      if (!key) {
        throw new Error(spec.entryName + " " + index + " is missing key");
      }
      if (typeof spec.validateEntry === "function") {
        spec.validateEntry(entry, index);
      }
      if (map.has(key)) {
        throw new Error(spec.duplicateMessage + key);
      }
      map.set(key, entry);
    });
    return map;
  }

  function decodeBlueprintManifest(data) {
    return decodeBlueprintKeyedEntries(data, {
      arrayField: "previews",
      objectMessage: "Blueprint manifest must be an object with a previews array",
      missingArrayMessage: "Blueprint manifest is missing previews array",
      entryName: "Blueprint manifest entry",
      duplicateMessage: "Blueprint manifest contains duplicate key "
    });
  }

  function decodeBlueprintHtmlCache(data) {
    return decodeBlueprintKeyedEntries(data, {
      arrayField: "entries",
      objectMessage: "Blueprint HTML cache must be an object with an entries array",
      missingArrayMessage: "Blueprint HTML cache is missing entries array",
      entryName: "Blueprint HTML cache entry",
      duplicateMessage: "Blueprint HTML cache contains duplicate key ",
      validateEntry: function (entry, index) {
        if (typeof entry.html !== "string") {
          throw new Error("Blueprint HTML cache entry " + index + " is missing html");
        }
        if (!entry.html.trim()) {
          throw new Error("Blueprint HTML cache entry " + index + " has empty html");
        }
      }
    });
  }

  function blueprintManifestUrl() {
    return blueprintDataUrl("blueprint-manifest.json");
  }

  function missingPreviewKeyDiagnosticHtml() {
    return (
      "<div class=\"bp_html_cache_preview_notice\">" +
      "<p><strong>Preview key missing.</strong></p>" +
      "<p>Provide a manifest/cache preview key such as " +
      "<code>some_label--statement</code> or <code>some_label--proof</code>.</p>" +
      "</div>"
    );
  }

  function blueprintHtmlCacheUrl() {
    return blueprintDataUrl("blueprint-html-cache.json");
  }

  const blueprintManifestStore = {
    status: null,
    map: null,
    promise: null,
    url: blueprintManifestUrl,
    decode: decodeBlueprintManifest,
    debugLabel: "manifest.loadFailed",
    consoleLabel: "Blueprint manifest",
    unavailableTitle: "Preview manifest unavailable.",
    requiredFilename: "blueprint-manifest.json",
    missingTitle: "Preview entry missing from manifest.",
    missingReadyText: "The site emitted a Blueprint manifest, but this preview key was not present."
  };

  const blueprintHtmlCacheStore = {
    status: null,
    map: null,
    promise: null,
    url: blueprintHtmlCacheUrl,
    decode: decodeBlueprintHtmlCache,
    debugLabel: "htmlCache.loadFailed",
    consoleLabel: "Blueprint HTML cache",
    unavailableTitle: "Preview HTML cache unavailable.",
    requiredFilename: "blueprint-html-cache.json",
    missingTitle: "Preview entry missing from HTML cache.",
    missingReadyText: "The site emitted a rendered-fragment cache, but this preview key was not present."
  };

  function defaultBlueprintStoreStatus(store) {
    return {
      state: "idle",
      attempts: 0,
      url: store.url(),
      lastError: "",
      entryCount: 0
    };
  }

  function cloneBlueprintStoreStatus(store, status) {
    const fallback = defaultBlueprintStoreStatus(store);
    if (!status || typeof status !== "object") return fallback;
    return {
      state: typeof status.state === "string" ? status.state : fallback.state,
      attempts: Number.isFinite(status.attempts) ? status.attempts : fallback.attempts,
      url: typeof status.url === "string" ? status.url : fallback.url,
      lastError: typeof status.lastError === "string" ? status.lastError : fallback.lastError,
      entryCount: Number.isFinite(status.entryCount) ? status.entryCount : fallback.entryCount
    };
  }

  function readBlueprintStoreStatus(store) {
    return cloneBlueprintStoreStatus(store, store.status);
  }

  function setBlueprintStoreStatus(store, status) {
    store.status = status;
    return status;
  }

  function readBlueprintManifestStatus() {
    return readBlueprintStoreStatus(blueprintManifestStore);
  }

  function readBlueprintHtmlCacheStatus() {
    return readBlueprintStoreStatus(blueprintHtmlCacheStore);
  }

  function blueprintStoreDiagnosticHtml(store, previewKey) {
    const status = readBlueprintStoreStatus(store);
    const trimmedKey = typeof previewKey === "string" ? previewKey.trim() : "";
    const keyHtml = trimmedKey ? "<code>" + escapeHtml(trimmedKey) + "</code>" : "this preview";
    if (status.state === "error") {
      const errorHtml = status.lastError
        ? "<p>Last load error: <code>" + escapeHtml(status.lastError) + "</code></p>"
        : "";
      return (
        "<div class=\"bp_html_cache_preview_notice\">" +
        "<p><strong>" + store.unavailableTitle + "</strong></p>" +
        "<p>Blueprint previews require <code>-verso-data/" + store.requiredFilename + "</code>. " +
        "Rebuild the site or retry after the current build finishes.</p>" +
        "<p>Requested preview: " + keyHtml + "</p>" +
        errorHtml +
        "</div>"
      );
    }
    if (status.state === "ready" && trimmedKey) {
      return (
        "<div class=\"bp_html_cache_preview_notice\">" +
        "<p><strong>" + store.missingTitle + "</strong></p>" +
        "<p>Requested preview: " + keyHtml + "</p>" +
        "<p>" + store.missingReadyText + "</p>" +
        "</div>"
      );
    }
    return "";
  }

  function blueprintManifestDiagnosticHtml(previewKey) {
    return blueprintStoreDiagnosticHtml(blueprintManifestStore, previewKey);
  }

  function blueprintHtmlCacheDiagnosticHtml(previewKey) {
    return blueprintStoreDiagnosticHtml(blueprintHtmlCacheStore, previewKey);
  }

  function fetchBlueprintStoreData(store) {
    const jsonUrl = store.url();
    return fetchBlueprintJson(jsonUrl).then(function (data) {
      return { data: data, url: jsonUrl };
    });
  }

  function loadBlueprintStore(store) {
    const existing = store.map;
    if (existing instanceof Map) {
      return Promise.resolve(existing);
    }
    const existingPromise = store.promise;
    if (existingPromise) {
      return existingPromise;
    }
    const url = store.url();
    const previousStatus = readBlueprintStoreStatus(store);
    const attempts =
      Number.isFinite(previousStatus.attempts) ? previousStatus.attempts + 1 : 1;
    setBlueprintStoreStatus(store, {
      state: "loading",
      attempts: attempts,
      url: url,
      lastError: "",
      entryCount: 0
    });
    let promise = null;
    promise = fetchBlueprintStoreData(store)
      .then(function (result) {
        const map = store.decode(result.data);
        store.map = map;
        setBlueprintStoreStatus(store, {
          state: "ready",
          attempts: attempts,
          url: result.url,
          lastError: "",
          entryCount: map.size
        });
        return map;
      })
      .catch(function (err) {
        const message =
          err && typeof err.message === "string" && err.message.length > 0
            ? err.message
            : String(err);
        store.map = null;
        setBlueprintStoreStatus(store, {
          state: "error",
          attempts: attempts,
          url: url,
          lastError: message,
          entryCount: 0
        });
        previewDebug(store.debugLabel, {
          url: url,
          attempts: attempts,
          error: message
        });
        try {
          console.error("[bp-preview] " + store.consoleLabel + " load failed", {
            url: url,
            error: message
          });
        } catch (_consoleErr) {}
        return new Map();
      })
      .then(function (map) {
        if (store.promise === promise) {
          store.promise = null;
        }
        return map;
      });
    store.promise = promise;
    return promise;
  }

  function loadBlueprintManifest() {
    return loadBlueprintStore(blueprintManifestStore);
  }

  function loadBlueprintHtmlCache() {
    return loadBlueprintStore(blueprintHtmlCacheStore);
  }

  function readBlueprintStoreEntry(store, previewKey) {
    if (typeof previewKey !== "string" || previewKey.length === 0) return null;
    const map = store.map;
    if (!(map instanceof Map)) return null;
    return map.get(previewKey) || null;
  }

  function previewKey(label, facet) {
    const trimmedLabel = typeof label === "string" ? label.trim() : "";
    if (!trimmedLabel) return "";
    const trimmedFacet = typeof facet === "string" && facet.trim() ? facet.trim() : "statement";
    return trimmedLabel + "--" + trimmedFacet;
  }

  function statementPreviewKey(label) {
    return previewKey(label, "statement");
  }

  // Preview resolution joins semantic manifest entries with opaque fragments.

  async function loadBlueprintStoreEntry(store, previewKey) {
    const exact = readBlueprintStoreEntry(store, previewKey);
    if (exact) return exact;
    const entryMap = await loadBlueprintStore(store);
    if (!(entryMap instanceof Map)) return null;
    if (typeof previewKey === "string" && previewKey.length > 0 && entryMap.has(previewKey)) {
      return entryMap.get(previewKey) || null;
    }
    return null;
  }

  async function loadBlueprintManifestEntry(previewKey) {
    return loadBlueprintStoreEntry(blueprintManifestStore, previewKey);
  }

  async function loadBlueprintHtmlCacheEntry(previewKey) {
    return loadBlueprintStoreEntry(blueprintHtmlCacheStore, previewKey);
  }

  async function resolveBlueprintPreview(previewKey) {
    const key = typeof previewKey === "string" ? previewKey.trim() : "";
    if (!key) {
      return {
        ok: false,
        key: "",
        reason: "missing-key",
        manifestEntry: null,
        htmlCacheEntry: null,
        html: "",
        diagnosticHtml: missingPreviewKeyDiagnosticHtml()
      };
    }
    const results = await Promise.all([
      loadBlueprintManifestEntry(key),
      loadBlueprintHtmlCacheEntry(key)
    ]);
    const manifestEntry = results[0] || null;
    const htmlCacheEntry = results[1] || null;
    const html = readHtml(htmlCacheEntry);
    if (!manifestEntry) {
      return {
        ok: false,
        key: key,
        reason: "manifest-entry-missing",
        manifestEntry: null,
        htmlCacheEntry: htmlCacheEntry,
        html: "",
        diagnosticHtml: blueprintManifestDiagnosticHtml(key)
      };
    }
    if (!html) {
      return {
        ok: false,
        key: key,
        reason: "html-cache-entry-missing",
        manifestEntry: manifestEntry,
        htmlCacheEntry: htmlCacheEntry,
        html: "",
        diagnosticHtml: blueprintHtmlCacheDiagnosticHtml(key)
      };
    }
    return {
      ok: true,
      key: key,
      reason: "",
      manifestEntry: manifestEntry,
      htmlCacheEntry: htmlCacheEntry,
      html: html,
      diagnosticHtml: ""
    };
  }

  // Rendered-fragment insertion and hydration.

  function hydrateRenderedPreview(root, options) {
    const opts = options && typeof options === "object" ? options : {};
    if (!(root instanceof Element || root instanceof Document)) return false;
    if (opts.hydrate !== false) {
      runPreviewHydrators(root);
    }
    if (opts.renderMath !== false) {
      renderBlueprintMath(root);
    }
    return true;
  }

  function renderHtmlInto(target, html, options) {
    if (!(target instanceof Element)) return false;
    const safeHtml = typeof html === "string" ? html : "";
    target.innerHTML = safeHtml;
    if (safeHtml) {
      hydrateRenderedPreview(target, options);
    }
    return true;
  }

  async function renderBlueprintPreviewInto(target, previewKey, options) {
    if (!(target instanceof Element)) {
      throw new Error("renderBlueprintPreviewInto target must be a DOM Element");
    }
    const opts = options && typeof options === "object" ? options : {};
    const result = await resolveBlueprintPreview(previewKey);
    const html = result.ok ? result.html : (opts.diagnostics === false ? "" : result.diagnosticHtml);
    renderHtmlInto(target, html, opts);
    return result;
  }

  function renderBlueprintMath(root) {
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

  // Panel behavior helpers shared by bundled Blueprint features.

  function bindCloseOnce(button, onClose) {
    if (!(button instanceof Element)) return;
    if (button.getAttribute("data-bp-bound") === "1") return;
    if (typeof onClose !== "function") return;
    button.setAttribute("data-bp-bound", "1");
    button.addEventListener("click", function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      onClose(ev);
    });
  }

  function readAnchorRect(anchor) {
    if (anchor instanceof Element) {
      return anchor.getBoundingClientRect();
    }
    if (
      anchor &&
      typeof anchor === "object" &&
      Number.isFinite(anchor.left) &&
      Number.isFinite(anchor.right) &&
      Number.isFinite(anchor.top) &&
      Number.isFinite(anchor.bottom)
    ) {
      return anchor;
    }
    return null;
  }

  function positionAnchoredPanel(panel, anchor, margin, offset) {
    if (!(panel instanceof Element)) return;
    const rect = readAnchorRect(anchor);
    if (!rect) return;
    const safeMargin = Number.isFinite(margin) ? margin : 12;
    const safeOffset = Number.isFinite(offset) ? offset : 10;
    const panelRect = panel.getBoundingClientRect();
    const panelWidth = panelRect.width || Math.min(520, window.innerWidth - safeMargin * 2);
    const panelHeight = panelRect.height || Math.min(420, window.innerHeight - safeMargin * 2);
    let left = rect.left;
    if (left + panelWidth > window.innerWidth - safeMargin) {
      left = window.innerWidth - panelWidth - safeMargin;
    }
    left = Math.max(safeMargin, left);
    let top = rect.bottom + safeOffset;
    if (top + panelHeight > window.innerHeight - safeMargin) {
      top = rect.top - panelHeight - safeOffset;
    }
    top = Math.max(safeMargin, top);
    panel.style.left = left + "px";
    panel.style.top = top + "px";
  }

  function shouldKeepOpen(nextTarget, trigger, panel) {
    if (!(nextTarget instanceof Element)) return false;
    if (trigger instanceof Element && trigger.contains(nextTarget)) return true;
    if (panel instanceof Element && panel.contains(nextTarget)) return true;
    const inlinePanel = document.getElementById("bp-inline-preview-panel");
    if (inlinePanel instanceof Element && inlinePanel.contains(nextTarget)) return true;
    return false;
  }

  function normalizePreviewMode(rawMode, fallback) {
    const defaultMode = fallback === "hover" || fallback === "pinned" ? fallback : "hover";
    const mode = String(rawMode || "").trim().toLowerCase();
    if (mode === "hover") return "hover";
    if (mode === "pinned") return "pinned";
    return defaultMode;
  }

  function normalizePreviewPlacement(rawPlacement, fallback) {
    const defaultPlacement =
      fallback === "anchored" || fallback === "docked" ? fallback : "anchored";
    const placement = String(rawPlacement || "").trim().toLowerCase();
    if (placement === "anchored") return "anchored";
    if (placement === "docked") return "docked";
    return defaultPlacement;
  }

  function readPanelBehavior(panel, defaults) {
    const defaultMode = normalizePreviewMode(defaults && defaults.mode, "hover");
    const defaultPlacement = normalizePreviewPlacement(defaults && defaults.placement, "anchored");
    if (!(panel instanceof Element)) {
      return {
        mode: defaultMode,
        placement: defaultPlacement,
        isPinned: defaultMode === "pinned",
        isHover: defaultMode === "hover",
        isAnchored: defaultPlacement === "anchored",
        isDocked: defaultPlacement === "docked"
      };
    }
    const rawMode = (panel.getAttribute("data-bp-preview-mode") || "").trim();
    const rawPlacement = (panel.getAttribute("data-bp-preview-placement") || "").trim();
    const mode = normalizePreviewMode(rawMode, defaultMode);
    const placement = normalizePreviewPlacement(rawPlacement, defaultPlacement);
    return {
      mode: mode,
      placement: placement,
      isPinned: mode === "pinned",
      isHover: mode === "hover",
      isAnchored: placement === "anchored",
      isDocked: placement === "docked"
    };
  }

  function resetPanelPosition(panel) {
    if (!(panel instanceof Element)) return;
    panel.style.left = "";
    panel.style.top = "";
  }

  function configureCloseButton(closeButton, onClose, behavior) {
    if (!(closeButton instanceof Element)) return;
    const pinned = !!(behavior && behavior.isPinned);
    closeButton.hidden = !pinned;
    closeButton.style.display = pinned ? "" : "none";
    closeButton.setAttribute("aria-hidden", pinned ? "false" : "true");
    closeButton.tabIndex = pinned ? 0 : -1;
    if (!pinned) return;
    bindCloseOnce(closeButton, onClose);
  }

  function pointerWithinPanel(panel, ev) {
    if (!(panel instanceof Element)) return false;
    if (!ev || !Number.isFinite(ev.clientX) || !Number.isFinite(ev.clientY)) return false;
    const rect = panel.getBoundingClientRect();
    return (
      ev.clientX >= rect.left &&
      ev.clientX <= rect.right &&
      ev.clientY >= rect.top &&
      ev.clientY <= rect.bottom
    );
  }

  function readPanelNodes(panel, titleSelector, bodySelector) {
    if (!(panel instanceof Element)) {
      return { title: null, body: null };
    }
    const title = panel.querySelector(titleSelector);
    const body = panel.querySelector(bodySelector);
    return {
      title: title instanceof Element ? title : null,
      body: body instanceof Element ? body : null
    };
  }

  function createPanelController(panel, behavior, titleSelector, bodySelector, options) {
    if (!(panel instanceof Element)) return null;
    const nodes = readPanelNodes(panel, titleSelector, bodySelector);
    const opts = options && typeof options === "object" ? options : {};
    const clearBody =
      typeof opts.clearBody === "function"
        ? opts.clearBody
        : function (body) { body.innerHTML = ""; };
    const renderBody =
      typeof opts.renderBody === "function" ? opts.renderBody : function () {};
    const positionPanel =
      typeof opts.positionPanel === "function" ? opts.positionPanel : function () {};
    const onHide =
      typeof opts.onHide === "function" ? opts.onHide : function () {};
    const controller = {
      panel: panel,
      title: nodes.title,
      body: nodes.body,
      behavior: behavior || {
        isPinned: true,
        isHover: false,
        isAnchored: false,
        isDocked: true
      },
      hide: function () {
        panel.hidden = true;
        if (controller.title) controller.title.textContent = "";
        if (controller.body) clearBody(controller.body);
        onHide();
      },
      position: function (anchorNode) {
        positionPanel(panel, anchorNode);
      },
      show: function (titleText, payload, anchorNode) {
        if (!controller.title || !controller.body) return false;
        controller.title.textContent = titleText || "";
        renderBody(controller.body, payload);
        panel.hidden = false;
        controller.position(anchorNode);
        return true;
      }
    };
    return controller;
  }

  function bindHoverablePanelLifetime(controller, getActiveAnchor, boundAttr) {
    const noop = {
      cancelHide: function () {},
      scheduleHide: function () {
        if (controller) controller.hide();
      }
    };
    if (!controller || !(controller.panel instanceof Element)) return noop;
    const panel = controller.panel;
    const attr =
      typeof boundAttr === "string" && boundAttr.length > 0
        ? boundAttr
        : "data-bp-preview-hover-bound";
    let hideTimer = null;

    function cancelHide() {
      if (hideTimer !== null) {
        clearTimeout(hideTimer);
        hideTimer = null;
      }
    }

    function scheduleHide() {
      if (!controller.behavior || !controller.behavior.isHover) return;
      cancelHide();
      hideTimer = window.setTimeout(function () {
        hideTimer = null;
        controller.hide();
      }, 180);
    }

    function maybeScheduleHide(ev) {
      if (
        shouldKeepOpen(
          ev && ev.relatedTarget,
          typeof getActiveAnchor === "function" ? getActiveAnchor() : null,
          panel
        )
      ) {
        return;
      }
      scheduleHide();
    }

    if (panel.getAttribute(attr) !== "1") {
      panel.setAttribute(attr, "1");
      panel.addEventListener("mouseenter", cancelHide);
      panel.addEventListener("focusin", cancelHide);
      panel.addEventListener("mouseleave", maybeScheduleHide);
      panel.addEventListener("focusout", maybeScheduleHide);
    }

    return {
      cancelHide: cancelHide,
      scheduleHide: scheduleHide
    };
  }

  function registerPreviewHydrator(name, fn) {
    if (typeof name !== "string" || name.length === 0) return;
    if (typeof fn !== "function") return;
    previewHydrators.set(name, fn);
  }

  function runPreviewHydrators(root) {
    if (!(root instanceof Element || root instanceof Document)) return;
    previewHydrators.forEach(function (fn) {
      if (typeof fn !== "function") return;
      try {
        fn(root);
      } catch (_err) {}
    });
  }

  function hidePanelContent(panel, titleNode, bodyNode) {
    if (!(panel instanceof Element)) return;
    panel.hidden = true;
    if (titleNode instanceof Element) titleNode.textContent = "";
    if (bodyNode instanceof Element) bodyNode.innerHTML = "";
  }

  function setPreviewHeaderLink(labelNode, sourceNode) {
    if (!(labelNode instanceof Element)) return;
    const label =
      sourceNode instanceof Element
        ? (sourceNode.getAttribute("data-bp-preview-header-label") || "").trim()
        : "";
    const href =
      sourceNode instanceof Element
        ? (sourceNode.getAttribute("data-bp-preview-header-href") || "").trim()
        : "";
    if (label.length > 0) {
      labelNode.textContent = label;
      if (href.length > 0) {
        labelNode.setAttribute("href", href);
      } else {
        labelNode.removeAttribute("href");
      }
      labelNode.hidden = false;
    } else {
      labelNode.textContent = "";
      labelNode.removeAttribute("href");
      labelNode.hidden = true;
    }
  }

  function showPanelContent(panel, titleNode, bodyNode, heading, html, behavior, anchor, margin, offset) {
    if (!(panel instanceof Element) || !(titleNode instanceof Element) || !(bodyNode instanceof Element)) {
      return false;
    }
    if (typeof html !== "string" || html.length === 0) {
      hidePanelContent(panel, titleNode, bodyNode);
      return false;
    }
    const safeMargin = Number.isFinite(margin) ? margin : 12;
    const safeOffset = Number.isFinite(offset) ? offset : 10;
    titleNode.textContent = typeof heading === "string" ? heading : "";
    renderHtmlInto(bodyNode, html);
    panel.hidden = false;
    if (behavior && behavior.isAnchored && readAnchorRect(anchor)) {
      positionAnchoredPanel(panel, anchor, safeMargin, safeOffset);
    } else {
      resetPanelPosition(panel);
    }
    return true;
  }

  // Template preview binding adapts the shared helpers to concrete surfaces.

  function bindTemplatePreview(options) {
    const root =
      options && (options.root instanceof Element || options.root instanceof Document)
        ? options.root
        : document;
    const previewRoot =
      options && (options.previewRoot instanceof Element || options.previewRoot instanceof Document)
        ? options.previewRoot
        : root;
    const triggerRoot =
      options && (options.triggerRoot instanceof Element || options.triggerRoot instanceof Document)
        ? options.triggerRoot
        : root;
    const panel = options && options.panel instanceof Element ? options.panel : null;
    const templateSelector =
      options && typeof options.templateSelector === "string" ? options.templateSelector : "";
    const triggerSelector =
      options && typeof options.triggerSelector === "string" ? options.triggerSelector : "";
    const keyAttr =
      options && typeof options.keyAttr === "string" && options.keyAttr.length > 0
        ? options.keyAttr
        : "data-bp-preview-label";
    const titleAttr =
      options && typeof options.titleAttr === "string" && options.titleAttr.length > 0
        ? options.titleAttr
        : keyAttr;
    const titleSelector =
      options && typeof options.titleSelector === "string" ? options.titleSelector : "";
    const bodySelector =
      options && typeof options.bodySelector === "string" ? options.bodySelector : "";
    const closeSelector =
      options && typeof options.closeSelector === "string" ? options.closeSelector : "";
    const triggerBoundAttr =
      options && typeof options.triggerBoundAttr === "string" && options.triggerBoundAttr.length > 0
        ? options.triggerBoundAttr
        : "data-bp-bound";
    const defaults = options && typeof options.defaults === "object" ? options.defaults : {};
    const margin =
      options && Number.isFinite(options.margin) ? options.margin : 12;
    const offset =
      options && Number.isFinite(options.offset) ? options.offset : 10;
    const readKey =
      options && typeof options.readKey === "function"
        ? options.readKey
        : function (trigger) {
            if (!(trigger instanceof Element)) return "";
            return (trigger.getAttribute(keyAttr) || "").trim();
          };
    const readTitle =
      options && typeof options.readTitle === "function"
        ? options.readTitle
        : function (trigger, key) {
            if (!(trigger instanceof Element)) return key;
            const heading = (trigger.getAttribute(titleAttr) || "").trim();
            return heading || key;
          };
    const readLookupKey =
      options && typeof options.readLookupKey === "function"
        ? options.readLookupKey
        : function (trigger) {
            if (!(trigger instanceof Element)) return "";
            return (trigger.getAttribute("data-bp-preview-key") || "").trim();
          };
    const allowHtmlCache = !!(options && options.allowHtmlCache);

    const previewMap = collectPreviewTemplates(previewRoot, templateSelector, keyAttr);
    const triggers = triggerRoot.querySelectorAll(triggerSelector);
    if (panel && panel.ownerDocument && panel.ownerDocument.body && panel.parentElement !== panel.ownerDocument.body) {
      panel.ownerDocument.body.appendChild(panel);
    }
    const title = panel ? panel.querySelector(titleSelector) : null;
    const body = panel ? panel.querySelector(bodySelector) : null;
    const close = panel ? panel.querySelector(closeSelector) : null;
    if (!panel || !(title instanceof Element) || !(body instanceof Element) || (!allowHtmlCache && previewMap.size === 0)) {
      if (panel) hidePanelContent(panel, title, body);
      return null;
    }
    if (triggers.length === 0) {
      hidePanelContent(panel, title, body);
      return null;
    }
    const behavior = readPanelBehavior(panel, defaults);
    let activeTrigger = null;
    let hideTimer = null;
    let showRequestToken = 0;

    function cancelHide() {
      if (hideTimer !== null) {
        clearTimeout(hideTimer);
        hideTimer = null;
      }
    }

    function hidePanel() {
      cancelHide();
      showRequestToken += 1;
      hidePanelContent(panel, title, body);
      activeTrigger = null;
    }

    function scheduleHide() {
      cancelHide();
      if (!behavior.isHover) {
        hidePanel();
        return;
      }
      hideTimer = window.setTimeout(function () {
        hideTimer = null;
        hidePanel();
      }, 180);
    }

    function positionPanel(anchor) {
      if (!behavior.isAnchored) {
        resetPanelPosition(panel);
        return;
      }
      if (!(anchor instanceof Element)) return;
      positionAnchoredPanel(panel, anchor, margin, offset);
    }

    async function resolveTriggerHtml(trigger, key) {
      const localEntry = previewMap.get(key);
      const localHtml = readHtml(localEntry);
      if (localHtml) return localHtml;
      if (!allowHtmlCache) return "";
      const lookupKey = readLookupKey(trigger, key, localEntry);
      const result = await resolveBlueprintPreview(lookupKey);
      if (result && result.ok) return result.html;
      const diagnosticHtml =
        result && typeof result.diagnosticHtml === "string" ? result.diagnosticHtml : "";
      return diagnosticHtml || blueprintHtmlCacheDiagnosticHtml(lookupKey || key);
    }

    async function showFromTrigger(trigger) {
      if (!(trigger instanceof Element)) return;
      const key = readKey(trigger);
      const requestToken = ++showRequestToken;
      const html = await resolveTriggerHtml(trigger, key);
      if (requestToken !== showRequestToken) return;
      if (!key || !html) {
        hidePanel();
        return;
      }
      activeTrigger = trigger;
      const heading = readTitle(trigger, key);
      showPanelContent(panel, title, body, heading, html, behavior, trigger, margin, offset);
    }

    configureCloseButton(close, hidePanel, behavior);

    triggers.forEach(function (trigger) {
      if (!(trigger instanceof Element)) return;
      if (trigger.getAttribute(triggerBoundAttr) === "1") return;
      trigger.setAttribute(triggerBoundAttr, "1");
      trigger.addEventListener("mouseenter", function () {
        cancelHide();
        showFromTrigger(trigger);
      });
      trigger.addEventListener("focusin", function () {
        cancelHide();
        showFromTrigger(trigger);
      });
      trigger.addEventListener("mouseleave", function (ev) {
        if (!behavior.isHover) return;
        if (shouldKeepOpen(ev.relatedTarget, trigger, panel)) return;
        scheduleHide();
      });
      trigger.addEventListener("focusout", function (ev) {
        if (!behavior.isHover) return;
        if (shouldKeepOpen(ev.relatedTarget, trigger, panel)) return;
        scheduleHide();
      });
    });

    panel.addEventListener("mouseenter", function () {
      cancelHide();
    });
    panel.addEventListener("focusin", function () {
      cancelHide();
    });
    panel.addEventListener("mouseleave", function (ev) {
      if (!behavior.isHover) return;
      if (shouldKeepOpen(ev.relatedTarget, activeTrigger, panel)) return;
      scheduleHide();
    });
    panel.addEventListener("focusout", function (ev) {
      if (!behavior.isHover) return;
      if (shouldKeepOpen(ev.relatedTarget, activeTrigger, panel)) return;
      scheduleHide();
    });

    document.addEventListener("keydown", function (ev) {
      if (ev.key === "Escape") {
        hidePanel();
      }
    });
    window.addEventListener("resize", function () {
      if (behavior.isAnchored && activeTrigger && !panel.hidden) positionPanel(activeTrigger);
    });
    window.addEventListener(
      "scroll",
      function () {
        if (behavior.isAnchored && activeTrigger && !panel.hidden) positionPanel(activeTrigger);
      },
      true
    );

    return {
      previewMap: previewMap,
      behavior: behavior,
      hidePanel: hidePanel,
      showFromTrigger: showFromTrigger
    };
  }

  function bindTemplatePreviewRoots(options) {
    const opts = options && typeof options === "object" ? options : {};
    const rootSelector = typeof opts.rootSelector === "string" ? opts.rootSelector : "";
    const panelSelector = typeof opts.panelSelector === "string" ? opts.panelSelector : "";
    const rootBoundAttr =
      typeof opts.rootBoundAttr === "string" && opts.rootBoundAttr.length > 0
        ? opts.rootBoundAttr
        : "data-bp-template-preview-root-bound";

    function copyStringOption(target, name) {
      if (typeof opts[name] === "string") {
        target[name] = opts[name];
      }
    }

    function bindRoot(root) {
      if (!(root instanceof Element)) return null;
      if (root.getAttribute(rootBoundAttr) === "1") return null;
      root.setAttribute(rootBoundAttr, "1");
      const panel = panelSelector ? root.querySelector(panelSelector) : null;
      if (!(panel instanceof Element)) return null;

      const bindOptions = {
        root: root,
        previewRoot: root,
        triggerRoot: root,
        panel: panel
      };
      [
        "templateSelector",
        "triggerSelector",
        "keyAttr",
        "titleAttr",
        "titleSelector",
        "bodySelector",
        "closeSelector",
        "triggerBoundAttr"
      ].forEach(function (name) {
        copyStringOption(bindOptions, name);
      });
      if (opts.allowHtmlCache === true) bindOptions.allowHtmlCache = true;
      if (opts.defaults && typeof opts.defaults === "object") bindOptions.defaults = opts.defaults;
      if (Number.isFinite(opts.margin)) bindOptions.margin = opts.margin;
      if (Number.isFinite(opts.offset)) bindOptions.offset = opts.offset;
      if (typeof opts.readKey === "function") bindOptions.readKey = opts.readKey;
      if (typeof opts.readTitle === "function") bindOptions.readTitle = opts.readTitle;
      if (typeof opts.readLookupKey === "function") bindOptions.readLookupKey = opts.readLookupKey;
      return bindTemplatePreview(bindOptions);
    }

    function refresh(root) {
      const scope = root instanceof Element || root instanceof Document ? root : document;
      const controllers = [];
      if (!rootSelector) return controllers;
      if (scope instanceof Element && scope.matches(rootSelector)) {
        const controller = bindRoot(scope);
        if (controller) controllers.push(controller);
      }
      scope.querySelectorAll(rootSelector).forEach(function (rootNode) {
        const controller = bindRoot(rootNode);
        if (controller) controllers.push(controller);
      });
      return controllers;
    }

    if (opts.autoStart !== false) {
      const start = function () { refresh(document); };
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", start, { once: opts.once === true });
      } else {
        start();
      }
    }

    return {
      bindRoot: bindRoot,
      refresh: refresh
    };
  }

  // API assembly and readiness synchronization.

  const stableCustomClientApi = {
    dataUrl: blueprintDataUrl,
    manifestUrl: blueprintManifestUrl,
    htmlCacheUrl: blueprintHtmlCacheUrl,
    loadManifest: loadBlueprintManifest,
    readManifestStatus: readBlueprintManifestStatus,
    loadManifestEntry: loadBlueprintManifestEntry,
    loadHtmlCache: loadBlueprintHtmlCache,
    readHtmlCacheStatus: readBlueprintHtmlCacheStatus,
    loadHtmlCacheEntry: loadBlueprintHtmlCacheEntry,
    previewKey: previewKey,
    statementPreviewKey: statementPreviewKey,
    resolvePreview: resolveBlueprintPreview,
    renderPreviewInto: renderBlueprintPreviewInto,
    hydrate: hydrateRenderedPreview
  };

  const bundledFeatureRenderHelpers = {
    collectPreviewTemplates: collectPreviewTemplates,
    escapeHtml: escapeHtml,
    renderHtmlInto: renderHtmlInto,
    positionAnchoredPanel: positionAnchoredPanel,
    shouldKeepOpen: shouldKeepOpen,
    readPanelBehavior: readPanelBehavior,
    resetPanelPosition: resetPanelPosition,
    configureCloseButton: configureCloseButton,
    pointerWithinPanel: pointerWithinPanel,
    createPanelController: createPanelController,
    bindHoverablePanelLifetime: bindHoverablePanelLifetime,
    registerPreviewHydrator: registerPreviewHydrator,
    previewDebug: previewDebug,
    previewDebugLabel: previewDebugLabel,
    hidePanelContent: hidePanelContent,
    setPreviewHeaderLink: setPreviewHeaderLink,
    showPanelContent: showPanelContent,
    bindTemplatePreviewRoots: bindTemplatePreviewRoots
  };

  const renderApi = Object.assign(
    {},
    stableCustomClientApi,
    bundledFeatureRenderHelpers
  );

  function reportRenderReadyError(err) {
    window.setTimeout(function () {
      throw err;
    }, 0);
  }

  function onRenderReady(fn) {
    if (typeof fn !== "function") return;
    fn(renderApi);
  }

  const namespace =
    window.VersoBlueprint && typeof window.VersoBlueprint === "object"
      ? window.VersoBlueprint
      : {};
  const queuedRenderReadyCallbacks = Array.isArray(namespace.renderReadyCallbacks)
    ? namespace.renderReadyCallbacks.slice()
    : [];
  namespace.render = renderApi;
  namespace.onRenderReady = onRenderReady;
  namespace.renderReadyCallbacks = [];
  window.VersoBlueprint = namespace;
  queuedRenderReadyCallbacks.forEach(function (fn) {
    try {
      onRenderReady(fn);
    } catch (err) {
      reportRenderReadyError(err);
    }
  });
})();
