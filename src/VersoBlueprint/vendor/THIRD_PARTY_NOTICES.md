# Third-party notices — vendored graph runtime

This directory holds third-party JavaScript bundles that are embedded into the
VersoBlueprint binary (via `include_str` in `../PreviewManifest.lean`) and emitted into
every generated site under `-verso-data/lib/`. They are redistributed to site readers, so
their license notices ship with the site: the `{licenseInfo}` block renders them from
`d3LicenseInfo` / `d3GraphvizLicenseInfo` (`../PreviewManifest.lean`).

Machine-readable provenance — upstream URL, version, acquisition command, SHA-256, SPDX id,
and a `verified` block distinguishing bundle-verified from upstream-declared facts — is in
[`vendor-manifest.json`](./vendor-manifest.json). `tests/harness/test_vendor_provenance.py`
recomputes each bundle's SHA-256 and fails if the bytes and the manifest ever diverge.

| file | component | version | SPDX | SHA-256 (prefix) |
|------|-----------|---------|------|------------------|
| `d3.min.js` | d3 | 7.9.0 (from bundle banner) | ISC | `f2094bbf…` |
| `d3-graphviz.min.js` | d3-graphviz | 5.x (not stamped in bundle) | BSD-3-Clause | `9c1ecd14…` |

## d3 — ISC License

Copyright 2010-2023 Mike Bostock

Permission to use, copy, modify, and/or distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright notice
and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
THIS SOFTWARE.

## d3-graphviz — BSD 3-Clause License

Copyright (c) 2018-2023, Magnus Jacobsson
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
