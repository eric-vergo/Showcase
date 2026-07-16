/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import Lean
import Verso
import VersoManual
import VersoBlueprint.Commands.Common
import VersoBlueprint.FormalizationYaml
import VersoBlueprint.ExternalRefSnapshot
import VersoBlueprint.Lib.ExtensionDecode
import VersoBlueprint.TraversalIndex
import VersoBlueprint.GraphApi
import VersoBlueprint.GraphChecks
import VersoBlueprint.NodeRoute

/-!
Dashboard trust strip.

A compact badge row surfaced with `blueprint_dashboard`: the statement-comparator
verdict plus a link to the project's `formalization.yaml` metadata page. It is fed
by build options naming machine-readable artifacts, read at elaboration time (paths
resolve against the build CWD, i.e. the consumer package root):

- `verso.blueprint.trust.formalizationYaml` — the project's
  `formalization.yaml` (v0.3).
- `verso.blueprint.trust.comparatorStatus` — a comparator-status JSON artifact
  (`{status, theorem_names, verified_at, note, ...}`); supplies the comparator
  badge, which links to the standalone `comparator/` page.

Degrades gracefully: an unset option silently omits its badge; a *set* option
naming a missing or unparsable file is a build error (a configured trust signal
must not vanish silently). When the document also renders a
`blueprint_formalization` page, the strip links to it (resolved through the
`FormalizationPage` traversal store, never a guessed slug). The strip renders only
when it carries a real trust signal (a configured comparator).
-/

namespace Informal.Commands

open Lean
open Verso Doc Html Genre Manual
open Verso.Output.Html

register_option verso.blueprint.trust.formalizationYaml : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the project's formalization.yaml; feeds the dashboard trust strip. Empty disables."
}

register_option verso.blueprint.trust.comparatorStatus : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to a comparator-status JSON artifact; feeds the dashboard trust strip's comparator badge. Empty disables."
}

register_option verso.blueprint.trust.comparatorConfig : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the comparator's configuration JSON; its contents are embedded verbatim (pretty-printed) on the comparator evidence page. Empty or missing ⇒ omitted (probe-and-degrade)."
}

register_option verso.blueprint.trust.challengeFile : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the comparator's Challenge Lean file; its contents are embedded verbatim on the comparator evidence page. Empty or missing ⇒ omitted (probe-and-degrade)."
}

register_option verso.blueprint.trust.solutionFile : String := {
  defValue := ""
  descr := "Path (relative to the build CWD) to the comparator's Solution Lean file; its contents are embedded verbatim on the comparator evidence page (after the Challenge file). Empty or missing ⇒ omitted (probe-and-degrade)."
}

register_option verso.blueprint.trust.requireConnected : Bool := {
  defValue := true
  descr := "Whether a disconnected `uses` graph (more than one weakly-connected component) FAILS the site build. Default true (a coherent formalization should be a single connected development). Set false for a deliberately multi-topic blueprint (independent example chapters): the connectivity check is then reported for information but does not gate the build. Acyclicity always hard-gates regardless."
}

register_option verso.blueprint.trust.ciRunUrl : String := {
  defValue := ""
  descr := "URL of the CI run that produced the comparator verdict (e.g. a GitHub Actions run). Used as a fallback for the comparator page's \"View CI run\" link when the status artifact carries no run_url of its own. Empty ⇒ no CI link (local builds). The consumer supplies this from its CI environment (it is not obtainable at site-build time)."
}

/-- Comparator verdict extracted from the comparator-status artifact.

`runUrl`/`configJson`/`challengeSource` are empty-string sentinels (matching the
other fields; empty ⇒ absent): the optional CI-run URL (from the status
artifact's `run_url` field, absent today ⇒ empty) and the verbatim contents of
the comparator config JSON / Challenge Lean file (embedded on the evidence page,
read from the `verso.blueprint.trust.comparatorConfig` / `.challengeFile`
options at elaboration; probe-and-degrade to empty). -/
structure TrustComparator where
  status : String := ""
  verifiedAt : String := ""
  theoremNames : List String := []
  note : String := ""
  runUrl : String := ""
  /-- The permitted axioms recorded in the comparator status artifact
  (`permitted_axioms`); rendered as the verdict header's axiom list. Empty ⇒ the row is
  omitted. -/
  permittedAxioms : List String := []
  /-- The comparator tool version the verdict was produced with (the status artifact's
  `tool_ref`, written by CI alongside the pinned checkout tag). Drives the `--branch` flag
  in the tier-3 reproduce commands; empty ⇒ no pinned version (the section shows a
  "check out the tag matching `lean-toolchain`" note instead). -/
  toolRef : String := ""
  /-- The comparator config path as passed on the command line (the status artifact's
  `config`, repo-root-relative) — exactly the argument the tier-3 reproduce command needs.
  Empty ⇒ recovered from the config blob URL when possible (`enrichTrustData`), else the
  run line is replaced by a README pointer. -/
  configArgPath : String := ""
  /-- The project's repository URL (derived from the first resolved challenge/solution/config
  blob URL in `enrichTrustData`). Adds a "clone the project" step to the tier-3 reproduce
  commands; empty ⇒ the commands run from the reader's own checkout. -/
  repoUrl : String := ""
  configJson : String := ""
  challengeSource : String := ""
  /-- Verbatim contents of the comparator's Solution Lean file (embedded on the
  evidence page after the Challenge file, read from the
  `verso.blueprint.trust.solutionFile` option; probe-and-degrade to empty). -/
  solutionSource : String := ""
  /-- Syntactically-highlighted HTML for `configJson` / `challengeSource` /
  `solutionSource` (built at elaboration by `enrichTrustData`; empty ⇒ the evidence
  page falls back to escaped plain text). `challengeHtml` / `solutionHtml` are the
  inner markup of a `<code class="hl lean">`. -/
  configHtml : String := ""
  challengeHtml : String := ""
  solutionHtml : String := ""
  /-- Outbound links for the Challenge / Solution sources (probe-and-degrade to empty
  when git info is unavailable): a GitHub blob URL at the pinned commit for the
  Challenge file, the Solution file, and the comparator config JSON, and a
  Lean-playground URL that opens the Challenge file against the playground's *current*
  Mathlib. -/
  githubChallengeUrl : String := ""
  githubSolutionUrl : String := ""
  githubConfigUrl : String := ""
  playgroundUrl : String := ""
  /-- Whether the comparator's independent nanoda-kernel replay is enabled, parsed from
  `enable_nanoda` in the comparator *config* JSON (the file behind
  `verso.blueprint.trust.comparatorConfig`) — NOT the status artifact, which carries no such
  field. Drives the nanoda clone/build lines in `reproCommands` and the "nanoda kernel" prose on
  the comparator page. Default `false` renders every page byte-identically to before. -/
  enableNanoda : Bool := false
deriving Inhabited, FromJson, ToJson, Quote

/-- Trust-strip payload: only fields present in the configured artifacts are set.
The `formalization.yaml`-derived scalars (`sorryCount` / `axioms` / `reviewStatus`)
are captured for downstream use; the strip and comparator page draw on `comparator`,
and the graph gate on `requireConnected`. -/
structure TrustData where
  sorryCount : Option Nat := none
  axioms : List String := []
  reviewStatus : String := ""
  comparator : Option TrustComparator := none
  /-- Whether a disconnected `uses` graph fails the build (item 1). Default `true`;
  a deliberately multi-topic blueprint sets `verso.blueprint.trust.requireConnected`
  false, and the connectivity check is then reported for information without gating. -/
  requireConnected : Bool := true
  /-- URL of the CI run that produced the comparator verdict, from the
  `verso.blueprint.trust.ciRunUrl` option (`none` ⇒ unset, e.g. a local build).
  Used as a fallback for the comparator page's "View CI run" link when the status
  artifact carries no `run_url` of its own. The SHA/run id lives in CI and is not
  readable at site-build time, so the consumer supplies it. -/
  ciRunUrl : Option String := none
deriving Inhabited, FromJson, ToJson, Quote

/-- The Mathlib project id used to open the Challenge file in the Lean 4 web
playground (`live.lean-lang.org`, `#project=<id>`). The exact id string is a
deployment detail of the playground; kept as a single easily-changed constant.
`MathlibDemo` is the `Projects/` folder name in the lean4web deployment (its
`leanweb-config.json` is `name := "Latest Mathlib"`, `default := true`), so even
if the id ever drifts the playground falls back to this default project. -/
def playgroundMathlibProjectId : String := "MathlibDemo"

/-- Extract the trust-relevant fields from a parsed `formalization.yaml` document. -/
def TrustData.ofFormalizationJson (doc : Json) : TrustData :=
  let status := (doc.getObjVal? "status").toOption.getD Json.null
  let review := (doc.getObjVal? "review").toOption.getD Json.null
  {
    sorryCount := (status.getObjValAs? Nat "sorry_count").toOption
    axioms := (status.getObjValAs? (List String) "axioms").toOption.getD []
    reviewStatus := (review.getObjValAs? String "status").toOption.getD ""
  }

/-- Extract the comparator verdict from a comparator-status artifact (`verified_at` may be `null`).
`run_url`, `permitted_axioms`, `tool_ref`, and `config` are all optional (absent in older
artifacts ⇒ empty-sentinel default). The embedded config / Challenge sources are filled in
later from their own options (`elabTrustData?`). -/
def TrustComparator.ofJson (j : Json) : TrustComparator :=
  {
    status := (j.getObjValAs? String "status").toOption.getD ""
    verifiedAt := (j.getObjValAs? String "verified_at").toOption.getD ""
    theoremNames := (j.getObjValAs? (List String) "theorem_names").toOption.getD []
    note := (j.getObjValAs? String "note").toOption.getD ""
    runUrl := (j.getObjValAs? String "run_url").toOption.getD ""
    permittedAxioms := (j.getObjValAs? (List String) "permitted_axioms").toOption.getD []
    toolRef := (j.getObjValAs? String "tool_ref").toOption.getD ""
    configArgPath := (j.getObjValAs? String "config").toOption.getD ""
  }

/-- The axioms every kernel-checked Mathlib development is expected to use. -/
def standardAxioms : List String := ["propext", "Classical.choice", "Quot.sound"]

/-- The axioms of `names` that are *not* one of the three standard ones. -/
def nonstandardAxioms (names : List String) : List String :=
  names.filter (fun a => !standardAxioms.contains a)

/-!
## Build-time JSON syntax highlighting

A tiny, total JSON tokenizer used to render the embedded comparator configuration on
the comparator evidence page. It reuses the shared Lean code-token classes
(`.hl.lean .const` for object keys, `.literal.string` / `.literal.number` for scalar
values, `.keyword` for `true`/`false`/`null`) so every color comes from the existing
`--verso-code-*` variables — no new color token, both themes for free. It never
fails: any character that does not begin a recognized token is emitted as base text,
so malformed input degrades to (escaped) plain text rather than throwing.
-/

open Verso.Output.Html in
/-- Tokenize a (pretty-printed) JSON string into themed token spans. Result is the
inner markup to wrap in `<code class="hl lean">`. -/
def highlightJsonHtml (src : String) : Output.Html := Id.run do
  let cs := src.data.toArray
  let n := cs.size
  let mut out : Array Output.Html := #[]
  let mut plain : String := ""
  let mut i : Nat := 0
  while i < n do
    let c := cs[i]!
    if c == '"' then
      if !plain.isEmpty then out := out.push (.text true plain); plain := ""
      -- String literal (keys and string values). Track escapes so an escaped quote
      -- does not close the string early.
      let mut j := i + 1
      let mut str : String := "\""
      let mut closed := false
      while j < n && !closed do
        let d := cs[j]!
        if d == '\\' && j + 1 < n then
          str := (str.push d).push cs[j+1]!
          j := j + 2
        else if d == '"' then
          str := str.push d
          j := j + 1
          closed := true
        else
          str := str.push d
          j := j + 1
      -- Object key iff the next non-whitespace character is a colon.
      let mut k := j
      while k < n && (cs[k]!).isWhitespace do k := k + 1
      let isKey := k < n && cs[k]! == ':'
      let cls := if isKey then "const" else "literal string"
      out := out.push (.tag "span" #[("class", cls)] (.text true str))
      i := j
    else if c.isDigit || (c == '-' && i + 1 < n && (cs[i+1]!).isDigit) then
      if !plain.isEmpty then out := out.push (.text true plain); plain := ""
      let mut j := i + 1
      while j < n &&
          (let d := cs[j]!; d.isDigit || d == '.' || d == 'e' || d == 'E' || d == '+' || d == '-') do
        j := j + 1
      let mut num : String := ""
      for p in [i:j] do num := num.push cs[p]!
      out := out.push (.tag "span" #[("class", "literal number")] (.text true num))
      i := j
    else if c.isAlpha then
      if !plain.isEmpty then out := out.push (.text true plain); plain := ""
      let mut j := i
      while j < n && (cs[j]!).isAlpha do j := j + 1
      let mut word : String := ""
      for p in [i:j] do word := word.push cs[p]!
      if word == "true" || word == "false" || word == "null" then
        out := out.push (.tag "span" #[("class", "keyword")] (.text true word))
      else
        out := out.push (.text true word)
      i := j
    else
      plain := plain.push c
      i := i + 1
  if !plain.isEmpty then out := out.push (.text true plain)
  return .seq out

/-!
## Comparator-source enrichment

At elaboration time the full environment (project + Mathlib) is available, so we can
syntax-highlight the comparator's config/Challenge/Solution blocks and resolve their
outbound source links (GitHub blob at the pinned commit + Lean-playground). Everything
here probes-and-degrades — a missing file or git remote yields empty fields, never a
build error.
-/

/-- Derive the `raw.githubusercontent.com` URL for a GitHub *blob* URL (splitting on
the first `/blob/` so a path segment literally named `blob` is preserved). `none` for
a non-GitHub URL. -/
def blobToRawGitHubUrl? (blob : String) : Option String :=
  let gh := "https://github.com/"
  if blob.startsWith gh then
    match ((blob.drop gh.length).toString).splitOn "/blob/" with
    | ownerRepo :: rest =>
      some s!"https://raw.githubusercontent.com/{ownerRepo}/{String.intercalate "/blob/" rest}"
    | [] => Option.none
  else Option.none

/-- The repository URL (everything before the first `/blob/`) of a GitHub *blob* URL, e.g.
`https://github.com/o/r/blob/<sha>/Path.lean` ↦ `https://github.com/o/r`. Splits on the
first `/blob/` only (so a path segment literally named `blob` is preserved). `none` for a
non-GitHub URL or one with no `/blob/` segment → degrade. -/
def blobToRepoUrl? (blob : String) : Option String :=
  let gh := "https://github.com/"
  if blob.startsWith gh then
    match ((blob.drop gh.length).toString).splitOn "/blob/" with
    | ownerRepo :: _ :: _ => some s!"https://github.com/{ownerRepo}"
    | _ => Option.none
  else Option.none

/-- The repo-root-relative path (everything after `/blob/<commit>/`) of a GitHub *blob* URL,
e.g. `https://github.com/o/r/blob/<sha>/Path/File.lean` ↦ `Path/File.lean`. Splits on the
first `/blob/` only, so a path segment literally named `blob` survives. `none` for a
non-GitHub URL or one with no `/blob/` segment → degrade. -/
def blobToRepoRelPath? (blob : String) : Option String :=
  let gh := "https://github.com/"
  if blob.startsWith gh then
    match ((blob.drop gh.length).toString).splitOn "/blob/" with
    | _ownerRepo :: rest@(_ :: _) =>
      -- `rest` rejoined is `<commit>/<path…>`; drop the leading commit segment.
      match (String.intercalate "/blob/" rest).splitOn "/" with
      | _commit :: pathSegs@(_ :: _) => some (String.intercalate "/" pathSegs)
      | _ => Option.none
    | _ => Option.none
  else Option.none

/-- The tier-3 "reproduce it yourself" shell commands, as a list of lines, derived purely
from a `TrustComparator` (unit-testable, total). Degrades with the data: the project-clone
line appears only with a `repoUrl`, the `--branch` flag only with a `toolRef`, and the final
`comparator` run line only with a `configArgPath` (otherwise the reproduce section points the
reader at the project README rather than guessing the config path). The tool is always cloned
as `comparator-tool` — a distinct directory that cannot collide with a project's own in-repo
`comparator/` folder (mirroring the CI checkout). When the comparator config enables the
independent nanoda kernel (`enableNanoda`), the flow also clones and builds `nanoda_lib` and
points the comparator at it via `COMPARATOR_NANODA`; the relative `../nanoda_lib/…` path resolves
because the run line first cd's into the project directory, a sibling of the two clones. -/
def reproCommands (cmp : TrustComparator) : List String :=
  let branchFlag := if cmp.toolRef.isEmpty then "" else s!"--branch {cmp.toolRef} "
  let cloneTool := s!"git clone {branchFlag}https://github.com/leanprover/comparator.git comparator-tool"
  let buildTool := "(cd comparator-tool && lake build lean4export comparator)"
  let nanodaBuild :=
    if cmp.enableNanoda then
      ["git clone https://github.com/ammkrn/nanoda_lib.git",
       "(cd nanoda_lib && cargo build --release --locked)"]
    else []
  let nanodaEnv :=
    if cmp.enableNanoda then "COMPARATOR_NANODA=../nanoda_lib/target/release/nanoda_bin " else ""
  let projectClone := if cmp.repoUrl.isEmpty then [] else [s!"git clone {cmp.repoUrl}"]
  let projectDir :=
    if cmp.repoUrl.isEmpty then "path/to/your/project"
    else ((cmp.repoUrl.splitOn "/").getLast?).getD "your-project"
  let runLines :=
    if cmp.configArgPath.isEmpty then []
    else [s!"cd {projectDir}", s!"{nanodaEnv}lake env ../comparator-tool/.lake/build/bin/comparator {cmp.configArgPath}"]
  projectClone ++ [cloneTool, buildTool] ++ nanodaBuild ++ runLines

/-- Absolute path of an option-configured path (relative to the build CWD). -/
private def absOptionPath (workspaceRoot : System.FilePath) (p : String) : System.FilePath :=
  let fp := System.FilePath.mk p
  if fp.isAbsolute then fp else workspaceRoot / p

open Informal in
/-- Fill in the comparator-source enrichment: syntax-highlighted config/Challenge/
Solution blocks and their source links (GitHub blob at the pinned commit +
Lean-playground). Runs in `CoreM` (environment + git available at elaboration); every
enrichment degrades to empty rather than failing. -/
def enrichTrustData (opts : Lean.Options) (trust : TrustData) : Lean.CoreM TrustData := do
  let workspaceRoot ← Informal.workspaceRoot
  let mut trust := trust
  -- Comparator: highlight the config/Challenge blocks and resolve the source links.
  if let some cmp := trust.comparator then
    let mut cmp := cmp
    if !cmp.configJson.isEmpty then
      cmp := { cmp with configHtml := (highlightJsonHtml cmp.configJson).asString }
    if !cmp.challengeSource.isEmpty then
      if let some html ← Informal.highlightModuleSourceHtml? cmp.challengeSource then
        cmp := { cmp with challengeHtml := html }
    if !cmp.solutionSource.isEmpty then
      if let some html ← Informal.highlightModuleSourceHtml? cmp.solutionSource then
        cmp := { cmp with solutionHtml := html }
    -- Blob URLs at the pinned commit, via the shared source-link builder (auto GitHub
    -- when the file is in a checkout with a GitHub `origin`; degrades to none).
    let chalPath := opts.get verso.blueprint.trust.challengeFile.name
      verso.blueprint.trust.challengeFile.defValue
    let solPath := opts.get verso.blueprint.trust.solutionFile.name
      verso.blueprint.trust.solutionFile.defValue
    let cfgPath := opts.get verso.blueprint.trust.comparatorConfig.name
      verso.blueprint.trust.comparatorConfig.defValue
    if !chalPath.isEmpty then
      if let some blob ← liftM <| sourceLinkHref? opts workspaceRoot none
          (some (absOptionPath workspaceRoot chalPath)) none then
        cmp := { cmp with githubChallengeUrl := blob }
        if let some raw := blobToRawGitHubUrl? blob then
          cmp := { cmp with
            playgroundUrl :=
              s!"https://live.lean-lang.org/#project={playgroundMathlibProjectId}&url={System.Uri.escapeUri raw}" }
    if !solPath.isEmpty then
      if let some blob ← liftM <| sourceLinkHref? opts workspaceRoot none
          (some (absOptionPath workspaceRoot solPath)) none then
        cmp := { cmp with githubSolutionUrl := blob }
    if !cfgPath.isEmpty then
      if let some blob ← liftM <| sourceLinkHref? opts workspaceRoot none
          (some (absOptionPath workspaceRoot cfgPath)) none then
        cmp := { cmp with githubConfigUrl := blob }
    -- Project repo URL for the tier-3 "clone the project" step: the repository of the first
    -- blob we managed to resolve. Degrades to empty when no GitHub remote is available.
    if let some blob := [cmp.githubChallengeUrl, cmp.githubSolutionUrl, cmp.githubConfigUrl].find?
        (fun u => !u.isEmpty) then
      if let some repo := blobToRepoUrl? blob then
        cmp := { cmp with repoUrl := repo }
    -- Config arg path for the tier-3 run line: prefer the status JSON's own `config` (already
    -- parsed by `ofJson`); otherwise recover it from the config blob's repo-root path.
    if cmp.configArgPath.isEmpty && !cmp.githubConfigUrl.isEmpty then
      if let some rel := blobToRepoRelPath? cmp.githubConfigUrl then
        cmp := { cmp with configArgPath := rel }
    trust := { trust with comparator := some cmp }
  return trust

/--
One trust badge. Reuses the dashboard's `.bp_summary_badge` classes (`variant`
is one of `""`/`success`/`warn`/`error`/`accent`); `title?` becomes a tooltip.
When `href?` is set the badge renders as an `<a>` linking to a page; otherwise it is
a plain `<span>`.
-/
def trustBadgeHtml (text : String) (variant : String := "")
    (title? : Option String := Option.none) (href? : Option String := Option.none) :
    Output.Html :=
  let className :=
    if variant.isEmpty then "bp_summary_badge"
    else s!"bp_summary_badge bp_summary_badge_{variant}"
  let attrs := #[("class", className)]
  let attrs :=
    match title? with
    | Option.some t => attrs.push ("title", t)
    | Option.none => attrs
  match href? with
  | Option.some href => .tag "a" (attrs.push ("href", href)) (.text true text)
  | Option.none => .tag "span" attrs (.text true text)

/-- The comparator verdict badge, linking to the standalone `comparator/` page. -/
def trustComparatorBadge (cmp : TrustComparator) : Output.Html :=
  let theoremsTitle :=
    if cmp.theoremNames.isEmpty then ""
    else s!"; theorems: {String.intercalate ", " cmp.theoremNames}"
  if cmp.status == "verified" then
    let when := if cmp.verifiedAt.isEmpty then "Independently verified" else s!"Verified at {cmp.verifiedAt}"
    trustBadgeHtml "comparator: verified" "success" (Option.some s!"{when}{theoremsTitle}")
      (Option.some Informal.NodeRoute.comparatorHref)
  else if cmp.status == "configured" then
    let title := if cmp.note.isEmpty then s!"Comparator configured{theoremsTitle}" else cmp.note
    trustBadgeHtml "comparator: configured — not yet run" "warn" (Option.some title)
      (Option.some Informal.NodeRoute.comparatorHref)
  else
    trustBadgeHtml s!"comparator: {cmp.status}" (href? := Option.some Informal.NodeRoute.comparatorHref)

/--
The rendered strip: a labelled badge row. Carries the comparator verdict badge and,
when the document emits a formalization-metadata page, a blue `accent` badge linking
to it. Empty when no comparator is configured (the "renders only with real trust
data" rule).
-/
def trustStripHtml (trust : TrustData) (detailsHref? : Option String := Option.none)
    (_checks? : Option Informal.GraphChecks.Results := Option.none) :
    Output.Html :=
  -- The strip carries only the comparator verdict (plus the formalization.yaml link
  -- below), a compact signal row rather than mirroring every metadata field.
  let badges : Array Output.Html := Id.run do
    let mut out : Array Output.Html := #[]
    if let some cmp := trust.comparator then
      out := out.push (trustComparatorBadge cmp)
    return out
  let allBadges := badges
  if allBadges.isEmpty then
    .empty
  else
    -- Append the formalization-metadata badge only when the strip already carries a
    -- trust signal, preserving the "strip renders only with real trust data" rule.
    let allBadges : Array Output.Html :=
      match detailsHref? with
      | Option.some href =>
        allBadges.push <|
          trustBadgeHtml "formalization.yaml" "accent"
            (title? := Option.some "Project formalization.yaml metadata")
            (href? := Option.some href)
      | Option.none => allBadges
    {{
      <section class="bp_trust_strip" "aria-label"="Trust signals">
        <span class="bp_trust_strip_label">"Trust"</span>
        <div class="bp_summary_badge_row">{{allBadges}}</div>
      </section>
    }}

-- Trust-strip stylesheet: the centred fit-content dashboard strip plus the claim-first
-- comparator page (verdict header, prose sections, reproduce list). See trust-strip.css.
def trustStripCss := include_str "trust-strip.css"

def trustStripAssetBundle : BlueprintAssetBundle :=
  blueprintCssAssetBundle [trustStripCss]

open Verso Doc Elab Genre Manual in
block_extension Block.trustStrip (trust : TrustData) where
  data := toJson trust
  traverse _id data _contents := do
    -- Stash the trust payload so the generation-time ExtraSteps (`emitBlueprintGraphGate`
    -- for `requireConnected`, `emitBlueprintComparatorPage` for the comparator verdict)
    -- can read it. `data` is the block's already `toJson`ed `TrustData`.
    modify fun st => Informal.TraversalIndex.TrustData.saveData st data
    return none
  toTeX := none
  toHtml :=
    open Verso.Doc.Html in
    open Verso.Output.Html in
    some <| fun _goI _goB _id data _blocks => do
      let some trust ← Informal.ExtensionDecode.decode? (α := TrustData) data
          (fun err => s!"Malformed data in Block.trustStrip.toHtml ({err})")
        | pure .empty
      let st ← HtmlT.state
      let checks := Informal.GraphChecks.run (Informal.GraphApi.masterGraph st)
      pure (trustStripHtml trust (Informal.TraversalIndex.FormalizationPage.href? st) (some checks))
  extraCss := trustStripAssetBundle.css
  extraJs := trustStripAssetBundle.js

open Verso Doc Elab in
/--
Read the artifacts named by the `verso.blueprint.trust.*` options into a
`TrustData` payload. `none` when both options are unset; a build error when a
set option names a missing or unparsable file. Reads happen at elaboration
time; relative paths resolve against the build CWD (the consumer package root).
-/
def elabTrustData? : PartElabM (Option TrustData) := do
  let opts ← Lean.getOptions
  let yamlPath : String :=
    opts.get verso.blueprint.trust.formalizationYaml.name
      verso.blueprint.trust.formalizationYaml.defValue
  let cmpPath : String :=
    opts.get verso.blueprint.trust.comparatorStatus.name
      verso.blueprint.trust.comparatorStatus.defValue
  if yamlPath.isEmpty && cmpPath.isEmpty then
    return Option.none
  let mut trust : TrustData := {}
  if !yamlPath.isEmpty then
    if !(← System.FilePath.pathExists yamlPath) then
      throwError "option 'verso.blueprint.trust.formalizationYaml' names a missing file (resolved against the build directory): {yamlPath}"
    match Informal.FormalizationYaml.parse (← IO.FS.readFile yamlPath) with
    | .error err => throwError "could not parse {yamlPath}: {err}"
    | .ok doc =>
      trust := TrustData.ofFormalizationJson doc
  if !cmpPath.isEmpty then
    if !(← System.FilePath.pathExists cmpPath) then
      throwError "option 'verso.blueprint.trust.comparatorStatus' names a missing file (resolved against the build directory): {cmpPath}"
    match Json.parse (← IO.FS.readFile cmpPath) with
    | .error err => throwError "could not parse {cmpPath}: {err}"
    | .ok j => trust := { trust with comparator := Option.some (TrustComparator.ofJson j) }
  -- Embed the comparator's config JSON + Challenge/Solution Lean source verbatim on the
  -- comparator page. Unlike the two required options above, these degrade silently
  -- when their file is empty/missing (probe-and-degrade) and only attach when a
  -- comparator verdict exists.
  if let some cmp := trust.comparator then
    let cfgPath : String :=
      opts.get verso.blueprint.trust.comparatorConfig.name
        verso.blueprint.trust.comparatorConfig.defValue
    let chalPath : String :=
      opts.get verso.blueprint.trust.challengeFile.name
        verso.blueprint.trust.challengeFile.defValue
    let solPath : String :=
      opts.get verso.blueprint.trust.solutionFile.name
        verso.blueprint.trust.solutionFile.defValue
    let mut cmp := cmp
    if !cfgPath.isEmpty then
      if (← System.FilePath.pathExists cfgPath) then
        let raw ← IO.FS.readFile cfgPath
        -- Pretty-print when it parses as JSON; fall back to the raw file text. The parsed
        -- config also carries `enable_nanoda`, driving the nanoda-aware repro lines and kernel
        -- prose (absent field / bad JSON / missing file ⇒ false, i.e. the unchanged page).
        match Json.parse raw with
        | .ok j =>
          cmp := { cmp with
            configJson := j.pretty
            enableNanoda := (j.getObjValAs? Bool "enable_nanoda").toOption.getD false }
        | .error _ =>
          cmp := { cmp with configJson := raw }
    if !chalPath.isEmpty then
      if (← System.FilePath.pathExists chalPath) then
        cmp := { cmp with challengeSource := (← IO.FS.readFile chalPath) }
    if !solPath.isEmpty then
      if (← System.FilePath.pathExists solPath) then
        cmp := { cmp with solutionSource := (← IO.FS.readFile solPath) }
    trust := { trust with comparator := Option.some cmp }
  -- Layer on the comparator-source enrichment (syntax highlighting + source links).
  -- Runs in `CoreM`; degrades to empty fields, never a build error.
  trust := (← liftM (enrichTrustData opts trust))
  let requireConnected : Bool :=
    opts.get verso.blueprint.trust.requireConnected.name
      verso.blueprint.trust.requireConnected.defValue
  let ciRunUrl : Option String :=
    let u := opts.get verso.blueprint.trust.ciRunUrl.name
      verso.blueprint.trust.ciRunUrl.defValue
    if u.isEmpty then none else some u
  trust := { trust with requireConnected, ciRunUrl }
  return Option.some trust

end Informal.Commands
