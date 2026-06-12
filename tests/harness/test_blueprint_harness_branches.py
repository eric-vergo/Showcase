from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import scripts.blueprint_harness_branches as branches_mod


class BlueprintHarnessBranchPolicyTests(unittest.TestCase):
    def write(self, path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def git(self, root: Path, *args: str) -> str:
        return subprocess.run(
            ["git", *args],
            cwd=root,
            check=True,
            text=True,
            capture_output=True,
        ).stdout.strip()

    def test_load_branch_policy_reads_default_dev_branch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root / "branch-policy.json", '{\n  "version": 1,\n  "default_dev_branch": "4.29.0"\n}\n')

            policy = branches_mod.load_branch_policy(root)

            self.assertEqual(policy.version, 1)
            self.assertEqual(policy.default_dev_branch, "v4.29.0")
            self.assertEqual(policy.required_backport_branches, ())
            self.assertEqual(policy.source_path, root / "branch-policy.json")

    def test_active_release_branch_uses_release_id_for_release_candidate_toolchain(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root / "lean-toolchain", "leanprover/lean4:v4.30.0-rc2\n")

            self.assertEqual(branches_mod.active_release_branch(root), "v4.30.0")

    def test_load_branch_policy_reads_required_backport_branches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(
                root / "branch-policy.json",
                '{\n  "version": 1,\n  "default_dev_branch": "v4.29.0",\n  "required_backport_branches": ["4.28.0"]\n}\n',
            )

            policy = branches_mod.load_branch_policy(root)

            self.assertEqual(policy.required_backport_branches, ("v4.28.0",))

    def test_load_branch_policy_reads_release_targets(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(
                root / "branch-policy.json",
                json.dumps(
                    {
                        "version": 2,
                        "default_dev_branch": "v4.30.0",
                        "required_backport_branches": ["v4.29.0"],
                        "release_targets": [
                            {
                                "id": "v4.29.0",
                                "toolchain": "v4.29.0",
                                "verso_ref": "v4.29.0",
                                "branch": "v4.29.0",
                                "deploy_pages": True,
                            },
                            {
                                "id": "v4.30.0",
                                "toolchain": "v4.30.0",
                                "verso_ref": "v4.30.0",
                                "branch": "v4.30.0",
                                "deploy_pages": True,
                            },
                        ],
                    }
                ),
            )

            policy = branches_mod.load_branch_policy(root)

            self.assertEqual(policy.version, 2)
            self.assertEqual([target.release_id for target in policy.release_targets], ["v4.29.0", "v4.30.0"])
            self.assertEqual(policy.release_targets[1].toolchain, "v4.30.0")

    def test_load_branch_policy_rejects_release_target_rc(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(
                root / "branch-policy.json",
                json.dumps(
                    {
                        "version": 2,
                        "default_dev_branch": "v4.30.0",
                        "release_targets": [
                            {
                                "id": "v4.30.0",
                                "toolchain": "v4.30.0",
                                "verso_ref": "v4.30.0",
                                "rc": "4.30-rc2",
                                "branch": "v4.30.0",
                                "deploy_pages": True,
                            }
                        ],
                    }
                ),
            )

            with self.assertRaisesRegex(SystemExit, "`rc` belongs on project targets"):
                branches_mod.load_branch_policy(root)

    def test_resolve_git_ref_prefers_branch_over_same_named_tag(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.git(root, "init")
            self.git(root, "config", "user.name", "Test User")
            self.git(root, "config", "user.email", "test@example.com")
            self.git(root, "config", "commit.gpgsign", "false")
            self.write(root / "file.txt", "base\n")
            self.git(root, "add", "file.txt")
            self.git(root, "commit", "-m", "base")
            self.git(root, "tag", "v4.28.0")
            self.write(root / "file.txt", "branch\n")
            self.git(root, "commit", "-am", "branch")
            self.git(root, "branch", "v4.28.0")
            self.git(root, "update-ref", "refs/remotes/origin/v4.28.0", "HEAD")

            self.assertEqual(branches_mod.resolve_git_ref(root, "v4.28.0"), "refs/heads/v4.28.0")
            self.assertEqual(branches_mod.resolve_git_ref(root, "origin/v4.28.0"), "refs/remotes/origin/v4.28.0")

    def test_write_branch_policy_normalizes_release_refs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            policy = branches_mod.write_branch_policy(
                root,
                default_dev_branch="4.30-rc2",
                required_backport_branches=["4.29.0", "leanprover/lean4:v4.28.0"],
            )

            self.assertEqual(policy.default_dev_branch, "v4.30.0")
            self.assertEqual(policy.required_backport_branches, ("v4.29.0", "v4.28.0"))
            self.assertEqual(
                (root / "branch-policy.json").read_text(encoding="utf-8"),
                '{\n  "version": 1,\n  "default_dev_branch": "v4.30.0",\n  "required_backport_branches": [\n    "v4.29.0",\n    "v4.28.0"\n  ]\n}\n',
            )

    def test_load_branch_policy_falls_back_to_active_release_branch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root / "lean-toolchain", "leanprover/lean4:v4.29.0\n")

            policy = branches_mod.load_branch_policy(root)

            self.assertEqual(policy.default_dev_branch, "v4.29.0")

    def test_checkout_branch_role_reports_default_dev_when_policy_matches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root / "lean-toolchain", "leanprover/lean4:v4.29.0\n")
            self.write(root / "branch-policy.json", '{\n  "version": 1,\n  "default_dev_branch": "v4.29.0"\n}\n')

            self.assertEqual(branches_mod.checkout_branch_role(root), "default_dev")
            self.assertFalse(branches_mod.checkout_is_backport_only(root))

    def test_checkout_branch_role_reports_backport_when_policy_differs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root / "lean-toolchain", "leanprover/lean4:v4.28.0\n")
            self.write(root / "branch-policy.json", '{\n  "version": 1,\n  "default_dev_branch": "v4.29.0"\n}\n')

            self.assertEqual(branches_mod.checkout_branch_role(root), "backport")
            self.assertTrue(branches_mod.checkout_is_backport_only(root))

    def test_require_checkout_role_rejects_backport_for_default_dev_only_operation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.write(root / "lean-toolchain", "leanprover/lean4:v4.28.0\n")
            self.write(root / "branch-policy.json", '{\n  "version": 1,\n  "default_dev_branch": "v4.29.0"\n}\n')

            with self.assertRaisesRegex(SystemExit, "refusing to run `bump-toolchain` from backport-only checkout `v4.28.0`"):
                branches_mod.require_checkout_role(root, required_role="default_dev", operation="bump-toolchain")

    def test_preferred_release_ref_falls_back_to_remote_head_before_main_master(self) -> None:
        originals = {
            "active_release_branch": branches_mod.active_release_branch,
            "ref_exists": branches_mod.ref_exists,
            "remote_head_ref": branches_mod.remote_head_ref,
        }
        try:
            branches_mod.active_release_branch = lambda _repo_root: "v4.30.0"
            branches_mod.remote_head_ref = lambda _repo_root: "origin/v4.29.0"
            branches_mod.ref_exists = lambda _repo_root, ref: ref == "refs/remotes/origin/v4.29.0"

            self.assertEqual(branches_mod.preferred_release_ref(Path("/tmp/repo")), "origin/v4.29.0")
        finally:
            for name, value in originals.items():
                setattr(branches_mod, name, value)

    def test_local_release_ref_uses_local_branch_matching_remote_head(self) -> None:
        originals = {
            "active_release_branch": branches_mod.active_release_branch,
            "ref_exists": branches_mod.ref_exists,
            "remote_head_ref": branches_mod.remote_head_ref,
        }
        try:
            branches_mod.active_release_branch = lambda _repo_root: "v4.30.0"
            branches_mod.remote_head_ref = lambda _repo_root: "origin/v4.29.0"
            branches_mod.ref_exists = lambda _repo_root, ref: ref == "refs/heads/v4.29.0"

            self.assertEqual(branches_mod.local_release_ref(Path("/tmp/repo")), "v4.29.0")
        finally:
            for name, value in originals.items():
                setattr(branches_mod, name, value)


if __name__ == "__main__":
    unittest.main()
