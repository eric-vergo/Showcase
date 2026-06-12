from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

import scripts.blueprint_harness_releases as releases_mod


class BlueprintHarnessReleaseHelperTests(unittest.TestCase):
    def write(self, path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_release_candidate_names_normalize_to_tags_and_branch_ids(self) -> None:
        self.assertEqual(releases_mod.normalize_release_candidate_name("4.30-rc2"), "4.30-rc2")
        self.assertEqual(releases_mod.normalize_release_candidate_name("v4.30.0-rc2"), "4.30-rc2")
        self.assertEqual(releases_mod.release_candidate_name_or_none("v4.30.0-rc2"), "4.30-rc2")
        self.assertIsNone(releases_mod.release_candidate_name_or_none("v4.30.0"))
        self.assertEqual(releases_mod.release_candidate_ref("4.30-rc2"), "v4.30.0-rc2")
        self.assertEqual(releases_mod.normalize_lean_release_ref("4.30-rc2"), "v4.30.0-rc2")
        self.assertEqual(releases_mod.release_branch_from_lean_ref("leanprover/lean4:v4.30.0-rc2"), "v4.30.0")

    def test_lean_release_order_key_orders_release_candidates_before_final_release(self) -> None:
        self.assertLess(
            releases_mod.lean_release_order_key("v4.30.0-rc1"),
            releases_mod.lean_release_order_key("v4.30.0-rc2"),
        )
        self.assertLess(
            releases_mod.lean_release_order_key("v4.30.0-rc2"),
            releases_mod.lean_release_order_key("v4.30.0"),
        )
        self.assertEqual(
            releases_mod.lean_release_order_key("v4.30-rc2"),
            releases_mod.lean_release_order_key("v4.30.0-rc2"),
        )
        self.assertIsNone(releases_mod.lean_release_order_key("nightly-testing"))

    def test_rewrite_lean_toolchain_preserves_existing_final_newline_style(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with_newline = root / "with-newline" / "lean-toolchain"
            without_newline = root / "without-newline" / "lean-toolchain"
            self.write(with_newline, "leanprover/lean4:v4.29.0\n")
            self.write(without_newline, "leanprover/lean4:v4.29.0")

            releases_mod.rewrite_lean_toolchain(with_newline, "v4.30.0")
            releases_mod.rewrite_lean_toolchain(without_newline, "v4.30.0")

            self.assertEqual(with_newline.read_text(encoding="utf-8"), "leanprover/lean4:v4.30.0\n")
            self.assertEqual(without_newline.read_text(encoding="utf-8"), "leanprover/lean4:v4.30.0")


if __name__ == "__main__":
    unittest.main()
