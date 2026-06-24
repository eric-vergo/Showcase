  // API assembly and readiness synchronization.

  const previewDataApi = {
    dataUrl: blueprintDataUrl,
    manifestUrl: blueprintManifestUrl,
    htmlCacheUrl: blueprintHtmlCacheUrl,
    loadManifest: loadBlueprintManifest,
    readManifestStatus: readBlueprintManifestStatus,
    loadManifestEntry: loadBlueprintManifestEntry,
    loadHtmlCache: loadBlueprintHtmlCache,
    readHtmlCacheStatus: readBlueprintHtmlCacheStatus,
    loadHtmlCacheEntry: loadBlueprintHtmlCacheEntry,
    getGraphData: collectGraphData,
    getGraphVariants: collectGraphVariants,
    graphsFromManifest: graphDataFromManifest,
    loadManifestGraphs: loadManifestGraphs,
    loadGraphs: loadBlueprintGraphs,
    graphApiModuleUrl: graphApiModuleUrl,
    previewApiModuleUrl: previewApiModuleUrl,
    previewKey: previewKey,
    statementPreviewKey: statementPreviewKey,
    resolvePreview: resolveBlueprintPreview,
    resolveCanonicalPreview: resolveCanonicalBlueprintPreview
  };

  const previewRenderApi = {
    renderPreviewInto: renderBlueprintPreviewInto,
    renderCanonicalPreviewInto: renderCanonicalBlueprintPreviewInto,
    hydrate: hydrateRenderedPreview
  };

  const previewTemplateHelpers = {
    collectPreviewTemplates: collectPreviewTemplates
  };

  const previewContentHelpers = {
    escapeHtml: escapeHtml,
    previewMessageHtml: previewMessageHtml,
    createPreviewPanel: createPreviewPanel,
    createPreviewSurface: createPreviewSurface,
    renderPreviewIntoSurface: renderPreviewIntoSurface,
    resolvePreviewHtml: resolvePreviewHtml
  };

  const previewLifecycleHelpers = {
    bindAnchoredPopover: bindAnchoredPopover,
    hidePreviewSurfaces: hidePreviewSurfaces,
  };

  const previewHydrationHelpers = {
    registerPreviewHydrator: registerPreviewHydrator,
    previewDebug: previewDebug,
    previewDebugLabel: previewDebugLabel
  };

  const stableCustomClientApi = {
    dataUrl: previewDataApi.dataUrl,
    manifestUrl: previewDataApi.manifestUrl,
    htmlCacheUrl: previewDataApi.htmlCacheUrl,
    loadManifest: previewDataApi.loadManifest,
    readManifestStatus: previewDataApi.readManifestStatus,
    loadManifestEntry: previewDataApi.loadManifestEntry,
    loadHtmlCache: previewDataApi.loadHtmlCache,
    readHtmlCacheStatus: previewDataApi.readHtmlCacheStatus,
    loadHtmlCacheEntry: previewDataApi.loadHtmlCacheEntry,
    getGraphData: previewDataApi.getGraphData,
    getGraphVariants: previewDataApi.getGraphVariants,
    graphsFromManifest: previewDataApi.graphsFromManifest,
    loadManifestGraphs: previewDataApi.loadManifestGraphs,
    loadGraphs: previewDataApi.loadGraphs,
    graphApiModuleUrl: previewDataApi.graphApiModuleUrl,
    previewApiModuleUrl: previewDataApi.previewApiModuleUrl,
    previewKey: previewDataApi.previewKey,
    statementPreviewKey: previewDataApi.statementPreviewKey,
    resolvePreview: previewDataApi.resolvePreview,
    renderPreviewInto: previewRenderApi.renderPreviewInto,
    resolveCanonicalPreview: previewDataApi.resolveCanonicalPreview,
    renderCanonicalPreviewInto: previewRenderApi.renderCanonicalPreviewInto,
    hydrate: previewRenderApi.hydrate
  };

  const bundledFeatureRenderHelpers = {
    collectPreviewTemplates: previewTemplateHelpers.collectPreviewTemplates,
    escapeHtml: previewContentHelpers.escapeHtml,
    createPreviewSurface: previewContentHelpers.createPreviewSurface,
    registerPreviewHydrator: previewHydrationHelpers.registerPreviewHydrator,
    previewDebug: previewHydrationHelpers.previewDebug,
    previewDebugLabel: previewHydrationHelpers.previewDebugLabel,
    previewMessageHtml: previewContentHelpers.previewMessageHtml,
    createPreviewPanel: previewContentHelpers.createPreviewPanel,
    renderPreviewIntoSurface: previewContentHelpers.renderPreviewIntoSurface,
    resolvePreviewHtml: previewContentHelpers.resolvePreviewHtml,
    bindAnchoredPopover: previewLifecycleHelpers.bindAnchoredPopover,
    hidePreviewSurfaces: previewLifecycleHelpers.hidePreviewSurfaces
  };

  const renderApi = Object.assign(
    {},
    stableCustomClientApi,
    bundledFeatureRenderHelpers
  );

  if (!window.bpGraphApi || typeof window.bpGraphApi !== "object") {
    window.bpGraphApi = {};
  }
  if (typeof window.bpGraphApi.graphApiModuleUrl !== "function") {
    window.bpGraphApi.graphApiModuleUrl = previewDataApi.graphApiModuleUrl;
  }

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
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      bindTemplatePreviewDescriptors(document);
    }, { once: true });
  } else {
    bindTemplatePreviewDescriptors(document);
  }
  queuedRenderReadyCallbacks.forEach(function (fn) {
    try {
      onRenderReady(fn);
    } catch (err) {
      reportRenderReadyError(err);
    }
  });
