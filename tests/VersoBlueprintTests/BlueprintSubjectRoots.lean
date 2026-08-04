/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.DeclRegistry
import VersoBlueprint.ExternalRefSnapshot

/-!
Tests for `verso.blueprint.subjectModuleRoots`: presenting a formalization that
arrives as a Lake/git **dependency** rather than as the consumer's own source.

No fixture plumbing is needed, because this package already *is* that arrangement:
it requires SubVerso from git, so those sources sit at
`<package>/.lake/packages/subverso/src/SubVerso/…` — physically under the workspace
root, but inside a Lake package directory. That is exactly the shape a presentation
repo has when its whole subject corpus is a pinned git dependency, and exactly the
shape the automatic project-boundary harvest cannot see (it only ever finds modules
of authored `(lean := …)` declarations whose source is the consumer's own).
`SubVerso.Module` stands in for one subject module.
-/

namespace Verso.VersoBlueprintTests.BlueprintSubjectRoots

open Lean
open Informal Informal.DeclRegistry

/-! ## Option parsing -/

-- Comma-separated, trimmed, empty chunks skipped, duplicates collapsed, order kept.
-- Dotted entries stay dotted: a root names a module *prefix*, not one component.
/-- info: #["Foo", "Bar.Baz"] -/
#guard_msgs in
#eval
  (configuredSubjectModuleRoots
    ((∅ : Options).set `verso.blueprint.subjectModuleRoots " Foo , Bar.Baz ,, Foo ")).map toString

-- Unset ⇒ no configured roots, so the automatic harvest stays in charge.
/-- info: #[] -/
#guard_msgs in
#eval (configuredSubjectModuleRoots (∅ : Options)).map toString

/-! ## Module-root matching -/

-- A root matches itself and its descendants, and nothing that merely shares a
-- textual prefix (`isPrefixOf` is component-wise).
/-- info: (true, true, false, false) -/
#guard_msgs in
#eval
  let roots := ({} : NameSet).insert `SubVerso.Highlighting
  (isProjectModule roots `SubVerso.Highlighting,
   isProjectModule roots `SubVerso.Highlighting.Code,
   isProjectModule roots `SubVerso.Compat,
   isProjectModule roots `SubVersoOther)

/-! ## The `/.lake/` boundary -/

-- A dependency source physically under the workspace root is still a dependency.
/-- info: (true, false, false) -/
#guard_msgs in
#eval
  let root : System.FilePath := "/w/consumer"
  (isProjectSourcePath root "/w/consumer/Sub/Mod.lean",
   isProjectSourcePath root "/w/consumer/.lake/packages/dep/Dep/Mod.lean",
   isProjectSourcePath root "/elsewhere/Mod.lean")

-- The same rule now holds for the external-ref snapshot's provenance tag, which
-- used to call anything under the workspace prefix `.inWorkspace` — including
-- `.lake/packages/…`. `SubVerso.Module.Module` really does live in this package's
-- SubVerso checkout, and the subject-root option is set here for the same reason a
-- real consumer sets it package-wide: it is what makes that path resolvable at all,
-- so the reject branch is exercised against a real resolved path rather than
-- passing vacuously on an unresolved one.
/-- info: "out workspace" -/
#guard_msgs(info, drop warning) in
set_option verso.blueprint.subjectModuleRoots "SubVerso.Module" in
#eval show CoreM String from do
  let ref : Informal.Data.ExternalRef :=
    { written := `SubVerso.Module.Module, canonical := `SubVerso.Module.Module }
  let snap ← Informal.externalRefSnapshotAtCurrentDir {} ref
  return snap.provenance.label

/-! ## Subject roots drive the registry -/

-- The configured roots *are* the answer: the harvest is skipped entirely.
/-- info: ["SubVerso.Module"] -/
#guard_msgs in
set_option verso.blueprint.subjectModuleRoots "SubVerso.Module" in
#eval show CoreM (List String) from do
  return (← projectModuleRoots).toList.map toString

-- Enumeration reaches the dependency's declarations, and only those.
/-- info: true -/
#guard_msgs in
set_option verso.blueprint.subjectModuleRoots "SubVerso.Module" in
#eval show CoreM Bool from do
  let decls ← enumerateProjectDecls (← projectModuleRoots) (includePrivate := true)
  return !decls.isEmpty && decls.all fun (_, _, modName) => modName == `SubVerso.Module

/--
Assert, or fail the surrounding `#eval` with a named error.

The registry build logs its re-elaboration coverage unconditionally, and that
count is not something a test should pin, so the checks below run in a
message-dropping `#guard_msgs` and report failure through `throwError` instead of
through the `#eval` result.
-/
private def check (ok : Bool) (what : String) : CoreM Unit :=
  unless ok do throwError "subject-roots check failed: {what}"

-- The whole point of the option: a registry (and therefore an all-declarations
-- graph, declaration pages, and catalog pages) built entirely out of a dependency
-- package's modules — with source links that resolve against *that* package's own
-- checkout, not the consumer's.
#guard_msgs(drop info, drop warning) in
set_option verso.blueprint.subjectModuleRoots "SubVerso.Module" in
#eval show CoreM Unit from do
  let (registry, bodies) ← buildDeclRegistry
  check (registry.declCount > 0) "registry is empty"
  check (registry.decls.size == registry.declCount) "declCount disagrees with decls"
  check (registry.decls.all fun e => e.moduleName == "SubVerso.Module")
    "an entry came from outside the configured root"
  check (registry.decls.all fun e => e.sourcePath.endsWith "SubVerso/Module.lean")
    s!"an entry lost its dependency source path (first: {(registry.decls[0]?).map (·.sourcePath)})"
  -- Unwired throughout: no blueprint node claims these, so every one of them gets
  -- its own `decl/<slug>/` page (exactly one canonical page per entry).
  check (registry.decls.all fun e => e.nodeHref?.isNone && e.declHref?.isSome)
    "an entry is missing its decl-page route"
  check (registry.decls.all fun e =>
      match e.sourceHref? with
      | some href => (href.splitOn "/subverso/blob/").length > 1
      | none => false)
    s!"an entry is missing a source link into the dependency's own repository (first: {(registry.decls[0]?).map (·.sourceHref?)}, path {(registry.decls[0]?).map (·.sourcePath)})"
  check (!bodies.bodies.isEmpty) "no proof/value bodies were captured"

/-! ## The pinned checkout wins over a same-named neighbour -/

-- Absolute, because the resolution helpers under test interpret a relative path as
-- workspace-relative and would prepend the workspace root to it a second time.
private partial def freshFixtureRoot : IO System.FilePath := do
  let suffix ← IO.rand 0 1000000000000
  let root :=
    (← IO.currentDir) / ".lake" / "build" / "tmp" /
      "verso-blueprint-subject-roots-test" / toString suffix
  if ← root.pathExists then freshFixtureRoot else pure root

-- Substring test on a resolved path. A top-level helper because the comparison needs a
-- known `Bool` expected type; inline in an `Option.map` it elaborates as a `Prop`.
private def pathContains (path needle : String) : Bool :=
  (path.splitOn needle).length > 1

private def writeModuleFile (path : System.FilePath) (contents : String) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile path contents

/--
Lay out a consumer whose subject module arrives as a pinned Lake dependency while a
*different* checkout of the same module sits next to the consumer:

```
<fixture>/decoy/Fixture/Subject.lean                        -- sibling, wrong bytes
<fixture>/consumer/.lake/packages/pinned/Fixture/Subject.lean  -- the pinned source
```

`workspaceModuleSourcePath?` scans the parent's child directories, so the decoy is
reachable — and used to win, because the `.lake/packages` probe only ran as a last
resort. Source provenance would then depend on what happened to be checked out beside
the repository on that machine.
-/
private def writeNeighbourFixture : IO (System.FilePath × System.FilePath) := do
  let fixture ← freshFixtureRoot
  let consumer := fixture / "consumer"
  writeModuleFile (fixture / "decoy" / "Fixture" / "Subject.lean") "-- neighbouring clone\n"
  writeModuleFile
    (consumer / ".lake" / "packages" / "pinned" / "Fixture" / "Subject.lean")
    "-- the pinned dependency\n"
  pure (fixture, consumer)

-- The pinned dependency wins for a *subject* module even though the neighbour is
-- there to be found. (`Fixture.Subject` is not imported, so the source search path
-- cannot answer and the fallback chain is what is under test.)
/-- info: (true, false) -/
#guard_msgs in
set_option verso.blueprint.subjectModuleRoots "Fixture" in
#eval show CoreM (Bool × Bool) from do
  let (fixture, consumer) ← writeNeighbourFixture
  try
    let resolved := (← Informal.sourcePathForModule? consumer `Fixture.Subject).map toString
    let has (needle : String) : Bool := (resolved.map (pathContains · needle)).getD false
    return (has "/.lake/packages/pinned/Fixture/Subject.lean", has "/decoy/")
  finally
    IO.FS.removeDirAll fixture

-- Without the subject-root declaration nothing changes: a module the consumer has not
-- claimed keeps the outward scan (and so keeps finding the neighbour), because the
-- `.lake/packages` probe is deliberately scoped to declared subject modules.
/-- info: (false, true) -/
#guard_msgs in
#eval show CoreM (Bool × Bool) from do
  let (fixture, consumer) ← writeNeighbourFixture
  try
    let resolved := (← Informal.sourcePathForModule? consumer `Fixture.Subject).map toString
    let has (needle : String) : Bool := (resolved.map (pathContains · needle)).getD false
    return (has "/.lake/packages/pinned/Fixture/Subject.lean", has "/decoy/")
  finally
    IO.FS.removeDirAll fixture

/-! ## Diagnostics for a root that matches nothing -/

-- A typo'd root is reported once, and the remaining roots still work. (The
-- diagnostic is claimed per-process in `RuntimeCache`, since the registry, the
-- all-declarations graph, and the axiom audit each ask for the roots.)
/--
warning: verso.blueprint.subjectModuleRoots names `Bogus.Root.Alpha`, which matches no imported module; its declarations will be missing from the registry, the all-declarations graph, and the declaration pages.
---
info: ["Bogus.Root.Alpha", "SubVerso.Module"]
-/
#guard_msgs in
set_option verso.blueprint.subjectModuleRoots "SubVerso.Module, Bogus.Root.Alpha" in
#eval show CoreM (List String) from do
  return (← projectModuleRoots).toList.map toString

-- Asked again in the same process, the same root stays quiet.
/-- info: ["Bogus.Root.Alpha"] -/
#guard_msgs in
set_option verso.blueprint.subjectModuleRoots "Bogus.Root.Alpha" in
#eval show CoreM (List String) from do
  return (← projectModuleRoots).toList.map toString

end Verso.VersoBlueprintTests.BlueprintSubjectRoots
