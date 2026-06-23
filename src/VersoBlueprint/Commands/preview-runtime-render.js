  // Preview resolution joins semantic manifest entries with opaque body fragments.
  //
  // The HTML cache is presentation data. Runtime code may insert and hydrate
  // its fragments, but semantic facts must come from the manifest entry. If a
  // future client needs another fact, add it to the manifest instead of parsing
  // cached HTML.

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

  // Rendered-fragment insertion.

  function renderHtmlInto(target, html, options) {
    if (!(target instanceof Element)) return false;
    const safeHtml = typeof html === "string" ? html : "";
    if (safeHtml.length === 0) {
      target.replaceChildren();
      return true;
    }
    target.innerHTML = safeHtml;
    hydrateRenderedPreview(target, options);
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
  const canonicalPreviewDocuments = new Map();
  const canonicalPreviewHtmlByKey = new Map();

  // Canonical generated-node rendering.
  //
  // The HTML cache intentionally carries reusable body fragments, not full
  // Blueprint node wrappers. To render the exact Lean-generated shell without
  // duplicating wrapper semantics in JavaScript or emitting a second wrapper
  // cache, follow the manifest href, clone the canonical node, and rebase its
  // links for insertion into the current page.

  function urlWithoutHash(url) {
    const clone = new URL(url.href);
    clone.hash = "";
    return clone.href;
  }

  function currentDocumentUrlWithoutHash() {
    return urlWithoutHash(new URL(window.location.href));
  }

  function canonicalPreviewUrl(entry) {
    if (!entry || typeof entry !== "object" || typeof entry.href !== "string") return null;
    const href = entry.href.trim();
    if (!href) return null;
    try {
      return new URL(href, document.baseURI || window.location.href);
    } catch (_err) {
      return null;
    }
  }

  function canonicalPreviewId(url, result) {
    if (url && typeof url.hash === "string" && url.hash.length > 1) {
      const raw = url.hash.slice(1);
      try {
        return decodeURIComponent(raw);
      } catch (_err) {
        return raw;
      }
    }
    if (result && typeof result.key === "string" && result.key) {
      return "--informal-preview-" + result.key;
    }
    return "";
  }

  function canonicalPreviewDiagnosticHtml(title, detail, previewKey) {
    const keyHtml = previewKey ? "<p>Requested preview: <code>" + escapeHtml(previewKey) + "</code></p>" : "";
    return (
      "<div class=\"bp_html_cache_preview_notice\">" +
      "<p><strong>" + escapeHtml(title) + "</strong></p>" +
      "<p>" + escapeHtml(detail) + "</p>" +
      keyHtml +
      "</div>"
    );
  }

  function canonicalPreviewResult(result, fields) {
    return Object.assign(
      {},
      result || {},
      {
        canonicalHtml: "",
        canonicalSourceHref: ""
      },
      fields || {}
    );
  }

  async function loadCanonicalPreviewDocument(url) {
    const pageUrl = urlWithoutHash(url);
    if (pageUrl === currentDocumentUrlWithoutHash()) {
      return document;
    }
    const existing = canonicalPreviewDocuments.get(pageUrl);
    if (existing) return existing;
    const promise = fetch(pageUrl)
      .then(function (resp) {
        if (!resp.ok) {
          throw new Error("HTTP " + resp.status + " while loading " + pageUrl);
        }
        return resp.text();
      })
      .then(function (html) {
        return new DOMParser().parseFromString(html, "text/html");
      });
    canonicalPreviewDocuments.set(pageUrl, promise);
    return promise;
  }

  function rebaseUrlAttribute(node, attrName, baseUrl) {
    const value = node.getAttribute(attrName);
    if (typeof value !== "string" || !value.trim()) return;
    const trimmed = value.trim();
    const lower = trimmed.toLowerCase();
    if (
      lower.startsWith("javascript:") ||
      lower.startsWith("mailto:") ||
      lower.startsWith("tel:") ||
      lower.startsWith("data:")
    ) return;
    try {
      node.setAttribute(attrName, new URL(trimmed, baseUrl).href);
    } catch (_err) {}
  }

  function forEachMatchingElement(root, selector, callback) {
    if (!(root instanceof Element)) return;
    if (root.matches(selector)) callback(root);
    root.querySelectorAll(selector).forEach(function (node) {
      callback(node);
    });
  }

  function canonicalPreviewDocumentBaseUrl(doc, sourceUrl) {
    const pageUrl = urlWithoutHash(sourceUrl);
    const base = doc instanceof Document ? doc.querySelector("base[href]") : null;
    const href = base instanceof Element ? (base.getAttribute("href") || "").trim() : "";
    if (href.length > 0) {
      try {
        return new URL(href, pageUrl).href;
      } catch (_err) {}
    }
    return pageUrl;
  }

  function rebaseCanonicalPreviewLinks(root, baseUrl) {
    forEachMatchingElement(root, "[href]", function (node) {
      rebaseUrlAttribute(node, "href", baseUrl);
    });
    forEachMatchingElement(root, "[src]", function (node) {
      rebaseUrlAttribute(node, "src", baseUrl);
    });
    forEachMatchingElement(root, "[data-bp-preview-header-href]", function (node) {
      rebaseUrlAttribute(node, "data-bp-preview-header-href", baseUrl);
    });
  }

  async function resolveCanonicalBlueprintPreview(previewKey) {
    const result = await resolveBlueprintPreview(previewKey);
    if (!result.ok) {
      return canonicalPreviewResult(result);
    }
    const cached = canonicalPreviewHtmlByKey.get(result.key);
    if (cached) {
      return canonicalPreviewResult(result, {
        canonicalHtml: cached.html,
        canonicalSourceHref: cached.href
      });
    }
    const url = canonicalPreviewUrl(result.manifestEntry);
    if (!url) {
      return canonicalPreviewResult(result, {
        ok: false,
        reason: "canonical-href-missing",
        diagnosticHtml: canonicalPreviewDiagnosticHtml(
          "Canonical preview link missing.",
          "The manifest entry did not include a generated-page link for this preview.",
          result.key
        )
      });
    }

    try {
      const doc = await loadCanonicalPreviewDocument(url);
      const id = canonicalPreviewId(url, result);
      const node = id ? doc.getElementById(id) : null;
      if (!(node instanceof Element)) {
        return canonicalPreviewResult(result, {
          ok: false,
          reason: "canonical-preview-node-missing",
          canonicalSourceHref: url.href,
          diagnosticHtml: canonicalPreviewDiagnosticHtml(
            "Canonical preview node missing.",
            "The generated page loaded, but the linked Blueprint node was not present.",
            result.key
          )
        });
      }
      const clone = node.cloneNode(true);
      rebaseCanonicalPreviewLinks(clone, canonicalPreviewDocumentBaseUrl(doc, url));
      const canonical = {
        html: clone.outerHTML,
        href: url.href
      };
      canonicalPreviewHtmlByKey.set(result.key, canonical);
      return canonicalPreviewResult(result, {
        canonicalHtml: canonical.html,
        canonicalSourceHref: canonical.href
      });
    } catch (err) {
      const message = err && err.message ? err.message : String(err);
      return canonicalPreviewResult(result, {
        ok: false,
        reason: "canonical-preview-load-failed",
        canonicalSourceHref: url.href,
        diagnosticHtml: canonicalPreviewDiagnosticHtml(
          "Canonical preview page unavailable.",
          message,
          result.key
        )
      });
    }
  }

  async function renderCanonicalBlueprintPreviewInto(target, previewKey, options) {
    if (!(target instanceof Element)) {
      throw new Error("renderCanonicalBlueprintPreviewInto target must be a DOM Element");
    }
    const opts = options && typeof options === "object" ? options : {};
    const result = await resolveCanonicalBlueprintPreview(previewKey);
    const html = result.ok
      ? result.canonicalHtml
      : (opts.diagnostics === false ? "" : result.diagnosticHtml);
    renderHtmlInto(target, html, opts);
    return result;
  }
