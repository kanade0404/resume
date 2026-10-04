#!/usr/bin/env bash
# verify.sh - run the applicable verification chain (typecheck / lint / test)
# for whatever stacks are detected in the current working tree, and report a
# structured, truthful pass/fail summary.
#
# Usage: verify.sh
#
# THIS SCRIPT NEVER SWALLOWS A CHECK'S EXIT CODE. The previous prose workflow
# piped `tsc --noEmit` through `|| true`, so a broken build could still be
# reported as a passing "tsc: ✅" in the PR comment. Every check below keeps
# its real exit status; a single failing check makes the whole script exit 1.
#
# Output (stdout): one line per check that ran, `<name>: PASS|FAIL`, followed
# by a trailing `RESULT: PASS|FAIL` line. Use this output verbatim as the
# source of truth for any completion comment - never assert a check passed
# without pointing at its line here.
#
# Exit codes:
#   0 - every detected check passed (including "no tooling detected")
#   1 - at least one detected check failed
set -uo pipefail
# NOTE: no `-e` on purpose. The point of this script is to run every
# applicable check and report all of their outcomes, not stop at the first
# failure. The overall exit status is computed explicitly at the end.

overall=0
ran_any=0

run_check() {
  local name="$1"
  shift
  echo "-- running: $name --" >&2
  if "$@"; then
    echo "$name: PASS"
  else
    echo "$name: FAIL"
    overall=1
  fi
  ran_any=1
}

# --- Node / TypeScript ---
if [ -f package.json ]; then
  if [ -f tsconfig.json ]; then
    run_check tsc npx --no-install tsc --noEmit
  fi
  if command -v jq >/dev/null 2>&1; then
    if jq -e '.scripts.lint' package.json >/dev/null 2>&1; then
      run_check lint npm run lint --if-present
    fi
    if jq -e '.scripts.test' package.json >/dev/null 2>&1; then
      # CI=true is the de-facto standard signal (jest, vitest, mocha, ava,
      # ...) for "don't enter watch mode". A bare `npm test` invoking a
      # watch-by-default runner would otherwise hang here indefinitely
      # (never emit PASS/FAIL, never reach the trailing RESULT line) in an
      # unattended run.
      run_check test env CI=true npm test --if-present
    fi
  else
    echo "warning: jq not found; cannot detect package.json scripts.lint/scripts.test - lint/test checks skipped without running them" >&2
  fi
fi

# --- Python ---
if [ -f pyproject.toml ]; then
  if command -v ruff >/dev/null 2>&1; then
    run_check ruff ruff check .
  fi
  if command -v pytest >/dev/null 2>&1; then
    run_check pytest pytest
  fi
fi

# --- Go ---
if [ -f go.mod ]; then
  run_check go-build go build ./...
  run_check go-test go test ./...
fi

# --- Rust ---
if [ -f Cargo.toml ]; then
  run_check cargo-check cargo check --workspace
  run_check cargo-test cargo test --workspace
fi

# --- Make-based projects (only if no more specific check already covered it) ---
if [ -f Makefile ] && grep -qE '^test:' Makefile; then
  run_check make-test make test
fi

if [ "$ran_any" -eq 0 ]; then
  echo "no known verification tooling detected (package.json/pyproject.toml/go.mod/Cargo.toml/Makefile); nothing to run" >&2
fi

if [ "$overall" -eq 0 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL"
fi

exit "$overall"
