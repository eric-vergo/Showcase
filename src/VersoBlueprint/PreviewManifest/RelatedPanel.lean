/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.Lib.HoverRender
import VersoBlueprint.PreviewManifest

namespace Informal.PreviewManifest

open Lean
open Verso.Output
open Verso.Output.Html

def RelatedEntry.displayLabel (entry : RelatedEntry) : String :=
  let label := entry.label.toString
  if label.isEmpty then entry.previewKey else label

def RelatedEntry.displayTitle (entry : RelatedEntry) : String :=
  let title := entry.title.trimAscii.toString
  if title.isEmpty then entry.displayLabel else title

def RelationAxis.badgeHtml (axis : RelationAxis) : Html :=
  {{<span class="bp_relation_axis_badge">{{Html.ofString axis.display}}</span>}}

def RelatedEntry.metaHtml (entry : RelatedEntry) : Html :=
  .seq <| #[
    {{<code>{{Html.ofString entry.displayLabel}}</code>}}
  ] ++ entry.axes.map RelationAxis.badgeHtml

def RelatedEntry.panelEntry
    (entry : RelatedEntry)
    (currentLabel : Name)
    (idPrefix : String) : Informal.RelatedPanel.PanelEntry :=
  {
    previewId := Informal.HoverRender.previewId idPrefix entry.displayLabel
    previewKey := entry.previewKey
    previewTitle := entry.displayTitle
    href := entry.href
    metaHtml := entry.metaHtml
    previewFallbackLabel? := some entry.displayLabel
    active := entry.label == currentLabel
  }

def relatedPanelEntries
    (entries : Array RelatedEntry)
    (currentLabel : Name)
    (idPrefix : String) : Array Informal.RelatedPanel.PanelEntry :=
  entries.map fun entry => entry.panelEntry currentLabel idPrefix

end Informal.PreviewManifest
