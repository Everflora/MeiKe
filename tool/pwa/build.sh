#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
meike_base="${1:-/MeiKe-web/}"
if [[ ! "$meike_base" =~ ^/([A-Za-z0-9_-]+/)*$ ]]; then
  echo 'Site path must start/end with / and contain only repository-name segments.' >&2
  exit 1
fi
meike_options=(build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run "--base-href=$meike_base")
if [[ -n "${MEIKE_DISCUSSION_API:-}" ]]; then
  if [[ ! "$MEIKE_DISCUSSION_API" =~ ^https://[^[:space:]]+/$ || "$MEIKE_DISCUSSION_API" == *[@\?\#]* ]]; then
    echo 'Discussion API must be an HTTPS base URL ending in /, without credentials, query or fragment.' >&2
    exit 1
  fi
  meike_options+=("--dart-define=DISCUSSION_API=$MEIKE_DISCUSSION_API")
fi
"${MEIKE_FLUTTER:-flutter}" "${meike_options[@]}"
node tool/pwa/finalize.mjs
