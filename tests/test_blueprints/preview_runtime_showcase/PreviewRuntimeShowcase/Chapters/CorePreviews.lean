import Verso
import VersoManual
import VersoBlueprint

open Verso.Genre
open Verso.Genre.Manual
open Informal

#doc (Manual) "Core Previews" =>

:::group "preview_core"
Core statements that drive the showcase summary and dependency graph.
:::

:::definition "preview_base" (parent := "preview_core")
Base statement for summary and graph previews.
:::

:::lemma_ "preview_next" (parent := "preview_core")
Depends on {uses "preview_base"}[].
:::

:::definition "lean_code_preview" (parent := "preview_core") (lean := "Nat.add")
Statement with an associated Lean declaration link in the summary.
:::

:::theorem "preview_final" (parent := "preview_core")
Combines {uses "preview_next"}[] with {uses "lean_code_preview"}[].
:::
