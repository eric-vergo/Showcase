"""Retired 2026-07-04 (Stage 1 of the clean-card redesign).

The GROUP header chip (``.bp_extra_slot_group`` + ``.bp_relation_chip``) was
removed together with the other header extras (group / uses / used-by / L∃∀N):
the block heading is now title + status dot only, and per-decl relations are
owned by the metadata rail. The rail has no group section yet — when Stage 2
adds registry-backed rail sections, group coverage should be reintroduced as a
rail-based assertion.
"""

import pytest

pytestmark = pytest.mark.skip(
    reason="GROUP header chip removed (clean-card Stage 1); group info moves to the metadata rail"
)


class TestBlueprintGroupPreview:
    def test_retired(self):  # pragma: no cover - skipped module
        pass
