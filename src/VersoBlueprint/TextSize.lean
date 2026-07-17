/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean

/-!
Text-size applier (the persistence/pre-paint half of the reader text-size
control).

Mirrors `ColorScheme.lean`. The actual scaling lives in the stylesheets:
`Commands/Common.lean` (`blueprintTokensCss`) defines
`:root[data-bp-text-size="small"|"large"] { font-size: … }`, which scales the
whole rem-based layout.

This module supplies `applierJs` — a synchronous IIFE that reads the saved size
from `localStorage` and sets `data-bp-text-size` on `<html>` **before first
paint** (no flash of the wrong size), then publishes
`window.VersoBlueprint.textSize = { get, set }` and fires a `bp-text-size-change`
event on every apply. The visible control lives in the metadata rail's pinned
footer (`Commands/metadata-rail.mjs`), which drives exactly this API.

The axis is `data-bp-text-size ∈ {medium (attribute absent), small, large}`.
-/

namespace Informal.TextSize

/-- localStorage key the saved text-size choice is persisted under. -/
def storageKey : String := "verso-blueprint-text-size"

/-- The attribute placed on `<html>` for an explicit (non-medium) size. -/
def attrName : String := "data-bp-text-size"

/--
The synchronous pre-paint applier + page-global text-size API.

MUST be delivered as an inline non-module `<script>` in `<head>` (via the global
blueprint `extraJs` channel) so it runs before first paint. Do NOT move it into a
deferred module, which would reintroduce a flash of the wrong size.
-/
def applierJs : String := r##"(function () {
  var storageKey = "verso-blueprint-text-size";
  var attrName = "data-bp-text-size";
  var root = document.documentElement;

  function normalizeSize(size) {
    if (size === "small" || size === "large") return size;
    return "medium";
  }

  function applySize(size) {
    var s = normalizeSize(size);
    if (s === "medium") {
      root.removeAttribute(attrName);
    } else {
      root.setAttribute(attrName, s);
    }
    try {
      window.dispatchEvent(new CustomEvent("bp-text-size-change", { detail: { size: s } }));
    } catch (_err) {}
  }

  function getSavedSize() {
    try {
      return normalizeSize(localStorage.getItem(storageKey));
    } catch (_err) {
      return "medium";
    }
  }

  function saveSize(size) {
    try {
      localStorage.setItem(storageKey, normalizeSize(size));
    } catch (_err) {}
  }

  // Pre-paint: apply the saved size synchronously (inline in <head>), so there is
  // no flash. "medium" leaves the attribute absent (book.css's default size).
  applySize(getSavedSize());

  // Page-global API so the metadata-rail footer reuses exactly this
  // normalize/apply/save logic (mirrors window.VersoBlueprint.colorScheme).
  try {
    var ns = window.VersoBlueprint || (window.VersoBlueprint = {});
    ns.textSize = {
      get: getSavedSize,
      set: function (size) {
        var s = normalizeSize(size);
        applySize(s);
        saveSize(s);
      }
    };
  } catch (_err) {}
})();"##

end Informal.TextSize
