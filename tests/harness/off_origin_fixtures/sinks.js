// Bundled module that reaches off-origin through assorted network sinks.
export function boot() {
  fetch("https://telemetry.invalid/collect");
  const xhr = new XMLHttpRequest();
  xhr.open("GET", "http://data.invalid/feed.json");
  new WebSocket("wss://push.invalid/ws");
  navigator.sendBeacon("https://beacon.invalid/hit");
  import("https://cdn.invalid/lazy.mjs");
  const el = document.querySelector("img");
  el.src = "https://img.invalid/tracker.gif";
}
