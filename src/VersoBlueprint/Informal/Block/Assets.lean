/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Emilio J. Gallego Arias, Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.ProofReveal
import VersoBlueprint.NodeCard

namespace Informal.Block.Assets

def css : String := r##"
.bp_wrapper {
  scroll-margin-top: 1rem;
  margin: 0.75rem 0;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-sm);
  padding: 0.5rem 0.5rem 0.5rem;
  background: var(--bp-color-surface);
}

/* Leave scroll room for relation panels opened near the end of a page. */
.content-wrapper > section:has(.bp_relation_panel) {
  padding-bottom: min(18rem, 42vh);
}

.bp_heading {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-wrap: wrap;
  font-style: normal;
  font-weight: bold;
  border-bottom: 1px solid var(--bp-color-border-soft);
  padding-bottom: 0.25rem;
}

.bp_heading_title_row {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
}

.bp_kind_proof_heading {
  align-items: baseline;
}

/* Compact caption/label/dot run ("Theorem 8.1 ●"): word-sized gaps, no fixed
   tracks — the old grid reserved an 11ch caption column that opened a large gap
   after short captions like "Lemma". */
.bp_heading_title_row_statement {
  display: inline-flex;
  align-items: baseline;
  column-gap: 0.35em;
}

.bp_caption {
  display: inline;
}

.bp_label {
  margin-left: 0.5rem;
}

.bp_heading_title_row_statement .bp_label {
  margin-left: 0;
  font-variant-numeric: tabular-nums;
}

/* Header status dot (1D): a small token-colored disc after the block title
   ("Theorem 4.2.9 ●"). `data-status` values mirror the declaration registry's
   status tags plus "informal" for nodes with no associated Lean; every color is
   an existing `--bp-color-*` token (all four scheme blocks), so light + dark
   come for free. Emitted by `CodeSummary.statusDotHtml`. */
.bp_status_dot {
  display: inline-block;
  flex: 0 0 auto;
  align-self: center;
  width: 0.55em;
  height: 0.55em;
  /* The title row's own column-gap spaces the dot ("Theorem 8.1 ●"). */
  border-radius: 50%;
  background: var(--bp-color-text-faint);
}

.bp_status_dot[data-status="proved"] {
  background: var(--bp-color-accent-success);
}

.bp_status_dot[data-status="containsSorry"] {
  background: var(--bp-color-accent-warning);
}

.bp_status_dot[data-status="axiomLike"] {
  background: var(--bp-color-accent-info);
}

.bp_status_dot[data-status="missing"] {
  background: var(--bp-color-accent-danger);
}

.bp_status_dot[data-status="informal"] {
  background: var(--bp-color-text-faint);
}

.bp_metadata_panel {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem 0.5rem;
  align-items: center;
  margin: 0.5rem 0 0.75rem;
  padding: 0.5rem 0.5rem;
  border: 1px solid var(--bp-color-border-panel);
  border-radius: var(--bp-radius-xl);
  background: var(--bp-color-surface-muted);
  font-size: var(--bp-fs-caption, 0.78rem);
  font-style: normal;
  font-weight: 400;
}

.bp_metadata_item {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  min-width: 0;
  flex-wrap: wrap;
}

.bp_metadata_owner {
  gap: 0.5rem;
}

.bp_metadata_key {
  font-weight: 700;
  color: var(--bp-color-text-subtle);
}

.bp_metadata_value {
  color: var(--bp-color-text-strong);
}

.bp_metadata_tags {
  display: inline-flex;
  flex-wrap: wrap;
  gap: 0.25rem;
}

.bp_metadata_tag {
  display: inline-flex;
  align-items: center;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-pill);
  background: var(--bp-color-surface);
  color: var(--bp-color-text-muted);
  padding: 0.06rem 0.5rem;
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 600;
}

.bp_metadata_link {
  color: inherit;
  text-decoration: none;
  font-weight: 600;
}

.bp_metadata_link:hover {
  text-decoration: underline;
}

.bp_code_link {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  font-size: var(--bp-fs-control, 0.82rem);
  color: inherit;
  text-decoration: none;
}

.bp_code_link_label {
  display: inline-flex;
  align-items: center;
}

.bp_code_status_symbol {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 0.9rem;
  font-size: var(--bp-fs-caption, 0.78rem);
  font-weight: 700;
  line-height: 1;
}

.bp_code_link_status_proved .bp_code_status_symbol {
  color: inherit;
}

.bp_code_link_status_warning .bp_code_status_symbol {
  color: var(--bp-color-accent-warning);
}

.bp_code_link_status_missing .bp_code_status_symbol,
.bp_code_link_status_axiom .bp_code_status_symbol {
  color: var(--bp-color-accent-danger);
}

.bp_code_link_status_absent .bp_code_status_symbol {
  color: inherit;
}

.bp_render_warning_badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 1rem;
  height: 1rem;
  border-radius: 999px;
  padding: 0 0.25rem;
  background: rgba(185, 28, 28, 0.08);
  color: var(--bp-color-status-error-text);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 800;
  line-height: 1;
  border: 1px solid rgba(185, 28, 28, 0.18);
}

.bp_code_render_warning_badge {
  margin-right: 0.25rem;
}

.bp_code_summary_preview_root {
  position: relative;
  display: inline-flex;
  align-items: center;
  min-width: 0;
}

.bp_code_summary_preview_wrap {
  display: inline-flex;
  align-items: center;
  min-width: 0;
}

.bp_code_summary_preview_wrap_active {
  border-radius: var(--bp-radius-sm);
  cursor: pointer;
}

.bp_code_summary_preview_wrap_active[tabindex="0"] {
  outline: none;
}

.bp_code_summary_preview_wrap_active:focus-visible {
  background: var(--bp-color-focus-surface);
  box-shadow: 0 0 0 0.16rem var(--bp-color-focus-ring);
}

.bp_code_summary_preview_panel {
  position: fixed;
  z-index: 36;
  width: min(32rem, calc(100vw - 1.25rem));
  max-height: min(24rem, 78vh);
  overflow: hidden;
}

.bp_code_summary_preview_panel[data-bp-preview-placement="docked"] {
  top: 0.9rem;
  right: 0.9rem;
  left: auto;
}

.bp_code_summary_preview_header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  padding: 0.5rem 0.5rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  background: linear-gradient(180deg, var(--bp-color-surface-muted), var(--bp-color-surface));
}

.bp_code_summary_preview_title {
  min-width: 0;
  color: var(--bp-color-text-strong);
  font-size: var(--bp-fs-control, 0.82rem);
  font-weight: 700;
  line-height: 1.35;
  white-space: normal;
  overflow-wrap: anywhere;
}

.bp_code_summary_preview_body {
  padding: 0.5rem 0.5rem 0.5rem;
  max-height: min(20rem, 68vh);
  overflow: auto;
}

.bp_code_summary_preview_content {
  display: grid;
  gap: 0.5rem;
}

.bp_code_summary_preview_panel .bp_code_hover_section {
  margin-top: 0;
}

.bp_code_summary_preview_panel .bp_code_hover_section + .bp_code_hover_section {
  margin-top: 0;
  padding-top: 0.5rem;
  border-top: 1px solid var(--bp-color-border-soft);
}

.bp_code_summary_preview_panel .bp_code_hover_label {
  display: inline-flex;
  align-items: center;
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--bp-color-text-faint);
}

.bp_code_summary_preview_panel .bp_code_hover_list {
  list-style: none;
}

.bp_code_decl_item {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: start;
  gap: 0.25rem 0.5rem;
}

.bp_code_decl_item + .bp_code_decl_item {
  margin-top: 0.25rem;
  padding-top: 0.25rem;
  border-top: 1px solid var(--bp-color-border-soft);
}

.bp_code_decl_name {
  min-width: 0;
  overflow-wrap: anywhere;
}

.bp_code_decl_name code {
  font-size: var(--bp-fs-caption, 0.78rem);
}

.bp_code_decl_status {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  white-space: nowrap;
  padding: 0.08rem 0.5rem;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-pill);
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-muted);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 700;
  line-height: 1.2;
}

.bp_code_decl_status_ok {
  border-color: rgba(22, 101, 52, 0.18);
  background: rgba(22, 101, 52, 0.08);
  color: var(--bp-color-status-success-text);
}

.bp_code_decl_status_warning,
.bp_code_decl_status_axiom {
  border-color: rgba(161, 98, 7, 0.2);
  background: rgba(161, 98, 7, 0.09);
  color: var(--bp-color-status-warning-text);
}

.bp_code_decl_status_missing {
  border-color: rgba(185, 28, 28, 0.18);
  background: rgba(185, 28, 28, 0.08);
  color: var(--bp-color-status-error-text);
}

.bp_code_hover {
  position: absolute;
  left: 50%;
  top: 100%;
  transform: translateX(-50%);
  min-width: 20rem;
  max-width: min(34rem, 75vw);
  z-index: 20;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-md);
  padding: 0.5rem 0.5rem;
  background: var(--bp-color-surface);
  box-shadow: 0 8px 20px rgba(15, 23, 42, 0.15);
  display: none;
  font-size: var(--bp-fs-caption, 0.78rem);
  font-style: normal;
  font-weight: 400;
}

.bp_code_hover_wrap:is(:hover, :focus-within) > .bp_code_hover,
.bp_code_link_wrap:is(:hover, :focus-within) > .bp_code_hover {
  display: block;
}

.bp_code_hover_title {
  font-weight: 700;
  margin-bottom: 0.25rem;
}

/* Code panels are bare (1E): no wrapper box, no visible "Lean code for …"
   header, no progress pill. The `<summary>` stays in the DOM (fold options and
   the proof-hider JS key off `details.bp_code_block`) but is visually hidden —
   accessible name + keyboard toggle only, via the standard sr-only recipe
   (never `display: none`, which would remove it from the a11y tree). */
.bp_code_block > summary.bp_code_summary_hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  margin: -1px;
  padding: 0;
  border: 0;
  overflow: hidden;
  clip: rect(0 0 0 0);
  white-space: nowrap;
  list-style: none;
}

.bp_code_block > summary.bp_code_summary_hidden::-webkit-details-marker {
  display: none;
}

.bp_code_panel {
  margin: 0;
}

.bp_code_panel_wrapper {
  margin-top: 0.5rem;
}

.bp_decl_target {
  background: var(--bp-color-selection);
  border-radius: 0.18rem;
  box-shadow: 0 0 0 0.12rem var(--bp-color-selection-ring);
  animation: bp-decl-target-pulse 1.8s ease-out;
}

.bp_decl_target_block {
  border-radius: 0.3rem;
  box-shadow: 0 0 0 0.18rem var(--bp-color-selection-ring);
  background: linear-gradient(180deg, var(--bp-color-selection-surface-soft), rgba(59, 130, 246, 0.04));
  animation: bp-decl-block-pulse 2.2s ease-out;
}

@keyframes bp-decl-target-pulse {
  0% {
    background: var(--bp-color-selection-surface-strong);
    box-shadow: 0 0 0 0.2rem var(--bp-color-selection-shadow-strong);
  }
  100% {
    background: var(--bp-color-selection-surface-faint);
    box-shadow: 0 0 0 0.08rem var(--bp-color-selection-shadow-faint);
  }
}

@keyframes bp-decl-block-pulse {
  0% {
    background: var(--bp-color-selection-surface-soft);
    box-shadow: 0 0 0 0.28rem var(--bp-color-selection-shadow-soft);
  }
  100% {
    background: rgba(59, 130, 246, 0.04);
    box-shadow: 0 0 0 0.14rem var(--bp-color-selection-shadow-faint);
  }
}

.bp_code_link:hover {
  text-decoration: underline;
}

.bp_code_link_empty:hover {
  text-decoration: none;
}

.bp_relation_wrap {
  position: relative;
  display: inline-flex;
  align-items: center;
  padding-bottom: 0.5rem;
  margin-bottom: -0.5rem;
}

.bp_relation_wrap::after {
  content: "";
  position: absolute;
  left: -0.25rem;
  right: -0.25rem;
  top: 100%;
  height: 0.45rem;
}

.bp_relation_chip {
  display: inline-flex;
  align-items: center;
  appearance: none;
  border: 0;
  background: none;
  padding: 0;
  color: inherit;
  font: inherit;
  line-height: inherit;
  text-align: left;
  font-family: var(--font-mono-ui);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 600;
  color: var(--bp-color-text-muted);
  white-space: nowrap;
  cursor: default;
}

.bp_relation_chip_empty {
  color: var(--bp-color-text-faint);
  font-weight: 500;
}

.bp_relation_chip_warn {
  color: var(--bp-color-status-warning-text);
}

.bp_relation_panel {
  position: absolute;
  top: 100%;
  right: 0;
  min-width: 26rem;
  width: min(50rem, 92vw);
  z-index: 26;
  border: 1px solid var(--bp-color-border);
  border-radius: var(--bp-radius-xl);
  background: var(--bp-color-surface);
  box-shadow: var(--bp-shadow-lg);
  display: none;
  font-style: normal;
  font-weight: 400;
}

.bp_relation_wrap.bp_relation_wrap_open > .bp_relation_panel {
  display: block;
}

.bp_relation_panel_header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 0.5rem;
  padding: 0.5rem 0.75rem 0.5rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  background: linear-gradient(180deg, var(--bp-color-surface-muted), var(--bp-color-surface));
}

.bp_relation_panel_title {
  font-size: var(--bp-fs-control, 0.82rem);
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_relation_panel_meta {
  font-size: var(--bp-fs-badge, 0.72rem);
  color: var(--bp-color-text-faint);
}

.bp_relation_panel_body {
  display: grid;
  grid-template-columns: minmax(14rem, 18rem) minmax(18rem, 1fr);
  gap: 0.75rem;
  align-items: start;
  padding: 0.75rem;
}

.bp_relation_list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  max-height: min(20rem, 62vh);
  overflow: auto;
}

.bp_relation_item {
  border: 1px solid var(--bp-color-border-panel);
  border-radius: var(--bp-radius-md);
  background: var(--bp-color-surface-muted);
  transition: border-color 120ms ease, box-shadow 120ms ease, background 120ms ease;
}

.bp_relation_item:hover,
.bp_relation_item:focus-within,
.bp_relation_item.bp_relation_item_active {
  border-color: var(--bp-color-focus-border);
  background: var(--bp-color-focus-surface);
  box-shadow: inset 0 0 0 1px var(--bp-color-focus-ring);
}

.bp_relation_target {
  display: block;
  padding: 0.5rem 0.5rem;
  color: inherit;
  text-decoration: none;
}

.bp_relation_target:hover {
  text-decoration: none;
}

.bp_relation_target_title {
  display: block;
  font-size: var(--bp-fs-control, 0.82rem);
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_relation_target_meta {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  flex-wrap: wrap;
  margin-top: 0.25rem;
  color: var(--bp-color-text-subtle);
  font-size: var(--bp-fs-badge, 0.72rem);
}

.bp_relation_target_meta code {
  font-size: var(--bp-fs-badge, 0.72rem);
}

.bp_relation_axis_badge {
  --bp-relation-badge-bg: var(--bp-color-surface);
  --bp-relation-badge-border: var(--bp-color-border);
  --bp-relation-badge-text: var(--bp-color-text-muted);
  --bp-relation-badge-prefix: var(--bp-color-text-faint);
  display: inline-flex;
  align-items: center;
  border: 1px solid var(--bp-relation-badge-border);
  border-radius: var(--bp-radius-pill);
  background: var(--bp-relation-badge-bg);
  color: var(--bp-relation-badge-text);
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 700;
  letter-spacing: 0;
  line-height: 1.2;
  text-transform: none;
  padding: 0.1rem 0.25rem;
  box-shadow: inset 0 -1px 0 rgba(255, 255, 255, 0.35);
}

.bp_relation_badge_axis {
  font-weight: 700;
}

.bp_relation_badge_statement {
  --bp-relation-badge-bg: rgba(37, 99, 235, 0.1);
  --bp-relation-badge-border: rgba(37, 99, 235, 0.28);
  --bp-relation-badge-text: #1d4ed8;
}

.bp_relation_badge_proof {
  --bp-relation-badge-bg: rgba(5, 150, 105, 0.12);
  --bp-relation-badge-border: rgba(5, 150, 105, 0.28);
  --bp-relation-badge-text: #047857;
}

.bp_relation_badge_origin::before,
.bp_relation_badge_intent::before {
  color: var(--bp-relation-badge-prefix);
  font-weight: 600;
  margin-right: 0.25rem;
}

.bp_relation_badge_origin::before {
  content: "origin";
}

.bp_relation_badge_intent::before {
  content: "intent";
}

.bp_relation_badge_origin_automatic {
  --bp-relation-badge-bg: rgba(124, 58, 237, 0.1);
  --bp-relation-badge-border: rgba(124, 58, 237, 0.26);
  --bp-relation-badge-text: #6d28d9;
  --bp-relation-badge-prefix: #7c3aed;
}

.bp_relation_badge_intent_auxiliary {
  --bp-relation-badge-bg: rgba(245, 158, 11, 0.14);
  --bp-relation-badge-border: rgba(245, 158, 11, 0.32);
  --bp-relation-badge-text: #92400e;
  --bp-relation-badge-prefix: #b45309;
}

.bp_relation_badge_intent_technical {
  --bp-relation-badge-bg: rgba(79, 70, 229, 0.1);
  --bp-relation-badge-border: rgba(79, 70, 229, 0.26);
  --bp-relation-badge-text: #4338ca;
  --bp-relation-badge-prefix: #4f46e5;
}

.bp_relation_preview_surface {
  min-height: 14rem;
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-lg);
  background: var(--bp-color-surface-muted);
  overflow: hidden;
}

.bp_relation_preview_header {
  padding: 0.5rem 0.5rem 0.5rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  background: linear-gradient(180deg, var(--bp-color-surface-muted), var(--bp-color-surface));
}

.bp_relation_preview_label {
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--bp-color-text-faint);
}

.bp_relation_preview_title {
  margin-top: 0.25rem;
  font-size: var(--bp-fs-control, 0.82rem);
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

.bp_relation_preview_body {
  max-height: min(20rem, 62vh);
  overflow: auto;
  padding: 0.5rem 0.75rem 0.75rem;
  background: var(--bp-color-surface);
}

.bp_relation_preview_message {
  display: grid;
  gap: 0.25rem;
  padding: 0.5rem 0.5rem;
  border: 1px solid var(--bp-color-border-soft);
  border-radius: 0.45rem;
  background: var(--bp-color-surface-muted);
  color: var(--bp-color-text-muted);
  font-size: var(--bp-fs-caption, 0.78rem);
  line-height: 1.38;
}

.bp_relation_preview_message[data-bp-preview-message="loading"] {
  color: var(--bp-color-text-faint);
}

.bp_relation_preview_message[data-bp-preview-message="error"] {
  border-color: var(--bp-color-status-error-border-soft);
  background: var(--bp-color-surface-warn);
  color: var(--bp-color-status-error-text);
}

.bp_relation_preview_message_title {
  font-weight: 700;
  color: inherit;
}

.bp_relation_preview_message_detail {
  color: inherit;
}

@media (max-width: 900px) {
  .bp_relation_panel {
    right: auto;
    left: 0;
    width: min(34rem, calc(100vw - 1.4rem));
  }

  .bp_relation_panel_body {
    grid-template-columns: 1fr;
  }

  .bp_relation_list,
  .bp_relation_preview_body {
    max-height: min(12rem, 36vh);
  }
}

.bp_status_mark {
  font-size: var(--bp-fs-caption, 0.78rem);
  font-weight: 600;
}

.bp_external_status_badge {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  border-radius: 999px;
  border: 1px solid currentColor;
  padding: 0.25rem 0.5rem;
  font-size: var(--bp-fs-caption, 0.78rem);
  font-weight: 700;
  line-height: 1.2;
  white-space: nowrap;
}

.bp_external_decl_ok {
  color: var(--bp-color-status-success-text);
}

.bp_external_decl_sorry {
  color: var(--bp-color-status-warning-text);
}

.bp_external_decl_missing {
  color: var(--bp-color-status-error-text);
}

.bp_external_decl_error {
  color: #7c3aed;
}

.bp_external_status_badge.bp_external_decl_ok {
  background: rgba(22, 101, 52, 0.08);
  border-color: rgba(22, 101, 52, 0.18);
}

.bp_external_status_badge.bp_external_decl_sorry {
  background: rgba(161, 98, 7, 0.09);
  border-color: rgba(161, 98, 7, 0.2);
}

.bp_external_status_badge.bp_external_decl_missing {
  background: rgba(185, 28, 28, 0.08);
  border-color: rgba(185, 28, 28, 0.18);
}

.bp_external_status_badge.bp_external_decl_error {
  background: rgba(124, 58, 237, 0.08);
  border-color: rgba(124, 58, 237, 0.18);
}

.bp_external_decl_meta {
  margin-top: 0.25rem;
  color: #475569;
  font-size: var(--bp-fs-caption, 0.78rem);
  line-height: 1.45;
}

.bp_external_decl_rendered_meta {
  display: flex;
  align-items: center;
  gap: 0.25rem 0.75rem;
  flex-wrap: wrap;
}

.bp_external_decl_footer_status {
  padding: 0.1rem 0.5rem;
  font-size: var(--bp-fs-badge, 0.72rem);
  font-weight: 700;
}

.bp_external_decl_list {
  list-style: none;
  margin: 0.5rem 0 0;
  padding-left: 0;
}

.bp_external_decl_item {
  margin: 0;
  padding: 0;
}

.bp_external_decl_item_rendered {
  padding: 0 0 0.1rem;
}

.bp_external_decl_list > .bp_external_decl_item + .bp_external_decl_item {
  margin-top: 0.75rem;
}

.bp_external_decl_head {
  display: flex;
  align-items: baseline;
  gap: 0.25rem 0.75rem;
  flex-wrap: wrap;
  line-height: 1.5;
}

/* Bare card (1F): inside the two-column node card, the per-declaration head row
   (decl name + status pill) and any footer status pill are suppressed so the Lean
   code reads bare — the properties rail owns decl identity + status. Scoped to
   `.bp_card2` so hover previews and decl pages keep their rows. The inline chapter
   card already renders these empty via a render flag (`includeStatusRows`); this
   also covers the node-page / graph-modal / graft cards, whose formal cells come
   from pre-rendered preview fragments the flag can't reach. */
.bp_card2 .bp_external_decl_head,
.bp_card2 .bp_external_decl_footer_status {
  display: none;
}

.bp_external_decl_head_meta {
  color: #64748b;
  font-size: var(--bp-fs-caption, 0.78rem);
}

.bp_external_decl_rendered_source {
  margin-left: auto;
}

.bp_external_decl_details {
  margin-top: 0.12rem;
}

.bp_external_decl_details summary {
  cursor: pointer;
  font-size: var(--bp-fs-badge, 0.72rem);
  color: var(--bp-color-text-muted);
}

.bp_external_decl_preview {
  margin-top: 0.25rem;
  border-left: 2px solid var(--bp-color-border-soft);
  padding-left: 0.5rem;
}

.bp_external_decl_preview summary {
  cursor: pointer;
  font-size: var(--bp-fs-badge, 0.72rem);
  color: var(--bp-color-text-strong);
}

.bp_external_decl_preview pre {
  margin: 0.25rem 0 0;
  max-height: 8.5rem;
  overflow: auto;
  white-space: pre-wrap;
  font-size: var(--bp-fs-badge, 0.72rem);
  line-height: 1.35;
}

.bp_external_decl_stmt {
  margin: 0.25rem 0 0;
  padding: 0.1rem 0 0.1rem 0.75rem;
  border: 0;
  border-left: 0.18rem solid var(--bp-color-border-strong);
  border-radius: 0;
  background: transparent;
  white-space: pre-wrap;
  font-size: var(--bp-fs-control, 0.82rem);
  line-height: 1.5;
  color: var(--bp-color-text-strong);
}

.bp_external_decl_rendered {
  margin: 0.25rem 0 0;
  border: 0;
  border-radius: 0;
  background: transparent;
  box-shadow: none;
  padding: 0;
  overflow-x: visible;
}

/* Bare code (1E): the rendered declaration carries no box / kicker chrome —
   just the highlighted signature (and, for structures/inductives, the nested
   constructor/field sections). */
.bp_external_decl_rendered .declaration {
  margin: 0;
  padding: 0;
  min-width: 100%;
}

.bp_external_decl_rendered .bp_external_decl_signature {
  margin: 0;
  padding: 0.5rem 0.25rem;
  max-width: 100%;
  overflow-x: auto;
  background: transparent;
  border: 0;
  font-size: var(--bp-fs-control, 0.82rem);
  line-height: 1.45;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.bp_external_decl_rendered .bp_external_decl_signature.hl.lean,
.bp_external_decl_rendered .name-and-type.hl.lean {
  white-space: pre-wrap;
}

.bp_external_decl_rendered .bp_external_decl_signature .token,
.bp_external_decl_rendered .name-and-type .token {
  overflow-wrap: anywhere;
  word-break: break-word;
}

.bp_external_decl_rendered .bp_external_decl_body:empty {
  display: none;
}

.bp_external_decl_rendered .bp_external_decl_body:not(:empty) {
  margin-top: 0;
  padding: 0.5rem 0.25rem;
}

.bp_external_decl_rendered .bp_external_decl_body > :first-child {
  margin-top: 0;
}

.bp_external_decl_rendered .bp_external_decl_body > :last-child {
  margin-bottom: 0;
}

.bp_external_decl_rendered .bp_external_decl_section + .bp_external_decl_section {
  margin-top: 0.75rem;
}

.bp_external_decl_rendered .bp_external_decl_section_label {
  margin: 0 0 0.5rem;
  padding-bottom: 0.25rem;
  border-bottom: 1px solid var(--bp-color-border-soft);
  color: var(--bp-color-text-muted);
  font-size: var(--bp-fs-caption, 0.78rem);
  font-weight: 600;
  letter-spacing: 0;
  text-transform: none;
}

.bp_external_decl_rendered pre {
  overflow-x: auto;
}

.bp_external_decl_rendered .constructor + .constructor,
.bp_external_decl_rendered .subdocs + .subdocs {
  margin-top: 0.5rem;
}

.bp_external_decl_rendered .constructor,
.bp_external_decl_rendered .subdocs {
  padding: 0.25rem 0 0.25rem 0.25rem;
  border-left: 0.1rem solid var(--bp-color-border-soft);
}

.bp_external_decl_rendered .name-and-type {
  margin: 0;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  font-size: var(--bp-fs-control, 0.82rem);
  line-height: 1.45;
}

.bp_external_decl_rendered .docs {
  margin: 0.25rem 0 0 0.25rem;
  color: var(--bp-color-text-muted);
}

.bp_external_decl_rendered .inheritance {
  margin-top: 0.25rem;
  color: #64748b;
  font-size: var(--bp-fs-control, 0.82rem);
}

.bp_external_decl_rendered .inheritance ol {
  display: inline;
  margin: 0;
  padding: 0;
}

.bp_external_decl_rendered .inheritance li {
  display: inline;
  list-style: none;
}

.bp_external_decl_rendered .inheritance li + li::before {
  content: " > ";
}

.bp_external_decl_rendered .docstring {
  margin-top: 0;
  padding: 0;
  border: 0;
  background: transparent;
  color: inherit;
  font-family: var(--verso-text-font-family, inherit);
  font-size: 0.98em;
  line-height: 1.6;
  overflow: visible;
  max-height: none;
  max-width: none;
  width: auto;
}

.bp_external_decl_rendered pre.docstring {
  white-space: pre-wrap;
}

.bp_external_decl_rendered div.docstring {
  white-space: normal;
}

.bp_external_decl_rendered div.docstring > :first-child {
  margin-top: 0;
}

.bp_external_decl_rendered div.docstring > :last-child {
  margin-bottom: 0;
}

.bp_external_decl_rendered details {
  margin-top: 0.5rem;
}

.bp_external_decl_rendered details > summary {
  cursor: pointer;
  font-weight: 600;
}

.bp_external_decl_rendered details > ul {
  margin: 0.5rem 0 0;
  padding-left: 1rem;
}

.bp_external_decl_rendered details > ul > li {
  margin: 0.25rem 0;
  overflow-wrap: anywhere;
}

.bp_external_decl_rendered_source .bp_code_link {
  font-size: var(--bp-fs-caption, 0.78rem);
  white-space: nowrap;
}

@media (max-width: 700px) {
  .bp_external_decl_head_meta,
  .bp_external_decl_rendered_source {
    width: 100%;
    margin-left: 0;
  }

  .bp_external_decl_list > .bp_external_decl_item + .bp_external_decl_item {
    margin-top: 0.75rem;
  }
}

.bp_content {
  margin-top: 0.25rem;
  padding-left: 0.5rem;
}

.bp_content > :first-child {
  margin-top: 0;
}

.bp_content > :last-child {
  margin-bottom: 0;
}

.bp-proof-tail-hidden {
  display: none;
}

.bp-proof-gap-hidden {
  display: none;
}

.bp-proof-by-toggle {
  cursor: pointer;
  text-decoration: underline dotted;
  text-decoration-thickness: 1px;
}

.bp-proof-by-toggle::after {
  content: " ...";
  color: var(--bp-color-text-faint);
}

.bp-proof-by-toggle.bp-proof-open::after {
  content: "";
}

details.bp_kind_proof_wrapper > summary.bp_heading {
  cursor: pointer;
  border-radius: var(--bp-radius-sm);
  padding: 0.1rem 0.25rem;
  margin-left: -0.25rem;
  transition: background-color 0.14s ease, color 0.14s ease;
}

details.bp_kind_proof_wrapper > summary.bp_heading:hover {
  background: var(--bp-color-surface-subtle);
}

details.bp_kind_proof_wrapper > summary.bp_heading::marker {
  color: var(--bp-color-text-faint);
}

.bp-proof-by-toggle {
  transition: color 0.14s ease, text-decoration-color 0.14s ease;
}

.bp_wrapper.bp_style_plain .bp_heading,
div.theorem-style-plain div[class$="_thmheading"] {
  font-style: normal;
  font-weight: bold;
}

/* Informal STATEMENT prose for theorem-like blocks reads italic serif (LaTeX
   convention; matches the mockup). Scoped by the kind-specific content classes
   so it also applies inside the two-column cards, whose cells carry the content
   classes without the `.bp_wrapper` shell; definitions and informal proof prose
   stay upright. */
.bp_kind_theorem_content, div.theorem_thmcontent,
.bp_kind_proposition_content, div.proposition_thmcontent,
.bp_kind_lemma_content, div.lemma_thmcontent,
.bp_kind_corollary_content, div.corollary_thmcontent {
  font-style: italic;
  font-weight: normal;
}

.bp_wrapper.bp_style_definition .bp_heading,
div.theorem-style-definition div[class$="_thmheading"] {
  font-style: normal;
  font-weight: bold;
}

/* Informal statement / proof prose: a quiet indent (1D — the colored left rule
   is gone; the italic serif body carries the register on its own). */
.bp_kind_theorem_content,
div.theorem_thmcontent,
.bp_kind_proposition_content,
div.proposition_thmcontent,
.bp_kind_lemma_content,
div.lemma_thmcontent,
.bp_kind_corollary_content,
div.corollary_thmcontent,
.bp_kind_proof_content,
div.proof_content {
  padding-left: var(--bp-space-4);
}

.bp_wrapper:target {
  animation: bp-target-pulse 1.6s ease-out;
  box-shadow: 0 0 0 0.18rem var(--bp-color-target-ring);
  border-radius: 0.35rem;
}

@keyframes bp-target-pulse {
  0% {
    background-color: var(--bp-color-target-surface);
    box-shadow: 0 0 0 0.28rem var(--bp-color-target-ring-strong);
  }
  100% {
    background-color: transparent;
    box-shadow: 0 0 0 0.18rem var(--bp-color-target-ring);
  }
}

/* ---- Typography roles ---------------------------------------------------- */

/* Informal mathematical prose: serif body for the statement/proof content so it
   harmonizes with inline KaTeX. Scoped to the math content only (not nav, ToC,
   UI labels, headings, code or identifiers). */
.bp_content p,
.bp_content li,
.bp_content dd,
.bp_content dt,
.bp_content blockquote {
  font-family: var(--font-prose);
  line-height: 1.6;
}

/* Cap the reading measure for the serif body (~68ch) so multi-line prose wraps
   at a comfortable width. Statements/proofs read tighter than the full content
   column; cards, code blocks, tables, the dashboard and display math keep the
   full width — display-math paragraphs are explicitly opted back out. */
.bp_content p,
.bp_content li,
.bp_content dd,
.bp_content dt,
.bp_content blockquote {
  max-width: 42rem;
}

.bp_content p:has(.bp_math.display),
.bp_content li:has(.bp_math.display),
.bp_content dd:has(.bp_math.display) {
  max-width: none;
}

/* "Apparatus": the kind caption ("Definition") and number label render as a
   title-case bold heading ("Theorem 4.2.9"). Identifiers/math in the content
   are untouched. */
.bp_caption,
.bp_label,
span[class$="_thmcaption"],
span[class$="_thmlabel"] {
  font-size: 1em;
  font-weight: 700;
  color: var(--bp-color-text-strong);
}

/* Links inside informal prose: blueprint-blue with a subtle underline. */
.bp_content a:not([class]) {
  color: var(--bp-color-link);
  text-decoration-thickness: 1px;
  text-underline-offset: 0.14em;
  text-decoration-color: color-mix(in srgb, var(--bp-color-link) 45%, transparent);
  transition: color 0.14s ease, text-decoration-color 0.14s ease;
}

.bp_content a:not([class]):hover {
  text-decoration-color: currentColor;
}
"##

def codeAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  Informal.Commands.blueprintCssAssetBundle [css, Verso.Genre.Manual.docstringStyle]

def blockAssetBundle : Informal.Commands.BlueprintAssetBundle :=
  Informal.Commands.previewPanelInlinePreviewAssetBundle
    (cssExtras :=
      [css, Informal.NodeCard.css,
        Verso.Genre.Manual.docstringStyle])
    (jsAfter := [Informal.ProofReveal.jsInteractive])

def codeCssAssets : List String :=
  codeAssetBundle.css

def blockCssAssets : List String :=
  blockAssetBundle.css

def blockJsAssets : List String :=
  blockAssetBundle.js

end Informal.Block.Assets
