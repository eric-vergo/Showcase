/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean

/-!
# Restricted YAML parser for `formalization.yaml`

Parses the subset of YAML that the `formalization.yaml` v0.3 standard
(https://github.com/mathlib-initiative/formalization.yaml) actually uses into
`Lean.Json`. No YAML library exists in this dependency tree, and a full YAML
implementation is far more than the standard needs, so this module deliberately
implements only the constructs the schema exercises. Unknown *keys* are fine
(the schema is open; everything parses generically into `Json`); unsupported
*constructs* fail with an error naming the offending line.

Supported subset:
- `#` comments: full-line, and trailing after a scalar value (a `#` inside a
  quoted string is content; a comment `#` must be at line start or preceded by
  whitespace);
- `key: value` entries with double-quoted strings (`\"`/`\\`/`\n`/`\t`
  escapes), single-quoted strings (`''` escape), unquoted strings, integers,
  `true`/`false`, `null`/`~`, and empty values (both parse to `null`);
- nested maps, one map per indentation level (any consistent deeper indent);
- inline lists `[a, "b", 3]` of scalars (nesting allowed);
- block lists: `- scalar` items and `- key: value` item-maps whose continuation
  fields align with the first key after the dash; a bare `-` introduces a
  nested node on the following deeper-indented lines;
- folded (`>`, `>-`) and literal (`|`, `|-`) block scalars: continuation lines
  indented deeper than the key. Folded style joins lines with spaces; literal
  style joins with newlines; blank continuation lines become a single `\n`
  break in both styles. The `-` chomp drops the trailing newline; without it a
  single trailing newline is kept.
- a single leading `---` document-start marker (skipped).

Not supported (each fails with a line-numbered error): anchors/aliases/tags
(`&`, `*`, `!`), flow mappings `{...}`, multi-document streams, tab
indentation, quoted or non-identifier keys, multi-line plain scalars, and
`>+`/`|+` chomping. Floats are not distinguished: unquoted numeric-looking
values that are not integers stay strings.
-/

namespace Informal.FormalizationYaml

open Lean

/-- Drop ASCII whitespace from both ends of `s`. -/
def trim (s : String) : String :=
  let isWs := fun c => c == ' ' || c == '\t' || c == '\r' || c == '\n'
  String.ofList (((s.toList.dropWhile isWs).reverse.dropWhile isWs).reverse)

/-- Number of leading spaces (the YAML indentation of a line). -/
private def countIndent (s : String) : Nat :=
  (s.toList.takeWhile (· == ' ')).length

/-- Blank lines and full-line comments carry no structure outside block scalars. -/
private def isIgnorableLine (raw : String) : Bool :=
  let t := trim raw
  t.isEmpty || t.startsWith "#"

/--
Strip a trailing `# comment` from a key/value line, honoring double/single
quotes (a `#` inside a quoted string is content). A comment starts at a `#`
that is at the line start or preceded by whitespace, outside any quotes.
Returns the trimmed remainder.
-/
private def stripTrailingComment (s : String) : String := Id.run do
  let mut out : String := ""
  let mut inDouble := false
  let mut inSingle := false
  let mut escaped := false
  let mut prevWs := true
  for c in s.toList do
    if inDouble then
      out := out.push c
      if escaped then escaped := false
      else if c == '\\' then escaped := true
      else if c == '"' then inDouble := false
    else if inSingle then
      out := out.push c
      if c == '\'' then inSingle := false
    else if c == '#' && prevWs then
      break
    else
      out := out.push c
      if c == '"' then inDouble := true
      else if c == '\'' then inSingle := true
    prevWs := c == ' ' || c == '\t'
  return trim out

private def unquoteDouble (lineNo : Nat) : List Char → String → Except String String
  | [], _ => .error s!"line {lineNo}: unterminated double-quoted string"
  | ['\\'], _ => .error s!"line {lineNo}: dangling escape in double-quoted string"
  | '\\' :: c :: rest, acc =>
    let c' := if c == 'n' then '\n' else if c == 't' then '\t' else c
    unquoteDouble lineNo rest (acc.push c')
  | '"' :: rest, acc =>
    if (trim (String.ofList rest)).isEmpty then .ok acc
    else .error s!"line {lineNo}: unexpected content after closing double quote"
  | c :: rest, acc => unquoteDouble lineNo rest (acc.push c)

private def unquoteSingle (lineNo : Nat) : List Char → String → Except String String
  | [], _ => .error s!"line {lineNo}: unterminated single-quoted string"
  | '\'' :: '\'' :: rest, acc => unquoteSingle lineNo rest (acc.push '\'')
  | '\'' :: rest, acc =>
    if (trim (String.ofList rest)).isEmpty then .ok acc
    else .error s!"line {lineNo}: unexpected content after closing single quote"
  | c :: rest, acc => unquoteSingle lineNo rest (acc.push c)

/-- Split an inline-list body on commas that sit outside quotes and brackets. -/
private def splitTopLevelCommas (s : String) : List String := Id.run do
  let mut parts : List String := []
  let mut cur := ""
  let mut depth : Nat := 0
  let mut inDouble := false
  let mut inSingle := false
  let mut escaped := false
  for c in s.toList do
    if inDouble then
      cur := cur.push c
      if escaped then escaped := false
      else if c == '\\' then escaped := true
      else if c == '"' then inDouble := false
    else if inSingle then
      cur := cur.push c
      if c == '\'' then inSingle := false
    else if c == ',' && depth == 0 then
      parts := cur :: parts
      cur := ""
    else
      cur := cur.push c
      if c == '"' then inDouble := true
      else if c == '\'' then inSingle := true
      else if c == '[' then depth := depth + 1
      else if c == ']' then depth := depth - 1
  return (cur :: parts).reverse

/-- Parse one inline scalar (or inline list of scalars). Input is comment-stripped. -/
private partial def parseScalar (lineNo : Nat) (s : String) : Except String Json := do
  let s := trim s
  if s.isEmpty || s == "null" || s == "~" then
    return Json.null
  else if s == "true" then
    return Json.bool true
  else if s == "false" then
    return Json.bool false
  else if s.startsWith "\"" then
    return Json.str (← unquoteDouble lineNo (s.toList.drop 1) "")
  else if s.startsWith "'" then
    return Json.str (← unquoteSingle lineNo (s.toList.drop 1) "")
  else if s.startsWith "[" then
    if !s.endsWith "]" then
      throw s!"line {lineNo}: unterminated inline list"
    let inner := trim ((s.drop 1).dropEnd 1).toString
    if inner.isEmpty then
      return Json.arr #[]
    let items ← (splitTopLevelCommas inner).mapM (parseScalar lineNo)
    return Json.arr items.toArray
  else if s.startsWith "{" then
    throw s!"line {lineNo}: flow mappings are not supported by the formalization.yaml subset parser"
  else if s.startsWith "&" || s.startsWith "*" || s.startsWith "!" then
    throw s!"line {lineNo}: YAML anchors/aliases/tags are not supported by the formalization.yaml subset parser"
  else
    match s.toInt? with
    | some n => return toJson n
    | none => return Json.str s

/-- Split `key: rest` at the first `:` that ends the line or is followed by a space. -/
private def splitKeyAux : List Char → String → Option (String × String)
  | [], _ => none
  | ':' :: rest, key =>
    match rest with
    | [] => some (key, "")
    | ' ' :: rest' => some (key, String.ofList rest')
    | _ => none
  | c :: rest, key => splitKeyAux rest (key.push c)

private def isPlainKeyChar (c : Char) : Bool :=
  c.isAlphanum || c == '_' || c == '-' || c == '.'

/-- Recognize a plain (unquoted, identifier-like) `key: value` split. -/
private def splitKey? (s : String) : Option (String × String) := do
  let (key, rest) ← splitKeyAux s.toList ""
  let key := trim key
  if key.isEmpty || !(key.toList.all isPlainKeyChar) then none
  else some (key, rest)

private def skipIgnorable (lines : Array (Nat × String)) (i : Nat) : Nat := Id.run do
  let mut j := i
  while h : j < lines.size do
    if isIgnorableLine (lines[j]).2 then j := j + 1 else break
  return j

/--
Consume a folded/literal block scalar's continuation lines: every following
line that is blank or indented deeper than `indent`. Returns the scalar and
the index of the first line after it.
-/
private def parseBlockScalar (lines : Array (Nat × String)) (start : Nat) (indent : Nat)
    (style : String) : Json × Nat := Id.run do
  let mut items : Array (Option String) := #[]
  let mut i := start
  let mut contentIndent : Option Nat := none
  while h : i < lines.size do
    let raw := (lines[i]).2
    if (trim raw).isEmpty then
      items := items.push none
      i := i + 1
    else if countIndent raw > indent then
      let ci :=
        match contentIndent with
        | some ci => ci
        | none => countIndent raw
      contentIndent := some ci
      items := items.push (some (raw.drop (Nat.min ci (countIndent raw))).toString)
      i := i + 1
    else
      break
  while !items.isEmpty && items.back!.isNone do
    items := items.pop
  let chomp := style.endsWith "-"
  let literal := style.startsWith "|"
  let mut out := ""
  let mut pendingBreak := false
  for item in items do
    match item with
    | none =>
      if !out.isEmpty then pendingBreak := true
    | some l =>
      let l := if literal then l else trim l
      if out.isEmpty then out := l
      else if pendingBreak || literal then out := out ++ "\n" ++ l
      else out := out ++ " " ++ l
      pendingBreak := false
  let chomped := if chomp || out.isEmpty then out else out ++ "\n"
  return (Json.str chomped, i)

mutual

/-- Parse the node (map or block list) whose first significant line is `lines[i]`. -/
private partial def parseNode (lines : Array (Nat × String)) (i : Nat) :
    Except String (Json × Nat) := do
  let raw := (lines[i]!).2
  let ind := countIndent raw
  let t := trim raw
  if t == "-" || t.startsWith "- " then
    parseListItems lines i ind #[]
  else
    parseMapEntries lines i ind #[]

/-- Parse consecutive `key: value` entries at exactly `indent` spaces. -/
private partial def parseMapEntries (lines : Array (Nat × String)) (i : Nat) (indent : Nat)
    (acc : Array (String × Json)) : Except String (Json × Nat) := do
  let i := skipIgnorable lines i
  if h : i < lines.size then
    let (no, raw) := lines[i]
    let ind := countIndent raw
    if ind < indent then
      return (Json.mkObj acc.toList, i)
    if ind > indent then
      throw s!"line {no}: unexpected indentation ({ind} spaces where {indent} were expected); multi-line plain scalars are not supported"
    let content := stripTrailingComment raw
    if content == "-" || content.startsWith "- " then
      throw s!"line {no}: unexpected list item; expected a 'key: value' mapping entry"
    let some (key, rest) := splitKey? content
      | throw s!"line {no}: expected 'key: value', got '{content}'"
    if acc.any (fun kv => kv.1 == key) then
      throw s!"line {no}: duplicate key '{key}'"
    let restT := trim rest
    if restT.isEmpty then
      -- Nested value (deeper map/list), same-indent block list, or empty (null).
      let j := skipIgnorable lines (i + 1)
      if hj : j < lines.size then
        let raw2 := (lines[j]).2
        let ind2 := countIndent raw2
        let t2 := trim raw2
        if ind2 > indent then
          let (v, k) ← parseNode lines j
          parseMapEntries lines k indent (acc.push (key, v))
        else if ind2 == indent && (t2 == "-" || t2.startsWith "- ") then
          let (v, k) ← parseListItems lines j indent #[]
          parseMapEntries lines k indent (acc.push (key, v))
        else
          parseMapEntries lines (i + 1) indent (acc.push (key, Json.null))
      else
        parseMapEntries lines (i + 1) indent (acc.push (key, Json.null))
    else if restT == ">" || restT == ">-" || restT == "|" || restT == "|-" then
      let (v, k) := parseBlockScalar lines (i + 1) indent restT
      parseMapEntries lines k indent (acc.push (key, v))
    else if restT.startsWith ">" || restT.startsWith "|" then
      throw s!"line {no}: unsupported block scalar header '{restT}' (only '>', '>-', '|', '|-' are supported)"
    else
      let v ← parseScalar no restT
      parseMapEntries lines (i + 1) indent (acc.push (key, v))
  else
    return (Json.mkObj acc.toList, i)

/-- Parse consecutive `- item` entries at exactly `indent` spaces. -/
private partial def parseListItems (lines : Array (Nat × String)) (i : Nat) (indent : Nat)
    (acc : Array Json) : Except String (Json × Nat) := do
  let i := skipIgnorable lines i
  if h : i < lines.size then
    let (no, raw) := lines[i]
    let ind := countIndent raw
    let t := trim raw
    if ind != indent || !(t == "-" || t.startsWith "- ") then
      if ind > indent then
        throw s!"line {no}: unexpected indentation inside a block list"
      return (Json.arr acc, i)
    let afterDash := (raw.drop (ind + 1)).toString
    let sp := countIndent afterDash
    let itemText := (afterDash.drop sp).toString
    -- Column of the item's first content char; item-map continuation fields align here.
    let itemCol := ind + 1 + sp
    if (trim itemText).isEmpty then
      -- Bare '-': the item is a nested node on the following deeper-indented lines.
      let j := skipIgnorable lines (i + 1)
      if hj : j < lines.size then
        if countIndent (lines[j]).2 > ind then
          let (v, k) ← parseNode lines j
          parseListItems lines k indent (acc.push v)
        else
          parseListItems lines (i + 1) indent (acc.push Json.null)
      else
        parseListItems lines (i + 1) indent (acc.push Json.null)
    else
      let content := stripTrailingComment itemText
      match splitKey? content with
      | some (key, rest) =>
        -- Item map: first entry on the dash line, continuation fields at `itemCol`.
        let restT := trim rest
        if restT == ">" || restT == ">-" || restT == "|" || restT == "|-" then
          let (v, k) := parseBlockScalar lines (i + 1) itemCol restT
          let (obj, k') ← parseMapEntries lines k itemCol #[(key, v)]
          parseListItems lines k' indent (acc.push obj)
        else
          let v ← if restT.isEmpty then pure Json.null else parseScalar no restT
          let (obj, k) ← parseMapEntries lines (i + 1) itemCol #[(key, v)]
          parseListItems lines k indent (acc.push obj)
      | none =>
        let v ← parseScalar no content
        parseListItems lines (i + 1) indent (acc.push v)
  else
    return (Json.arr acc, i)

end

/-! ## A structural subset check derived from the v0.4 schema

Not a validator. `check-jsonschema` against the published schema is the validator, and a
project that wants one runs it in CI; this is a hand-written check of the *shape* of the
fields the v0.4 standard requires and constrains, written so a site build can refuse to
render a document it cannot read honestly.

Two consequences of "subset", both deliberate:

- It checks what the schema states as required fields, types, enumerations and array
  minimums. It does not check formats, string lengths, uniqueness, or `alignment`, which the
  standard leaves freeform on purpose.
- Extra keys are fine everywhere, because the schema is open. A v0.3 document passes when
  its required fields are there; its `author_contacted` and `prior_work` keys are simply not
  the check's business.

Every surface that reports having run this says exactly what it is: a subset check derived
from the v0.4 JSON Schema, not a general validator.
-/

/-- The sentence every surface prints about what this check is. -/
def validationProvenance : String :=
  "a subset check derived from the v0.4 JSON Schema, not a general validator"

/-- Present and not the parser's reading of an empty value. -/
private def present (j : Json) (key : String) : Bool :=
  match (j.getObjVal? key).toOption with
  | Option.none | Option.some Json.null => false
  | _ => true

private def strCheck (path : String) (j : Json) (key : String) (required : Bool := false) :
    Array String :=
  match (j.getObjVal? key).toOption with
  | Option.none | Option.some Json.null =>
    if required then #[s!"{path}{key} is required"] else #[]
  | Option.some (Json.str s) =>
    if (trim s).isEmpty then #[s!"{path}{key} must not be empty"] else #[]
  | Option.some _ => #[s!"{path}{key} must be a string"]

/-- A `string | number` field, which the schema uses for costs. -/
private def scalarCheck (path : String) (j : Json) (key : String) : Array String :=
  match (j.getObjVal? key).toOption with
  | Option.none | Option.some Json.null => #[]
  | Option.some (Json.str _) | Option.some (Json.num _) => #[]
  | Option.some _ => #[s!"{path}{key} must be a string or a number"]

private def natCheck (path : String) (j : Json) (key : String) : Array String :=
  match (j.getObjVal? key).toOption with
  | Option.none | Option.some Json.null => #[]
  | Option.some (Json.num _) =>
    match (j.getObjValAs? Nat key).toOption with
    | Option.some _ => #[]
    | Option.none => #[s!"{path}{key} must be a non-negative integer"]
  | Option.some _ => #[s!"{path}{key} must be a non-negative integer"]

/-- The schema's enumerations all admit `""` as "not stated". -/
private def enumCheck (path : String) (j : Json) (key : String) (allowed : List String)
    (required : Bool := false) : Array String :=
  match (j.getObjVal? key).toOption with
  | Option.none | Option.some Json.null =>
    if required then #[s!"{path}{key} is required"] else #[]
  | Option.some (Json.str s) =>
    if s.isEmpty && !required then #[]
    else if allowed.contains s then #[]
    else #[s!"{path}{key} must be one of {String.intercalate ", " allowed} (found '{s}')"]
  | Option.some _ => #[s!"{path}{key} must be a string"]

/-- An array of non-empty strings, optionally required and optionally non-empty itself. -/
private def strArrayCheck (path : String) (j : Json) (key : String) (required : Bool := false)
    (minItems : Nat := 0) : Array String := Id.run do
  match (j.getObjVal? key).toOption with
  | Option.none | Option.some Json.null =>
    return if required then #[s!"{path}{key} is required"] else #[]
  | Option.some (Json.arr items) =>
    let mut out : Array String := #[]
    if items.size < minItems then
      out := out.push s!"{path}{key} must list at least {minItems} entr\
        {if minItems == 1 then "y" else "ies"}"
    for (item, i) in items.zipIdx do
      match item with
      | Json.str s =>
        if (trim s).isEmpty then out := out.push s!"{path}{key}[{i}] must not be empty"
      | _ => out := out.push s!"{path}{key}[{i}] must be a string"
    return out
  | Option.some _ => return #[s!"{path}{key} must be a list"]

/-- Items of an array-of-objects field, with the shape violations of the field itself. -/
private def objArray (path : String) (j : Json) (key : String) (required : Bool := false)
    (minItems : Nat := 0) : Array Json × Array String := Id.run do
  match (j.getObjVal? key).toOption with
  | Option.none | Option.some Json.null =>
    return (#[], if required then #[s!"{path}{key} is required"] else #[])
  | Option.some (Json.arr items) =>
    let mut out : Array String := #[]
    let mut objs : Array Json := #[]
    if items.size < minItems then
      out := out.push s!"{path}{key} must list at least {minItems} entr\
        {if minItems == 1 then "y" else "ies"}"
    for (item, i) in items.zipIdx do
      match item with
      | Json.obj _ => objs := objs.push item
      | _ => out := out.push s!"{path}{key}[{i}] must be a mapping"
    return (objs, out)
  | Option.some _ => return (#[], #[s!"{path}{key} must be a list"])

/-- A required sub-mapping: the object when it is one, plus the violation when it is not. -/
private def objField (path : String) (j : Json) (key : String) (required : Bool := false) :
    Option Json × Array String :=
  match (j.getObjVal? key).toOption with
  | Option.none | Option.some Json.null =>
    (Option.none, if required then #[s!"{path}{key} is required"] else #[])
  | Option.some (v@(Json.obj _)) => (Option.some v, #[])
  | Option.some _ => (Option.none, #[s!"{path}{key} must be a mapping"])

private def sourceRelationships : List String :=
  ["formalizes", "adapts", "independently-proves", "background", "other"]

private def sourceEndorsements : List String :=
  ["participated", "endorsed", "no-response", "not-contacted", "declined", "n/a", "other"]

private def relatedRelationships : List String :=
  ["builds-on", "adapts", "independent", "supersedes", "other"]

private def automationMethods : List String :=
  ["manual", "copilot", "agent", "autonomous", "other"]

private def repositoryRoles : List String := ["substantive-development", "thin-wrapper"]

/--
Structural violations of the v0.4 subset, in document order. Empty ⇒ nothing this check
knows how to look for is wrong.

Deliberately total and pure: it reports everything it finds rather than stopping at the
first problem, so one build tells a consumer everything they have to fix.
-/
def validate (doc : Json) : Array String := Id.run do
  match doc with
  | Json.obj _ => pure ()
  | _ => return #["the document is not a mapping"]
  let mut out : Array String := #[]
  out := out ++ strCheck "" doc "version"
  -- project
  let (project?, projectErrs) := objField "" doc "project" (required := true)
  out := out ++ projectErrs
  if let Option.some project := project? then
    out := out ++ strCheck "project." project "name" (required := true)
    out := out ++ strCheck "project." project "description"
    out := out ++ strArrayCheck "project." project "authors" (required := true) (minItems := 1)
    out := out ++ strArrayCheck "project." project "responsible_maintainers"
    out := out ++ strCheck "project." project "license" (required := true)
  -- repository (optional, with the schema's two conditionals)
  let (repository?, repositoryErrs) := objField "" doc "repository"
  out := out ++ repositoryErrs
  if let Option.some repository := repository? then
    out := out ++ enumCheck "repository." repository "role" repositoryRoles
    let (substantive?, substantiveErrs) := objField "repository." repository "substantive_formalization"
    out := out ++ substantiveErrs
    if let Option.some substantive := substantive? then
      out := out ++ strCheck "repository.substantive_formalization." substantive "id"
        (required := true)
      out := out ++ strCheck "repository.substantive_formalization." substantive "revision"
    let role := ((repository.getObjValAs? String "role").toOption).getD ""
    if role == "thin-wrapper" && !present repository "substantive_formalization" then
      out := out.push "repository.substantive_formalization is required when \
        repository.role is thin-wrapper"
    if role == "substantive-development" && present repository "substantive_formalization" then
      out := out.push "repository.substantive_formalization must be absent when \
        repository.role is substantive-development"
  -- sources
  let (sources, sourceErrs) := objArray "" doc "sources" (required := true) (minItems := 1)
  out := out ++ sourceErrs
  for (src, i) in sources.zipIdx do
    let p := s!"sources[{i}]."
    out := out ++ strCheck p src "title" (required := true)
    out := out ++ strArrayCheck p src "authors"
    out := out ++ strCheck p src "id"
    out := out ++ strCheck p src "type"
    out := out ++ strCheck p src "location"
    out := out ++ strCheck p src "note"
    out := out ++ strCheck p src "license"
    out := out ++ enumCheck p src "relationship" sourceRelationships
    out := out ++ enumCheck p src "author_endorsement" sourceEndorsements
    let (contributors, contributorErrs) := objArray p src "contributors"
    out := out ++ contributorErrs
    for (c, k) in contributors.zipIdx do
      let cp := s!"{p}contributors[{k}]."
      out := out ++ strCheck cp c "name" (required := true)
      out := out ++ strCheck cp c "role" (required := true)
  -- related_formalizations
  let (related, relatedErrs) := objArray "" doc "related_formalizations"
  out := out ++ relatedErrs
  for (r, i) in related.zipIdx do
    let p := s!"related_formalizations[{i}]."
    out := out ++ strCheck p r "id" (required := true)
    out := out ++ enumCheck p r "relationship" relatedRelationships
    out := out ++ strCheck p r "note"
  -- classification
  let (classification?, classificationErrs) := objField "" doc "classification"
  out := out ++ classificationErrs
  if let Option.some classification := classification? then
    out := out ++ strArrayCheck "classification." classification "arxiv"
    out := out ++ strArrayCheck "classification." classification "msc2020"
  -- automation
  let (automation?, automationErrs) := objField "" doc "automation" (required := true)
  out := out ++ automationErrs
  if let Option.some automation := automation? then
    let (methods, methodErrs) := objArray "automation." automation "methods"
      (required := true) (minItems := 1)
    out := out ++ methodErrs
    for (m, i) in methods.zipIdx do
      let p := s!"automation.methods[{i}]."
      out := out ++ enumCheck p m "method" automationMethods (required := true)
      out := out ++ strArrayCheck p m "models"
      out := out ++ strCheck p m "framework"
      out := out ++ strCheck p m "tool_setup"
      out := out ++ strCheck p m "prompting_notes"
      let (cost?, costErrs) := objField p m "cost"
      out := out ++ costErrs
      if let Option.some cost := cost? then
        out := out ++ scalarCheck s!"{p}cost." cost "wall_time"
        out := out ++ scalarCheck s!"{p}cost." cost "spend_usd"
        out := out ++ scalarCheck s!"{p}cost." cost "hardware"
    out := out ++ scalarCheck "automation." automation "spend_usd"
    out := out ++ strCheck "automation." automation "notes"
  -- status
  let (status?, statusErrs) := objField "" doc "status"
  out := out ++ statusErrs
  if let Option.some status := status? then
    out := out ++ strCheck "status." status "scope"
    out := out ++ natCheck "status." status "sorry_count"
    out := out ++ natCheck "status." status "sorry_in_definitions"
    out := out ++ strArrayCheck "status." status "axioms"
    let (results, resultErrs) := objArray "status." status "main_results"
    out := out ++ resultErrs
    for (r, i) in results.zipIdx do
      let p := s!"status.main_results[{i}]."
      out := out ++ strCheck p r "declaration"
      out := out ++ strCheck p r "file"
      out := out ++ natCheck p r "sorry_count"
      out := out ++ strArrayCheck p r "axioms"
      out := out ++ strCheck p r "comparator_config"
      let (deps, depErrs) := objArray p r "literature_dependencies"
      out := out ++ depErrs
      for (d, k) in deps.zipIdx do
        let dp := s!"{p}literature_dependencies[{k}]."
        out := out ++ strCheck dp d "statement"
        out := out ++ strCheck dp d "source"
  -- fidelity
  let (fidelity?, fidelityErrs) := objField "" doc "fidelity"
  out := out ++ fidelityErrs
  if let Option.some fidelity := fidelity? then
    out := out ++ strCheck "fidelity." fidelity "divergences"
  -- review
  let (review?, reviewErrs) := objField "" doc "review" (required := true)
  out := out ++ reviewErrs
  if let Option.some review := review? then
    out := out ++ strCheck "review." review "status" (required := true)
    out := out ++ strArrayCheck "review." review "reviewers"
    out := out ++ strCheck "review." review "notes"
  -- `alignment` is freeform by design and is not checked.
  out := out ++ strCheck "" doc "acknowledgements"
  return out

/-- Parse a `formalization.yaml`-subset document into `Lean.Json`. -/
def parse (input : String) : Except String Json := do
  let mut lines : Array (Nat × String) := #[]
  let mut n := 1
  for l in input.splitOn "\n" do
    let l := if l.endsWith "\r" then (l.dropEnd 1).toString else l
    if (l.toList.takeWhile (fun c => c == ' ' || c == '\t')).contains '\t' then
      throw s!"line {n}: tab characters in indentation are not supported"
    lines := lines.push (n, l)
    n := n + 1
  -- Allow (and skip) a single leading document-start marker.
  let first := skipIgnorable lines 0
  let mut start := first
  if h : first < lines.size then
    if trim (lines[first]).2 == "---" then
      start := first + 1
  let i := skipIgnorable lines start
  if h : i < lines.size then
    let (no, raw) := lines[i]
    if countIndent raw != 0 then
      throw s!"line {no}: top-level content must start at column 0"
    if trim raw == "---" then
      throw s!"line {no}: multi-document YAML streams are not supported"
    let (v, k) ← parseNode lines i
    let k := skipIgnorable lines k
    if hk : k < lines.size then
      throw s!"line {(lines[k]).1}: unexpected trailing content"
    return v
  else
    return Json.mkObj []

end Informal.FormalizationYaml
