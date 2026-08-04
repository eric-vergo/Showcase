"""Format-aware off-origin asset scanner for generated blueprint sites (CX-013).

"The published site must load nothing from another origin" is a whole-site behavioral
property, not an enumerated-substring property. The previous CI gate implemented it as a
battery of regular expressions and consequently missed every URL-bearing surface it did
not happen to enumerate (image ``srcset``, video ``poster``, ``object[data]``, SVG
``image href``/``xlink:href``, and JS ``Image.src`` assignment all passed cleanly).

This scanner instead parses each emitted artifact by format and enumerates URL-bearing
constructs:

* HTML — every resource-bearing element attribute (``src``/``srcset``/``href``/
  ``xlink:href``/``poster``/``data``/``formaction``/…), plus ``<meta http-equiv=refresh>``
  targets. Inline ``<script>`` bodies are handed to the JS pass and inline ``<style>``
  bodies plus ``style=`` attributes to the CSS pass.
* CSS — ``url(...)`` and ``@import`` targets, including ``image-set()``.
* JavaScript — a comment/string-aware lexer flags network sinks whose argument is an
  off-origin URL literal (``fetch``, ``XMLHttpRequest.open``, ``WebSocket``,
  ``navigator.sendBeacon``, ``EventSource``, ``importScripts``, dynamic ``import()``)
  and off-origin literals assigned to resource properties (``.src``/``.srcset``/
  ``.href``/``.data``/``.poster``/``.action``). Off-origin URLs that appear only inside
  comments or unrelated strings (e.g. a vendored library's banner) are intentionally not
  flagged.

A target is off-origin when it is absolute with an ``http``/``https`` scheme or is
protocol-relative (``//host/...``); whitespace, ASCII-case, and HTML-entity variants
normalize to the same verdict. Same-origin relative URLs and ``data:``/``blob:`` payloads
are allowed (they never leave the origin).

This module is both a CLI gate and an importable library (the regression suite in
tests/harness/test_off_origin_scanner.py drives its functions directly). It has no
third-party dependencies so CI can run it under the runner's bare ``python3``.

The scanner is the primary boundary; the emitted ``<meta http-equiv="Content-Security-Policy">``
(see verso-blueprint's blueprint asset seam) is the second, browser-enforced boundary.
"""

from __future__ import annotations

import argparse
import html as html_module
import re
import sys
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


HTML_SUFFIXES = {".html", ".htm", ".xhtml"}
CSS_SUFFIXES = {".css"}
JS_SUFFIXES = {".js", ".mjs", ".cjs"}


@dataclass(frozen=True)
class Hit:
    path: str
    kind: str  # "html" | "css" | "js"
    detail: str
    target: str

    def __str__(self) -> str:
        return f"{self.path}: [{self.kind}] {self.detail} -> {self.target!r}"


def is_off_origin(value: str | None) -> bool:
    """True when *value* would load from another origin in a browser.

    Absolute ``http``/``https`` URLs and protocol-relative ``//host`` URLs are off-origin.
    Relative URLs, fragments, and ``data:``/``blob:``/``mailto:``/``tel:`` are same-origin
    or non-network and allowed. Leading/trailing whitespace and ASCII case do not matter.
    """
    if value is None:
        return False
    stripped = value.strip()
    if not stripped:
        return False
    if stripped.startswith("//") and not stripped.startswith("///"):
        return True
    scheme = urlsplit(stripped).scheme.lower()
    return scheme in {"http", "https", "ws", "wss", "ftp"}


# --- HTML -----------------------------------------------------------------------------

# Element -> resource-bearing attributes. Enumerated, not sampled: any attribute a browser
# resolves as a URL that can initiate an off-origin request belongs here.
_RESOURCE_ATTRS: dict[str, tuple[str, ...]] = {
    "script": ("src",),
    "link": ("href",),
    "img": ("src", "srcset", "lowsrc"),
    "source": ("src", "srcset"),
    "iframe": ("src",),
    "frame": ("src",),
    "embed": ("src",),
    "video": ("src", "poster"),
    "audio": ("src",),
    "track": ("src",),
    "object": ("data",),
    "input": ("src", "formaction"),
    "button": ("formaction"),
    "form": ("action",),
    "image": ("href", "xlink:href"),  # SVG <image>
    "use": ("href", "xlink:href"),  # SVG <use>
    "a": (),  # outbound links are the point of a blueprint; never flagged
    "area": (),
}

_SRCSET_ATTRS = {"srcset", "imagesrcset"}


def _srcset_candidates(value: str) -> list[str]:
    return [item.strip().split()[0] for item in value.split(",") if item.strip()]


class _HtmlScanner(HTMLParser):
    def __init__(self, path: str) -> None:
        # convert_charrefs decodes entity-encoded URLs (e.g. https&#58;//host) before we
        # inspect them, so the entity-escaping bypass class is covered.
        super().__init__(convert_charrefs=True)
        self.path = path
        self.hits: list[Hit] = []
        self._script_stack: list[dict[str, str]] = []
        self._style_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        data = {name.lower(): (value or "") for name, value in attrs}
        for attr in _RESOURCE_ATTRS.get(tag, ()):  # type: ignore[arg-type]
            raw = data.get(attr)
            if raw is None:
                continue
            values = _srcset_candidates(raw) if attr in _SRCSET_ATTRS else [raw]
            for value in values:
                if is_off_origin(value):
                    self.hits.append(Hit(self.path, "html", f"<{tag} {attr}>", value))
        # imagesrcset on <link rel=preload as=image> / <source>
        for attr in ("imagesrcset",):
            if attr in data:
                for value in _srcset_candidates(data[attr]):
                    if is_off_origin(value):
                        self.hits.append(Hit(self.path, "html", f"<{tag} {attr}>", value))
        # <meta http-equiv="refresh" content="0; url=...">
        if tag == "meta" and data.get("http-equiv", "").lower() == "refresh":
            match = re.search(r"(?i)\burl\s*=\s*(.+)$", data.get("content", ""))
            if match:
                target = match.group(1).strip().strip("'\"")
                if is_off_origin(target):
                    self.hits.append(Hit(self.path, "html", "<meta refresh>", target))
        # inline style attribute
        if "style" in data:
            self.hits.extend(scan_css(data["style"], self.path, detail_prefix="style="))
        if tag == "script":
            self._script_stack.append(data)
        if tag == "style":
            self._style_depth += 1

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)

    def handle_data(self, data: str) -> None:
        if self._script_stack:
            attrs = self._script_stack[-1]
            script_type = attrs.get("type", "").lower()
            # data blocks (application/json, text/template, …) are not executable JS
            if script_type in ("", "module", "text/javascript", "application/javascript"):
                self.hits.extend(scan_js(data, self.path, detail_prefix="inline <script> "))
        elif self._style_depth > 0:
            self.hits.extend(scan_css(data, self.path))

    def handle_endtag(self, tag: str) -> None:
        if tag == "script" and self._script_stack:
            self._script_stack.pop()
        if tag == "style" and self._style_depth > 0:
            self._style_depth -= 1


def scan_html(text: str, path: str = "<html>") -> list[Hit]:
    scanner = _HtmlScanner(path)
    scanner.feed(text)
    scanner.close()
    return scanner.hits


# --- CSS ------------------------------------------------------------------------------

_CSS_URL = re.compile(r"url\(\s*(?P<q>['\"]?)(?P<u>[^)'\"]+)(?P=q)\s*\)", re.IGNORECASE)
_CSS_IMPORT = re.compile(r"@import\s+(?:url\(\s*)?(?P<q>['\"]?)(?P<u>[^)'\";]+)(?P=q)", re.IGNORECASE)


def scan_css(text: str, path: str = "<css>", *, detail_prefix: str = "") -> list[Hit]:
    hits: list[Hit] = []
    for match in _CSS_URL.finditer(text):
        target = html_module.unescape(match.group("u").strip())
        if is_off_origin(target):
            hits.append(Hit(path, "css", f"{detail_prefix}url()", target))
    for match in _CSS_IMPORT.finditer(text):
        target = html_module.unescape(match.group("u").strip())
        if is_off_origin(target):
            hits.append(Hit(path, "css", f"{detail_prefix}@import", target))
    return hits


# --- JavaScript -----------------------------------------------------------------------

def _strip_js_comments(text: str) -> str:
    """Remove // and /* */ comments while respecting string and template literals, so an
    off-origin URL inside a vendored banner comment is not mistaken for a live sink."""
    out: list[str] = []
    i, n = 0, len(text)
    quote: str | None = None
    while i < n:
        ch = text[i]
        two = text[i : i + 2]
        if quote is not None:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if two == "//":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if two == "/*":
            i += 2
            while i < n and text[i : i + 2] != "*/":
                i += 1
            i += 2
            continue
        if ch in "'\"`":
            quote = ch
            out.append(ch)
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


# String literal (single/double/backtick) capturing its contents.
_STR = r"""(?:'([^'\\]*(?:\\.[^'\\]*)*)'|"([^"\\]*(?:\\.[^"\\]*)*)"|`([^`\\]*(?:\\.[^`\\]*)*)`)"""

# Network-request sinks whose URL is the FIRST string-literal argument.
_JS_SINK_FIRST_ARG = re.compile(
    r"(?P<sink>\bfetch|\bimport(?!Scripts)|\bimportScripts|new\s+WebSocket|"
    r"new\s+EventSource|navigator\s*\.\s*sendBeacon)\s*\(\s*" + _STR,
    re.IGNORECASE,
)

# XMLHttpRequest.open(method, url, ...) — the URL is the SECOND string-literal argument.
_JS_XHR_OPEN = re.compile(
    r"(?P<sink>\.\s*open)\s*\(\s*" + _STR + r"\s*,\s*" + _STR,
    re.IGNORECASE,
)

# Off-origin literals assigned to resource-loading DOM properties (the Image.src bypass).
_JS_PROP_ASSIGN = re.compile(
    r"\.\s*(?P<prop>src|srcset|href|data|poster|action|formAction|xlinkHref)\s*=\s*" + _STR,
    re.IGNORECASE,
)

# setAttribute("src", "http://…") / setAttributeNS(ns, "href", "http://…")
_JS_SET_ATTR = re.compile(
    r"\.\s*setAttribute(?:NS)?\s*\(\s*(?:[^()]*?,\s*)?"
    r"['\"](?:src|srcset|href|xlink:href|data|poster|action|formaction)['\"]\s*,\s*" + _STR,
    re.IGNORECASE,
)


def _literal(match: re.Match[str]) -> str:
    for group in match.groups()[-3:]:
        if group is not None:
            # decode common JS escapes that matter for scheme detection
            return group.encode().decode("unicode_escape", "ignore")
    return ""


def scan_js(text: str, path: str = "<js>", *, detail_prefix: str = "") -> list[Hit]:
    source = _strip_js_comments(text)
    hits: list[Hit] = []
    for pattern in (_JS_SINK_FIRST_ARG, _JS_XHR_OPEN):
        for match in pattern.finditer(source):
            target = _literal(match)
            if is_off_origin(target):
                sink = re.sub(r"\s+", " ", match.group("sink")).strip().lstrip(".")
                hits.append(Hit(path, "js", f"{detail_prefix}{sink}() network sink", target))
    for match in _JS_PROP_ASSIGN.finditer(source):
        target = _literal(match)
        if is_off_origin(target):
            hits.append(Hit(path, "js", f"{detail_prefix}.{match.group('prop')} = assignment", target))
    for match in _JS_SET_ATTR.finditer(source):
        target = _literal(match)
        if is_off_origin(target):
            hits.append(Hit(path, "js", f"{detail_prefix}setAttribute() resource", target))
    return hits


# --- Dispatch / CLI -------------------------------------------------------------------

def scan_file(path: Path) -> list[Hit]:
    suffix = path.suffix.lower()
    text = path.read_text(errors="replace")
    rel = str(path)
    if suffix in HTML_SUFFIXES:
        return scan_html(text, rel)
    if suffix in CSS_SUFFIXES:
        return scan_css(text, rel)
    if suffix in JS_SUFFIXES:
        return scan_js(text, rel)
    return []


def scan_tree(root: Path) -> list[Hit]:
    hits: list[Hit] = []
    targets = [root] if root.is_file() else sorted(root.rglob("*"))
    for path in targets:
        if path.is_file() and path.suffix.lower() in (HTML_SUFFIXES | CSS_SUFFIXES | JS_SUFFIXES):
            hits.extend(scan_file(path))
    return hits


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Scan a generated site for off-origin assets.")
    parser.add_argument("roots", nargs="+", type=Path, help="Site directories or files to scan.")
    args = parser.parse_args(argv)

    all_hits: list[Hit] = []
    for root in args.roots:
        if not root.exists():
            print(f"off-origin scanner: path does not exist: {root}", file=sys.stderr)
            return 2
        all_hits.extend(scan_tree(root))

    if all_hits:
        print(f"off-origin: {len(all_hits)} off-origin asset reference(s) found in the generated site:")
        for hit in all_hits:
            print(f"  {hit}")
        return 1
    print("off-origin: none found")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
