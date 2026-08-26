/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5 (Claude Code)
-/

import VersoBlueprint
import VersoBlueprintTests.Blueprint.Support
import VersoManual

/-!
The closure surface through the real option path.

`StatementClosureRender` asserts the rendering rules against constructed payloads, which
is where they belong; this module turns the option on the way a consumer does and checks
that the whole path works — options read at elaboration, the subprocess run and its
document parsed, the chain bound against the recorded run, the payload quoted into the
document and decoded again at generation time, and the trust-model page describing what
it found.

The fixture is the a362583 shape reduced to its essentials: a challenge file, a status
artifact recording that file's digest as an ordered `challenge_chain`, and a certified
theorem to close over. What must come back is a *bound* closure, because a bound closure
is the only rung whose copy this page is allowed to write.
-/

namespace Verso.VersoBlueprintTests.StatementClosureWiring

open Lean
open Verso Genre Manual
open Informal Informal.Commands
open Verso.VersoBlueprintTests.Blueprint.Support

set_option verso.blueprint.trust.comparatorStatus "tests/fixtures/trust/comparator-status.json"
set_option verso.blueprint.trust.comparatorConfig "tests/fixtures/trust/comparator.json"
set_option verso.blueprint.trust.challengeFile "tests/fixtures/trust/Challenge.lean"
set_option verso.blueprint.trust.solutionFile "tests/fixtures/trust/Solution.lean"
set_option verso.blueprint.trust.statementClosure true

#docs (Manual) closureWiringDoc "Closure Wiring" :=
:::::::
:::theorem "closure.wiring.anchor" (lean := "Nat.add_comm")
Addition on the naturals commutes.
:::

{blueprint_dashboard}

{blueprint_trust_model}
:::::::

/-! ## The trust-model page reports the surface, in the state it is actually in -/

-- Elaborating this module ran the tool: the fixture's chain matched, so the page gets the
-- bound sentence and not one of the three weaker ones.
/-- info: true -/
#guard_msgs(info, drop warning) in
#eval show IO Bool from do
  let html ← renderManualDocHtmlString extension_impls% closureWiringDoc
  return hasSubstr html
      "computed from the exact challenge files the verifying run recorded" &&
    hasSubstr html "marked as bound to that run only when the bytes match digest for digest" &&
    -- The point of the paragraph: it measures the unmovable step, it does not remove it.
    hasSubstr html "That list does not check the correspondence and cannot." &&
    hasSubstr html "how much reading the unmovable residue actually is" &&
    -- And it is not the unbound, aligned-statement, or unavailable wording.
    !hasSubstr html "nothing ties them to the run the verdict came from" &&
    !hasSubstr html "aligned with the certified statements rather than from the challenge file" &&
    !hasSubstr html "it reports there why it could not"

/-! ## The payload survives the round trip

The closure is quoted into the document and decoded from the traversal store at generation
time; a field that does not survive that is a field the comparator page never sees.
-/

/-- info: (true, true, true, true) -/
#guard_msgs(info, drop warning) in
#eval show IO (Bool × Bool × Bool × Bool) from do
  let (_, st) ← renderManualDocHtmlStringAndState extension_impls% closureWiringDoc
  let trust? := (Informal.TraversalIndex.TrustData.raw? st).bind fun j =>
    (fromJson? (α := TrustData) j).toOption
  match trust?.bind (·.comparator) |>.bind (·.closure?) with
  | Option.none => return (false, false, false, false)
  | Option.some c =>
    return (
      c.provenance == "chain" && c.reason.isEmpty,
      c.roots == ["TrustFixture.add_comm_claim"] && !c.truncated && c.total > 0,
      -- The chain the tool hashed, carried through for the provenance line.
      c.chainFiles.any (fun f => (f.1.splitOn "Challenge.lean").length > 1),
      -- The schema-2 edge structure the meaning graph is drawn from.
      c.entries.any (fun e => !e.uses.isEmpty))

end Verso.VersoBlueprintTests.StatementClosureWiring
