#!/usr/bin/env bash
# Deterministic exclusive-lock acquisition for issue-driven-development.
#
# Fixes two known failure modes (kanade0404/skills#31):
#   1. Queue loss: the old procedure flipped claude:ready -> claude:in-progress
#      BEFORE the race for the lock was decided. A run that lost the race (or
#      crashed between the flip and the win-check) removed only its own
#      claude:in-progress and left the issue with NEITHER claude:ready NOR
#      claude:in-progress -- nobody would ever pick it up again.
#   2. Deadlock: "oldest claude-lock: comment wins" never expired, so a
#      crashed owner's lock comment blocked every future run forever.
#
# Guarantees this script makes:
#   - Labels are ONLY ever touched by the confirmed winner. A losing or
#     erroring run never mutates labels, so it can never cause queue loss.
#   - Every abnormal exit of THIS process after it flips labels to
#     claude:in-progress restores claude:ready via an EXIT trap. This is
#     best-effort: it protects against this script's own crashes, not a
#     host-level kill that happens later, after the script has already
#     exited 0 and control has passed to the caller's implementation phase.
#   - Lock comments carry a lease timestamp (`claude-lock: <run-id>
#     ts=<epoch>`). A claude:in-progress issue whose lease is older than
#     LOCK_LEASE_TTL_SECONDS is detected and reclaimed back to
#     claude:ready (with an audit comment) the NEXT time this script looks
#     at that issue -- either via single-issue mode (manual retry / label
#     event) or via `--reap`, which a queue-selection pass should run
#     before picking the next claude:ready issue. This is what breaks the
#     deadlock even after an ungraceful crash that outlives this script's
#     own trap.
#
# Usage:
#   acquire-lock.sh <owner/repo> <issue-number> [run-id]
#   acquire-lock.sh --reap <owner/repo>
#
# Requires: gh (authenticated), jq. bash 4+ (uses process substitution free
# constructs so it also runs under bash 3.2 / macOS default bash).
#
# Env:
#   LOCK_LEASE_TTL_SECONDS  seconds before an unattended claude:in-progress
#                           lock is considered abandoned and reclaimed.
#                           Default 3600 (60 min).
#
# Exit codes (single-issue mode):
#   0  lock acquired -- labels are now claude:in-progress. Prints
#      "run_id=<uuid>" and "acquired_at=<epoch>" to stdout.
#   3  skip: issue already terminal (claude:done or claude:failed present)
#   4  skip: locked by another live run (lease not yet expired)
#   5  skip: lost the race to acquire (another comment is older)
#   2  usage error
#   1  unexpected failure (gh/jq error). Any label mutation already made by
#      THIS run is rolled back by the EXIT trap before returning.
#
# Exit codes (--reap mode): always 0. Prints "reclaimed=<n>".
set -euo pipefail

LABEL_READY="claude:ready"
LABEL_PROGRESS="claude:in-progress"
LABEL_DONE="claude:done"
LABEL_FAILED="claude:failed"
LEASE_TTL="${LOCK_LEASE_TTL_SECONDS:-3600}"

usage() {
  cat <<'EOF' >&2
usage:
  acquire-lock.sh <owner/repo> <issue-number> [run-id]
  acquire-lock.sh --reap <owner/repo>
EOF
}

gen_run_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid; print(uuid.uuid4())'
  elif command -v node >/dev/null 2>&1; then
    # Use require("crypto") rather than the global `crypto` object: the
    # global was only added in Node 19 (stable in 20), while
    # require("crypto").randomUUID has worked since Node 14.17/15.6.
    node -e 'console.log(require("crypto").randomUUID())'
  else
    printf '%s-%s-%s\n' "$(date -u +%s%N)" "$$" "$RANDOM"
  fi
}

ensure_labels() {
  repo="$1"
  # claude-loop:1..3 are provisioned here too: this is now the only label
  # provisioning path before the workflow hands off to the CI-fix/review
  # reactions, and those bounded-retry reactions assume the labels already
  # exist (gh issue/pr edit --add-label does not auto-create labels).
  for l in "$LABEL_READY" "$LABEL_PROGRESS" "$LABEL_DONE" "$LABEL_FAILED" needs-human \
    claude-loop:1 claude-loop:2 claude-loop:3; do
    gh label create "$l" -R "$repo" --color ededed --force >/dev/null 2>&1 || true
  done
}

# Fetch the most recent claude-lock: comment on an issue and report its age
# in seconds. Prints "<age>" ("" if no lock comment exists at all, which the
# caller treats as infinitely stale).
lock_lease_age() {
  repo="$1" num="$2" now="$3"
  last_lock=$(gh issue view "$num" -R "$repo" --json comments \
    --jq '[.comments[] | select(.body | startswith("claude-lock: "))] | sort_by(.createdAt) | last')
  if [ -z "$last_lock" ] || [ "$last_lock" = "null" ]; then
    echo ""
    return 0
  fi
  last_ts=$(printf '%s' "$last_lock" | jq -r '(.body | capture("ts=(?<ts>[0-9]+)").ts) // "0"')
  echo $(( now - last_ts ))
}

# Reclaim a single issue's stale claude:in-progress lock back to
# claude:ready, with an audit comment. Idempotent.
reclaim_issue() {
  repo="$1" num="$2" age="$3" by="$4"
  gh issue edit "$num" -R "$repo" \
    --remove-label "$LABEL_PROGRESS" --add-label "$LABEL_READY" >/dev/null
  gh issue comment "$num" -R "$repo" \
    --body "claude-lock-reclaim: lease expired (age ${age:-unknown}s > ${LEASE_TTL}s) or missing; requeued to ${LABEL_READY} by ${by}." \
    >/dev/null
}

# --- --reap mode: sweep all claude:in-progress issues in a repo ----------
if [ "${1:-}" = "--reap" ]; then
  if [ "$#" -ne 2 ]; then
    usage
    exit 2
  fi
  repo="$2"
  now=$(date -u +%s)
  ensure_labels "$repo"
  reclaimed=0
  # --limit: gh issue list defaults to 30 results, which would silently skip
  # stale claude:in-progress issues once a repo has more open ones than that.
  numbers=$(gh issue list -R "$repo" --label "$LABEL_PROGRESS" --state open --limit 1000 --json number --jq '.[].number')
  for num in $numbers; do
    # Mirror the single-issue terminal check: a run that partially completes
    # (label mutations aren't atomic) can leave BOTH claude:in-progress and a
    # terminal label on the same issue. Without this, a later sweep would
    # requeue an already-finished issue back onto claude:ready.
    term_labels=$(gh issue view "$num" -R "$repo" --json labels --jq '[.labels[].name]')
    if printf '%s' "$term_labels" \
        | jq -e --arg d "$LABEL_DONE" --arg f "$LABEL_FAILED" \
          'index($d) != null or index($f) != null' >/dev/null; then
      continue
    fi
    age=$(lock_lease_age "$repo" "$num" "$now")
    if [ -z "$age" ] || [ "$age" -gt "$LEASE_TTL" ]; then
      reclaim_issue "$repo" "$num" "$age" "reap sweep"
      reclaimed=$((reclaimed + 1))
    fi
  done
  echo "reclaimed=${reclaimed}"
  exit 0
fi

# --- single-issue mode ----------------------------------------------------
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage
  exit 2
fi

REPO="$1"
ISSUE="$2"
RUN_ID="${3:-$(gen_run_id)}"
NOW=$(date -u +%s)

ensure_labels "$REPO"

# State the EXIT trap uses to decide whether a rollback is owed. Both start
# false; SWAPPED flips true right before we attempt the label flip (so a
# partially-applied `gh issue edit` is still rolled back), WON flips true
# only once the flip has actually succeeded.
SWAPPED_TO_PROGRESS=0
WON=0

restore_on_failure() {
  status=$?
  if [ "$SWAPPED_TO_PROGRESS" = "1" ] && [ "$WON" != "1" ]; then
    gh issue edit "$ISSUE" -R "$REPO" \
      --remove-label "$LABEL_PROGRESS" --add-label "$LABEL_READY" >/dev/null 2>&1 || true
    gh issue comment "$ISSUE" -R "$REPO" \
      --body "claude-lock-restore: run ${RUN_ID} exited abnormally (status ${status}) before completing lock acquisition; requeued to ${LABEL_READY}." \
      >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap restore_on_failure EXIT

# --- stage 0: terminal check -----------------------------------------------
labels=$(gh issue view "$ISSUE" -R "$REPO" --json labels --jq '[.labels[].name]')
has_label() {
  printf '%s' "$labels" | jq -e --arg l "$1" 'index($l) != null' >/dev/null
}

if has_label "$LABEL_DONE" || has_label "$LABEL_FAILED"; then
  echo "skip: issue already terminal" >&2
  exit 3
fi

# --- stage 0b: reap our own target issue if its lease is stale ------------
if has_label "$LABEL_PROGRESS"; then
  age=$(lock_lease_age "$REPO" "$ISSUE" "$NOW")
  if [ -z "$age" ] || [ "$age" -gt "$LEASE_TTL" ]; then
    reclaim_issue "$REPO" "$ISSUE" "$age" "run ${RUN_ID}"
  else
    echo "skip: locked by an active run (lease age ${age}s <= ${LEASE_TTL}s)" >&2
    exit 4
  fi
fi

# --- stage 1: post our lock comment ----------------------------------------
gh issue comment "$ISSUE" -R "$REPO" --body "claude-lock: ${RUN_ID} ts=${NOW}" >/dev/null

# --- stage 2: decide the winner BEFORE touching any label -------------------
# Only comments within the lease window count -- an ancient claude-lock:
# comment (e.g. left by a run that has since crashed) must not block us
# forever. This is what breaks the deadlock from kanade0404/skills#31.
# Note: `gh --jq` only takes a single expression string (no --arg/--argjson
# like the standalone jq binary), so we fetch raw JSON via gh and filter with
# a separate `jq` process where $now/$ttl can be bound safely.
oldest_run=$(gh issue view "$ISSUE" -R "$REPO" --json comments \
  | jq -r --argjson now "$NOW" --argjson ttl "$LEASE_TTL" '
    [.comments[]
      | select(.body | startswith("claude-lock: "))
      | . + {run: (.body | capture("claude-lock: (?<run>[^ ]+)").run),
             ts: ((.body | capture("ts=(?<ts>[0-9]+)").ts // "0") | tonumber)}
      | select(($now - .ts) <= $ttl)]
    | sort_by(.createdAt) | first.run // empty')

if [ "$oldest_run" != "$RUN_ID" ]; then
  echo "skip: lost the race (oldest live lock is ${oldest_run:-unknown})" >&2
  exit 5
fi

# --- stage 3: we won -- only now is it safe to flip labels -----------------
SWAPPED_TO_PROGRESS=1
gh issue edit "$ISSUE" -R "$REPO" \
  --remove-label "$LABEL_READY" --add-label "$LABEL_PROGRESS" >/dev/null
WON=1

echo "run_id=${RUN_ID}"
echo "acquired_at=${NOW}"
