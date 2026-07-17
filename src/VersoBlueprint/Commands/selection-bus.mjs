// Shared "current selection" channel for the metadata rail.
//
// One selection at a time, identified by a declaration name. Any feature that
// can express "the user is looking at this declaration" pushes to the bus via
// `set`; the metadata rail (and anyone else) reads it via `subscribe` / `get`
// or the `verso-blueprint:selection` DOM CustomEvent. JS-only, no core edits.
//
// A selection is `{ declName, source?, nodeLabel?, title?, meta? }`:
//   * `declName`  fully-qualified name (registry / `data-bp-decl` key) — required.
//   * `source`    who set it ("card" | "graph" | "rail" | "load" | …), advisory.
//   * `nodeLabel` originating blueprint node label, when known.
//   * `title`     display title hint (e.g. "Definition 3 (bit)"), when known.
//   * `meta`      optional inline slim record (see metadata-rail.mjs) so a
//                 selection can carry first-paint data without a registry fetch.

export const SELECTION_EVENT = "verso-blueprint:selection";

function createSelectionBus() {
  const listeners = new Set();
  let current = null;

  function get() {
    return current;
  }

  function set(selection) {
    const next =
      selection && typeof selection === "object" && selection.declName
        ? selection
        : null;
    current = next;
    listeners.forEach(function (fn) {
      try {
        fn(current);
      } catch (err) {
        if (typeof console !== "undefined" && console && console.error) {
          console.error("metadata rail: selection listener failed", err);
        }
      }
    });
    if (typeof document !== "undefined" && typeof CustomEvent === "function") {
      try {
        document.dispatchEvent(
          new CustomEvent(SELECTION_EVENT, { detail: current })
        );
      } catch (_e) {
        /* ignore environments without CustomEvent construction */
      }
    }
    return current;
  }

  function subscribe(fn) {
    if (typeof fn !== "function") return function () {};
    listeners.add(fn);
    return function () {
      listeners.delete(fn);
    };
  }

  return { get: get, set: set, subscribe: subscribe, event: SELECTION_EVENT };
}

// Install (idempotently) onto `window.VersoBlueprint.selection`, coexisting with
// the preview runtime's `window.VersoBlueprint.render` namespace.
export function installSelectionBus() {
  const bus = createSelectionBus();
  if (typeof window === "undefined") return bus;
  const ns =
    window.VersoBlueprint && typeof window.VersoBlueprint === "object"
      ? window.VersoBlueprint
      : {};
  if (!ns.selection || typeof ns.selection.subscribe !== "function") {
    ns.selection = bus;
  }
  window.VersoBlueprint = ns;
  return ns.selection;
}

export default { installSelectionBus, SELECTION_EVENT };
