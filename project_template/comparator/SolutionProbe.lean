import Lean.Elab.Command

/-!
# Comparator sandbox regression fixture (CI only)

⚠️ **This module writes files when it is elaborated. Never open it in an elaborating editor
outside a sandbox.** That behaviour is the point: it is `comparator/Solution.lean` plus one
top-level `run_cmd` that tries to write outside the comparator's Landlock sandbox, before any
declaration of this module is elaborated.

Lean elaboration is arbitrary code execution, so a comparator run that elaborates the solution
*outside* confinement lets that write succeed. CI drives this module through the same sandbox
wrapper as the real solution, using `comparator/comparator-probe.json`, and it is expected to
FAIL:

* every write denied — elaboration aborts with the sentinel
  `COMPARATOR_PROBE_WRITES_DENIED`, the sandboxed build fails and the comparator exits
  non-zero. This is the passing outcome; CI matches the sentinel so an unrelated failure
  cannot be mistaken for it.
* any write accepted — this module stays silent, proves the challenge statement like the real
  solution, and the comparator exits 0 with the canary files on disk. CI fails on both signals.

It is registered as the `SolutionProbe` lake lib, is deliberately not a default target, and
nothing imports it.
-/

namespace SolutionProbe

/-- The paths the probe writes to. Both parent directories always exist, so a refused write is
a denial rather than a missing directory: the process working directory, inside the checkout
the sandbox mounts read-only, and the home directory, outside the checkout. -/
private def probeTargets : IO (Array String) := do
  let cwd ← IO.currentDir
  let mut targets : Array String := #[cwd.toString ++ "/comparator-probe-canary"]
  if let some home := (← IO.getEnv "HOME") then
    targets := targets.push (home ++ "/comparator-probe-canary")
  return targets

/-- Attempt one write, reporting whether it was accepted. -/
private def tryWrite (target : String) : IO Bool := do
  try
    IO.FS.writeFile (System.FilePath.mk target)
      "comparator sandbox breach: an elaboration-time write succeeded\n"
    return true
  catch _ =>
    return false

/-- The targets whose writes were accepted; empty means the sandbox held. -/
private def attemptEscape (targets : Array String) : IO (Array String) := do
  let mut written : Array String := #[]
  for target in targets do
    if (← tryWrite target) then
      written := written.push target
  return written

end SolutionProbe

run_cmd do
  let targets ← SolutionProbe.probeTargets
  let written ← SolutionProbe.attemptEscape targets
  if written.isEmpty then
    let names := String.intercalate ", " targets.toList
    throwError "COMPARATOR_PROBE_WRITES_DENIED: every elaboration-time write outside the sandbox was refused (tried: {names})"

namespace Challenge

/-- Addition on the natural numbers is associative. -/
theorem add_assoc (a b c : Nat) : a + b + c = a + (b + c) := Nat.add_assoc a b c

end Challenge
