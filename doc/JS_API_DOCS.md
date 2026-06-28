# Verso Blueprint JavaScript API

Verso Blueprint emits browser-facing ESM modules under `-verso-data/api/` in
generated sites. These modules are plain JavaScript, documented with JSDoc, and
checked with TypeScript's `allowJs` and `checkJs` workflow.

Use the preview API for most custom clients:

```js
import { createPreview } from "./-verso-data/api/preview.mjs";

const preview = createPreview({
  hydrators: {
    audit(root) {
      root.querySelectorAll("[data-audit-target]").forEach(bindAuditWidget);
    }
  }
});

await preview.renderNode(document.querySelector("#target"), {
  label: "Chapter2:Problem2.11.6",
  externalMarkup: {
    prefer: [
      { language: "verso", slot: "statement" },
      { language: "markdown", slot: "original", render: renderMarkdown },
      { display: "source" }
    ]
  }
});
```

## Modules

- [preview API](module-blueprint-preview-api.html): render Blueprint nodes,
  hydrate generated fragments, resolve canonical generated-node shells, and
  provide call-scoped external-markup fallback renderers.
- [data API](module-blueprint-data-api.html): load generated manifests,
  rendered-fragment caches, preview keys, and generated-data URLs without
  installing browser-global render hooks.
- [graph API](module-blueprint-graph-api.html): read graph data embedded in
  generated graph pages, load graph variants from a manifest, or render
  generated graph blocks with an explicit preview renderer.
- [shared API types](module-blueprint-api-types.html): request, result, option,
  manifest, cache, graph, external-markup, and hydrator shapes.

## Key Types

- `BlueprintPreviewOptions`: loader, hydration, math-rendering, canonical-page,
  and cache options accepted by render-capable APIs.
- `BlueprintRenderNodeRequest`: label-oriented request accepted by
  `renderNode`.
- `BlueprintExternalMarkupPreference`: ordered fallback entry for Markdown,
  TeX, Verso source, or raw-source display when a native rendered preview is
  unavailable.
- `BlueprintPreviewApi`: the render-capable API returned by `createPreview`;
  it combines manifest/cache helpers with preview-specific render methods.
- `BlueprintRenderNodeResult`: typed success or diagnostic result returned by
  `renderNode`.

## Generated Artifacts

The declarations produced by `npm run build:types` are build artifacts under
`dist/types`; they are not tracked in source. `npm run check:types` verifies
that the generated public declarations keep named API types instead of
collapsing to broad `any` shapes. The HTML docs produced by `npm run docs` are
written to `_out/jsdoc-api`; `npm run check:docs` validates the generated
module pages, local links, and Blueprint typedef anchors before CI uploads that
directory as the `js-api-docs` artifact.
