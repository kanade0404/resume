#!/bin/bash
set -e  # Exit on error

for f in *.md; do
  out="${f%.md}.pdf"
  echo "Generating $out"
  md-to-pdf "$f" \
    --stylesheet ./style.css \
    --pdf-options '{ "format": "A4", "printBackground": true }'
done
