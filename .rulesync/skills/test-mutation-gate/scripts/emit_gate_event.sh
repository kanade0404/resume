#!/usr/bin/env bash
# emit_gate_event.sh - best-effort metrics emission for test-mutation-gate.
#
# Usage:
#   emit_gate_event.sh <result_subtype: pass|block> <caller> <findings_critical> <findings_warn> \
#     [by_check_json] [mutations_caught] [mutations_total]
#
# The last two args (mutations_caught, mutations_total) are optional and
# come from the Phase 2 mutation smoke (scripts/mutate_and_run.py). Callers
# that don't run mutation smoke can omit them entirely - back-compat with
# the pre-Phase-2 4/5-arg call sites is preserved (the fields are simply
# left out of the payload rather than sent as 0, so "didn't run mutation
# smoke" stays distinguishable from "ran it and caught nothing").
#
# Sends an agent_run event (test-mutation-gate phase, loop-ops event schema
# v1) to kanade0404/loop-ops via the GitHub Contents API when LOOP_OPS_TOKEN
# is set, otherwise appends the event to
# .cache/test-mutation-gate/gate-events.jsonl in the current repo (a
# dedicated cache path, not the agent config directory, and covered by this
# repo's distributed .gitignore so the mandatory gate never leaves an
# untracked file behind for commit-cleanliness / verify-done checks to trip
# over). Metrics emission is best-effort and must never affect the gate's
# own PASS/BLOCK verdict, so this script always exits 0.
#
# Intentionally no `set -e`: every step below has an explicit fallback, and
# a mid-script abort would defeat that (best-effort) design.
set -u

result_subtype="${1:-unknown}"
caller="${2:-unknown}"
findings_critical="${3:-0}"
findings_warn="${4:-0}"
by_check_json="${5:-}"
mutations_caught="${6:-}"
mutations_total="${7:-}"

# Guard against non-integer input rather than letting jq --argjson choke on it.
if ! [[ "$findings_critical" =~ ^-?[0-9]+$ ]]; then
  findings_critical=0
fi
if ! [[ "$findings_warn" =~ ^-?[0-9]+$ ]]; then
  findings_warn=0
fi

if [ -z "$by_check_json" ] || ! jq -e . >/dev/null 2>&1 <<<"$by_check_json"; then
  by_check_json='{}'
fi

# Unset (not just non-integer) means "mutation smoke wasn't run" - keep that
# distinguishable from "ran it, 0 mutations". Only coerce to an int when the
# caller passed something that isn't a valid integer.
have_mutation_fields=1
if [ -z "$mutations_caught" ] && [ -z "$mutations_total" ]; then
  have_mutation_fields=0
else
  if ! [[ "$mutations_caught" =~ ^-?[0-9]+$ ]]; then
    mutations_caught=0
  fi
  if ! [[ "$mutations_total" =~ ^-?[0-9]+$ ]]; then
    mutations_total=0
  fi
fi

# Derive "owner/name" from the origin remote URL (handles both
# git@host:owner/name.git and https://host/owner/name.git forms). Falls
# back to unknown/unknown if there's no origin remote or it doesn't parse.
get_repo_slug() {
  local url
  url=$(git remote get-url origin 2>/dev/null) || { printf '%s\n' "unknown/unknown"; return; }
  if [ -z "$url" ]; then
    printf '%s\n' "unknown/unknown"
    return
  fi
  # Note: bash's [[ =~ ]] uses POSIX ERE, which has no lazy quantifiers, so
  # group 3 is captured greedily (it may include a trailing ".git") and the
  # suffix is stripped afterward with plain parameter expansion instead.
  if [[ "$url" =~ ^(https?://[^/]+/|git@[^:]+:)([^/]+)/([^/]+)/?$ ]]; then
    local owner="${BASH_REMATCH[2]}"
    local name="${BASH_REMATCH[3]}"
    name="${name%.git}"
    printf '%s/%s\n' "$owner" "$name"
  else
    printf '%s\n' "unknown/unknown"
  fi
}

repo="$(get_repo_slug)"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# -c (compact) is required here: this payload is appended as one line per
# event to test-gate-events.jsonl, so it must never contain embedded
# newlines.
payload="$(jq -nc \
  --argjson v 1 \
  --arg ts "$ts" \
  --arg event "agent_run" \
  --arg repo "$repo" \
  --arg phase "test-mutation-gate" \
  --arg result_subtype "$result_subtype" \
  --arg caller "$caller" \
  --argjson findings_critical "$findings_critical" \
  --argjson findings_warn "$findings_warn" \
  --argjson by_check "$by_check_json" \
  --argjson have_mutation_fields "$have_mutation_fields" \
  --argjson mutations_caught "${mutations_caught:-0}" \
  --argjson mutations_total "${mutations_total:-0}" \
  '{
    v: $v,
    ts: $ts,
    event: $event,
    repo: $repo,
    phase: $phase,
    result_subtype: $result_subtype,
    caller: $caller,
    findings_critical: $findings_critical,
    findings_warn: $findings_warn,
    by_check: $by_check
  } + (if $have_mutation_fields == 1 then
    {mutations_caught: $mutations_caught, mutations_total: $mutations_total}
  else
    {}
  end)')"

sent=0

month="$(date -u +%Y-%m)"
# $$ adds process-level uniqueness alongside epoch+RANDOM so concurrent
# invocations in the same second don't collide on the same event path.
event_path="metrics/events/${month}/agent_run-$(date +%s)-${RANDOM}-$$.json"
content_b64="$(printf '%s' "$payload" | base64 | tr -d '\n')"
body="$(jq -n \
  --arg message "metrics: test-mutation-gate ${result_subtype}" \
  --arg content "$content_b64" \
  '{message: $message, content: $content}')"

if [ -n "${LOOP_OPS_TOKEN:-}" ]; then
  # -H "Content-Type: application/json" is required: curl -d otherwise
  # defaults to application/x-www-form-urlencoded, which the GitHub Contents
  # API does not accept for a JSON body - without it the PUT can fail and
  # this falls through to the local-file branch below silently.
  # --connect-timeout/--max-time: this call must stay best-effort - a slow
  # or unresponsive network must not hang the gate itself, it should fail
  # fast and fall through to the local JSONL sink below.
  if curl -sf --connect-timeout 5 --max-time 10 \
      -X PUT "https://api.github.com/repos/kanade0404/loop-ops/contents/${event_path}" \
      -H "Authorization: Bearer ${LOOP_OPS_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "Content-Type: application/json" \
      -d "$body" >/dev/null 2>&1; then
    sent=1
  fi
fi

# Middle tier: developer machines usually have no LOOP_OPS_TOKEN exported but
# do have an authenticated `gh` (the same account that owns loop-ops). Without
# this tier every local gate invocation lands in the local JSONL only, loop-ops
# sees zero agent_run events, and the gate-heartbeat monitor would alarm
# forever. GH_PROMPT_DISABLED prevents gh from blocking on interactive auth.
if [ "$sent" -ne 1 ] && command -v gh >/dev/null 2>&1; then
  if printf '%s' "$body" | GH_PROMPT_DISABLED=1 gh api -X PUT \
      "repos/kanade0404/loop-ops/contents/${event_path}" \
      --input - >/dev/null 2>&1; then
    sent=1
  fi
fi

if [ "$sent" -ne 1 ]; then
  mkdir -p .cache/test-mutation-gate
  printf '%s\n' "$payload" >> .cache/test-mutation-gate/gate-events.jsonl
fi

exit 0
