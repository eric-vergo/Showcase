/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import VersoManual
import VersoBlueprint.Commands.TrustStrip
import VersoBlueprint.Commands.Graph
import VersoBlueprint.Graph
import VersoBlueprint.NodeRoute

/-!
"What you must read to believe this claim" — the reader-facing half of the statement
closure.

The engine (`VersoBlueprint.StatementClosure`) answers a question about bytes; this module
turns that answer into a section of the comparator page. What it may say is decided by
where the closure came from and whether it finished, and those two axes are kept apart
because they fail differently:

- **Provenance** (§A1) is about *which file* was closed over. `chain` is the chain the
  recorded run verified, digest for digest. `chain-unbound` is the right file with nothing
  tying it to the verdict. `claim-decls` is a different thing entirely — the subject's own
  statements, aligned by the consumer — and says so in every sentence it appears in.
  `unavailable` is the notice that says why there is nothing.
- **Completeness** (§A3) is about whether the walk finished. A truncated closure reports a
  lower bound and nothing else: no exact count, no favourable gradient, no graph. The cap
  is named where the number is, because a number that means "at least" and a number that
  means "exactly" are not the same number.

The favourable half of the trust gradient is available only to a complete closure whose
provenance is `chain` or `claim-decls`. An unbound closure may be a closure of the current
tree rather than of the checked one, and "this is short, so it is easy to check" is exactly
the sentence that must not be said about a file nobody has bound to the verdict.
-/

namespace Informal.Commands.StatementClosurePanel

open Lean
open Verso Verso.Output Verso.Doc
open Verso.Genre Manual
open Verso.Output.Html

/--
Where the reading list's rows can send a reader, supplied by the page that renders the
panel.

The three origins resolve in three different places, and none of them may guess: a row
that links to the wrong declaration is worse than a row that links nowhere.
-/
structure Context where
  /-- Element id of the rendered Challenge source on this page. The chain's own
  declarations are printed there and nowhere else, so that is where their rows point.
  Empty ⇒ the source is not on this page and those rows render unlinked. -/
  claimAnchor : String := ""
  /-- Where this site publishes a declaration, by fully-qualified name — the registry's
  answer, resolved at generation time, never a slug guessed from the name. `none` ⇒ the
  site does not publish it. -/
  siteHref : String → Option String := fun _ => none
  /-- Suffix distinguishing this panel's element ids on a multi-topic page. -/
  idSuffix : String := ""

/-- Whether this claim's panel has rows that want the challenge source anchored. Gating
the anchor on that is what keeps a page without the closure surface byte-identical to what
it rendered before: an id nothing links to is still a change to the markup. -/
def needsClaimAnchor (cmp : TrustComparator) : Bool :=
  match cmp.closure? with
  | none => false
  | some c => c.entries.any (·.origin == "challenge")

/-! ## Rendering constants -/

/--
Where the trust gradient stops calling a statement's dependency set short.

Fifteen declarations outside Mathlib and core is about what a reader can hold in one
sitting: a short file's worth of definitions, readable end to end before the attention
that brought them to the page runs out. Beyond it the honest thing to say is that reading
the statement is real work, which is the whole point of Brasca's observation — the
distance between "I checked this claim" and "I checked this claim's meaning" grows with
the closure, and a site that reports the closure should say when it has grown.

A constant rather than an option: the sentence it selects is this fork's editorial voice,
and a consumer tuning the threshold would be tuning how favourably its own claims read.
-/
def gradientShortMax : Nat := 15

/--
Largest closure the meaning graph is drawn for.

Past this the picture stops being one: a hundred-and-twenty-node dependency mesh at a
readable font size is already a wall, and the reading list carries the same information
in a form that survives the scale. Suppressed rather than shrunk, and the suppression is
stated with the number that caused it.
-/
def graphMaxNodes : Nat := 120

/-! ## Copy -/

/-- Render a list of phrases as prose ("a, b and c"). -/
private def andList : List String → String
  | [] => ""
  | [a] => a
  | [a, b] => s!"{a} and {b}"
  | a :: rest => s!"{a}, {andList rest}"

private def plural (n : Nat) (one many : String) : String := if n == 1 then one else many

/-- Origins with a fixed meaning; anything else is a module root the closure reached and
names under its own name. -/
private def knownOrigins : Array String := #["challenge", "subject", "mathlib", "core"]

private def countFor (c : StatementClosure) (origin : String) : Nat :=
  ((c.counts.find? (fun p => p.1 == origin)).map (·.2)).getD 0

/-- Module roots the closure reached that this fork has no name for, in the order they
were first seen. Surfacing these under their own names is the point: a dependency nobody
expected is exactly what a reader wants to be told about. -/
private def otherOrigins (c : StatementClosure) : Array (String × Nat) :=
  c.counts.filter (fun p => !knownOrigins.contains p.1)

/-- Group heading for one origin. -/
private def originTitle (origin : String) : String :=
  if origin == "challenge" then "Declared in the challenge chain"
  else if origin == "subject" then "From the subject project"
  else if origin == "mathlib" then "From Mathlib, used as given"
  else if origin == "core" then "From Lean's core libraries, used as given"
  else s!"From {origin}"

/-- Reading order for the groups: what a reader has to work through first, then the
libraries they were invited to accept. -/
private def originRank (origin : String) : Nat :=
  if origin == "challenge" then 0
  else if origin == "subject" then 1
  else if origin == "mathlib" then 3
  else if origin == "core" then 4
  else 2

/-- The clause naming each origin's share of the closure, in reading order. Mathlib and
core are combined when both are present: a reader accepting one accepts the other, and
splitting them adds a number without adding a decision. -/
private def breakdownPhrases (c : StatementClosure) : List String :=
  let k := countFor c "challenge"
  let j := countFor c "subject"
  let fm := countFor c "mathlib"
  let fc := countFor c "core"
  let challenge := if k == 0 then [] else [s!"{k} declared in the challenge chain itself"]
  let subject := if j == 0 then [] else [s!"{j} from the subject project"]
  let others := (otherOrigins c).toList.map fun (root, n) => s!"{n} from {root}"
  let libs :=
    if fm > 0 && fc > 0 then
      [s!"{fm + fc} from Mathlib and Lean's core libraries, used as given"]
    else if fm > 0 then [s!"{fm} from Mathlib, used as given"]
    else if fc > 0 then [s!"{fc} from Lean's core libraries, used as given"]
    else []
  challenge ++ subject ++ others ++ libs

/-- The parenthetical that puts the count a reader cares about beside the total. Omitted
when the closure touches no Mathlib at all, where it would restate the total. -/
private def outsideMathlibClause (c : StatementClosure) : String :=
  if countFor c "mathlib" == 0 || c.outsideMathlib == 0 then ""
  else s!" ({c.outsideMathlib} outside Mathlib)"

/--
The headline, in the one shape the closure's state permits.

Truncated is §A3's sentence verbatim and nothing else: "at least" is a different claim
from a count, and the two must not be spelled alike. `claim-decls` gets a lead that names
what was closed over, because "to believe this claim you must read" would be a claim about
the challenge file, which is not what was walked.
-/
private def headline (c : StatementClosure) : String :=
  if c.truncated then
    s!"At least {c.total} declarations were discovered before this site's configured cap \
       ({c.maxNodes}); the reading list is incomplete."
  else
    let n := c.total
    let noun := plural n "declaration" "declarations"
    let breakdown :=
      match breakdownPhrases c with
      | [] => ""
      | parts => s!": {andList parts}"
    if c.provenance == "claim-decls" then
      s!"Reading the subject's aligned statements means reading {n} {noun}\
         {outsideMathlibClause c}{breakdown}."
    else
      s!"To believe this claim you must read {n} {noun}{outsideMathlibClause c}{breakdown}."

/-- The sentence that keeps a truncated reading list usable without letting it read as a
count. -/
private def truncationNote : String :=
  "The walk stops at the cap, and it stops breadth-first, so what follows is the shallowest \
   part of the closure — the part a reader would start with — and not the whole of it. The \
   count above is a lower bound on what the statement depends on, and no gradient or graph \
   is drawn from it."

/--
The trust gradient (Brasca): one sentence about how much of trusting this result is
reading its statement.

Derived only from a complete closure's `untrusted` count — the declarations a reader
cannot skip by accepting Mathlib and core — because that is the number that measures the
work. Suppressed entirely for a truncated closure (the number is a lower bound) and for an
unbound one (the favourable reading would be about a file nothing ties to the verdict).
-/
private def gradient? (c : StatementClosure) : Option String :=
  if c.truncated then none
  else if c.provenance != "chain" && c.provenance != "claim-decls" then none
  else if c.untrusted == 0 then none
  else if c.untrusted ≤ gradientShortMax then
    some s!"The statement check here is short: outside Mathlib and Lean's core libraries, \
      this claim's meaning rests on {c.untrusted} {plural c.untrusted "declaration" "declarations"}."
  else
    some "Reading this statement's dependencies is a substantial part of trusting this result."

/-! ## The provenance line -/

/-- The badge and the paragraph under it: which file was closed over, and how firmly that
is tied to the verdict above. -/
private def provenanceBlock (c : StatementClosure) : Output.Html :=
  let (badge, lead) : Output.Html × String :=
    if c.provenance == "chain" then
      (trustBadgeHtml "Bound to the recorded run" "success"
        (Option.some "Every file the closure was computed from matches, in order, the digests the verifying run recorded."),
       "Computed from the challenge chain the recorded run verified, elaborated in a fresh \
        environment holding exactly that chain's declared imports — not this site's \
        environment, where the subject library is in scope and a short name could resolve to \
        something the verifier never saw. The bytes read here match, in order, the digests \
        that run recorded.")
    else if c.provenance == "chain-unbound" then
      (trustBadgeHtml "Not bound to the recorded run" "warn"
        (Option.some "The closure was computed from this build's files; nothing ties them to the verdict above."),
       "Source exploration of the current tree — not bound to the recorded verifier run. The \
        closure below was computed from the challenge chain as it stands in this build, in a \
        fresh environment holding exactly that chain's declared imports, but the files read \
        are not the files the verdict above was produced from.")
    else if c.provenance == "claim-decls" then
      (trustBadgeHtml "Subject's aligned statements" "warn"
        (Option.some "Not the challenge file: the subject-side declarations the project's manifest aligned with the certified statements."),
       "Closure of the subject's aligned statements, not of the challenge file. The project's \
        topic manifest names subject declarations it takes to correspond to the certified \
        statements, and this build walked those instead. Whether they say the same thing as \
        the challenge is the manifest author's assertion, checked by nobody: read this as an \
        indication of the shape of the claim's meaning, not as a closure of what was \
        certified.")
    else
      (trustBadgeHtml "Not computed" ""
        (Option.some "The closure surface is configured, and this is why it has nothing to show."),
       "No statement closure is available for this claim.")
  let truncationBadge : Output.Html :=
    if !c.truncated then .empty
    else trustBadgeHtml s!"Incomplete — cap {c.maxNodes}" "warn"
      (Option.some "The walk reached the configured cap; the reading list is a lower bound.")
  let rootsRow : Output.Html :=
    if c.roots.isEmpty then .empty
    else
      let label := if c.provenance == "claim-decls" then "Closed over" else "Certified statement(s)"
      {{ <p class="bp_trust_note">{{.text true (label ++ ": ")}}
           {{.text true (String.intercalate ", " c.roots)}}</p> }}
  -- The engine's reasons are written as clauses ("the run record carries no chain, so …"),
  -- which is what they are where they are composed. Standing alone as a paragraph they get
  -- a capital.
  let reasonRow : Output.Html :=
    if c.reason.isEmpty then .empty
    else
      let text := match c.reason.data with
        | first :: rest => String.mk (first.toUpper :: rest)
        | [] => c.reason
      {{ <p class="bp_trust_note">{{.text true text}}</p> }}
  let chainRow : Output.Html :=
    if c.chainFiles.isEmpty then .empty
    else
      let files := String.intercalate ", " (c.chainFiles.map (·.1)).toList
      {{ <p class="bp_trust_note">{{.text true s!"Chain read, in elaboration order: {files}."}}</p> }}
  .seq #[
    {{ <p class="bp_trust_verdict_row">{{badge}}{{truncationBadge}}</p> }},
    {{ <p class="bp_trust_prose">{{.text true lead}}</p> }},
    rootsRow, chainRow, reasonRow]

/-! ## The reading list -/

private def isKnownOrigin (origin : String) : Bool := knownOrigins.contains origin

/-- Every origin present in the closure, in reading order; unrecognized roots sort among
themselves by name so the page is stable across builds. -/
private def orderedOrigins (c : StatementClosure) : Array String :=
  let seen := c.entries.foldl (init := (#[] : Array String)) fun acc e =>
    if acc.contains e.origin then acc else acc.push e.origin
  seen.qsort fun a b =>
    if originRank a != originRank b then originRank a < originRank b
    else if isKnownOrigin a then false
    else a < b

/--
Where a reader can go and read one entry, or nothing.

Three origins, resolved in the order they are reliable: the challenge's own declarations
are printed on this page, the subject's are published where the registry says and nowhere
else, and everything left over gets the outbound link the build resolved into its package
checkout. No branch guesses a URL.
-/
private def entryHref? (ctx : Context) (e : StatementClosureEntry) : Option String :=
  if e.origin == "challenge" then
    if ctx.claimAnchor.isEmpty then none
    else some (Informal.NodeRoute.comparatorHref ++ "#" ++ ctx.claimAnchor)
  else
    match ctx.siteHref e.name with
    | some href => some href
    | none => if e.href.isEmpty then none else some e.href

/--
One row: what kind of thing it is, its name (linked where a reader can go and read it),
and its type.

The name is fully qualified. Everywhere else on this site short names are the display
form, but a closure is a claim about *which* declarations a statement depends on, and a
short name is exactly the part of that claim that can be ambiguous — two entries whose
last components agree are two different things a reader must not conflate.
-/
private def entryRow (ctx : Context) (e : StatementClosureEntry) : Output.Html :=
  let name : Output.Html := {{ <code class="bp_closure_name">{{.text true e.name}}</code> }}
  let linked : Output.Html :=
    match entryHref? ctx e with
    | none => name
    | some href =>
      if e.origin == "challenge" then
        {{ <a class="bp_closure_link" href={{href}}
              title="Read it in the challenge source on this page">{{name}}</a> }}
      else if (ctx.siteHref e.name).isSome then
        {{ <a class="bp_closure_link" href={{href}}>{{name}}</a> }}
      else
        {{ <a class="bp_closure_link" href={{href}} target="_blank" rel="noopener"
              title="Read it at the revision this build resolved">{{name}}</a> }}
  let signature : Output.Html :=
    if e.signature.isEmpty then .empty
    else {{ <code class="bp_closure_sig">{{.text true e.signature}}</code> }}
  {{
    <li class="bp_closure_row">
      <span class="bp_closure_kind">{{.text true e.kind}}</span>
      {{linked}}
      {{signature}}
    </li>
  }}

/-- Depth-descending, discovery order within a depth: the shallowest rows — the claim
itself and what it names directly — come last, so the list reads bottom-up from the
primitives to the statement. -/
private def readingOrder (entries : Array StatementClosureEntry) :
    Array StatementClosureEntry :=
  let decorated := entries.zipIdx
  let sorted := decorated.qsort fun a b =>
    if a.1.depth != b.1.depth then a.1.depth > b.1.depth else a.2 < b.2
  sorted.map (·.1)

/-- One origin's rows, with the machinery folded into a subgroup of its own.

Auxiliaries are counted in the total and listed here rather than dropped: the walk reached
them through real dependency edges (a definition by pattern match genuinely uses its
matcher), and a list that silently omitted them would be reporting a smaller closure than
the count above it. Folding them away is a rendering decision, made where the reader can
be told it happened. -/
private def originGroup (ctx : Context) (origin : String)
    (entries : Array StatementClosureEntry) : Output.Html :=
  let ordered := readingOrder entries
  let main := ordered.filter (fun e => !e.auxiliary)
  let aux := ordered.filter (·.auxiliary)
  let mainList : Output.Html :=
    if main.isEmpty then .empty
    else {{ <ul class="bp_closure_list">{{.seq (main.map (entryRow ctx))}}</ul> }}
  let auxList : Output.Html :=
    if aux.isEmpty then .empty
    else
      {{
        <details class="bp_closure_aux">
          <summary>{{.text true s!"compiler-generated auxiliaries ({aux.size})"}}</summary>
          <ul class="bp_closure_list">{{.seq (aux.map (entryRow ctx))}}</ul>
        </details> }}
  {{
    <div class="bp_closure_group">
      <h3 class="bp_closure_group_title">
        {{.text true (originTitle origin)}}
        <span class="bp_closure_group_count">{{.text true s!"{entries.size}"}}</span>
      </h3>
      {{mainList}}
      {{auxList}}
    </div>
  }}

private def readingList (ctx : Context) (c : StatementClosure) : Output.Html :=
  if c.entries.isEmpty then .empty
  else
    let groups : Array Output.Html := (orderedOrigins c).map fun origin =>
      originGroup ctx origin (c.entries.filter (fun e => e.origin == origin))
    let summaryText :=
      if c.truncated then s!"Reading list ({c.entries.size} of at least {c.total})"
      else s!"Reading list ({c.entries.size})"
    {{
      <details class="bp_trust_disclosure bp_closure_disclosure">
        <summary>{{.text true summaryText}}</summary>
        <div class="bp_closure_groups">{{.seq groups}}</div>
      </details>
    }}

/-! ## The meaning graph (F1b) -/

/-- Closure kind → the graph's two shapes. Everything that is not a proposition is drawn
as a definition, which is what the shape distinction means here: a thing to read versus a
thing that is asserted. -/
private def graphKind (kind : String) : Informal.Data.NodeKind :=
  if kind == "theorem" || kind == "axiom" then .theorem else .definition

/--
The closure as a picture: nodes are the reading list's rows, edges are "the meaning of
this one refers to that one".

Origin drives the two existing node registers — the muted supporting fill for the trusted
frontier a reader was invited to accept, the plain raised fill for everything they cannot
skip — and the roots carry a second outline. No new colours: the graph canvas is
deliberately theme-invariant (see `graph.css`), so every fill here is one already tuned
for it.
-/
private def closureGraph (ctx : Context) (c : StatementClosure) (roots : Array String) :
    Informal.Graph.GraphData :=
  let present : Array String := c.entries.map (·.name)
  let refs := fun (names : Array String) =>
    names.foldl (init := (#[] : Array Informal.Data.UseRef)) fun acc d =>
      if present.contains d then
        acc.push { label := (d.toName : Informal.Data.Label), origin := .automatic }
      else acc
  let nodes := c.entries.map fun e =>
    let node := Informal.Graph.mkSupportingNodeData (graphKind e.kind) e.name.toName
      (refs e.uses) #[]
    let trusted := e.origin == "mathlib" || e.origin == "core"
    let visual :=
      if trusted then node.visual
      else { node.visual with
              fillcolor := Informal.Graph.definitionBackgroundColor
              color := Informal.Graph.supportingFontColor
              peripheries := if roots.contains e.name then 2 else 1 }
    { node with
        visual
        href := entryHref? ctx e
        title := e.name }
  let data : Informal.Graph.GraphData := { key := "statement-closure", nodes }
  { data with edges := Informal.Graph.edgesForGraph data.toGraph }

/-- The graph section, or the sentence saying why there is none. Drawn only for a complete
closure (§A3) of at most `graphMaxNodes` rows. -/
private def graphSection (ctx : Context) (c : StatementClosure) : Output.Html :=
  if c.truncated || c.entries.size ≤ 1 then .empty
  else if c.entries.size > graphMaxNodes then
    {{ <p class="bp_trust_note">{{.text true
         s!"No meaning graph is drawn: this closure has {c.entries.size} declarations and the \
            graph is drawn only up to {graphMaxNodes}, past which it stops being readable. \
            The reading list above carries the same declarations."}}</p> }}
  else
    let data := closureGraph ctx c c.roots.toArray
    let variant : Informal.Graph.GraphRenderVariant := {
      key := "meaning"
      label := "Meaning closure"
      dot := data.toDotWith
    }
    let idBase :=
      if ctx.idSuffix.isEmpty then "bp-closure-graph" else s!"bp-closure-graph-{ctx.idSuffix}"
    {{
      <figure class="bp_closure_graph">
        {{Informal.Commands.renderGraphFullwidth data #[variant] {} idBase
            (static := true) (zoomControls := true)}}
        <figcaption class="bp_trust_note">
          "Meaning graph — what the statement refers to, not how it is proved."
        </figcaption>
      </figure>
    }}

/-! ## The section -/

/--
"What you must read to believe this claim", for one certified claim.

`.empty` when no closure was computed — which is not the same as an unavailable one: a
consumer that never turned the option on renders exactly what it rendered before, and one
that did gets the notice saying why there is nothing.
-/
def render (cmp : TrustComparator) (ctx : Context := {}) : Output.Html :=
  match cmp.closure? with
  | none => .empty
  | some c =>
    if c.provenance.isEmpty then .empty
    else
      let body : Output.Html :=
        if c.provenance == "unavailable" then .empty
        else
          let gradientHtml : Output.Html :=
            match gradient? c with
            | some g => {{ <p class="bp_trust_prose bp_closure_gradient">{{.text true g}}</p> }}
            | none => .empty
          let truncationHtml : Output.Html :=
            if !c.truncated then .empty
            else {{ <p class="bp_trust_note">{{.text true truncationNote}}</p> }}
          .seq #[
            {{ <p class="bp_trust_prose bp_closure_headline">{{.text true (headline c)}}</p> }},
            truncationHtml,
            gradientHtml,
            readingList ctx c,
            graphSection ctx c]
      trustSection "What you must read to believe this claim"
        (.seq #[provenanceBlock c, body])

end Informal.Commands.StatementClosurePanel
