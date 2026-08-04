/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import VersoBlueprint.Sha256

/-!
Test vectors for the pure-Lean SHA-256 used to bind displayed comparator evidence to
the digests a verifying CI run recorded.

The first three are the FIPS 180-4 samples (empty message; `"abc"`, one block; the
56-byte message that forces a second block through the length field). The fourth is a
4500-byte multi-block input.

All four expectations were cross-checked against the system `shasum -a 256` at
development time — the point being interoperability with whatever CI writes into the
status artifact, not merely internal consistency. To repeat the cross-check:

```bash
printf ''    | shasum -a 256   # e3b0c442…b855
printf 'abc' | shasum -a 256   # ba7816bf…15ad
printf 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq' | shasum -a 256
python3 -c "import sys; sys.stdout.write('The quick brown fox jumps over the lazy dog. '*100)" \
  | shasum -a 256              # 3b9dc18c…59d0, 4500 bytes
```
-/

namespace Verso.VersoBlueprintTests.Sha256

open Informal.Sha256

/-! ## FIPS 180-4 sample vectors -/

-- Empty message: exercises the padding path where the whole block is padding.
/-- info: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" -/
#guard_msgs in
#eval hexOfString ""

-- "abc": the canonical one-block vector.
/-- info: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" -/
#guard_msgs in
#eval hexOfString "abc"

-- 56 bytes: with the 0x80 terminator this leaves no room for the 8-byte length in the
-- first block, so the message spills into a second one. The off-by-one in `pad` that
-- this catches is the classic SHA-256 implementation bug.
/-- info: "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" -/
#guard_msgs in
#eval hexOfString "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"

/-! ## Multi-block, cross-checked against the system `shasum -a 256` -/

-- 4500 bytes = 70 full blocks plus a partial one.
private def longMessage : String :=
  String.join (List.replicate 100 "The quick brown fox jumps over the lazy dog. ")

/-- info: (4500, "3b9dc18c6a8d76556996cd1829f61a38fb7b223f027d0326bb9f39c6ca2459d0") -/
#guard_msgs in
#eval (longMessage.utf8ByteSize, hexOfString longMessage)

/-! ## Digest normalization

A status artifact written by a tool that uppercases its digests, or prefixes them, must
not read as a substitution.
-/

/-- info: #["e3b0c442", "e3b0c442", "e3b0c442", "e3b0c442", ""] -/
#guard_msgs in
#eval #["e3b0c442", "E3B0C442", "  e3b0c442  ", "sha256:E3B0C442", "   "].map normalizeDigest

end Verso.VersoBlueprintTests.Sha256
