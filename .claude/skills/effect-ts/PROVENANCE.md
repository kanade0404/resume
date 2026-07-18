# Provenance

This skill is **vendored** (copied in) from a third-party repository, per the
copy-in exception in the repo-root `CLAUDE.md` ("copy-in 例外は skill ディレクトリ内に
出典 + LICENSE を残す").

- Source: https://github.com/Effect-TS/skills/tree/main/skills/effect-ts
- Upstream repo: https://github.com/Effect-TS/skills
- Pinned commit: `b5026c68318f395bbfd258182ea6b524ff2be549`
- Commit date: 2026-05-15
- Vendored on: 2026-07-05
- Reason: supply-chain safety — copied verbatim instead of fetching at consume time.

## License status

At the time of vendoring, the upstream `Effect-TS/skills` repository contained
**no LICENSE file and no explicit license statement** (verified via the GitHub
API and the upstream README). The Effect project is generally published under the
MIT License, but this `skills` repository carries no explicit grant. This copy is
made in good faith for internal use. If upstream adds an explicit license, or
requests removal, update or remove this vendored copy accordingly.

## Re-syncing from upstream

Re-fetch each file at a chosen commit `<SHA>`:

```sh
for f in SKILL.md references/features.md references/guide-effect.md \
  references/guide-error-handling.md references/guide-layers.md \
  references/guide-observability.md references/guide-retries.md \
  references/guide-schedule.md references/guide-schema.md \
  references/guide-sql.md references/guide-testing.md references/setup.md; do
  gh api "repos/Effect-TS/skills/contents/skills/effect-ts/$f?ref=<SHA>" \
    --jq '.content' | base64 -d > "skills/effect-ts/$f"
done
```

After re-syncing, re-apply the source-attribution comment in SKILL.md and update the
pinned commit / dates above.
