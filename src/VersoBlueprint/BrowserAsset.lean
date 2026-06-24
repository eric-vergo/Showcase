/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/

namespace Informal.BrowserAsset

/--
Drop ESM-only import/export lines before embedding a private module as a
classic script. This is intentionally narrow: Blueprint controls the source
modules and uses the helper only while Verso lacks first-class module-script
assets.
-/
private def dropEsmOnlyLine (line : String) : Bool :=
  line.startsWith "import " ||
  line.startsWith "export {" ||
    line.startsWith "export default " ||
    line.startsWith "export * "

private def withoutEsmOnlyLines (source : String) : String :=
  String.intercalate "\n" <| (source.splitOn "\n").filter fun line =>
    !dropEsmOnlyLine line

/--
Embed a private ESM source module as a classic-script compatibility adapter.
The returned script installs the module's globals by running `installCall`
inside an IIFE whose `globalScope` argument is the browser global.
-/
def esmModuleToClassicScriptWithPrelude (source prelude installCall : String) : String :=
  let body :=
    (withoutEsmOnlyLines source)
      |>.replace "export function " "function "
      |>.replace "export const " "const "
      |>.replace "export let " "let "
      |>.replace "export var " "var "
      |>.replace "export class " "class "
  "(function (globalScope) {\n" ++
    prelude ++ "\n" ++
    body ++ "\n" ++
    installCall ++ "\n" ++
    "})(\n" ++
    "  typeof globalThis !== \"undefined\"\n" ++
    "    ? globalThis\n" ++
    "    : (typeof window !== \"undefined\" ? window : this)\n" ++
    ");"

def esmModuleToClassicScript (source installCall : String) : String :=
  esmModuleToClassicScriptWithPrelude source "" installCall

end Informal.BrowserAsset
