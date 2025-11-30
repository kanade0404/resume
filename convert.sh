#!/bin/bash
set -e  # Exit on error

LAUNCH_OPTS='{ "args": ["--no-sandbox", "--disable-setuid-sandbox"] }'

for f in *.md; do
  out="${f%.md}.pdf"
  echo "Generating $out"
  md-to-pdf "$f" \
    --stylesheet ./style.css \
    --pdf-options '{ "format": "A4", "printBackground": true }' \
    --launch-options "$LAUNCH_OPTS"
done
