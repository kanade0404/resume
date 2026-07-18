#!/usr/bin/env bash
# Post the aggregated Review Response Summary as a NEW issue-level comment on
# the PR. Always creates a new comment (never edits) so historical summaries
# remain visible.
#
# Usage: post_summary.sh <pr-number> <body-file>
# stdout: created comment URL.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <pr-number> <body-file>" >&2
  exit 2
fi

pr="$1"
body_file="$2"

if [ ! -f "$body_file" ]; then
  echo "error: body file not found: $body_file" >&2
  exit 2
fi

resp=$(gh pr comment "$pr" --body-file "$body_file")
# `gh pr comment` already prints the URL on success; relay it.
echo "$resp"
