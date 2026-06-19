from __future__ import annotations

from pathlib import Path
import re


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
BLUEPRINT_SRC = PACKAGE_ROOT / "src" / "VersoBlueprint"
RUNTIME_BOOTSTRAP_JS = {
    Path("Commands/preview-runtime.js"),
    Path("Commands/preview-ready.js"),
}


def blueprint_js_files() -> list[Path]:
    return sorted(BLUEPRINT_SRC.rglob("*.js"))


def blueprint_js_source() -> str:
    return "\n\n".join(
        path.read_text(encoding="utf-8")
        for path in blueprint_js_files()
    )


def find_balanced_js_object_body(source: str, name: str) -> str:
    match = re.search(rf"\bconst\s+{re.escape(name)}\s*=\s*{{", source)
    if match is None:
        raise AssertionError(f"missing JavaScript object literal {name}")
    depth = 1
    pos = match.end()
    while pos < len(source):
        char = source[pos]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[match.end():pos]
        pos += 1
    raise AssertionError(f"unterminated JavaScript object literal {name}")


def js_object_methods(source: str, name: str) -> set[str]:
    body = find_balanced_js_object_body(source, name)
    return set(re.findall(r"^\s+([A-Za-z][A-Za-z0-9_]*):", body, flags=re.MULTILINE))


def runtime_api_methods(name: str) -> list[str]:
    return sorted(js_object_methods(blueprint_js_source(), name))


def manual_stable_api_methods(source: str) -> set[str]:
    start_marker = "Stable custom-client entrypoints:"
    end_marker = "Blueprint's bundled graph"
    start = source.index(start_marker) + len(start_marker)
    end = source.index(end_marker, start)
    section = source[start:end]
    return set(re.findall(r"`api\.([A-Za-z][A-Za-z0-9_]*)\(", section))
