#!/usr/bin/env bash
# Package a generated blueprint site into the tarball + pin the deploy gate reads.
#
# The verify workflow's site-generate job runs this against the tree it just
# generated. It refuses anything the deploy gate would refuse, so the refusal
# happens here, in seconds, instead of after a release was cut:
#
#   * the worktree must be clean, the site's own provenance record must not be
#     marked dirty (a site that describes no commit is not published), and the
#     revision it was generated from must be HEAD or an ancestor of HEAD -- the
#     registry's source links and the build stamp name that revision, and the
#     deploy gate holds every trust input at HEAD to what that generation read;
#   * the tree must fit GitHub Pages: refused over --max-bytes (900 MB by
#     default; the documented limit is 1 GB and deployments near it time out),
#     with a per-component size report written next to the tarball;
#   * the off-origin gates (ci/scripts/site_offline_gates.sh) must pass;
#   * the freshly written pin, the tarball and the tree must pass
#     ci/scripts/check_site_release.py exactly as the deploy workflow runs it.
#
# Extracted from eric-vergo/HopfProblem scripts/package_site.sh. Four changes:
#
#   * the site root, the pin path, the site package directory and the gate's
#     required-file list are arguments, not constants;
#   * `pins` records EVERY package in the site workspace's manifest rather than a
#     hardcoded four -- a pin that names four of eleven revisions describes a
#     build nobody can reproduce;
#   * the tarball is fully deterministic (`--sort=name --mtime=@0 --owner=0
#     --group=0 --numeric-owner --mode=go-w` on top of the already-sorted member
#     list and `gzip -n`), so its digest is a pure function of path + content +
#     mode. Without that, two runs of the same commit produce different bytes and
#     every run cuts a release;
#   * the pin is schemaVersion 2: it carries a `producer` block naming WHICH run
#     of WHICH CI code packaged the site. That block is REQUIRED, and it comes
#     from the environment -- packaging is a CI act under this standard, because
#     what Pages serves has to be what a run generated from a run's checkout. A
#     workstation invocation fails here rather than producing a pin the deploy
#     gate would refuse later.
#
# Environment (all required): WORKFLOW_REPOSITORY, WORKFLOW_REF, WORKFLOW_SHA,
# GITHUB_RUN_ID, GITHUB_SERVER_URL, GITHUB_REPOSITORY.
#
# Usage, from the repository root:
#   ci/scripts/package_site.sh --site-root site/_out/site/html-multi \
#                              --pin site/trust/site-build.json \
#                              --site-dir site \
#                              --out "$RUNNER_TEMP/site-release" \
#                              [--max-bytes 900000000] \
#                              [--min-files 50] \
#                              [--required-file index.html ...]
set -euo pipefail

site_root=""
pin=""
site_dir="site"
out=""
max_bytes=900000000
min_files=50
required_files=()

die() { echo "package_site: $*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --site-root) site_root="$2"; shift 2 ;;
    --pin) pin="$2"; shift 2 ;;
    --site-dir) site_dir="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --max-bytes) max_bytes="$2"; shift 2 ;;
    --min-files) min_files="$2"; shift 2 ;;
    --required-file) required_files+=("$2"); shift 2 ;;
    --required-file=*) required_files+=("${1#--required-file=}"); shift ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[ -n "$site_root" ] || die "--site-root is required"
[ -n "$pin" ] || die "--pin is required"

root="$(git rev-parse --show-toplevel)"
cd "$root"
out="${out:-$root/_site-release}"

for var in WORKFLOW_REPOSITORY WORKFLOW_REF WORKFLOW_SHA GITHUB_RUN_ID \
           GITHUB_SERVER_URL GITHUB_REPOSITORY; do
  eval "value=\${$var:-}"
  [ -n "$value" ] || die "\$$var is unset. The pin records WHICH run of WHICH CI code packaged this site, and the deploy gate requires it; packaging happens in the site-generate job of the reusable workflow, not on a workstation."
done

[ -d "$site_root" ] || die "$site_root does not exist -- generate the site first"
[ -f "$site_root/-verso-data/trust-provenance.json" ] || die "no trust-provenance.json under $site_root"

# The pin is the one file this script itself writes; a stale pin from an earlier
# packaging is not dirt. Anything else uncommitted is.
if [ -n "$(git status --porcelain --untracked-files=normal -- . ":!$pin")" ]; then
  git status --short -- . ":!$pin" >&2
  die "the worktree has uncommitted changes; commit or stash them, then regenerate if they touched the site"
fi

head="$(git rev-parse HEAD)"
read -r gen dirty < <(python3 - "$site_root/-verso-data/trust-provenance.json" <<'PY'
import json, sys
record = json.load(open(sys.argv[1], encoding="utf-8"))
build = record.get("buildRevision") or {}
print(build.get("commit", ""), "true" if build.get("dirty") else "false")
PY
)
[ "$dirty" = "false" ] || die "the site's provenance record is marked dirty -- regenerate from a clean worktree"
if [ "$gen" != "$head" ]; then
  git merge-base --is-ancestor "$gen" "$head" 2>/dev/null \
    || die "the site was generated at ${gen:-<none>}, which is not on the history of HEAD $head -- regenerate under HEAD"
  echo "package_site: the site was generated at ${gen:0:7}; HEAD is ${head:0:7} (the deploy gate re-hashes every trust input at HEAD against that generation)"
fi

# --- Size: one repository, one GitHub Pages site -------------------------------
mkdir -p "$out"
python3 - "$site_root" "$out/size-report.txt" "$max_bytes" <<'PY'
import os, sys
root, report, limit = sys.argv[1], sys.argv[2], int(sys.argv[3])
def tree(path):
    files = total = 0
    for dirpath, _d, names in os.walk(path):
        for n in names:
            files += 1; total += os.path.getsize(os.path.join(dirpath, n))
    return files, total
rows = []
whole = tree(root)
for label, rel in (("declaration pages (decl/)", "decl"), ("node pages (node/)", "node"),
                   ("-verso-data (registry, manifests, assets)", "-verso-data"),
                   ("xref.json", "xref.json")):
    p = os.path.join(root, rel)
    rows.append((label,) + (tree(p) if os.path.isdir(p) else ((1, os.path.getsize(p)) if os.path.isfile(p) else (0, 0))))
rest = (whole[0] - sum(r[1] for r in rows), whole[1] - sum(r[2] for r in rows))
rows.append(("everything else (chapters, index, PM, trust pages)",) + rest)
lines = ["site size report", "  {:52s} {:>7s} {:>10s}".format("component", "files", "MB")]
for label, files, total in rows:
    lines.append("  {:52s} {:7d} {:10.1f}".format(label, files, total / 1e6))
lines.append("  {:52s} {:7d} {:10.1f}".format("TOTAL", whole[0], whole[1] / 1e6))
decl = rows[0]
if decl[1]:
    lines.append("  mean declaration page: {:.1f} KB; headroom to the {:.0f} MB gate at that size: {:d} more page(s)".format(
        decl[2] / decl[1] / 1e3, limit / 1e6, max(0, int((limit - whole[1]) / (decl[2] / decl[1])))))
text = "\n".join(lines)
print(text)
open(report, "w", encoding="utf-8").write(text + "\n")
if whole[1] > limit:
    print("package_site: {} bytes exceeds the {} byte gate for one GitHub Pages site".format(whole[1], limit))
    sys.exit(1)
PY

bash "$(dirname "${BASH_SOURCE[0]}")/site_offline_gates.sh" "$site_root"

short="${gen:0:7}"
tag="site-$(date -u +%Y%m%d)-$short"
asset="site-$short.tar.gz"
mkdir -p "$out"
tarball="$out/$asset"
rm -f "$tarball"
# Deterministic in member order (find | sort), in metadata (--sort/--mtime/--owner/
# --group/--numeric-owner/--mode) and in the gzip header (-n). The digest is then a
# pure function of path + content + mode, so two runs of the same commit produce
# the same bytes and the release-unchanged skip below is meaningful.
site_parent="$(dirname "$site_root")"
site_leaf="$(basename "$site_root")"
( cd "$site_parent" && find "$site_leaf" -type f | LC_ALL=C sort \
    | tar -cf - --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --mode=go-w -T - \
    | gzip -n -6 > "$tarball" )

repository="$(git remote get-url origin | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')"

python3 - "$pin" "$tarball" "$site_root" "$gen" "$tag" "$asset" "$site_dir" <<'PY'
import datetime, hashlib, json, os, sys

pin, tarball, site_root, head, tag, asset, site_dir = sys.argv[1:8]

digest = hashlib.sha256()
with open(tarball, "rb") as handle:
    for chunk in iter(lambda: handle.read(1 << 20), b""):
        digest.update(chunk)

files = sum(len(names) for _, _, names in os.walk(site_root))

# EVERY package the site workspace resolved, not a hardcoded four: a pin that
# names four of eleven revisions describes a build nobody can reproduce.
manifest_path = os.path.join(site_dir, "lake-manifest.json")
with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)
pins = {}
for package in manifest.get("packages", []):
    name = package.get("name")
    if isinstance(name, str) and name:
        pins[name] = package.get("rev")
with open(os.path.join(site_dir, "lean-toolchain"), encoding="utf-8") as handle:
    pins["toolchain"] = handle.read().strip()

document = {
    "schemaVersion": 2,
    "generationRevision": head,
    "generatedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "release": {
        "tag": tag,
        "asset": asset,
        "sha256": digest.hexdigest(),
        "bytes": os.path.getsize(tarball),
        "files": files,
    },
    "pins": pins,
    "producer": {
        "workflow_repository": os.environ["WORKFLOW_REPOSITORY"],
        "workflow_ref": os.environ["WORKFLOW_REF"],
        "workflow_sha": os.environ["WORKFLOW_SHA"],
        "run_id": os.environ["GITHUB_RUN_ID"],
        "run_url": "{}/{}/actions/runs/{}".format(
            os.environ["GITHUB_SERVER_URL"],
            os.environ["GITHUB_REPOSITORY"],
            os.environ["GITHUB_RUN_ID"],
        ),
    },
}
os.makedirs(os.path.dirname(pin) or ".", exist_ok=True)
with open(pin, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2, sort_keys=True)
    handle.write("\n")
print("wrote {}: {} ({} bytes, {} files) generated at {}".format(
    pin, asset, document["release"]["bytes"], files, head[:7]))
PY

cp "$pin" "$out/site-build.json"
gate=("python3" "$(dirname "${BASH_SOURCE[0]}")/check_site_release.py"
      --pin "$pin" --tarball "$tarball" --site-root "$site_root"
      --repo-root "$root" --site-dir "$site_dir" --head "$head"
      --repository "$repository" --min-files "$min_files" --max-bytes "$max_bytes")
for f in ${required_files+"${required_files[@]}"}; do
  # `--required-file=VALUE`, never two tokens: a required path may start with `-`
  # (`-verso-data/blueprint-manifest.json`), and argparse reads a bare `-verso-data/...`
  # after `--required-file` as the next option ("expected one argument").
  gate+=("--required-file=$f")
done
"${gate[@]}"

echo "package_site: ${asset} is packaged and passes the deploy gate."
