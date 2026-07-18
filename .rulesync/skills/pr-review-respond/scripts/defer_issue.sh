#!/usr/bin/env bash
# Create a follow-up issue for a VALID_DEFER review-thread classification.
#
# Usage:
#   defer_issue.sh <pr-number> <thread-url> <title> <body-file>
#
# body-file should contain the caller's own summary of the finding plus the
# 1-line reason it's out of scope for this PR. This script appends a fixed
# footer linking back to the PR and the original review thread, so a
# `Tracked in #<issue>` reply is always traceable to its source even if the
# caller forgets to include the link.
#
# stdout: "<issue-number> <issue-url>"

set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: $0 <pr-number> <thread-url> <title> <body-file>" >&2
  exit 2
fi

pr="$1"
thread_url="$2"
title="$3"
body_file="$4"

if [ ! -f "$body_file" ]; then
  echo "error: body file not found: $body_file" >&2
  exit 2
fi

owner=$(gh repo view --json owner --jq '.owner.login')
repo=$(gh repo view --json name --jq '.name')
pr_url=$(gh pr view "$pr" --json url --jq '.url')

# Retry-safe: a prior invocation for this exact thread may have already
# created the follow-up issue (e.g. this step succeeded but a later step in
# the caller's flow failed and the whole defer sequence got re-run). Search
# existing issues (any state) whose body already contains this thread_url
# before creating a new one, so retries don't leave duplicate tracking
# issues behind. This is best-effort: GitHub's search index can lag a few
# seconds behind issue creation, so an immediate retry could still race it.
search_json=$(gh search issues --repo "$owner/$repo" --match body "$thread_url" \
  --json number,url,body --limit 10)
existing=$(jq -r --arg url "$thread_url" \
  '[.[] | select(.body | contains($url))][0] | if . == null then "" else "\(.number) \(.url)" end' \
  <<<"$search_json")

if [ -n "$existing" ]; then
  echo "$existing"
  exit 0
fi

body=$(cat "$body_file")
full_body=$(printf '%s\n\nDeferred from PR %s review thread: %s\n' "$body" "$pr_url" "$thread_url")

resp=$(gh api -X POST \
  -H "Accept: application/vnd.github+json" \
  "repos/$owner/$repo/issues" \
  -f title="$title" \
  -f body="$full_body")

jq -r '"\(.number) \(.html_url)"' <<<"$resp"
