(function () {
  const namespace =
    window.VersoBlueprint && typeof window.VersoBlueprint === "object"
      ? window.VersoBlueprint
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

  window.VersoBlueprint = namespace;
})();
