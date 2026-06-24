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

private def stripEsmExportKeywords (source : String) : String :=
  source
    |>.replace "export async function " "async function "
    |>.replace "export function " "function "
    |>.replace "export const " "const "
    |>.replace "export let " "let "
    |>.replace "export var " "var "
    |>.replace "export class " "class "

/--
Embed a private ESM source module as a classic-script compatibility adapter.
The returned script installs the module's globals by running `installCall`
inside an IIFE whose `globalScope` argument is the browser global.
-/
def esmModuleToClassicScriptWithPrelude (source prelude installCall : String) : String :=
  let body := stripEsmExportKeywords (withoutEsmOnlyLines source)
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

/--
Embed a private ESM source module as a classic-script fragment. Unlike
`esmModuleToClassicScript`, this does not add an IIFE; callers use it when the
fragment must share lexical scope with neighboring runtime chunks in the
current bundled Verso asset.
-/
def esmModuleToClassicFragmentWithPrelude (source prelude : String) : String :=
  prelude ++ "\n" ++ stripEsmExportKeywords (withoutEsmOnlyLines source)

def esmModuleToClassicFragment (source : String) : String :=
  esmModuleToClassicFragmentWithPrelude source ""

end Informal.BrowserAsset
