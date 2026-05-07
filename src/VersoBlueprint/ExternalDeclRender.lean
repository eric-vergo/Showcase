/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual

open Lean Meta

namespace Informal

abbrev ExternalDeclHtml := Verso.Output.Html

inductive ExternalDeclRenderError where
  | moduleUnavailable (decl : Name)
  | exception (decl : Name) (message : String)
  deriving Repr, Inhabited

deriving instance Lean.ToJson for ExternalDeclRenderError
deriving instance Lean.FromJson for ExternalDeclRenderError

instance : Lean.Quote ExternalDeclRenderError where
  quote
    | .moduleUnavailable decl =>
        Lean.Syntax.mkApp (Lean.mkCIdent ``ExternalDeclRenderError.moduleUnavailable) #[Lean.quote decl]
    | .exception decl message =>
        Lean.Syntax.mkApp (Lean.mkCIdent ``ExternalDeclRenderError.exception) #[Lean.quote decl, Lean.quote message]

abbrev ExternalDeclRenderResult := Except ExternalDeclRenderError ExternalDeclHtml

def ExternalDeclRenderError.message : ExternalDeclRenderError → String
  | .moduleUnavailable decl => s!"module unavailable for {decl}"
  | .exception decl message => s!"{decl}: {message}"

private def runHighlightedHtml
    (html : Verso.Code.HighlightHtmlM Verso.Genre.Manual ExternalDeclHtml) : ExternalDeclHtml :=
  let ctx : Verso.Code.HighlightHtmlM.Context Verso.Genre.Manual := {
    linkTargets := {}
    traverseContext := { logError := fun _ => pure () }
    definitionIds := {}
    options := {}
  }
  let (html, hoverState) := ((html.run ctx).run {})
  inlineVersoHoverAttrs html hoverState.dedup
where
  /-
  Direct external declaration rendering is isolated from the page-level Verso hover table,
  so deduplicated hover ids would otherwise point at unrelated page content. Inline the
  resolved hover payloads locally to keep the rendered snippet self-contained.
  -/
  inlineVersoHoverAttrs
      (html : ExternalDeclHtml) (hoverDedup : Verso.Code.Hover.Dedup ExternalDeclHtml) :
      ExternalDeclHtml :=
    Id.run <|
      html.visitM (tag := fun name attrs contents => do
        let mut inlineHover? : Option ExternalDeclHtml := none
        let mut attrs' : Array (String × String) := #[]
        for (attr, value) in attrs do
          if attr == "data-verso-hover" then
            inlineHover? := value.toNat? >>= hoverDedup.get?
          else
            attrs' := attrs'.push (attr, value)
        let contents :=
          match inlineHover? with
          | some hoverHtml => contents ++ .tag "span" #[("class", "hover-info")] hoverHtml
          | none => contents
        pure <| some <| .tag name attrs' contents)

private def highlightedToHtml (h : SubVerso.Highlighting.Highlighted) : ExternalDeclHtml :=
  runHighlightedHtml (h.toHtml (g := Verso.Genre.Manual))

private def renderExternalDeclSignatureVariant
    (keywordText : String) (signature : SubVerso.Highlighting.Highlighted) : ExternalDeclHtml :=
  open Verso.Output.Html in
  {{
    <pre class="bp_external_decl_signature signature hl lean block">
      <span class="keyword token">{{.text true keywordText}}</span> " " {{highlightedToHtml signature}}
    </pre>
  }}

private def signatureToHtml (keywordText : String) (sig : Verso.Genre.Manual.Signature) :
    ExternalDeclHtml :=
  open Verso.Output.Html in
  {{
    <div class="bp_external_decl_signature_wrap">
      <div class="wide-only">{{renderExternalDeclSignatureVariant keywordText sig.wide}}</div>
      <div class="narrow-only">{{renderExternalDeclSignatureVariant keywordText sig.narrow}}</div>
    </div>
  }}

private def plainDocstringHtml (docs? : Option String) : ExternalDeclHtml :=
  open Verso.Output.Html in
  match docs? with
  | none => .empty
  | some docs =>
    {{<pre class="docstring">{{.text true docs}}</pre>}}

private def docsHtml (docs? : Option String) : ExternalDeclHtml :=
  open Verso.Output.Html in
  {{<div class="docs">{{plainDocstringHtml docs?}}</div>}}

private def renderTitledSection? (title : String) (rows : Array ExternalDeclHtml) :
    Option ExternalDeclHtml :=
  open Verso.Output.Html in
  if rows.isEmpty then
    none
  else
    some {{
      <h1>{{.text true title}}</h1>
      {{rows}}
    }}

private def kindMarkerOfDeclType : Verso.Genre.Manual.Block.Docstring.DeclType → String
  | .theorem => "theorem"
  | .axiom _ => "axiom"
  | .opaque _ => "opaque"
  | .def _ => "def"
  | .structure true .. => "class"
  | .structure false .. => "structure"
  | .inductive .. => "inductive"
  | .ctor .. => "constructor"
  | .recursor _ => "recursor"
  | .quotPrim _ => "primitive"
  | .other => "def"

private structure ExternalDeclPresentation where
  kindClass : String
  kindMarker : String
  keywordText : String

structure ExternalDeclHeaderBadge where
  className : String
  text : String

structure ExternalDeclHeaderSource where
  text : String
  href? : Option String := none

private def countMeta? (singular plural : String) (count : Nat) : Option String :=
  if count == 0 then
    none
  else
    some s!"{count} {if count == 1 then singular else plural}"

private def keywordTextOfDefinitionSafety (safety : DefinitionSafety) (base : String) : String :=
  match safety with
  | .unsafe => s!"unsafe {base}"
  | .partial => s!"partial {base}"
  | .safe => base

private def externalDeclPresentation
    (declType : Verso.Genre.Manual.Block.Docstring.DeclType) (cinfo : ConstantInfo) :
    ExternalDeclPresentation :=
  let kindMarker := kindMarkerOfDeclType declType
  match cinfo with
  | .defnInfo defn =>
    if defn.hints.isAbbrev then
      {
        kindClass := s!"{kindMarker} abbrev"
        kindMarker := "abbrev"
        keywordText := keywordTextOfDefinitionSafety defn.safety "abbrev"
      }
    else
      {
        kindClass := kindMarker
        kindMarker
        keywordText := keywordTextOfDefinitionSafety defn.safety "def"
      }
  | _ =>
      {
        kindClass := kindMarker
        kindMarker
        keywordText := kindMarker
      }

private def renderExternalDeclWrapper
    (decl : Name) (kindClass : String) (kindMarker : String)
    (signature : ExternalDeclHtml) (body : ExternalDeclHtml)
    (headerBadge? : Option ExternalDeclHeaderBadge := none)
    (headerMeta : Array String := #[])
    (headerSource? : Option ExternalDeclHeaderSource := none) : ExternalDeclHtml :=
  open Verso.Output.Html in
  let headerMetaHtml : ExternalDeclHtml :=
    if headerMeta.isEmpty then
      .empty
    else
      {{<span class="bp_external_decl_header_meta">{{.text true s!"({String.intercalate ", " headerMeta.toList})"}}</span>}}
  let headerSourceHtml : ExternalDeclHtml :=
    match headerSource? with
    | none => .empty
    | some source =>
      let sourceNode : ExternalDeclHtml :=
        match source.href? with
        | some href =>
          {{<a class="bp_external_decl_source_path" href={{href}}>{{.text true source.text}}</a>}}
        | none =>
          {{<span class="bp_external_decl_source_path">{{.text true source.text}}</span>}}
      {{
        <span class="bp_external_decl_source">
          "defined in " {{sourceNode}}
        </span>
      }}
  {{
    <div class={{s!"declaration decl {kindClass}"}} data-decl={{decl.toString}} data-kind={{kindMarker}}>
      <div class="bp_external_decl_kicker">
        <div class="bp_external_decl_kicker_main">
          <span class="bp_external_decl_kind">{{.text true kindMarker}}</span>
          {{headerMetaHtml}}
          {{headerSourceHtml}}
        </div>
        <div class="bp_external_decl_kicker_status">
          {{if let some badge := headerBadge? then
            {{<span class={{s!"bp_external_status_badge bp_external_decl_header_status {badge.className}"}}>{{.text true badge.text}}</span>}}
          else .empty}}
        </div>
      </div>
      {{signature}}
      <div class="bp_external_decl_body">{{body}}</div>
    </div>
  }}

private def visibilityHtml (v : Verso.Genre.Manual.Block.Docstring.Visibility) : ExternalDeclHtml :=
  open Verso.Output.Html in
  match v with
  | .public => .empty
  | .private => {{<span class="keyword">"private"</span>" "}}
  | .protected => .empty

private def renderDocNameCtor (docName : Verso.Genre.Manual.Block.Docstring.DocName) :
    ExternalDeclHtml :=
  open Verso.Output.Html in
  {{
    <div class="constructor">
      <pre class="name-and-type hl lean">{{highlightedToHtml docName.signature}}</pre>
      {{docsHtml docName.docstring?}}
    </div>
  }}

private def renderFieldSignature (field : Verso.Genre.Manual.Block.Docstring.FieldInfo) :
    ExternalDeclHtml :=
  open Verso.Output.Html in
  let inheritedInfo : ExternalDeclHtml :=
    if field.fieldFrom.isEmpty then
      .empty
    else
      let inheritedRows : Array ExternalDeclHtml :=
        field.fieldFrom.toArray.map fun parent =>
          {{<li><code>{{.text true parent.name.toString}}</code></li>}}
      {{
        <div class="inheritance docs">
          "Inherited from "
          <ol>{{inheritedRows}}</ol>
        </div>
      }}
  {{
    <section class="subdocs">
      <pre class="name-and-type hl lean">
        {{visibilityHtml field.visibility}}{{highlightedToHtml field.fieldName}} " : " {{highlightedToHtml field.type}}
      </pre>
      {{inheritedInfo}}
      {{docsHtml field.docString?}}
    </section>
  }}

private def renderParentsSection
    (parents : Array Verso.Genre.Manual.Block.Docstring.ParentInfo) :
    Option ExternalDeclHtml :=
  open Verso.Output.Html in
  if parents.isEmpty then
    none
  else
    let rows :=
      parents.map fun parent =>
        {{<li><code class="hl lean inline">{{highlightedToHtml parent.parent}}</code></li>}}
    some {{
      <h1>"Extends"</h1>
      <ul class="extends">{{rows}}</ul>
    }}

private def safetyHeaderMeta (cinfo : ConstantInfo) : Array String :=
  match cinfo with
  | .defnInfo defn =>
    match defn.safety with
    | .unsafe => #["unsafe"]
    | .partial => #["partial"]
    | .safe => #[]
  | _ => #[]

private def renderExternalDeclHeaderMeta
    (declType : Verso.Genre.Manual.Block.Docstring.DeclType) :
    Array String := Id.run do
  let mut items : Array String := #[]
  match declType with
  | .structure isClass _ _ fieldInfo _ parents =>
    if !parents.isEmpty then
      items := items.push s!"extends {parents.size}"
    let visibleFields := fieldInfo.filter (fun f => f.subobject?.isNone)
    if let some fieldCount := countMeta?
        (if isClass then "method" else "field")
        (if isClass then "methods" else "fields")
        visibleFields.size then
      items := items.push fieldCount
  | .inductive ctors numArgs propOnly =>
    if let some ctorCount := countMeta? "constructor" "constructors" ctors.size then
      items := items.push ctorCount
    if propOnly then
      items := items.push "Prop"
    if let some paramCount := countMeta? "parameter" "parameters" numArgs then
      items := items.push paramCount
  | _ => pure ()
  return items

private def renderDeclHtmlDocstringFromInfoE
    (decl : Name) (cinfo : ConstantInfo)
    (headerBadge? : Option ExternalDeclHeaderBadge := none)
    (headerSource? : Option ExternalDeclHeaderSource := none) : MetaM ExternalDeclRenderResult :=
  open Verso.Output.Html in do
  let env ← getEnv
  let declType ←
    withOptions (verso.docstring.allowMissing.set · true) <|
      Verso.Genre.Manual.Block.Docstring.DeclType.ofName decl (hideStructureConstructor := true)
  let signature ← Verso.Genre.Manual.Signature.forName decl
  let docs? ← liftM <| findDocString? env decl

  let ctorSection? : Option ExternalDeclHtml :=
    match declType with
    | .structure isClass ctor? _ _ _ _ =>
      ctor?.bind fun ctor =>
        let title := if isClass then "Instance Constructor" else "Constructor"
        renderTitledSection? title #[renderDocNameCtor ctor]
    | _ => none

  let methodsOrFieldsSection? : Option ExternalDeclHtml :=
    match declType with
    | .structure isClass _ _ fieldInfo _ _ =>
      let rows := fieldInfo.filter (fun f => f.subobject?.isNone) |>.map renderFieldSignature
      renderTitledSection? (if isClass then "Methods" else "Fields") rows
    | _ => none

  let parentsSection? : Option ExternalDeclHtml :=
    match declType with
    | .structure _ _ _ _ parents _ => renderParentsSection parents
    | _ => none

  let inductiveCtorsSection? : Option ExternalDeclHtml :=
    match declType with
    | .inductive ctors _ _ =>
      renderTitledSection? "Constructors" (ctors.map renderDocNameCtor)
    | _ => none

  let mut sections : Array ExternalDeclHtml := #[]
  if let some s := ctorSection? then
    sections := sections.push s
  if let some s := parentsSection? then
    sections := sections.push s
  if let some s := methodsOrFieldsSection? then
    sections := sections.push s
  if let some s := inductiveCtorsSection? then
    sections := sections.push s

  let presentation := externalDeclPresentation declType cinfo
  let signatureHtml := signatureToHtml presentation.keywordText signature
  let headerMeta := safetyHeaderMeta cinfo ++ renderExternalDeclHeaderMeta declType

  let body : ExternalDeclHtml :=
    if sections.isEmpty then
      plainDocstringHtml docs?
    else
      {{ {{plainDocstringHtml docs?}} {{sections}} }}
  pure <| .ok <| renderExternalDeclWrapper
    decl presentation.kindClass presentation.kindMarker signatureHtml body
    (headerBadge? := headerBadge?) (headerMeta := headerMeta) (headerSource? := headerSource?)

/--
Render one declaration directly from known declaration facts.
Errors represent rendering failures only; declaration lookup is handled by callers.
-/
def renderDeclHtmlDirectFromInfoE
    (decl : Name) (cinfo : ConstantInfo)
    (headerBadge? : Option ExternalDeclHeaderBadge := none)
    (headerSource? : Option ExternalDeclHeaderSource := none) : MetaM ExternalDeclRenderResult := do
  try
    renderDeclHtmlDocstringFromInfoE decl cinfo
      (headerBadge? := headerBadge?) (headerSource? := headerSource?)
  catch ex =>
    return .error (.exception decl (← ex.toMessageData.toString))

/--
String compatibility wrapper over `renderDeclHtmlDirectFromInfoE`.
Core external-rendering dataflow should use typed HTML payloads.
-/
def renderDeclHtmlStringDirectFromInfoE
    (decl : Name) (cinfo : ConstantInfo) : MetaM (Except ExternalDeclRenderError String) := do
  return (← renderDeclHtmlDirectFromInfoE decl cinfo).map (·.asString)

/-- Render one declaration directly from the in-memory `Environment` (no database, no source parsing). -/
def renderDeclHtmlNodeDirect? (decl : Name) : MetaM (Option ExternalDeclHtml) := do
  let decl := decl.eraseMacroScopes
  try
    let env ← getEnv
    let some cinfo := env.find? decl
      | return none
    match ← renderDeclHtmlDirectFromInfoE decl cinfo with
    | .ok html => return some html
    | .error err =>
      logError m!"External declaration rendering failed for {decl}: {err.message}"
      return none
  catch ex =>
    logError m!"External declaration rendering failed for {decl}: {← ex.toMessageData.toString}"
    return none

/-- String wrapper over `renderDeclHtmlNodeDirect?`. -/
def renderDeclHtmlStringDirect? (decl : Name) : MetaM (Option String) := do
  match ← renderDeclHtmlNodeDirect? decl with
  | some html => return some html.asString
  | none => return none

/--
Optional fallback path for non-`MetaM` contexts.
Database fallback is currently unavailable, so this returns `none`.
-/
def renderDeclHtmlNodeFromDb? (_dbPath : System.FilePath) (_decl : Name) :
    IO (Option ExternalDeclHtml) := do
  IO.eprintln "[external render db] fallback unavailable"
  return none

/-- Smoke demo targets: theorem/def (`Nat.add`), structure (`Prod`), and a missing name. -/
def externalDeclRenderSmokeDecls : Array Name := #[`Nat.add, `Prod, `No.Such.Declaration]

/-- Measure textual payload length in rendered declaration HTML. -/
def ExternalDeclHtml.textLength : ExternalDeclHtml → Nat
  | .text _ s => s.length
  | .tag _ _ content => textLength content
  | .seq contents => contents.foldl (fun acc child => acc + textLength child) 0

/-- Smoke demo helper for quick direct-path checks. -/
def runExternalDeclRenderSmokeDirect : MetaM (Array (Name × Option ExternalDeclHtml)) := do
  externalDeclRenderSmokeDecls.mapM fun decl => do
    let rendered? ← renderDeclHtmlNodeDirect? decl
    if let some html := rendered? then
      logInfo m!"[external decl render smoke] {decl}: rendered ({ExternalDeclHtml.textLength html} chars)"
    else
      logInfo m!"[external decl render smoke] {decl}: none"
    pure (decl, rendered?)

end Informal
