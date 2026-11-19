#!/bin/bash
set -e  # Exit on error

LAUNCH_OPTS='{ "args": ["--no-sandbox", "--disable-setuid-sandbox"] }'
PDF_OPTS='{ "format": "A4", "printBackground": true }'

generate() {
  local src="$1"
  local title="$2"
  echo "Generating ${src%.md}.pdf (title: $title)"
  md-to-pdf "$src" \
    --stylesheet ./style.css \
    --pdf-options "$PDF_OPTS" \
    --launch-options "$LAUNCH_OPTS" \
    --document-title "$title"
}

# AGENTS.md など、経歴書以外の Markdown は PDF にしない
generate README.md "職務経歴書_坂田誠也"
generate detail.md "職務経歴書_坂田誠也_詳細"
