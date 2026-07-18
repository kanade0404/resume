#!/usr/bin/env bash
# Unattended fallback for Phase E: label the PR `needs-human` and post a
# structured escalation comment. Use this ONLY when there is no caller left
# to hand a WAITING verdict to (headless CI / scheduled run). In an
# interactive session or a subagent dispatched by another skill, return
# WAITING instead — see skills/pr-review-respond/SKILL.md Phase E.
#
# Usage:
#   escalate.sh <pr-number> <reason> <body-file>
#
# reason: one of budget-exceeded max-turns ci-3-fail review-5-rounds
#         no-progress ambiguous-issue repo-unresolvable conflict
#         security-block other
#         (same taxonomy as skills/issue-driven-development/SKILL.md, so
#         downstream tooling that greps for these reasons keeps working.)
#
# body-file: free-text situation summary, expected to end with the
#   loop-escalation:v1 marker and JSON block:
#     <!-- loop-escalation:v1 -->
#     {"reason": "...", "detail": "...", "attempts": <n>, ...}
#   This script does not construct that JSON itself — the caller fills in
#   attempts/session_id/next_action_hint because only the caller knows them.

set -euo pipefail

valid_reasons="budget-exceeded max-turns ci-3-fail review-5-rounds no-progress ambiguous-issue repo-unresolvable conflict security-block other"

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <pr-number> <reason> <body-file>" >&2
  exit 2
fi

pr="$1"
reason="$2"
body_file="$3"

case " $valid_reasons " in
  *" $reason "*)
    ;;
  *)
    echo "error: unknown reason: $reason (expected one of: $valid_reasons)" >&2
    exit 2
    ;;
esac

if [ ! -f "$body_file" ]; then
  echo "error: body file not found: $body_file" >&2
  exit 2
fi

# Post the escalation comment first. It is the only human-visible signal in
# an unattended run, so it must not be blocked by the label step:
# `needs-human` may not exist yet in every consumer repo, and under
# `set -e` a failing `gh pr edit --add-label` would previously abort before
# the comment was ever posted. Labeling is now best-effort and non-fatal —
# if it fails (missing label, permissions, etc.) we warn to stderr but still
# exit 0, because the comment (the actual escalation) already succeeded.
gh pr comment "$pr" --body-file "$body_file"

if ! gh pr edit "$pr" --add-label needs-human >/dev/null 2>&1; then
  echo "warning: failed to add 'needs-human' label (it may not exist in this repo); escalation comment was posted regardless" >&2
fi
