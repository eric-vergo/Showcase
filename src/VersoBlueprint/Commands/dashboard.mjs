// Dashboard d3 charts.
//
// Progressive enhancement only: every chart mount (`.bp_dashboard_chart`) ships
// with server-rendered fallback content. This module lazily loads the vendored
// d3 bundle (offline, no CDN), parses the embedded `chartData` JSON, and draws a
// donut + bar charts into the mounts. On success it marks the mount
// `bp_dashboard_chart_enhanced` (CSS then hides the fallback). On ANY error — or
// when JS is disabled — the class is never added, so the fallback stays visible.

import { load } from "./graph-runtime-core.mjs";

// Document-relative; resolves to the site root via each page's <base href>,
// matching how the graph runtime references the vendored d3 bundle.
const D3_URL = "-verso-data/lib/d3.min.js";

function hasD3() {
  return !!(window.d3 && typeof window.d3.select === "function");
}

let d3Promise = null;

function ensureD3() {
  if (hasD3()) return Promise.resolve(window.d3);
  if (!d3Promise) {
    d3Promise = load(D3_URL)
      .then(function () {
        return hasD3() ? window.d3 : null;
      })
      .catch(function (err) {
        d3Promise = null;
        throw err;
      });
  }
  return d3Promise;
}

function readChartData() {
  const node = document.querySelector(".bp-dashboard-data");
  if (!node) return null;
  try {
    return JSON.parse(node.textContent || "{}");
  } catch (_err) {
    return null;
  }
}

function cssVar(name, fallback) {
  try {
    const v = getComputedStyle(document.documentElement).getPropertyValue(name);
    return v && v.trim() ? v.trim() : fallback;
  } catch (_err) {
    return fallback;
  }
}

// Palette read from the `--bp-color-*` design tokens, so charts track light and
// dark themes automatically (the tokens are redefined per color scheme).
function readPalette() {
  return {
    closed: cssVar("--bp-color-accent-success", "#16a34a"),
    ready: cssVar("--bp-color-accent-info", "#7c3aed"),
    blocked: cssVar("--bp-color-accent-danger", "#dc2626"),
    warning: cssVar("--bp-color-accent-warning", "#ca8a04"),
    other: cssVar("--bp-color-border-strong", "#94a3b8"),
    text: cssVar("--bp-color-text", "#111827"),
    textMuted: cssVar("--bp-color-text-muted", "#334155"),
    grid: cssVar("--bp-color-border-soft", "#e2e8f0"),
    track: cssVar("--bp-color-surface-muted", "#f8fafc")
  };
}

function chartHost(mount) {
  const prev = mount.querySelector(".bp_dashboard_chart_canvas");
  if (prev) prev.remove();
  const host = document.createElement("div");
  host.className = "bp_dashboard_chart_canvas";
  mount.appendChild(host);
  return host;
}

function appendLegend(host, items) {
  const ul = document.createElement("ul");
  ul.className = "bp_dashboard_legend";
  items.forEach(function (it) {
    const li = document.createElement("li");
    const sw = document.createElement("span");
    sw.className = "bp_dashboard_swatch";
    sw.style.background = it.color;
    li.appendChild(sw);
    li.appendChild(document.createTextNode(it.label + ": " + it.value));
    ul.appendChild(li);
  });
  host.appendChild(ul);
}

function drawStatusDonut(d3, mount, data, pal) {
  const cs = data.coverageSplit || {};
  const slices = [
    { label: "Fully closed", value: cs.fullyClosed || 0, color: pal.closed },
    { label: "Formalized, ancestors open", value: cs.formalizedWithoutAncestors || 0, color: pal.warning },
    { label: "Ready to formalize", value: cs.readyToFormalize || 0, color: pal.ready },
    { label: "Informal only", value: cs.informalOnly || 0, color: pal.other },
    { label: "Blocked / incomplete", value: cs.blockedOrIncomplete || 0, color: pal.blocked }
  ].filter(function (d) { return d.value > 0; });
  const total = slices.reduce(function (a, d) { return a + d.value; }, 0);
  if (total === 0) return false;

  const host = chartHost(mount);
  const width = 220;
  const height = 200;
  const radius = Math.min(width, height) / 2 - 4;

  const svg = d3
    .select(host)
    .append("svg")
    .attr("class", "bp_dashboard_svg")
    .attr("viewBox", "0 0 " + width + " " + height)
    .attr("role", "img")
    .attr("aria-label", "Coverage by status");
  const g = svg
    .append("g")
    .attr("transform", "translate(" + width / 2 + "," + height / 2 + ")");
  const pie = d3.pie().sort(null).value(function (d) { return d.value; });
  const arc = d3.arc().innerRadius(radius * 0.58).outerRadius(radius);
  g.selectAll("path")
    .data(pie(slices))
    .enter()
    .append("path")
    .attr("d", arc)
    .attr("fill", function (d) { return d.data.color; })
    .attr("stroke", pal.grid)
    .attr("stroke-width", 1);
  g.append("text")
    .attr("text-anchor", "middle")
    .attr("dy", "0.35em")
    .attr("fill", pal.text)
    .attr("font-size", "22")
    .attr("font-weight", "700")
    .text(total);

  appendLegend(host, slices);
  return true;
}

// Generic horizontal stacked bar chart.
function drawStackedBars(d3, mount, rows, keys, pal) {
  rows = rows.filter(function (r) { return (r.total || 0) > 0; });
  if (rows.length === 0) return false;

  const host = chartHost(mount);
  const margin = { top: 4, right: 8, bottom: 4, left: 110 };
  const rowH = 26;
  const innerW = 360;
  const width = margin.left + innerW + margin.right;
  const height = margin.top + rows.length * rowH + margin.bottom;
  const maxTotal = d3.max(rows, function (r) { return r.total; }) || 1;

  const svg = d3
    .select(host)
    .append("svg")
    .attr("class", "bp_dashboard_svg")
    .attr("viewBox", "0 0 " + width + " " + height)
    .attr("role", "img")
    .attr("aria-label", "Per-group breakdown");

  const x = d3.scaleLinear().domain([0, maxTotal]).range([0, innerW]);
  const y = d3
    .scaleBand()
    .domain(rows.map(function (_r, i) { return i; }))
    .range([margin.top, height - margin.bottom])
    .padding(0.25);

  rows.forEach(function (r, i) {
    const yPos = y(i);
    const bandH = y.bandwidth();
    // label
    svg
      .append("text")
      .attr("x", margin.left - 8)
      .attr("y", yPos + bandH / 2)
      .attr("dy", "0.35em")
      .attr("text-anchor", "end")
      .attr("fill", pal.textMuted)
      .attr("font-size", "11")
      .text(r.label.length > 18 ? r.label.slice(0, 17) + "…" : r.label);
    // track
    svg
      .append("rect")
      .attr("x", margin.left)
      .attr("y", yPos)
      .attr("width", innerW)
      .attr("height", bandH)
      .attr("rx", 3)
      .attr("fill", pal.track);
    // stacked segments
    let acc = 0;
    keys.forEach(function (k) {
      const v = r[k.key] || 0;
      if (v <= 0) return;
      svg
        .append("rect")
        .attr("x", margin.left + x(acc))
        .attr("y", yPos)
        .attr("width", Math.max(0, x(acc + v) - x(acc)))
        .attr("height", bandH)
        .attr("fill", k.color);
      acc += v;
    });
    // total count
    svg
      .append("text")
      .attr("x", margin.left + x(r.total) + 4)
      .attr("y", yPos + bandH / 2)
      .attr("dy", "0.35em")
      .attr("fill", pal.textMuted)
      .attr("font-size", "11")
      .text(r.total);
  });
  return true;
}

function drawChapterBars(d3, mount, data, pal) {
  const rows = (data.groupHealth || []).map(function (g) {
    const label = g.header && g.header.length ? g.header : String(g.parent || "");
    const closed = g.closedEntries || 0;
    const ready = g.readyEntries || 0;
    const blocked = g.blockedEntries || 0;
    const total = g.totalEntries || 0;
    const other = Math.max(0, total - closed - ready - blocked);
    return { label: label, closed: closed, ready: ready, blocked: blocked, other: other, total: total };
  });
  const keys = [
    { key: "closed", color: pal.closed },
    { key: "ready", color: pal.ready },
    { key: "blocked", color: pal.blocked },
    { key: "other", color: pal.other }
  ];
  const drew = drawStackedBars(d3, mount, rows, keys, pal);
  if (drew) {
    appendLegend(mount.querySelector(".bp_dashboard_chart_canvas"), [
      { label: "closed", value: "", color: pal.closed },
      { label: "ready", value: "", color: pal.ready },
      { label: "blocked", value: "", color: pal.blocked },
      { label: "other", value: "", color: pal.other }
    ]);
  }
  return drew;
}

function drawRollupBars(d3, mount, items, pal, kind) {
  const rows = (items || []).map(function (it) {
    const label =
      kind === "owner"
        ? it.displayName && it.displayName.length
          ? it.displayName
          : String(it.owner || "")
        : String(it.tag || "");
    const total = it.totalEntries || 0;
    const actionable = it.actionableEntries || 0;
    return { label: label, actionable: actionable, rest: Math.max(0, total - actionable), total: total };
  });
  const keys = [
    { key: "actionable", color: pal.ready },
    { key: "rest", color: pal.other }
  ];
  return drawStackedBars(d3, mount, rows, keys, pal);
}

// Draw (or redraw) every mount. `chartHost` removes any previous canvas before
// appending a fresh one, so calling this again on a theme change replaces the
// charts in place — no duplicate SVGs or leaked legends.
function drawAll(d3, mounts, data) {
  const pal = readPalette();
  mounts.forEach(function (mount) {
    try {
      const kind = mount.getAttribute("data-bp-chart");
      let drew = false;
      if (kind === "status") drew = drawStatusDonut(d3, mount, data, pal);
      else if (kind === "chapters") drew = drawChapterBars(d3, mount, data, pal);
      else if (kind === "owners") drew = drawRollupBars(d3, mount, data.ownerRollups || [], pal, "owner");
      else if (kind === "tags") drew = drawRollupBars(d3, mount, data.tagRollups || [], pal, "tag");
      if (drew) mount.classList.add("bp_dashboard_chart_enhanced");
    } catch (_err) {
      // Leave this mount's server-rendered fallback in place.
    }
  });
}

export function startDashboard() {
  let mounts;
  try {
    mounts = Array.prototype.slice.call(document.querySelectorAll(".bp_dashboard_chart"));
  } catch (_err) {
    return;
  }
  if (!mounts || mounts.length === 0) return;
  const data = readChartData();
  if (!data) return;

  ensureD3()
    .then(function (d3) {
      if (!d3) return;
      drawAll(d3, mounts, data);

      // Redraw when the color scheme toggles so the charts pick up the new
      // `--bp-color-*` palette. Coalesce bursts and defer to the next frame so the
      // updated CSS variables are in effect before `getComputedStyle` reads them.
      const raf =
        window.requestAnimationFrame || function (cb) { return setTimeout(cb, 0); };
      let pending = false;
      window.addEventListener("bp-color-scheme-change", function () {
        if (pending) return;
        pending = true;
        raf(function () {
          pending = false;
          try {
            drawAll(d3, mounts, data);
          } catch (_err) {
            // Keep the existing charts on a redraw failure.
          }
        });
      });
    })
    .catch(function () {
      // d3 failed to load: leave all fallbacks in place.
    });
}

export default { startDashboard };
