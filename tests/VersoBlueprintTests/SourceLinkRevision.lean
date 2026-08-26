/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import VersoBlueprint.DeclRegistry
import VersoBlueprint.ExternalRefSnapshot
import VersoBlueprint.Git
import VersoBlueprint.RuntimeCache

/-!
Source links name the revision the site says it was built from (CX-066).

The defect: the declaration registry is built at elaboration and replayed from a warm
`.lake` across commits, while the build stamp probes git at generation. A cache restored
across two commits therefore published a clean current-`HEAD` stamp over 196 links naming
the older revision — with the trust page promising, verbatim, that `"View source" links
point at the commit the site was built from`.

The unit-level equivalent of that warm cache is direct, and it needs no second checkout:
produce the registry as elaboration produces it, then emit it under a *different*
revision and require the emitted links to name the emission revision. That it can be
written this way at all is the fix — the elaboration-time artifact no longer carries a
revision that could go stale.
-/

namespace Verso.VersoBlueprintTests.SourceLinkRevision

open Lean
open Informal
open Informal.DeclRegistry

private def hasSubstr (s needle : String) : Bool := (s.splitOn needle).length > 1

/-! ## Two revisions of one project -/

/-- The revision a warm `.lake` was populated at. -/
private def revA : Informal.Git.BuildRevision := {
  root? := some (System.FilePath.mk "/w/project")
  repositoryUrl? := some "https://github.com/eric-vergo/Example"
  fullCommit? := some "4fd434e57f92feff1b500f9b6b99fe106018176c"
  shortCommit? := some "4fd434e"
  dirty? := some false }

/-- The revision the site is emitted at. -/
private def revB : Informal.Git.BuildRevision := { revA with
  fullCommit? := some "f641fbd611d281226a306d0429ef965e1f0e04cd"
  shortCommit? := some "f641fbd" }

/-! ## A registry as elaboration leaves it -/

/-- A declaration in the project's own repository: repository-relative path, no revision. -/
private def projectEntry : Entry := {
  name := "Example.thm"
  kind := "Theorem"
  moduleName := "Example.Defs"
  sourcePath := "Example/Defs.lean"
  range? := some { pos := { line := 36, column := 0 }, endPos := { line := 39, column := 20 } }
  signatureText := "True"
  signatureHtml? := none
  status := "proved"
  sourceRepoPath? := some "Example/Defs.lean" }

/-- A declaration in a dependency checkout: already resolved, at the revision the lockfile
pins, which is not this build's to move. -/
private def depEntry : Entry := { projectEntry with
  name := "Mathlib.foo"
  moduleName := "Mathlib.Foo"
  sourcePath := "Mathlib/Foo.lean"
  sourceRepoPath? := none
  sourceHref? := some
    "https://github.com/leanprover-community/mathlib4/blob/\
     51e69921a26d4b0dd7d0fd93a7b1e8b2e5a2ec4d/Mathlib/Foo.lean#L36-L39" }

private def storedRegistry : Registry :=
  { namePrefix := "Example", declCount := 2, decls := #[projectEntry, depEntry] }

/-! ## The warm-cache drift, at the unit the fix acts on

Registry data produced under revision A, emitted under revision B: the links name B. The
old behavior is the first component of this pair being *equal* to the second — which is
what a warm cache produced, and what the build stamp beside it contradicted.
-/

/--
info: ("https://github.com/eric-vergo/Example/blob/4fd434e57f92feff1b500f9b6b99fe106018176c/Example/Defs.lean#L36-L39",
  "https://github.com/eric-vergo/Example/blob/f641fbd611d281226a306d0429ef965e1f0e04cd/Example/Defs.lean#L36-L39")
-/
#guard_msgs in
#eval
  let under := fun rev =>
    (((Registry.withResolvedSourceLinks rev storedRegistry).decls[0]!).sourceHref?).getD ""
  (under revA, under revB)

/-- The `/blob/<sha>/` component of a blob URL — the same thing the a362583 publishing gate
parses, so the property asserted here is the property CI enforces. -/
private def blobSha? (url : String) : Option String :=
  match url.splitOn "/blob/" with
  | _ :: rest :: _ => (rest.splitOn "/").head?
  | _ => none

-- The trust page's sentence, as an invariant rather than as a hope: every project-local
-- link the emitted registry carries names the revision it was emitted at, and everything
-- else is left exactly as it was. Quantified over both revisions and the whole registry,
-- which is what "by construction" means here.
/-- info: true -/
#guard_msgs in
#eval
  [revA, revB].all fun rev =>
    let resolved := (Registry.withResolvedSourceLinks rev storedRegistry).decls
    (storedRegistry.decls.zip resolved).all fun (stored, out) =>
      if stored.sourceRepoPath?.isSome then
        out.sourceHref?.bind blobSha? == rev.fullCommit?
      else
        out.sourceHref? == stored.sourceHref?

-- A dependency's link is left exactly as elaboration built it, and the internal path
-- field never reaches the published bytes.
/-- info: (true, true, true) -/
#guard_msgs in
#eval
  let resolved := Registry.withResolvedSourceLinks revB storedRegistry
  (resolved.decls[1]!.sourceHref? == depEntry.sourceHref?,
   resolved.decls.all (·.sourceRepoPath?.isNone),
   !hasSubstr (toJson resolved).compress "sourceRepoPath")

/-! ## The dirty case

The contract the trust page states is that a dirty build's link goes to the recorded
`HEAD` while the stamp says the tree is not that commit. Both halves come off one record,
so they cannot drift apart.
-/

/--
info: (some "f641fbd-dirty", some "f641fbd",
  some "https://github.com/eric-vergo/Example/blob/f641fbd611d281226a306d0429ef965e1f0e04cd/Example/Defs.lean#L36-L39")
-/
#guard_msgs in
#eval
  let dirty : Informal.Git.BuildRevision := { revB with dirty? := some true }
  (dirty.stampCommit?, revB.stampCommit?,
   ((Registry.withResolvedSourceLinks dirty storedRegistry).decls[0]!).sourceHref?)

/-! ## Degradation

A build with no GitHub remote, or none this fork can name, emits no link rather than a
guessed one — the same way every other probe in this stack degrades.
-/

/-- info: (none, none, some "https://e/blob/c/p#L1") -/
#guard_msgs in
#eval
  let noRemote : Informal.Git.BuildRevision := { fullCommit? := some "c" }
  let noCommit : Informal.Git.BuildRevision := { repositoryUrl? := some "https://e" }
  let full : Informal.Git.BuildRevision :=
    { repositoryUrl? := some "https://e", fullCommit? := some "c" }
  (Informal.resolveSourceHref? noRemote (some "p") "#L1" none,
   Informal.resolveSourceHref? noCommit (some "p") "#L1" none,
   Informal.resolveSourceHref? full (some "p") "#L1" none)

-- Line anchors are recomputed from the entry's own range, not carried alongside the path.
/-- info: ("#L36-L39", "#L36", "") -/
#guard_msgs in
#eval
  (Informal.sourceLineFragment 36 39, Informal.sourceLineFragment 36 36,
   Informal.sourceLineFragment 0 0)

/-! ## The stored artifact, through the one accessor that publishes it

`resolveStoredRegistry` is the only route from the traversal store to a registry with
publishable source links, and it reads the shared revision record. Asserted against
whatever revision this test run is at, so the property holds rather than a fixture.
-/

/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  let rev ← Informal.RuntimeCache.currentBuildRevision
  match ← resolveStoredRegistry (toJson storedRegistry).compress with
  | .error _ => return false
  | .ok resolved =>
    let expected := Informal.resolveSourceHref? rev (some "Example/Defs.lean") "#L36-L39" none
    return resolved.decls[0]!.sourceHref? == expected
      && resolved.decls[1]!.sourceHref? == depEntry.sourceHref?
      && resolved.decls.all (·.sourceRepoPath?.isNone)
      && !hasSubstr (toJson resolved).compress "sourceRepoPath"
      && resolved.schemaVersion == storedRegistry.schemaVersion

-- Emission now decodes and re-serializes what elaboration stored, where it used to copy
-- the stored bytes out verbatim. The claim that a clean same-revision build still emits
-- exactly the bytes it emitted before therefore rests on that round-trip being exact: a
-- registry whose links are all already final resolves to itself, and must come back
-- byte-for-byte as it went in.
/-- info: true -/
#guard_msgs in
#eval show IO Bool from do
  let depOnly : Registry := { storedRegistry with declCount := 1, decls := #[depEntry] }
  let raw := (toJson depOnly).compress
  match ← resolveStoredRegistry raw with
  | .error _ => return false
  | .ok resolved => return (toJson resolved).compress == raw

/-! ## Classification, against a real tree

This package is its own fixture for both sides: its sources are the project's, and the
SubVerso checkout it requires from git is a dependency's. The two must classify
differently, or the distinction the fix rests on is not being made.
-/

/-- info: (true, true) -/
#guard_msgs in
set_option verso.blueprint.subjectModuleRoots "SubVerso.Module" in
#eval show CoreM (Bool × Bool) from do
  let root ← Informal.workspaceRoot
  let ownLink ← liftM <| Informal.sourceLinkFor? {} root none
    (some (root / "src" / "VersoBlueprint" / "Git.lean")) none
  let depPath? ← Informal.sourcePathForModule? root `SubVerso.Module
  let depLink ← liftM <| Informal.sourceLinkFor? {} root (some `SubVerso.Module) depPath? none
  let ownIsProject :=
    match ownLink with
    | some (.project relPath) => relPath == "src/VersoBlueprint/Git.lean"
    | _ => false
  let depIsFixed :=
    match depLink with
    | some (.fixed url) => hasSubstr url "/subverso/blob/"
    | _ => false
  return (ownIsProject, depIsFixed)

-- The external-ref snapshot classifies the same way, so the copies of it that ride the
-- published manifest carry a repository-relative path rather than a revision that a warm
-- cache would strand.
/-- info: (true, true) -/
#guard_msgs(info, drop warning) in
#eval show CoreM (Bool × Bool) from do
  let ref : Informal.Data.ExternalRef :=
    { written := `Informal.Git.buildRevisionAt, canonical := `Informal.Git.buildRevisionAt }
  let snap ← Informal.externalRefSnapshotAtCurrentDir {} ref
  return (snap.sourceHref?.isNone,
    (snap.sourceRepoPath?.map (· == "src/VersoBlueprint/Git.lean")).getD false)

end Verso.VersoBlueprintTests.SourceLinkRevision
