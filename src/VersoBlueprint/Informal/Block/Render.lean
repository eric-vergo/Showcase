/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoManual
import VersoBlueprint.Informal.Block.Model
import VersoBlueprint.Informal.MetadataView

namespace Informal

open Verso.Output.Html

structure BlockKindRenderStyle where
  kindText : String
  showLabel : Bool := true
  kindCss : String
  wrapperCss : String
  headingCss : String
  captionCss : String
  labelCss : String
  contentCss : String

namespace BlockKindRenderStyle

def ofInProgressKind : Data.InProgressKind → BlockKindRenderStyle
  | .proof =>
    {
      kindText := "Proof"
      showLabel := false
      kindCss := "proof"
      wrapperCss := "proof_wrapper bp_kind_proof bp_style_proof"
      headingCss := "proof_heading"
      captionCss := "proof_caption"
      labelCss := "proof_label"
      contentCss := "proof_content"
    }
  | .statement nodeKind =>
    match nodeKind with
    | .definition =>
      {
        kindText := s!"{nodeKind}"
        kindCss := "definition"
        wrapperCss := "definition_thmwrapper theorem-style-definition bp_kind_definition bp_style_definition"
        headingCss := "definition_thmheading"
        captionCss := "definition_thmcaption"
        labelCss := "definition_thmlabel"
        contentCss := "definition_thmcontent"
      }
    | .proposition =>
      {
        kindText := s!"{nodeKind}"
        kindCss := "proposition"
        wrapperCss := "proposition_thmwrapper theorem-style-plain bp_kind_proposition bp_style_plain"
        headingCss := "proposition_thmheading"
        captionCss := "proposition_thmcaption"
        labelCss := "proposition_thmlabel"
        contentCss := "proposition_thmcontent"
      }
    | .theorem =>
      {
        kindText := s!"{nodeKind}"
        kindCss := "theorem"
        wrapperCss := "theorem_thmwrapper theorem-style-plain bp_kind_theorem bp_style_plain"
        headingCss := "theorem_thmheading"
        captionCss := "theorem_thmcaption"
        labelCss := "theorem_thmlabel"
        contentCss := "theorem_thmcontent"
      }
    | .lemma =>
      {
        kindText := s!"{nodeKind}"
        kindCss := "lemma"
        wrapperCss := "lemma_thmwrapper theorem-style-plain bp_kind_lemma bp_style_plain"
        headingCss := "lemma_thmheading"
        captionCss := "lemma_thmcaption"
        labelCss := "lemma_thmlabel"
        contentCss := "lemma_thmcontent"
      }
    | .corollary =>
      {
        kindText := s!"{nodeKind}"
        kindCss := "corollary"
        wrapperCss := "corollary_thmwrapper theorem-style-plain bp_kind_corollary bp_style_plain"
        headingCss := "corollary_thmheading"
        captionCss := "corollary_thmcaption"
        labelCss := "corollary_thmlabel"
        contentCss := "corollary_thmcontent"
      }

end BlockKindRenderStyle

private def blockKindRenderStyle (data : BlockData) : BlockKindRenderStyle :=
  BlockKindRenderStyle.ofInProgressKind data.kind

/-- Render the caption/label row shared by informal block shells. -/
def renderBlockTitleRow (style : BlockKindRenderStyle)
    (labelText numberText captionText : String) :
    Verso.Output.Html :=
  open Verso.Output.Html in
  let titleRowClass :=
    if style.showLabel then
      "bp_heading_title_row bp_heading_title_row_statement"
    else
      "bp_heading_title_row"
  let captionClass := s!"bp_caption bp_kind_{style.kindCss}_caption {style.captionCss}"
  let labelClass := s!"bp_label bp_kind_{style.kindCss}_label {style.labelCss}"
  {{
    <div class={{titleRowClass}}>
      <span class={{captionClass}} title={{labelText}}> {{.text true captionText}} </span>
      {{ if style.showLabel then {{<span class={{labelClass}}> {{.text true numberText}} </span>}} else .empty }}
    </div>
  }}

/-- Standard and custom Blueprint block header extra kinds. -/
inductive HeaderExtraKind where
  | group
  | uses
  | code
  | usedBy
  | custom (key : Lean.Name)
deriving Repr, Inhabited, BEq

def HeaderExtraKind.defaultOrder : HeaderExtraKind → Nat
  | .group => 10
  | .uses => 20
  | .usedBy => 30
  | .code => 40
  | .custom _ => 100

private def headerExtraCssSegment (raw : String) : String :=
  raw
    |>.replace "." "_"
    |>.replace ":" "_"
    |>.replace "/" "_"
    |>.replace " " "_"

def HeaderExtraKind.slotKey : HeaderExtraKind → String
  | .group => "group"
  | .uses => "uses"
  | .code => "code"
  | .usedBy => "used_by"
  | .custom key => s!"custom_{headerExtraCssSegment key.toString}"

def HeaderExtraKind.slotClass (kind : HeaderExtraKind) : String :=
  match kind with
  | .custom _ => s!"bp_extra_slot bp_extra_slot_custom bp_extra_slot_{kind.slotKey}"
  | _ => s!"bp_extra_slot bp_extra_slot_{kind.slotKey}"

/--
Rendered header content for a Blueprint block.

The block renderer owns layout and lifecycle-sensitive wrappers; callers provide
already-rendered content for standard extras or ordered project-specific extras.
-/
structure HeaderExtra where
  kind : HeaderExtraKind
  html : Verso.Output.Html
  order : Nat := kind.defaultOrder
  wrapperClass : String := ""

def HeaderExtra.ofHtml (kind : HeaderExtraKind) (html : Verso.Output.Html)
    (order : Nat := kind.defaultOrder) (wrapperClass : String := "") : HeaderExtra :=
  { kind, html, order, wrapperClass }

def HeaderExtra.group (html : Verso.Output.Html) : HeaderExtra :=
  HeaderExtra.ofHtml .group html

def HeaderExtra.uses (html : Verso.Output.Html) : HeaderExtra :=
  HeaderExtra.ofHtml .uses html

def HeaderExtra.code (html : Verso.Output.Html) : HeaderExtra :=
  HeaderExtra.ofHtml .code html

def HeaderExtra.usedBy (html : Verso.Output.Html) : HeaderExtra :=
  HeaderExtra.ofHtml .usedBy html

def HeaderExtra.custom (key : Lean.Name) (html : Verso.Output.Html)
    (order : Nat := HeaderExtraKind.defaultOrder (.custom key)) (wrapperClass : String := "") :
    HeaderExtra :=
  HeaderExtra.ofHtml (.custom key) html (order := order) (wrapperClass := wrapperClass)

/--
Standard Blueprint header extras plus a controlled extension point for
project-specific extras.
-/
structure HeaderExtras where
  group? : Option HeaderExtra := none
  uses? : Option HeaderExtra := none
  code? : Option HeaderExtra := none
  usedBy? : Option HeaderExtra := none
  custom : Array HeaderExtra := #[]

private def HeaderExtra.asStandard (kind : HeaderExtraKind) (extra : HeaderExtra) : HeaderExtra :=
  { extra with kind, order := kind.defaultOrder }

private def HeaderExtras.renderable (extras : HeaderExtras) : Array HeaderExtra :=
  let standard : Array HeaderExtra :=
    #[
      extras.group?.map (·.asStandard .group),
      extras.uses?.map (·.asStandard .uses),
      extras.usedBy?.map (·.asStandard .usedBy),
      extras.code?.map (·.asStandard .code)
    ].filterMap id
  (standard ++ extras.custom).qsort fun a b =>
    a.order < b.order || (a.order == b.order && a.kind.slotKey < b.kind.slotKey)

private def HeaderExtras.wrapperClass (extras : HeaderExtras) : String :=
  let classes := Id.run do
    let mut classes := #["bp_extras", "thm_header_extras"]
    if extras.group?.isSome then
      classes := classes.push "bp_extras_with_group"
    if extras.uses?.isSome then
      classes := classes.push "bp_extras_with_uses"
    if !extras.custom.isEmpty then
      classes := classes.push "bp_extras_with_custom"
    return classes
  String.intercalate " " classes.toList

private def renderHeaderExtraSlot (extra : HeaderExtra) : Verso.Output.Html :=
  open Verso.Output.Html in
  let slotClass :=
    if extra.wrapperClass.isEmpty then
      extra.kind.slotClass
    else
      s!"{extra.kind.slotClass} {extra.wrapperClass}"
  {{<span class={{slotClass}}>{{extra.html}}</span>}}

def renderStatementHeaderExtras (extras : HeaderExtras) : Verso.Output.Html :=
  open Verso.Output.Html in
  let renderable := extras.renderable
  if renderable.isEmpty then
    .empty
  else
    {{
      <div class={{extras.wrapperClass}}>
        {{renderable.map renderHeaderExtraSlot}}
      </div>
    }}

private def renderMetadataItem (key : String) (value : Verso.Output.Html) (extraClass : String := "") :
    Verso.Output.Html :=
  open Verso.Output.Html in
  let itemClass :=
    if extraClass.isEmpty then
      "bp_metadata_item"
    else
      s!"bp_metadata_item {extraClass}"
  {{
    <span class={{itemClass}}>
      <span class="bp_metadata_key">{{.text true key}}</span>
      {{value}}
    </span>
  }}

private def renderMetadataTextValue (value : String) : Verso.Output.Html :=
  {{<span class="bp_metadata_value">{{.text true value}}</span>}}

private def renderMetadataLinkValue (href : String) (label : String) : Verso.Output.Html :=
  {{<a class="bp_metadata_link bp_metadata_value" href={{href}}>{{.text true label}}</a>}}

private def renderMetadataCodeValue (value : Data.AuthorId) : Verso.Output.Html :=
  {{<span class="bp_metadata_value"><code>s!"{value}"</code></span>}}

private def renderMetadataCodeLinkValue (href : String) (value : Data.AuthorId) : Verso.Output.Html :=
  {{<a class="bp_metadata_link bp_metadata_value" href={{href}}><code>s!"{value}"</code></a>}}

private def renderOwnerMetadataItem (data : BlockData) : Verso.Output.Html :=
  open Verso.Output.Html in
  let avatar : Verso.Output.Html :=
    match data.ownerImageUrl with
    | some href => {{ <img class="bp_metadata_avatar" src={{href}} alt="" /> }}
    | none => .empty
  match data.ownerDisplayName, data.owner, data.ownerUrl with
  | some displayName, _, some href =>
    renderMetadataItem "Owner" (.seq #[avatar, renderMetadataLinkValue href displayName]) "bp_metadata_owner"
  | some displayName, _, none =>
    renderMetadataItem "Owner" (.seq #[avatar, renderMetadataTextValue displayName]) "bp_metadata_owner"
  | none, some owner, some href =>
    renderMetadataItem "Owner" (.seq #[avatar, renderMetadataCodeLinkValue href owner]) "bp_metadata_owner"
  | none, some owner, none =>
    renderMetadataItem "Owner" (.seq #[avatar, renderMetadataCodeValue owner]) "bp_metadata_owner"
  | _, _, _ => .empty

private def renderStatementMetadataPanel (data : BlockData) : Verso.Output.Html :=
  open Verso.Output.Html in
  let metadata := data.metadataPresentation
  let ownerItem := renderOwnerMetadataItem data
  let effortNode : Verso.Output.Html :=
    match metadata.effort with
    | some effort => renderMetadataItem "Effort" (renderMetadataTextValue effort)
    | none => .empty
  let priorityNode : Verso.Output.Html :=
    match metadata.priority with
    | some priority => renderMetadataItem "Priority" (renderMetadataTextValue priority)
    | none => .empty
  let prNode : Verso.Output.Html :=
    match metadata.prUrl with
    | some href => renderMetadataItem "PR" (renderMetadataLinkValue href "link")
    | none => .empty
  let tagNodes : Verso.Output.Html :=
    if metadata.tags.isEmpty then
      .empty
    else
      renderMetadataItem "Tags" {{
        <span class="bp_metadata_tags">
          {{metadata.tags.map (fun tag => {{ <span class="bp_metadata_tag">{{.text true tag}}</span> }})}}
        </span>
      }}
  if metadata.hasAny then
    {{
      <div class="bp_metadata_panel">
        {{ownerItem}}
        {{effortNode}}
        {{priorityNode}}
        {{tagNodes}}
        {{prNode}}
      </div>
    }}
  else
    .empty

/--
Context needed to render the reusable HTML shell for an informal Blueprint block.

Manual traversal remains responsible for resolving the values in this context:
HTML IDs, header extras, and the resolved display number.
-/
structure InformalBlockRenderContext where
  numberText : String
  captionText? : Option String := none
  attrs : Array (String × String) := #[]
  headerExtras : HeaderExtras := {}
  folded : Bool := false

/--
Genre-neutral inputs for the reusable Blueprint informal-block shell.

Callers own phase-specific data lookup and body rendering. This shell owns the
stable Blueprint wrapper, heading, title row, extras slot, metadata slot, and
content container assembly.
-/
structure InformalBlockShell where
  style : BlockKindRenderStyle
  labelText : String
  numberText : String
  captionText : String
  attrs : Array (String × String) := #[]
  titleRowAttrs? : Option (Array (String × String)) := none
  headerExtras : HeaderExtras := {}
  metadataPanel : Verso.Output.Html := .empty
  folded : Bool := false

private def renderShellTitleRow (shell : InformalBlockShell) : Verso.Output.Html :=
  let titleRow := renderBlockTitleRow shell.style shell.labelText shell.numberText shell.captionText
  match shell.titleRowAttrs? with
  | some attrs => .tag "a" attrs titleRow
  | none => titleRow

def renderInformalBlockShell (shell : InformalBlockShell)
    (content : Verso.Output.Html) : Verso.Output.Html :=
  open Verso.Output.Html in
  let style := shell.style
  let wrapperClass := s!"bp_wrapper bp_kind_{style.kindCss}_wrapper {style.kindCss}_thmwrapper {style.wrapperCss}"
  let headingClass := s!"bp_heading bp_kind_{style.kindCss}_heading {style.headingCss}"
  let contentClass := s!"bp_content bp_kind_{style.kindCss}_content {style.contentCss}"
  let titleRow := renderShellTitleRow shell
  let extras := renderStatementHeaderExtras shell.headerExtras
  if shell.folded then
    {{
      <details class={{wrapperClass}} title={{shell.labelText}} {{shell.attrs}}>
        <summary class={{headingClass}}>
          {{titleRow}}
          {{extras}}
        </summary>
        {{shell.metadataPanel}}
        <div class={{contentClass}}> {{content}} </div>
      </details>
    }}
  else
    {{
      <div class={{wrapperClass}} title={{shell.labelText}} {{shell.attrs}}>
        <div class={{headingClass}}>
          {{titleRow}}
          {{extras}}
        </div>
        {{shell.metadataPanel}}
        <div class={{contentClass}}> {{content}} </div>
      </div>
    }}

/--
Render the reusable HTML shell for an informal Blueprint block.

This deliberately has no dependency on Manual traversal state. Callers provide
already-rendered content plus the resolved metadata in
{name}`InformalBlockRenderContext`.
-/
def renderInformalBlockHtml (data : BlockData) (ctx : InformalBlockRenderContext)
    (content : Array Verso.Output.Html) : Verso.Output.Html :=
  open Verso.Output.Html in
  let style := blockKindRenderStyle data
  let labelText := s!"{data.label}"
  let headerExtras :=
    match data.kind with
    | .proof => {}
    | .statement _ => ctx.headerExtras
  let metadataPanel : Verso.Output.Html :=
    match data.kind with
    | .proof => .empty
    | .statement _ => renderStatementMetadataPanel data
  renderInformalBlockShell
    {
      style
      labelText
      numberText := ctx.numberText
      captionText := ctx.captionText?.getD style.kindText
      attrs := ctx.attrs
      headerExtras
      metadataPanel
      folded := ctx.folded
    }
    (.seq content)

end Informal
