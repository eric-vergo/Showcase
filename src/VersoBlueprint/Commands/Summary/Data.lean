/- 
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import VersoBlueprint.Data
import VersoBlueprint.ProvedStatus

namespace Informal.Commands

open Lean

structure SorryItem where
  label : Name
  kind : String
  decl : Name
  isTheorem : Bool := false
  status : Data.ProvedStatus := .proved
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote SorryItem where
  quote s := mkCApp ``SorryItem.mk #[quote s.label, quote s.kind, quote s.decl, quote s.isTheorem, quote s.status]

structure MissingLeanDeclItem where
  label : Name
  kind : String
  written : Name
  canonical : Name
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote MissingLeanDeclItem where
  quote s := mkCApp ``MissingLeanDeclItem.mk #[quote s.label, quote s.kind, quote s.written, quote s.canonical]

structure RenderFailureItem where
  label : Name
  kind : String
  written : Name
  canonical : Name
  message : String
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote RenderFailureItem where
  quote s := mkCApp ``RenderFailureItem.mk #[quote s.label, quote s.kind, quote s.written, quote s.canonical, quote s.message]

structure IndexItem where
  label : Name
  kind : String
  leanObjects : List Name := []
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote IndexItem where
  quote s := mkCApp ``IndexItem.mk #[quote s.label, quote s.kind, quote s.leanObjects]

abbrev PendingInformalItem := IndexItem

structure ParentTheoremGroup where
  parent : Name
  header : String := ""
  entries : List IndexItem := []
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote ParentTheoremGroup where
  quote s := mkCApp ``ParentTheoremGroup.mk #[quote s.parent, quote s.header, quote s.entries]

structure EntryStatusCounts where
  completed : Nat := 0
  completedDepsNo : Nat := 0
  withSorries : Nat := 0
  noProof : Nat := 0
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote EntryStatusCounts where
  quote s := mkCApp ``EntryStatusCounts.mk
    #[
      quote s.completed,
      quote s.completedDepsNo,
      quote s.withSorries,
      quote s.noProof
    ]

structure PriorityItem where
  label : Name
  kind : String
  stage : String
  priority : Option String := none
  ownerDisplayName : Option String := none
  effort : Option String := none
  prUrl : Option String := none
  tags : List String := []
  statementStatus : String
  proofStatus : String := ""
  directUses : Nat := 0
  downstreamUses : Nat := 0
  leanObjects : List Name := []
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote PriorityItem where
  quote s := mkCApp ``PriorityItem.mk
    #[
      quote s.label,
      quote s.kind,
      quote s.stage,
      quote s.priority,
      quote s.ownerDisplayName,
      quote s.effort,
      quote s.prUrl,
      quote s.tags,
      quote s.statementStatus,
      quote s.proofStatus,
      quote s.directUses,
      quote s.downstreamUses,
      quote s.leanObjects
    ]

structure UsageItem where
  label : Name
  kind : String
  statementUses : Nat := 0
  proofUses : Nat := 0
  directUses : Nat := 0
  downstreamUses : Nat := 0
  leanObjects : List Name := []
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote UsageItem where
  quote s := mkCApp ``UsageItem.mk
    #[
      quote s.label,
      quote s.kind,
      quote s.statementUses,
      quote s.proofUses,
      quote s.directUses,
      quote s.downstreamUses,
      quote s.leanObjects
    ]

structure GroupHealthItem where
  parent : Name
  header : String := ""
  totalEntries : Nat := 0
  closedEntries : Nat := 0
  localOnlyEntries : Nat := 0
  readyEntries : Nat := 0
  blockedEntries : Nat := 0
  incompleteLeanEntries : Nat := 0
  unlockScore : Nat := 0
  nextPriority? : Option PriorityItem := none
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote GroupHealthItem where
  quote s := mkCApp ``GroupHealthItem.mk
    #[
      quote s.parent,
      quote s.header,
      quote s.totalEntries,
      quote s.closedEntries,
      quote s.localOnlyEntries,
      quote s.readyEntries,
      quote s.blockedEntries,
      quote s.incompleteLeanEntries,
      quote s.unlockScore,
      quote s.nextPriority?
    ]

structure CoverageSplit where
  informalOnly : Nat := 0
  readyToFormalize : Nat := 0
  formalizedWithoutAncestors : Nat := 0
  fullyClosed : Nat := 0
  blockedOrIncomplete : Nat := 0
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote CoverageSplit where
  quote s := mkCApp ``CoverageSplit.mk
    #[
      quote s.informalOnly,
      quote s.readyToFormalize,
      quote s.formalizedWithoutAncestors,
      quote s.fullyClosed,
      quote s.blockedOrIncomplete
    ]

structure DependencyLoadItem where
  label : Name
  kind : String
  statementDeps : Nat := 0
  proofDeps : Nat := 0
  totalDeps : Nat := 0
  directUses : Nat := 0
  downstreamUses : Nat := 0
  leanObjects : List Name := []
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote DependencyLoadItem where
  quote s := mkCApp ``DependencyLoadItem.mk
    #[
      quote s.label,
      quote s.kind,
      quote s.statementDeps,
      quote s.proofDeps,
      quote s.totalDeps,
      quote s.directUses,
      quote s.downstreamUses,
      quote s.leanObjects
    ]

structure DebtHotspotItem where
  parent : Name
  header : String := ""
  affectedEntries : Nat := 0
  incompleteDecls : Nat := 0
  missingDecls : Nat := 0
  totalDebt : Nat := 0
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote DebtHotspotItem where
  quote s := mkCApp ``DebtHotspotItem.mk
    #[
      quote s.parent,
      quote s.header,
      quote s.affectedEntries,
      quote s.incompleteDecls,
      quote s.missingDecls,
      quote s.totalDebt
    ]

structure OwnerRollupItem where
  owner : Name
  displayName : String := ""
  totalEntries : Nat := 0
  actionableEntries : Nat := 0
  quickWins : Nat := 0
  linkedPrs : Nat := 0
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote OwnerRollupItem where
  quote s := mkCApp ``OwnerRollupItem.mk
    #[
      quote s.owner,
      quote s.displayName,
      quote s.totalEntries,
      quote s.actionableEntries,
      quote s.quickWins,
      quote s.linkedPrs
    ]

structure TagRollupItem where
  tag : String
  totalEntries : Nat := 0
  actionableEntries : Nat := 0
  quickWins : Nat := 0
  linkedPrs : Nat := 0
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote TagRollupItem where
  quote s := mkCApp ``TagRollupItem.mk
    #[
      quote s.tag,
      quote s.totalEntries,
      quote s.actionableEntries,
      quote s.quickWins,
      quote s.linkedPrs
    ]

structure MetadataEntryItem where
  label : Name
  kind : String
  ownerDisplayName : Option String := none
  effort : Option String := none
  priority : Option String := none
  prUrl : Option String := none
  tags : List String := []
  leanObjects : List Name := []
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote MetadataEntryItem where
  quote s := mkCApp ``MetadataEntryItem.mk
    #[
      quote s.label,
      quote s.kind,
      quote s.ownerDisplayName,
      quote s.effort,
      quote s.priority,
      quote s.prUrl,
      quote s.tags,
      quote s.leanObjects
    ]

structure Summary where
  showDebugDiagnostics : Bool := false
  totalEntries : Nat := 0
  definitions : Nat := 0
  lemmas : Nat := 0
  theorems : Nat := 0
  corollaries : Nat := 0
  axioms : Nat := 0
  leanOnlyEntries : Nat := 0
  informalOnlyEntries : Nat := 0
  totalStatus : EntryStatusCounts := {}
  definitionStatus : EntryStatusCounts := {}
  lemmaStatus : EntryStatusCounts := {}
  theoremStatus : EntryStatusCounts := {}
  corollaryStatus : EntryStatusCounts := {}
  axiomStatus : EntryStatusCounts := {}
  pendingInformalEntries : List PendingInformalItem := []
  leanDecls : Nat := 0
  sorries : Nat := 0
  sorryDetails : List SorryItem := []
  missingLeanDecls : List MissingLeanDeclItem := []
  renderFailures : List RenderFailureItem := []
  definitionIndex : List IndexItem := []
  theoremLikeIndex : List IndexItem := []
  axiomIndex : List IndexItem := []
  theoremLikeByParent : List ParentTheoremGroup := []
  topPriorities : List PriorityItem := []
  mostUsed : List UsageItem := []
  groupHealth : List GroupHealthItem := []
  coverageSplit : CoverageSplit := {}
  heaviestPrerequisites : List DependencyLoadItem := []
  noPrerequisites : List IndexItem := []
  noDependents : List IndexItem := []
  proofDebtHotspots : List DebtHotspotItem := []
  quickWins : List PriorityItem := []
  ownerRollups : List OwnerRollupItem := []
  tagRollups : List TagRollupItem := []
  linkedPrs : List MetadataEntryItem := []
  missingOwners : List MetadataEntryItem := []
  missingEffort : List MetadataEntryItem := []
  untaggedEntries : List MetadataEntryItem := []
deriving Inhabited, FromJson, ToJson

open Syntax in
instance : Quote Summary where
  quote s := mkCApp ``Summary.mk
    #[
      quote s.showDebugDiagnostics,
      quote s.totalEntries,
      quote s.definitions,
      quote s.lemmas,
      quote s.theorems,
      quote s.corollaries,
      quote s.axioms,
      quote s.leanOnlyEntries,
      quote s.informalOnlyEntries,
      quote s.totalStatus,
      quote s.definitionStatus,
      quote s.lemmaStatus,
      quote s.theoremStatus,
      quote s.corollaryStatus,
      quote s.axiomStatus,
      quote s.pendingInformalEntries,
      quote s.leanDecls,
      quote s.sorries,
      quote s.sorryDetails,
      quote s.missingLeanDecls,
      quote s.renderFailures,
      quote s.definitionIndex,
      quote s.theoremLikeIndex,
      quote s.axiomIndex,
      quote s.theoremLikeByParent,
      quote s.topPriorities,
      quote s.mostUsed,
      quote s.groupHealth,
      quote s.coverageSplit,
      quote s.heaviestPrerequisites,
      quote s.noPrerequisites,
      quote s.noDependents,
      quote s.proofDebtHotspots,
      quote s.quickWins,
      quote s.ownerRollups,
      quote s.tagRollups,
      quote s.linkedPrs,
      quote s.missingOwners,
      quote s.missingEffort,
      quote s.untaggedEntries
    ]

end Informal.Commands
