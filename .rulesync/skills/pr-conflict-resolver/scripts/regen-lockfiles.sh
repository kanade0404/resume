#!/usr/bin/env bash
# regen-lockfiles.sh - regenerate conflicted dependency lockfiles instead of
# hand-editing conflict markers inside generated content.
#
# Usage: regen-lockfiles.sh <lockfile-path> [<lockfile-path> ...]
#
# Each path's basename selects the ecosystem-specific regeneration command
# (the `case` below). An unrecognized lockfile name fails loudly rather than
# being silently skipped, so the caller never pushes a file that still has
# `<<<<<<<` markers in it.
#
# --ignore-scripts (npm/pnpm/yarn/bun) is deliberate: it stops untrusted
# postinstall hooks from executing during unattended conflict resolution.
# Repository-specific postinstall steps still run in CI afterward.
set -uo pipefail
# NOTE: no `-e` at the top level on purpose. With N conflicted lockfiles we
# want to attempt every one and report which failed, not abort after the
# first failure and leave the rest un-attempted. Exit status is computed
# explicitly from the per-file results below.

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <lockfile-path> [<lockfile-path> ...]" >&2
  exit 2
fi

status=0

for path in "$@"; do
  if [ ! -e "$path" ]; then
    echo "error: '$path' does not exist (conflict marker removal or a prior step may have deleted it)" >&2
    status=1
    continue
  fi

  base=$(basename -- "$path")
  dir=$(dirname -- "$path")

  echo "== regenerating $path ==" >&2

  (
    set -e
    cd "$dir"
    case "$base" in
      package-lock.json)
        rm -f package-lock.json
        npm install --package-lock-only --ignore-scripts
        ;;
      pnpm-lock.yaml)
        rm -f pnpm-lock.yaml
        pnpm install --lockfile-only --ignore-scripts
        ;;
      yarn.lock)
        rm -f yarn.lock
        yarn install --mode update-lockfile --ignore-scripts 2>/dev/null \
          || yarn install --ignore-scripts
        ;;
      bun.lock | bun.lockb)
        rm -f bun.lock bun.lockb
        bun install --frozen-lockfile=false --ignore-scripts
        ;;
      Cargo.lock)
        cargo update --workspace --offline 2>/dev/null \
          || cargo generate-lockfile
        ;;
      poetry.lock)
        # poetry/uv/go/bundle all parse the existing lockfile before
        # resolving, so a conflict-marker-tainted file aborts even
        # `--no-update` mode. Remove it first, matching the fallback the
        # npm/pnpm/yarn/bun/Cargo.lock branches above already use.
        rm -f poetry.lock
        poetry lock --no-update
        ;;
      uv.lock)
        rm -f uv.lock
        uv lock
        ;;
      go.sum)
        rm -f go.sum
        go mod tidy
        # `go mod tidy` can also rewrite go.mod (missing/unused
        # requirements). go.mod isn't part of the caller's resolved-file
        # list (only go.sum was conflicted), so stage it here - otherwise
        # finalize.sh's pre-push "working tree clean" checklist fails after
        # the merge commit has already been created, since go.mod would be
        # left modified but uncommitted.
        git add -- go.mod
        ;;
      Gemfile.lock)
        rm -f Gemfile.lock
        bundle lock --update
        ;;
      *)
        echo "error: unsupported lockfile '$base' - resolve manually, do not guess a regen command" >&2
        exit 1
        ;;
    esac
  )
  file_status=$?

  if [ "$file_status" -ne 0 ]; then
    echo "error: regeneration failed for '$path' (exit $file_status)" >&2
    status=1
  fi
done

exit "$status"
