/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

import VersoBlueprint.NodeCard
import VersoBlueprint.NodeRoute

/-!
Tests for the Stage-2 decl-page primitives:

* `NodeCard.shortDeclName` — the single source of truth for prefix-stripped
  short display names (empty / exact / strip / non-match / nested cases);
* the `decl/<slug>/` routes (`NodeRoute.declPageSlug` / `declPageHref` /
  `declPagePath`), which the registry (`Entry.declHref?`), the all-decls graph
  supporting nodes, the catalog rows, and the page emitter must all agree on;
* `NodeCard.declMetaJson` byte-stability — the payload without the new optional
  `shortName` / `declHref` keys must be byte-identical to the legacy output, and
  the new keys must appear only when set.
-/

namespace Verso.VersoBlueprintTests.BlueprintDeclPages

/-! ## `shortDeclName` -/

-- Empty prefix is the identity.
/-- info: "A362583.Defs.foo" -/
#guard_msgs in
#eval Informal.NodeCard.shortDeclName "" "A362583.Defs.foo"

-- Exact prefix == name is the identity (never render an empty name).
/-- info: "A362583" -/
#guard_msgs in
#eval Informal.NodeCard.shortDeclName "A362583" "A362583"

-- A matching prefix + dot is stripped.
/-- info: "Defs.foo" -/
#guard_msgs in
#eval Informal.NodeCard.shortDeclName "A362583" "A362583.Defs.foo"

-- A non-matching prefix is the identity (no partial-component stripping).
/-- info: "A3625831.foo" -/
#guard_msgs in
#eval Informal.NodeCard.shortDeclName "A362583" "A3625831.foo"

-- Nested namespaces strip only the configured root prefix.
/-- info: "Sub.foo" -/
#guard_msgs in
#eval Informal.NodeCard.shortDeclName "A362583" "A362583.Sub.foo"

/-! ## Decl-page routes -/

/-- info: "A362583___Defs___foo" -/
#guard_msgs in
#eval Informal.NodeRoute.declPageSlug "A362583.Defs.foo"

/-- info: "decl/A362583___Defs___foo/" -/
#guard_msgs in
#eval Informal.NodeRoute.declPageHref "A362583.Defs.foo"

/-- info: #["decl", "A362583___Defs___foo"] -/
#guard_msgs in
#eval Informal.NodeRoute.declPagePath "A362583.Defs.foo"

-- Primed names sluggify deterministically (href and path stay in agreement).
/-- info: true -/
#guard_msgs in
#eval
  let slug := Informal.NodeRoute.declPageSlug "A362583.aux_lemma_3'"
  Informal.NodeRoute.declPageHref "A362583.aux_lemma_3'" == s!"decl/{slug}/" &&
    Informal.NodeRoute.declPagePath "A362583.aux_lemma_3'" == #["decl", slug]

/-! ## `declMetaJson` byte-stability -/

-- Legacy call shape (no optional keys): byte-identical to the pre-Stage-2 output.
/-- info: true -/
#guard_msgs in
#eval
  Informal.NodeCard.declMetaJson "A.b" "Theorem" "proved" "A.M" "Theorem 1"
      (some 3) (some 9) (some "node/thm-b/") ==
    "{\"endLine\":9,\"kind\":\"Theorem\",\"module\":\"A.M\",\"name\":\"A.b\"," ++
    "\"nodeHref\":\"node/thm-b/\",\"startLine\":3,\"status\":\"proved\",\"title\":\"Theorem 1\"}"

-- Explicitly-`none` optional keys emit nothing (same bytes as the legacy call).
/-- info: true -/
#guard_msgs in
#eval
  Informal.NodeCard.declMetaJson "A.b" "Theorem" "proved" "A.M" "Theorem 1"
      (some 3) (some 9) (some "node/thm-b/") (shortName := none) (declHref := none) ==
    Informal.NodeCard.declMetaJson "A.b" "Theorem" "proved" "A.M" "Theorem 1"
      (some 3) (some 9) (some "node/thm-b/")

-- Set optional keys appear (compressed-JSON key order is alphabetical).
/-- info: true -/
#guard_msgs in
#eval
  Informal.NodeCard.declMetaJson "A.b" "Theorem" "proved" "A.M" "Theorem 1"
      (some 3) (some 9) (some "node/thm-b/") (shortName := some "b")
      (declHref := some "decl/a-b/") ==
    "{\"declHref\":\"decl/a-b/\",\"endLine\":9,\"kind\":\"Theorem\",\"module\":\"A.M\"," ++
    "\"name\":\"A.b\",\"nodeHref\":\"node/thm-b/\",\"shortName\":\"b\",\"startLine\":3," ++
    "\"status\":\"proved\",\"title\":\"Theorem 1\"}"

-- Minimal payload: no range, no hrefs, no optional keys.
/-- info: true -/
#guard_msgs in
#eval
  Informal.NodeCard.declMetaJson "A.b" "Definition" "missing" "A.M" "" none none none ==
    "{\"kind\":\"Definition\",\"module\":\"A.M\",\"name\":\"A.b\",\"status\":\"missing\",\"title\":\"\"}"

-- NB: the Item-9 `:=`-value-prefix (`NodeCard.formalSourceBody (assignPrefix := …)`)
-- and the docstring provenance marker produce `Html`, which the `#eval`/`#guard_msgs`
-- harness cannot evaluate (no ToExpr/Repr for `Html`). They are verified end-to-end
-- by the starter smoke build: the `ProjectTemplate.doubleNat` decl page shows its
-- `:= 2 * n` value flush under the signature, and each unwired decl page shows its
-- docstring with a "From docstring" marker.

end Verso.VersoBlueprintTests.BlueprintDeclPages
