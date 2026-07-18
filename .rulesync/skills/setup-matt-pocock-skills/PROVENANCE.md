# Provenance

This skill is a **vendored copy** of a third-party skill, brought in under the
copy-in exception in the repo `CLAUDE.md` ("サードパーティ skill は vendor しない。
copy-in 例外は skill ディレクトリ内に出典 + LICENSE を残す"). It was copied — not
fetched at runtime via `npx skill` / `gh skill` — deliberately, to avoid executing
upstream tooling (supply-chain hardening).

## Source

- **Upstream repo**: https://github.com/mattpocock/skills
- **Upstream path**: `skills/engineering/setup-matt-pocock-skills`
- **Author**: Matt Pocock
- **License**: MIT (see [LICENSE](./LICENSE))
- **Commit pinned**: `272f99b22574f50e4266791c86b9302682970e23` (`main`)
- **Retrieved**: 2026-07-05

In the **source-of-truth** directory `skills/setup-matt-pocock-skills/`, the following
files are byte-for-byte copies of the upstream at that commit:

- `SKILL.md`
- `domain.md`
- `issue-tracker-github.md`
- `issue-tracker-gitlab.md`
- `issue-tracker-local.md`
- `triage-labels.md`

`LICENSE` and this `PROVENANCE.md` are added by the vendoring; everything else is
untouched. To audit, diff the files under `skills/setup-matt-pocock-skills/` against
the pinned upstream URL:

```
https://raw.githubusercontent.com/mattpocock/skills/272f99b22574f50e4266791c86b9302682970e23/skills/engineering/setup-matt-pocock-skills/<file>
```

### Generated mirrors are not byte-for-byte

The byte-for-byte claim above is about `skills/setup-matt-pocock-skills/` only. This
repo also commits **rulesync-generated** mirrors under `.claude/skills/` and
`.agents/skills/` (see `scripts/rulesync-sync.mjs`; regenerate, don't hand-edit). Those
are derived artifacts and rulesync transforms frontmatter per target — notably the
`codexcli` target (`.agents/`) drops fields Codex CLI doesn't support, so
`.agents/skills/setup-matt-pocock-skills/SKILL.md` omits `disable-model-invocation:
true` while the source and the `.claude/` (Claude Code) mirror keep it. Verify the
mirrors with `node scripts/rulesync-sync.mjs --check`, not by diffing against upstream.

## Caveat: sibling-skill dependencies

`SKILL.md` references other Matt Pocock engineering skills that are **not** vendored
here — e.g. `to-issues`, `triage`, `to-prd`, `qa`, `wayfinder`, `domain-modeling`,
`grill-with-docs`, `improve-codebase-architecture`, `diagnosing-bugs`, `tdd`. This
setup skill only scaffolds the per-repo config (`docs/agents/*.md`, the `## Agent
skills` block) that those skills read; it is a no-op in isolation. Vendor the sibling
skills the same way if you intend to use the rest of the suite.

## Accepted deviations from local conventions, and known upstream critiques

This is a **byte-for-byte vendored copy**, so upstream content is kept verbatim even
where it diverges from this repo's local conventions or where automated reviewers flag
it. Editing the vendored files would break the `diff == 0`-against-pinned-upstream
guarantee that is the whole point of the copy-in (supply-chain auditability). The items
below are therefore **intentionally not patched here**; where they are genuine upstream
bugs, the right fix is a PR/issue against `mattpocock/skills`, not a local fork.

Deviations from *this repo's* conventions (accepted for fidelity):

- **Description voice** — `SKILL.md`'s frontmatter description is imperative
  ("Configure this repo…"), not the third-person form AGENTS.md prefers. This skill is
  `disable-model-invocation: true` (slash-command only), so the description is never used
  for model auto-invocation and the third-person rule's purpose (trigger matching) does
  not apply.
- **Flat file layout** — the seed templates (`domain.md`, `issue-tracker-*.md`,
  `triage-labels.md`) sit at the skill root rather than under `references/`/`assets/`.
  `SKILL.md` links them with root-relative paths (`./issue-tracker-github.md`); moving
  them would force edits to `SKILL.md` too, breaking fidelity there as well.

Upstream recipe critiques (raised by automated reviewers; upstream's to fix):

- `issue-tracker-github.md` — `gh pr list --json authorAssociation` may not be a
  supported `--json` field on current `gh`; `gh issue/pr list` default `--limit` is 30
  (no explicit pagination in the recipe).
- `issue-tracker-gitlab.md` — `glab issue list -F json` / `--state` flag usage may not
  match current `glab`.
- `SKILL.md` step 4 — when both `CLAUDE.md` and `AGENTS.md` exist it edits only
  `CLAUDE.md`, so a Codex-side `AGENTS.md` would not receive the `## Agent skills` block.

## Updating

Re-run the copy against a newer upstream commit, update the pinned commit / retrieval
date above, and re-verify the byte-for-byte claim. If upstream fixes any of the recipe
critiques above, bumping the pinned commit pulls the fix in automatically.
