/-
Copyright (c) 2026 Eric Vergo. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Eric Vergo, Claude Fable 5, Claude Opus 4.8, Claude Opus 5 (Claude Code)
-/

import VersoManual
import VersoBlueprint.Macros

/-!
Build-time TikZ → SVG diagrams for the Blueprint genre.

Mirrors the core `Verso.Genre.Manual.Block.diagram` block (`verso-manual/.../Diagrams.lean`),
but instead of evaluating an Illuminate term it renders author-supplied TikZ source to SVG at
elaboration time by shelling out to `latex` + `dvisvgm` (modeled on `MathLint.lean`).

The resulting SVG is inlined into the page (no external file / CDN) so the generated site stays
fully self-contained offline. Rendering is best-effort: if the TeX toolchain is unavailable or
the render fails, the build still succeeds and the diagram degrades to its TikZ source plus
caption.
-/

open Lean Elab
open Verso ArgParse Doc Elab Genre.Manual Html
open Verso.Output (Html)
open Verso.Doc.Html (HtmlT)

register_option verso.blueprint.diagram.render : Bool := {
  defValue := true
  descr := "if true, render blueprint TikZ diagrams to inline SVG at build time via latex+dvisvgm; falls back to showing the TikZ source when the toolchain is unavailable or rendering fails"
}

namespace Informal.Tikz

/-- Whether build-time TikZ rendering is enabled (mirrors `Informal.MathLint.enabled`). -/
def renderEnabled (opts : Lean.Options) : Bool :=
  opts.get verso.blueprint.diagram.render.name verso.blueprint.diagram.render.defValue

/-- Probe of `latex` + `dvisvgm`, computed once per Lean process. -/
initialize toolchainAvailableRef : IO.Ref (Option Bool) ← IO.mkRef none

/-- Memoizes rendered SVGs keyed by a hash of `(preamble, source)`. `none` = render failed. -/
initialize diagramCacheRef : IO.Ref (Std.HashMap String (Option String)) ← IO.mkRef {}

/-- kpathsea environment overrides for the `dvisvgm` subprocess, derived once via `kpsewhich`. -/
initialize kpathseaEnvRef : IO.Ref (Option (Array (String × Option String))) ← IO.mkRef none

private def probe (cmd : String) : IO Bool := do
  try
    let out ← IO.Process.output { cmd, args := #["--version"] }
    pure (out.exitCode == 0)
  catch _ =>
    pure false

private def kpsewhichVar (var : String) : IO (Option String) := do
  try
    let out ← IO.Process.output { cmd := "kpsewhich", args := #["-var-value", var] }
    if out.exitCode == 0 then
      let v := out.stdout.trimAscii.toString
      pure (if v.isEmpty then none else some v)
    else
      pure none
  catch _ =>
    pure none

/--
Environment overrides that point a non-TeX-Live `dvisvgm` (e.g. the Homebrew build, whose bundled
kpathsea searches the wrong tree) at the active TeX Live installation, derived once via `kpsewhich`.

Returns `#[]` when `kpsewhich` is unavailable; a normal full TeX Live install (where `dvisvgm`
ships with the distribution) needs no override.
-/
def kpathseaEnv : IO (Array (String × Option String)) := do
  if let some cached := ← kpathseaEnvRef.get then
    return cached
  let overrides ←
    match (← kpsewhichVar "TEXMFROOT"), (← kpsewhichVar "TEXMFDIST") with
    | some root, some dist =>
      pure #[("TEXMFROOT", some root), ("TEXMFDIST", some dist),
             ("TEXMFCNF", some s!"{dist}/web2c:{root}")]
    | some root, none => pure #[("TEXMFROOT", some root)]
    | _, _ => pure #[]
  kpathseaEnvRef.set (some overrides)
  pure overrides

/-- Probe `latex` and `dvisvgm` once per process; missing tooling quietly disables rendering. -/
def toolchainAvailable : IO Bool := do
  match ← toolchainAvailableRef.get with
  | some available => pure available
  | none =>
    let available := (← probe "latex") && (← probe "dvisvgm")
    toolchainAvailableRef.set (some available)
    pure available

/-- Wrap bare TikZ commands in a `tikzpicture` environment unless the author supplied their own. -/
private def wrapPicture (source : String) : String :=
  if (source.splitOn "\\begin{tikzpicture}").length > 1 then
    source
  else
    "\\begin{tikzpicture}\n" ++ source ++ "\n\\end{tikzpicture}"

/--
Build a standalone LaTeX document for one TikZ picture, reusing the shared blueprint preamble.

Uses the `dvisvgm` PGF system driver so the DVI carries native `dvisvgm:raw` SVG specials rather
than PostScript specials — this avoids a Ghostscript dependency and the dvips PostScript headers.
-/
private def standaloneDoc (preamble source : String) : String :=
  let pre := if preamble.trimAscii.toString.isEmpty then "" else preamble ++ "\n"
  "\\documentclass[border=2pt]{standalone}\n" ++
    "\\def\\pgfsysdriver{pgfsys-dvisvgm.def}\n" ++
    "\\usepackage{tikz}\n" ++
    pre ++
    "\\begin{document}\n" ++
    wrapPicture source ++ "\n" ++
    "\\end{document}\n"

private def renderUncached (preamble source : String) : IO (Option String) := do
  if !(← toolchainAvailable) then
    return none
  try
    IO.FS.withTempDir fun dir => do
      let texFile := dir / "diagram.tex"
      IO.FS.writeFile texFile (standaloneDoc preamble source)
      -- latex (DVI mode) -> diagram.dvi
      let latexOut ← IO.Process.output {
        cmd := "latex"
        args := #["-interaction=nonstopmode", "-halt-on-error",
                  "-output-directory", dir.toString, texFile.toString]
        cwd := some dir
      }
      let dviFile := dir / "diagram.dvi"
      if latexOut.exitCode != 0 || !(← dviFile.pathExists) then
        IO.eprintln s!"verso-blueprint: TikZ latex step failed; falling back to source.\n{latexOut.stdout}"
        return none
      -- dvisvgm -> diagram.svg (env points a non-TeX-Live dvisvgm at the active TeX tree)
      let svgFile := dir / "diagram.svg"
      let svgOut ← IO.Process.output {
        cmd := "dvisvgm"
        args := #["--no-fonts", "--exact", "--relative",
                  dviFile.toString, "-o", svgFile.toString]
        cwd := some dir
        env := ← kpathseaEnv
      }
      if svgOut.exitCode != 0 || !(← svgFile.pathExists) then
        IO.eprintln s!"verso-blueprint: TikZ dvisvgm step failed; falling back to source.\n{svgOut.stderr}"
        return none
      let svg ← IO.FS.readFile svgFile
      return some svg
  catch e =>
    IO.eprintln s!"verso-blueprint: TikZ render raised an exception; falling back to source: {e}"
    return none

/--
Render TikZ `source` (with the shared TeX `preamble`) to an inline SVG string.

Best-effort and memoized: returns `none` if the toolchain is unavailable or any step fails, so
callers can degrade gracefully to the TikZ source.
-/
def renderTikz? (preamble source : String) : IO (Option String) := do
  let key := toString (hash (preamble ++ "\x00TIKZ\x00" ++ source))
  if let some cached := (← diagramCacheRef.get)[key]? then
    return cached
  let result ← renderUncached preamble source
  diagramCacheRef.modify (·.insert key result)
  pure result

/-- Author-facing configuration for the `tikz` code block. -/
structure TikzConfig where
  caption : Option String
  label : Option String

section
variable [Monad m] [MonadError m] [MonadInfoTree m] [MonadLiftT CoreM m] [MonadEnv m]

/-- Argument parser for `TikzConfig`. -/
def TikzConfig.parse : ArgParse m TikzConfig :=
  TikzConfig.mk <$> .named' `caption true <*> .named' `label true

instance : FromArgs TikzConfig m := ⟨TikzConfig.parse⟩

end

private def optStr : Option String → Json
  | some s => Json.str s
  | none => Json.null

private def jsonStr? : Json → Option String
  | .str s => some s
  | _ => none

private def figureCss : String := r#"
figure.bp_figure {
  margin: 1.75em auto;
  text-align: center;
}
figure.bp_figure .bp_diagram {
  display: inline-block;
  max-width: 100%;
  padding: 0.75em 1em;
  /* dvisvgm emits hard `fill/stroke #000`, so the figure card stays a fixed light
     surface in every theme — a black diagram on a fixed white card is readable in
     dark mode too. The background literal equals the light `--bp-color-surface`
     value (#ffffff). The border is an intentional slate-300 (#cbd5e1) — a slightly
     stronger hairline than `--bp-color-border` (#dbe2ea) — kept fixed across themes
     alongside the fixed white card so the black SVG stays framed and readable; it is
     routed through `--bp-figure-border` rather than hardcoded. */
  border: 1px solid var(--bp-figure-border, #cbd5e1);
  border-radius: var(--bp-radius-md, 8px);
  background: #ffffff;
}
figure.bp_figure .bp_diagram svg {
  /* dvisvgm natural size is tiny (~209x117px) in a wide column; scale the schematic
     up to a comfortable default width while preserving aspect ratio and not
     overflowing the card. */
  width: 100%;
  max-width: 24rem;
  height: auto;
}
figure.bp_figure figcaption {
  margin-top: 0.5em;
  font-size: 0.9em;
  color: var(--bp-color-text-muted, #334155);
}
figure.bp_figure .bp_figure_label {
  font-weight: 600;
  color: var(--bp-color-text-strong, #15212b);
}
figure.bp_figure .bp_diagram_fallback {
  text-align: left;
}
figure.bp_figure .bp_diagram_fallback pre {
  margin: 0;
  overflow-x: auto;
}
"#

block_extension Block.tikzDiagram
    (svg : Option String) (texSource : String) (caption : Option String) (label : Option String) where
  data := Json.arr #[optStr svg, Json.str texSource, optStr caption, optStr label]
  extraCss := [figureCss]
  traverse id data _ := do
    let .arr #[_, _, captionJson, labelJson] := data
      | pure none
    match jsonStr? labelJson with
    | some label =>
      assignFigureNumber id label (jsonStr? captionJson)
      pure none
    | none => pure none
  toHtml :=
    open Verso.Output.Html in
    open Verso.Doc.Html HtmlT in
    some <| fun _ _ id data _ => do
      let .arr #[svgJson, texJson, captionJson, labelJson] := data
        | reportError "Expected four-element JSON for tikzDiagram" *> pure .empty
      let svg? := jsonStr? svgJson
      let texSrc := (jsonStr? texJson).getD ""
      let caption? := jsonStr? captionJson
      let label? := jsonStr? labelJson
      let st ← state
      -- The assigned figure number, if this diagram was labeled and registered during traversal.
      let figNum? := label?.bind fun l =>
        (st.getDomainObject? figureDomain l).bind (·.data.getObjValAs? String "figNum" |>.toOption)
      let inner :=
        match svg? with
        | some svg =>
          Html.tag "div" #[("class", "bp_diagram")] (Html.text false svg)
        | none =>
          Html.tag "div" #[("class", "bp_diagram bp_diagram_fallback")]
            (Html.tag "pre" #[] (Html.tag "code" #[] (Html.text true texSrc)))
      -- The "Figure N." prefix is wrapped in its own element so it reads as a label/eyebrow
      -- typographically set apart from the caption prose.
      let figLabel := fun (n : String) =>
        Html.tag "span" #[("class", "bp_figure_label")] (Html.text true s!"Figure {n}.")
      let captionHtml :=
        match figNum?, caption? with
        | some n, some c => Html.tag "figcaption" #[] (figLabel n ++ Html.text true s!" {c}")
        | some n, none => Html.tag "figcaption" #[] (figLabel n)
        | none, some c => Html.tag "figcaption" #[] (Html.text true c)
        | none, none => Html.empty
      -- Anchor id comes from the cross-reference machinery (matches the `{ref}` link target) so
      -- references resolve; falls back to no id for unlabeled figures.
      let attrs := #[("class", "bp_figure")] ++ st.htmlId id
      pure <| Html.tag "figure" attrs (inner ++ captionHtml)
  usePackages := ["\\usepackage{tikz}"]
  toTeX :=
    some <| fun _ _ _ data _ => do
      let .arr #[_svgJson, texJson, captionJson, labelJson] := data
        | reportError "Expected four-element JSON for tikzDiagram" *> pure .empty
      let texSrc := (jsonStr? texJson).getD ""
      let caption? := jsonStr? captionJson
      let label? := jsonStr? labelJson
      let body := wrapPicture texSrc
      let captionTeX := match caption? with | some c => "\\caption{" ++ c ++ "}\n" | none => ""
      let labelTeX := match label? with | some l => "\\label{" ++ l ++ "}\n" | none => ""
      pure <| .raw <|
        "\\begin{figure}\n\\centering\n" ++ body ++ "\n" ++ captionTeX ++ labelTeX ++ "\\end{figure}\n"

end Informal.Tikz

open Verso Doc Elab Genre.Manual

/--
A build-time-rendered TikZ figure.

Authored as a fenced code block whose body is raw TikZ source:

````
```tikz (caption := "The Collatz step") (label := "fig:collatz")
\node (n) {$n$};
\node (a) [right=of n] {$3n+1$};
\draw[->] (n) -- (a);
```
````

The body may be bare TikZ commands (automatically wrapped in a `tikzpicture` environment) or a
full `\begin{tikzpicture}...\end{tikzpicture}`. Both arguments are optional:

* `caption := "<text>"` — rendered as a `<figcaption>` (and a `\caption{...}` in TeX output).
* `label := "<id>"` — used as the figure's HTML `id` anchor (and a `\label{...}` in TeX output).

The TikZ source is rendered to SVG at build time and inlined into the page, so the generated site
stays fully offline. If `latex`/`dvisvgm` are unavailable or rendering fails, the build still
succeeds and the figure falls back to showing the TikZ source.
-/
@[code_block]
def tikz : CodeBlockExpanderOf Informal.Tikz.TikzConfig
  | cfg, str => do
    let source := str.getString
    let enabled := Informal.Tikz.renderEnabled (← getOptions)
    let svg? ←
      if enabled then
        let preamble ← Informal.Macros.getTexPrelude
        Informal.Tikz.renderTikz? preamble source
      else
        pure none
    if enabled && svg?.isNone then
      logWarning "Blueprint TikZ diagram could not be rendered to SVG; showing the TikZ source instead. Ensure `latex` and `dvisvgm` are installed and on PATH."
    ``(Verso.Doc.Block.other
        (Informal.Tikz.Block.tikzDiagram
          $(quote svg?) $(quote source) $(quote cfg.caption) $(quote cfg.label))
        #[Verso.Doc.Block.code $(quote source)])
