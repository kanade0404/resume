#!/usr/bin/env bash
# Create a follow-up issue for a VALID_DEFER review-thread classification.
#
# Usage:
#   defer_issue.sh <pr-number> <thread-url> <title> <body-file>
#
# <thread-url> identifies ONE finding and doubles as the retry dedup key:
#   - inline thread:            https://github.com/o/r/pull/7#discussion_r123
#   - review body / comment:    <review-or-comment-url>#finding-<category>-<path>-<start>-<end>-<ordinal>
#     (a bare #pullrequestreview- / #issuecomment- URL is rejected, since all
#      findings in that review would share it)
#
# body-file should contain the caller's own summary of the finding plus the
# 1-line reason it's out of scope for this PR. This script appends a fixed
# footer linking back to the PR and the original review thread, so a
# `Tracked in #<issue>` reply is always traceable to its source even if the
# caller forgets to include the link.
#
# stdout: "<issue-number> <issue-url>"

set -euo pipefail

# 直接実行にも耐えるよう、dispatcher (prr) 頼みにせず自前でも色強制を無効化する
export NO_COLOR=1
export CLICOLOR_FORCE=0
unset GH_FORCE_TTY
export GH_PAGER=cat

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

# The source URL is also the dedup key (see the search below), so it must be
# unique per finding. An inline thread URL (#discussion_r<id>) is. A review
# URL (#pullrequestreview-<id>) or conversation comment URL (#issuecomment-<id>)
# is shared by every finding in that review / comment, so deferring two of
# them would hand the second finding the first one's issue. Those must carry
# a per-finding key: <url>#finding-<category>-<path>-<start>-<end>-<ordinal>.
case "$thread_url" in
  *"#finding-"*) ;;
  *"#pullrequestreview-"* | *"#issuecomment-"*)
    echo "error: $thread_url is shared by every finding in that review/comment." >&2
    echo "       Append a per-finding key: <url>#finding-<category>-<path>-<start>-<end>-<ordinal>" >&2
    exit 2
    ;;
esac

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=lib_repo.sh
. "$SCRIPT_DIR/lib_repo.sh"
prr_resolve_repo
pr_url=$(gh pr view "$pr" -R "$GH_REPO" --json url --jq '.url')

# Retry-safe: a prior invocation for this exact thread may have already
# created the follow-up issue (e.g. this step succeeded but a later step in
# the caller's flow failed and the whole defer sequence got re-run). Search
# existing issues (any state) whose body already contains this thread_url
# before creating a new one, so retries don't leave duplicate tracking
# issues behind. This is best-effort: GitHub's search index can lag a few
# seconds behind issue creation, so an immediate retry could still race it.
#
# Search is fuzzy and only produces candidates (queried with the URL minus the
# #finding- key, to stay well under the 256-char query limit). The match is
# exact on the footer line this script writes, so "...-1" never matches an
# issue for "...-10" and a bare review URL never matches a finding's issue.
# Every finding of one review shares that candidate query, so the candidate
# pool grows with the number of deferred findings in the review. Ask for the
# search API's ceiling (1000 results) instead of one page of 100, or an older
# finding's issue falls outside the page and a retry duplicates it.
search_json=$(gh search issues --repo "$owner/$repo" --match body "${thread_url%%#finding-*}" \
  --json number,url,body --limit 1000)
existing=$(jq -r --arg url "$thread_url" \
  '[.[] | select(.body // "" | split("\n") | map(rtrimstr("\r"))
                 | any(endswith(" review thread: " + $url)))][0]
   | if . == null then "" else "\(.number) \(.url)" end' \
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
