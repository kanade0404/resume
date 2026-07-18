#!/usr/bin/env bash
# Post a reply to a pull-request review-thread comment using the correct
# /replies endpoint.
#
# Usage:
#   reply_thread.sh <pr-number> <root-comment-id> <body-file>
#
# The endpoint is:
#   POST /repos/{owner}/{repo}/pulls/{pr}/comments/{comment_id}/replies
# (replies-to-replies are NOT supported by the API — comment_id must be a
#  top-level review comment.)
#
# Body is read from a file to avoid shell-quoting issues with multi-line text.
# stdout: created comment URL (so caller can record it in the response log).

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <pr-number> <root-comment-id> <body-file>" >&2
  exit 2
fi

pr="$1"
comment_id="$2"
body_file="$3"

if [ ! -f "$body_file" ]; then
  echo "error: body file not found: $body_file" >&2
  exit 2
fi

owner=$(gh repo view --json owner --jq '.owner.login')
repo=$(gh repo view --json name --jq '.name')

body=$(cat "$body_file")

resp=$(gh api -X POST \
  -H "Accept: application/vnd.github+json" \
  "repos/$owner/$repo/pulls/$pr/comments/$comment_id/replies" \
  -f body="$body")

jq -r '.html_url' <<<"$resp"
