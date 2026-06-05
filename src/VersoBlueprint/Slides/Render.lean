/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Verso.Output.Html
import VersoBlueprint.PreviewManifest
import VersoBlueprint.Informal.Block.RelatedPanel
import VersoBlueprint.Informal.Block.Render

namespace Informal.Slides

open Lean
open Verso.Output
open Verso.Output.Html

private def slideNodeMarkerAttr : String := "data-bp-blueprint-node"
private def slideNodeMarkerValue : String := "true"

def blueprintSlideNodeMarkerAttrs : Array (String × String) :=
  #[(slideNodeMarkerAttr, slideNodeMarkerValue)]

private def Html.raw (html : String) : Html :=
  .text false html

private def trimSlashes (side : String) (text : String) : String :=
  let trimLeft (s : String) : String :=
    String.ofList <| s.toList.dropWhile (· == '/')
  let trimRight (s : String) : String :=
    String.ofList <| (s.toList.reverse.dropWhile (· == '/')).reverse
  let left :=
    if side == "left" || side == "both" then
      trimLeft text
    else
      text
  if side == "right" || side == "both" then
    trimRight left
  else
    left

private def isAbsoluteHref (href : String) : Bool :=
  href.startsWith "#"
    || href.startsWith "//"
    || href.contains "://"
    || href.startsWith "mailto:"
    || href.startsWith "tel:"

private def resolveBlueprintHref (href : Option String) (baseUrl : Option String) : Option String :=
  href.bind fun raw =>
    let raw := raw.trimAscii.toString
    if raw.isEmpty || isAbsoluteHref raw then
      some raw
    else
      match baseUrl with
      | some base =>
        let base := base.trimAscii.toString
        if base.isEmpty then some raw else some s!"{trimSlashes "right" base}/{trimSlashes "left" raw}"
      | none => some raw

private def nameString (name : Name) : String :=
  name.toString

private def containsName (values : Array Name) (label : Name) : Bool :=
  values.any (· == label)

private def statementPreviewKey (label : Name) : String :=
  Informal.PreviewCache.key label .statement

private def safePreviewId (idPrefix value : String) : String :=
  let trimHyphens (s : String) : String :=
    String.ofList <| (s.toList.dropWhile (· == '-')).reverse.dropWhile (· == '-') |>.reverse
  let isAllowed (c : Char) : Bool :=
    let v := c.val
    (v >= 'A'.val && v <= 'Z'.val) ||
      (v >= 'a'.val && v <= 'z'.val) ||
      (v >= '0'.val && v <= '9'.val) ||
      c == '_' || c == '-'
  let body :=
    value.toList.foldl
      (fun acc c => acc.push (if isAllowed c then c else '-'))
      ""
  s!"{idPrefix}-{trimHyphens body}"

private def splitDisplayTitle (entry : Informal.PreviewManifest.Entry) (titleOverride? : Option String) :
    String × String × String :=
  let title := (titleOverride?.getD entry.title).trimAscii.toString
  let kindText :=
    match entry.kind with
    | some kind => toString kind
    | none => "Blueprint"
  if title.isEmpty then
    let label := nameString entry.label
    (kindText, label, if label.isEmpty then kindText else s!"{kindText} {label}")
  else
    match title.splitOn " " with
    | [] => (kindText, title, title)
    | first :: rest =>
      let label := String.intercalate " " rest
      if label.isEmpty then (kindText, first, title) else (first, label, title)

private def entryIsBlockStatement (entry : Informal.PreviewManifest.Entry) : Bool :=
  match entry.targetKind, entry.facet with
  | .block, .statement => true
  | _, _ => false

private def entryByStatementLabel? (manifest : Informal.PreviewManifest.File) (label : Name) :
    Option Informal.PreviewManifest.Entry :=
  manifest.previews.find? fun entry =>
    entryIsBlockStatement entry && entry.label == label

private def dependencyAxis (entry : Informal.PreviewManifest.Entry) (label : Name) : Option String :=
  let inStatement := containsName entry.statementDeps label
  let inProof := containsName entry.proofDeps label
  match inStatement, inProof with
  | true, true => some "statement, proof"
  | false, true => some "proof"
  | true, false => some "statement"
  | false, false => none

private structure PanelItem where
  label : Name
  title : String
  href : Option String := none
  key : String
  axis : Option String := none

private def uniquePanelItems (items : Array PanelItem) : Array PanelItem :=
  let items := items.foldl
    (fun acc item =>
      if acc.any (fun existing => existing.label == item.label || existing.key == item.key) then
        acc
      else
        acc.push item)
    #[]
  items.qsort fun a b =>
    if a.title == b.title then nameString a.label < nameString b.label else a.title < b.title

private def dependencyEntries (manifest : Informal.PreviewManifest.File)
    (entry : Informal.PreviewManifest.Entry) : Array PanelItem :=
  let labels := (entry.statementDeps ++ entry.proofDeps).foldl
    (fun acc label => if acc.contains label then acc else acc.push label)
    #[]
  uniquePanelItems <| labels.map fun label =>
    let manifestEntry? := entryByStatementLabel? manifest label
    {
      label
      title := manifestEntry?.map (·.title) |>.getD (nameString label)
      href := manifestEntry?.bind (·.href)
      key := statementPreviewKey label
      axis := dependencyAxis entry label
    }

private def usedByEntries (manifest : Informal.PreviewManifest.File)
    (entry : Informal.PreviewManifest.Entry) : Array PanelItem :=
  uniquePanelItems <| manifest.previews.filterMap fun candidate =>
    if !entryIsBlockStatement candidate || candidate.label == entry.label then
      none
    else
      dependencyAxis candidate entry.label |>.map fun axis =>
        {
          label := candidate.label
          title := candidate.title
          href := candidate.href
          key := statementPreviewKey candidate.label
          axis := some axis
        }

private def groupEntries (manifest : Informal.PreviewManifest.File)
    (entry : Informal.PreviewManifest.Entry) : Array PanelItem :=
  match entry.parent with
  | none => #[]
  | some parent =>
    uniquePanelItems <| manifest.previews.filterMap fun candidate =>
      if entryIsBlockStatement candidate && candidate.parent == some parent then
        some {
          label := candidate.label
          title := candidate.title
          href := candidate.href
          key := statementPreviewKey candidate.label
        }
      else
        none

private def codeEntries (manifest : Informal.PreviewManifest.File)
    (entry : Informal.PreviewManifest.Entry) : Array Informal.PreviewManifest.Entry :=
  entry.leanCodePreviewKeys.filterMap fun key =>
    manifest.previews.find? fun candidate => candidate.key == key

private def panelEntry (item : PanelItem) (currentLabel : Name)
    (idPrefix : String) (baseUrl : Option String) : Informal.RelatedPanel.PanelEntry :=
  let label := nameString item.label
  let title := if item.title.trimAscii.toString.isEmpty then label else item.title
  let href := resolveBlueprintHref item.href baseUrl
  let previewId := safePreviewId idPrefix (if label.isEmpty then item.key else label)
  let axisBadge : Html :=
    match item.axis with
    | some axis =>
      {{<span class="bp_used_by_axis_badge">{{Html.ofString axis}}</span>}}
    | none => .empty
  {
    previewId
    previewKey := item.key
    previewTitle := title
    href
    metaHtml := {{
      <code>{{Html.ofString (if label.isEmpty then item.key else label)}}</code>
      {{axisBadge}}
    }}
    previewFallbackLabel? := some (if label.isEmpty then item.key else label)
    active := item.label == currentLabel
  }

private def renderSlidePanel (kind chipText chipTitle panelTitle panelMeta : String)
    (entries : Array PanelItem) (currentLabel : Name) (idPrefix : String)
    (baseUrl : Option String) : Html :=
  let panelEntries := entries.map fun item => panelEntry item currentLabel idPrefix baseUrl
  Informal.RelatedPanel.renderPanel {
    chipText := fun _ => chipText
    chipTitle := fun _ => chipTitle
    singleTitle := fun _ => chipTitle
    panelTitle := fun _ => panelTitle
    panelMeta
    wrapClass := "bp_used_by_wrap bp_slide_" ++ kind ++ "_wrap"
    panelAttrs := #[("data-bp-slide-panel", kind)]
    singleMode := .panel
  } panelEntries

private def renderGroupChip (manifest : Informal.PreviewManifest.File)
    (entry : Informal.PreviewManifest.Entry) (baseUrl : Option String) : Html :=
  match entry.parentTitle <|> entry.parent.map nameString with
  | none => .empty
  | some title =>
    let entries := groupEntries manifest entry
    renderSlidePanel
      "group"
      "group"
      s!"Other entries in group {title}"
      s!"Group: {title} ({entries.size})"
      "Hover another entry in this group to preview it."
      entries
      entry.label
      s!"bp-slide-group-{nameString entry.label}"
      baseUrl

private def renderCodeStatusChip (entry : Informal.PreviewManifest.Entry) (count : Nat) : Html :=
  if count == 0 then
    .empty
  else
    let previewKey := entry.leanCodePreviewKeys[0]?
    let previewTitle := nameString entry.label
    let chip : Html :=
      {{
        <span class="bp_code_link bp_code_link_status bp_code_link_status_proved"
            title={{s!"Lean declarations (available: {count})"}}>
          <span class="bp_code_status_symbol">"✓"</span>
          <span class="bp_code_link_label">"L∃∀N"</span>
        </span>
      }}
    let body : Html :=
      match previewKey with
      | some key =>
        .tag "span"
          #[ ("class", "bp_inline_preview_ref bp_slide_code_chip_preview")
           , ("data-bp-preview-id", safePreviewId "bp-slide-code" previewTitle)
           , ("data-bp-preview-title", previewTitle)
           , ("data-bp-preview-key", key)
           , ("tabindex", "0")
           , ("role", "button")
           , ("aria-label", "Lean declarations")
           ]
          chip
      | none => chip
    {{
      <span class="bp_code_summary_preview_root">{{body}}</span>
    }}

private def renderUsesChip (manifest : Informal.PreviewManifest.File)
    (entry : Informal.PreviewManifest.Entry) (baseUrl : Option String) : Html :=
  let entries := dependencyEntries manifest entry
  if entries.isEmpty then
    .empty
  else
    let count := entries.size
    renderSlidePanel
      "uses"
      s!"uses {count}"
      "Statement and proof dependencies"
      s!"Uses {count}"
      "Hover a dependency to preview it."
      entries
      Name.anonymous
      "bp-slide-uses"
      baseUrl

private def renderUsedByChip (manifest : Informal.PreviewManifest.File)
    (entry : Informal.PreviewManifest.Entry) (baseUrl : Option String) : Html :=
  let entries := usedByEntries manifest entry
  let count := entries.size
  if count == 0 then
    {{
      <span class="bp_used_by_chip bp_used_by_chip_empty" title="Reverse dependencies">
        {{Html.ofString s!"used by {count}"}}
      </span>
    }}
  else
    renderSlidePanel
      "used-by"
      s!"used by {count}"
      "Reverse dependencies"
      s!"Used by {count}"
      "Hover a use site to preview it."
      entries
      Name.anonymous
      "bp-slide-used-by"
      baseUrl

private def renderExtras (manifest : Informal.PreviewManifest.File)
    (entry : Informal.PreviewManifest.Entry) (codeCount : Nat) (baseUrl : Option String) : Html :=
  let group := renderGroupChip manifest entry baseUrl
  let uses := renderUsesChip manifest entry baseUrl
  let code := renderCodeStatusChip entry codeCount
  let usedBy := renderUsedByChip manifest entry baseUrl
  Informal.renderStatementHeaderExtras {
    group? := if group == .empty then none else some <| Informal.HeaderExtra.group group
    uses? := if uses == .empty then none else some <| Informal.HeaderExtra.uses uses
    code? := if code == .empty then none else some <| Informal.HeaderExtra.code code
    usedBy? := if usedBy == .empty then none else some <| Informal.HeaderExtra.usedBy usedBy
  }

private def renderCodeBadge (count : Nat) : Html :=
  if count == 0 then
    .empty
  else
    let noun := if count == 1 then "theorem" else "declarations"
    {{
      <span class="bp_code_summary_indicator">
        <span class="bp_external_status_badge bp_external_status_badge_summary bp_external_status_ok"
            title={{s!"Lean declarations: {count} available"}}>
          <span class="bp_external_status_icon bp_external_status_ok">"●"</span>
          <span class="bp_external_status_badge_text">{{Html.ofString s!"{count} {noun}"}}</span>
        </span>
      </span>
    }}

private def renderCodePanel (entry : Informal.PreviewManifest.Entry)
    (codeEntries : Array Informal.PreviewManifest.Entry) (caption label : String) : Html :=
  if codeEntries.isEmpty then
    .empty
  else
    let codeHtml := codeEntries.map (fun codeEntry => Html.raw codeEntry.html)
    {{
      <div class="bp_wrapper bp_code_panel_wrapper">
        <details class="bp_code_block bp_code_panel" open>
          <summary class="bp_heading lemma_thmheading" title={{"Lean code for " ++ nameString entry.label}}>
            <span class="bp_heading_title_row">
              <span class="bp_caption lemma_thmcaption bp_code_summary_text">
                {{Html.ofString s!"Lean code for {caption}"}}
              </span>
              <span class="bp_label lemma_thmlabel bp_code_summary_label">
                {{Html.ofString label}}
              </span>
            </span>
            {{renderCodeBadge codeEntries.size}}
          </summary>
          <div class="bp_slide_code_body">{{codeHtml}}</div>
        </details>
      </div>
    }}

private def renderNotice (kind title detail : String) : Html :=
  {{
    <div class={{"bp_slide_node_notice bp_slide_node_notice_" ++ kind}}>
      <strong>{{Html.ofString title}}</strong><br/>
      {{Html.ofString detail}}
    </div>
  }}

private def renderEntryShell (manifest : Informal.PreviewManifest.File)
    (entry : Informal.PreviewManifest.Entry) (titleOverride? siteBase? : Option String)
    (compact : Bool) : Html :=
  let isProof := entry.facet == .proof
  let renderKind :=
    if isProof then
      Informal.Data.InProgressKind.proof
    else
      .statement (entry.kind.getD .theorem)
  let style := Informal.BlockKindRenderStyle.ofInProgressKind renderKind
  let (caption, label, _title) := splitDisplayTitle entry titleOverride?
  let href := resolveBlueprintHref entry.href siteBase?
  let codeEntries := if compact then #[] else codeEntries manifest entry
  let titleRow : Html :=
    if isProof then
      {{
        <div class="bp_heading_title_row">
          <span class="bp_caption bp_kind_proof_caption proof_caption" title={{nameString entry.label}}>
            "Proof"
          </span>
        </div>
      }}
    else
      {{
        <div class="bp_heading_title_row bp_heading_title_row_statement">
          <span class={{"bp_caption bp_kind_" ++ style.kindCss ++ "_caption " ++ style.captionCss}}
              title={{nameString entry.label}}>
            {{Html.ofString caption}}
          </span>
          <span class={{"bp_label bp_kind_" ++ style.kindCss ++ "_label " ++ style.labelCss}}>
            {{Html.ofString label}}
          </span>
        </div>
      }}
  let linkedTitleRow : Html :=
    match href with
    | some href =>
      .tag "a"
        #[ ("class", "bp_slide_node_heading_link")
         , ("data-bp-slide-link", "blueprint")
         , ("href", href)
         , ("target", "bp-slide-blueprint")
         , ("rel", "noopener")
         , ("title", "Open Blueprint node")
         ]
        titleRow
    | none => titleRow
  let heading : Html :=
    {{
      <div class={{"bp_heading bp_kind_" ++ style.kindCss ++ "_heading " ++ style.headingCss}}>
        {{linkedTitleRow}}
        {{ if isProof then .empty else renderExtras manifest entry codeEntries.size siteBase? }}
      </div>
    }}
  let wrapperClass := s!"bp_wrapper bp_kind_{style.kindCss}_wrapper {style.kindCss}_thmwrapper {style.wrapperCss}"
  let contentClass := s!"bp_content bp_kind_{style.kindCss}_content {style.contentCss}"
  {{
    <div class="bp_slide_node_blueprint">
      <div class={{wrapperClass}} title={{nameString entry.label}}>
        {{heading}}
        <div class={{contentClass}}>{{Html.raw entry.html}}</div>
      </div>
      {{renderCodePanel entry codeEntries caption label}}
    </div>
  }}

private structure PlaceholderConfig where
  label : String
  facet : String
  key : String
  title? : Option String := none
  compact : Bool := false
  siteBase? : Option String := none

private def unescapeAttr (value : String) : String :=
  value
    |>.replace "&quot;" "\""
    |>.replace "&amp;" "&"

private def attrValue? (tag name : String) : Option String :=
  match tag.splitOn (name ++ "=\"") with
  | _ :: valueAndMore :: _ =>
    match valueAndMore.splitOn "\"" with
    | value :: _ => some (unescapeAttr value)
    | _ => none
  | _ => none

private def placeholderConfig? (tag : String) : Option PlaceholderConfig := do
  let marker ← attrValue? tag slideNodeMarkerAttr
  guard (marker == slideNodeMarkerValue)
  let label ← attrValue? tag "data-bp-label"
  let facet := attrValue? tag "data-bp-facet" |>.getD "statement"
  let key := attrValue? tag "data-bp-preview-key" |>.getD s!"{label}--{facet}"
  let title? := attrValue? tag "data-bp-title"
  let compact := attrValue? tag "data-bp-compact" == some "true"
  let siteBase? := attrValue? tag "data-bp-site-base"
  some { label, facet, key, title?, compact, siteBase? }

private def renderedNodeAttrs (cfg : PlaceholderConfig) : Array (String × String) :=
  #[ ("class", if cfg.compact then "bp_slide_node bp_slide_node_compact" else "bp_slide_node")
   , ("data-bp-label", cfg.label)
   , ("data-bp-facet", cfg.facet)
   , ("data-bp-preview-key", cfg.key)
   , ("data-bp-compact", if cfg.compact then "true" else "false")
   , ("data-bp-rendered", "static")
   ] ++
   (cfg.title?.map (fun title => #[("data-bp-title", title)] ) |>.getD #[]) ++
   (cfg.siteBase?.map (fun siteBase => #[("data-bp-site-base", siteBase)] ) |>.getD #[])

private def renderMissingNode (cfg : PlaceholderConfig) (title detail : String) : Html :=
  .tag "div" (renderedNodeAttrs cfg) (renderNotice "error" title detail)

private def renderPlaceholder (manifest? : Option Informal.PreviewManifest.File)
    (cfg : PlaceholderConfig) : Html :=
  match manifest? with
  | none =>
    renderMissingNode cfg "Preview manifest unavailable"
      "Pass previewManifest? to slidesMainWithBlueprintPreviews so Blueprint slide nodes can be rendered during slide generation."
  | some manifest =>
    match manifest.previews.find? (fun entry => entry.key == cfg.key) with
    | none =>
      renderMissingNode cfg "Blueprint node not found" cfg.key
    | some entry =>
      .tag "div" (renderedNodeAttrs cfg)
        (renderEntryShell manifest entry cfg.title? cfg.siteBase? cfg.compact)

/--
Replace the first generated placeholder emitted by `blueprint_node`.

Verso Slides does not expose a raw-HTML block extension, so the slide wrapper
post-processes the deterministic `<div ... data-bp-blueprint-node="true">`
shape that this package emits. The placeholder body is a simple fallback
paragraph, so the first closing `</div>` belongs to the placeholder itself.
-/
private def replaceFirstPlaceholder? (manifest? : Option Informal.PreviewManifest.File)
    (html : String) : Option String := do
  let marker := s!"{slideNodeMarkerAttr}=\"{slideNodeMarkerValue}\""
  let beforeMarker :: afterMarker :: _ := html.splitOn marker
    | none
  let beforeParts := beforeMarker.splitOn "<div"
  let startTagLeft ← beforeParts.getLast?
  let beforeStart := String.intercalate "<div" beforeParts.dropLast
  let afterStartParts := afterMarker.splitOn ">"
  let startTagRight ← afterStartParts.head?
  let afterStart := String.intercalate ">" (afterStartParts.drop 1)
  let tag := "<div" ++ startTagLeft ++ marker ++ startTagRight ++ ">"
  let cfg ← placeholderConfig? tag
  let afterEndParts := afterStart.splitOn "</div>"
  let _placeholderBody ← afterEndParts.head?
  let afterEnd := String.intercalate "</div>" (afterEndParts.drop 1)
  let rendered := (renderPlaceholder manifest? cfg).asString
  some (beforeStart ++ rendered ++ afterEnd)

partial def renderBlueprintSlideNodesInHtml
    (manifest? : Option Informal.PreviewManifest.File) (html : String) : String :=
  match replaceFirstPlaceholder? manifest? html with
  | none => html
  | some html' => renderBlueprintSlideNodesInHtml manifest? html'

def readBlueprintPreviewManifest (path : System.FilePath) :
    IO Informal.PreviewManifest.File := do
  let json ←
    match Json.parse (← IO.FS.readFile path) with
    | .ok json => pure json
    | .error err => throw <| IO.userError s!"could not parse Blueprint preview manifest {path}: {err}"
  match fromJson? (α := Informal.PreviewManifest.File) json with
  | .ok file => pure file
  | .error err => throw <| IO.userError s!"could not decode Blueprint preview manifest {path}: {err}"

def renderBlueprintSlideNodesInFile
    (indexPath : System.FilePath)
    (manifest? : Option Informal.PreviewManifest.File) : IO Unit := do
  let html ← IO.FS.readFile indexPath
  IO.FS.writeFile indexPath (renderBlueprintSlideNodesInHtml manifest? html)

end Informal.Slides
