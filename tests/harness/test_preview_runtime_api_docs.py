from __future__ import annotations

from pathlib import Path
import re
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
BLUEPRINT_SRC = PACKAGE_ROOT / "src" / "VersoBlueprint"


def _blueprint_js_source() -> str:
    return "\n\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(BLUEPRINT_SRC.rglob("*.js"))
    )


def _find_balanced_js_object_body(source: str, name: str) -> str:
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


def _js_object_methods(source: str, name: str) -> set[str]:
    body = _find_balanced_js_object_body(source, name)
    return set(re.findall(r"^\s+([A-Za-z][A-Za-z0-9_]*):", body, flags=re.MULTILINE))


def _manual_stable_api_methods(source: str) -> set[str]:
    start_marker = "Stable custom-client entrypoints:"
    end_marker = "Blueprint's bundled graph"
    start = source.index(start_marker) + len(start_marker)
    end = source.index(end_marker, start)
    section = source[start:end]
    return set(re.findall(r"`api\.([A-Za-z][A-Za-z0-9_]*)\(", section))


class PreviewRuntimeApiDocsTests(unittest.TestCase):
    def test_manual_stable_api_table_matches_runtime_source(self) -> None:
        runtime = _blueprint_js_source()
        manual = (PACKAGE_ROOT / "doc" / "MANUAL.md").read_text(encoding="utf-8")

        source_methods = _js_object_methods(runtime, "stableCustomClientApi")
        documented_methods = _manual_stable_api_methods(manual)

        self.assertEqual(documented_methods, source_methods)
        self.assertIn("`window.VersoBlueprint.onRenderReady(callback)`", manual)
        self.assertIn("namespace.onRenderReady = onRenderReady", runtime)

    def test_manual_stable_api_table_excludes_bundled_feature_helpers(self) -> None:
        runtime = _blueprint_js_source()
        manual = (PACKAGE_ROOT / "doc" / "MANUAL.md").read_text(encoding="utf-8")

        documented_methods = _manual_stable_api_methods(manual)
        helper_methods = _js_object_methods(runtime, "bundledFeatureRenderHelpers")

        self.assertFalse(documented_methods & helper_methods)


if __name__ == "__main__":
    unittest.main()
