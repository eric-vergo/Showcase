/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Lean.Data.Lsp.Communication
import VersoBlueprint.Data

namespace Informal.ForeignLsp

open Lean
open Lean.JsonRpc

register_option verso.blueprint.foreignLsp.timeoutMs : Nat := {
  defValue := 5000
  descr := "Timeout, in milliseconds, for best-effort foreign language-server definition requests"
}

register_option verso.blueprint.foreignLsp.idleShutdownMs : Nat := {
  defValue := 1000
  descr := "Idle time, in milliseconds, before cached foreign language-server processes are shut down"
}

register_option verso.blueprint.foreignLsp.rocq.command : String := {
  defValue := Informal.Data.ForeignLanguage.rocq.defaultCommand
  descr := "Executable used for Rocq foreign-reference LSP lookup"
}

register_option verso.blueprint.foreignLsp.rust.command : String := {
  defValue := Informal.Data.ForeignLanguage.rust.defaultCommand
  descr := "Executable used for Rust foreign-reference LSP lookup"
}

register_option verso.blueprint.foreignLsp.rocq.prelude : String := {
  defValue := ""
  descr := "Prelude prepended to synthetic Rocq lookup files"
}

register_option verso.blueprint.foreignLsp.rust.prelude : String := {
  defValue := ""
  descr := "Prelude prepended to synthetic Rust lookup files"
}

private def timeoutMs (opts : Options) : Nat :=
  opts.get
    verso.blueprint.foreignLsp.timeoutMs.name
    verso.blueprint.foreignLsp.timeoutMs.defValue

private def idleShutdownMs (opts : Options) : Nat :=
  opts.get
    verso.blueprint.foreignLsp.idleShutdownMs.name
    verso.blueprint.foreignLsp.idleShutdownMs.defValue

private def command (opts : Options) (language : Data.ForeignLanguage) : String :=
  let raw :=
    match language with
    | .rocq =>
      opts.get
        verso.blueprint.foreignLsp.rocq.command.name
        verso.blueprint.foreignLsp.rocq.command.defValue
    | .rust =>
      opts.get
        verso.blueprint.foreignLsp.rust.command.name
        verso.blueprint.foreignLsp.rust.command.defValue
  let raw := raw.trimAscii.toString
  if raw.isEmpty then language.defaultCommand else raw

private def prelude (opts : Options) (language : Data.ForeignLanguage) : String :=
  match language with
  | .rocq =>
    opts.get
      verso.blueprint.foreignLsp.rocq.prelude.name
      verso.blueprint.foreignLsp.rocq.prelude.defValue
  | .rust =>
    opts.get
      verso.blueprint.foreignLsp.rust.prelude.name
      verso.blueprint.foreignLsp.rust.prelude.defValue

def parseReferenceList (language : Data.ForeignLanguage) (raw : String) :
    Except String (Array String) := do
  let rawTrimmed := raw.trimAscii.toString
  if rawTrimmed.isEmpty then
    throw s!"'{language.key}' references must not be empty"
  let parts := raw.splitOn "," |>.toArray |>.map (·.trimAscii.toString)
  if parts.any (·.isEmpty) then
    throw s!"'{language.key}' references must be a comma-separated list of non-empty names"
  pure <| parts.foldl (init := #[]) fun acc ref =>
    if acc.contains ref then acc else acc.push ref

private partial def findLakeRootFrom (dir : System.FilePath) : IO (Option System.FilePath) := do
  if ← (dir / "lakefile.lean").pathExists then
    pure (some dir)
  else if ← (dir / "lakefile.toml").pathExists then
    pure (some dir)
  else
    match dir.parent with
    | none => pure none
    | some parent =>
      if parent == dir then
        pure none
      else
        findLakeRootFrom parent

private def packageRootForSource? (sourceFile : String) : IO (Option System.FilePath) := do
  if sourceFile.isEmpty || sourceFile.startsWith "<" then
    pure none
  else
    let sourcePath ←
      try
        IO.FS.realPath (System.FilePath.mk sourceFile)
      catch _ =>
        pure (System.FilePath.mk sourceFile)
    match sourcePath.parent with
    | none => pure none
    | some dir => findLakeRootFrom dir

private def countNewlines (s : String) : Nat :=
  s.foldl (init := 0) fun n c => if c == '\n' then n + 1 else n

private def asciiLength (s : String) : Nat :=
  s.length

private def sanitizePathText (s : String) : String :=
  s.map fun c => if c.isAlphanum then c else '_'

structure UseSite where
  written : String
  line : Nat
  character : Nat
deriving Repr, Inhabited, DecidableEq

structure SyntheticDocument where
  path : System.FilePath
  uri : String
  text : String
  preludeLastLine? : Option Nat := none
  uses : Array UseSite := #[]
deriving Repr, Inhabited, DecidableEq

private def headerFor (language : Data.ForeignLanguage) : String :=
  match language with
  | .rocq => "(* Verso Blueprint foreign reference lookups. *)\n"
  | .rust => "// Verso Blueprint foreign reference lookups.\n"

private def referenceCharacter (prefixText ref : String) : Nat :=
  asciiLength prefixText + if asciiLength ref > 1 then 1 else 0

private def useLineFor (language : Data.ForeignLanguage) (idx : Nat) (ref : String) : String × Nat :=
  match language with
  | .rocq =>
    let prefixText := "Check "
    (prefixText ++ ref ++ ".", referenceCharacter prefixText ref)
  | .rust =>
    let prefixText := s!"#[allow(dead_code)] fn __verso_blueprint_lookup_{idx}() \{ let _ = "
    (prefixText ++ ref ++ "; }", referenceCharacter prefixText ref)

def syntheticDocument
    (root : System.FilePath) (sourceFile : String)
    (language : Data.ForeignLanguage) (rawPrelude : String)
    (refs : Array String) : SyntheticDocument :=
  let preludeText := rawPrelude.trimAsciiEnd.toString
  let preludePart :=
    if preludeText.isEmpty then "" else preludeText ++ "\n\n"
  let preludeLastLine? :=
    if preludeText.isEmpty then none else some (countNewlines preludeText)
  let header := headerFor language
  let prefixText := preludePart ++ header
  let sourceName := sanitizePathText ((System.FilePath.mk sourceFile).fileName.getD "source")
  let syntheticPath :=
    root / ".verso-blueprint-foreign" /
      s!"{sourceName}.{language.key}.{language.sourceExtension}"
  let uri := (System.Uri.pathToUri syntheticPath : String)
  let startLine := countNewlines prefixText
  let (body, uses, _, _) := refs.foldl (init := ("", #[], startLine, 0)) fun (body, uses, line, idx) ref =>
    let (lineText, character) := useLineFor language idx ref
    (body ++ lineText ++ "\n", uses.push { written := ref, line, character },
      line + countNewlines lineText + 1, idx + 1)
  { path := syntheticPath, uri, text := prefixText ++ body, preludeLastLine?, uses }

private def structuredToJson : Json.Structured → Json
  | .arr values => .arr values
  | .obj fields => .obj fields

private def positionOfJson? (json : Json) : Except String Data.ForeignPosition := do
  let line ← json.getObjValAs? Nat "line"
  let character ← json.getObjValAs? Nat "character"
  pure { line, character }

private def rangeOfJson? (json : Json) : Except String Data.ForeignRange := do
  let start ← positionOfJson? (← json.getObjVal? "start")
  let stop ← positionOfJson? (← json.getObjVal? "end")
  pure { start, stop }

private structure DefinitionTarget where
  uri : String
  range : Data.ForeignRange
deriving Repr, Inhabited

private def targetOfJson? (json : Json) : Except String (Option DefinitionTarget) := do
  match json.getObjVal? "uri" with
  | .ok uriJson =>
    let uri ← fromJson? (α := String) uriJson
    let range ← rangeOfJson? (← json.getObjVal? "range")
    pure (some { uri, range })
  | .error _ =>
    match json.getObjVal? "targetUri" with
    | .ok uriJson =>
      let uri ← fromJson? (α := String) uriJson
      let rangeJson ←
        match json.getObjVal? "targetSelectionRange" with
        | .ok rangeJson => pure rangeJson
        | .error _ => json.getObjVal? "targetRange"
      let range ← rangeOfJson? rangeJson
      pure (some { uri, range })
    | .error _ =>
      pure none

private def firstDefinitionTarget? (json : Json) : Except String (Option DefinitionTarget) := do
  match json with
  | .null => pure none
  | .arr values =>
    values.foldlM (init := none) fun found? item =>
      match found? with
      | some _ => pure found?
      | none => targetOfJson? item
  | .obj _ => targetOfJson? json
  | _ => throw s!"unexpected definition response: {json.compress}"

private def sourceHref (target : DefinitionTarget) : String :=
  s!"{target.uri}#L{target.range.start.line + 1}"

private def rustIdentRest (c : Char) : Bool :=
  c.isAlphanum || c == '_'

private def rustLeadingIdentifier (token : String) : String :=
  let chars :=
    match token.toList with
    | 'r' :: '#' :: rest => rest
    | rest => rest
  String.ofList <| chars.takeWhile rustIdentRest

private def rustLineTokens (line : String) : List String :=
  let line := line.replace "\t" " " |>.replace "\r" " " |>.replace "\n" " "
  (line.splitOn " ").filter (!·.isEmpty)

private def rustItemKeywords : List String :=
  ["fn", "const", "static", "struct", "enum", "trait", "type"]

private partial def rustTokensDeclareReference (ref : String) : List String → Bool
  | keyword :: next :: rest =>
    (rustItemKeywords.contains keyword && rustLeadingIdentifier next == ref) ||
      rustTokensDeclareReference ref (next :: rest)
  | _ => false

private def rustDefinitionLineMatches (ref line : String) : Bool :=
  let text := line.trimAscii.toString
  !text.startsWith "//" && rustTokensDeclareReference ref (rustLineTokens text)

private def rustSnippetStartLine (lines : Array String) (targetLine : Nat) (ref : String) : Nat :=
  if lines.isEmpty then
    0
  else
    Id.run do
      let mut line := min targetLine (lines.size - 1)
      let mut start := line
      let mut done := false
      let mut remaining := 20
      while !done && remaining > 0 do
        let text := lines[line]!
        if rustDefinitionLineMatches ref text then
          start := line
          done := true
        else if line == 0 then
          done := true
        else
          line := line - 1
          remaining := remaining - 1
      while start > 0 do
        let prev := (lines[start - 1]!).trimAscii.toString
        if prev.startsWith "///" || prev.startsWith "#[" then
          start := start - 1
        else
          break
      return start

private def rustBraceDelta (line : String) : Int :=
  line.foldl (init := 0) fun acc c =>
    if c == '{' then
      acc + 1
    else if c == '}' then
      acc - 1
    else
      acc

private def rustSnippetEndLine (lines : Array String) (startLine : Nat) : Nat :=
  if lines.isEmpty then
    0
  else
    Id.run do
      let mut line := min startLine (lines.size - 1)
      let mut stop := line
      let mut depth : Int := 0
      let mut sawBrace := false
      let mut done := false
      while !done && line < lines.size do
        let text := lines[line]!
        let delta := rustBraceDelta text
        if delta != 0 then
          sawBrace := true
        depth := depth + delta
        stop := line
        if sawBrace && depth <= 0 then
          done := true
        else if !sawBrace && text.trimAscii.toString.endsWith ";" then
          done := true
        else
          line := line + 1
      return stop

private def linesSlice (lines : Array String) (startLine stopLine : Nat) : String :=
  let stopLine := min stopLine (lines.size - 1)
  String.intercalate "\n" <| (lines.extract startLine (stopLine + 1)).toList

private def rustSnippetOfSource? (ref : String) (targetLine : Nat) (source : String) :
    Option String :=
  if source.isEmpty then
    none
  else
    let lines := source.splitOn "\n" |>.toArray
    if lines.isEmpty then
      none
    else
      let startLine := rustSnippetStartLine lines targetLine ref
      let stopLine := rustSnippetEndLine lines startLine
      some (linesSlice lines startLine stopLine)

namespace Testing

def rustSnippetOfSource? (ref : String) (targetLine : Nat) (source : String) :
    Option String :=
  Informal.ForeignLsp.rustSnippetOfSource? ref targetLine source

end Testing

private def rustSnippetOfTarget? (ref : String) (target : DefinitionTarget) :
    IO (Option String) := do
  let some path := System.Uri.fileUriToPath? target.uri
    | pure none
  let source ←
    try
      IO.FS.readFile path
    catch _ =>
      pure ""
  pure <| rustSnippetOfSource? ref target.range.start.line source

private def sourceSnippetOfTarget?
    (language : Data.ForeignLanguage) (ref : String) (target : DefinitionTarget) :
    IO (Option String) := do
  match language with
  | .rust => rustSnippetOfTarget? ref target
  | .rocq => pure none

private def diagnosticOfJson? (json : Json) : Except String Data.ForeignDiagnostic := do
  let message ← json.getObjValAs? String "message"
  let range? :=
    match json.getObjVal? "range" with
    | .ok rangeJson => (rangeOfJson? rangeJson).toOption
    | .error _ => none
  pure { message, range? }

private def publishDiagnostics? (syntheticUri : String) (json : Json) :
    Option (Array Data.ForeignDiagnostic) := do
  let uri ← (json.getObjValAs? String "uri").toOption
  guard (uri == syntheticUri)
  let .arr diagnosticsJson ← (json.getObjVal? "diagnostics").toOption
    | some #[]
  let diagnostics := diagnosticsJson.filterMap fun item => (diagnosticOfJson? item).toOption
  some diagnostics

private abbrev serverStdio : IO.Process.StdioConfig where
  stdin := .piped
  stdout := .piped
  stderr := .null

private structure Server where
  serverId : Nat
  language : Data.ForeignLanguage
  command : String
  root : System.FilePath
  timeoutMsRef : IO.Ref Nat
  child : IO.Process.Child serverStdio
  stdin : IO.FS.Stream
  stdout : IO.FS.Stream
  diagnosticsRef : IO.Ref (Array Data.ForeignDiagnostic)
  readTaskRef : IO.Ref (Option (Task (Except IO.Error JsonRpc.Message)))
  nextIdRef : IO.Ref Nat
  openDocumentsRef : IO.Ref (Std.HashMap String Nat)
  useSeqRef : IO.Ref Nat
  lock : Std.Mutex Unit

private partial def waitForTaskWithTimeout
    (task : Task α)
    (timeoutMs : Nat)
    (pollMs : Nat := 50) : IO (Option α) := do
  let rec loop (remainingMs : Nat) : IO (Option α) := do
    if ← IO.hasFinished task then
      return some (← IO.wait task)
    if remainingMs == 0 then
      return none
    IO.sleep pollMs.toUInt32
    loop (remainingMs - min pollMs remainingMs)
  loop timeoutMs

private def Server.readMessageWithTimeout
    (server : Server) (timeoutMs : Nat) : IO (Option JsonRpc.Message) := do
  let task? ← server.readTaskRef.get
  let task ←
    match task? with
    | some task => pure task
    | none =>
      let task ← IO.asTask server.stdout.readLspMessage
      server.readTaskRef.set (some task)
      pure task
  match ← waitForTaskWithTimeout task timeoutMs with
  | none => pure none
  | some result =>
    server.readTaskRef.set none
    match result with
    | .ok msg => pure (some msg)
    | .error _ => pure none

private def collectDiagnostics
    (synthetic : SyntheticDocument)
    (diagnosticsRef : IO.Ref (Array Data.ForeignDiagnostic))
    (msg : JsonRpc.Message) : IO Unit := do
  match msg with
  | .notification "textDocument/publishDiagnostics" (some params) =>
    if let some diagnostics := publishDiagnostics? synthetic.uri (structuredToJson params) then
      diagnosticsRef.modify fun current => current ++ diagnostics
  | _ => pure ()

private def lspRequest (id : Nat) (method : String) (param : Json) : JsonRpc.Request Json :=
  { id := (id : RequestID), method, param }

private def lspNotification (method : String) (param : Json) : JsonRpc.Notification Json :=
  { method, param }

private def initializeParams (root : System.FilePath) : Json :=
  let rootUri := (System.Uri.pathToUri root : String)
  Json.mkObj [
    ("processId", toJson (0 : Int)),
    ("rootUri", toJson rootUri),
    ("capabilities", Json.mkObj []),
    ("workspaceFolders", toJson #[Json.mkObj [
      ("uri", toJson rootUri),
      ("name", toJson (root.fileName.getD root.toString))
    ]])
  ]

private def didOpenParams (language : Data.ForeignLanguage) (synthetic : SyntheticDocument) : Json :=
  Json.mkObj [
    ("textDocument", Json.mkObj [
      ("uri", toJson synthetic.uri),
      ("languageId", toJson language.languageId),
      ("version", toJson (0 : Nat)),
      ("text", toJson synthetic.text)
    ])
  ]

private def didChangeParams (synthetic : SyntheticDocument) (version : Nat) : Json :=
  Json.mkObj [
    ("textDocument", Json.mkObj [
      ("uri", toJson synthetic.uri),
      ("version", toJson version)
    ]),
    ("contentChanges", toJson #[Json.mkObj [
      ("text", toJson synthetic.text)
    ]])
  ]

private def definitionParams (synthetic : SyntheticDocument) (useSite : UseSite) : Json :=
  Json.mkObj [
    ("textDocument", Json.mkObj [("uri", toJson synthetic.uri)]),
    ("position", Json.mkObj [
      ("line", toJson useSite.line),
      ("character", toJson useSite.character)
    ])
  ]

private def configurationResponse (params? : Option Json.Structured) : Json :=
  match params?.map structuredToJson with
  | some params =>
    match params.getObjVal? "items" with
    | .ok (.arr items) => Json.arr (items.map fun _ => Json.null)
    | _ => Json.arr #[]
  | none => Json.arr #[]

private def workspaceFoldersResponse (root : System.FilePath) : Json :=
  let rootUri := (System.Uri.pathToUri root : String)
  Json.arr #[Json.mkObj [
    ("uri", toJson rootUri),
    ("name", toJson (root.fileName.getD root.toString))
  ]]

private def Server.respondToRequest
    (server : Server) (id : RequestID) (method : String) (params? : Option Json.Structured) :
    IO Unit := do
  let result :=
    match method with
    | "workspace/configuration" => configurationResponse params?
    | "workspace/workspaceFolders" => workspaceFoldersResponse server.root
    | "client/registerCapability" => Json.null
    | "window/showMessageRequest" => Json.null
    | _ => Json.null
  try
    server.stdin.writeLspResponse ({ id, result } : JsonRpc.Response Json)
  catch _ =>
    pure ()

private partial def Server.waitForResponse
    (server : Server) (synthetic : SyntheticDocument) (id : RequestID) :
    IO (Except String Json) := do
  let rec loop : IO (Except String Json) := do
    let timeoutMs ← server.timeoutMsRef.get
    let some msg ← server.readMessageWithTimeout timeoutMs
      | return .error s!"language server response timed out after {timeoutMs}ms"
    match msg with
    | .request requestId method params? =>
      server.respondToRequest requestId method params?
      loop
    | .response msgId result =>
      collectDiagnostics synthetic server.diagnosticsRef msg
      if msgId == id then
        return .ok result
      else
        loop
    | .responseError msgId _code message _data =>
      collectDiagnostics synthetic server.diagnosticsRef msg
      if msgId == id then
        return .error message
      else
        loop
    | _ =>
      collectDiagnostics synthetic server.diagnosticsRef msg
      loop
  loop

private def Server.sendRequest (server : Server) (method : String) (param : Json) :
    IO RequestID := do
  let id ← server.nextIdRef.get
  server.nextIdRef.set (id + 1)
  server.stdin.writeLspRequest (lspRequest id method param)
  pure (id : RequestID)

private def Server.sendNotification (server : Server) (method : String) (param : Json) :
    IO Unit := do
  server.stdin.writeLspNotification (lspNotification method param)

private def Server.initialize (server : Server) (synthetic : SyntheticDocument) :
    IO (Except String Unit) := do
  let id ← server.sendRequest "initialize" (initializeParams server.root)
  match ← server.waitForResponse synthetic id with
  | .error err => pure (.error err)
  | .ok _ =>
    server.sendNotification "initialized" (Json.mkObj [])
    pure (.ok ())

private def Server.openOrChangeDocument (server : Server) (synthetic : SyntheticDocument) : IO Unit := do
  let openDocuments ← server.openDocumentsRef.get
  match openDocuments[synthetic.uri]? with
  | none =>
    server.sendNotification "textDocument/didOpen" (didOpenParams server.language synthetic)
    server.openDocumentsRef.modify (·.insert synthetic.uri 0)
  | some version =>
    let version := version + 1
    server.sendNotification "textDocument/didChange" (didChangeParams synthetic version)
    server.openDocumentsRef.modify (·.insert synthetic.uri version)

private def Server.hasOpenDocument (server : Server) (uri : String) : IO Bool := do
  pure <| (← server.openDocumentsRef.get).contains uri

private def foreignRefNeedsContentRetry (ref : Data.ForeignRef) : Bool :=
  ref.status == .failed &&
    match ref.message? with
    | some message => message.contains "content modified"
    | none => false

private def foreignRefNeedsDefinitionRetry (ref : Data.ForeignRef) : Bool :=
  foreignRefNeedsContentRetry ref || ref.status == .unresolved

private def Server.definitionAtOnce
    (server : Server) (synthetic : SyntheticDocument) (useSite : UseSite) :
    IO Data.ForeignRef := do
  let id ← server.sendRequest "textDocument/definition" (definitionParams synthetic useSite)
  match ← server.waitForResponse synthetic id with
  | .ok result =>
    match firstDefinitionTarget? result with
    | .ok (some target) =>
      let sourceSnippet? ← sourceSnippetOfTarget? server.language useSite.written target
      pure {
        written := useSite.written
        status := .resolved
        targetUri? := some target.uri
        targetRange? := some target.range
        sourceHref? := some (sourceHref target)
        sourceSnippet? := sourceSnippet?
      }
    | .ok none =>
      pure {
        written := useSite.written
        status := .unresolved
        message? := some "language server did not return a definition location"
      }
    | .error err =>
      pure {
        written := useSite.written
        status := .failed
        message? := some err
      }
  | .error err =>
    pure {
      written := useSite.written
      status := .failed
      message? := some err
    }

private partial def Server.drainDiagnostics
    (server : Server) (synthetic : SyntheticDocument) (timeoutMs : Nat := 100) :
    IO Unit := do
  match ← server.readMessageWithTimeout timeoutMs with
  | none => pure ()
  | some (.request requestId method params?) =>
    server.respondToRequest requestId method params?
    server.drainDiagnostics synthetic timeoutMs
  | some msg =>
    collectDiagnostics synthetic server.diagnosticsRef msg
    server.drainDiagnostics synthetic timeoutMs

private partial def Server.definitionAt
    (server : Server) (synthetic : SyntheticDocument) (useSite : UseSite) :
    IO Data.ForeignRef := do
  let rec loop (remainingRetries : Nat) : IO Data.ForeignRef := do
    let ref ← server.definitionAtOnce synthetic useSite
    if remainingRetries > 0 && foreignRefNeedsDefinitionRetry ref then
      server.drainDiagnostics synthetic 250
      IO.sleep 100
      loop (remainingRetries - 1)
    else
      pure ref
  loop 4

private def Server.shutdown (server : Server) : IO Unit := do
  try
    server.stdin.writeLspRequest (lspRequest 999999 "shutdown" Json.null)
  catch _ =>
    pure ()
  try
    server.stdin.writeLspNotification (lspNotification "exit" Json.null)
  catch _ =>
    pure ()

private def Server.terminate (server : Server) : IO Unit := do
  try server.shutdown catch _ => pure ()
  try server.child.kill catch _ => pure ()
  try discard server.child.tryWait catch _ => pure ()

private def Server.hasExited (server : Server) : IO Bool := do
  try
    pure (← server.child.tryWait).isSome
  catch _ =>
    pure true

private def Server.bumpUseSeq (server : Server) : IO Nat := do
  let seq := (← server.useSeqRef.get) + 1
  server.useSeqRef.set seq
  pure seq

private def Server.withLock (server : Server) (act : IO α) : IO α := do
  server.lock.atomically do
    liftM act

private def unavailableRef (ref message : String)
    (status : Data.ForeignLookupStatus := .unavailable) : Data.ForeignRef :=
  { written := ref, status, message? := some message }

private def attachmentWithMessage
    (language : Data.ForeignLanguage) (cmd : String) (root : String) (syntheticUri : String)
    (refs : Array String) (message : String)
    (status : Data.ForeignLookupStatus := .unavailable) : Data.ForeignAttachment :=
  {
    language
    command := cmd
    root
    syntheticUri
    refs := refs.map (fun ref => unavailableRef ref message status)
  }

private def preludeDiagnosticsOf
    (synthetic : SyntheticDocument) (diagnostics : Array Data.ForeignDiagnostic) :
    Array Data.ForeignDiagnostic :=
  match synthetic.preludeLastLine? with
  | none => #[]
  | some lastLine =>
    diagnostics.filter fun diagnostic =>
      match diagnostic.range? with
      | some range => range.start.line <= lastLine
      | none => true

private def writeSyntheticDocument (synthetic : SyntheticDocument) : IO (Except String Unit) := do
  try
    if let some dir := synthetic.path.parent then
      IO.FS.createDirAll dir
    IO.FS.writeFile synthetic.path synthetic.text
    pure (.ok ())
  catch e =>
    pure (.error s!"could not write synthetic lookup file '{synthetic.path}': {e}")

private def commandExists (cmd : String) : IO Bool := do
  if cmd.contains '/' then
    (System.FilePath.mk cmd).pathExists
  else
    match ← IO.getEnv "PATH" with
    | none => pure false
    | some pathText =>
      let dirs := pathText.splitOn ":"
      dirs.anyM fun dir =>
        if dir.isEmpty then
          pure false
        else
          (System.FilePath.mk dir / cmd).pathExists

initialize nextServerIdRef : IO.Ref Nat ← IO.mkRef 0

private def Server.start
    (root : System.FilePath) (language : Data.ForeignLanguage) (cmd : String)
    (timeoutMs : Nat) : IO (Except String Server) := do
  if !(← commandExists cmd) then
    return .error s!"could not find LSP command '{cmd}' on PATH"
  let child ←
    try
      IO.Process.spawn {
        toStdioConfig := serverStdio
        cmd
        cwd := some root
      }
    catch e =>
      return .error s!"could not start '{cmd}': {e}"
  IO.sleep 20
  if let some exitCode ← child.tryWait then
    return .error s!"language server '{cmd}' exited during startup with code {exitCode}"
  let serverId ← nextServerIdRef.modifyGet fun id => (id + 1, id)
  let timeoutMsRef ← IO.mkRef timeoutMs
  let diagnosticsRef ← IO.mkRef #[]
  let readTaskRef ← IO.mkRef none
  let nextIdRef ← IO.mkRef 0
  let openDocumentsRef ← IO.mkRef {}
  let useSeqRef ← IO.mkRef 0
  let lock ← Std.Mutex.new ()
  let stdin := IO.FS.Stream.ofHandle child.stdin
  let stdout := IO.FS.Stream.ofHandle child.stdout
  pure <| .ok {
    serverId
    language
    command := cmd
    root
    timeoutMsRef
    child
    stdin
    stdout
    diagnosticsRef
    readTaskRef
    nextIdRef
    openDocumentsRef
    useSeqRef
    lock
  }

initialize serverCacheRef : IO.Ref (Std.HashMap String Server) ← IO.mkRef {}
initialize serverCacheLock : Std.Mutex Unit ← Std.Mutex.new ()

private def serverCacheKey
    (language : Data.ForeignLanguage) (cmd : String) (root : System.FilePath) : String :=
  (Json.mkObj [
    ("language", toJson language),
    ("command", toJson cmd),
    ("root", toJson root.toString)
  ]).compress

private def startInitializedServer
    (root : System.FilePath) (language : Data.ForeignLanguage) (cmd : String)
    (synthetic : SyntheticDocument) (timeoutMs : Nat) : IO (Except String Server) := do
  match ← Server.start root language cmd timeoutMs with
  | .error message => pure (.error message)
  | .ok server =>
    match ← server.initialize synthetic with
    | .error err =>
      server.terminate
      pure (.error s!"could not initialize '{cmd}': {err}")
    | .ok _ =>
      pure (.ok server)

private def getOrStartServer
    (root : System.FilePath) (language : Data.ForeignLanguage) (cmd : String)
    (synthetic : SyntheticDocument) (timeoutMs : Nat) : IO (Except String Server) := do
  let key := serverCacheKey language cmd root
  serverCacheLock.atomically (m := IO) do
    liftM <| show IO (Except String Server) from do
      let cache ← serverCacheRef.get
      match cache[key]? with
      | some server =>
        if ← server.hasExited then
          server.terminate
          serverCacheRef.modify (·.erase key)
          match ← startInitializedServer root language cmd synthetic timeoutMs with
          | .error message => pure (Except.error message)
          | .ok server =>
            serverCacheRef.modify (·.insert key server)
            pure (Except.ok server)
        else
          server.timeoutMsRef.set timeoutMs
          pure (Except.ok server)
      | none =>
        match ← startInitializedServer root language cmd synthetic timeoutMs with
        | .error message => pure (Except.error message)
        | .ok server =>
          serverCacheRef.modify (·.insert key server)
          pure (Except.ok server)

private def clearServerCache : IO Unit := do
  let servers ← serverCacheLock.atomically (m := IO) do
    liftM <| show IO (Array Server) from do
      let cache ← serverCacheRef.get
      serverCacheRef.set {}
      pure <| cache.toList.map Prod.snd |>.toArray
  for server in servers do
    server.terminate

private def scheduleServerIdleShutdown (key : String) (server : Server) (idleMs : Nat) :
    IO Unit := do
  if idleMs == 0 then
    pure ()
  else
    let seq ← server.useSeqRef.get
    discard <| IO.asTask do
      IO.sleep idleMs.toUInt32
      server.withLock do
        if (← server.useSeqRef.get) == seq && !(← server.hasExited) then
          let shouldTerminate ← serverCacheLock.atomically (m := IO) do
            liftM <| show IO Bool from do
              let cache ← serverCacheRef.get
              match cache[key]? with
              | some cached =>
                if cached.serverId == server.serverId && (← server.useSeqRef.get) == seq then
                  serverCacheRef.modify (·.erase key)
                  pure true
                else
                  pure false
              | none => pure false
          if shouldTerminate then
            server.terminate

private def runDefinitionLookup
    (root : System.FilePath) (language : Data.ForeignLanguage) (cmd : String)
    (synthetic : SyntheticDocument) (refs : Array String) (timeoutMs idleShutdownMs : Nat) :
    IO Data.ForeignAttachment := do
  match ← writeSyntheticDocument synthetic with
  | .error message =>
    return attachmentWithMessage language cmd root.toString synthetic.uri refs message .failed
  | .ok _ => pure ()
  match ← getOrStartServer root language cmd synthetic timeoutMs with
  | .error message =>
    return attachmentWithMessage language cmd root.toString synthetic.uri refs message
  | .ok server =>
    let serverKey := serverCacheKey language cmd root
    let attachment ← server.withLock do
      try
        discard <| server.bumpUseSeq
        if ← server.hasExited then
          return attachmentWithMessage language cmd root.toString synthetic.uri refs
            s!"language server '{cmd}' exited before the request"
        server.timeoutMsRef.set timeoutMs
        server.diagnosticsRef.set #[]
        server.openOrChangeDocument synthetic
        server.drainDiagnostics synthetic 250
        let mut resolvedRefs : Array Data.ForeignRef := #[]
        for useSite in synthetic.uses do
          resolvedRefs := resolvedRefs.push (← server.definitionAt synthetic useSite)
        server.drainDiagnostics synthetic
        let diagnostics ← server.diagnosticsRef.get
        let attachment : Data.ForeignAttachment := {
          language
          command := cmd
          root := root.toString
          syntheticUri := synthetic.uri
          preludeDiagnostics := preludeDiagnosticsOf synthetic diagnostics
          refs := resolvedRefs
        }
        pure attachment
      catch e =>
        server.terminate
        pure <| attachmentWithMessage language cmd root.toString synthetic.uri refs
          s!"language server request failed: {e}" .failed
    scheduleServerIdleShutdown serverKey server idleShutdownMs
    pure attachment

initialize lookupCacheRef : IO.Ref (Std.HashMap String Data.ForeignAttachment) ← IO.mkRef {}

private def cacheKey
    (language : Data.ForeignLanguage) (cmd : String) (root : System.FilePath)
    (synthetic : SyntheticDocument) (refs : Array String) : String :=
  (Json.mkObj [
    ("language", toJson language),
    ("command", toJson cmd),
    ("root", toJson root.toString),
    ("uri", toJson synthetic.uri),
    ("text", toJson synthetic.text),
    ("refs", toJson refs)
  ]).compress

def lookup
    (opts : Options) (sourceFile : String)
    (language : Data.ForeignLanguage) (refs : Array String) : IO Data.ForeignAttachment := do
  let cmd := command opts language
  let some root ← packageRootForSource? sourceFile
    | return attachmentWithMessage language cmd "" "" refs
        "could not find a lakefile.lean or lakefile.toml root for this Blueprint source file"
  let synthetic := syntheticDocument root sourceFile language (prelude opts language) refs
  let key := cacheKey language cmd root synthetic refs
  if let some cached := (← lookupCacheRef.get)[key]? then
    return cached
  let attachment ← runDefinitionLookup root language cmd synthetic refs (timeoutMs opts) (idleShutdownMs opts)
  lookupCacheRef.modify fun cache => cache.insert key attachment
  pure attachment

def lookupAtCurrentFile
    (opts : Options) (language : Data.ForeignLanguage) (refs : Array String) :
    CoreM Data.ForeignAttachment := do
  let sourceFile ← getFileName
  liftM <| lookup opts sourceFile language refs

def clearCache : IO Unit := do
  lookupCacheRef.set {}
  clearServerCache

end Informal.ForeignLsp
