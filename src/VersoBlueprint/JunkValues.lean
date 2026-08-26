/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import Lean
import Std.Data.HashMap
import Std.Data.HashSet
import VersoBlueprint.Sha256

/-!
# Known caveat patterns — total-function conventions a reader can misread

Lean's functions are total. `a - b` on `ℕ` is `0` when `b` exceeds `a`, `x / 0` is `0`,
`Real.sqrt` of a negative is `0`, `Set.ncard` of an infinite set is `0`. None of that is a
defect; all of it is a place where a statement can say something other than what a reader
takes it to say. This module carries a **partial, hand-maintained table** of such symbols
and the machinery to look for them.

Three things about the register, because they are the whole point:

- **These are caveats to check, not findings of error.** A hit means a reader should look;
  it does not mean anything is wrong. Nothing here ever asserts a defect.
- **The table is partial and says so everywhere.** A scan that matched nothing has found
  nothing in *this table*, which is not evidence that no total-function convention
  applies. Every zero-match state renders that sentence, with the table's version and
  digest, so a reader can tell which table was silent.
- **Guard detection is a presence scan, never a verdict.** It looks for a hypothesis whose
  head symbol the table lists as a guarding shape. Finding one does not establish that it
  guards the flagged operand, and the copy never says it does; finding none does not
  establish that a guard is missing.

## Where the scan runs

Two scans, deliberately different, each honest about its own coverage:

- The **certified-claim scan** rides F1's meaning traversal
  (`Informal.StatementClosure.walk`) inside the `statement-closure` subprocess, matching on
  every constant the walk encounters — including the constants at the trusted frontier,
  where it matches and stops. That is what catches a junk symbol hidden behind a wrapper
  definition: the wrapper is expanded, the frontier symbol it names is matched.
- The **registry-side scan** is cheap and shallow: a declaration's own type constants plus
  one hop through instance values. Its coverage string says exactly that, because a shallow
  scan reported as a deep one is worse than no scan.

The traversal is not reproduced here. This module receives one encountered constant at a
time (`observe`), which keeps it independent of the traversal engine and lets the
subprocess feed it the one walk it already performs rather than a second one that could
disagree with it.
-/

namespace Informal.JunkValues

open Lean

/-! ## Options

Registered here rather than beside the other `verso.blueprint.trust.*` options because the
declaration registry reads them too and cannot import the trust module. One registration is
the only way both scans answer to the same switch.
-/

register_option verso.blueprint.trust.statementCaveats : Bool := {
  defValue := true
  descr := "Whether to look for known total-function conventions — Lean's junk values: truncated subtraction on ℕ, division by zero, `Set.ncard` of an infinite set — in the statements this site presents, and report them as caveats a reader should check. On by default; these are caveats to check, never findings of error, and the surface says so in its own copy. Two scans, activating independently. The DECLARATION-REGISTRY scan runs wherever the registry does (`verso.blueprint.graph.includeAllDecls`) and covers a declaration's own type constants plus one instance hop. The CERTIFIED-CLAIM scan rides the statement-closure traversal and therefore runs only where `verso.blueprint.trust.statementClosure` is also on — with that option off there is no traversal to ride and no certified-claim caveat block. Off ⇒ nothing is scanned and nothing is rendered anywhere."
}

register_option verso.blueprint.trust.junkValueTable : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to a JSON junk-value table merged OVER the one this fork ships. Schema: {\"schemaVersion\": 1, \"updated\": \"YYYY-MM-DD\", \"sources\": [...], \"entries\": [ {\"symbol\", \"aliases\"?, \"instances\"?, \"behavior\", \"guards\"?, \"guardHint\"?, \"provenance\"} ]}. Merge is entry-replace on the stable `symbol` key — an override entry replaces the bundled one whole rather than merging field by field, since a half-replaced safety entry is the failure nobody notices. Two things are build errors: an unsupported `schemaVersion`, and a match key (symbol, alias or instance name) claimed by two entries after the merge. Empty ⇒ the bundled table. Read at elaboration, so a warm rebuild that does not re-elaborate the block that read it keeps the previous table (see the warm-rebuild staleness note)."
}

/-- Whether the caveat surface is on at all. -/
def caveatsEnabled (opts : Lean.Options) : Bool :=
  opts.get verso.blueprint.trust.statementCaveats.name
    verso.blueprint.trust.statementCaveats.defValue

/-- The configured override path (empty ⇒ the bundled table). -/
def tableOverridePath (opts : Lean.Options) : String :=
  opts.get verso.blueprint.trust.junkValueTable.name
    verso.blueprint.trust.junkValueTable.defValue

/-! ## The table -/

/-- Schema version of the junk-value table document — the bundled one and any consumer
override. A document at another version is refused by name rather than read tolerantly: a
safety table parsed under the wrong schema is a table nobody can rely on. -/
def tableSchemaVersion : Nat := 1

/--
One symbol whose total-function convention a reader can misread.

`symbol` is the merge key and the display name. `aliases` and `instances` are the other
names an elaborated statement can mention the same convention under — `a - b : ℕ` never
names `Nat.sub`, it names `HSub.hSub` and `instSubNat` — and matching on them is what makes
the scan see arithmetic rather than only spelled-out applications.
-/
structure Entry where
  /-- Canonical name; the stable key an override merges on. -/
  symbol : String
  /-- Other constants naming the same convention. -/
  aliases : Array String := #[]
  /-- Instance constants whose value is this symbol, which is how notation reaches it. -/
  instances : Array String := #[]
  /-- What the symbol does at the edge, in one sentence, in the indicative. -/
  behavior : String := ""
  /-- Head symbols of a hypothesis that would guard the edge case (`LE.le`, `Ne`, …).
  Empty ⇒ nothing to look for, and the guard state is `not-evaluated`. -/
  guards : Array String := #[]
  /-- What a guarding hypothesis looks like, for a reader who wants to add one. -/
  guardHint : String := ""
  /-- Where the entry came from: `core` (the declaration's own documented behaviour),
  `mathlib` (a Mathlib lemma stating it), or `curated` (this fork's editorial judgement). -/
  provenance : String := ""
deriving Inhabited, Repr, ToJson

/-- Read tolerantly: an entry that lists no aliases omits the key rather than writing an
empty array, and a table author should not have to know that. `symbol` is the one field
without a default, and its absence is an error. -/
instance : FromJson Entry where
  fromJson? j := do
    let str (k : String) : String := (j.getObjValAs? String k).toOption.getD ""
    let arr (k : String) : Array String :=
      (j.getObjValAs? (Array String) k).toOption.getD #[]
    let symbol := str "symbol"
    if symbol.isEmpty then throw "entry has no 'symbol'"
    return {
      symbol
      aliases := arr "aliases"
      instances := arr "instances"
      behavior := str "behavior"
      guards := arr "guards"
      guardHint := str "guardHint"
      provenance := str "provenance"
    }

/-- A junk-value table: the bundled one, a consumer override, or their merge. -/
structure Table where
  schemaVersion : Nat := tableSchemaVersion
  /-- The table's own revision date, `YYYY-MM-DD`. Rendered as its version. -/
  updated : String := ""
  /-- What the entries were checked against, verbatim. -/
  sources : Array String := #[]
  entries : Array Entry := #[]
deriving Inhabited, Repr, ToJson, FromJson

/-- Every name an entry can be matched under. -/
def Entry.keys (e : Entry) : Array String :=
  #[e.symbol] ++ e.aliases ++ e.instances

/-- The table's version, as the non-exhaustiveness sentence names it. -/
def Table.version (t : Table) : String :=
  if t.updated.isEmpty then s!"schema {t.schemaVersion}" else t.updated

/-- SHA-256 of the table's canonical serialization, truncated for display.

Over the *effective* table, so a consumer override yields a different digest from the
bundled one: "no matches in the configured partial table" is only worth reading if the
reader can tell which table was silent. -/
def Table.digest (t : Table) : String :=
  ((Informal.Sha256.hexOfString (toJson t).compress).take 12).toString

/-- Reject a table whose entries collide on any match key.

A duplicate key makes the match ambiguous — two entries would claim the same constant, and
which one a reader sees would depend on iteration order — so it is refused rather than
resolved. -/
def Table.checkKeys (t : Table) : Except String Unit := do
  let mut seen : Std.HashMap String String := {}
  for e in t.entries do
    if e.symbol.isEmpty then
      throw "a junk-value table entry has an empty 'symbol'"
    for k in e.keys do
      match seen[k]? with
      | some owner =>
        throw s!"'{k}' is claimed by both '{owner}' and '{e.symbol}'; a match key must name \
          exactly one entry"
      | none => seen := seen.insert k e.symbol
  return ()

/-- Parse and validate a table document. An unsupported schema version is refused by name —
the one failure mode a tolerant reader would turn into silently missing entries. -/
def Table.ofJson? (j : Json) : Except String Table := do
  let version := (j.getObjValAs? Nat "schemaVersion").toOption.getD 0
  if version != tableSchemaVersion then
    throw s!"junk-value table is schema version {version}; this build reads version \
      {tableSchemaVersion}"
  let entriesJson :=
    ((j.getObjVal? "entries").toOption.getD (Json.arr #[])).getArr?.toOption.getD #[]
  let mut entries : Array Entry := #[]
  for e in entriesJson do
    match (fromJson? (α := Entry) e) with
    | .error err => throw s!"junk-value table entry: {err}"
    | .ok entry => entries := entries.push entry
  let t : Table := {
    schemaVersion := version
    updated := (j.getObjValAs? String "updated").toOption.getD ""
    sources := (j.getObjValAs? (Array String) "sources").toOption.getD #[]
    entries
  }
  Table.checkKeys t
  return t

/--
Merge a consumer override over a base table.

**Entry-replace on the stable `symbol` key**: an override entry naming a symbol the base
already has replaces it whole, rather than merging field by field. Field-merging a safety
table is how an override meaning to correct a behaviour sentence silently keeps a guard
list that no longer applies. New symbols are appended in the override's order.

The merged `updated` is the override's when it has one — the effective table is the
consumer's — and `sources` accumulate, so the provenance of what is being matched stays
readable.
-/
def Table.mergeOver (base override : Table) : Except String Table := do
  let mut entries := base.entries
  for e in override.entries do
    match entries.findIdx? (fun b => b.symbol == e.symbol) with
    | some i => entries := entries.set! i e
    | none => entries := entries.push e
  let merged : Table := {
    schemaVersion := tableSchemaVersion
    updated := if override.updated.isEmpty then base.updated else override.updated
    sources := base.sources ++ override.sources
    entries
  }
  Table.checkKeys merged
  return merged

/-- The table this fork ships. Partial by construction and dated in its own `updated`
field; see the module docstring for what "partial" is allowed to mean. -/
def bundledJson : String := include_str "junk-values.json"

/-- The bundled table, parsed. An error here is a defect in this fork's own asset. -/
def bundled : Except String Table :=
  match Json.parse bundledJson with
  | .error err => .error s!"bundled junk-values.json is not valid JSON: {err}"
  | .ok j => Table.ofJson? j

/-- The bundled table's version, for a test that should not restate it. -/
def bundledTableVersion : String := (bundled.toOption.getD {}).version

/--
Load the effective table: the bundled one, or the bundled one with a consumer override
merged over it.

A configured path that does not exist, does not parse, carries an unsupported schema
version, or collides on a match key returns the reason, which the caller raises as a build
error. A configured safety table must not degrade into the default one.
-/
def loadTable (overridePath : String) : IO (Except String Table) := do
  let base ← match bundled with
    | .error err => return .error err
    | .ok t => pure t
  if overridePath.isEmpty then return .ok base
  unless ← System.FilePath.pathExists overridePath do
    return .error s!"names a missing file (resolved against the build directory): {overridePath}"
  let raw ←
    try
      IO.FS.readFile overridePath
    catch e =>
      return .error s!"could not read {overridePath}: {e}"
  match Json.parse raw with
  | .error err => return .error s!"could not parse {overridePath}: {err}"
  | .ok j =>
    match Table.ofJson? j with
    | .error err => return .error s!"{overridePath}: {err}"
    | .ok override => return Table.mergeOver base override

/-! ## Consumer-declared characterizations (§A7(e))

A caveat says a definition has an edge case. The answer to one is often a lemma the project
has already proved — "this is the definition's characterization, and here is where it is
established". That is a claim the consumer makes, not one this fork checks, so it is loaded
from a sidecar the consumer writes, labelled as the consumer's, and carried with the
sidecar's path and digest so a reader can see which file said it.

Every failure mode is a build error rather than a silent omission: a missing file, a
malformed document, two entries for one declaration, or a declaration this environment does
not have. A characterization that quietly disappeared would be a claim a project believes it
is publishing and is not.
-/

/-- Schema version of the characterization sidecar. -/
def characterizationSchemaVersion : Nat := 1

/-- One consumer-declared characterization of one declaration. -/
structure Characterization where
  /-- Fully-qualified declaration the characterization is about. -/
  decl : String := ""
  /-- The characterizing statement, as the consumer words it. -/
  statement : String := ""
  /-- Where it is established — a lemma name, usually. -/
  reference : String := ""
  note : String := ""
deriving Inhabited, Repr, ToJson

instance : FromJson Characterization where
  fromJson? j := do
    let str (k : String) : String := (j.getObjValAs? String k).toOption.getD ""
    let decl := str "decl"
    if decl.isEmpty then throw "characterization entry has no 'decl'"
    let statement := str "statement"
    if statement.isEmpty then
      throw s!"characterization for '{decl}' has no 'statement'"
    return { decl, statement, reference := str "reference", note := str "note" }

/-- A loaded sidecar, with the provenance of the bytes it came from. -/
structure Characterizations where
  /-- Path as configured, for the provenance line. -/
  path : String := ""
  /-- SHA-256 of the bytes read, truncated for display. -/
  digest : String := ""
  entries : Array Characterization := #[]
deriving Inhabited, Repr, ToJson, FromJson

/-- Read a characterization sidecar, refusing every way it could be wrong. The
unresolved-declaration check needs an environment and is the caller's (see
`elabCharacterizations?`). -/
def loadCharacterizations (path : String) : IO (Except String Characterizations) := do
  unless ← System.FilePath.pathExists path do
    return .error s!"names a missing file (resolved against the build directory): {path}"
  let raw ←
    try
      IO.FS.readFile path
    catch e =>
      return .error s!"could not read {path}: {e}"
  let j ← match Json.parse raw with
    | .error err => return .error s!"could not parse {path}: {err}"
    | .ok j => pure j
  let version := (j.getObjValAs? Nat "schemaVersion").toOption.getD 0
  if version != characterizationSchemaVersion then
    return .error s!"{path} is schema version {version}; this build reads version \
      {characterizationSchemaVersion}"
  let arr :=
    ((j.getObjVal? "characterizations").toOption.getD (Json.arr #[])).getArr?.toOption.getD #[]
  let mut entries : Array Characterization := #[]
  let mut seen : Std.HashSet String := {}
  for e in arr do
    match fromJson? (α := Characterization) e with
    | .error err => return .error s!"{path}: {err}"
    | .ok c =>
      if seen.contains c.decl then
        return .error s!"{path} declares two characterizations for '{c.decl}'; a declaration \
          has one characterization or none"
      seen := seen.insert c.decl
      entries := entries.push c
  return .ok { path, digest := ((Informal.Sha256.hexOfString raw).take 12).toString, entries }

/-- Declarations a sidecar names that an environment does not have. The one check the
loader cannot make on its own, split out so it can be exercised without an elaborator. -/
def unresolvedDecls (env : Environment) (cs : Characterizations) : Array String :=
  (cs.entries.filter fun c => (env.find? c.decl.toName).isNone).map (·.decl)

/-! ## Matching -/

/-- A table prepared for lookup: every match key resolved to its entry. -/
structure Index where
  byKey : Std.HashMap String Entry := {}
  table : Table := {}
deriving Inhabited

/-- Index a table for lookup. `Table.checkKeys` has already refused collisions, so the last
writer here is also the only writer. -/
def Table.index (t : Table) : Index :=
  { table := t
    byKey := t.entries.foldl (init := ({} : Std.HashMap String Entry)) fun m e =>
      e.keys.foldl (init := m) fun m k => m.insert k e }

def Index.find? (ix : Index) (n : Name) : Option Entry := ix.byKey[n.toString]?

/-- Whether the index has anything to match at all. -/
def Index.isEmpty (ix : Index) : Bool := ix.byKey.isEmpty

/-! ## Guard presence

A presence scan over a declaration's binder telescope, looking for a hypothesis whose head
symbol the table lists as a guarding shape. It relates nothing to anything, and the copy
that renders a positive result says so in the same sentence.
-/

/-- Head constants of one binder type, descending through `¬` so `¬ (b = 0)` reports `Eq`
as well as `Not`. -/
private partial def headsOf (e : Expr) (acc : Std.HashSet Name) : Std.HashSet Name :=
  match e.getAppFn with
  | .const n _ =>
    let acc := acc.insert n
    if n == ``Not then
      match e.getAppArgs with
      | #[a] => headsOf a acc
      | _ => acc
    else acc
  | _ => acc

/-- Head symbols of every binder in a type's telescope. Loose bound variables are
irrelevant here: a head constant does not depend on them. -/
private partial def telescopeHeads (e : Expr) (acc : Std.HashSet Name) : Std.HashSet Name :=
  match e with
  | .forallE _ t b _ => telescopeHeads b (headsOf t acc)
  | _ => acc

/-- Head symbols of one type's binder telescope. -/
def guardHeads (type : Expr) : Std.HashSet Name := telescopeHeads type {}

/-- Head symbols of several declarations' telescopes — the certified statements of one
claim, scanned as one population of hypotheses. -/
def guardHeadsOfAll (types : Array Expr) : Std.HashSet Name :=
  types.foldl (init := ({} : Std.HashSet Name)) fun acc t => telescopeHeads t acc

/-- A guard-shaped hypothesis occurs in the scanned telescope. Not a claim that it guards
the flagged operand — this scan cannot establish that. -/
def guardCandidatePresent : String := "candidate-present"

/-- The telescope was scanned and no hypothesis of a guarding shape was found. -/
def guardNotDetected : String := "not-detected"

/-- Nothing was looked for: the table records no guard shape for this symbol. -/
def guardNotEvaluated : String := "not-evaluated"

/-- Which guard state an entry is in against a scanned telescope. -/
def guardState (e : Entry) (heads : Std.HashSet Name) : String :=
  if e.guards.isEmpty then guardNotEvaluated
  else if e.guards.any (fun g => heads.contains g.toName) then guardCandidatePresent
  else guardNotDetected

/-! ## Findings -/

/-- One table symbol the scan encountered. -/
structure Finding where
  /-- The table entry's canonical symbol. -/
  symbol : String := ""
  /-- The constant actually encountered, which may be an alias or an instance. -/
  matchedVia : String := ""
  behavior : String := ""
  /-- `candidate-present`, `not-detected`, or `not-evaluated`. -/
  guard : String := ""
  guardHint : String := ""
  /-- The table entry's provenance. -/
  provenance : String := ""
  /-- Origin bucket of the constant where the match occurred (`challenge`, `subject`,
  `mathlib`, `core`, …); empty for the registry-side scan, which has one origin. -/
  origin : String := ""
  /-- Distance from the scanned statement, along the edge that reached the match. -/
  depth : Nat := 0
deriving Inhabited, Repr, ToJson

/-- Read tolerantly, like every other document this fork consumes: a row missing a field
loses that field, not the whole report. -/
instance : FromJson Finding where
  fromJson? j :=
    let str (k : String) : String := (j.getObjValAs? String k).toOption.getD ""
    return {
      symbol := str "symbol"
      matchedVia := str "matchedVia"
      behavior := str "behavior"
      guard := str "guard"
      guardHint := str "guardHint"
      provenance := str "provenance"
      origin := str "origin"
      depth := (j.getObjValAs? Nat "depth").toOption.getD 0
    }

/-- One `set_option` the scanned chain sets. Neutral by construction: an override is a
configuration fact, and this record carries no judgement about it. -/
structure OptionOverride where
  option : String := ""
  value : String := ""
  file : String := ""
  line : Nat := 0
  column : Nat := 0
  /-- `file` for a top-level `set_option`, `term` for `set_option … in`. -/
  scope : String := ""
deriving Inhabited, Repr, ToJson

instance : FromJson OptionOverride where
  fromJson? j :=
    let str (k : String) : String := (j.getObjValAs? String k).toOption.getD ""
    return {
      option := str "option"
      value := str "value"
      file := str "file"
      line := (j.getObjValAs? Nat "line").toOption.getD 0
      column := (j.getObjValAs? Nat "column").toOption.getD 0
      scope := str "scope"
    }

/-! ### Scan status

Five states, distinct in the data and distinct in the copy, because they are five different
things a reader should conclude.
-/

/-- The scan was not performed: the surface is switched off. -/
def statusDisabled : String := "disabled"
/-- The scan could not be performed; `reason` says why. -/
def statusUnavailable : String := "unavailable"
/-- The traversal hit its cap before finishing, so the findings are a lower bound. -/
def statusPartial : String := "partial"
/-- The traversal finished and matched nothing in the configured table. -/
def statusCompletedZero : String := "completed-zero"
/-- The traversal finished and matched something. -/
def statusCompletedWithHits : String := "completed-with-hits"

/-- What one scan found, and how far it looked. -/
structure ScanReport where
  /-- One of `disabled`, `unavailable`, `partial`, `completed-zero`,
  `completed-with-hits`. -/
  status : String := ""
  /-- Why the scan is unavailable or disabled, in the register the page uses. Empty
  otherwise. -/
  reason : String := ""
  /-- The matched symbols, one row each. Serialized as `matches` (`matches` is a token). -/
  hits : Array Finding := #[]
  /-- The effective table's revision date. -/
  tableVersion : String := ""
  /-- The effective table's digest, so a reader can tell which table was silent. -/
  tableDigest : String := ""
  /-- What was actually looked at, in the words the surface repeats verbatim. -/
  coverage : String := ""
  truncated : Bool := false
  /-- `set_option` overrides found in the scanned chain; empty when none were found *or*
  when no option scan ran — `optionScanFiles` distinguishes those. -/
  optionOverrides : Array OptionOverride := #[]
  /-- Files the option scan lexed. Empty ⇒ no option scan ran. -/
  optionScanFiles : Array String := #[]
deriving Inhabited, Repr

/-- Serialized with `hits` under the key `matches`, which is what the field is called
everywhere except in Lean, where `matches` is a token. -/
instance : ToJson ScanReport where
  toJson r := Json.mkObj <|
    [("status", Json.str r.status)]
    ++ (if r.reason.isEmpty then [] else [("reason", Json.str r.reason)])
    ++ [("matches", Json.arr (r.hits.map toJson)),
        ("tableVersion", Json.str r.tableVersion),
        ("tableDigest", Json.str r.tableDigest),
        ("coverage", Json.str r.coverage),
        ("truncated", Json.bool r.truncated)]
    ++ (if r.optionOverrides.isEmpty then []
        else [("optionOverrides", Json.arr (r.optionOverrides.map toJson))])
    ++ (if r.optionScanFiles.isEmpty then []
        else [("optionScanFiles", Json.arr (r.optionScanFiles.map Json.str))])

instance : FromJson ScanReport where
  fromJson? j := do
    let arrOf (α : Type) [FromJson α] (k : String) : Except String (Array α) := do
      let raw := ((j.getObjVal? k).toOption.getD (Json.arr #[])).getArr?.toOption.getD #[]
      let mut out : Array α := #[]
      for x in raw do
        out := out.push (← fromJson? (α := α) x)
      return out
    return {
      status := (j.getObjValAs? String "status").toOption.getD ""
      reason := (j.getObjValAs? String "reason").toOption.getD ""
      hits := ← arrOf Finding "matches"
      tableVersion := (j.getObjValAs? String "tableVersion").toOption.getD ""
      tableDigest := (j.getObjValAs? String "tableDigest").toOption.getD ""
      coverage := (j.getObjValAs? String "coverage").toOption.getD ""
      truncated := (j.getObjValAs? Bool "truncated").toOption.getD false
      optionOverrides := ← arrOf OptionOverride "optionOverrides"
      optionScanFiles := (j.getObjValAs? (Array String) "optionScanFiles").toOption.getD #[]
    }

/-- Coverage wording for the certified-claim scan. -/
def coverageMeaningClosure : String :=
  "every constant the statement's meaning closure reaches, including the constants at the \
   trusted frontier"

/-- Coverage wording for the registry-side scan. Says exactly what it did, and no more. -/
def coverageDirectPlusInstanceHop : String :=
  "direct constants plus one instance hop"

/-- The honest empty state. -/
def unavailable (reason : String) : ScanReport :=
  { status := statusUnavailable, reason }

/-- The switched-off state. Produced at the subprocess boundary when a job carries no
table, so a caller that omitted one is told rather than served an empty result. -/
def disabled (reason : String) : ScanReport :=
  { status := statusDisabled, reason }

/-! ## The scan itself -/

/-- Accumulated matches, one row per table symbol. -/
structure ScanState where
  /-- One row per symbol, in first-encounter order. The walk is breadth-first, so the first
  encounter is the shallowest one — where a reader would meet the symbol first. -/
  hits : Array Finding := #[]
  seen : Std.HashSet String := {}
deriving Inhabited

/--
Record one encountered constant.

Called for every constant the traversal reaches, frontier leaves and repeats included:
matching at the frontier and stopping there is the only way a symbol behind a trusted
wrapper is ever seen. `guard` is left empty and filled in by `finish`, which has the
telescope.
-/
def observe (ix : Index) (name : Name) (origin : String) (depth : Nat) :
    StateM ScanState Unit := do
  match ix.find? name with
  | none => return ()
  | some e =>
    let st ← get
    if st.seen.contains e.symbol then return ()
    set { st with
      seen := st.seen.insert e.symbol
      hits := st.hits.push {
        symbol := e.symbol
        matchedVia := name.toString
        behavior := e.behavior
        guardHint := e.guardHint
        provenance := e.provenance
        origin
        depth
      } }

/-- Close a scan: fill in each finding's guard state and decide the status. -/
def finish (ix : Index) (st : ScanState) (heads : Std.HashSet Name) (truncated : Bool)
    (coverage : String) : ScanReport :=
  let hits := st.hits.map fun f =>
    match ix.find? f.symbol.toName with
    | some e => { f with guard := guardState e heads }
    | none => { f with guard := guardNotEvaluated }
  {
    status :=
      if truncated then statusPartial
      else if hits.isEmpty then statusCompletedZero
      else statusCompletedWithHits
    hits
    tableVersion := ix.table.version
    tableDigest := ix.table.digest
    coverage
    truncated
  }

/--
The registry-side scan: a declaration's own type constants plus one hop through instance
values.

Cheap and total — no `whnf`, no unification, one environment lookup per constant. It sees
`a - b : ℕ` through `instSubNat`, and it does **not** see a symbol hidden inside a
definition the type merely names. `coverageDirectPlusInstanceHop` is what the surface says
about it, in those words.
-/
def scanDeclType (env : Environment) (ix : Index) (type : Expr) : ScanReport := Id.run do
  if ix.isEmpty then
    return unavailable "the configured caveat table has no entries"
  let direct := type.getUsedConstants
  let expanded : Array Name := direct.foldl (init := direct) fun acc c =>
    if Lean.Meta.isInstanceCore env c then
      match (env.find? c).bind (·.value?) with
      | some v => acc ++ v.getUsedConstants
      | none => acc
    else acc
  let (_, st) := (expanded.forM (fun c => observe ix c "" 0)).run {}
  return finish ix st (guardHeads type) (truncated := false)
    (coverage := coverageDirectPlusInstanceHop)

/-! ## `set_option` overrides in the chain (§A7(f))

A challenge file that raises `maxHeartbeats` is doing something ordinary. A challenge file
that sets `debug.byAsSorry` is doing something a reader of the verdict would want to know
about. Neither is reported as a defect: the copy says "configuration override present", and
the allowlist below is published beside the findings so a reader can see what was looked for
and — just as importantly — what was not.
-/

/--
Options this fork reports when a challenge chain sets them.

Chosen for bearing on what a statement *means* or on what checking it establishes:
elaboration budgets (a build that raises them is doing more work than the defaults allow),
the implicit-binder settings (which can turn a typo into a universally quantified variable),
and the switches that weaken checking outright. Everything else — `pp.*`, `trace.*`, linter
settings — is display or diagnostics and is deliberately not reported.

Published in the rendered copy: an allowlist a reader cannot see is an allowlist a reader
cannot rely on.
-/
def trustRelevantOptions : Array String := #[
  "debug.skipKernelTC",
  "debug.byAsSorry",
  "allowUnsafeReducibility",
  "autoImplicit",
  "relaxedAutoImplicit",
  "checkBinderAnnotations",
  "maxHeartbeats",
  "maxRecDepth",
  "maxSynthPendingDepth",
  "synthInstance.maxHeartbeats",
  "synthInstance.maxSize"
]

private def isIdentChar (c : Char) : Bool :=
  c.isAlphanum || c == '_' || c == '.' || c == '\'' || c == '!' || c == '?'

/--
Find every `set_option` in a Lean source, with comments and string literals lexed out.

Hand-rolled rather than parsed: the file may be one this build cannot elaborate — which is
half of why it is being reported on — and a scan that only works on files that elaborate is
a scan that goes quiet exactly when it matters. Nested block comments, doc comments, line
comments, string literals and character literals are all skipped, so a `set_option`
mentioned in prose or inside a string is not a finding.
-/
def scanSetOptions (file : String) (source : String) : Array OptionOverride := Id.run do
  let cs := source.toList.toArray
  let n := cs.size
  -- 1-based line/column per index, computed once so the lexer only tracks an offset.
  let mut lineAt : Array Nat := Array.replicate n 1
  let mut colAt : Array Nat := Array.replicate n 1
  let mut ln := 1
  let mut cl := 1
  for i in [0:n] do
    lineAt := lineAt.set! i ln
    colAt := colAt.set! i cl
    if cs[i]! == '\n' then
      ln := ln + 1
      cl := 1
    else
      cl := cl + 1
  let kw := "set_option".toList.toArray
  let mut out : Array OptionOverride := #[]
  let mut i := 0
  while i < n do
    let c := cs[i]!
    if c == '-' && i + 1 < n && cs[i + 1]! == '-' then
      while i < n && cs[i]! != '\n' do
        i := i + 1
      continue
    if c == '/' && i + 1 < n && cs[i + 1]! == '-' then
      let mut depth := 1
      i := i + 2
      while i < n && depth > 0 do
        if i + 1 < n && cs[i]! == '/' && cs[i + 1]! == '-' then
          depth := depth + 1
          i := i + 2
        else if i + 1 < n && cs[i]! == '-' && cs[i + 1]! == '/' then
          depth := depth - 1
          i := i + 2
        else
          i := i + 1
      continue
    if c == '"' then
      i := i + 1
      while i < n && cs[i]! != '"' do
        i := if cs[i]! == '\\' then i + 2 else i + 1
      i := i + 1
      continue
    if c == '\'' && (i == 0 || !isIdentChar cs[i - 1]!) then
      -- A character literal. A trailing `'` inside an identifier never reaches here,
      -- because the preceding character is an identifier character.
      i := i + 1
      i := if i < n && cs[i]! == '\\' then i + 2 else i + 1
      if i < n && cs[i]! == '\'' then
        i := i + 1
      continue
    let atBoundary := i == 0 || !isIdentChar cs[i - 1]!
    let isKeyword :=
      atBoundary && i + kw.size ≤ n
        && (List.range kw.size).all (fun k => cs[i + k]! == kw[k]!)
        && (i + kw.size == n || !isIdentChar cs[i + kw.size]!)
    if isKeyword then
      let startLine := lineAt[i]!
      let startCol := colAt[i]!
      i := i + kw.size
      while i < n && (cs[i]!).isWhitespace do
        i := i + 1
      let mut name := ""
      while i < n && isIdentChar cs[i]! do
        name := name.push cs[i]!
        i := i + 1
      while i < n && (cs[i]!).isWhitespace && cs[i]! != '\n' do
        i := i + 1
      let mut value := ""
      if i < n && cs[i]! == '"' then
        value := value.push '"'
        i := i + 1
        while i < n && cs[i]! != '"' do
          if cs[i]! == '\\' && i + 1 < n then
            value := value.push cs[i]!
            i := i + 1
          value := value.push cs[i]!
          i := i + 1
        if i < n then
          value := value.push '"'
          i := i + 1
      else
        while i < n && !(cs[i]!).isWhitespace do
          value := value.push cs[i]!
          i := i + 1
      -- `set_option … in` binds to the next command only.
      let mut j := i
      while j < n && (cs[j]!).isWhitespace do
        j := j + 1
      let isScoped :=
        j + 2 ≤ n && cs[j]! == 'i' && cs[j + 1]! == 'n'
          && (j + 2 == n || !isIdentChar cs[j + 2]!)
      if trustRelevantOptions.contains name then
        out := out.push {
          option := name
          value
          file
          line := startLine
          column := startCol
          scope := if isScoped then "term" else "file"
        }
      continue
    i := i + 1
  return out

end Informal.JunkValues
