// Command palette: a Ctrl/Cmd-K fuzzy "jump to node" overlay.
//
// Offline & self-contained: the only network access is a single same-origin
// `fetch("xref.json")` (resolved against the page `<base href>`), lazily on the
// first open. The fuzzy matcher is hand-rolled (subsequence scorer with
// contiguity / word-boundary bonuses) — no external dependency, no CDN.
//
// The overlay DOM is created on demand and themed entirely with the
// `--bp-color-*` design tokens (see `Commands/CommandPalette.lean`), so it works
// in dark mode. Keyboard-accessible: Ctrl/Cmd-K toggles, arrows move, Enter
// navigates to the selected node page, Esc closes.

const INFORMAL_DOMAIN = "«Informal.Block.informal»";

let indexPromise = null;
let overlay = null;
let inputEl = null;
let resultsEl = null;
let items = [];
let filtered = [];
let activeIndex = 0;
let lastFocused = null;

/** Strip a single leading slash so the href resolves against `<base href>`. */
function stripLeadingSlash(href) {
  return typeof href === "string" && href.startsWith("/") ? href.slice(1) : (href || "");
}

/** Pick a readable display string from an informal-domain `data` block. */
function displayFor(name, data) {
  if (data && typeof data === "object") {
    if (typeof data.display === "string" && data.display.trim()) return data.display.trim();
    if (typeof data.label === "string" && data.label.trim()) return data.label.trim();
  }
  return name;
}

/** Pick the node kind from the `data.kind` discriminated union, if present. */
function kindFor(data) {
  const k = data && data.kind;
  if (!k || typeof k !== "object") return "";
  // kind is e.g. { statement: { kind: "theorem" } } or { definition: {} }.
  const outer = Object.keys(k)[0];
  if (!outer) return "";
  const inner = k[outer];
  if (inner && typeof inner === "object" && typeof inner.kind === "string") return inner.kind;
  return outer;
}

/** Build a muted secondary context line (kind + chapter + parent). */
function detailFor(data) {
  const parts = [];
  const kind = kindFor(data);
  if (kind) parts.push(kind);
  if (data && typeof data.partPrefix === "string" && data.partPrefix.trim()) {
    parts.push("§" + data.partPrefix.trim());
  }
  if (data && typeof data.parent === "string" && data.parent.trim()) {
    parts.push(data.parent.trim());
  }
  return parts.join(" · ");
}

/** Fetch and index the informal-domain entries from `xref.json` (once). */
function loadIndex() {
  if (indexPromise) return indexPromise;
  indexPromise = fetch("xref.json", { credentials: "same-origin" })
    .then((resp) => {
      if (!resp.ok) throw new Error("xref.json: " + resp.status);
      return resp.json();
    })
    .then((xref) => {
      const domain = xref && xref[INFORMAL_DOMAIN];
      const contents = (domain && domain.contents) || {};
      const out = [];
      const seen = new Set();
      for (const name of Object.keys(contents)) {
        const entries = contents[name];
        if (!Array.isArray(entries) || entries.length === 0) continue;
        const entry = entries[0];
        const data = entry && entry.data;
        const href = stripLeadingSlash(entry && entry.address);
        if (!href || seen.has(href)) continue;
        seen.add(href);
        const label = (data && typeof data.label === "string" && data.label) || name;
        out.push({
          label,
          display: displayFor(name, data),
          detail: detailFor(data),
          href,
          haystack: (label + " " + displayFor(name, data)).toLowerCase(),
        });
      }
      out.sort((a, b) => a.display.localeCompare(b.display));
      return out;
    })
    .catch((err) => {
      console.warn("command palette: failed to load xref.json", err);
      return [];
    });
  return indexPromise;
}

const BOUNDARY = /[\s._\-/:]/;

/**
 * Hand-rolled fuzzy subsequence scorer.
 *
 * Returns `null` when `query` is not a subsequence of `text`; otherwise a number
 * where higher is a better match. Rewards contiguous runs and matches at word
 * boundaries (start, or after a separator / camelCase hump).
 */
function fuzzyScore(query, text) {
  if (!query) return 0;
  const q = query.toLowerCase();
  const t = text.toLowerCase();
  let score = 0;
  let ti = 0;
  let prevMatch = -2;
  for (let qi = 0; qi < q.length; qi++) {
    const ch = q[qi];
    let found = -1;
    for (let j = ti; j < t.length; j++) {
      if (t[j] === ch) { found = j; break; }
    }
    if (found === -1) return null;
    score += 1;
    if (found === prevMatch + 1) score += 6; // contiguity bonus
    const prevCh = found > 0 ? text[found - 1] : "";
    const isBoundary =
      found === 0 ||
      BOUNDARY.test(prevCh) ||
      (prevCh && prevCh.toLowerCase() === prevCh && text[found].toLowerCase() !== text[found]);
    if (isBoundary) score += 8; // word-boundary bonus
    score -= (found - ti) * 0.5; // gap penalty (distance skipped)
    prevMatch = found;
    ti = found + 1;
  }
  // Prefer shorter haystacks and earlier first matches.
  score -= text.length * 0.05;
  return score;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function render() {
  if (!resultsEl) return;
  if (filtered.length === 0) {
    resultsEl.innerHTML =
      '<li class="bp-cmdk-empty" role="presentation">No matching nodes</li>';
    return;
  }
  const html = filtered.map((it, i) => {
    const active = i === activeIndex ? " bp-cmdk-item-active" : "";
    const detail = it.detail
      ? '<span class="bp-cmdk-item-detail">' + escapeHtml(it.detail) + "</span>"
      : "";
    return (
      '<li class="bp-cmdk-item' + active + '" role="option" id="bp-cmdk-opt-' + i +
      '" aria-selected="' + (i === activeIndex) + '" data-index="' + i + '">' +
      '<span class="bp-cmdk-item-label">' + escapeHtml(it.display) + "</span>" +
      detail +
      "</li>"
    );
  }).join("");
  resultsEl.innerHTML = html;
  inputEl.setAttribute("aria-activedescendant", "bp-cmdk-opt-" + activeIndex);
  const activeEl = resultsEl.querySelector(".bp-cmdk-item-active");
  if (activeEl && activeEl.scrollIntoView) activeEl.scrollIntoView({ block: "nearest" });
}

function applyFilter() {
  const query = (inputEl.value || "").trim();
  if (!query) {
    filtered = items.slice(0, 50);
  } else {
    const scored = [];
    for (const it of items) {
      const s = fuzzyScore(query, it.haystack);
      if (s !== null) scored.push({ it, s });
    }
    scored.sort((a, b) => b.s - a.s);
    filtered = scored.slice(0, 50).map((x) => x.it);
  }
  activeIndex = 0;
  render();
}

function buildOverlay() {
  overlay = document.createElement("div");
  overlay.className = "bp-cmdk-overlay";
  overlay.setAttribute("hidden", "");
  overlay.innerHTML =
    '<div class="bp-cmdk-panel" role="dialog" aria-modal="true" aria-label="Jump to node">' +
    '<input class="bp-cmdk-input" type="text" autocomplete="off" spellcheck="false" ' +
    'role="combobox" aria-expanded="true" aria-controls="bp-cmdk-results" ' +
    'aria-autocomplete="list" placeholder="Jump to a node…" />' +
    '<ul class="bp-cmdk-results" id="bp-cmdk-results" role="listbox"></ul>' +
    '<div class="bp-cmdk-hint">↑↓ navigate · ↵ open · esc close</div>' +
    "</div>";
  document.body.appendChild(overlay);
  inputEl = overlay.querySelector(".bp-cmdk-input");
  resultsEl = overlay.querySelector(".bp-cmdk-results");

  overlay.addEventListener("mousedown", (e) => {
    if (e.target === overlay) closePalette();
  });
  inputEl.addEventListener("input", applyFilter);
  inputEl.addEventListener("keydown", onInputKeydown);
  resultsEl.addEventListener("mousemove", (e) => {
    const li = e.target.closest(".bp-cmdk-item");
    if (li && li.dataset.index) {
      const idx = parseInt(li.dataset.index, 10);
      if (idx !== activeIndex) { activeIndex = idx; render(); }
    }
  });
  resultsEl.addEventListener("click", (e) => {
    const li = e.target.closest(".bp-cmdk-item");
    if (li && li.dataset.index) {
      activeIndex = parseInt(li.dataset.index, 10);
      navigateActive();
    }
  });
}

function navigateActive() {
  const it = filtered[activeIndex];
  if (!it) return;
  closePalette();
  try {
    const url = new URL(it.href, document.baseURI);
    window.location.href = url.href;
  } catch (_) {
    window.location.href = it.href;
  }
}

function onInputKeydown(e) {
  if (e.key === "ArrowDown") {
    e.preventDefault();
    if (filtered.length) { activeIndex = (activeIndex + 1) % filtered.length; render(); }
  } else if (e.key === "ArrowUp") {
    e.preventDefault();
    if (filtered.length) { activeIndex = (activeIndex - 1 + filtered.length) % filtered.length; render(); }
  } else if (e.key === "Enter") {
    e.preventDefault();
    navigateActive();
  } else if (e.key === "Escape") {
    e.preventDefault();
    closePalette();
  }
}

function openPalette() {
  if (!overlay) buildOverlay();
  lastFocused = document.activeElement;
  overlay.removeAttribute("hidden");
  inputEl.value = "";
  // Show something immediately, then refine once the index resolves.
  filtered = items.slice(0, 50);
  render();
  inputEl.focus();
  loadIndex().then((loaded) => {
    items = loaded;
    if (!overlay.hasAttribute("hidden")) applyFilter();
  });
}

function closePalette() {
  if (!overlay || overlay.hasAttribute("hidden")) return;
  overlay.setAttribute("hidden", "");
  if (lastFocused && lastFocused.focus) {
    try { lastFocused.focus(); } catch (_) { /* ignore */ }
  }
}

function isPaletteOpen() {
  return overlay && !overlay.hasAttribute("hidden");
}

export function startCommandPalette() {
  if (typeof document === "undefined") return;
  if (globalThis.__bpCommandPaletteStarted) return;
  globalThis.__bpCommandPaletteStarted = true;
  document.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && (e.key === "k" || e.key === "K")) {
      e.preventDefault();
      if (isPaletteOpen()) closePalette();
      else openPalette();
    }
  });
}

export default { startCommandPalette };
