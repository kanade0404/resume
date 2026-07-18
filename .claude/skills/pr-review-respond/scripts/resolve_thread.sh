#!/usr/bin/env bash
# Mark a CodeRabbit review thread as resolved by posting a reply with the
# `@coderabbitai resolve` directive. The CodeRabbit bot listens for that
# directive and flips the thread state.
#
# Usage:
#   resolve_thread.sh <pr-number> <root-comment-id> <classification> [body-file]
#
# classification must be one of: VALID VALID_DEFER DUPLICATE.
#
# Guard: INVALID_PUSH is REJECTED (non-zero exit, no API call made). Resolving
# an INVALID_PUSH thread would tell the reviewer "fixed" when we actually
# pushed back — this guard makes that misuse fail loudly instead of relying
# on the caller to remember the rule (skills/pr-review-respond/SKILL.md
# Phase D).
#
# If body-file is omitted, the reply is just `@coderabbitai resolve`. When
# given, body-file content is concatenated BEFORE the directive line, so the
# caller can include "Fixed in <SHA>" / "Tracked in #N" etc.

set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "usage: $0 <pr-number> <root-comment-id> <classification> [body-file]" >&2
  exit 2
fi

pr="$1"
comment_id="$2"
classification="$3"
body_file="${4:-}"

case "$classification" in
  VALID|VALID_DEFER|DUPLICATE)
    ;;
  INVALID_PUSH)
    echo "error: refusing to resolve thread $comment_id on PR $pr: classification is INVALID_PUSH." >&2
    echo "       INVALID_PUSH threads must stay open (reply only, never resolve)." >&2
    exit 1
    ;;
  *)
    echo "error: unknown classification: $classification (expected VALID|VALID_DEFER|DUPLICATE|INVALID_PUSH)" >&2
    exit 2
    ;;
esac

owner=$(gh repo view --json owner --jq '.owner.login')
repo=$(gh repo view --json name --jq '.name')

prefix=""
if [ -n "$body_file" ]; then
  if [ ! -f "$body_file" ]; then
    echo "error: body file not found: $body_file" >&2
    exit 2
  fi
  prefix=$(cat "$body_file")
  prefix="${prefix}"$'\n\n'
fi

body="${prefix}@coderabbitai resolve"

resp=$(gh api -X POST \
  -H "Accept: application/vnd.github+json" \
  "repos/$owner/$repo/pulls/$pr/comments/$comment_id/replies" \
  -f body="$body")

jq -r '.html_url' <<<"$resp"
