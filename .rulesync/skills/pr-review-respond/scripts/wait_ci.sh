#!/usr/bin/env bash
# Wait for CI checks on a PR to complete. Exits non-zero if any check
# concludes as failure or is timed out.
#
# Usage: wait_ci.sh <pr-number> [interval-seconds]
#
# Default interval: 30s. Caller decides what to do on failure (typically
# delegate to ci-self-heal). This script does NOT retry.

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 <pr-number> [interval-seconds]" >&2
  exit 2
fi

pr="$1"
interval="${2:-30}"

# `--watch` blocks until all checks complete; exit code reflects pass/fail.
gh pr checks "$pr" --watch --interval "$interval"
