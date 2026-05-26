/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean.CoreM
import Lean.EnvExtension
import VersoManual
import VersoBlueprint.Data

namespace Informal.Environment

open Lean
open Informal.Data

-- TODO: Consolidate with Data.Node
structure InProgress where
  label : Label
  kind : Data.InProgressKind := .proof
  codeHint : Option CodeRef := none
  parent : Option Parent := none
  priority : Option String := none
  owner : Option AuthorId := none
  tags : Array String := #[]
  effort : Option String := none
  prUrl : Option String := none
  deps : Array UseRef := #[]
  previewBlocks : Array (Verso.Doc.Block Verso.Genre.Manual) := #[]
  elabStx : Array Syntax := #[]
deriving Inhabited, Repr

inductive ImportedConflictKind where
  | node
  | group
  | author
deriving Inhabited, Repr, DecidableEq

structure ImportedConflict where
  kind : ImportedConflictKind
  label : Name
deriving Inhabited, Repr, DecidableEq

-- TODO: Consolidate with traversal information
structure State where
  data : Data := Data.empty
  localData : NameMap Node := {}
  groups : NameMap String := {}
  localGroups : NameMap String := {}
  authors : NameMap AuthorInfo := {}
  localAuthors : NameMap AuthorInfo := {}
  importedConflicts : Array ImportedConflict := #[]
  importedConflictsReported : Bool := false
  stack : List InProgress := []
deriving Inhabited, Repr

private def ImportedConflictKind.rank : ImportedConflictKind → Nat
  | .node => 0
  | .group => 1
  | .author => 2

def ImportedConflict.message (conflict : ImportedConflict) : String :=
  match conflict.kind with
  | .node => s!"Duplicate imported blueprint node label '{conflict.label}'"
  | .group => s!"Duplicate imported blueprint group label '{conflict.label}'"
  | .author => s!"Duplicate imported blueprint author id '{conflict.label}'"

private def pushImportedConflict (conflicts : Array ImportedConflict)
    (kind : ImportedConflictKind) (label : Name) : Array ImportedConflict :=
  let conflict : ImportedConflict := { kind, label }
  if conflicts.contains conflict then conflicts else conflicts.push conflict

private def sortImportedConflicts (conflicts : Array ImportedConflict) : Array ImportedConflict :=
  conflicts.qsort fun a b =>
    ImportedConflictKind.rank a.kind < ImportedConflictKind.rank b.kind ||
      (ImportedConflictKind.rank a.kind == ImportedConflictKind.rank b.kind &&
        a.label.toString < b.label.toString)

inductive Entry where
  | node (label : Name) (node : Node)
  | group (label : Name) (header : String)
  | author (label : Name) (info : AuthorInfo)
deriving Inhabited, Repr

initialize informalExt : PersistentEnvExtension Entry Entry State ←
  registerPersistentEnvExtension {
    mkInitial := pure {}
    addEntryFn state := fun
      | .node label node =>
        { state with
          data := state.data.insert label node
          localData := state.localData.insert label node
        }
      | .group label header =>
        { state with
          groups := state.groups.insert label header
          localGroups := state.localGroups.insert label header
        }
      | .author label info =>
        { state with
          authors := state.authors.insert label info
          localAuthors := state.localAuthors.insert label info
        }
    addImportedFn entries := do
      let (data, groups, authors, importedConflicts) := entries.foldl
          (init := (({} : NameMap Node), ({} : NameMap String), ({} : NameMap AuthorInfo), (#[] : Array ImportedConflict))) fun acc entry =>
        entry.foldl (init := acc) fun (dataAcc, groupAcc, authorAcc, conflictsAcc) item =>
          match item with
          | .node label node =>
            if dataAcc.contains label then
              (dataAcc, groupAcc, authorAcc, pushImportedConflict conflictsAcc .node label)
            else
              (dataAcc.insert label node, groupAcc, authorAcc, conflictsAcc)
          | .group label header =>
            if groupAcc.contains label then
              (dataAcc, groupAcc, authorAcc, pushImportedConflict conflictsAcc .group label)
            else
              (dataAcc, groupAcc.insert label header, authorAcc, conflictsAcc)
          | .author label info =>
            if authorAcc.contains label then
              (dataAcc, groupAcc, authorAcc, pushImportedConflict conflictsAcc .author label)
            else
              (dataAcc, groupAcc, authorAcc.insert label info, conflictsAcc)
      pure { data, groups, authors, importedConflicts := sortImportedConflicts importedConflicts }
    -- Strip transient elaboration cache before exporting nodes to the environment.
    exportEntriesFnEx env := fun state =>
      let nodeEntries := state.localData.toArray.map fun (name, node) =>
        let statement := node.statement.map fun s =>
          if s.previewBlocks.isEmpty then s else { s with elabStx := #[] }
        let proof := node.proof.map fun p =>
          if p.previewBlocks.isEmpty then p else { p with elabStx := #[] }
        Entry.node name { node with statement, proof }
      let groupEntries := state.localGroups.toArray.map fun (label, header) =>
        Entry.group label header
      let authorEntries := state.localAuthors.toArray.map fun (label, info) =>
        Entry.author label info
      OLeanEntries.uniform (nodeEntries ++ groupEntries ++ authorEntries)
  }

section EnvOps

variable [Monad m] [MonadEnv m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

def modify (f : State -> State) : m Unit :=
  modifyEnv (informalExt.modifyState · f)

def modifyM (f : State -> m State) : m Unit := do
  let st := informalExt.getState (← getEnv)
  let st ← f st
  modifyEnv (informalExt.setState · st)

def importedConflicts : m (Array ImportedConflict) := do
  return (informalExt.getState (← getEnv)).importedConflicts

def reportImportedConflicts : m Unit := do
  modifyM fun state => do
    if state.importedConflictsReported || state.importedConflicts.isEmpty then
      return state
    for conflict in state.importedConflicts do
      logError conflict.message
    return { state with importedConflictsReported := true }

-- XXX: needs: test
def checkLabelAndNesting (label : Label) (kind : Data.InProgressKind) : m Bool := do
  let { data, stack, .. } := informalExt.getState (← getEnv)
  match (kind, data.get? label, stack.isEmpty) with
  | (.statement _, none, true) => return true
  | (.statement _, some node, true) =>
    if node.statement.isNone then
      return true
    else do
      logError m!"Label {label} already defined"
      return false
  | (.proof, some node, true) =>
    if node.proof.isSome then
      logError m!"Label {label} already has a proof"
      return false
    else if node.statement.isNone then
      logError m!"Cannot add proof for {label}: statement/dependencies are missing"
      return false
    else
      return true
  | (.proof, none, true) =>
    logError m!"Cannot find proof for label {label}"
    return false
  | (_, _, false) =>
    logError m!"Cannot declare nested definitions"
    return false

-- stack operators, to associate {uses} role to the currently opened label
def push (label : Label) (kind : Data.InProgressKind)
    (codeHint : Option CodeRef := none) (parent : Option Parent := none) (priority : Option String := none)
    (owner : Option AuthorId := none) (tags : Array String := #[]) (effort : Option String := none)
    (prUrl : Option String := none) (useRefs : Array UseRef := #[]) : m Bool := do
  reportImportedConflicts
  let ok ← checkLabelAndNesting label kind
  if !ok then
    return false
  modify fun data =>
    let pdata := { label, kind, codeHint, parent, priority, owner, tags, effort, prUrl, deps := useRefs }
    { data with stack := pdata :: data.stack }
  return true

def getCount : m Nat := do
  return (informalExt.getState (← getEnv)).data.size

/-- When unwinding a nested declaration, discard only the nested frame and keep `data` unchanged. -/
def State.popNested? (state : State) : Option State :=
  match state.stack with
  | _ :: stack =>
    if stack.isEmpty then
      none
    else
      some { state with stack }
  | [] => none

def pop (ref : Syntax) : m Nat := do
  modifyM fun state => do
    if let some state := state.popNested? then
      return state
    else
      match state.stack with
      | [] =>
        logError m!"Internal Error: closing non-opened directive"
        return state
      | cur :: stack =>
        let payload : InformalData := {
          stx := ref
          deps := cur.deps
          previewBlocks := cur.previewBlocks
          elabStx := cur.elabStx
        }
        let data ← state.data.register
          cur.label cur.kind payload cur.codeHint cur.parent cur.priority cur.owner cur.tags cur.effort cur.prUrl
        let localData :=
          match data.get? cur.label with
          | some node => state.localData.insert cur.label node
          | none => state.localData
        return { state with data, localData, stack }
  getCount

def peek : m (Option InProgress) := do
  return (informalExt.getState (← getEnv)).stack.head?

def stack : m (List InProgress) := do
  return (informalExt.getState (← getEnv)).stack

def addUse (stx : Syntax) (useRef : UseRef) : m Unit := do
  match (informalExt.getState (← getEnv)).stack with
  | [] =>
    logErrorAt stx m!"uses declaration outside an informal enviroment"
    pure ()
  | cur :: rest =>
    let cur := {
      cur with
        deps := cur.deps.push useRef
    }
    let stack := cur :: rest
    modify fun state => { state with stack }

def addDep (stx : Syntax) (dep : Name) : m Unit := do
  addUse stx { label := dep }

def setStatementElab (stxs : Array Syntax) : m Unit := do
  match (informalExt.getState (← getEnv)).stack with
  | [] => pure ()
  | cur :: rest =>
    match cur.kind with
    | .proof => pure ()
    | .statement _ =>
      let cur := { cur with elabStx := stxs }
      modify fun state => { state with stack := cur :: rest }

def setPreviewBlocks (blocks : Array (Verso.Doc.Block Verso.Genre.Manual)) : m Unit := do
  match (informalExt.getState (← getEnv)).stack with
  | [] => pure ()
  | cur :: rest =>
    let cur := { cur with previewBlocks := blocks }
    modify fun state => { state with stack := cur :: rest }

def registerCode (label : Label) (code : Syntax)
    (definedDefs : Array LiterateDef := #[]) (definedTheorems : Array LiterateThm := #[]) : m Unit := do
  modifyM fun state => do
    let data ← state.data.registerCode label code definedDefs definedTheorems
    let localData :=
      match data.get? label with
      | some node => state.localData.insert label node
      | none => state.localData
    return { state with data, localData }

def registerRustCode (label : Label) (code : RustInlineCode) : m Unit := do
  modifyM fun state => do
    let data ← state.data.registerRustCode label code
    let localData :=
      match data.get? label with
      | some node => state.localData.insert label node
      | none => state.localData
    return { state with data, localData }

def registerTexSource (label : Label) (slot : String) (texSource : TexSource) : m Unit := do
  modifyM fun state => do
    let data ← state.data.registerTexSource label slot texSource
    let localData :=
      match data.get? label with
      | some node => state.localData.insert label node
      | none => state.localData
    return { state with data, localData }

def getNode? (label : Label) : m (Option Node) := do
  return (informalExt.getState (← getEnv)).data.get? label

def registerGroup (label : Label) (header : String) : m Unit := do
  reportImportedConflicts
  let header := header.trimAscii.toString
  modifyM fun state => do
    match state.groups.get? label with
    | none =>
      return {
        state with
        groups := state.groups.insert label header
        localGroups := state.localGroups.insert label header
      }
    | some currentHeader =>
      if currentHeader = header then
        logWarning m!"Group {label} is declared multiple times with the same header; keeping '{currentHeader}'"
      else
        logError m!"Group {label} has conflicting headers: existing '{currentHeader}', new '{header}'"
      return state

def getAuthor? (label : AuthorId) : m (Option AuthorInfo) := do
  return (informalExt.getState (← getEnv)).authors.get? label

def registerAuthor (label : AuthorId) (info : AuthorInfo) : m Unit := do
  reportImportedConflicts
  let info := {
    info with
      displayName := info.displayName.trimAscii.toString
      url := info.url.map (·.trimAscii.toString)
      imageUrl := info.imageUrl.map (·.trimAscii.toString)
  }
  modifyM fun state => do
    match state.authors.get? label with
    | none =>
      return {
        state with
        authors := state.authors.insert label info
        localAuthors := state.localAuthors.insert label info
      }
    | some currentInfo =>
      if currentInfo = info then
        logWarning m!"Author {label} is declared multiple times with the same metadata; keeping '{currentInfo.displayName}'"
      else
        logError m!"Author {label} has conflicting metadata definitions"
      return state

end EnvOps
