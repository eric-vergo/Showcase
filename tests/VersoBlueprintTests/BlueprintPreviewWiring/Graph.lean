/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprintTests.BlueprintPreviewWiring.Shared

namespace Verso.VersoBlueprintTests.BlueprintPreviewWiring.Graph

open Verso
open Verso.Genre.Manual
open Informal
open Verso.VersoBlueprintTests.Blueprint.Support
open Verso.VersoBlueprintTests.BlueprintPreviewWiring.Shared

set_option doc.verso true

#docs (Genre.Manual) lrDirectionGraphDoc "Blueprint LR Direction Graph" :=
:::::::
:::definition "def:graph.lr.base"
Base statement for an explicit left-to-right graph.
:::

{blueprint_graph (direction := LR) (pack := false)}
:::::::

#docs (Genre.Manual) hoverPreviewGraphDoc "Blueprint Hover Preview Graph" :=
:::::::
:::definition "def:graph.hover.base"
Base statement for an explicit hover-preview graph with the default docked panel.
:::

{blueprint_graph (preview := hover)}
:::::::

#docs (Genre.Manual) anchoredHoverPreviewGraphDoc "Blueprint Anchored Hover Preview Graph" :=
:::::::
:::definition "def:graph.hover.anchored.base"
Base statement for an explicit anchored hover-preview graph.
:::

{blueprint_graph (preview := hover) (previewPlacement := anchored)}
:::::::

set_option verso.blueprint.graph.defaultPreviewMode "hover" in
#docs (Genre.Manual) optionHoverPreviewGraphDoc "Blueprint Option Hover Preview Graph" :=
:::::::
:::definition "def:graph.option.hover.base"
Base statement for graph preview mode option coverage.
:::

{blueprint_graph}
:::::::

#guard (Informal.Commands.parseGraphPreviewMode? "hover").map (·.dataValue) == some "hover"
#guard (Informal.Commands.parseGraphPreviewMode? "pinned").map (·.dataValue) == some "pinned"
#guard (Informal.Commands.parseGraphPreviewMode? "transient").isNone
#guard (Informal.Commands.parseGraphPreviewMode? "click").isNone
#guard (Informal.Commands.parseGraphPreviewMode? "click-to-pin").isNone
#guard (Informal.Commands.parseGraphPreviewPlacement? "docked").map (·.dataValue) == some "docked"
#guard (Informal.Commands.parseGraphPreviewPlacement? "anchored").map (·.dataValue) == some "anchored"
#guard (Informal.Commands.parseGraphPreviewPlacement? "fixed").isNone
#guard (Informal.Commands.parseGraphPreviewPlacement? "near-node").isNone
#guard
  Informal.Commands.fallbackGraphControlId (default : Verso.Multi.InternalId) "--view" ==
    "bp-graph--0023-003C0-003E--view"

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, st) ← renderManualDocHtmlStringAndState manualImpls previewWiringDoc
    let graphJs? :=
      findExtraJsContaining? st
        "function attachPreviewHandlers(previewUtils, graphBlock, graphContainer, previewMap, previewController, previewKeyByNodeId)"
    pure (
      hasSubstr out "bp_graph_preview" &&
      hasSubstr out "class=\"bp_graph_preview bp_preview_panel\"" &&
      hasSubstr out "data-bp-preview-mode=\"pinned\"" &&
      hasSubstr out "data-bp-preview-placement=\"docked\"" &&
      hasSubstr out "class=\"bp_graph_controls_select bp_graph_preview_mode_select\"" &&
      hasSubstr out "data-bp-graph-default-preview-mode=\"pinned\"" &&
      hasSubstr out "class=\"bp_graph_controls_select bp_graph_preview_placement_select\"" &&
      hasSubstr out "data-bp-graph-default-preview-placement=\"docked\"" &&
      hasSubstr out "value=\"pinned\"" &&
      hasSubstr out "Click to pin" &&
      hasSubstr out "value=\"hover\"" &&
      hasSubstr out "Hover" &&
      hasSubstr out "value=\"docked\"" &&
      hasSubstr out "Docked" &&
      hasSubstr out "value=\"anchored\"" &&
      hasSubstr out "Near node" &&
      !hasSubstr out "class=\"bp_graph_preview_store\"" &&
      !hasSubstr out "class=\"bp_graph_preview_tpl\"" &&
      hasSubstr out "class=\"bp_group_hover_preview bp_preview_panel\"" &&
      hasSubstr out "class=\"bp_group_hover_preview_header bp_preview_panel_header\"" &&
      hasSubstr out "class=\"bp_group_hover_preview_title bp_preview_panel_title\"" &&
      hasSubstr out "class=\"bp_group_hover_preview_close bp_preview_panel_close\"" &&
      hasSubstr out "class=\"bp_group_hover_preview_graph bp_preview_panel_body\"" &&
      hasSubstr out "aria-label=\"Close group preview\"" &&
      hasSubstr out "class=\"bp-graph-variants\"" &&
      hasSubstr out "class=\"bp_graph_controls_button bp_graph_options_button\"" &&
      hasSubstr out "class=\"bp_graph_options_popover\"" &&
      hasSubstr out "class=\"bp_graph_controls_select bp_graph_direction_select\"" &&
      hasSubstr out "class=\"bp_graph_pack_input\"" &&
      hasSubstr out "data-bp-graph-direction=\"TB\"" &&
      hasSubstr out "data-bp-graph-pack=\"false\"" &&
      hasSubstr out "data-bp-graph-default-pack=\"false\"" &&
      hasSubstr out "\"options\":{\"direction\":\"TB\",\"pack\":false}" &&
      hasSubstr out "data-bp-tex-prelude-id" &&
      !hasSubstr out "data-bp-tex-prelude=\"" &&
      !hasSubstr out "bp_preview_tex_prelude" &&
      match graphJs? with
      | some graphJs =>
        hasRenderReadyWiring graphJs "previewUtils" &&
        hasAllSubstr graphJs [
          "function collectPreviewTemplates(previewUtils, rootNode)",
          "function parsePreviewEntry(previewUtils, entry)",
          "return previewUtils.readHtml(entry);"
        ] &&
        lacksAllSubstr graphJs [
          "function blueprintRender()",
          "window.VersoBlueprint.render"
        ] &&
        hasSubstr graphJs "function layoutGraphCanvas(graphRoot, graphState)" &&
        !hasSubstr graphJs "function normalizePreviewMode(rawMode)" &&
        !hasSubstr graphJs "function normalizePreviewPlacement(rawPlacement)" &&
        hasSubstr graphJs "function ensureGraphBlockState(graphBlock)" &&
        hasSubstr graphJs "function createPanelController(panel, behavior, titleSelector, bodySelector, options)" &&
        hasSubstr graphJs "function bindHoverablePanelLifetime(previewUtils, controller, getActiveAnchor, boundAttr)" &&
        hasSubstr graphJs "function configurePanelCloseButton(previewUtils, closeButton, hidePanel, behavior)" &&
        hasSubstr graphJs "const previewModeSelector = graphBlock.querySelector(\".bp_graph_preview_mode_select\");" &&
        hasSubstr graphJs "const previewPlacementSelector = graphBlock.querySelector(\".bp_graph_preview_placement_select\");" &&
        hasSubstr graphJs "const previewKey = nodeId ? (previewKeys.get(nodeId) || \"\") : \"\";" &&
        hasSubstr graphJs "previewUtils.resolvePreview(previewKey)" &&
        hasSubstr graphJs "previewUtils.readPanelBehavior(null, {" &&
        hasSubstr graphJs "previewUtils.readPanelBehavior(previewPanelNode, { mode: \"pinned\", placement: \"docked\" })" &&
        hasSubstr graphJs "previewUtils.renderHtmlInto(body, html)" &&
        hasSubstr graphJs "previewUtils.readPanelBehavior(groupHoverPanel, { mode: \"pinned\", placement: \"docked\" })" &&
        hasSubstr graphJs "function attachPreviewHandlers(previewUtils, graphBlock, graphContainer, previewMap, previewController, previewKeyByNodeId)" &&
        hasSubstr graphJs "graphState.previewActiveNode === node && !previewController.panel.hidden" &&
        hasSubstr graphJs "if (!previewController.behavior || !previewController.behavior.isHover) return;" &&
        hasSubstr graphJs "if (!previewController.behavior || !previewController.behavior.isPinned) return;" &&
        hasSubstr graphJs "setPreviewBehavior(previewModeSelector.value, readPreviewPlacement());" &&
        hasSubstr graphJs "setPreviewBehavior(readPreviewMode(), previewPlacementSelector.value);" &&
        hasSubstr graphJs "configurePanelCloseButton(previewUtils, previewClose" &&
        hasSubstr graphJs "configurePanelCloseButton(previewUtils, groupHoverClose" &&
        hasSubstr graphJs "previewKeyByNodeId: new Map(previewKeyByNodeId)" &&
        hasSubstr graphJs "graphviz: null," &&
        hasSubstr graphJs "renderedVariantKey: \"\"," &&
        hasSubstr graphJs "renderedOptionsKey: \"\"," &&
        hasSubstr graphJs "renderToken: 0," &&
        hasSubstr graphJs "function dotWithGraphOptions(dot, options)" &&
        hasSubstr graphJs "function dotForVariantOptions(variant, options)" &&
        hasSubstr graphJs "return dotWithGraphOptions(variant.dot, options);" &&
        hasSubstr graphJs "function resetGraphvizForVariant(graphRoot, graphState)" &&
        hasSubstr graphJs "function bindOptionsPopover(graphBlock)" &&
        hasSubstr graphJs "const finalizeRender = function () {" &&
        hasSubstr graphJs "if (graphState.renderToken !== renderToken) return;" &&
        hasSubstr graphJs "const gv = graphState.graphviz || graphContainer.graphviz();" &&
        hasSubstr graphJs "const directionSelector = graphBlock.querySelector(\".bp_graph_direction_select\");" &&
        hasSubstr graphJs "const packInput = graphBlock.querySelector(\".bp_graph_pack_input\");" &&
        hasSubstr graphJs "let activeOptions = normalizeGraphOptions({" &&
        hasSubstr graphJs "switchDirection(directionSelector.value);" &&
        hasSubstr graphJs "switchPack(packInput.checked);" &&
        hasSubstr graphJs ".zoom(true)" &&
        hasSubstr graphJs "function normalizeGraphDirection(rawDirection)" &&
        hasSubstr graphJs "function normalizeGraphPack(rawPack)" &&
        hasSubstr graphJs "layoutGraphCanvas(graphRoot, graphState)" &&
        hasSubstr graphJs "if (typeof ResizeObserver === \"function\")" &&
        hasSubstr graphJs ".fit(true)" &&
        hasSubstr graphJs "syncLegend(graphBlock, activeKey)"
      | none => false
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, _) ← renderManualDocHtmlStringAndState manualImpls hoverPreviewGraphDoc
    pure (
      hasSubstr out "data-bp-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-preview-placement=\"docked\"" &&
      hasSubstr out "data-bp-graph-default-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-graph-default-preview-placement=\"docked\"" &&
      hasSubstr out "value=\"pinned\"" &&
      hasSubstr out "Click to pin" &&
      hasSubstr out "value=\"hover\"" &&
      hasSubstr out "Hover" &&
      hasSubstr out "value=\"docked\"" &&
      hasSubstr out "Docked" &&
      hasSubstr out "value=\"anchored\"" &&
      hasSubstr out "Near node"
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, _) ← renderManualDocHtmlStringAndState manualImpls anchoredHoverPreviewGraphDoc
    pure (
      hasSubstr out "data-bp-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-preview-placement=\"anchored\"" &&
      hasSubstr out "data-bp-graph-default-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-graph-default-preview-placement=\"anchored\""
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, _) ← renderManualDocHtmlStringAndState manualImpls optionHoverPreviewGraphDoc
    pure (
      hasSubstr out "data-bp-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-preview-placement=\"docked\"" &&
      hasSubstr out "data-bp-graph-default-preview-mode=\"hover\"" &&
      hasSubstr out "data-bp-graph-default-preview-placement=\"docked\""
    )

/-- info: true -/
#guard_msgs in
#eval
  show IO Bool from do
    let (out, _) ← renderManualDocHtmlStringAndState manualImpls lrDirectionGraphDoc
    pure (
      hasSubstr out "data-bp-graph-direction=\"LR\"" &&
      hasSubstr out "data-bp-graph-pack=\"false\"" &&
      hasSubstr out "data-bp-graph-default-direction=\"LR\"" &&
      hasSubstr out "data-bp-graph-default-pack=\"false\"" &&
      (hasSubstr out "selected value=\"LR\"" || hasSubstr out "value=\"LR\" selected") &&
      hasSubstr out "\"options\":{\"direction\":\"LR\",\"pack\":false}" &&
      hasSubstr out "rankdir=LR;" &&
      hasSubstr out "pack=false;" &&
      !hasSubstr out "dotByDirection"
    )

end Verso.VersoBlueprintTests.BlueprintPreviewWiring.Graph
