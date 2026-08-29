#!/usr/bin/env bash
# Off-origin asset gates over a generated blueprint site.
#
# The published site must load nothing from another origin: no CDN scripts, no
# remote stylesheets, fonts, images or module imports. Only ASSET positions are
# matched -- outbound <a href="https://..."> links are the point of a blueprint
# and stay allowed. The regexes are a362583's publish-job gates verbatim, kept in
# one script so the packaging step (ci/scripts/package_site.sh, run in the
# site-generate job) and the Pages deploy workflow
# (.github/workflows/blueprint-deploy.yml) refuse the same trees.
#
# NB: `if grep ...; then exit 1; fi` rather than `! grep ...`. Under `set -e`, a
# non-final `!`-inverted command that "fails" (grep found a match) is exempt from
# -e and does NOT abort, so a `! grep` gate that is not the last statement
# silently false-passes.
#
# Usage: ci/scripts/site_offline_gates.sh <html-multi directory>
set -euo pipefail

root="${1:?usage: site_offline_gates.sh <html-multi directory>}"
[ -d "$root" ] || { echo "off-origin: $root is not a directory"; exit 1; }

fail_on() {  # fail_on <what> <extended regex>
  if grep -RIEl "$2" "$root"; then
    echo "off-origin: $1 found in the generated site"
    exit 1
  fi
}

fail_on "jsdelivr reference(s)" "jsdelivr"
fail_on "external <script src>/<link href>" "<(script[^>]*[[:space:]]src|link[^>]*[[:space:]]href)=[\"']https?://"
fail_on "external media src" "<(img|iframe|embed|source|video|audio|track|object)[^>]*[[:space:]]src=[\"']https?://"
fail_on "external CSS url()" "url\([[:space:]]*[\"']?https?://"
fail_on "external CSS @import" "@import[[:space:]]+(url\()?[[:space:]]*[\"']?https?://"
fail_on "off-origin fetch()/dynamic import()" "(fetch|import)\([[:space:]]*[\"']https?://"
fail_on "off-origin ES module import" "(^|[^A-Za-z0-9_])(import|export)[^\"']*[[:space:]]from[[:space:]]*[\"']https?://"
fail_on "protocol-relative asset reference" "[[:space:]](src|srcset)=[\"']//|<link[^>]*[[:space:]]href=[\"']//"

echo "off-origin: clean ($root)"
