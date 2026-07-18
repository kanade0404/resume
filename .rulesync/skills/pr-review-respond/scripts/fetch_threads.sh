#!/usr/bin/env bash
# Fetch unresolved review threads + general PR comments for a given PR.
# Outputs a single JSON document on stdout with normalized fields.
#
# Usage: fetch_threads.sh <pr-number>
# Requires: gh (authenticated), jq
#
# Output schema:
# {
#   "pr": { "number": int, "title": str, "url": str, "head_oid": str, "base": str },
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
#   "issue_comments": [           # PR-level (non-inline) comments
#     { "id": int, "author": str, "vendor": str, "body": str, "url": str, "created_at": str }
#   ]
# }
#
# Design notes:
# - Vendor detection is based on author login + body shape, not bot suffix.
#   - login starts with "coderabbit" → coderabbit
#   - login starts with "devin" or contains "devin-ai-integration" → devin
#   - everything else → human (safe default to avoid resolve-misfire)
# - is_resolved/is_outdated filtering is the caller's responsibility; this
#   script returns ALL threads so the caller can audit history if needed.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <pr-number>" >&2
  exit 2
fi

pr="$1"
owner=$(gh repo view --json owner --jq '.owner.login')
repo=$(gh repo view --json name --jq '.name')

# PR metadata
pr_meta=$(gh pr view "$pr" --json number,title,url,headRefOid,baseRefName \
  --jq '{number, title, url, head_oid: .headRefOid, base: .baseRefName}')

# Review threads (with cursor pagination)
threads_json='[]'
cursor=""
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
  threads_json=$(jq -c --argjson r "$resp" '. + $r.data.repository.pullRequest.reviewThreads.nodes' <<<"$threads_json")
  hasNext=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' <<<"$resp")
  cursor=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor // empty' <<<"$resp")
  pr_author=$(jq -r '.data.repository.pullRequest.author.login // ""' <<<"$resp")
  [ "$hasNext" = "true" ] || break
done

# General (issue-level) comments — coderabbit summary, devin overview, etc.
issue_comments=$(gh api --paginate "repos/$owner/$repo/issues/$pr/comments" \
  --jq '[.[] | {id, author: .user.login, body, url: .html_url, created_at}]' \
  | jq -s 'add // []')

vendor_filter='
def vendor(login):
  (login // "" | ascii_downcase) as $l
  | if   ($l | startswith("coderabbit")) then "coderabbit"
    elif ($l | startswith("devin")) or ($l | contains("devin-ai")) then "devin"
    else "human" end;
'

normalized=$(jq -n \
  --argjson meta "$pr_meta" \
  --argjson threads "$threads_json" \
  --argjson issue_comments "$issue_comments" \
  --arg pr_author "${pr_author:-}" \
  "$vendor_filter"'
{
  pr: $meta,
  threads: [
    $threads[]
    | . as $t
    | ($t.comments.nodes[0]) as $root
    | {
        thread_id: $t.id,
        is_resolved: $t.isResolved,
        is_outdated: $t.isOutdated,
        root_comment: {
          id: $root.databaseId,
          author: $root.author.login,
          vendor: vendor($root.author.login),
          path: $root.path,
          line: $root.line,
          start_line: $root.startLine,
          original_line: $root.originalLine,
          body: $root.body,
          url: $root.url,
          created_at: $root.createdAt
        },
        self_replied: ([$t.comments.nodes[1:][] | select(.author.login == $pr_author)] | length > 0)
      }
  ],
  issue_comments: [
    $issue_comments[]
    | . + { vendor: vendor(.author) }
  ]
}
'
)

echo "$normalized"
