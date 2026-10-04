#!/usr/bin/env bash
# Fetch ALL review feedback for a given PR and emit one normalized JSON doc.
#
# Three sources, all required — reading only one of them is how findings get
# missed (observed: only Devin's 2 inline comments were picked up while
# CodeRabbit's "Outside diff range" findings lived in the review body):
#   1. inline review threads        (GraphQL reviewThreads)
#   2. review bodies                (REST pulls/{n}/reviews — CodeRabbit puts
#                                    "Outside diff range" / "Nitpick" /
#                                    "Additional" / "Duplicate" comments in
#                                    collapsed <details> here; Devin and humans
#                                    may also write findings only here)
#   3. PR conversation comments     (REST issues/{n}/comments — walkthroughs,
#                                    summaries, free-form findings)
#
# Usage: fetch_threads.sh <pr-number>      (normally via `prr [-R owner/repo] fetch`)
# Requires: gh (authenticated), jq
#
# Repository: GH_REPO (set by `prr -R owner/repo`) or the current directory's
# repository — see lib_repo.sh. The resolved repository is printed on stderr.
# Exits non-zero (stderr says why) when the PR does not exist in that
# repository or belongs to another one, instead of emitting an empty document.
#
# Output schema:
# {
#   "pr": { "number": int, "title": str, "url": str, "head_oid": str, "base": str,
#           "repo": "owner/repo" (base repository), "head_repo": "owner/repo" | null },
#   "threads": [
#     {
#       "thread_id": str,        # GraphQL node id
#       "is_resolved": bool,
#       "is_outdated": bool,
#       "root_comment": {
#         "id": int,             # databaseId, used for replies
#         "author": str,         # login
#         "vendor": "coderabbit" | "devin" | "human",
#         "path": str | null,
#         "line": int | null,
#         "start_line": int | null,
#         "original_line": int | null,
#         "body": str,
#         "url": str,
#         "created_at": str
#       },
#       "self_replied": bool     # true if any subsequent comment in thread is by the PR author
#     }
#   ],
#   "review_bodies": [            # submitted reviews with a non-blank body (PENDING excluded)
#     {
#       "id": int, "author": str, "vendor": str,
#       "state": "COMMENTED" | "APPROVED" | "CHANGES_REQUESTED" | "DISMISSED",
#       "body": str,             # full body, ALWAYS kept verbatim
#       "submitted_at": str, "url": str, "commit_id": str,
#       "embedded_findings": [   # best-effort split of CodeRabbit <details> sections;
#         {                      # [] when the body does not follow that layout
#           "category": "outside_diff_range" | "nitpick" | "additional" | "duplicate",
#           "path": str, "start_line": int, "end_line": int,
#           "title": str, "body": str
#         }
#       ]
#     }
#   ],
#   "issue_comments": [           # PR-level (non-inline) comments, full body kept
#     { "id": int, "author": str, "vendor": str, "body": str, "url": str, "created_at": str }
#   ],
#   "counts": {                   # report these per source — never just "N comments"
#     "threads": int, "unresolved_threads": int,
#     "eligible_threads": int,   # unresolved ∧ ¬outdated ∧ ¬self_replied (= Phase A triage target)
#     "skipped_threads": int,    # unresolved but outdated or self_replied
#     "review_bodies": int, "embedded_findings": int, "issue_comments": int
#   }
# }
#
# Design notes:
# - Vendor detection is based on author login, not bot suffix.
#   - login starts with "coderabbit" → coderabbit
#   - login starts with "devin" or contains "devin-ai" → devin
#   - everything else → human (safe default to avoid resolve-misfire)
# - is_resolved/is_outdated filtering is the caller's responsibility; this
#   script returns ALL threads so the caller can audit history if needed.
# - The pure normalization lives in normalize_fetch.jq so it can be tested
#   against fixtures without network access.

set -euo pipefail

# 直接実行にも耐えるよう、dispatcher (prr) 頼みにせず自前でも色強制を無効化する
export NO_COLOR=1
export CLICOLOR_FORCE=0
unset GH_FORCE_TTY
export GH_PAGER=cat

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <pr-number>" >&2
  exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=lib_repo.sh
. "$SCRIPT_DIR/lib_repo.sh"
pr="$1"
prr_resolve_repo

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

wrong_repo_hint() {
  if [ "$repo_source" = "cwd" ]; then
    echo "hint: the repository was taken from the current directory; if the PR lives elsewhere, run 'prr -R owner/repo fetch $pr'" >&2
  fi
}

# PR metadata. This also proves the PR exists in the resolved repository —
# a missing PR must be an error, never an empty (= "no findings") document.
if ! gh pr view "$pr" -R "$GH_REPO" \
  --json number,title,url,headRefOid,baseRefName,headRepository,headRepositoryOwner \
  >"$tmp/pr.json" 2>"$tmp/pr.err"; then
  echo "error: PR #$pr not found in $owner/$repo (source: $repo_source): $(tr '\n' ' ' <"$tmp/pr.err")" >&2
  wrong_repo_hint
  exit 1
fi
jq '{
    number, title, url, head_oid: .headRefOid, base: .baseRefName,
    repo: (.url | capture("^https?://[^/]+/(?<o>[^/]+)/(?<r>[^/]+)/pull/") | "\(.o)/\(.r)"),
    head_repo: (if .headRepositoryOwner.login and .headRepository.name
                then "\(.headRepositoryOwner.login)/\(.headRepository.name)" else null end)
  }' "$tmp/pr.json" >"$tmp/meta.json"
# The PR must belong to the resolved repository (as its base, or as the head
# of a same-repo PR). Anything else means we are about to read another
# repository's threads under this PR's name.
target=$(printf '%s/%s' "$owner" "$repo" | tr '[:upper:]' '[:lower:]')
if ! jq -e --arg t "$target" \
  '[.repo, .head_repo] | map(select(. != null) | ascii_downcase) | index($t) != null' \
  "$tmp/meta.json" >/dev/null; then
  echo "error: PR #$pr resolved to $(jq -r '.url' "$tmp/meta.json"), which is not in $owner/$repo (source: $repo_source)" >&2
  wrong_repo_hint
  exit 1
fi

# Review threads (with cursor pagination)
threads_json='[]'
cursor=""
pr_author=""
while :; do
  args=(-F owner="$owner" -F repo="$repo" -F pr="$pr")
  if [ -n "$cursor" ]; then
    args+=(-F cursor="$cursor")
  fi
  resp=$(gh api graphql "${args[@]}" -f query='query($owner:String!, $repo:String!, $pr:Int!, $cursor:String) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        author { login }
        reviewThreads(first:100, after:$cursor) {
          pageInfo { hasNextPage endCursor }
          nodes {
            id
            isResolved
            isOutdated
            comments(first:50) {
              nodes {
                databaseId
                body
                path
                line
                startLine
                originalLine
                url
                createdAt
                author { login }
              }
            }
          }
        }
      }
    }
  }')
  if ! jq -e '.data.repository.pullRequest != null' >/dev/null <<<"$resp"; then
    echo "error: GraphQL returned no pull request #$pr for $owner/$repo: $(jq -c '.errors // empty' <<<"$resp" 2>/dev/null)" >&2
    exit 1
  fi
  threads_json=$(jq -c --argjson r "$resp" '. + $r.data.repository.pullRequest.reviewThreads.nodes' <<<"$threads_json")
  hasNext=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' <<<"$resp")
  cursor=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor // empty' <<<"$resp")
  pr_author=$(jq -r '.data.repository.pullRequest.author.login // ""' <<<"$resp")
  [ "$hasNext" = "true" ] || break
done
printf '%s\n' "$threads_json" >"$tmp/threads.json"

# Review bodies — CodeRabbit "Outside diff range" / "Nitpick" etc. live ONLY here.
gh api --paginate "repos/$owner/$repo/pulls/$pr/reviews" \
  | jq -s 'add // []' >"$tmp/reviews.json"

# General (issue-level) comments — coderabbit summary, devin overview, etc.
gh api --paginate "repos/$owner/$repo/issues/$pr/comments" \
  | jq -s 'add // []' >"$tmp/issue_comments.json"

jq -n -f "$SCRIPT_DIR/normalize_fetch.jq" \
  --slurpfile meta "$tmp/meta.json" \
  --slurpfile threads "$tmp/threads.json" \
  --slurpfile reviews "$tmp/reviews.json" \
  --slurpfile issue_comments "$tmp/issue_comments.json" \
  --arg pr_author "$pr_author"
