// Top-nav category strip injected into the fixed site banner (the `<body> > header`
// element). JS-only: no verso-core template edit (same pattern as banner-nav.mjs).
//
// Links: Modules / Definitions / Theorems / Index -> the declaration-catalog pages
// (`modules/`, `defs/`, `theorems/`, `decl-index/`). Each is resolved against
// `document.baseURI` (every page carries a `<base href>` pointing at the site root),
// so they work correctly from a 2-deep node page and under file://. The current
// page's tab is marked `aria-current="page"`.
//
// Wide viewports: an inline row on the right of the banner. At <=700px (where the
// core banner hides the logo slot and shows the burger) it folds into a compact
// "Browse" dropdown so the tabs never collide with the title. Styling +
// responsiveness live in Commands/DocsChrome.lean (`--bp-*` tokens; both themes).

const NAV_CLASS = "bp-topnav";
const MENU_ID = "bp-topnav-menu";

const CATEGORIES = [
  { label: "Modules", href: "modules/" },
  { label: "Definitions", href: "defs/" },
  { label: "Theorems", href: "theorems/" },
  { label: "Index", href: "decl-index/" }
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
    if (isActive(target)) a.setAttribute("aria-current", "page");
    menu.appendChild(a);
  });

  nav.appendChild(menu);
  // Insert BEFORE the `flex: 1` title wrapper so that growing element physically
  // separates the nav (left) from the later-mounted search box (right, appended at
  // `window load`) — appending after the title lets the two right-aligned items
  // stack and the search input overlays the tabs.
  const titleWrap = header.querySelector(".header-title-wrapper");
  if (titleWrap) {
    header.insertBefore(nav, titleWrap);
  } else {
    header.appendChild(nav);
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
