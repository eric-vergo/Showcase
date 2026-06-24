function defaultGlobalScope() {
  return typeof globalThis !== "undefined" ? globalThis : window;
}

export function installPreviewClientReady(globalScope = defaultGlobalScope()) {
  const windowObj = globalScope && globalScope.window ? globalScope.window : globalScope;
  const namespace =
    windowObj.VersoBlueprint && typeof windowObj.VersoBlueprint === "object"
      ? windowObj.VersoBlueprint
      : {};

  if (!Array.isArray(namespace.renderReadyCallbacks)) {
    namespace.renderReadyCallbacks = [];
  }

  if (typeof namespace.onRenderReady !== "function") {
    namespace.onRenderReady = function (fn) {
      if (typeof fn !== "function") return;
      if (namespace.render) {
        fn(namespace.render);
        return;
      }
      namespace.renderReadyCallbacks.push(fn);
    };
  }

  windowObj.VersoBlueprint = namespace;
  return namespace;
}

export const previewClientReady = {
  installPreviewClientReady
};

export default previewClientReady;
