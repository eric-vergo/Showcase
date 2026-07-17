// Back / Home controls injected into the fixed site banner's (otherwise empty)
// `.header-logo-wrapper` slot. JS-only: no verso-core template edits.
//
// * Home resolves to the site root. Every page carries a `<base href>` pointing
//   at the site root (node pages `./../../`), so `document.baseURI` is the root
//   URL; `index.html` relative to it is the root page (works under http *and*
//   file://).
// * Back uses `history.back()`, falling back to Home when there is no useful
//   same-origin history (direct entry / fresh tab -> `history.length <= 1`).
//
// The controls are quiet icon buttons with tooltips + ARIA labels, natively
// keyboard-focusable, styled with `--bp-*` / `--verso-*` tokens (see
// `Commands/BannerNav.lean`). Runs on every page because the page runtime that
// boots it (`blueprint-page-runtime.mjs`) is injected site-wide.

const NAV_ID = "bp-banner-nav";

function homeHref() {
  try {
    return new URL("index.html", document.baseURI).href;
  } catch (_e) {
    try {
      return document.baseURI;
    } catch (_e2) {
      return "./";
    }
  }
}

const ICON_BACK =
  '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" ' +
  'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ' +
  'focusable="false"><path d="M19 12H5"/><path d="M12 19l-7-7 7-7"/></svg>';

const ICON_HOME =
  '<svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" ' +
  'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ' +
  'focusable="false"><path d="M3 11l9-8 9 8"/><path d="M5 9.8V21h4v-6h6v6h4V9.8"/></svg>';

function goBack(ev) {
  if (ev && typeof ev.preventDefault === "function") ev.preventDefault();
  if (window.history && window.history.length > 1) {
    window.history.back();
  } else {
    window.location.href = homeHref();
  }
}

function installBannerNav() {
  if (typeof document === "undefined") return;
  if (document.getElementById(NAV_ID)) return;
  const wrapper = document.querySelector(".header-logo-wrapper");
  if (!wrapper) return;

  const nav = document.createElement("div");
  nav.id = NAV_ID;
  nav.className = "bp-banner-nav";
  nav.setAttribute("role", "group");
  nav.setAttribute("aria-label", "Site navigation");

  const back = document.createElement("button");
  back.type = "button";
  back.className = "bp-banner-nav-btn bp-banner-nav-back";
  back.setAttribute("aria-label", "Go back");
  back.setAttribute("title", "Back");
  back.innerHTML = ICON_BACK;
  back.addEventListener("click", goBack);

  const home = document.createElement("a");
  home.className = "bp-banner-nav-btn bp-banner-nav-home";
  home.setAttribute("aria-label", "Home");
  home.setAttribute("title", "Home");
  home.href = homeHref();
  home.innerHTML = ICON_HOME;

  nav.appendChild(back);
  nav.appendChild(home);
  // Prepend so the controls sit at the top-left, ahead of any (usually absent)
  // logo link.
  wrapper.insertBefore(nav, wrapper.firstChild);
}

export function startBannerNav() {
  if (typeof document === "undefined") return;
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", installBannerNav);
  } else {
    installBannerNav();
  }
}

export default { startBannerNav };
