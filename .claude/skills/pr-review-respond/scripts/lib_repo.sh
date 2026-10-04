#!/usr/bin/env bash
# Shared owner/repo resolution for the prr subcommands. Sourced, not executed:
#   . "$SCRIPT_DIR/lib_repo.sh"; prr_resolve_repo
#
# Sets (globals): owner, repo, repo_source ("-R" | "GH_REPO" | "cwd"), and
# exports GH_REPO=<owner>/<repo> so every later `gh pr ...` call targets the
# same repository as the REST / GraphQL calls built from $owner/$repo.
#
# Precedence: GH_REPO (set by `prr -R owner/repo`, or exported by the caller)
#             > the repository of the current directory (`gh repo view`).
#
# Why this exists:
# - Run from a different repository's clone, `gh repo view` silently resolves
#   to *that* repository. If the same PR number exists there (e.g. an old
#   merged PR), every API call succeeds and `prr fetch` used to exit 0 with
#   empty threads / reviews / comments — indistinguishable from "no findings".
#   `-R owner/repo` makes the target explicit, and the resolved repository is
#   always reported on stderr so a wrong target is visible.
# - `gh repo view` ignores GH_REPO while `gh pr view` / `gh pr comment` honor
#   it. Mixing the two used to build a document whose PR metadata came from
#   one repository and whose threads came from another. Resolving once here
#   and passing the result explicitly everywhere removes that split.

# 直接 source されても色強制に依存しないよう、自前でも無効化する
export NO_COLOR=1
export CLICOLOR_FORCE=0
unset GH_FORCE_TTY
export GH_PAGER=cat

# shellcheck disable=SC2034  # owner / repo / repo_source are read by the sourcing script
prr_resolve_repo() {
  local spec
  if [ -n "${GH_REPO:-}" ]; then
    spec="${GH_REPO%/}"
    # GH_REPO is [HOST/]OWNER/REPO
    if [[ ! "$spec" =~ ^([^/[:space:]]+/)?[^/[:space:]]+/[^/[:space:]]+$ ]]; then
      echo "error: invalid repository '$GH_REPO' (expected owner/repo)" >&2
      return 2
    fi
    # Only github.com is supported: the REST / GraphQL calls are built from
    # owner/repo and `gh api` targets github.com unless --hostname is passed,
    # so a GHE host would silently read github.com/<owner>/<repo> instead.
    # Reject other hosts up front rather than query the wrong server.
    if [[ "$spec" == */*/* ]]; then
      local host="${spec%%/*}"
      if [ "$host" != "github.com" ]; then
        echo "error: host '$host' in '$GH_REPO' is not supported (prr only targets github.com; pass owner/repo)" >&2
        return 2
      fi
      spec="${spec#*/}"
    fi
    repo="${spec##*/}"
    owner="${spec%/*}"
    repo_source="${PRR_REPO_SOURCE:-GH_REPO}"
    export GH_REPO="$owner/$repo"
  else
    if ! spec=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || [ -z "$spec" ]; then
      echo "error: could not resolve a GitHub repository from the current directory; pass -R owner/repo" >&2
      return 1
    fi
    owner="${spec%%/*}"
    repo="${spec#*/}"
    repo_source="cwd"
    export GH_REPO="$owner/$repo"
  fi
  echo "prr: repository $owner/$repo (source: $repo_source)" >&2
}
