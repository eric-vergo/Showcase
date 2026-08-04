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
