from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
TEMPLATE_ROOT = PACKAGE_ROOT / "project_template"

# Lake surfaces an out-of-date lockfile as a warning and then keeps resolving against the locked
# graph (Lake/Load/Resolve.lean). For the distributed starter that is a silent-drift trust hole
# (CX-009): the committed manifest must already agree with the declared requires, so any of these
# markers means a fresh copy would resolve something other than the reviewed pins. A warning is
# not a trust boundary for a locked graph — treat it as a hard failure.
MANIFEST_DRIFT_MARKERS = (
    "manifest out of date",
    "manifest is out of date",
    "out-of-date manifest",
)

# The starter's `verso` / `subverso` must resolve to the eric-vergo forks (self-hosted `marked`,
# fork highlighting), never upstream — the exact substitution CX-009 caught in the stale manifest.
EXPECTED_FORK_ORIGINS = {
    "VersoBlueprint": "https://github.com/eric-vergo/Showcase.git",
    "verso": "https://github.com/eric-vergo/verso.git",
    "subverso": "https://github.com/eric-vergo/subverso.git",
}


def run_capture(command: list[str], *, cwd: Path) -> subprocess.CompletedProcess[str]:
    print(f"[project-template-fresh-repo] $ {shlex.join(command)}", flush=True)
    return subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def git_output(args: list[str], *, cwd: Path) -> str | None:
    if not (cwd / ".git").exists():
        return None
    result = subprocess.run(["git", *args], cwd=cwd, text=True, capture_output=True)
    return result.stdout.strip() if result.returncode == 0 else None


def committed_git_pins(manifest_path: Path) -> list[dict[str, str]]:
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    return [package for package in data["packages"] if package.get("type") == "git"]


def package_checkout_dir(packages_dir: Path, name: str) -> Path:
    # Lake stores Git packages under their name with the guillemet quoting stripped
    # (e.g. `«verso-slides»` → `verso-slides`).
    return packages_dir / name.strip("«»")


def fail_on_drift(output: str) -> None:
    drift = [marker for marker in MANIFEST_DRIFT_MARKERS if marker in output.lower()]
    if drift:
        raise SystemExit(
            "[project-template-fresh-repo] Lake reported manifest drift "
            f"{drift}; the committed lake-manifest.json does not agree with the declared "
            "requires. Regenerate it so a fresh copy resolves without `lake update`."
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Copy the UNMODIFIED project_template to a throwaway directory and resolve it with no "
            "`lake update`, exactly as a user who copies the folder receives it. Fails if Lake "
            "reports manifest drift, rewrites the committed manifest, or resolves any dependency "
            "to a revision/origin other than the committed pin (CX-009/010). With --build it also "
            "compiles the pinned dependency stack to prove the pins build standalone."
        ),
    )
    parser.add_argument(
        "--build",
        action="store_true",
        help=(
            "Additionally run `lake build VersoBlueprint` to compile the pinned dependency stack "
            "(verso + subverso + VersoBlueprint) from source. Slow (cold build); off by default so "
            "the resolution-integrity gate stays fast."
        ),
    )
    args = parser.parse_args()

    committed_manifest = TEMPLATE_ROOT / "lake-manifest.json"
    committed_manifest_bytes = committed_manifest.read_bytes()
    pins = committed_git_pins(committed_manifest)

    with tempfile.TemporaryDirectory(prefix="verso-blueprint-template-fresh-repo-") as tmp:
        fresh_root = Path(tmp) / "project-template"
        # Copy the artifact verbatim: no dependency rewrite, no `lake update`. The parent of
        # `fresh_root` is a throwaway temp directory, so a stray `from ".."` could not resolve to
        # the in-repo package — resolution must stand on the committed Git pins alone.
        shutil.copytree(TEMPLATE_ROOT, fresh_root)

        # Load the workspace with no update: this materializes every dependency and runs Lake's
        # manifest validation (which emits the drift warning if the lockfile disagrees).
        resolve = run_capture(["lake", "env", "true"], cwd=fresh_root)
        sys.stdout.write(resolve.stdout)
        sys.stdout.flush()
        fail_on_drift(resolve.stdout)
        if resolve.returncode != 0:
            raise SystemExit(
                f"[project-template-fresh-repo] fresh-copy dependency resolution failed "
                f"(exit {resolve.returncode})"
            )

        # Lake must not have rewritten the committed lockfile behind our back.
        if (fresh_root / "lake-manifest.json").read_bytes() != committed_manifest_bytes:
            raise SystemExit(
                "[project-template-fresh-repo] `lake env` rewrote the committed manifest; the "
                "template lockfile is not stable on a plain load."
            )

        packages_dir = fresh_root / ".lake" / "packages"
        mismatches: list[str] = []
        for package in pins:
            name = package["name"]
            checkout = package_checkout_dir(packages_dir, name)
            head = git_output(["rev-parse", "HEAD"], cwd=checkout)
            origin = git_output(["remote", "get-url", "origin"], cwd=checkout)
            if head is None:
                mismatches.append(f"{name}: not resolved as a Git checkout at {checkout}")
                continue
            if head != package["rev"]:
                mismatches.append(f"{name}: resolved {head} but the committed pin is {package['rev']}")
            expected_origin = EXPECTED_FORK_ORIGINS.get(name)
            if expected_origin is not None and origin != expected_origin:
                mismatches.append(f"{name}: origin {origin} is not the expected {expected_origin}")
        if mismatches:
            raise SystemExit(
                "[project-template-fresh-repo] dependency resolution drifted from the committed pins:\n  "
                + "\n  ".join(mismatches)
            )

        print(
            "[project-template-fresh-repo] OK: fresh copy resolved from the committed pins with no "
            "manifest drift; VersoBlueprint/verso/subverso came from the eric-vergo forks at their "
            "pinned revisions and the committed manifest was left untouched."
        )

        if args.build:
            build = run_capture(["lake", "build", "VersoBlueprint"], cwd=fresh_root)
            sys.stdout.write(build.stdout)
            sys.stdout.flush()
            fail_on_drift(build.stdout)
            if build.returncode != 0:
                raise SystemExit(
                    f"[project-template-fresh-repo] pinned dependency build failed (exit {build.returncode})"
                )
            print("[project-template-fresh-repo] OK: the pinned dependency stack compiled standalone.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
