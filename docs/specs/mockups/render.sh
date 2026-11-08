#!/usr/bin/env bash
# Renders every mockup in html/ to img/ (annotated) and img/clean/ (no callouts) with headless Chrome.
# Usage: bash docs/specs/mockups/render.sh [name-filter]
set -euo pipefail
cd "$(dirname "$0")"
CHROME="${CHROME:-/c/Program Files/Google/Chrome/Application/chrome.exe}"
mkdir -p img/clean
for f in html/*${1:-}*.html; do
  name="$(basename "$f" .html)"
  url="file:///$(cygpath -m "$PWD/$f")"
  for mode in annotated clean; do
    if [ "$mode" = clean ]; then out="img/clean/$name.png"; q="?clean"; else out="img/$name.png"; q=""; fi
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1280,820 \
      --virtual-time-budget=8000 --screenshot="$(cygpath -w "$PWD/$out")" "$url$q" >/dev/null 2>&1
    echo "rendered $out"
  done
done
python optimize_images.py img 2>/dev/null && echo "converted to webp in img/" || echo "Pillow not found: PNGs left as they are"
