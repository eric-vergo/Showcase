/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.TraversalIndex

/-!
Per-node page routing.

This is the single source of truth for the URL of a Blueprint node page. It is
intentionally a tiny, low-level module so that it can be imported by both
`GraphApi` (which re-points graph node hrefs) and `PreviewManifest` (which
re-points the public xref permalinks) without introducing an import cycle with
the node-page emitter in `NodePage`.

All routes are **root-relative without a leading slash** so that they resolve
against each page's `<base href>` — the same convention the existing graph URLs
use. Never emit these into DOT/JSON payloads with a leading slash. The xref
permalink rewrite (in `emitPublicXref`) is the one place that intentionally uses
a leading slash, because `find.js` strips it before resolving against `<base>`.
-/

namespace Informal.NodeRoute

open Lean
open Verso Verso.Multi
open Verso.Genre Manual

/--
Slug for a node-page directory derived from the canonical label string.

Pure and deterministic: identical inputs always produce identical slugs, so the
graph re-point (`GraphApi.enrichNode`), the xref re-point (`emitPublicXref`), and
the node-page emitter all agree without sharing any state. Collisions between two
distinct labels that sluggify identically are detected and reported by the
emitter; they are vanishingly rare for unique dotted Lean `Name`s.
-/
def nodePageSlugOfString (s : String) : String :=
  s.sluggify.toString

/-- Slug for a node-page directory derived from an informal node label. -/
def nodePageSlug (label : Name) : String :=
  nodePageSlugOfString label.toString

/--
Root-relative href (no leading slash) to a node page. Resolves against the
per-page `<base href>`; safe to emit into DOT/JSON graph payloads.
-/
def nodePageHref (label : Name) : String :=
  "node/" ++ nodePageSlug label ++ "/"

/-- Multi-page output path for a node page: `node/<slug>/index.html`. -/
def nodePagePath (label : Name) : Verso.Multi.Path :=
  #["node", nodePageSlug label]

/--
Whether `label` has a dedicated node page. Node pages are emitted for every
informal node (statement-facet) recorded in the traversal node index, so this is
exactly "is there an informal node for this label".
-/
def hasNodePage (state : TraverseState) (label : Name) : Bool :=
  (Informal.TraversalIndex.Nodes.data? state label).isSome

end Informal.NodeRoute
