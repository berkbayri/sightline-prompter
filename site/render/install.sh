#!/usr/bin/env bash
# Copies the renders from render-all.py's output folder into site/assets: every loop the page plays (video/<code>/)
# and the distance scene frames (img/dist/<code>/). Usage: site/render/install.sh /tmp/claude-502/r7/all
set -euo pipefail
A="$1"; shift
LOCALES="${*:-en tr de es fr it pt-br ja ko zh-hans zh-hant}"
cd "$(dirname "$0")/../assets"
for l in $LOCALES; do
  mkdir -p "img/dist/$l" "video/$l"
  for f in "$A/$l"-dist-*.webp; do cp "$f" "img/dist/$l/${f##*-dist-}"; done
  cp "$A/video/$l/"*.mp4 "$A/video/$l/"*.webm "$A/video/$l/"*-poster.webp "video/$l/"
done
# English is also the root fallback.
cp video/en/*.mp4 video/en/*.webm video/en/*-poster.webp video/
find video -name '*.json' -delete
echo installed
