// https://d3js.org v7.9.0 Copyright 2010-2023 Mike Bostock
// A vendored library banner and doc comments reference off-origin URLs but never
// initiate a request. See https://github.com/d3/d3 for provenance.
export function graph(root) {
  const data = "-verso-data/graph.json"; // same-origin
  return fetch(data).then((r) => r.json());
  /* also note: fetch("https://example.com/x") appears here only inside a comment */
}
