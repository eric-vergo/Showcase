/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import Lean
import VersoBlueprint.Sha256
import VersoBlueprint.JunkValues

/-!
# Statement closure — the meaning a certified claim depends on

A worklist over declaration **types**: what a reader has to read to know what a
certified theorem *says*, as opposed to how it is proved. Theorem and axiom values are
never traversed; definitions, structures, inductives and instances are unfolded through
their values and constructor types while they remain outside the trusted frontier, and
constants from the trusted libraries (core, Mathlib by default) are recorded as frontier
leaves and expanded no further.

Two properties are load-bearing beyond F1's own reading list:

- **Every encounter is reported.** `walk` takes a visitor and calls it for every constant
  it reaches — repeats, frontier leaves, and the constants it declines to record past the
  cap included. A caller matching a symbol table (the junk-value scan) rides this one
  traversal rather than running a second, shallower one of its own.
- **Truncation is a state, not a footnote.** Hitting `maxNodes` sets `truncated`, and a
  truncated result is a lower bound: it may not be phrased as a count. `capFloor` is the
  smallest cap that can carry even that much, and a caller configuring less is an error
  at its own boundary.

The environment this runs against is supplied by the caller. For the certified surface
that is a clean subprocess environment (`statement-closure`), which imports exactly the
challenge chain's declared imports and nothing else — deliberately not the site's own
elaboration environment, where the subject library and Verso are in scope and a
short name could resolve to something the verified chain never saw.
-/

namespace Informal.StatementClosure

open Lean

/-- Module roots whose declarations are the Lean distribution's own foundation. Fixed:
these name the `core` origin bucket, which is a claim about what a declaration *is*, not
about whether this site trusts it (that is `Config.trustedRoots`). -/
def coreRoots : Array Name := #[`Init, `Lean, `Std, `Batteries]

/-- The libraries a reader is assumed to already accept, and which the walk therefore
stops at. Configurable per job; this is the default. -/
def defaultTrustedRoots : Array Name := #[`Init, `Lean, `Std, `Batteries, `Mathlib]

/-- The smallest cap a closure can be computed under and still say anything.

Below this a truncated result is not a weak claim but an empty one — the reading list is
a handful of arbitrary constants and the "at least N" phrasing carries no information. A
caller configuring less is rejected rather than served a number nobody should read. -/
def capFloor : Nat := 32

/-- Default cap. Large enough that a single-theorem challenge over Mathlib completes. -/
def defaultMaxNodes : Nat := 400

/-- Whether `m` is `root` or nested under it, component-wise. -/
def underRoot (root m : Name) : Bool := root == m || root.isPrefixOf m

/-! ## Path comparison

The chain is spelled differently by the two records that must agree about it: the
consumer's options resolve against the build CWD (`../comparator/Challenge.lean`), the
verifying run recorded repo-root-relative paths (`comparator/Challenge.lean`), and the
tool is handed whichever the driver had. One rule, defined once, used by the tool, by the
§A1 binding comparison, and by the existing comparator cross-checks.
-/

/-- Normalize a filesystem path for comparison: separators to `/`, `./` segments
dropped. Deliberately does **not** resolve `..` — the two paths being compared are
rooted differently by design. -/
def normalizePathForCompare (p : String) : String :=
  let segs := ((p.replace "\\" "/").splitOn "/").filter fun s => s != "." && !s.isEmpty
  String.intercalate "/" segs

/-- Whether `path` ends with `suffix` on a *path-component* boundary. Comparing the
strings would reject every correctly-configured project; comparing components catches a
genuinely different file while accepting a different root. -/
def pathHasSuffix (path suffix : String) : Bool :=
  let ps := (normalizePathForCompare path).splitOn "/"
  let ss := (normalizePathForCompare suffix).splitOn "/"
  ss.length ≤ ps.length && ss == ps.drop (ps.length - ss.length)

/-- Whether two paths name the same file as far as either record can tell: one is a
path-component suffix of the other. -/
def pathsAgree (a b : String) : Bool := pathHasSuffix a b || pathHasSuffix b a

/-- Where a declaration lives and whether the walk stops there. -/
structure Site where
  name : Name
  /-- `challenge`, `subject`, `mathlib`, `core`, `local`, or the module root, named.
  Naming an unrecognized root rather than bucketing it as "other" is the point: a
  dependency nobody expected shows up under its own name. -/
  origin : String
  /-- Defining module; anonymous for a declaration the elaborated chain itself made. -/
  definesModule : Name
  /-- Frontier: recorded and counted, never expanded. -/
  trusted : Bool
deriving Inhabited, Repr

/-- What a closure walk is parameterized by. -/
structure Config where
  /-- Module roots the walk stops at. -/
  trustedRoots : Array Name := defaultTrustedRoots
  /-- Module roots holding the subject library this site presents. Expanded like the
  chain: a reader of the claim has to read them too. -/
  subjectRoots : Array Name := #[]
  /-- Modules whose declarations count as chain-declared. The subprocess leaves this
  empty (the chain's declarations have no defining module at all); a caller walking an
  already-imported fixture names the fixture's modules here. -/
  chainModules : Array Name := #[]
  /-- Whether a constant with no defining module — one the elaborated chain declared —
  counts as `challenge`. False makes it `local`, for a caller walking an environment
  whose own module is not the chain. -/
  localIsChain : Bool := true
  maxNodes : Nat := defaultMaxNodes
  /-- Cap on a recorded signature's characters. -/
  signatureChars : Nat := 200
deriving Inhabited

private def isChainModule (cfg : Config) (m : Name) : Bool :=
  cfg.chainModules.any (underRoot · m)

private def isSubjectModule (cfg : Config) (m : Name) : Bool :=
  cfg.subjectRoots.any (underRoot · m)

/-- The origin bucket of a defining module. Chain and subject win over trust: a module
the consumer named as its own is never reported as a library a reader may skip. -/
def moduleOrigin (cfg : Config) (m : Name) : String :=
  if isChainModule cfg m then "challenge"
  else if isSubjectModule cfg m then "subject"
  else
    let root := m.getRoot
    if root == `Mathlib then "mathlib"
    else if coreRoots.contains root then "core"
    else root.toString

/-- Whether the walk stops at a module. -/
def moduleTrusted (cfg : Config) (m : Name) : Bool :=
  !isChainModule cfg m && !isSubjectModule cfg m && cfg.trustedRoots.any (underRoot · m)

/-- Locate a constant: which module defines it, which bucket that is, whether to stop. -/
def classify (env : Environment) (cfg : Config) (n : Name) : Site :=
  match env.getModuleIdxFor? n with
  | none =>
    { name := n
      origin := if cfg.localIsChain then "challenge" else "local"
      definesModule := .anonymous
      trusted := false }
  | some idx =>
    let m := (env.header.moduleNames[idx.toNat]?).getD .anonymous
    { name := n
      origin := moduleOrigin cfg m
      definesModule := m
      trusted := moduleTrusted cfg m }

/--
Whether a constant is machinery rather than something a reader reads: an auto-generated
recursor, matcher or `noConfusion`, a reserved derived name (`injEq`, `sizeOf_spec`), or
a name Lean marks as an internal detail.

Recorded as a flag, never filtered out. The walk reaches these through real dependency
edges — a definition by pattern match genuinely uses its matcher — and dropping them
would make the count smaller than the closure it claims to report. What to *show* is a
rendering decision, made where the reader can be told what was folded away.
-/
def isAuxiliary (env : Environment) (n : Name) : Bool :=
  n.isInternalDetail || Lean.isAuxRecursor env n || Lean.isNoConfusion env n
    || Lean.isRecCore env n || Lean.Meta.isMatcherCore env n || Lean.isReservedName env n

/-- Declaration kind, as the reading list names it. -/
def kindOf (env : Environment) (info : ConstantInfo) : String :=
  match info with
  | .axiomInfo _ => "axiom"
  | .defnInfo _ => "def"
  | .thmInfo _ => "theorem"
  | .opaqueInfo _ => "opaque"
  | .quotInfo _ => "quot"
  | .inductInfo i => if Lean.isStructure env i.name then "structure" else "inductive"
  | .ctorInfo _ => "constructor"
  | .recInfo _ => "recursor"

/--
The constants a reader must go on to read, for a declaration the walk expands.

Types always. Values only where the value *is* the meaning — a definition's body, an
opaque's witness, an inductive's constructors. A theorem's value is its proof, which is
what the closure is deliberately not about; an axiom and a recursor have no value to
read. This is the whole difference between "what you must read to understand the claim"
and "what the proof touches".
-/
def successors (info : ConstantInfo) : Array Name :=
  let typeDeps := info.type.getUsedConstants
  match info with
  | .defnInfo i => typeDeps ++ i.value.getUsedConstants
  | .opaqueInfo i => typeDeps ++ i.value.getUsedConstants
  | .inductInfo i => typeDeps ++ i.ctors.toArray
  | _ => typeDeps

/-- One constant the walk reached, reported to the visitor before any decision about it.

Frontier leaves and repeats are reported too — a symbol-table scan matches on every
constant encountered and then stops, which it can only do if it is told about the ones
the walk stops at. -/
structure Encounter where
  site : Site
  kind : String
  /-- Machinery rather than something a reader reads (`isAuxiliary`). -/
  auxiliary : Bool
  /-- Distance from the nearest root along the edge that reached it here. -/
  depth : Nat
  /-- First time the walk reached this constant. -/
  firstVisit : Bool
  /-- Whether the walk goes on to expand it. False at the frontier, on a repeat, and
  past the cap. -/
  expanded : Bool
deriving Inhabited

/-- A recorded constant, before signatures are rendered. -/
structure Node where
  site : Site
  kind : String
  auxiliary : Bool
  depth : Nat
deriving Inhabited

/-- The traversal's result: what it recorded, and whether it finished. -/
structure Walk where
  /-- Recorded constants in discovery order (breadth-first, so a truncated walk keeps
  the shallowest — the part of the reading list a reader would start with). -/
  nodes : Array Node := #[]
  /-- Every edge the walk enumerated, as (expanded constant, constant it names). A
  repeat encounter is a real edge and is kept; an edge into a constant the cap turned
  away is kept here and dropped when the reading list is rendered, so the picture never
  points at a row that is not in the list. -/
  edges : Array (Name × Name) := #[]
  /-- The cap was reached and constants were left undiscovered. -/
  truncated : Bool := false
deriving Inhabited

private structure St where
  seen : NameSet := {}
  nodes : Array Node := #[]
  edges : Array (Name × Name) := #[]
  queue : Array (Name × Nat) := #[]
  head : Nat := 0
  truncated : Bool := false
deriving Inhabited

private instance instInhabitedMSt {m : Type → Type} [Monad m] : Inhabited (m St) :=
  ⟨pure default⟩

private partial def walkGo {m : Type → Type} [Monad m] (env : Environment) (cfg : Config)
    (visit : Encounter → m Unit) (s : St) : m St := do
  if h : s.head < s.queue.size then
    let (n, depth) := s.queue[s.head]
    let s := { s with head := s.head + 1 }
    match env.find? n with
    | none => walkGo env cfg visit s
    | some info =>
      let site := classify env cfg n
      let kind := kindOf env info
      let auxiliary := isAuxiliary env n
      if s.seen.contains n then
        visit { site, kind, auxiliary, depth, firstVisit := false, expanded := false }
        walkGo env cfg visit s
      else if s.nodes.size ≥ cfg.maxNodes then
        visit { site, kind, auxiliary, depth, firstVisit := true, expanded := false }
        walkGo env cfg visit { s with truncated := true }
      else
        visit { site, kind, auxiliary, depth, firstVisit := true, expanded := !site.trusted }
        let node : Node := { site, kind, auxiliary, depth }
        let s := { s with seen := s.seen.insert n, nodes := s.nodes.push node }
        let s :=
          if site.trusted then s
          else
            -- A constant is expanded exactly once, so deduplicating within its own
            -- successors is enough to keep the edge list free of repeats.
            let succs := (successors info).foldl (init := (#[] : Array Name)) fun acc c =>
              if acc.contains c then acc else acc.push c
            succs.foldl (init := s) fun s c =>
              let s := { s with edges := s.edges.push (n, c) }
              if s.seen.contains c then s else { s with queue := s.queue.push (c, depth + 1) }
        walkGo env cfg visit s
  else
    return s

/--
Walk the meaning closure of `roots`, reporting every constant reached to `visit`.

Breadth-first and cycle-safe (an inductive's constructor types name the inductive back).
Generic in the monad so a caller can thread its own state through the visitor: this is
the one traversal, and a second scan over the same edges would be a second chance to
disagree with it.
-/
def walk {m : Type → Type} [Monad m] (env : Environment) (cfg : Config) (roots : Array Name)
    (visit : Encounter → m Unit := fun _ => pure ()) : m Walk := do
  let s ← walkGo env cfg visit { queue := roots.map (fun r => (r, 0)) }
  return { nodes := s.nodes, edges := s.edges, truncated := s.truncated }

/-! ## Rendering the reading list -/

/-- Strip Lean's inaccessible-name dagger (`✝`, with its superscript hygiene digits) from
pretty-printed text: it is not valid Lean syntax and reads as noise. -/
private def stripInaccessibleDagger (s : String) : String :=
  let isSuper : Char → Bool := fun c => "⁰¹²³⁴⁵⁶⁷⁸⁹".toList.contains c
  (s.foldl (fun (st : String × Bool) c =>
      let (acc, dropping) := st
      if c == '✝' then (acc, true)
      else if dropping && isSuper c then (acc, true)
      else (acc.push c, false))
    ("", false)).1

/-- Collapse every whitespace run to one space and trim. A reading-list row is one line. -/
private def oneLine (s : String) : String :=
  let folded := (s.foldl (fun (st : String × Bool) c =>
      let (acc, inWs) := st
      if c == ' ' || c == '\t' || c == '\n' || c == '\r' then
        (if inWs then acc else acc.push ' ', true)
      else (acc.push c, false))
    ("", true)).1
  folded.trimAscii.toString

/-- One-line, capped signature text for a declaration's type. -/
def signatureText (cfg : Config) (info : ConstantInfo) : MetaM String := do
  let fmt ←
    try Lean.PrettyPrinter.ppExpr info.type
    catch _ => pure (Std.Format.text "")
  let text := oneLine (stripInaccessibleDagger fmt.pretty)
  if text.length ≤ cfg.signatureChars then return text
  return (text.take cfg.signatureChars).toString ++ "…"

/-- One row of the reading list. -/
structure Entry where
  name : String
  origin : String
  kind : String
  /-- Machinery rather than something a reader reads: an auto-generated recursor,
  matcher, `noConfusion`, or a reserved derived name. -/
  auxiliary : Bool
  depth : Nat
  signature : String
  /-- Defining module; empty for a declaration the chain itself made. -/
  definesModule : String
  /-- Constants this one's meaning refers to, restricted to declarations the reading
  list actually records. This is the edge structure the meaning graph draws; an edge to
  something the cap turned away is dropped here rather than pointing at a missing row. -/
  uses : Array String := #[]
deriving Inhabited, Repr

/-- A completed closure computation. -/
structure Result where
  roots : Array String := #[]
  maxNodes : Nat := 0
  /-- The cap was reached: `total` is a lower bound and may not be phrased as a count. -/
  truncated : Bool := false
  total : Nat := 0
  /-- Entries whose origin is not `mathlib`. -/
  outsideMathlib : Nat := 0
  /-- Entries outside the trusted frontier — what a reader cannot skip by accepting the
  libraries the site trusts. -/
  untrusted : Nat := 0
  /-- Per-origin totals, in first-appearance order. -/
  counts : Array (String × Nat) := #[]
  entries : Array Entry := #[]
deriving Inhabited

private def tally (nodes : Array Node) : Array (String × Nat) :=
  nodes.foldl (init := #[]) fun acc n =>
    match acc.findIdx? (fun p => p.1 == n.site.origin) with
    | some i => acc.set! i (n.site.origin, acc[i]!.2 + 1)
    | none => acc.push (n.site.origin, 1)

/-- Render a walk into a reading list, pretty-printing each recorded type. -/
def render (cfg : Config) (roots : Array Name) (w : Walk) : MetaM Result := do
  let env ← Lean.getEnv
  let recorded : NameSet := w.nodes.foldl (init := {}) fun s n => s.insert n.site.name
  let uses : NameMap (Array Name) := w.edges.foldl (init := {}) fun m (from_, to) =>
    if recorded.contains to then m.insert from_ (((m.find? from_).getD #[]).push to) else m
  let mut entries : Array Entry := #[]
  for node in w.nodes do
    let signature ←
      match env.find? node.site.name with
      | some info => signatureText cfg info
      | none => pure ""
    entries := entries.push {
      name := node.site.name.toString
      origin := node.site.origin
      kind := node.kind
      auxiliary := node.auxiliary
      depth := node.depth
      signature
      definesModule :=
        if node.site.definesModule.isAnonymous then "" else node.site.definesModule.toString
      uses := ((uses.find? node.site.name).getD #[]).map (·.toString)
    }
  return {
    roots := roots.map (·.toString)
    maxNodes := cfg.maxNodes
    truncated := w.truncated
    total := entries.size
    outsideMathlib := entries.foldl (init := 0) fun acc e =>
      if e.origin == "mathlib" then acc else acc + 1
    untrusted := w.nodes.foldl (init := 0) fun acc n => if n.site.trusted then acc else acc + 1
    counts := tally w.nodes
    entries
  }

/-- Walk and render in one step, with no visitor. -/
def closure (cfg : Config) (roots : Array Name) : MetaM Result := do
  let w ← walk (← Lean.getEnv) cfg roots
  render cfg roots w

/--
Walk **once**, rendering the reading list and matching the caveat table on the same
traversal.

The scan is not a second, shallower pass over the roots' types: it rides this walk, so it
sees a junk symbol wherever the meaning closure reaches it — including behind a wrapper
definition whose body names a frontier constant, which is exactly the shape a root-type
scan misses. Matching happens at every encounter, the trusted frontier included, and the
walk stops there as it always did: match-then-stop.

Guard presence is scanned over the roots' own telescopes, since a guarding hypothesis on a
certified statement is the only guard the statement itself can carry. `truncated` becomes
the scan's `partial` status: a capped walk found what it found, which is a lower bound.
-/
def closureAndScan (cfg : Config) (roots : Array Name)
    (table? : Option Informal.JunkValues.Table) :
    MetaM (Result × Option Informal.JunkValues.ScanReport) := do
  let env ← Lean.getEnv
  match table? with
  | none =>
    let w ← walk env cfg roots
    return (← render cfg roots w, none)
  | some table =>
    let ix := table.index
    let (w, st) := Id.run <|
      (walk (m := StateM Informal.JunkValues.ScanState) env cfg roots
        (fun e => Informal.JunkValues.observe ix e.site.name e.site.origin e.depth)).run {}
    let result ← render cfg roots w
    let heads := Informal.JunkValues.guardHeadsOfAll
      (roots.filterMap fun n => (env.find? n).map (·.type))
    return (result,
      some (Informal.JunkValues.finish ix st heads w.truncated
        Informal.JunkValues.coverageMeaningClosure))

/-! ## Wire format

The subprocess boundary. Both sides of it live here so the shape cannot drift: the tool
writes `Result.toJson`, the build-time driver reads it back with `Result.ofJson?`.
-/

/-- Schema version of the job spec and the result document.

Version 2 added each entry's `uses`, the edge structure the meaning graph is drawn from.
Version 3 adds the caveat scan: a `caveatTable` input on the job and a `caveats` report on
the output. The scan rides this walk rather than running a second one — a second traversal
over the same edges would be a second chance to disagree with the first — so it belongs to
this document rather than to a subprocess run of its own. -/
def schemaVersion : Nat := 3

def Entry.toJson (e : Entry) : Json :=
  Json.mkObj <|
    [("name", Json.str e.name), ("origin", Json.str e.origin), ("kind", Json.str e.kind),
      ("depth", Json.num e.depth)]
    ++ (if e.auxiliary then [("auxiliary", Json.bool true)] else [])
    ++ (if e.signature.isEmpty then [] else [("signature", Json.str e.signature)])
    ++ (if e.definesModule.isEmpty then [] else [("definesModule", Json.str e.definesModule)])
    ++ (if e.uses.isEmpty then [] else [("uses", Json.arr (e.uses.map Json.str))])

def Entry.ofJson? (j : Json) : Except String Entry := do
  let str (k : String) : String := (j.getObjValAs? String k).toOption.getD ""
  let name := str "name"
  if name.isEmpty then throw "closure entry has no 'name'"
  return {
    name
    origin := str "origin"
    kind := str "kind"
    auxiliary := (j.getObjValAs? Bool "auxiliary").toOption.getD false
    depth := (j.getObjValAs? Nat "depth").toOption.getD 0
    signature := str "signature"
    definesModule := str "definesModule"
    uses := (j.getObjValAs? (Array String) "uses").toOption.getD #[]
  }

def Result.toJson (r : Result) : Json :=
  Json.mkObj [
    ("roots", Json.arr (r.roots.map Json.str)),
    ("maxNodes", Json.num r.maxNodes),
    ("truncated", Json.bool r.truncated),
    ("total", Json.num r.total),
    ("outsideMathlib", Json.num r.outsideMathlib),
    ("untrusted", Json.num r.untrusted),
    -- An array of pairs rather than an object: the origin bucket of an unrecognized
    -- module root is that root's own name, and a reader of this document should not have
    -- to enumerate object keys to find one.
    ("counts", Json.arr (r.counts.map fun (origin, count) =>
      Json.mkObj [("origin", Json.str origin), ("count", Json.num count)])),
    ("entries", Json.arr (r.entries.map Entry.toJson))
  ]

def Result.ofJson? (j : Json) : Except String Result := do
  let entriesJson := (j.getObjVal? "entries").toOption.getD (Json.arr #[])
  let mut entries : Array Entry := #[]
  for e in entriesJson.getArr?.toOption.getD #[] do
    entries := entries.push (← Entry.ofJson? e)
  let countsJson := ((j.getObjVal? "counts").toOption.getD (Json.arr #[])).getArr?.toOption.getD #[]
  let counts : Array (String × Nat) := countsJson.foldl (init := #[]) fun acc c =>
    let origin := (c.getObjValAs? String "origin").toOption.getD ""
    if origin.isEmpty then acc
    else acc.push (origin, (c.getObjValAs? Nat "count").toOption.getD 0)
  return {
    roots := ((j.getObjValAs? (Array String) "roots").toOption.getD #[])
    maxNodes := (j.getObjValAs? Nat "maxNodes").toOption.getD 0
    truncated := (j.getObjValAs? Bool "truncated").toOption.getD false
    total := (j.getObjValAs? Nat "total").toOption.getD entries.size
    outsideMathlib := (j.getObjValAs? Nat "outsideMathlib").toOption.getD 0
    untrusted := (j.getObjValAs? Nat "untrusted").toOption.getD 0
    counts
    entries
  }

/-- One chain file as the tool read it: the path it was given, and the digest of the
bytes it hashed and elaborated. §A1's binding compares these against what the verifying
run recorded, so they are a statement about the bytes that produced *this* closure. -/
structure ChainDigest where
  path : String
  sha256 : String
deriving Inhabited, Repr, BEq

/-- What the tool reports about the chain it elaborated, alongside the closure. -/
structure Provenance where
  /-- Chain files in elaboration order, with the digest of the bytes read. -/
  files : Array ChainDigest := #[]
  /-- Every module the run loaded, across the whole chain. Deliberately **not** what any
  one file elaborated against: each chain file gets its own declared imports plus those of
  the earlier chain files it imports, and nothing a later file declared (CX-044). -/
  imports : Array String := #[]
  /-- Imports satisfied by an earlier chain file rather than by an olean. -/
  chainInternalImports : Array String := #[]
  /-- Whether the import set came from a caller-supplied override rather than from the
  chain's own headers. -/
  importsOverridden : Bool := false
deriving Inhabited

def Provenance.toJson (p : Provenance) : Json :=
  Json.mkObj [
    ("files", Json.arr (p.files.map fun f =>
      Json.mkObj [("path", Json.str f.path), ("sha256", Json.str f.sha256)])),
    ("imports", Json.arr (p.imports.map Json.str)),
    ("chainInternalImports", Json.arr (p.chainInternalImports.map Json.str)),
    ("importsOverridden", Json.bool p.importsOverridden)
  ]

def Provenance.ofJson? (j : Json) : Except String Provenance := do
  let filesJson := ((j.getObjVal? "files").toOption.getD (Json.arr #[])).getArr?.toOption.getD #[]
  let mut files : Array ChainDigest := #[]
  for f in filesJson do
    let path := (f.getObjValAs? String "path").toOption.getD ""
    let sha256 := (f.getObjValAs? String "sha256").toOption.getD ""
    if path.isEmpty || sha256.isEmpty then
      throw "chain provenance entry is missing 'path' or 'sha256'"
    files := files.push { path, sha256 }
  return {
    files
    imports := (j.getObjValAs? (Array String) "imports").toOption.getD #[]
    chainInternalImports :=
      (j.getObjValAs? (Array String) "chainInternalImports").toOption.getD #[]
    importsOverridden := (j.getObjValAs? Bool "importsOverridden").toOption.getD false
  }

/-- The document the tool writes on success. -/
structure Report where
  provenance : Provenance := {}
  result : Result := {}
  /-- Names the elaborated chain itself declared, in declaration order. -/
  declared : Array String := #[]
  /-- The caveat scan that rode the same walk. `none` ⇒ the document predates the scan;
  a job that carried no table gets a `disabled` report rather than an absent one, so
  absence here means an old tool and nothing else. -/
  caveats? : Option Informal.JunkValues.ScanReport := none
deriving Inhabited

def Report.toJson (r : Report) : Json :=
  Json.mkObj <|
    [("ok", Json.bool true),
      ("schemaVersion", Json.num schemaVersion),
      ("chain", r.provenance.toJson),
      ("declared", Json.arr (r.declared.map Json.str)),
      ("closure", r.result.toJson)]
    ++ (match r.caveats? with
        | some c => [("caveats", Lean.toJson c)]
        | none => [])

def Report.ofJson? (j : Json) : Except String Report := do
  match (j.getObjValAs? Bool "ok").toOption with
  | some true => pure ()
  | _ =>
    let stage := (j.getObjValAs? String "stage").toOption.getD "unknown"
    let err := (j.getObjValAs? String "error").toOption.getD "no reason recorded"
    throw s!"{stage}: {err}"
  let version := (j.getObjValAs? Nat "schemaVersion").toOption.getD 0
  if version != schemaVersion then
    throw s!"closure document is schema version {version}; this build reads version {schemaVersion}"
  let provenance ← Provenance.ofJson? ((j.getObjVal? "chain").toOption.getD (Json.mkObj []))
  let result ← Result.ofJson? ((j.getObjVal? "closure").toOption.getD (Json.mkObj []))
  let caveats? ←
    match (j.getObjVal? "caveats").toOption with
    | none => pure none
    | some c =>
      match Lean.fromJson? (α := Informal.JunkValues.ScanReport) c with
      | .error err => throw s!"closure document's caveat report is unreadable: {err}"
      | .ok r => pure (some r)
  return {
    provenance
    result
    declared := (j.getObjValAs? (Array String) "declared").toOption.getD #[]
    caveats?
  }

/-- The document the tool writes when it cannot produce a closure. A half-result is never
written: either the whole walk succeeded or this says at which stage it stopped. -/
def errorJson (stage message : String) : Json :=
  Json.mkObj [
    ("ok", Json.bool false),
    ("schemaVersion", Json.num schemaVersion),
    ("stage", Json.str stage),
    ("error", Json.str message)
  ]

/-! ## Job spec -/

/-- A closure job, as the driver hands it to the tool. -/
structure Job where
  /-- Chain files in elaboration order: dependencies first, the primary Challenge last. -/
  files : Array String := #[]
  /-- Explicit import closure, replacing the one read from the chain's headers. `none` ⇒
  the headers decide, which is the normal case. An override is used verbatim — including
  the implicit `Init` a header carries, and its `meta` companion — so a list that omits
  what the chain needs fails at elaboration rather than being quietly repaired. -/
  importsOverride? : Option (Array String) := none
  /-- Certified theorem names to close over. -/
  roots : Array String := #[]
  maxNodes : Nat := defaultMaxNodes
  trustedRoots : Array String := defaultTrustedRoots.map (·.toString)
  subjectRoots : Array String := #[]
  signatureChars : Nat := 200
  /-- The effective caveat table, sent by value. The driver has already merged any consumer
  override over the bundled table and refused a bad one as a build error, so what arrives
  here is what the surface will name by version and digest. `none` ⇒ the caveat surface is
  off, and the tool reports that state rather than omitting the report. -/
  caveatTable? : Option Informal.JunkValues.Table := none
deriving Inhabited

def Job.toJson (job : Job) : Json :=
  Json.mkObj <|
    [("files", Json.arr (job.files.map Json.str)),
      ("roots", Json.arr (job.roots.map Json.str)),
      ("maxNodes", Json.num job.maxNodes),
      ("trustedRoots", Json.arr (job.trustedRoots.map Json.str)),
      ("subjectRoots", Json.arr (job.subjectRoots.map Json.str)),
      ("signatureChars", Json.num job.signatureChars)]
    ++ (match job.importsOverride? with
        | some imps => [("imports", Json.arr (imps.map Json.str))]
        | none => [])
    ++ (match job.caveatTable? with
        | some t => [("caveatTable", Lean.toJson t)]
        | none => [])

/-- Parse and validate a job spec. Validation is part of the boundary: a cap below
`capFloor` and an empty file or root list are rejected here rather than producing a
document that reads like an answer. -/
def Job.ofJson? (j : Json) : Except String Job := do
  let files := (j.getObjValAs? (Array String) "files").toOption.getD #[]
  if files.isEmpty then
    throw "job spec names no chain files ('files': [...])"
  let roots := (j.getObjValAs? (Array String) "roots").toOption.getD #[]
  if roots.isEmpty then
    throw "job spec names no root theorems ('roots': [...])"
  let maxNodes := (j.getObjValAs? Nat "maxNodes").toOption.getD defaultMaxNodes
  if maxNodes < capFloor then
    throw s!"job spec sets maxNodes to {maxNodes}; the floor is {capFloor}, below which a \
      truncated closure reports nothing a reader can use"
  let trustedRoots :=
    match (j.getObjVal? "trustedRoots").toOption with
    | some v => (Lean.fromJson? (α := Array String) v).toOption.getD #[]
    | none => defaultTrustedRoots.map (·.toString)
  -- A table that is present but unreadable is a refusal, not a silent fall-through to
  -- "no scan": the surface would then say the table found nothing.
  let caveatTable? ←
    match (j.getObjVal? "caveatTable").toOption with
    | none => pure none
    | some t =>
      match Informal.JunkValues.Table.ofJson? t with
      | .error err => throw s!"job spec's 'caveatTable' is unusable: {err}"
      | .ok table => pure (some table)
  return {
    files
    importsOverride? := (j.getObjVal? "imports").toOption.map fun v =>
      (Lean.fromJson? (α := Array String) v).toOption.getD #[]
    roots
    maxNodes
    trustedRoots
    subjectRoots := (j.getObjValAs? (Array String) "subjectRoots").toOption.getD #[]
    signatureChars := (j.getObjValAs? Nat "signatureChars").toOption.getD 200
    caveatTable?
  }

/-! ## §A1 — binding a closure to the recorded run

A closure is a statement about bytes. The bytes this build read are the ones the tool
hashed; the bytes the verifier checked are the ones the run recorded in
`challenge_chain`. The closure may be presented as adjacent to the verdict only when
those are the same bytes, in the same order — and a dep-only edit with a byte-identical
primary Challenge must drop the label, which is exactly why the whole ordered chain is
compared rather than the Challenge alone.
-/

/-- Whether a closure is bound to the recorded run, and what to say when it is not. -/
inductive Binding where
  /-- Every chain file matched the run record, in order. -/
  | bound
  /-- Not bound; the reason, in the register the page will use. -/
  | unbound (reason : String)
deriving Inhabited, Repr

/--
Compare the chain the tool actually read against the chain the verifying run recorded.

Fail-closed at every step: no record, a different length, a different file, or a
different digest all yield `unbound` with the specific reason. Paths compare by
path-component suffix, since the two records are rooted differently by design; digests
compare exactly (after the usual prefix/case normalization).
-/
def bindChain (read : Array ChainDigest) (recorded : Array (String × String)) : Binding :=
  if recorded.isEmpty then
    .unbound "the run record carries no challenge chain, so the files this site read are \
      tied to the verdict by nothing"
  else if read.isEmpty then
    .unbound "this build read no chain files, so there is nothing to compare against the \
      run record"
  else if read.size != recorded.size then
    .unbound s!"the run recorded {recorded.size} chain file(s); this build read \
      {read.size}"
  else Id.run do
    for i in [0:read.size] do
      let got := read[i]!
      let (wantPath, wantDigest) := recorded[i]!
      unless pathsAgree got.path wantPath do
        return .unbound s!"chain position {i + 1} is '{got.path}' here and '{wantPath}' in \
          the run record"
      let a := Informal.Sha256.normalizeDigest got.sha256
      let b := Informal.Sha256.normalizeDigest wantDigest
      unless a == b do
        return .unbound s!"'{got.path}' does not match the bytes the run recorded \
          (read {a}, recorded {b})"
    return .bound

/-- The `provenance` tag a bound/unbound closure carries into the payload. -/
def Binding.provenanceTag : Binding → String
  | .bound => "chain"
  | .unbound _ => "chain-unbound"

/-- The recorded reason; empty when bound. -/
def Binding.reason : Binding → String
  | .bound => ""
  | .unbound r => r

/-- The walk configuration a job asks for. -/
def Job.config (job : Job) : Config := {
  trustedRoots := job.trustedRoots.map String.toName
  subjectRoots := job.subjectRoots.map String.toName
  chainModules := #[]
  localIsChain := true
  maxNodes := job.maxNodes
  signatureChars := job.signatureChars
}

end Informal.StatementClosure
