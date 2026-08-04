/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import Init

/-!
# SHA-256

A self-contained SHA-256 (FIPS 180-4) over `ByteArray`, used to bind the comparator
evidence a site displays to the digests the verifying CI run recorded.

**Why pure Lean rather than shelling out to `shasum`/`sha256sum`.** The digest check is
a security boundary. A boundary that depends on an external binary has to do one of two
things when the binary is missing: fail the build (breaking builds on machines that are
not doing anything wrong, and inviting the check to be switched off), or skip the check
— degrading *open*, which makes it worthless precisely in the situation an attacker
would arrange. The inputs are single-digit-kilobyte source files, so there is no
performance argument on the other side, and no build-time toolchain dependency is worth
either failure mode.

Correctness is pinned in `tests/VersoBlueprintTests/Sha256.lean` by the FIPS 180-4
sample vectors (empty string; `"abc"`; the 56-byte two-block message) plus a longer
multi-block input, all cross-checked against the system `shasum -a 256` so the digests
interoperate with whatever CI writes into the status artifact.
-/

namespace Informal.Sha256

/-- Round constants: the first 32 bits of the fractional parts of the cube roots of the
first 64 primes (FIPS 180-4 §4.2.2). -/
private def roundConstants : Array UInt32 := #[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

/-- Initial hash value: the first 32 bits of the fractional parts of the square roots of
the first eight primes (FIPS 180-4 §5.3.3). -/
private def initialState : Array UInt32 :=
  #[0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]

/-- Rotate right within 32 bits. `n` is always in `[1, 31]` here, so the shift never
hits the mod-32 wraparound of `UInt32.shiftLeft`. -/
@[inline] private def rotr (x : UInt32) (n : UInt32) : UInt32 :=
  (x >>> n) ||| (x <<< (32 - n))

/-- The big-endian 32-bit word at byte offset `off`. -/
@[inline] private def wordAt (bs : ByteArray) (off : Nat) : UInt32 :=
  ((bs.get! off).toUInt32 <<< 24) |||
  ((bs.get! (off + 1)).toUInt32 <<< 16) |||
  ((bs.get! (off + 2)).toUInt32 <<< 8) |||
  (bs.get! (off + 3)).toUInt32

/-- FIPS 180-4 §5.1.1 padding: a `0x80` byte, zeros up to 56 mod 64, then the message
length in **bits** as a big-endian 64-bit integer. -/
private def pad (msg : ByteArray) : ByteArray := Id.run do
  let mut out := msg.push 0x80
  -- Zero-fill so that the total length is 8 bytes short of a block boundary.
  let rem := out.size % 64
  let zeros := if rem ≤ 56 then 56 - rem else 120 - rem
  for _ in [0:zeros] do
    out := out.push 0
  let bits : UInt64 := (msg.size * 8).toUInt64
  for i in [0:8] do
    out := out.push (bits >>> ((56 - 8 * i).toUInt64)).toUInt8
  return out

/-- The SHA-256 digest of `msg`, as 32 raw bytes. -/
def hash (msg : ByteArray) : ByteArray := Id.run do
  let m := pad msg
  let blocks := m.size / 64
  let mut h := initialState
  for blk in [0:blocks] do
    let off := blk * 64
    -- Message schedule.
    let mut w : Array UInt32 := #[]
    for i in [0:16] do
      w := w.push (wordAt m (off + 4 * i))
    for i in [16:64] do
      let w15 := w[i - 15]!
      let w2 := w[i - 2]!
      let s0 := (rotr w15 7) ^^^ (rotr w15 18) ^^^ (w15 >>> 3)
      let s1 := (rotr w2 17) ^^^ (rotr w2 19) ^^^ (w2 >>> 10)
      w := w.push (w[i - 16]! + s0 + w[i - 7]! + s1)
    -- Compression.
    let mut a := h[0]!
    let mut b := h[1]!
    let mut c := h[2]!
    let mut d := h[3]!
    let mut e := h[4]!
    let mut f := h[5]!
    let mut g := h[6]!
    let mut hh := h[7]!
    for i in [0:64] do
      let bigS1 := (rotr e 6) ^^^ (rotr e 11) ^^^ (rotr e 25)
      let ch := (e &&& f) ^^^ ((~~~e) &&& g)
      let temp1 := hh + bigS1 + ch + roundConstants[i]! + w[i]!
      let bigS0 := (rotr a 2) ^^^ (rotr a 13) ^^^ (rotr a 22)
      let maj := (a &&& b) ^^^ (a &&& c) ^^^ (b &&& c)
      let temp2 := bigS0 + maj
      hh := g; g := f; f := e; e := d + temp1
      d := c; c := b; b := a; a := temp1 + temp2
    h := #[h[0]! + a, h[1]! + b, h[2]! + c, h[3]! + d,
           h[4]! + e, h[5]! + f, h[6]! + g, h[7]! + hh]
  let mut out := ByteArray.empty
  for word in h do
    out := out.push (word >>> 24).toUInt8
    out := out.push (word >>> 16).toUInt8
    out := out.push (word >>> 8).toUInt8
    out := out.push word.toUInt8
  return out

private def hexDigits : Array Char :=
  #['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f']

/-- Lowercase hex encoding of a byte string. -/
def toHex (bs : ByteArray) : String :=
  bs.foldl (init := "") fun acc byte =>
    (acc.push hexDigits[byte.toNat >>> 4]!).push hexDigits[byte.toNat &&& 15]!

/-- The SHA-256 digest of `msg` as lowercase hex — the spelling `shasum -a 256`,
`sha256sum`, and GitHub Actions' `hashFiles` all produce. -/
def hex (msg : ByteArray) : String := toHex (hash msg)

/-- The SHA-256 digest of a string's UTF-8 encoding, as lowercase hex. -/
def hexOfString (s : String) : String := hex s.toUTF8

/-- Normalize a recorded digest for comparison: trimmed, lowercased, and with an
optional `sha256:` / `sha256-` prefix removed. Comparing normalized forms means a
status artifact written by a tool that uppercases (or prefixes) its digests is not
rejected as a substitution. -/
def normalizeDigest (s : String) : String :=
  let s := s.trimAscii.toString.toLower
  if s.startsWith "sha256:" then (s.drop 7).toString
  else if s.startsWith "sha256-" then (s.drop 7).toString
  else s

end Informal.Sha256
