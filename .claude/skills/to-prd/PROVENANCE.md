# Provenance

This skill is a **vendored copy** of a third-party skill, brought in under the
copy-in exception in the repo `CLAUDE.md` ("サードパーティ skill は vendor しない。
copy-in 例外は skill ディレクトリ内に出典 + LICENSE を残す"). It was copied — not
fetched at runtime via `npx skill` / `gh skill` — deliberately, to avoid executing
upstream tooling (supply-chain hardening).

## Source

- **Upstream repo**: https://github.com/mattpocock/skills
- **Upstream path**: `skills/engineering/to-prd`
- **Author**: Matt Pocock
- **License**: MIT (see [LICENSE](./LICENSE))
- **Commit pinned**: `272f99b22574f50e4266791c86b9302682970e23` (`main`)
- **Retrieved**: 2026-07-05

In the **source-of-truth** directory `skills/to-prd/`, the following file is a
byte-for-byte copy of the upstream at that commit:

- `SKILL.md`

`LICENSE` and this `PROVENANCE.md` are added by the vendoring; everything else is
untouched. To audit, diff the file under `skills/to-prd/` against the pinned
upstream URL:

```text
https://raw.githubusercontent.com/mattpocock/skills/272f99b22574f50e4266791c86b9302682970e23/skills/engineering/to-prd/SKILL.md
```

### Generated mirrors are not byte-for-byte

The byte-for-byte claim above is about `skills/to-prd/` only. This repo also commits
**rulesync-generated** mirrors under `.claude/skills/` and `.agents/skills/` (see
`scripts/rulesync-sync.mjs`; regenerate, don't hand-edit). Those are derived artifacts
and rulesync transforms frontmatter per target — notably the `codexcli` target
(`.agents/`) drops fields Codex CLI doesn't support, so
`.agents/skills/to-prd/SKILL.md` omits `disable-model-invocation: true` while the
source and the `.claude/` (Claude Code) mirror keep it. Verify the mirrors with
`node scripts/rulesync-sync.mjs --check`, not by diffing against upstream.

## Caveat: sibling-skill dependencies

`SKILL.md` references `/setup-matt-pocock-skills`, which scaffolds the per-repo config
(issue tracker, triage label vocabulary, domain doc layout) that this skill reads. That
skill is vendored alongside it at `skills/setup-matt-pocock-skills/`, so the dependency
resolves within this repo. `SKILL.md` also assumes the surrounding Matt Pocock
engineering suite (domain glossary / `CONTEXT.md`, ADRs); vendor the sibling skills the
same way if you intend to use the rest of the suite.

## Accepted deviations from local conventions, and known upstream critiques

This is a **byte-for-byte vendored copy**, so upstream content is kept verbatim even
where it diverges from this repo's local conventions or where automated reviewers flag
it. Editing the vendored file would break the `diff == 0`-against-pinned-upstream
guarantee that is the whole point of the copy-in (supply-chain auditability). The items
below are therefore **intentionally not patched here**; where they are genuine upstream
bugs, the right fix is a PR/issue against `mattpocock/skills`, not a local fork.

Deviations from *this repo's* conventions (accepted for fidelity):

- **Description voice** — `SKILL.md`'s frontmatter description is imperative
  ("Turn the current conversation…"), not the third-person form AGENTS.md prefers. This
  skill is `disable-model-invocation: true` (slash-command only), so the description is
  never used for model auto-invocation and the third-person rule's purpose (trigger
  matching) does not apply.

Upstream behaviour critiques (raised by automated reviewers; upstream's to fix):

- `SKILL.md` step 2 — "Check with the user that these seams match their expectations"
  reads as a clarification step, which reviewers flag against the frontmatter's "no
  interview" line. Upstream's intent is narrower: don't re-run a full requirements
  interview (synthesize from existing context) while still confirming the test seams
  once. Kept verbatim.
- `SKILL.md` step 3 — applies the literal `ready-for-agent` triage label. That is
  upstream's canonical default; repos with a different AFK-ready label remap it via
  `setup-matt-pocock-skills`' `triage-labels.md` rather than by editing this skill.

## Updating

Re-run the copy against a newer upstream commit, update the pinned commit / retrieval
date above, and re-verify the byte-for-byte claim. If upstream fixes any of the
critiques above, bumping the pinned commit pulls the fix in automatically.
