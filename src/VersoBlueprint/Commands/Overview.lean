/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Opus 5 (Claude Code)
-/

import Lean
import Lean.Elab.Command
import Verso
import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.Commands.Graph
import VersoBlueprint.Environment
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Lib.HtmlId
import VersoBlueprint.Milestones.Render
import VersoBlueprint.TraversalIndex

/-!
`blueprint_overview` — the proof-overview surface.

```
{blueprint_overview}                     -- its own page, "Proof overview"
{blueprint_overview (page := false)}     -- a block in the current part
{blueprint_overview (title := "…")}      -- a different page/section title
```

**Why the checks live here and not in `GraphGate`.** The gate runs between
traversal and emission, where the Lean environment is gone; the project-declaration
graph (`buildProjectDeclGraph`) can only be built during elaboration, and it
deliberately never enters the traversal-cached master graph. This command
elaborates inside the document with every chapter's imports in scope, so it is the
one place that can consult both graphs — and a phantom member fails `lake build`
here, early and with a message that names the milestone.

**What is an error and what is a warning.** A member label that names no
blueprint node, a `uses` naming no milestone, a self-edge, and a pinned row that
contradicts a dependency are *defects*: they are reported with `logErrorAt` and
then recovered from, so the page still renders and a `#guard_msgs` test can
capture the message. An edge no graph witnesses is *not* a defect — a proof sketch
is allowed to record a mathematical dependency the Lean terms reach by another
route — so it warns once, draws dashed, wears a badge, and is counted on the
trust-model page.
-/

namespace Informal.Commands

open Lean Elab Command
open Informal Data Environment
open Informal.Milestones
open Verso Doc Html Genre Manual
open Verso.Output.Html
open Verso.ArgParse

register_option verso.blueprint.overview.witnessViaProjectDecls : Bool := {
  defValue := true
  descr := "Let `blueprint_overview` corroborate a milestone edge through the wider project-declaration graph when the presented blueprint graph has no dependency path for it. Requires `verso.blueprint.graph.includeAllDecls`; the extra graph is built only when at least one edge failed the presented-graph check."
}

register_option verso.blueprint.overview.maxMembersShown : Nat := {
  defValue := 24
  descr := "How many member nodes a milestone card lists before folding the rest into a `<details>` (0 ⇒ list every member)."
}

/-- Parsed arguments of `blueprint_overview`. `page` chooses between the standalone
page (the default) and a block in the current part; `title` renames both. -/
structure BlueprintOverviewConfig where
  page : Option Bool := none
  title : Option String := none

instance : FromArgs BlueprintOverviewConfig Verso.Doc.Elab.PartElabM where
  fromArgs :=
    BlueprintOverviewConfig.mk <$> .named' `page true <*> .named `title .string true

/-! ### Building the overview -/

/-- Distinct member labels across every milestone, in first-mention order. -/
private def allMemberLabels (ms : Array Milestone) : Array Name :=
  ms.foldl (init := (#[] : Array Name)) fun acc m =>
    m.members.foldl (init := acc) fun acc' l => if acc'.contains l then acc' else acc'.push l

/--
Assemble the overview, reporting every defect it finds.

`none` ⇒ the document declares no milestones, and the command emits nothing at
all: no page, no PM-hub link, no trust-model line.
-/
def buildOverviewData (stx : Syntax) (title : String) :
    Verso.Doc.Elab.PartElabM (Option OverviewData) := do
  let declared ← Environment.milestones
  if declared.isEmpty then
    return none
  let opts ← Lean.getOptions
  let maxMembersShown :=
    opts.get verso.blueprint.overview.maxMembersShown.name
      verso.blueprint.overview.maxMembersShown.defValue
  -- The presented blueprint graph: exactly the nodes and edges a reader sees.
  let presented ← buildAll
  let nodes := Milestones.nodeIndex presented
  let known : NameSet :=
    declared.foldl (init := ({} : NameSet)) fun acc m => acc.insert m.label
  -- Members that name no blueprint node are a defect; report each one and drop it,
  -- so the rest of the overview still builds.
  let mut sanitized : Array Milestone := #[]
  for m in declared do
    -- A milestone with no members covers nothing and can never witness an edge, so every
    -- edge incident to it comes out author-asserted. That is also exactly what a wrapped
    -- `(members := …)` looks like — a Verso directive reads its arguments from its opening
    -- line, and a continuation line becomes body prose — so the warning names the trap
    -- rather than leaving the author to explain a page of plausible, wrong numbers.
    if m.members.isEmpty then
      logWarningAt stx
        m!"Milestone {displayLabel m.label} lists no members — its edges can never be \
           witnessed; if the `(members := …)` argument was wrapped onto a continuation \
           line, put it on the directive's opening line"
    let mut members : Array Data.Label := #[]
    for mem in m.members do
      if members.contains mem then
        continue
      if nodes.contains mem then
        members := members.push mem
      else
        logErrorAt stx
          m!"Milestone {displayLabel m.label} lists member '{displayLabel mem}', which is not a \
             blueprint node label"
    let mut uses : Array Data.Label := #[]
    for u in m.uses do
      if uses.contains u then
        continue
      else if u == m.label then
        logErrorAt stx
          m!"Milestone {displayLabel m.label} depends on itself"
      else if !known.contains u then
        logErrorAt stx
          m!"Milestone {displayLabel m.label} depends on '{displayLabel u}', which is not a \
             declared milestone"
      else
        uses := uses.push u
    sanitized := sanitized.push { m with members, uses }
  -- Rows: longest-path depth over milestone edges, with author pins honored.
  let rowOf : Lean.NameMap Nat ←
    match Milestones.rows sanitized with
    | .ok rowOf => pure rowOf
    | .error msg =>
      logErrorAt stx m!"{msg}"
      -- Recover with a flat layout so the cards still render and the remaining
      -- diagnostics still reach the author in one build.
      pure (sanitized.foldl (init := ({} : Lean.NameMap Nat)) fun acc m => acc.insert m.label 0)
  -- Witness tier 1: a dependency path in the presented graph.
  let memberLabels := allMemberLabels sanitized
  let presentedAnc := Milestones.ancestorIndex presented memberLabels
  let byLabel : Lean.NameMap Milestone :=
    sanitized.foldl (init := ({} : Lean.NameMap Milestone)) fun acc m => acc.insert m.label m
  let mut verdicts : Array EdgeVerdict := #[]
  for m in sanitized do
    for u in m.uses do
      match byLabel.get? u with
      | Option.none => pure ()
      | some src =>
        match Milestones.witness? presentedAnc m src with
        | some (a, b) =>
          verdicts := verdicts.push
            { source := u, target := m.label, tier := .presented,
              witnessFrom := some a, witnessTo := some b }
        | Option.none =>
          verdicts := verdicts.push { source := u, target := m.label, tier := .asserted }
  -- Witness tier 2: the wider project-declaration graph, built lazily and only for
  -- the edges tier 1 could not corroborate. It is opt-in twice over, because it is
  -- the expensive one and because "witnessed through declarations this blueprint
  -- does not present" is a weaker statement that must be labelled as such.
  let projectDeclsAllowed :=
    verso.blueprint.graph.includeAllDecls.get opts &&
      opts.get verso.blueprint.overview.witnessViaProjectDecls.name
        verso.blueprint.overview.witnessViaProjectDecls.defValue
  let mut projectDeclsConsulted := false
  if projectDeclsAllowed && verdicts.any (·.isAsserted) then
    let project ← buildProjectDeclGraph presented
    if project.nodes.size > presented.nodes.size then
      projectDeclsConsulted := true
      let projectAnc := Milestones.ancestorIndex project memberLabels
      verdicts := verdicts.map fun e =>
        if !e.isAsserted then e
        else
          match byLabel.get? e.target, byLabel.get? e.source with
          | some tgt, some src =>
            match Milestones.witness? projectAnc tgt src with
            | some (a, b) =>
              { e with tier := .projectDecls, witnessFrom := some a, witnessTo := some b }
            | Option.none => e
          | _, _ => e
  -- Unwitnessed edges warn, once, naming them. They are never rejected.
  let asserted := verdicts.filter (·.isAsserted)
  unless asserted.isEmpty do
    let names := asserted.map fun e =>
      s!"{displayLabel e.target} → {displayLabel e.source}"
    logWarningAt stx
      m!"proof overview: {asserted.size} milestone edge(s) have no dependency path between the \
         two milestones' nodes, so they are shown as author-asserted: \
         {String.intercalate "; " names.toList}"
  -- Lay out and assemble.
  let mut anchors : Array String := #[]
  let mut milestones : Array OverviewMilestone := #[]
  for i in [0 : sanitized.size] do
    let m := sanitized[i]!
    let row := rowOf.getD m.label 0
    -- Position within the row is author order, which is the order this loop runs in.
    let column := (milestones.filter (·.row == row)).size
    -- Two labels can in principle sluggify alike; disambiguate rather than emit
    -- two cards with one id, exactly as the declaration-page emitter does.
    let base := Milestones.anchorSlug m.label
    let mut anchor := base
    let mut bump := 2
    while anchors.contains anchor do
      anchor := s!"{base}-{bump}"
      bump := bump + 1
    anchors := anchors.push anchor
    let members := m.members.filterMap (Milestones.memberStatus? nodes)
    milestones := milestones.push {
      label := m.label
      anchor
      title := m.displayTitle
      paper := m.paper
      paperUrl := m.paperUrl
      row
      column
      order := i + 1
      members
      memberTotal := members.size
      memberClosed := (members.filter (·.closed)).size
      memberReady := (members.filter (·.ready)).size
      uses := verdicts.filter (·.target == m.label)
    }
  let audit : Audit :=
    Milestones.auditOf milestones.size presented.nodes.size memberLabels.size verdicts
      projectDeclsConsulted
  if verso.blueprint.debug.commands.get opts then
    logInfo m!"Blueprint overview: {milestones.size} milestones, {verdicts.size} edges"
  return some {
    title
    milestones
    edges := verdicts
    audit
    maxMembersShown
  }

/-! ### The block -/

/--
Decode the `OverviewData` from `Block.proofOverview`'s flat compressed-JSON string.

The payload is a `String` rather than the structured value for the same reason
`Block.graph`'s is: `quote`ing an array of milestones, members and edges overflows
the LCNF code generator's recursion ceiling once a real blueprint's node labels are
in it. Degrades to `none` on any string/parse/schema failure.
-/
def decodeOverviewData? {m : Type → Type} [Monad m] [Verso.MonadBuildLog m]
    (data : Json) (context : String) : m (Option OverviewData) := do
  match data.getStr? with
  | .error err =>
    Verso.reportError s!"Malformed data in {context}: expected JSON string ({err})"
    pure none
  | .ok raw =>
    match Json.parse raw with
    | .error err =>
      Verso.reportError s!"Malformed data in {context}: JSON parse failed ({err})"
      pure none
    | .ok json =>
      Informal.ExtensionDecode.decode? (α := OverviewData) json
        (fun err => s!"Malformed data in {context} ({err})")

open Verso Doc Elab Genre Manual in
block_extension Block.proofOverview (payloadJson : String) where
  data := Json.str payloadJson
  traverse id data _contents := do
    match ← decodeOverviewData? data "Block.proofOverview.traverse" with
    | some overview =>
      let path ← (·.path) <$> read
      let _ ← Verso.Genre.Manual.externalTag id path "--bp-proof-overview"
      modify fun st =>
        let st := Informal.TraversalIndex.OverviewPage.saveId st id
        Informal.TraversalIndex.MilestoneAudit.saveData st overview.audit
    | Option.none => pure ()
    return none
  toTeX := none
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI goB id data _blocks => do
      match ← decodeOverviewData? data "Block.proofOverview.toHtml" with
      | Option.none => pure .empty
      | some overview =>
        let st ← HtmlT.state
        let idBase := Informal.HtmlId.prefixed "bp-ms" (toString id)
        -- The sketches live in the traversal store, because a `:::milestone`
        -- renders nothing where it is written. Render them through the genre's own
        -- block renderer so authored prose behaves exactly as it does anywhere else.
        let mut rendered : Array (Name × Verso.Output.Html) := #[]
        for m in overview.milestones do
          let html ←
            match Informal.TraversalIndex.Milestones.data? st m.label with
            | some sketch => Verso.Output.Html.seq <$> sketch.contents.mapM goB
            | Option.none => pure .empty
          rendered := rendered.push (m.label, html)
        let sketch := fun (label : Data.Label) =>
          match rendered.find? (fun e => e.1 == label) with
          | some e => e.2
          | Option.none => Verso.Output.Html.empty
        pure (Milestones.renderOverview st overview idBase sketch)
  extraCss := Milestones.overviewAssetBundle.css
  extraJs := Milestones.overviewAssetBundle.js

/-! ### The command -/

open Verso Doc Elab Syntax in
/-- The standalone overview page. The title is load-bearing: the emitted route is
derived from it (`Proof-overview/` by default). -/
def mkOverviewPart (stx : Syntax) (endPos : String.Pos.Raw) (title payloadJson : String) :
    PartElabM FinishedPart := do
  let titleLit : TSyntax `str := ⟨Syntax.mkStrLit title⟩
  let titleInlines ← `(inline| $titleLit:str)
  let expandedTitle ← #[titleInlines].mapM (elabInline ·)
  let metadata : Option (TSyntax `term) := some (← `(term| { number := false }))
  let block ← ``(Verso.Doc.Block.other
    (Informal.Commands.Block.proofOverview $(quote payloadJson)) #[])
  pure <| FinishedPart.mk stx stx expandedTitle title metadata #[block] #[] endPos

open Verso Doc Elab Syntax PartElabM in
@[part_command Lean.Doc.Syntax.command]
public meta def blueprintOverviewCmd : PartCommand
  | stx@`(block|command{blueprint_overview $args*}) => do
    let cfg ← Verso.ArgParse.parseThe BlueprintOverviewConfig (← parseArgs args)
    let requested := (cfg.title.getD "").trimAscii.toString
    let title := if requested.isEmpty then "Proof overview" else requested
    match ← buildOverviewData stx title with
    | Option.none =>
      logWarningAt stx
        m!"`blueprint_overview` found no `:::milestone` declarations, so no proof overview is \
           emitted"
    | some overview =>
      let payloadJson := (toJson overview).compress
      if cfg.page.getD true then
        let endPos := stx.getTailPos?.get!
        closePartsUntil 1 endPos
        addPart (← mkOverviewPart stx endPos title payloadJson)
      else
        PartElabM.addBlock (← ``(Verso.Doc.Block.other
          (Informal.Commands.Block.proofOverview $(quote payloadJson)) #[]))
  | _ => (Lean.Elab.throwUnsupportedSyntax : PartElabM Unit)

end Informal.Commands
