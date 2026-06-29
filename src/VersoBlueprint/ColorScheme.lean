/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean

/-!
Dark-mode color-scheme switcher.

This is the toggle/persistence/pre-paint half of the dark-mode feature. The actual
color values live in the stylesheets:

* core tokens + layout vars: `verso/static-web/verso-vars.css` and
  `verso-manual/.../Html/Style.lean` (`pageStyle` → `book.css`);
* blueprint tokens: `Commands/Common.lean` (`blueprintTokensCss`).

This module supplies:

* `applierJs` — a tiny synchronous IIFE that reads the saved scheme from
  `localStorage` and sets `data-bp-color-scheme` on `<html>` **before first paint**
  (so there is no flash of the wrong theme), then installs the "Theme" control.
* `css` — styling for the standalone control box used on pages that do not carry
  the existing `#bp-style-switcher` (index / ToC / bibliography). On content pages
  the control is merged into `#bp-style-switcher` instead.

The color-scheme axis (`data-bp-color-scheme ∈ {auto(absent), light, dark}`) is
**orthogonal** to the existing `data-bp-style` (blueprint/modern/bold) axis.
-/

namespace Informal.ColorScheme

/-- localStorage key the saved color-scheme choice is persisted under. -/
def storageKey : String := "verso-blueprint-color-scheme"

/-- The attribute placed on `<html>` for an explicit (non-auto) scheme. -/
def attrName : String := "data-bp-color-scheme"

/--
CSS for the standalone color-scheme control box.

On content pages the "Theme" control is appended into the existing
`#bp-style-switcher` (which already carries its own styling); this block only
styles the standalone `#bp-color-scheme-switcher` box created on pages without the
style switcher. It reuses the `--bp-color-*` tokens (globally available because the
blueprint token CSS is registered in the global blueprint HTML assets), with light
fallbacks so it renders even if those tokens are absent.
-/
def css : String := r##"
#bp-color-scheme-switcher {
  position: fixed;
  right: 1rem;
  bottom: 1rem;
  z-index: 1000;
  display: flex;
  align-items: center;
  gap: 0.4rem 0.6rem;
  flex-wrap: wrap;
  background: var(--bp-color-surface, #ffffff);
  border: 1px solid var(--bp-color-border, #cbd5e1);
  border-radius: var(--bp-radius-md, 0.45rem);
  box-shadow: var(--bp-shadow-sm, 0 4px 14px rgba(15, 23, 42, 0.1));
  padding: 0.4rem 0.55rem;
  font-size: 0.82rem;
  color: var(--bp-color-text, #111827);
}

#bp-color-scheme-switcher .bp-style-switcher-control {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
}

#bp-color-scheme-switcher label {
  font-weight: 600;
}

#bp-color-scheme-switcher select {
  border: 1px solid var(--bp-color-border, #cbd5e1);
  border-radius: 0.3rem;
  background: var(--bp-color-surface, #ffffff);
  color: var(--bp-color-text, #111827);
  font-size: 0.82rem;
  padding: 0.1rem 0.25rem;
}
"##

/--
The synchronous pre-paint applier + control installer.

MUST be delivered as an inline non-module `<script>` in `<head>` (i.e. via the
global blueprint `extraJs` channel) so that `applyScheme` runs before first paint.
Do NOT move this into a deferred module (`blueprint-page-runtime.mjs`), which would
reintroduce a flash of the wrong theme.
-/
def applierJs : String := r##"(function () {
  var schemeStorageKey = "verso-blueprint-color-scheme";
  var attrName = "data-bp-color-scheme";
  var switcherId = "bp-color-scheme-switcher";
  var selectId = "bp-color-scheme-select";
  var styleSwitcherId = "bp-style-switcher";
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

  function installSchemeControl() {
    if (document.getElementById(selectId)) return;
    if (!document.body) return;

    // Merge into the style switcher box when it exists (content pages); otherwise
    // create a standalone control box (index / ToC / bibliography).
    var host = document.getElementById(styleSwitcherId);
    var ownHost = false;
    if (!host) {
      host = document.createElement("div");
      host.id = switcherId;
      ownHost = true;
    }

    var control = document.createElement("div");
    control.className = "bp-style-switcher-control";

    var label = document.createElement("label");
    label.setAttribute("for", selectId);
    label.textContent = "Theme";

    var select = document.createElement("select");
    select.id = selectId;
    ["auto", "light", "dark"].forEach(function (value) {
      var option = document.createElement("option");
      option.value = value;
      option.textContent = value;
      select.appendChild(option);
    });

    control.appendChild(label);
    control.appendChild(select);
    host.appendChild(control);
    if (ownHost) document.body.appendChild(host);

    select.value = getSavedScheme();
    select.addEventListener("change", function () {
      var value = normalizeScheme(select.value);
      applyScheme(value);
      saveScheme(value);
    });
  }

  function scheduleInstall() {
    // Defer past other DOMContentLoaded handlers (e.g. the style switcher's) so we
    // can merge our control into the shared #bp-style-switcher box when it exists.
    setTimeout(installSchemeControl, 0);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", scheduleInstall);
  } else {
    scheduleInstall();
  }
})();"##

end Informal.ColorScheme
