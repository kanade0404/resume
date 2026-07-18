# Provenance

This skill is a **vendored copy** of a third-party skill, brought in under the
copy-in exception in the repo `CLAUDE.md` ("サードパーティ skill は vendor しない。
copy-in 例外は skill ディレクトリ内に出典 + LICENSE を残す"). It was copied — not
fetched at runtime via `npx skill` / `gh skill` — deliberately, to avoid executing
upstream tooling (supply-chain hardening).

## Source

- **Upstream repo**: https://github.com/mattpocock/skills
- **Upstream path**: `skills/engineering/to-issues`
- **Author**: Matt Pocock
- **License**: MIT (see [LICENSE](./LICENSE))
- **Commit pinned**: `272f99b22574f50e4266791c86b9302682970e23` (`main`)
- **Retrieved**: 2026-07-05

In the **source-of-truth** directory `skills/to-issues/`, the following file is a
byte-for-byte copy of the upstream at that commit:

- `SKILL.md`

`LICENSE` and this `PROVENANCE.md` are added by the vendoring; everything else is
untouched. To audit, diff the file under `skills/to-issues/` against the pinned
upstream URL:

```text
https://raw.githubusercontent.com/mattpocock/skills/272f99b22574f50e4266791c86b9302682970e23/skills/engineering/to-issues/SKILL.md
```

### Generated mirrors are not byte-for-byte

The byte-for-byte claim above is about `skills/to-issues/` only. This repo also commits
**rulesync-generated** mirrors under `.claude/skills/` and `.agents/skills/` (see
`scripts/rulesync-sync.mjs`; regenerate, don't hand-edit). Those are derived artifacts
and rulesync transforms frontmatter per target — notably the `codexcli` target
(`.agents/`) drops fields Codex CLI doesn't support, so
`.agents/skills/to-issues/SKILL.md` omits `disable-model-invocation: true` while the
source and the `.claude/` (Claude Code) mirror keep it. Verify the mirrors with
`node scripts/rulesync-sync.mjs --check`, not by diffing against upstream.

## Dependency: setup-matt-pocock-skills

`SKILL.md` tells the user to run `/setup-matt-pocock-skills` when the issue tracker and
triage label vocabulary have not been provided. That sibling skill is vendored in this
repo (`skills/setup-matt-pocock-skills/`), so the reference resolves; it scaffolds the
per-repo config (issue tracker, triage labels, domain docs) that this skill reads.

## Accepted deviations from local conventions, and known upstream critiques

This is a **byte-for-byte vendored copy**, so upstream content is kept verbatim even
where it diverges from this repo's local conventions or where automated reviewers flag
it. Editing the vendored file would break the `diff == 0`-against-pinned-upstream
guarantee that is the whole point of the copy-in (supply-chain auditability). The items
below are therefore **intentionally not patched here**; where they are genuine upstream
bugs, the right fix is a PR/issue against `mattpocock/skills`, not a local fork.

Deviations from *this repo's* conventions (accepted for fidelity):

- **Description voice** — `SKILL.md`'s frontmatter description is imperative
  ("Break a plan…"), not the third-person form AGENTS.md prefers, and it lacks an
  explicit "when to use" clause. This skill is `disable-model-invocation: true`
  (slash-command only), so the description is never used for model auto-invocation and
  the third-person / when-to-use rule's purpose (trigger matching) does not apply.
- **`disable-model-invocation: true`** — first use of this Claude Code-specific field in
  this catalog. It is intentional upstream design: the skill has the side effect of
  publishing issues to the tracker, so it is invoked only by explicit user request
  (`/to-issues`), never auto-triggered by the model. The `codexcli` mirror drops the
  field (see above).

Upstream recipe critiques (raised by automated reviewers; upstream's to fix):

- **Issue template omits a verification method** — the template asks for Acceptance
  Criteria but no verification command/test plan. This repo's
  `skills/issue-driven-development/SKILL.md` entrance gate wants both (though it accepts
  a verification method that is self-evident from the AC), so issues generated here may
  need a verification method added by hand before an AFK runner picks them up.
- **Approval step (step 4) does not show the generated issue body** — the quiz presents
  titles, blockers, and covered stories, but not the acceptance criteria / body that
  step 5 publishes. For side-effectful runs that create real tracker issues, review the
  drafted bodies before publishing.

## Updating

Re-run the copy against a newer upstream commit, update the pinned commit / retrieval
date above, and re-verify the byte-for-byte claim. If upstream fixes any of the recipe
critiques above, bumping the pinned commit pulls the fix in automatically.
