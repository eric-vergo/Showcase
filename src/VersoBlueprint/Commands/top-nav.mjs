// Top-nav category strip injected into the fixed site banner (the `<body> > header`
// element). JS-only: no verso-core template edit (same pattern as banner-nav.mjs).
//
// Tabs: Definitions / Theorems / Project management -> `defs/`, `theorems/`, `pm/`.
// Each href is resolved against `document.baseURI` (every page carries a
// `<base href>` pointing at the site root), so the tabs work correctly from a 2-deep
// node page and under file://. The active tab is marked `aria-current="page"`; the
// Project-management tab is active on the PM hub *and* on every project-management
// route (`pm/`, `worklist/`, `audit/`, `mathlib-candidates/`, `owners/`, `tags/`).
//
// Placement: the nav is appended INSIDE the banner's `.header-logo-wrapper` (its
// first cell) so the tabs sit beside the Home logo and leave the grid banner's
// centre cell free to truly centre the title; it falls back to inserting before the
// `flex: 1` `.header-title-wrapper` when no logo wrapper is present (older banners).
// At <=700px the core banner hides the logo slot (and the tabs with it) and shows
// the ToC burger, so the tabs are a desktop/tablet affordance — the command palette
// + ToC cover navigation on phones. Styling + responsiveness live in
// Commands/DocsChrome.lean (`--bp-*` tokens; both themes).

const NAV_CLASS = "bp-topnav";
const MENU_ID = "bp-topnav-menu";

const CATEGORIES = [
  { label: "Definitions", href: "defs/" },
  { label: "Theorems", href: "theorems/" },
  // The Project-management tab is active on its hub page and on every top-level
  // project-management route (worklist / audit / candidates / owner / tag pages).
  {
    label: "Project management",
    href: "pm/",
    also: ["worklist/", "audit/", "mathlib-candidates/", "owners/", "tags/"]
  }
];

function resolve(href) {
  try {
    return new URL(href, document.baseURI).href;
  } catch (_e) {
    return href;
  }
}

// A tab is active when the current page lives within the tab's directory (the
// href always ends in "/", so `theorems/` never matches `theorems-x/`).
function isActive(targetHref) {
  try {
    const t = new URL(targetHref);
    const p = window.location.pathname;
    return p === t.pathname || p.indexOf(t.pathname) === 0;
  } catch (_e) {
    return false;
  }
}

function install() {
  if (typeof document === "undefined") return;
  const header = document.querySelector("body > header");
  if (!header || header.querySelector("." + NAV_CLASS)) return;

  const nav = document.createElement("nav");
  nav.className = NAV_CLASS;
  nav.setAttribute("aria-label", "Browse declarations");

  const menu = document.createElement("div");
  menu.className = "bp-topnav-menu";
  menu.id = MENU_ID;

  CATEGORIES.forEach(function (cat) {
    const a = document.createElement("a");
    a.className = "bp-topnav-link";
    a.textContent = cat.label;
    const target = resolve(cat.href);
    a.href = target;
    // A tab is active when the page is under its own directory or under any of its
    // additional `also` routes (the Project-management tab spans the PM sub-pages).
    const active =
      isActive(target) ||
      (cat.also || []).some(function (h) { return isActive(resolve(h)); });
    if (active) a.setAttribute("aria-current", "page");
    menu.appendChild(a);
  });

  nav.appendChild(menu);
  // Append inside the banner's logo wrapper (its first cell) so the tabs sit beside
  // the Home logo and the grid banner's centre cell can truly centre the title.
  // Fall back to inserting before the `flex: 1` title wrapper when no logo wrapper
  // is present (older banners): placing the nav before that growing element keeps the
  // later-mounted search box (right, appended at `window load`) from overlaying the
  // tabs.
  const logoWrap = header.querySelector(".header-logo-wrapper");
  if (logoWrap) {
    logoWrap.appendChild(nav);
  } else {
    const titleWrap = header.querySelector(".header-title-wrapper");
    if (titleWrap) {
      header.insertBefore(nav, titleWrap);
    } else {
      header.appendChild(nav);
    }
  }
}

export function startTopNav() {
  if (typeof document === "undefined") return;
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", install, { once: true });
  } else {
    install();
  }
}

export default { startTopNav };
