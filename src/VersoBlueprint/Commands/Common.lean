/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean.Data.Options

namespace Informal.Commands

open Lean

register_option verso.blueprint.debug.commands : Bool := {
  defValue := false
  descr := "Emit debug info logs for blueprint graph, summary, and bibliography commands"
}

def blueprintTokensCss : String := r##"
:root {
  --bp-color-surface: #ffffff;
  --bp-color-surface-muted: #f8fafc;
  --bp-color-surface-subtle: #f9fafb;
  --bp-color-surface-modern: #f8fbff;
  --bp-color-surface-warn: #fff7ed;
  --bp-color-surface-warn-soft: #ffedd5;
  --bp-color-surface-note: #fffbeb;
  --bp-color-border: #cbd5e1;
  --bp-color-border-soft: #e2e8f0;
  --bp-color-border-muted: #d1d5db;
  --bp-color-border-panel: #dbe4ee;
  --bp-color-border-strong: #94a3b8;
  --bp-color-text-strong: #0f172a;
  --bp-color-text: #111827;
  --bp-color-text-muted: #334155;
  --bp-color-text-subtle: #475569;
  --bp-color-text-faint: #64748b;
  --bp-color-accent-success: #16a34a;
  --bp-color-accent-warning: #ca8a04;
  --bp-color-accent-danger: #dc2626;
  --bp-color-accent-info: #7c3aed;
  --bp-color-status-success-text: #166534;
  --bp-color-status-warning-text: #a16207;
  --bp-color-status-warning-strong: #9a3412;
  --bp-color-status-warning-border: #fdba74;
  --bp-color-status-warning-border-soft: #fed7aa;
  --bp-color-status-error-text: #b91c1c;
  --bp-color-status-error-strong: #991b1b;
  --bp-color-status-error-border-soft: #fecaca;
  --bp-color-status-note-border: #fcd34d;
  --bp-color-status-note-text: #92400e;
  --bp-color-focus-border: #93c5fd;
  --bp-color-focus-surface: #eff6ff;
  --bp-color-focus-ring: rgba(59, 130, 246, 0.12);
  --bp-color-selection: rgba(59, 130, 246, 0.18);
  --bp-color-selection-ring: rgba(59, 130, 246, 0.22);
  --bp-color-selection-surface-strong: rgba(59, 130, 246, 0.28);
  --bp-color-selection-surface-soft: rgba(59, 130, 246, 0.14);
  --bp-color-selection-surface-faint: rgba(59, 130, 246, 0.1);
  --bp-color-selection-shadow-strong: rgba(59, 130, 246, 0.3);
  --bp-color-selection-shadow-soft: rgba(59, 130, 246, 0.24);
  --bp-color-selection-shadow-faint: rgba(59, 130, 246, 0.16);
  --bp-color-target-ring: rgba(37, 99, 235, 0.22);
  --bp-color-target-surface: rgba(37, 99, 235, 0.14);
  --bp-color-target-ring-strong: rgba(37, 99, 235, 0.28);
  --bp-color-modern-border: #d6deea;
  --bp-color-modern-surface-alt: #f5f9ff;
  --bp-color-modern-caption: #e0ecff;
  --bp-color-bold-surface-glow-1: rgba(251, 191, 36, 0.2);
  --bp-color-bold-surface-glow-2: rgba(16, 185, 129, 0.2);
  --bp-color-bold-link: #7c2d12;
  --bp-color-bold-label: #f59e0b;
  --bp-color-biblio-border: #d6ccff;
  --bp-color-biblio-surface: #faf7ff;
  --bp-color-biblio-border-soft: #e9ddff;
  --bp-color-biblio-surface-soft: #fdfbff;
  --bp-color-biblio-link: #4c1d95;
  --bp-radius-sm: 0.35rem;
  --bp-radius-md: 0.45rem;
  --bp-radius-lg: 0.5rem;
  --bp-radius-xl: 0.55rem;
  --bp-radius-2xl: 0.7rem;
  --bp-radius-3xl: 0.85rem;
  --bp-radius-pill: 999px;
  --bp-shadow-sm: 0 4px 14px rgba(15, 23, 42, 0.1);
  --bp-shadow-md: 0 10px 24px rgba(15, 23, 42, 0.16);
  --bp-shadow-lg: 0 12px 28px rgba(15, 23, 42, 0.18);
  --bp-shadow-modern: 0 6px 18px rgba(15, 23, 42, 0.08);
  --bp-shadow-bold: 0 7px 0 var(--bp-color-text-strong);
  --bp-shadow-bold-lg: 0 9px 0 var(--bp-color-text-strong);
}
"##

def previewPanelCss : String := r##"
.bp_preview_panel {
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-lg);
  background: var(--bp-color-surface);
  box-shadow: var(--bp-shadow-md);
  padding: 0.65rem 0.75rem;
}

.bp_preview_panel[hidden] {
  display: none !important;
}

.bp_preview_panel[data-bp-preview-placement="anchored"]::before {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  top: -0.85rem;
  height: 0.85rem;
}

.bp_preview_panel[data-bp-preview-placement="anchored"]::after {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  bottom: -0.85rem;
  height: 0.85rem;
}

.bp_preview_panel_header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  margin-bottom: 0.4rem;
}

.bp_preview_panel_title {
  font-weight: 700;
  color: var(--bp-color-text);
  min-width: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.bp_preview_panel_close {
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-sm);
  background: var(--bp-color-surface);
  color: var(--bp-color-text-strong);
  font-size: 0.72rem;
  font-weight: 600;
  line-height: 1;
  padding: 0.25rem 0.45rem;
  cursor: pointer;
}

.bp_preview_panel[data-bp-preview-mode="hover"] .bp_preview_panel_close {
  display: none;
}

.bp_preview_panel_body {
  border-left: 2px solid var(--bp-color-border-soft);
  overflow: auto;
}
"##

-- Keep this module rebuilt when the embedded preview runtime changes.
-- This module owns the shared Blueprint render API boundary, so adjacent edits
-- here should land whenever preview runtime assets are intentionally refreshed.
def previewHoverUtilsJs : String := include_str "preview-runtime.js"

def previewHeaderCss : String := r##"
.bp_preview_header_heading {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 0.42rem;
  flex: 1 1 auto;
  min-width: 0;
}

.bp_preview_header_heading > *:first-child {
  min-width: 0;
}

.bp_preview_header_label {
  margin-left: auto;
  max-width: 100%;
  color: var(--bp-color-text-muted);
  font-family: var(--bp-font-mono, ui-monospace, SFMono-Regular, Menlo, Consolas, monospace);
  font-size: 0.72rem;
  font-weight: 600;
  overflow-wrap: anywhere;
  text-align: right;
  text-decoration: none;
}

.bp_preview_header_label[href]:hover {
  color: var(--bp-color-link);
  text-decoration: underline;
}

.bp_preview_header_label[hidden] {
  display: none;
}
"##

def inlinePreviewCss : String := r##"
.bp_inline_preview_ref {
  cursor: help;
}

.bp_inline_preview_panel {
  position: fixed;
  display: flex;
  flex-direction: column;
  z-index: 70;
  min-width: 18rem;
  max-width: min(34rem, 86vw);
  max-height: min(26rem, 80vh);
  overflow: hidden;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-md);
  background: var(--bp-color-surface);
  box-shadow: var(--bp-shadow-lg);
}

.bp_inline_preview_panel[hidden] {
  display: none !important;
}

.bp_inline_preview_panel_child {
  z-index: 71;
}

.bp_inline_preview_panel[hidden] {
  display: none;
}

.bp_inline_preview_panel[data-bp-preview-placement="anchored"]::before {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  top: -0.85rem;
  height: 0.85rem;
}

.bp_inline_preview_panel[data-bp-preview-placement="docked"] {
  top: 0.9rem;
  right: 0.9rem;
  left: auto;
}

.bp_inline_preview_panel_header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.6rem;
  padding: 0.4rem 0.55rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  background: var(--bp-color-surface-muted);
}

.bp_inline_preview_panel_title {
  font-size: 0.82rem;
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_inline_preview_panel_close {
  border: 1px solid var(--bp-color-border);
  border-radius: 0.3rem;
  background: var(--bp-color-surface);
  color: var(--bp-color-text-muted);
  font-size: 0.72rem;
  line-height: 1;
  padding: 0.2rem 0.35rem;
  cursor: pointer;
}

.bp_inline_preview_panel_body {
  padding: 0.5rem 0.6rem 0.55rem;
  min-height: 0;
  max-height: min(22rem, 70vh);
  overflow: auto;
  font-size: 0.8rem;
}

.bp_inline_preview_panel_footer {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.35rem;
  padding: 0.38rem 0.55rem 0.42rem;
  border-top: 1px solid var(--bp-color-border-soft);
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-subtle);
  font-size: 0.72rem;
}

.bp_inline_preview_panel_footer[hidden] {
  display: none;
}

.bp_inline_preview_panel_footer code {
  font-size: 0.72rem;
}

.bp_bibliography_hover_entry {
  border: 1px solid var(--bp-color-border-soft);
  border-radius: 0.4rem;
  padding: 0.35rem 0.45rem;
  background: var(--bp-color-surface-muted);
}

.bp_bibliography_hover_entry .citation {
  display: block;
  line-height: 1.35;
}

.bp_bibliography_hover_meta {
  margin-top: 0.42rem;
  display: flex;
  align-items: baseline;
  gap: 0.42rem;
  flex-wrap: wrap;
}

.bp_bibliography_hover_meta_label {
  font-size: 0.68rem;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--bp-color-text-faint);
}

.bp_bibliography_hover_meta_value {
  font-size: 0.76rem;
  font-weight: 600;
  color: var(--bp-color-text-strong);
}

.bp_code_hover_section {
  margin-top: 0.28rem;
}

.bp_code_hover_label {
  font-weight: 600;
  color: var(--bp-color-text-muted);
}

.bp_code_hover_list code {
  font-size: 0.76rem;
}

.bp_code_hover_none {
  color: var(--bp-color-text-faint);
  font-style: italic;
}

.bp_inline_preview_panel[data-bp-preview-mode="hover"] .bp_inline_preview_panel_close {
  display: none;
}
"##

def openTargetDetailsJs : String := r##"(function () {
  function openFromHash() {
    if (!window.location.hash) return;
    const id = decodeURIComponent(window.location.hash.slice(1));
    if (!id) return;
    const target = document.getElementById(id);
    if (!target) return;
    const details = target.matches("details") ? target : target.closest("details");
    if (details) details.open = true;
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", openFromHash);
  } else {
    openFromHash();
  }
  window.addEventListener("hashchange", openFromHash);
})();"##

def inlineLinkPreviewJs : String := r##"(function () {
  const triggerSelector = ".bp_inline_preview_ref[data-bp-preview-id]";

  function fallbackInlinePreviewHtml(trigger, key, escapeHtml) {
    if (!(trigger instanceof Element)) return "";
    const title = (trigger.getAttribute("data-bp-preview-title") || key || "").trim();
    const label = (trigger.getAttribute("data-bp-preview-fallback-label") || "").trim();
    const detail = (trigger.getAttribute("data-bp-preview-fallback-detail") || "").trim();
    const text = (trigger.textContent || "").trim();
    let html = '<div class="bp_code_hover" role="tooltip">';
    html += '<div class="bp_code_hover_title">' + escapeHtml(title || "Preview") + "</div>";
    if (text.length > 0) {
      html += '<div class="bp_code_hover_section"><span class="bp_code_hover_label">Reference</span><ul class="bp_code_hover_list"><li>' +
        escapeHtml(text) + "</li></ul></div>";
    }
    if (label.length > 0) {
      html += '<div class="bp_code_hover_section"><span class="bp_code_hover_label">Blueprint label</span><ul class="bp_code_hover_list"><li><code>' +
        escapeHtml(label) + "</code></li></ul></div>";
    }
    if (detail.length > 0) {
      html += '<div class="bp_code_hover_section"><span class="bp_code_hover_label">Detail</span><ul class="bp_code_hover_list"><li>' +
        escapeHtml(detail) + "</li></ul></div>";
    }
    html += "</div>";
    return html;
  }

  function makePanel(id, extraClass) {
    const panel = document.createElement("aside");
    panel.id = id;
    panel.className =
      "bp_inline_preview_panel" + (typeof extraClass === "string" && extraClass.length > 0 ? " " + extraClass : "");
    panel.setAttribute("data-bp-preview-mode", "hover");
    panel.setAttribute("data-bp-preview-placement", "anchored");
    panel.hidden = true;
    panel.innerHTML =
      '<div class="bp_inline_preview_panel_header">' +
      '<div class="bp_inline_preview_panel_heading bp_preview_header_heading">' +
      '<div class="bp_inline_preview_panel_title"></div>' +
      '<a class="bp_inline_preview_panel_label bp_preview_header_label" hidden></a>' +
      "</div>" +
      '<button type="button" class="bp_inline_preview_panel_close" aria-label="Close inline preview">Close</button>' +
      "</div>" +
      '<div class="bp_inline_preview_panel_body"></div>' +
      '<div class="bp_inline_preview_panel_footer" hidden></div>';
    document.body.appendChild(panel);
    return panel;
  }

  function getPanel(id, extraClass) {
    const existing = document.getElementById(id);
    if (existing instanceof Element) return existing;
    return makePanel(id, extraClass);
  }

  function bindInlinePreview() {
    if (!(document.body instanceof Element)) return;
    if (document.body.getAttribute("data-bp-inline-preview-bound") === "1") return;
    document.body.setAttribute("data-bp-inline-preview-bound", "1");

    const previewUtils = window.VersoBlueprint && window.VersoBlueprint.render;
    if (
      !previewUtils ||
      typeof previewUtils.readPanelBehavior !== "function" ||
      typeof previewUtils.showPanelContent !== "function" ||
      typeof previewUtils.hidePanelContent !== "function" ||
      typeof previewUtils.setPreviewHeaderLink !== "function" ||
      typeof previewUtils.shouldKeepOpen !== "function" ||
      typeof previewUtils.escapeHtml !== "function" ||
      typeof previewUtils.configureCloseButton !== "function" ||
      typeof previewUtils.positionAnchoredPanel !== "function" ||
      typeof previewUtils.resolvePreview !== "function" ||
      typeof previewUtils.hydrate !== "function"
    ) {
      return;
    }
    const escapeHtml = previewUtils.escapeHtml;
    const previewDebug =
      typeof previewUtils.previewDebug === "function"
        ? previewUtils.previewDebug
        : function () {};
    const previewDebugLabel =
      typeof previewUtils.previewDebugLabel === "function"
        ? previewUtils.previewDebugLabel
        : function (node) { return String(node); };

    const panel = getPanel("bp-inline-preview-panel", "");
    const title = panel.querySelector(".bp_inline_preview_panel_title");
    const headerLabel = panel.querySelector(".bp_inline_preview_panel_label");
    const body = panel.querySelector(".bp_inline_preview_panel_body");
    const footer = panel.querySelector(".bp_inline_preview_panel_footer");
    const close = panel.querySelector(".bp_inline_preview_panel_close");
    const childPanel = getPanel("bp-inline-preview-child-panel", "bp_inline_preview_panel_child");
    const childTitle = childPanel.querySelector(".bp_inline_preview_panel_title");
    const childHeaderLabel = childPanel.querySelector(".bp_inline_preview_panel_label");
    const childBody = childPanel.querySelector(".bp_inline_preview_panel_body");
    const childFooter = childPanel.querySelector(".bp_inline_preview_panel_footer");
    const childClose = childPanel.querySelector(".bp_inline_preview_panel_close");
    if (
      !(title instanceof Element) || !(headerLabel instanceof Element) ||
      !(body instanceof Element) || !(footer instanceof Element) || !(close instanceof Element) ||
      !(childTitle instanceof Element) || !(childHeaderLabel instanceof Element) ||
      !(childBody instanceof Element) || !(childFooter instanceof Element) ||
      !(childClose instanceof Element)
    ) {
      return;
    }

    function makeBehavior(mode, placement) {
      return previewUtils.readPanelBehavior(null, { mode: mode, placement: placement });
    }

    let behavior = makeBehavior("hover", "anchored");
    let activeTrigger = null;
    let activeHost = null;
    let activePreviewKey = "";
    let hideTimer = null;
    let updatingPanel = false;
    let ignoreNextPanelExit = false;
    let showRequestToken = 0;
    let childActiveTrigger = null;
    let childPreviewKey = "";
    let childHideTimer = null;
    let childShowRequestToken = 0;
    const childBehavior = makeBehavior("hover", "anchored");

    function clearPanelSizeLock() {
      panel.style.width = "";
      panel.style.minHeight = "";
    }

    function lockPanelSizeToCurrentRect() {
      const rect = panel.getBoundingClientRect();
      if (!(rect.width > 0) || !(rect.height > 0)) return;
      panel.style.width = rect.width + "px";
      panel.style.minHeight = rect.height + "px";
    }

    function cancelHide() {
      if (hideTimer !== null) {
        clearTimeout(hideTimer);
        hideTimer = null;
      }
    }

    function cancelChildHide() {
      if (childHideTimer !== null) {
        clearTimeout(childHideTimer);
        childHideTimer = null;
      }
    }

    function setPanelFooter(footerNode, trigger) {
      if (!(footerNode instanceof Element)) return;
      const footerHtml =
        trigger instanceof Element
          ? (trigger.getAttribute("data-bp-preview-footer-html") || "").trim()
          : "";
      if (footerHtml.length > 0) {
        footerNode.innerHTML = footerHtml;
        footerNode.hidden = false;
        previewUtils.hydrate(footerNode);
      } else {
        footerNode.innerHTML = "";
        footerNode.hidden = true;
      }
    }

    function readInlinePreviewHost(trigger) {
      if (!(trigger instanceof Element)) return null;
      const host = trigger.closest(".bp_relation_panel, .bp_graph_preview, .bp_group_hover_preview");
      if (!(host instanceof Element)) return null;
      if (panel.contains(host)) return null;
      let kind = "generic";
      if (host.matches(".bp_relation_panel")) {
        kind = "relation";
      } else if (host.matches(".bp_graph_preview")) {
        kind = "graph";
      } else if (host.matches(".bp_group_hover_preview")) {
        kind = "graph-group";
      }
      return {
        element: host,
        kind: kind,
        behavior: makeBehavior("hover", "anchored")
      };
    }

    function positionDockedPanel(hostInfo) {
      if (!hostInfo || !(hostInfo.element instanceof Element)) return;
      const margin = 12;
      const gap = 12;
      const hostRect = hostInfo.element.getBoundingClientRect();
      const panelRect = panel.getBoundingClientRect();
      const panelWidth = panelRect.width || Math.min(520, window.innerWidth - margin * 2);
      const panelHeight = panelRect.height || Math.min(420, window.innerHeight - margin * 2);
      let left = hostRect.right + gap;
      if (left + panelWidth > window.innerWidth - margin) {
        left = hostRect.left - panelWidth - gap;
      }
      left = Math.max(margin, Math.min(left, window.innerWidth - panelWidth - margin));
      let top = hostRect.top;
      if (top + panelHeight > window.innerHeight - margin) {
        top = window.innerHeight - panelHeight - margin;
      }
      top = Math.max(margin, top);
      panel.style.left = left + "px";
      panel.style.top = top + "px";
    }

    function applyBehavior(nextBehavior, hostInfo) {
      behavior = nextBehavior || makeBehavior("hover", "anchored");
      activeHost = hostInfo || null;
      panel.setAttribute("data-bp-preview-mode", behavior.mode);
      panel.setAttribute("data-bp-preview-placement", behavior.placement);
      if (activeHost && activeHost.kind) {
        panel.setAttribute("data-bp-inline-host", activeHost.kind);
      } else {
        panel.removeAttribute("data-bp-inline-host");
      }
      previewUtils.configureCloseButton(close, hidePanel, behavior);
    }

    function bindInlinePreviewTriggers(root) {
      if (!(root instanceof Element || root instanceof Document)) return;
      root.querySelectorAll(triggerSelector).forEach(function (trigger) {
        if (!(trigger instanceof Element)) return;
        if (trigger.getAttribute("data-bp-inline-bound") === "1") return;
        trigger.setAttribute("data-bp-inline-bound", "1");
        const triggerKey = (trigger.getAttribute("data-bp-preview-id") || "").trim();
        const triggerInsidePanel = panel.contains(trigger) || childPanel.contains(trigger);
        trigger.addEventListener("mouseenter", function () {
          if (triggerInsidePanel) {
            cancelHide();
            cancelChildHide();
            showChildFromTrigger(trigger);
          } else {
            cancelHide();
            showFromTrigger(trigger);
          }
        });
        trigger.addEventListener("focusin", function () {
          if (triggerInsidePanel) {
            cancelHide();
            cancelChildHide();
            showChildFromTrigger(trigger);
          } else {
            cancelHide();
            showFromTrigger(trigger);
          }
        });
        if (triggerInsidePanel) {
          trigger.addEventListener("mouseleave", function (ev) {
            if (childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
            if (previewUtils.shouldKeepOpen(ev.relatedTarget, trigger, childPanel)) return;
            scheduleChildHide();
          });
          trigger.addEventListener("focusout", function (ev) {
            if (childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
            if (previewUtils.shouldKeepOpen(ev.relatedTarget, trigger, childPanel)) return;
            scheduleChildHide();
          });
          return;
        }
        trigger.addEventListener("mouseleave", function (ev) {
          if (!behavior.isHover) return;
          if (!trigger.isConnected) return;
          if (triggerKey && activePreviewKey && triggerKey !== activePreviewKey) return;
          if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
          if (panel.matches(":hover") || panel.matches(":focus-within")) return;
          if (previewUtils.shouldKeepOpen(ev.relatedTarget, trigger, panel)) return;
          previewDebug("inline.trigger.mouseleave", {
            triggerKey: triggerKey,
            activePreviewKey: activePreviewKey,
            trigger: previewDebugLabel(trigger),
            relatedTarget: previewDebugLabel(ev.relatedTarget),
            panelHover: panel.matches(":hover"),
            panelFocus: panel.matches(":focus-within"),
            updatingPanel: updatingPanel
          });
          scheduleHide();
        });
        trigger.addEventListener("focusout", function (ev) {
          if (!behavior.isHover) return;
          if (!trigger.isConnected) return;
          if (triggerKey && activePreviewKey && triggerKey !== activePreviewKey) return;
          if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
          if (panel.matches(":hover") || panel.matches(":focus-within")) return;
          if (previewUtils.shouldKeepOpen(ev.relatedTarget, trigger, panel)) return;
          previewDebug("inline.trigger.focusout", {
            triggerKey: triggerKey,
            activePreviewKey: activePreviewKey,
            trigger: previewDebugLabel(trigger),
            relatedTarget: previewDebugLabel(ev.relatedTarget),
            panelHover: panel.matches(":hover"),
            panelFocus: panel.matches(":focus-within"),
            updatingPanel: updatingPanel
          });
          scheduleHide();
        });
      });
    }

    function refresh(root) {
      const scope = root instanceof Element || root instanceof Document ? root : document;
      bindInlinePreviewTriggers(scope);
    }

    function hidePanel() {
      cancelHide();
      showRequestToken += 1;
      hideChildPanel();
      previewDebug("inline.hide", {
        activePreviewKey: activePreviewKey,
        activeTrigger: previewDebugLabel(activeTrigger),
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within"),
        updatingPanel: updatingPanel
      });
      clearPanelSizeLock();
      previewUtils.hidePanelContent(panel, title, body);
      previewUtils.setPreviewHeaderLink(headerLabel, null);
      setPanelFooter(footer, null);
      activeTrigger = null;
      activeHost = null;
      activePreviewKey = "";
      applyBehavior(makeBehavior("hover", "anchored"), null);
    }

    function hideChildPanel() {
      cancelChildHide();
      childShowRequestToken += 1;
      previewUtils.hidePanelContent(childPanel, childTitle, childBody);
      previewUtils.setPreviewHeaderLink(childHeaderLabel, null);
      setPanelFooter(childFooter, null);
      childActiveTrigger = null;
      childPreviewKey = "";
    }

    function scheduleHide() {
      cancelHide();
      if (!behavior.isHover) {
        hidePanel();
        return;
      }
      hideTimer = window.setTimeout(function () {
        hideTimer = null;
        previewDebug("inline.scheduleHide.fire", {
          activePreviewKey: activePreviewKey,
          activeTrigger: previewDebugLabel(activeTrigger),
          panelHover: panel.matches(":hover"),
          panelFocus: panel.matches(":focus-within"),
          updatingPanel: updatingPanel
        });
        hidePanel();
      }, 180);
    }

    function scheduleChildHide() {
      cancelChildHide();
      childHideTimer = window.setTimeout(function () {
        childHideTimer = null;
        hideChildPanel();
      }, 180);
    }

    async function resolvePreviewHtml(key, trigger) {
      const previewLookupKey =
        trigger instanceof Element
          ? (trigger.getAttribute("data-bp-preview-key") || "").trim()
          : "";
      if (previewLookupKey) {
        const result = await previewUtils.resolvePreview(previewLookupKey);
        if (result && result.ok && result.html) return result.html;
      }
      return fallbackInlinePreviewHtml(trigger, key, escapeHtml);
    }

    async function showChildFromTrigger(trigger) {
      if (!(trigger instanceof Element)) return;
      const key = (trigger.getAttribute("data-bp-preview-id") || "").trim();
      if (!key) {
        hideChildPanel();
        return;
      }
      const requestToken = ++childShowRequestToken;
      const html = await resolvePreviewHtml(key, trigger);
      if (requestToken !== childShowRequestToken) return;
      if (!html) {
        hideChildPanel();
        return;
      }
      const heading = (trigger.getAttribute("data-bp-preview-title") || key).trim() || key;
      cancelHide();
      cancelChildHide();
      childPreviewKey = key;
      childActiveTrigger = trigger;
      previewUtils.setPreviewHeaderLink(childHeaderLabel, trigger);
      setPanelFooter(childFooter, trigger);
      previewUtils.showPanelContent(childPanel, childTitle, childBody, heading, html, childBehavior, trigger, 12, 10);
    }

    async function showFromTrigger(trigger) {
      if (!(trigger instanceof Element)) return;
      if (panel.contains(trigger) || childPanel.contains(trigger)) {
        showChildFromTrigger(trigger);
        return;
      }
      const key = (trigger.getAttribute("data-bp-preview-id") || "").trim();
      if (!key) {
        hidePanel();
        return;
      }
      const requestToken = ++showRequestToken;
      const html = await resolvePreviewHtml(key, trigger);
      if (requestToken !== showRequestToken) return;
      if (!html) {
        hidePanel();
        return;
      }
      const heading = (trigger.getAttribute("data-bp-preview-title") || key).trim() || key;
      activePreviewKey = key;
      const inPanel = panel.contains(trigger);
      const hostInfo = inPanel ? activeHost : readInlinePreviewHost(trigger);
      applyBehavior(hostInfo ? hostInfo.behavior : makeBehavior("hover", "anchored"), hostInfo);
      updatingPanel = inPanel;
      previewDebug("inline.show", {
        key: key,
        inPanel: inPanel,
        trigger: previewDebugLabel(trigger),
        host: activeHost ? activeHost.kind : "",
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within")
      });
      if (inPanel) {
        lockPanelSizeToCurrentRect();
        activeTrigger = null;
        ignoreNextPanelExit = true;
        title.textContent = heading;
        previewUtils.setPreviewHeaderLink(headerLabel, trigger);
        setPanelFooter(footer, trigger);
        body.innerHTML = html;
        previewUtils.hydrate(body);
        panel.hidden = false;
        if (behavior.isDocked && activeHost) {
          positionDockedPanel(activeHost);
        }
        window.setTimeout(function () {
          updatingPanel = false;
        }, 180);
      } else {
        hideChildPanel();
        clearPanelSizeLock();
        activeTrigger = trigger;
        previewUtils.setPreviewHeaderLink(headerLabel, trigger);
        setPanelFooter(footer, trigger);
        previewUtils.showPanelContent(panel, title, body, heading, html, behavior, trigger, 12, 10);
        if (behavior.isDocked && activeHost) {
          positionDockedPanel(activeHost);
        }
      }
    }
    applyBehavior(behavior, null);
    previewUtils.configureCloseButton(childClose, hideChildPanel, childBehavior);
    panel.addEventListener("mouseenter", function () {
      cancelHide();
    });
    panel.addEventListener("focusin", function () {
      cancelHide();
    });
    panel.addEventListener("mouseleave", function (ev) {
      if (!behavior.isHover) return;
      if (updatingPanel) return;
      if (ignoreNextPanelExit) {
        ignoreNextPanelExit = false;
        previewDebug("inline.panel.mouseleave.ignored", {
          activePreviewKey: activePreviewKey,
          relatedTarget: previewDebugLabel(ev.relatedTarget),
          panelHover: panel.matches(":hover"),
          panelFocus: panel.matches(":focus-within")
        });
        return;
      }
      if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
      if (previewUtils.pointerWithinPanel(panel, ev)) return;
      if (panel.matches(":hover") || panel.matches(":focus-within")) return;
      if (previewUtils.shouldKeepOpen(ev.relatedTarget, activeTrigger, panel)) return;
      previewDebug("inline.panel.mouseleave", {
        activePreviewKey: activePreviewKey,
        activeTrigger: previewDebugLabel(activeTrigger),
        relatedTarget: previewDebugLabel(ev.relatedTarget),
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within"),
        updatingPanel: updatingPanel
      });
      scheduleHide();
    });
    panel.addEventListener("focusout", function (ev) {
      if (!behavior.isHover) return;
      if (updatingPanel) return;
      if (ignoreNextPanelExit) {
        ignoreNextPanelExit = false;
        previewDebug("inline.panel.focusout.ignored", {
          activePreviewKey: activePreviewKey,
          relatedTarget: previewDebugLabel(ev.relatedTarget),
          panelHover: panel.matches(":hover"),
          panelFocus: panel.matches(":focus-within")
        });
        return;
      }
      if (childPanel.contains(ev.relatedTarget) || childPanel.matches(":hover") || childPanel.matches(":focus-within")) return;
      if (panel.matches(":hover") || panel.matches(":focus-within")) return;
      if (previewUtils.shouldKeepOpen(ev.relatedTarget, activeTrigger, panel)) return;
      previewDebug("inline.panel.focusout", {
        activePreviewKey: activePreviewKey,
        activeTrigger: previewDebugLabel(activeTrigger),
        relatedTarget: previewDebugLabel(ev.relatedTarget),
        panelHover: panel.matches(":hover"),
        panelFocus: panel.matches(":focus-within"),
        updatingPanel: updatingPanel
      });
      scheduleHide();
    });
    document.addEventListener("keydown", function (ev) {
      if (ev.key === "Escape") {
        hidePanel();
      }
    });
    childPanel.addEventListener("mouseenter", function () {
      cancelHide();
      cancelChildHide();
    });
    childPanel.addEventListener("focusin", function () {
      cancelHide();
      cancelChildHide();
    });
    childPanel.addEventListener("mouseleave", function (ev) {
      if (previewUtils.pointerWithinPanel(childPanel, ev)) return;
      if (previewUtils.shouldKeepOpen(ev.relatedTarget, childActiveTrigger, childPanel)) return;
      scheduleChildHide();
    });
    childPanel.addEventListener("focusout", function (ev) {
      if (previewUtils.shouldKeepOpen(ev.relatedTarget, childActiveTrigger, childPanel)) return;
      scheduleChildHide();
    });
    window.addEventListener("resize", function () {
      if (behavior.isAnchored && activeTrigger && !panel.hidden) {
        previewUtils.positionAnchoredPanel(panel, activeTrigger, 12, 10);
      } else if (behavior.isDocked && activeHost && !panel.hidden) {
        positionDockedPanel(activeHost);
      }
      if (childActiveTrigger && !childPanel.hidden) {
        previewUtils.positionAnchoredPanel(childPanel, childActiveTrigger, 12, 10);
      }
    });
    window.addEventListener("scroll", function () {
      if (behavior.isAnchored && activeTrigger && !panel.hidden) {
        previewUtils.positionAnchoredPanel(panel, activeTrigger, 12, 10);
      } else if (behavior.isDocked && activeHost && !panel.hidden) {
        positionDockedPanel(activeHost);
      }
      if (childActiveTrigger && !childPanel.hidden) {
        previewUtils.positionAnchoredPanel(childPanel, childActiveTrigger, 12, 10);
      }
    }, true);

    previewUtils.registerPreviewHydrator("inline", refresh);

    refresh(document);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", bindInlinePreview);
  } else {
    bindInlinePreview();
  }
})();"##

def withBlueprintCssAssets (extras : List String := []) : List String :=
  [blueprintTokensCss] ++ extras

def withPreviewPanelCssAssets (extras : List String := []) : List String :=
  withBlueprintCssAssets ([previewPanelCss] ++ extras)

def withInlinePreviewCssAssets (extras : List String := []) : List String :=
  withBlueprintCssAssets (extras ++ [previewHeaderCss, inlinePreviewCss])

def withPreviewPanelInlinePreviewCssAssets (extras : List String := []) : List String :=
  withPreviewPanelCssAssets (extras ++ [previewHeaderCss, inlinePreviewCss])

def previewRuntimeJsAssets : List String :=
  [previewHoverUtilsJs]

def inlinePreviewJsAssets : List String :=
  previewRuntimeJsAssets ++ [inlineLinkPreviewJs]

def withPreviewRuntimeJsAssets (before : List String) (after : List String) : List String :=
  before ++ previewRuntimeJsAssets ++ after

def withInlinePreviewJsAssets (before : List String) (after : List String) : List String :=
  before ++ inlinePreviewJsAssets ++ after

end Informal.Commands
