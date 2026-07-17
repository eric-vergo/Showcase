/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean

/-!
Dark-mode color-scheme applier.

This is the persistence/pre-paint half of the dark-mode feature. The actual
color values live in the stylesheets:

* core tokens + layout vars: `verso/static-web/verso-vars.css` and
  `verso-manual/.../Html/Style.lean` (`pageStyle` → `book.css`);
* blueprint tokens: `Commands/Common.lean` (`blueprintTokensCss`).

This module supplies `applierJs` — a tiny synchronous IIFE that reads the saved
scheme from `localStorage` and sets `data-bp-color-scheme` on `<html>` **before
first paint** (so there is no flash of the wrong theme), then publishes a
page-global `window.VersoBlueprint.colorScheme = { get, set }` API. The visible
theme control lives in the metadata rail's pinned footer
(`Commands/metadata-rail.mjs`), which drives exactly this API instead of
duplicating the storage/apply logic.

The color-scheme axis is `data-bp-color-scheme ∈ {auto (attribute absent),
light, dark}`; `auto` follows the OS via the `@media (prefers-color-scheme)`
rules with zero JS.
-/

namespace Informal.ColorScheme

/-- localStorage key the saved color-scheme choice is persisted under. -/
def storageKey : String := "verso-blueprint-color-scheme"

/-- The attribute placed on `<html>` for an explicit (non-auto) scheme. -/
def attrName : String := "data-bp-color-scheme"

/--
The synchronous pre-paint applier + page-global scheme API.

MUST be delivered as an inline non-module `<script>` in `<head>` (i.e. via the
global blueprint `extraJs` channel) so that `applyScheme` runs before first paint.
Do NOT move this into a deferred module (`blueprint-page-runtime.mjs`), which would
reintroduce a flash of the wrong theme.
-/
def applierJs : String := r##"(function () {
  var schemeStorageKey = "verso-blueprint-color-scheme";
  var attrName = "data-bp-color-scheme";
  var root = document.documentElement;

  function normalizeScheme(scheme) {
    if (scheme === "light" || scheme === "dark") return scheme;
    return "auto";
  }

  function applyScheme(scheme) {
    var s = normalizeScheme(scheme);
    if (s === "auto") {
      root.removeAttribute(attrName);
    } else {
      root.setAttribute(attrName, s);
    }
    // Notify theme-aware widgets (e.g. the dashboard d3 charts, which read the
    // `--bp-color-*` tokens via getComputedStyle) so they can redraw with the new
    // palette. Fired on every apply, including the synchronous pre-paint call.
    try {
      window.dispatchEvent(new CustomEvent("bp-color-scheme-change", { detail: { scheme: s } }));
    } catch (_err) {}
  }

  function getSavedScheme() {
    try {
      return normalizeScheme(localStorage.getItem(schemeStorageKey));
    } catch (_err) {
      return "auto";
    }
  }

  function saveScheme(scheme) {
    try {
      localStorage.setItem(schemeStorageKey, normalizeScheme(scheme));
    } catch (_err) {}
  }

  // Pre-paint: apply the saved scheme synchronously (this script is inline in
  // <head>), so there is no flash. "auto" leaves the attribute absent, letting the
  // @media (prefers-color-scheme: dark) rules follow the OS with zero JS.
  applyScheme(getSavedScheme());

  // Page-global API so theme UI (the metadata-rail footer) reuses exactly this
  // normalize/apply/save logic — mirrors the selection-bus
  // `window.VersoBlueprint.*` precedent.
  try {
    var ns = window.VersoBlueprint || (window.VersoBlueprint = {});
    ns.colorScheme = {
      get: getSavedScheme,
      set: function (scheme) {
        var s = normalizeScheme(scheme);
        applyScheme(s);
        saveScheme(s);
      }
    };
  } catch (_err) {}
})();"##

end Informal.ColorScheme
