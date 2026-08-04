"""Provenance/checksum guard for vendored third-party bundles (CX-028).

The graph-runtime bundles under src/VersoBlueprint/vendor/ are embedded into the
VersoBlueprint binary and redistributed in every generated site. Their provenance —
upstream URL, version, acquisition, SHA-256, SPDX id, and required notice — is tracked in
vendor-manifest.json. This test makes the bytes and the manifest inseparable: if a vendored
bundle changes without its manifest entry (and thus its notice) being updated, the recomputed
SHA-256 no longer matches and this fails. It also checks that every manifest entry has a
rendered LicenseInfo in PreviewManifest.lean and a notice in THIRD_PARTY_NOTICES.md.
"""

from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path


PACKAGE_ROOT = Path(__file__).resolve().parents[2]
VENDOR_DIR = PACKAGE_ROOT / "src" / "VersoBlueprint" / "vendor"
MANIFEST = VENDOR_DIR / "vendor-manifest.json"
NOTICES = VENDOR_DIR / "THIRD_PARTY_NOTICES.md"
PREVIEW_MANIFEST = PACKAGE_ROOT / "src" / "VersoBlueprint" / "PreviewManifest.lean"

_REQUIRED_FIELDS = {
    "file", "component", "upstream_url", "version", "spdx_license_id",
    "copyright", "acquisition", "sha256", "bytes",
}


def _entries() -> list[dict]:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    return data["vendored"]


class VendorProvenanceTests(unittest.TestCase):
    def test_manifest_and_notices_exist(self) -> None:
        self.assertTrue(MANIFEST.exists(), "vendor-manifest.json is missing")
        self.assertTrue(NOTICES.exists(), "THIRD_PARTY_NOTICES.md is missing")

    def test_every_vendored_bundle_has_a_manifest_entry(self) -> None:
        tracked = {p.name for p in VENDOR_DIR.glob("*.js")}
        described = {entry["file"] for entry in _entries()}
        self.assertEqual(
            tracked,
            described,
            f"vendored *.js files {sorted(tracked)} and manifest entries "
            f"{sorted(described)} disagree; every redistributed bundle needs provenance",
        )

    def test_sha256_and_size_match_the_bytes(self) -> None:
        for entry in _entries():
            path = VENDOR_DIR / entry["file"]
            self.assertTrue(path.exists(), f"missing vendored bundle: {entry['file']}")
            raw = path.read_bytes()
            actual = hashlib.sha256(raw).hexdigest()
            self.assertEqual(
                actual,
                entry["sha256"],
                f"{entry['file']}: SHA-256 diverged from the manifest. If the vendored bytes "
                f"changed intentionally, update sha256/bytes/version and the license notice.",
            )
            self.assertEqual(len(raw), entry["bytes"], f"{entry['file']}: byte count diverged")

    def test_entries_carry_required_provenance_fields(self) -> None:
        for entry in _entries():
            missing = _REQUIRED_FIELDS - set(entry)
            self.assertEqual(missing, set(), f"{entry.get('file')}: missing provenance fields {missing}")

    def test_each_component_has_a_rendered_licenseinfo_and_notice(self) -> None:
        preview = PREVIEW_MANIFEST.read_text(encoding="utf-8")
        notices = NOTICES.read_text(encoding="utf-8")
        for entry in _entries():
            component = entry["component"]
            spdx = entry["spdx_license_id"]
            # A LicenseInfo value in PreviewManifest names the component and its SPDX id.
            self.assertIn(
                f'dependency := "{component}"',
                preview,
                f"no LicenseInfo `dependency := \"{component}\"` in PreviewManifest.lean",
            )
            self.assertIn(f'identifier := "{spdx}"', preview, f"no `identifier := \"{spdx}\"` for {component}")
            self.assertIn(component, notices, f"{component} missing from THIRD_PARTY_NOTICES.md")


if __name__ == "__main__":
    unittest.main()
