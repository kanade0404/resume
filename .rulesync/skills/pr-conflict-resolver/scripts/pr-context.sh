#!/usr/bin/env bash
# pr-context.sh - resolve a PR number into eval-able shell variable
# assignments (head/base branch, title, url, head SHA).
#
# Usage: pr-context.sh <pr-number>
# Requires: gh (authenticated), jq
#
# Output (stdout): one `NAME=value` assignment per line, each value shell-
# quoted with bash's `printf %q` so the whole output is safe to consume with
# `eval "$(bash pr-context.sh <n>)"` even if a title/branch contains spaces
# or quotes.
#
# Exported names:
#   PR_NUMBER   - the PR number, as returned by gh (validated integer)
#   PR_HEAD     - head branch name (what to check out / push back to)
#   PR_BASE     - base branch name (what to merge in)
#   PR_TITLE    - PR title (for status comments)
#   PR_URL      - PR URL (for status comments)
#   PR_HEAD_SHA - head branch's commit SHA at fetch time (drift/race check:
#                 compare against HEAD after checkout before pushing)
set -euo pipefail

# Best-effort external timeout: this runs unattended, so a network stall on
# `gh pr view` must not block the whole conflict-resolution workflow
# indefinitely. Prefer GNU coreutils `timeout`/`gtimeout` when present; fall
# back to running the command directly when neither exists (e.g. a bare
# macOS shell with no coreutils installed) rather than hard-failing every
# invocation on a missing dependency.
run_with_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  else
    "$@"
  fi
}

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <pr-number>" >&2
  exit 2
fi

pr="$1"

if ! [[ "$pr" =~ ^[0-9]+$ ]]; then
  echo "error: PR number must be a positive integer, got: '$pr'" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI not found on PATH" >&2
  exit 127
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq not found on PATH" >&2
  exit 127
fi

# Deliberately NOT `2>&1`: merging stderr into the captured JSON means any
# warning gh writes to stderr (deprecation notice, etc.) corrupts the value
# `jq` parses below, even when the PR lookup itself succeeded. Let stderr
# surface on its own; only stdout is captured as the JSON payload.
if ! json=$(run_with_timeout 30 gh pr view "$pr" --json number,headRefName,baseRefName,title,url,headRefOid); then
  echo "error: 'gh pr view $pr' failed (PR not found, no auth, no access, or timed out)" >&2
  exit 1
fi

pr_number=$(jq -r '.number' <<<"$json")
pr_head=$(jq -r '.headRefName' <<<"$json")
pr_base=$(jq -r '.baseRefName' <<<"$json")
pr_title=$(jq -r '.title' <<<"$json")
pr_url=$(jq -r '.url' <<<"$json")
pr_head_sha=$(jq -r '.headRefOid' <<<"$json")

if [ -z "$pr_head" ] || [ "$pr_head" = "null" ] || [ -z "$pr_base" ] || [ "$pr_base" = "null" ]; then
  echo "error: gh returned an incomplete PR record for #$pr (headRefName/baseRefName missing)" >&2
  exit 1
fi

printf 'PR_NUMBER=%q\n' "$pr_number"
printf 'PR_HEAD=%q\n' "$pr_head"
printf 'PR_BASE=%q\n' "$pr_base"
printf 'PR_TITLE=%q\n' "$pr_title"
printf 'PR_URL=%q\n' "$pr_url"
printf 'PR_HEAD_SHA=%q\n' "$pr_head_sha"
