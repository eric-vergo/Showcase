# Caveat-surface fixtures

Inputs for `tests/VersoBlueprintTests/Caveats.lean`.

- `Challenge.lean` — the §A7(a) shape: a certified statement that mentions no
  total-function convention, whose meaning closure reaches three of them one wrapper deep.
  A root-type scan finds nothing here; the traversal-riding scan finds `Nat.sub`,
  `Nat.div` and generic division by zero. It also carries a real `set_option`, one inside
  a comment, and one inside a string literal, which is what the lexical half has to get
  right.
- `table-override.json` — a consumer override that **replaces** the bundled `Nat.sub`
  entry (entry-replace on the stable symbol key) and **adds** one symbol.
- `table-duplicate-alias.json` — an override claiming `instSubNat`, a match key the
  bundled `Nat.sub` entry already owns. Merging it is a build error.
- `table-future-version.json` — `schemaVersion: 99`. Reading it is a build error.
- `characterizations.json` — a well-formed sidecar naming a declaration every environment
  has.
- `characterizations-duplicate.json` — two entries for one declaration.
- `characterizations-malformed.json` — an entry with no `decl`.
- `characterizations-unresolved.json` — a `decl` no environment has; the one failure the
  loader cannot see on its own (`unresolvedDecls` needs an environment).
