import Verso
import VersoManual
import VersoBlueprint

open Verso
open Verso.Genre
open Verso.Genre.Manual

namespace PreviewRuntimeShowcase.Chapters.CustomRenderClient

def customRenderClientCss : String := r##"
.bp_custom_render_client {
  margin: 1.5rem 0;
}

.bp_custom_render_client_header {
  align-items: baseline;
  border-bottom: 1px solid var(--bp-color-border-soft);
  display: flex;
  flex-wrap: wrap;
  gap: 0.6rem;
  justify-content: space-between;
  margin-bottom: 1rem;
  padding: 0 0 0.5rem;
}

.bp_custom_render_client_header h2 {
  font-size: 1rem;
  margin: 0;
}

.bp_custom_render_client_status {
  color: var(--bp-color-text-muted);
  font-size: 0.78rem;
  font-weight: 700;
  text-transform: uppercase;
}

.bp_custom_render_client_examples {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.bp_custom_render_client_example {
  min-width: 0;
}

.bp_custom_render_client_example h3 {
  font-size: 0.9rem;
  margin: 0 0 0.5rem;
}

.bp_custom_render_client_note {
  color: var(--bp-color-text-muted);
  font-size: 0.78rem;
  margin: 0 0 0.35rem;
}

.bp_custom_render_client_example[data-bp-custom-client-example="render-preview-into"],
.bp_custom_render_client_example[data-bp-render-ok="false"] {
  background: var(--bp-color-surface);
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-sm);
  padding: 0.9rem;
}

.bp_custom_render_client_preview_header {
  background: var(--bp-color-background);
  border: 1px solid var(--bp-color-border-soft);
  border-left: 0.24rem solid var(--bp-color-accent, var(--bp-color-border));
  border-radius: var(--bp-radius-sm);
  margin-bottom: 0.65rem;
  padding: 0.5rem 0.6rem;
}

.bp_custom_render_client_preview_title {
  color: var(--bp-color-text-strong);
  display: block;
  font-weight: 700;
  margin-bottom: 0.25rem;
}

.bp_custom_render_client_preview_meta {
  color: var(--bp-color-text-muted);
  display: flex;
  flex-wrap: wrap;
  font-size: 0.76rem;
  gap: 0.45rem;
}

.bp_custom_render_client_summary {
  background: var(--bp-color-background);
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-sm);
  color: var(--bp-color-text-muted);
  font-size: 0.76rem;
  margin-bottom: 0.65rem;
  padding: 0.5rem;
}

.bp_custom_render_client_facts {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
}

.bp_custom_render_client_fact {
  background: var(--bp-color-surface);
  border-radius: var(--bp-radius-sm);
  padding: 0.16rem 0.36rem;
}

.bp_custom_render_client_fact strong {
  color: var(--bp-color-text-strong);
}

.bp_custom_render_client_graph {
  background: var(--bp-color-surface);
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-sm);
  padding: 0.9rem;
}

.bp_custom_render_client_graph h3 {
  font-size: 0.9rem;
  margin: 0 0 0.5rem;
}

.bp_custom_render_client_graph_nodes {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  margin-top: 0.65rem;
}

.bp_custom_render_client_graph_node {
  background: var(--bp-color-background);
  border: 1px solid var(--bp-color-border-soft);
  border-radius: var(--bp-radius-sm);
  color: var(--bp-color-text);
  padding: 0.18rem 0.4rem;
  text-decoration: none;
}

.bp_custom_render_client_graph_node:hover {
  border-color: var(--bp-color-accent, var(--bp-color-border));
}

.bp_custom_render_client_body {
  min-height: 8rem;
}

.bp_custom_render_client_body .bp_wrapper {
  max-width: 100%;
  overflow-wrap: anywhere;
}

.bp_custom_render_client_body .bp_heading {
  align-items: flex-start;
}

.bp_custom_render_client_body .bp_extras {
  display: flex;
  flex-wrap: wrap;
  gap: 0.3rem 0.55rem;
  justify-content: flex-start;
  margin-left: 0;
  width: 100%;
}

.bp_custom_render_client_body .bp_extra_slot {
  justify-content: flex-start;
}
"##

-- Keep this module rebuilt when the standalone custom-client asset changes.
def customRenderClientJs : String :=
  Informal.Commands.withPreviewClientReadyJs (include_str "custom-render-client.js")

private def clientText (text : String) : Verso.Output.Html :=
  VersoBlueprint.Html.text text

private def clientTag
    (tagName : String) (attrs : Array (String × String)) (body : Verso.Output.Html) :
    Verso.Output.Html :=
  Verso.Output.Html.tag tagName attrs body

private def clientExample
    (exampleName label facet title bodyKey note : String)
    (expectOk : Bool := true)
    (extras : Array Verso.Output.Html := #[]) :
    Verso.Output.Html :=
  let titleNode :=
    clientTag "h3" #[("data-bp-custom-client-title", "true")] (clientText title)
  let noteNode :=
    clientTag "p" #[("class", "bp_custom_render_client_note")] (clientText note)
  let summaryNode :=
    clientTag "div"
      #[("class", "bp_custom_render_client_summary"), ("data-bp-custom-client-summary", "true")]
      (clientText "Waiting for manifest data.")
  let previewHeaderNode :=
    clientTag "div"
      #[("class", "bp_custom_render_client_preview_header"),
        ("data-bp-custom-client-preview-header", "true")]
      (clientText "Waiting for preview header.")
  let bodyNode :=
    clientTag "div"
      #[("class", "bp_custom_render_client_body"), ("data-bp-custom-client-body", bodyKey)]
      .empty
  let expectedAttr := if expectOk then "true" else "false"
  clientTag "article"
    #[ ("class", "bp_custom_render_client_example"),
       ("data-bp-custom-client-example", exampleName),
       ("data-bp-preview-label", label),
       ("data-bp-preview-facet", facet),
       ("data-bp-expect-ok", expectedAttr) ]
    (Verso.Output.Html.seq
      (#[titleNode, noteNode, summaryNode] ++ extras ++ #[previewHeaderNode, bodyNode]))

private def graphDataExample : Verso.Output.Html :=
  let titleNode :=
    clientTag "h3" #[("data-bp-custom-client-title", "true")] (clientText "Graph manifest data")
  let noteNode :=
    clientTag "p" #[("class", "bp_custom_render_client_note")]
      (clientText "Standalone manifest access with api.loadGraphs; no rendered graph block is required on this page.")
  let summaryNode :=
    clientTag "div"
      #[("class", "bp_custom_render_client_summary"), ("data-bp-custom-client-graph-summary", "true")]
      (clientText "Waiting for graph data.")
  let nodeList :=
    clientTag "div"
      #[("class", "bp_custom_render_client_graph_nodes"), ("data-bp-custom-client-graph-nodes", "true")]
      .empty
  clientTag "article"
    #[ ("class", "bp_custom_render_client_graph"),
       ("data-bp-custom-client-graph", "true"),
       ("data-bp-graph-ok", "false") ]
    (Verso.Output.Html.seq #[titleNode, noteNode, summaryNode, nodeList])

def customRenderClientHtml : Verso.Output.Html :=
  let heading := clientTag "h2" #[] (clientText "Standalone Render Client")
  let status :=
    clientTag "div"
      #[("class", "bp_custom_render_client_status"), ("data-bp-custom-client-status-text", "true")]
      (clientText "Idle")
  let header :=
    clientTag "header"
      #[("class", "bp_custom_render_client_header")]
      (Verso.Output.Html.seq #[heading, status])
  let examples :=
    clientTag "div"
      #[("class", "bp_custom_render_client_examples")]
      (Verso.Output.Html.seq #[
        clientExample "render-preview-into" "preview_facets" "statement" "Body fragment"
          "statement"
          "Direct insertion with renderPreviewInto: useful for custom UIs, but intentionally body-only.",
        clientExample "render-canonical-preview-into" "preview_facets" "statement" "Canonical statement"
          "canonical-statement"
          "Canonical insertion with renderCanonicalPreviewInto; this reuses the generated Blueprint node wrapper.",
        clientExample "render-canonical-preview-into" "preview_facets" "proof" "Canonical proof"
          "proof"
          "Canonical proof-facet rendering, including the standard Blueprint heading.",
        clientExample "render-canonical-preview-into" "used_target" "statement" "Used-by and code"
          "used-target"
          "A definition with reverse dependencies, the standard used-by chip, and a Lean-code preview key.",
        clientExample "render-canonical-preview-into" "group_target" "statement" "Group header data"
          "group-target"
          "A grouped node with the standard group and used-by header extras.",
        clientExample "render-canonical-preview-into" "used_grouped_proof_panel" "statement" "Grouped theorem"
          "grouped-statement"
          "A theorem with group data, proof dependencies, used-by data, and an associated Lean preview key.",
        clientExample "render-canonical-preview-into" "used_grouped_proof_panel" "proof" "Proof dependencies"
          "grouped-proof"
          "The proof facet for the same theorem, showing proof-side uses and relation metadata.",
        clientExample "render-canonical-preview-into" "missing_custom_client_target" "statement" "Missing preview diagnostic"
          "missing"
          "An expected miss that demonstrates the runtime diagnostic branch for custom clients."
          false,
        graphDataExample
      ])
  clientTag "section"
    #[ ("class", "bp_custom_render_client"),
       ("id", "custom-render-client-example"),
       ("data-bp-custom-render-client", "true"),
       ("data-bp-custom-client-status", "idle") ]
    (Verso.Output.Html.seq #[header, examples])

open Verso Doc Elab Genre Manual in
block_extension Block.customRenderClientExample where
  data := Lean.Json.null
  traverse _id _data _contents := pure none
  toTeX := none
  extraCss := Informal.Commands.withBlueprintCssAssets [customRenderClientCss]
  extraJs := Informal.Commands.withPreviewRuntimeJsAssets [] [customRenderClientJs]
  toHtml :=
    some <| fun _goI _goB _id _data _blocks => do
      pure customRenderClientHtml

open Verso Doc Elab in
@[block_command]
public meta def custom_render_client_example : BlockCommandOf Unit
  | () => ``(Block.other Block.customRenderClientExample #[])

end PreviewRuntimeShowcase.Chapters.CustomRenderClient

open PreviewRuntimeShowcase.Chapters.CustomRenderClient

#doc (Manual) "Custom Render Client" =>

This page carries a standalone browser client for the Blueprint render API.

{custom_render_client_example}
