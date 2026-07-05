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

/-!
Dashboard trust strip.

A compact badge row surfaced with `blueprint_dashboard`: sorry count, axiom
hygiene, review status, and the statement-comparator verdict. It is fed by two
build options naming machine-readable artifacts, both read at elaboration time
(paths resolve against the build CWD, i.e. the consumer package root):

- `verso.blueprint.trust.formalizationYaml` — the project's
  `formalization.yaml` (v0.3); supplies the sorry/axioms/review badges.
- `verso.blueprint.trust.comparatorStatus` — a comparator-status JSON artifact
  (`{status, theorem_names, verified_at, note, ...}`); supplies the comparator
  badge.

Degrades gracefully: an unset option silently omits its badges; a *set* option
naming a missing or unparsable file is a build error (a configured trust signal
must not vanish silently). When the document also renders a
`blueprint_formalization` page, the strip links to it (resolved through the
`FormalizationPage` traversal store, never a guessed slug).
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
  configJson : String := ""
  challengeSource : String := ""
  /-- Syntactically-highlighted HTML for `configJson` / `challengeSource` (built at
  elaboration by `enrichTrustData`; empty ⇒ the evidence page falls back to escaped
  plain text). `challengeHtml` is the inner markup of a `<code class="hl lean">`. -/
  configHtml : String := ""
  challengeHtml : String := ""
  /-- Outbound links for the Challenge source (probe-and-degrade to empty when git
  info is unavailable): a GitHub blob URL at the pinned commit for the Challenge file
  and for the comparator config JSON, and a Lean-playground URL that opens the
  Challenge file against the playground's *current* Mathlib. -/
  githubChallengeUrl : String := ""
  githubConfigUrl : String := ""
  playgroundUrl : String := ""
deriving Inhabited, FromJson, ToJson, Quote

/-- Kernel-derived axiom evidence for one named theorem (Phase 1B): the transitive
axiom set the kernel records for `declaration` (via `Lean.collectAxioms`, computed at
elaboration) versus the axiom set the project declared for it in `formalization.yaml`.
`computed := false` when the declaration was not resolvable in the build environment
(import-dependent) — the page then presents the declared list marked as *not*
independently computed, never as verified. -/
structure AxiomEvidence where
  declaration : String := ""
  computed : Bool := false
  kernelAxioms : List String := []
  declaredAxioms : List String := []
deriving Inhabited, FromJson, ToJson, Quote

/-- Trust-strip payload: only fields present in the configured artifacts are set.
The `axiomEvidence` / `sorryScanRan` / `sorryDecls` fields carry the Phase-1B
kernel-derived enrichment (all defaulted, so serialized payloads stay
back-compatible with pre-1B artifacts). -/
structure TrustData where
  sorryCount : Option Nat := none
  axioms : List String := []
  reviewStatus : String := ""
  comparator : Option TrustComparator := none
  /-- Per-main-result kernel-derived axiom evidence (empty when `formalization.yaml`
  lists no `status.main_results`). -/
  axiomEvidence : List AxiomEvidence := []
  /-- Whether a kernel sorry scan actually ran (a project namespace was configured via
  `verso.blueprint.declNamePrefix`). `false` ⇒ the sorries page reports the YAML count
  as *declared*, not independently computed. -/
  sorryScanRan : Bool := false
  /-- Declarations in the project namespace whose type/value uses `sorryAx`, found by
  the kernel scan (empty for a sorry-free development). -/
  sorryDecls : List String := []
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

/-- The `(declaration, declared-axioms)` pairs from `status.main_results[]`, used to
drive the per-theorem kernel axiom breakdown. A result's declared axiom set is its own
`axioms` when present, else the top-level `status.axioms` (a project that declares a
single shared axiom set need not repeat it per result). Empty when the document lists
no main results. -/
def mainResultsDeclared (doc : Json) : List (String × List String) :=
  let status := (doc.getObjVal? "status").toOption.getD Json.null
  let topAxioms := (status.getObjValAs? (List String) "axioms").toOption.getD []
  let results := (status.getObjValAs? (Array Json) "main_results").toOption.getD #[]
  results.toList.filterMap fun r =>
    (r.getObjValAs? String "declaration").toOption.map fun decl =>
      (decl, (r.getObjValAs? (List String) "axioms").toOption.getD topAxioms)

/-- Extract the comparator verdict from a comparator-status artifact (`verified_at` may be `null`).
`run_url` is optional (absent in older artifacts ⇒ empty). The embedded config /
Challenge sources are filled in later from their own options (`elabTrustData?`). -/
def TrustComparator.ofJson (j : Json) : TrustComparator :=
  {
    status := (j.getObjValAs? String "status").toOption.getD ""
    verifiedAt := (j.getObjValAs? String "verified_at").toOption.getD ""
    theoremNames := (j.getObjValAs? (List String) "theorem_names").toOption.getD []
    note := (j.getObjValAs? String "note").toOption.getD ""
    runUrl := (j.getObjValAs? String "run_url").toOption.getD ""
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
## Kernel-derived enrichment

At elaboration time the full environment (project + Mathlib) is available, so we can
compute *independent* trust evidence rather than merely transcribing
`formalization.yaml`: the kernel's transitive axiom set per named theorem
(`Lean.collectAxioms`) and a scan for declarations that use `sorryAx`. Everything here
probes-and-degrades — an unresolvable declaration or missing git remote yields empty
fields, never a build error.
-/

/-- The kernel's transitive axiom evidence for one named theorem: resolve it in the
environment and, when present, collect the axioms it actually depends on. -/
def axiomEvidenceFor (declStr : String) (declared : List String) :
    Lean.CoreM AxiomEvidence := do
  let name := declStr.toName
  match (← getEnv).find? name with
  | some _ =>
    let kernel := (← Lean.collectAxioms name).toList.map toString
    return {
      declaration := declStr
      computed := true
      kernelAxioms := kernel
      declaredAxioms := declared
    }
  | _ => return { declaration := declStr, computed := false, declaredAxioms := declared }

/-- Scan the project namespace (`namePrefix`, e.g. `A362583`) for declarations whose
type or value uses `sorryAx`, returning their user-facing names. Bounded to the
project by a cheap name-prefix filter (the expensive `Expr.hasSorry` traversal only
runs on matches), and skips compiler-internal names. Empty when no prefix is
configured or the development is sorry-free (the showcase's case). -/
def collectProjectSorries (namePrefix : String) : Lean.CoreM (Array String) := do
  if namePrefix.isEmpty then return #[]
  let root := namePrefix.toName
  let env ← getEnv
  let found := env.constants.fold (init := #[]) fun acc name cinfo =>
    -- `allowOpaque := true`: a `sorry` proof is stored as an opaque body, so the default
    -- `value?` (which hides opaque bodies) would miss it — matching `ProvedStatus`.
    if (root == name || root.isPrefixOf name) && !name.isInternalDetail &&
        (cinfo.type.hasSorry || ((cinfo.value? (allowOpaque := true)).map (·.hasSorry)).getD false) then
      acc.push name.toString
    else acc
  return found

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

/-- Absolute path of an option-configured path (relative to the build CWD). -/
private def absOptionPath (workspaceRoot : System.FilePath) (p : String) : System.FilePath :=
  let fp := System.FilePath.mk p
  if fp.isAbsolute then fp else workspaceRoot / p

open Informal in
/-- Fill in the Phase-1B kernel-derived enrichment: per-main-result axiom evidence, the
project sorry scan, syntax-highlighted config/Challenge blocks, and the Challenge
source links (GitHub blob at the pinned commit + Lean-playground). Runs in `CoreM`
(environment + git available at elaboration); every enrichment degrades to empty
rather than failing. -/
def enrichTrustData (opts : Lean.Options) (namePrefix : String)
    (mainResults : List (String × List String)) (trust : TrustData) : Lean.CoreM TrustData := do
  let workspaceRoot ← Informal.workspaceRoot
  -- Per-main-result kernel axiom evidence.
  let axiomEvidence ← mainResults.mapM (fun (d, ax) => axiomEvidenceFor d ax)
  -- Kernel sorry scan over the project namespace.
  let sorries ← collectProjectSorries namePrefix
  let mut trust := { trust with
    axiomEvidence
    sorryScanRan := !namePrefix.isEmpty
    sorryDecls := sorries.toList }
  -- Comparator: highlight the config/Challenge blocks and resolve the source links.
  if let some cmp := trust.comparator then
    let mut cmp := cmp
    if !cmp.configJson.isEmpty then
      cmp := { cmp with configHtml := (highlightJsonHtml cmp.configJson).asString }
    if !cmp.challengeSource.isEmpty then
      if let some html ← Informal.highlightModuleSourceHtml? cmp.challengeSource then
        cmp := { cmp with challengeHtml := html }
    -- Blob URLs at the pinned commit, via the shared source-link builder (auto GitHub
    -- when the file is in a checkout with a GitHub `origin`; degrades to none).
    let chalPath := opts.get verso.blueprint.trust.challengeFile.name
      verso.blueprint.trust.challengeFile.defValue
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
    if !cfgPath.isEmpty then
      if let some blob ← liftM <| sourceLinkHref? opts workspaceRoot none
          (some (absOptionPath workspaceRoot cfgPath)) none then
        cmp := { cmp with githubConfigUrl := blob }
    trust := { trust with comparator := some cmp }
  return trust

/-!
Evidence-page routes. Each configured badge links to a generated evidence page
under `trust/`; these root-relative hrefs (no leading slash) resolve against each
page's `<base href>`, matching the worklist/audit route convention. The paired
`Verso.Multi.Path`s are the multi-page output locations `TrustPages` writes to.
-/

def trustSorriesHref : String := "trust/sorries/"
def trustSorriesPath : Verso.Multi.Path := #["trust", "sorries"]
def trustAxiomsHref : String := "trust/axioms/"
def trustAxiomsPath : Verso.Multi.Path := #["trust", "axioms"]
def trustReviewHref : String := "trust/review/"
def trustReviewPath : Verso.Multi.Path := #["trust", "review"]
def trustComparatorHref : String := "trust/comparator/"
def trustComparatorPath : Verso.Multi.Path := #["trust", "comparator"]

/--
One trust badge. Reuses the dashboard's `.bp_summary_badge` classes (`variant`
is one of `""`/`success`/`warn`/`error`/`accent`); `title?` becomes a tooltip.
When `href?` is set the badge renders as an `<a>` linking to its evidence page;
otherwise it is a plain `<span>`.
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

def trustSorryBadge (n : Nat) : Output.Html :=
  trustBadgeHtml
    s!"{n} {if n == 1 then "sorry" else "sorries"}"
    (if n == 0 then "success" else "error")
    (href? := Option.some trustSorriesHref)

def trustAxiomsBadge (axioms : List String) : Output.Html :=
  if axioms.isEmpty then
    trustBadgeHtml "axioms: none recorded" (href? := Option.some trustAxiomsHref)
  else
    let nonstandard := axioms.filter (fun a => !standardAxioms.contains a)
    let title := s!"Axioms: {String.intercalate ", " axioms}"
    if nonstandard.isEmpty then
      trustBadgeHtml s!"axioms: standard {axioms.length}" "success" (Option.some title)
        (Option.some trustAxiomsHref)
    else
      trustBadgeHtml s!"axioms: {axioms.length} ({nonstandard.length} nonstandard)" "warn"
        (Option.some title) (Option.some trustAxiomsHref)

def trustReviewBadge (status : String) : Output.Html :=
  trustBadgeHtml s!"review: {status}" (href? := Option.some trustReviewHref)

def trustComparatorBadge (cmp : TrustComparator) : Output.Html :=
  let theoremsTitle :=
    if cmp.theoremNames.isEmpty then ""
    else s!"; theorems: {String.intercalate ", " cmp.theoremNames}"
  if cmp.status == "verified" then
    let when := if cmp.verifiedAt.isEmpty then "Independently verified" else s!"Verified at {cmp.verifiedAt}"
    trustBadgeHtml "comparator: verified" "success" (Option.some s!"{when}{theoremsTitle}")
      (Option.some trustComparatorHref)
  else if cmp.status == "configured" then
    let title := if cmp.note.isEmpty then s!"Comparator configured{theoremsTitle}" else cmp.note
    trustBadgeHtml "comparator: configured — not yet run" "warn" (Option.some title)
      (Option.some trustComparatorHref)
  else
    trustBadgeHtml s!"comparator: {cmp.status}" (href? := Option.some trustComparatorHref)

/--
The rendered strip: a labelled badge row. When the document emits a
formalization-metadata page, a blue `accent` badge linking to it is appended to
the row (it replaces the former trailing text link). Empty when no badge has data.
-/
def trustStripHtml (trust : TrustData) (detailsHref? : Option String := Option.none) :
    Output.Html :=
  let badges : Array Output.Html := Id.run do
    let mut out : Array Output.Html := #[]
    if let some n := trust.sorryCount then
      out := out.push (trustSorryBadge n)
    if !trust.axioms.isEmpty then
      out := out.push (trustAxiomsBadge trust.axioms)
    if !trust.reviewStatus.isEmpty then
      out := out.push (trustReviewBadge trust.reviewStatus)
    if let some cmp := trust.comparator then
      out := out.push (trustComparatorBadge cmp)
    return out
  if badges.isEmpty then
    .empty
  else
    -- Append the formalization-metadata badge only when the strip already carries a
    -- trust signal, preserving the "strip renders only with real trust data" rule.
    let badges : Array Output.Html :=
      match detailsHref? with
      | Option.some href =>
        badges.push <|
          trustBadgeHtml "formalization.yaml" "accent"
            (title? := Option.some "Project formalization.yaml metadata")
            (href? := Option.some href)
      | Option.none => badges
    {{
      <section class="bp_trust_strip" "aria-label"="Trust signals">
        <span class="bp_trust_strip_label">"Trust"</span>
        <div class="bp_summary_badge_row">{{badges}}</div>
      </section>
    }}

def trustStripCss := include_str "trust-strip.css"

def trustStripAssetBundle : BlueprintAssetBundle :=
  blueprintCssAssetBundle [trustStripCss]

open Verso Doc Elab Genre Manual in
block_extension Block.trustStrip (trust : TrustData) where
  data := toJson trust
  traverse _id data _contents := do
    -- Stash the trust payload so the generation-time `TrustPages` ExtraStep can
    -- emit one evidence page per configured badge. `data` is the block's already
    -- `toJson`ed `TrustData`.
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
      pure (trustStripHtml trust (Informal.TraversalIndex.FormalizationPage.href? st))
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
  let mut mainResults : List (String × List String) := []
  if !yamlPath.isEmpty then
    if !(← System.FilePath.pathExists yamlPath) then
      throwError "option 'verso.blueprint.trust.formalizationYaml' names a missing file (resolved against the build directory): {yamlPath}"
    match Informal.FormalizationYaml.parse (← IO.FS.readFile yamlPath) with
    | .error err => throwError "could not parse {yamlPath}: {err}"
    | .ok doc =>
      trust := TrustData.ofFormalizationJson doc
      mainResults := mainResultsDeclared doc
  if !cmpPath.isEmpty then
    if !(← System.FilePath.pathExists cmpPath) then
      throwError "option 'verso.blueprint.trust.comparatorStatus' names a missing file (resolved against the build directory): {cmpPath}"
    match Json.parse (← IO.FS.readFile cmpPath) with
    | .error err => throwError "could not parse {cmpPath}: {err}"
    | .ok j => trust := { trust with comparator := Option.some (TrustComparator.ofJson j) }
  -- Embed the comparator's config JSON + Challenge Lean source verbatim on the
  -- evidence page. Unlike the two required options above, these degrade silently
  -- when their file is empty/missing (probe-and-degrade) and only attach when a
  -- comparator verdict exists.
  if let some cmp := trust.comparator then
    let cfgPath : String :=
      opts.get verso.blueprint.trust.comparatorConfig.name
        verso.blueprint.trust.comparatorConfig.defValue
    let chalPath : String :=
      opts.get verso.blueprint.trust.challengeFile.name
        verso.blueprint.trust.challengeFile.defValue
    let mut cmp := cmp
    if !cfgPath.isEmpty then
      if (← System.FilePath.pathExists cfgPath) then
        let raw ← IO.FS.readFile cfgPath
        -- Pretty-print when it parses as JSON; fall back to the raw file text.
        let pretty := match Json.parse raw with
          | .ok j => j.pretty
          | .error _ => raw
        cmp := { cmp with configJson := pretty }
    if !chalPath.isEmpty then
      if (← System.FilePath.pathExists chalPath) then
        cmp := { cmp with challengeSource := (← IO.FS.readFile chalPath) }
    trust := { trust with comparator := Option.some cmp }
  -- Phase 1B: layer on the kernel-derived enrichment (axiom evidence, sorry scan,
  -- syntax highlighting, Challenge source links). Runs in `CoreM`; degrades to empty
  -- fields, never a build error.
  let namePrefix : String := opts.get `verso.blueprint.declNamePrefix ""
  trust := (← liftM (enrichTrustData opts namePrefix mainResults trust))
  return Option.some trust

end Informal.Commands
