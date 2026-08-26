/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Emilio J. Gallego Arias, Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Lean
import VersoBlueprint.Process

namespace Informal.Git

/-- GitHub-backed repository metadata used for generated source links. -/
structure RepositoryInfo where
  root : System.FilePath
  githubUrl : String
  commit : String
deriving Inhabited, Repr

private def stripGitSuffix (url : String) : String :=
  if url.endsWith ".git" then
    match url.splitOn ".git" with
    | stem :: _ => stem
    | [] => url
  else
    url

/--
Normalize common GitHub remote URL spellings to browser URLs.

Non-GitHub remotes return `none`; current Blueprint source-link and build
metadata UI only know how to construct GitHub links.
-/
def githubRepositoryUrl? (url : String) : Option String :=
  let url := stripGitSuffix url.trimAscii.toString
  if url.startsWith "https://github.com/" then
    some url
  else if url.startsWith "http://github.com/" then
    some <| "https://github.com/" ++ (url.drop "http://github.com/".length).toString
  else if url.startsWith "git@github.com:" then
    some <| "https://github.com/" ++ (url.drop "git@github.com:".length).toString
  else if url.startsWith "ssh://git@github.com/" then
    some <| "https://github.com/" ++ (url.drop "ssh://git@github.com/".length).toString
  else
    none

def shortCommitAt? (dir : System.FilePath) : IO (Option String) :=
  Process.runTrimmedCommand? "git" #["-C", dir.toString, "rev-parse", "--short", "HEAD"]

def fullCommitAt? (dir : System.FilePath) : IO (Option String) :=
  Process.runTrimmedCommand? "git" #["-C", dir.toString, "rev-parse", "HEAD"]

def subjectAt? (dir : System.FilePath) : IO (Option String) :=
  Process.runTrimmedCommand? "git" #["-C", dir.toString, "log", "-1", "--pretty=%s"]

/--
Whether the worktree at `dir` has uncommitted changes (`git status --porcelain`
prints at least one entry).

`none` when the probe could not run (no git, not a repository). Callers use this
to qualify a displayed commit: a source link or build stamp naming commit `abc123`
is only accurate if the tree it was built from actually *is* `abc123`.
-/
def dirtyAt? (dir : System.FilePath) : IO (Option Bool) := do
  match ← Process.runCommandAllowingEmpty? "git"
      #["-C", dir.toString, "status", "--porcelain", "--untracked-files=no"] with
  | some out => pure (some !out.isEmpty)
  | none => pure none

def toplevelAt? (dir : System.FilePath) : IO (Option System.FilePath) := do
  let some root ← Process.runTrimmedCommand? "git" #["-C", dir.toString, "rev-parse", "--show-toplevel"]
    | return none
  pure <| some (System.FilePath.mk root)

def repositoryUrlAt? (dir : System.FilePath) : IO (Option String) := do
  match ← Process.runTrimmedCommand? "git" #["-C", dir.toString, "remote", "get-url", "origin"] with
  | some url => pure <| githubRepositoryUrl? url
  | none => pure none

def commitUrl? (repositoryUrl? commit? : Option String) : Option String :=
  match repositoryUrl?, commit? with
  | some repositoryUrl, some commit => some s!"{repositoryUrl}/commit/{commit}"
  | _, _ => none

def repositoryInfoAtRoot? (gitRoot : System.FilePath) : IO (Option RepositoryInfo) := do
  let some repositoryUrl ← repositoryUrlAt? gitRoot
    | return none
  let some commit ← fullCommitAt? gitRoot
    | return none
  pure <| some {
    root := gitRoot
    githubUrl := repositoryUrl
    commit
  }

/--
The one revision-and-dirty value a site build describes itself by.

Two things a generated site says about its own provenance have to agree: the build
stamp (`PreviewManifest.readBuildMetadata`) and every source link it publishes into the
project's *own* repository. They used to be sampled independently — the links at
elaboration, baked into the declaration registry and the external-ref snapshots and then
replayed from a warm `.lake` across commits; the stamp at generation, probed fresh. A
cache restored across two commits therefore published a clean current-`HEAD` stamp over
links naming an older revision, which is exactly the identity the trust page promises.

Both now read this record, probed once per process
(`Informal.RuntimeCache.currentBuildRevision`), and project-local links acquire their
revision from it at emission rather than at elaboration.

Every field is optional: a build outside a checkout, or on a machine without `git`, has
no revision to report and says so by omission rather than by guessing one.
-/
structure BuildRevision where
  /-- Git toplevel of the directory the build ran in. -/
  root? : Option System.FilePath := none
  /-- Browser URL of the `origin` remote, when it is a GitHub one. -/
  repositoryUrl? : Option String := none
  /-- Full 40-character `HEAD`. This is the revision source links name. -/
  fullCommit? : Option String := none
  /-- Abbreviated `HEAD`, for display in the build stamp. -/
  shortCommit? : Option String := none
  /-- Whether the worktree has uncommitted changes to tracked files. -/
  dirty? : Option Bool := none
deriving Inhabited, Repr

/-- Probe one checkout for the whole record. Each field degrades independently. -/
def buildRevisionAt (dir : System.FilePath) : IO BuildRevision := do
  let root? ← toplevelAt? dir
  let repositoryUrl? ← repositoryUrlAt? dir
  let fullCommit? ← fullCommitAt? dir
  let shortCommit? ← shortCommitAt? dir
  let dirty? ← dirtyAt? dir
  pure { root?, repositoryUrl?, fullCommit?, shortCommit?, dirty? }

/--
The commit as the *build stamp* names it: the abbreviated `HEAD`, marked `-dirty` when
the worktree had uncommitted changes — a stamp naming `abc1234` is only accurate if the
tree it was built from actually *is* `abc1234`.
-/
def BuildRevision.stampCommit? (rev : BuildRevision) : Option String :=
  match rev.shortCommit?, rev.dirty? with
  | some c, some true => some s!"{c}-dirty"
  | c, _ => c

/-- `origin`'s commit page for this revision. (Root-qualified: inside this namespace the
short name would resolve to this definition itself.) -/
def BuildRevision.commitUrl? (rev : BuildRevision) : Option String :=
  _root_.Informal.Git.commitUrl? rev.repositoryUrl? rev.fullCommit?

/--
The GitHub blob URL for a path relative to this repository's root, at this revision.

`none` when the build has no GitHub remote or no `HEAD` to name: a link that cannot be
composed is omitted, never guessed. A dirty worktree still links to the recorded `HEAD`
— that is the documented contract, and it is why the stamp marks such a build `-dirty`:
so the reader knows the link goes to the last commit rather than to what they are
looking at.
-/
def BuildRevision.blobUrl? (rev : BuildRevision) (relPath fragment : String) :
    Option String := do
  let url ← rev.repositoryUrl?
  let commit ← rev.fullCommit?
  return s!"{url}/blob/{commit}/{relPath}{fragment}"

end Informal.Git
