/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoSlides
import Verso.Doc.ArgParse
import Verso.Doc.Elab
import VersoBlueprint.LabelNameParsing
import VersoBlueprint.PreviewCache

namespace Informal.Slides

open Lean
open Verso Doc Elab ArgParse

private def slideNodeMarkerAttr : String := "data-bp-blueprint-node"
private def slideNodeMarkerValue : String := "true"

private def blueprintSlideNodeMarkerAttrs : Array (String × String) :=
  #[(slideNodeMarkerAttr, slideNodeMarkerValue)]

public structure BlueprintSlideNode where
  label : String
  facet : String := "statement"
  key : String
  title? : Option String := none
  compact : Bool := false
  siteBase? : Option String := none
deriving Repr, BEq

private def attrValue? (attrs : Array (String × String)) (name : String) : Option String :=
  (attrs.find? fun attr => attr.1 == name).map (·.2)

private def BlueprintSlideNode.className (node : BlueprintSlideNode) : String :=
  if node.compact then
    "bp_slide_node bp_slide_node_compact"
  else
    "bp_slide_node"

def BlueprintSlideNode.toAttrs (node : BlueprintSlideNode) : Array (String × String) :=
  blueprintSlideNodeMarkerAttrs ++
    #[ ("class", node.className)
     , ("data-bp-label", node.label)
     , ("data-bp-facet", node.facet)
     , ("data-bp-preview-key", node.key)
     , ("data-bp-compact", if node.compact then "true" else "false")
     ] ++
    (node.title?.map (fun title => #[("data-bp-title", title)] ) |>.getD #[]) ++
    (node.siteBase?.map (fun siteBase => #[("data-bp-site-base", siteBase)] ) |>.getD #[])

def BlueprintSlideNode.fromAttrs? (attrs : Array (String × String)) : Option BlueprintSlideNode := do
  let marker ← attrValue? attrs slideNodeMarkerAttr
  guard (marker == slideNodeMarkerValue)
  let label ← attrValue? attrs "data-bp-label"
  let facet := attrValue? attrs "data-bp-facet" |>.getD "statement"
  let key := attrValue? attrs "data-bp-preview-key" |>.getD s!"{label}--{facet}"
  let title? := attrValue? attrs "data-bp-title"
  let compact := attrValue? attrs "data-bp-compact" == some "true"
  let siteBase? := attrValue? attrs "data-bp-site-base"
  some { label, facet, key, title?, compact, siteBase? }

def BlueprintSlideNode.renderedAttrs (node : BlueprintSlideNode) : Array (String × String) :=
  node.toAttrs ++ #[("data-bp-rendered", "static")]

def BlueprintSlideNode.fallbackText (node : BlueprintSlideNode) : String :=
  s!"Loading Blueprint node {node.label}..."

public structure BlueprintNodeConfig where
  label : String
  facet : Option String := none
  title : Option String := none
  compact : Bool := false
  siteBase : Option String := none

public meta instance : FromArgs BlueprintNodeConfig DocElabM where
  fromArgs :=
    BlueprintNodeConfig.mk <$>
      .positional `label .string <*>
      .named `facet .string true <*>
      .named `title .string true <*>
      .flag `compact false <*>
      .named `siteBase .string true

private def previewKey (label facet : String) : String :=
  let label := Informal.LabelNameParsing.parse label
  match facet with
  | "statement" => Informal.PreviewCache.key label .statement
  | "proof" => Informal.PreviewCache.key label .proof
  | other => s!"{label}--{other}"

def BlueprintNodeConfig.toSlideNode (cfg : BlueprintNodeConfig) : BlueprintSlideNode :=
  let facet := cfg.facet.getD "statement"
  {
    label := cfg.label
    facet
    key := previewKey cfg.label facet
    title? := cfg.title
    compact := cfg.compact
    siteBase? := cfg.siteBase
  }

public meta def blueprintNodeBlock (cfg : BlueprintNodeConfig) : DocElabM Term := do
  let node := cfg.toSlideNode
  let attrs := node.toAttrs
  let fallback := node.fallbackText
  ``(Verso.Doc.Block.other (VersoSlides.BlockExt.wrap $(quote attrs))
      #[Verso.Doc.Block.para #[Verso.Doc.Inline.text $(quote fallback)]])

end Informal.Slides
