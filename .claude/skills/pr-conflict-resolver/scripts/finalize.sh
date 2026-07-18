#!/usr/bin/env bash
# finalize.sh - stage resolved conflict files, complete the in-progress
# merge commit, run a pre-push safety checklist, and push.
#
# Usage: finalize.sh <push-branch> [<resolved-file> ...]
#
# This is the step the previous prose-only workflow was missing entirely:
# without `git add` + `git commit`, a resolved merge stays half-finished
# (MERGE_HEAD still set, paths still "unmerged" in the index) and a
# subsequent `git push` either fails outright or - worse - pushes a branch
# that silently dropped the merge. This script refuses to push unless the
# merge is actually complete.
#
# Two entry states, both ending at the same pre-push checklist + push:
#   - Conflicted merge (MERGE_HEAD present): caller passes every resolved
#     file; this script verifies coverage + no leftover markers, stages,
#     and commits.
#   - Already-clean merge (MERGE_HEAD absent, e.g. resolve-merge.sh exited 0
#     with no conflicts and its own `git merge` already created the commit):
#     caller passes zero resolved files; this script skips straight to the
#     checklist instead of erroring out on "no merge in progress".
#
# Exit codes:
#   0 - merge committed (or already committed), checklist passed, pushed
#   1 - refused to proceed (see stderr for which checklist item failed) or
#       `git push` itself failed
#   2 - usage error
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <push-branch> [<resolved-file> ...]" >&2
  exit 2
fi

branch="$1"
shift
resolved_files=("$@")

git_dir=$(git rev-parse --git-dir)

if [ -f "$git_dir/MERGE_HEAD" ]; then
  # 1. Every currently-unmerged path must be covered by the caller's file list.
  #    Checked BEFORE staging: `git add` clears a path's "unmerged" status
  #    regardless of its content, so after staging this check would always
  #    come back empty and prove nothing about whether resolution happened.
  unmerged=$(git diff --name-only --diff-filter=U || true)
  if [ -n "$unmerged" ]; then
    missing=""
    while IFS= read -r path; do
      [ -z "$path" ] && continue
      found=0
      for rf in "${resolved_files[@]}"; do
        [ "$rf" = "$path" ] && found=1 && break
      done
      [ "$found" -eq 0 ] && missing="${missing}${path}"$'\n'
    done <<<"$unmerged"
    if [ -n "$missing" ]; then
      echo "error: conflicted paths were not passed to finalize.sh and remain unresolved:" >&2
      printf '  %s\n' "$missing" >&2
      exit 1
    fi
  fi

  # 2. Refuse to stage any resolved file that still contains literal conflict
  #    markers. This is the check that actually catches "claimed resolved but
  #    wasn't" - staging alone would happily clear the unmerged flag on a file
  #    that still has `<<<<<<<` in it, which is exactly how a bad merge commit
  #    slips through unnoticed. Git's real markers are always `<<<<<<< <ref>`,
  #    a bare `=======`, and `>>>>>>> <ref>` - anchoring on the trailing space
  #    (outer markers) / end-of-line (middle separator) avoids false-positives
  #    on unrelated content that merely starts with 7+ of these characters
  #    (e.g. a longer Markdown Setext heading underline).
  marker_hit=0
  for f in "${resolved_files[@]}"; do
    if [ -f "$f" ] && grep -ncE '^<<<<<<< |^=======$|^>>>>>>> ' -- "$f" >/dev/null 2>&1; then
      echo "error: '$f' still contains conflict markers; resolve its content before finalizing" >&2
      marker_hit=1
    fi
  done
  if [ "$marker_hit" -ne 0 ]; then
    echo "refusing to stage files with unresolved conflict markers" >&2
    exit 1
  fi

  # 3. Stage exactly the files the caller says it resolved. Deliberately not
  #    `git add -A`, which could sweep in unrelated stray changes.
  git add -- "${resolved_files[@]}"

  # 4. Sanity check: staging should have cleared every unmerged path. If not,
  #    something outside this script's model changed the index concurrently.
  remaining=$(git diff --name-only --diff-filter=U || true)
  if [ -n "$remaining" ]; then
    echo "error: unmerged paths remain after staging (unexpected):" >&2
    printf '  %s\n' "$remaining" >&2
    exit 1
  fi

  # 5. Complete the merge commit (uses the pre-populated merge message).
  git commit --no-edit
else
  # 1'. MERGE_HEAD absent: either resolve-merge.sh already completed a
  # conflict-free merge (its own `git merge` auto-commits and clears
  # MERGE_HEAD), or this call is confused about which exit code it followed.
  # resolve-merge.sh only ever produces a resolved-file list on exit 10
  # (conflicts); on exit 0 there is nothing to resolve, so a non-empty list
  # here means the caller thinks there was a conflict when there wasn't.
  if [ "${#resolved_files[@]}" -gt 0 ]; then
    echo "error: no merge in progress (MERGE_HEAD not found), but resolved file(s) were passed: ${resolved_files[*]}" >&2
    echo "       resolve-merge.sh only produces a file list on exit 10 (conflicts); on exit 0 there is nothing to resolve" >&2
    exit 1
  fi
  echo "no merge in progress (MERGE_HEAD not found); treating this as an already-committed, conflict-free merge and proceeding to the pre-push checklist" >&2
fi

# 6. Pre-push checklist. Every item must hold before this script pushes
#    anything. Content-level marker scanning already happened in step 2,
#    pre-commit; this is git-state verification only.
checklist_failed=0

if [ -n "$(git status --porcelain)" ]; then
  echo "error: [checklist] working tree not clean after merge commit" >&2
  git status --porcelain >&2
  checklist_failed=1
fi

if [ -f "$git_dir/MERGE_HEAD" ]; then
  echo "error: [checklist] MERGE_HEAD still present after commit; merge did not complete" >&2
  checklist_failed=1
fi

if git diff --name-only --diff-filter=U | grep -q .; then
  echo "error: [checklist] unmerged paths still present" >&2
  checklist_failed=1
fi

current_branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$current_branch" != "$branch" ]; then
  echo "error: [checklist] expected HEAD on '$branch', but it is on '$current_branch'" >&2
  checklist_failed=1
fi

if [ "$checklist_failed" -ne 0 ]; then
  echo "error: pre-push checklist failed; refusing to push (merge commit was already created locally - fix the issue above and push manually once verified, do not re-run this script blindly)" >&2
  exit 1
fi

# 7. Push. No --force / --force-with-lease: a merge commit never needs
#    history rewriting.
git push origin "$branch"
