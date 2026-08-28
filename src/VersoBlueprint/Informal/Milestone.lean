/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Opus 5 (Claude Code)
-/

import VersoManual

import VersoBlueprint.Data
import VersoBlueprint.DirectiveArgParsing
import VersoBlueprint.Environment
import VersoBlueprint.Informal.LabelArg
import VersoBlueprint.Informal.UseConfig
import VersoBlueprint.LabelNameParsing
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.Milestones.Data
import VersoBlueprint.Profiling
import VersoBlueprint.TraversalIndex

/-!
The `:::milestone` directive.

```
:::milestone "ms:period-family" (title := "The period family") (paper := "§3") (paper_url := "…") (row := 2) (uses := "ms:lattice, ms:uniformization") (members := "def:period-point, thm:exists-period-functions")
An informal sketch of this waypoint, in ordinary Verso prose.
:::
```

Every argument goes on the opening line. A Verso directive reads its arguments from
that line alone, so one wrapped onto a continuation line becomes the body's first
line instead — silently, and with consequences the author would not connect to a
line break: a milestone whose `members` were wrapped covers no nodes, and every
edge incident to it therefore comes out author-asserted.

**A milestone renders nothing where it is written.** It may be declared in any
document module, it is not tied to a chapter or to a position within one, and no
marker is left behind: its sketch appears only on the overview surface, which
assembles every milestone in declaration order. That is why `toHtml` returns
`.empty`, exactly as `:::group` and `:::author` do — and why the sketch prose has
to reach the overview through the traversal store rather than through the
document tree.
-/

open Verso Doc Elab
open Verso.Genre Manual
open Verso.ArgParse
open Lean.Doc.Syntax
open Lean Elab

namespace Informal

/-- Parsed arguments of a `:::milestone` directive. -/
structure MilestoneConfig where
  label : Data.Label
  labelSyntax : Syntax := Syntax.missing
  title : Option String := none
  paper : Option String := none
  paperUrl : Option String := none
  row : Option Nat := none
  uses : Array Data.Label := #[]
  members : Array Data.Label := #[]

section
variable [Monad m] [MonadInfoTree m] [MonadResolveName m] [MonadLiftT CoreM m] [MonadEnv m]
    [MonadError m] [MonadFileMap m] [MonadLog m] [AddMessageContext m] [MonadOptions m]

/-- `(paper := "§3")` rather than `(section := …)`: `section` is a Lean keyword.
`(row := n)` is a layout override for the overview graph and nothing else. -/
def MilestoneConfig.parse : ArgParse m MilestoneConfig :=
  (fun (labelArg : Verso.ArgParse.WithSyntax String) title paper paperUrl row uses members =>
    let parsedLabel := LabelArg.parse labelArg
    {
      label := parsedLabel.label
      labelSyntax := parsedLabel.labelSyntax
      title := title.map (·.trimAscii.toString)
      paper := paper.map (·.trimAscii.toString)
      paperUrl := paperUrl.map (·.trimAscii.toString)
      row
      uses := UseConfig.parseLabels uses
      members := UseConfig.parseLabels members
    }) <$> .positional `label (.withSyntax .string)
        <*> .named `title .string true
        <*> .named `paper .string true
        <*> .named `paper_url .string true
        <*> .named' `row true
        <*> .named `uses .string true
        <*> .named `members .string true

instance : FromArgs MilestoneConfig m where
  fromArgs := MilestoneConfig.parse

end

/-!
The milestone block carries its label and title so traversal can key the sketch,
and it renders nothing.

The sketch prose travels as this block's *contents*. Traversal stashes them in a
runtime-cache store keyed by label — a semantic domain would publish the prose
into `xref.json`, which is not what a proof sketch is.
-/

open Verso Doc Elab Genre Manual in
block_extension Block.milestone (data : Milestones.MilestoneBlockData) where
  data := toJson data
  traverse _id data contents := do
    let some blockData ← ExtensionDecode.decode? (α := Milestones.MilestoneBlockData) data
        (fun err => s!"Malformed data in Block.milestone.traverse ({err})")
      | return none
    let sketch : Milestones.SketchData := {
      label := blockData.label
      title := blockData.title
      declOrder := blockData.declOrder
      contents
    }
    modify fun st =>
      Informal.TraversalIndex.Milestones.saveData st blockData.label (toJson sketch)
    return none
  toTeX := some <| fun _ _ _ _ _ => pure .empty
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI _goB _id _data _blocks => pure .empty

private def milestoneExpanderImpl : DirectiveExpanderOf MilestoneConfig
  | cfg, contents => do
    let contents ← contents.mapM elabBlock
    let title := (cfg.title.getD "").trimAscii.toString
    if title.isEmpty then
      logWarningAt cfg.labelSyntax
        m!"Milestone {Milestones.displayLabel cfg.label} has no title; using the label instead"
    let milestone : Milestones.Milestone := {
      label := cfg.label
      title := if title.isEmpty then Milestones.displayLabel cfg.label else title
      paper := cfg.paper.getD ""
      paperUrl := cfg.paperUrl.getD ""
      row? := cfg.row
      members := cfg.members
      uses := cfg.uses
    }
    match ← Environment.registerMilestone cfg.labelSyntax milestone with
    | none => ``(Block.concat #[$contents,*])
    | some blockData =>
      ``(Block.other (Block.milestone $(quote blockData)) #[$contents,*])

@[directive] def «milestone» : DirectiveExpanderOf MilestoneConfig
  | cfg, contents =>
    Profile.withDocElab "directive" "milestone" <|
      milestoneExpanderImpl cfg contents

end Informal
