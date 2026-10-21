#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
meike_base="${1:-/MeiKe-web/}"
if [[ ! "$meike_base" =~ ^/([A-Za-z0-9_-]+/)*$ ]]; then
  echo 'Site path must start/end with / and contain only repository-name segments.' >&2
  exit 1
fi
"${MEIKE_FLUTTER:-flutter}" build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run --base-href="$meike_base"
node tool/pwa/finalize.mjs
