// Per-page "On this page" declaration outline.
//
// Built entirely from the node cards already in the DOM (no new build data): on any
// page carrying `.bp_card2[data-bp-decl]` cards (chapter + node pages) it lists those
// declarations as anchor links and injects them below the fixed sidebar ToC
// (`nav#toc .first`), reusing the ToC's own scroll region rather than fighting the
// fixed layout. Styling lives in Commands/DocsChrome.lean (`--bp-*` tokens; both
// themes). An IntersectionObserver highlights the entry nearest the top as you scroll.

const OUTLINE_CLASS = "bp-page-outline";

function sanitizeId(name) {
  return "bp-outline-" + String(name).replace(/[^A-Za-z0-9_.-]/g, "_");
}

// A card's display label: the clean numbered title from the slim meta payload
// ("Theorem 3.1"), else the (often noisy — it carries the group blurb) card header
// text, else the raw declaration name.
function cardLabel(card, declName) {
  const meta = card.querySelector(".bp-decl-meta[data-bp-decl]");
  if (meta) {
    try {
      const rec = JSON.parse(meta.textContent || "null");
      if (rec && rec.title) return String(rec.title);
    } catch (_e) {
      /* ignore */
    }
  }
  const header = card.querySelector(".bp_card2_header");
  if (header) {
    const t = (header.textContent || "").replace(/\s+/g, " ").trim();
    if (t) return t;
  }
  return declName;
}

function cardKind(card) {
  const meta = card.querySelector(".bp-decl-meta[data-bp-decl]");
  if (meta) {
    try {
      const rec = JSON.parse(meta.textContent || "null");
      if (rec && rec.kind) return rec.kind === "Definition" ? "def" : "thm";
    } catch (_e) {
      /* ignore */
    }
  }
  return "";
}

function install() {
  if (typeof document === "undefined") return;
  const host = document.querySelector("nav#toc .first");
  if (!host || host.querySelector("." + OUTLINE_CLASS)) return;

  const cards = Array.prototype.slice.call(
    document.querySelectorAll('.bp_card2[data-bp-decl]:not([data-bp-decl=""])')
  );
  if (cards.length === 0) return;

  const list = document.createElement("ul");
  list.className = "bp-page-outline-list";
  const linksById = {};

  cards.forEach(function (card, i) {
    const declName = (card.getAttribute("data-bp-decl") || "").trim();
    if (!declName) return;
    let id = card.id;
    if (!id) {
      id = sanitizeId(declName) + "-" + i;
      card.id = id;
    }
    const li = document.createElement("li");
    const a = document.createElement("a");
    // Use the absolute page path (not a bare `#id`) so the `<base href>` on
    // multi-page output can't redirect the fragment to the site root.
    a.setAttribute("href", window.location.pathname + "#" + id);
    a.setAttribute("data-bp-outline-target", id);
    const kind = cardKind(card);
    if (kind) {
      const k = document.createElement("span");
      k.className = "bp-page-outline-kind";
      k.textContent = kind;
      a.appendChild(k);
    }
    a.appendChild(document.createTextNode(cardLabel(card, declName)));
    a.title = declName;
    li.appendChild(a);
    list.appendChild(li);
    linksById[id] = a;
  });

  if (list.childNodes.length === 0) return;

  const section = document.createElement("section");
  section.className = OUTLINE_CLASS;
  const title = document.createElement("h2");
  title.className = "bp-page-outline-title";
  title.textContent = "On this page";
  section.appendChild(title);
  section.appendChild(list);
  host.appendChild(section);

  // Scroll-spy: mark the card nearest the top as active.
  if (typeof IntersectionObserver === "function") {
    let activeId = null;
    const setActive = function (id) {
      if (id === activeId) return;
      if (activeId && linksById[activeId]) {
        linksById[activeId].classList.remove("bp-outline-active");
      }
      activeId = id;
      if (id && linksById[id]) linksById[id].classList.add("bp-outline-active");
    };
    const visible = new Set();
    const obs = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (e) {
          if (e.isIntersecting) visible.add(e.target.id);
          else visible.delete(e.target.id);
        });
        // Pick the first card (document order) currently intersecting.
        for (let i = 0; i < cards.length; i++) {
          if (visible.has(cards[i].id)) {
            setActive(cards[i].id);
            return;
          }
        }
      },
      { rootMargin: "-10% 0px -70% 0px", threshold: 0 }
    );
    cards.forEach(function (card) {
      if (card.id) obs.observe(card);
    });
  }
}

export function startPageOutline() {
  if (typeof document === "undefined") return;
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", install, { once: true });
  } else {
    install();
  }
}

export default { startPageOutline };
