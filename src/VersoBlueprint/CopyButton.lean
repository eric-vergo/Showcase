/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean

/-!
Copy-to-clipboard button for Lean code blocks.

This is a vendored, dependency-free enhancement modelled on the literate-HTML
reference `verso/static-web/literate/copy-button.js`. It targets the Lean *source*
code blocks rendered by `Highlighted.blockHtml` (`<code class="hl lean block">`) and
deliberately skips `.lean-output` blocks (compiler messages / `#eval` output).

Delivery: both `css` and `js` ride the global blueprint HTML assets
(`blueprintHtmlAssets`), the same `extraJs`/`extraCss` channel used by the dark-mode
applier, so the button appears on every page with zero per-block wiring.

Offline: no CDN / network dependency. Clipboard writes use `navigator.clipboard`
with a `document.execCommand("copy")` fallback for older browsers.

Theming: the button styling uses the `--bp-color-*` / `--bp-radius-*` design tokens
(with light literal fallbacks), so it follows the dark-mode color scheme
automatically.
-/

namespace Informal.CopyButton

/--
Styling for the copy button.

The button is positioned over the top-right corner of each Lean code block via a
runtime-inserted `.bp-copy-wrap` (`position: relative`) wrapper. Colors come from the
blueprint design tokens so the control themes correctly in dark mode; literal
fallbacks keep it legible if the tokens are ever absent.
-/
def css : String := r##"
.bp-copy-wrap {
  position: relative;
}

.bp-copy-button {
  position: absolute;
  top: 0.35rem;
  right: 0.5rem;
  z-index: 3;
  padding: 0.1rem 0.5rem;
  font-size: 0.78rem;
  line-height: 1.5;
  font-family: inherit;
  color: var(--bp-color-text-muted, #475569);
  background: var(--bp-color-surface, #ffffff);
  border: 1px solid var(--bp-color-border, #cbd5e1);
  border-radius: var(--bp-radius-sm, 0.3rem);
  box-shadow: var(--bp-shadow-sm, 0 4px 14px rgba(15, 23, 42, 0.1));
  cursor: pointer;
  opacity: 0;
  transition: opacity 0.12s ease-in-out, color 0.12s, border-color 0.12s;
}

.bp-copy-wrap:hover .bp-copy-button,
.bp-copy-wrap:focus-within .bp-copy-button,
.bp-copy-button:focus-visible {
  opacity: 1;
}

.bp-copy-button:hover {
  color: var(--bp-color-text, #111827);
  border-color: var(--bp-color-accent-info, #6a4fba);
}

.bp-copy-button.bp-copied {
  opacity: 1;
  color: var(--bp-color-accent-success, #15803d);
  border-color: var(--bp-color-accent-success, #15803d);
}

/* Permalink ("Copy link") button used in the node-page header. Always visible
   (no hover-reveal), themed with the same design tokens as the copy button. */
.bp-permalink-button {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  padding: 0.15rem 0.6rem;
  font-size: 0.85rem;
  line-height: 1.5;
  font-family: inherit;
  color: var(--bp-color-text, #15212b);
  background: var(--bp-color-surface-muted, #f1f4f7);
  border: 1px solid var(--bp-color-border, #dbe2ea);
  border-radius: var(--bp-radius-pill, 999px);
  cursor: pointer;
  transition: color 0.12s, border-color 0.12s;
}

.bp-permalink-button:hover {
  border-color: var(--bp-color-accent, #1c5fb8);
}

.bp-permalink-button.bp-copied {
  color: var(--bp-color-accent-success, #15803d);
  border-color: var(--bp-color-accent-success, #15803d);
}
"##

/--
The copy-button installer (dependency-free IIFE).

Targets `code.hl.lean.block` (the Lean *source* blocks) and skips anything that is,
or is inside, a `.lean-output` block. Each targeted block is wrapped in a
`.bp-copy-wrap` container so the absolutely-positioned button hovers over it. The
copied text is the block's text content with any (defensively) nested `.lean-output`
removed and trailing whitespace trimmed.
-/
def js : String := r##"(function () {
  "use strict";

  function collectCodeText(block) {
    if (!block.querySelector(".lean-output")) {
      return (block.textContent || "").replace(/\s+$/, "");
    }
    var clone = block.cloneNode(true);
    var outputs = clone.querySelectorAll(".lean-output");
    for (var i = 0; i < outputs.length; i++) {
      outputs[i].parentNode.removeChild(outputs[i]);
    }
    return (clone.textContent || "").replace(/\s+$/, "");
  }

  function showCopied(button) {
    var original = button.dataset.bpLabel || "Copy";
    button.textContent = "Copied!";
    button.classList.add("bp-copied");
    setTimeout(function () {
      button.textContent = original;
      button.classList.remove("bp-copied");
    }, 2000);
  }

  function copyText(text, button) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () {
        showCopied(button);
      }).catch(function () {
        // clipboard write failed (e.g. permissions denied)
      });
    } else {
      var textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      try {
        document.execCommand("copy");
        showCopied(button);
      } catch (err) {
        // silently fail
      }
      document.body.removeChild(textarea);
    }
  }

  function addCopyButtons() {
    // Lean *source* blocks: `code.hl.lean.block` (Highlighted.blockHtml) plus the
    // `pre.hl.lean` form (e.g. external-decl signatures). Compiler output is either
    // `pre.hl.lean.lean-output` or a `pre.hl.lean` inside `details.lean-output`; both
    // are excluded by the `.lean-output` guards below.
    var blocks = document.querySelectorAll("code.hl.lean.block, pre.hl.lean");
    for (var i = 0; i < blocks.length; i++) {
      var block = blocks[i];
      if (!(block instanceof HTMLElement)) continue;
      // Source blocks only: never decorate compiler-output blocks.
      if (block.classList.contains("lean-output")) continue;
      if (block.closest(".lean-output")) continue;
      if (block.dataset.bpCopyButton === "1") continue;
      block.dataset.bpCopyButton = "1";

      var wrap;
      if (block.parentElement && block.parentElement.classList.contains("bp-copy-wrap")) {
        wrap = block.parentElement;
      } else {
        wrap = document.createElement("div");
        wrap.className = "bp-copy-wrap";
        block.parentNode.insertBefore(wrap, block);
        wrap.appendChild(block);
      }

      var button = document.createElement("button");
      button.type = "button";
      button.className = "bp-copy-button";
      button.textContent = "Copy";
      button.setAttribute("aria-label", "Copy Lean code to clipboard");
      button.addEventListener("click", (function (codeBlock) {
        return function () {
          copyText(collectCodeText(codeBlock), this);
        };
      })(block));
      wrap.appendChild(button);
    }
  }

  // Permalink ("Copy link") buttons: any element carrying `data-bp-permalink`
  // copies its value (or the current location.href when empty) to the clipboard.
  function addPermalinkButtons() {
    var buttons = document.querySelectorAll("[data-bp-permalink]");
    for (var i = 0; i < buttons.length; i++) {
      var button = buttons[i];
      if (!(button instanceof HTMLElement)) continue;
      if (button.dataset.bpPermalinkWired === "1") continue;
      button.dataset.bpPermalinkWired = "1";
      button.addEventListener("click", (function (el) {
        return function () {
          var target = el.getAttribute("data-bp-permalink");
          if (!target) {
            target = window.location.href;
          }
          copyText(target, this);
        };
      })(button));
    }
  }

  function init() {
    addCopyButtons();
    addPermalinkButtons();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();"##

end Informal.CopyButton
