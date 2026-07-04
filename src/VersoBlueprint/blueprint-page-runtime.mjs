import { createPreview } from "./api/preview.mjs";
import { installOpenTargetDetails } from "./Commands/open-target-details.mjs";
import { startGraphRuntime } from "./Commands/graph.mjs";
import { startInlinePreview } from "./Commands/inline-preview.mjs";
import { startRelationPanels } from "./Informal/Block/relation-panel.mjs";
import { startCommandPalette } from "./Commands/command-palette.mjs";
import { startDashboard } from "./Commands/dashboard.mjs";
import { startProofToggle } from "./Commands/proof-toggle.mjs";
import { startBannerNav } from "./Commands/banner-nav.mjs";
import { startMetadataRail } from "./Commands/metadata-rail.mjs";
import { startTopNav } from "./Commands/top-nav.mjs";
import { bootLineNumbers } from "./Commands/line-numbers.mjs";
import { startPageOutline } from "./Commands/page-outline.mjs";

export function startBlueprintPageRuntime(options = {}) {
  const preview = createPreview(options);
  installOpenTargetDetails(globalThis);
  startInlinePreview(preview);
  startRelationPanels(preview);
  startGraphRuntime(preview);
  startCommandPalette();
  startDashboard();
  startProofToggle();
  // After proof-toggle so any relocated tactic tail already exists; line-numbers
  // targets the server-rendered signature / proof-source blocks only.
  bootLineNumbers();
  startBannerNav();
  startTopNav();
  startMetadataRail();
  startPageOutline();
  return preview;
}

export const blueprintPageRuntime = startBlueprintPageRuntime();

export default {
  blueprintPageRuntime,
  startBlueprintPageRuntime,
};
