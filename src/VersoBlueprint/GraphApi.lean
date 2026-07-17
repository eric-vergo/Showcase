/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.Graph
import VersoBlueprint.Informal.Block.Store
import VersoBlueprint.Lib.PreviewSource
import VersoBlueprint.NodeRoute
import VersoBlueprint.TraversalIndex

/-!
Public graph-data helpers.

`Informal.Graph` owns the stable graph data structures and the semantic
environment builder. This module adds the traversal-state bridge: graph blocks
store semantic `GraphData` during traversal, and renderers/manifests finalize
that cached object against the completed traversal state to add hrefs and
display titles.
-/

namespace Informal.GraphApi

open Lean
open Verso
open Verso.Genre Manual

/-- Stable traversal-cache key for a rendered graph block. -/
def cacheKey (id : Verso.Multi.InternalId) : String :=
  s!"graph:{id}"

/-- Attach the rendered block key to graph data. -/
def keyedData (id : Verso.Multi.InternalId) (data : Informal.Graph.GraphData) :
    Informal.Graph.GraphData :=
  { data with key := cacheKey id }

private def nodeTitle? (state : TraverseState) (label : Name) : Option String :=
  (Informal.TraversalIndex.Nodes.data? state label).map fun data =>
    data.displayTitle state

private def nodeHref? (state : TraverseState) (label : Name) : Option String :=
  Informal.TraversalIndex.Nodes.href? state label

private def groupTitle? (state : TraverseState) (label : Name) : Option String :=
  (Informal.TraversalIndex.Groups.data? state label).bind fun groupData =>
    let title := groupData.header.trimAscii.toString
    if title.isEmpty then none else some title

/-- Human-readable chapter name from the chapter slug embedded in an in-chapter
href (`Nonlinearity-of-the-Prime-Race/#…` → `Nonlinearity of the Prime Race`).
The 2-liner precedent is `ExtraPages.candidateChapter`. -/
private def chapterTitleFromHref (href : String) : String :=
  ((href.splitOn "/").headD "").replace "-" " "

/-- Compact cluster title for a group: the chapter name of a representative member,
resolved from the member's raw in-chapter href in the traversal node index. Uses
`TraversalIndex.Nodes.href?` deliberately — NOT the enriched `NodeData.href`, which
may point at a `nodes/…` page and would yield the bogus chapter "nodes". `none` when
no member has a resolvable chapter href. -/
private def groupShortTitle? (state : TraverseState) (group : Informal.Graph.GroupData) :
    Option String :=
  group.children.findSome? fun child =>
    match Informal.TraversalIndex.Nodes.href? state child with
    | some href =>
      let title := chapterTitleFromHref href
      if title.isEmpty then none else some title
    | none => none

private def enrichNode (state : TraverseState) (node : Informal.Graph.NodeData) :
    Informal.Graph.NodeData :=
  let title := (nodeTitle? state node.label).getD node.title
  -- Re-point nodes that have a dedicated per-node page to that page (the node
  -- page is now canonical and links back to the chapter). Nodes without a node
  -- page (e.g. external/Mathlib dependencies) keep their existing chapter anchor
  -- so we never emit a dangling node-page link. The href is root-relative with
  -- no leading slash, so it resolves via the per-page `<base href>` exactly like
  -- the chapter anchors it replaces (DOT/JSON payloads are not relativized).
  let href :=
    if Informal.NodeRoute.hasNodePage state node.label then
      some (Informal.NodeRoute.nodePageHref node.label)
    else
      nodeHref? state node.label <|> node.href
  let previewKey := Informal.PreviewSource.traversalLookupKeyOrStatement state node.label
  { node with title, href, previewKey }

private def enrichGroup (state : TraverseState) (group : Informal.Graph.GroupData) :
    Informal.Graph.GroupData :=
  let group :=
    match groupTitle? state group.label with
    | some title => { group with title, declared := true }
    | none => group
  match groupShortTitle? state group with
  | some short => { group with shortTitle := short }
  | none => group

/--
Finalize graph data against a completed traversal state.

This is the single projection from semantic graph data to public graph data:
rendered page JSON and manifest/cache output both use it so href, title, and
group metadata stay consistent.
-/
def finalData (state : TraverseState) (data : Informal.Graph.GraphData) :
    Informal.Graph.GraphData :=
  {
    data with
      nodes := data.nodes.map (enrichNode state)
      groups := data.groups.map (enrichGroup state)
  }

/--
Finalize a graph block's semantic graph data for public page JSON.

Use this when rendering one graph block from its block payload and rendered
block id.
-/
def finalDataForBlock
    (state : TraverseState)
    (id : Verso.Multi.InternalId)
    (data : Informal.Graph.GraphData) : Informal.Graph.GraphData :=
  finalData state (keyedData id data)

/--
Store graph block data during traversal.

The cached payload deliberately remains semantic data plus the stable block key;
call `cachedData` after traversal finishes to read the public, finalized form.
-/
def saveData
    (state : TraverseState)
    (id : Verso.Multi.InternalId)
    (data : Informal.Graph.GraphData) : TraverseState :=
  let key := cacheKey id
  let data := keyedData id data
  state
    |> (fun state => Informal.TraversalIndex.Graphs.saveId state key id)
    |> (fun state => Informal.TraversalIndex.Graphs.saveData state key data)

/--
Read every traversal-cached graph and finalize it for public manifest/API use.

Call this only with the completed traversal state for the document/site being
emitted.
-/
def cachedData (state : TraverseState) : Array Informal.Graph.GraphData :=
  Informal.TraversalIndex.Graphs.allData state |>.map (finalData state)

/--
Union of every traversal-cached graph block into a single master `GraphData`.

This is the whole-document dependency universe consumed by the ancestors /
descendants traversals and (later) graph metrics. It folds over `cachedData`
(already finalized: hrefs, titles, statuses):

* nodes are deduplicated by `label`, keeping the first finalized occurrence;
* edges are unioned and deduplicated by `(source, target)` (first occurrence
  wins — the master graph block already carries each edge with its full axes);
* groups are unioned by `label`, merging their `children`, `declared` flag, and
  first non-empty `title`.

Fallback choice: when there are no cached graph blocks this returns an empty
`GraphData`. We deliberately do not synthesize adjacency from manifest entries.
`masterGraph` is pure (`TraverseState → GraphData`) so it cannot log a note, an
empty graph is the honest result when nothing was rendered, and every generated
Blueprint renders at least one graph block in practice — so this fallback is
effectively unreachable.
-/
def masterGraph (state : TraverseState) : Informal.Graph.GraphData :=
  (cachedData state).foldl (init := ({} : Informal.Graph.GraphData)) fun acc data =>
    let acc := data.nodes.foldl (init := acc) fun acc node =>
      if acc.nodes.any (·.label == node.label) then acc
      else { acc with nodes := acc.nodes.push node }
    let acc := data.edges.foldl (init := acc) fun acc edge =>
      if acc.edges.any (fun e => e.source == edge.source && e.target == edge.target) then acc
      else { acc with edges := acc.edges.push edge }
    data.groups.foldl (init := acc) fun acc group =>
      match acc.groups.findIdx? (fun g => g.label == group.label) with
      | some i =>
        { acc with
          groups := acc.groups.modify i fun existing =>
            { existing with
              children := group.children.foldl (init := existing.children) fun ch c =>
                if ch.contains c then ch else ch.push c
              declared := existing.declared || group.declared
              title := if existing.title.isEmpty then group.title else existing.title
              shortTitle := if existing.shortTitle.isEmpty then group.shortTitle else existing.shortTitle } }
      | none => { acc with groups := acc.groups.push group }

end Informal.GraphApi
