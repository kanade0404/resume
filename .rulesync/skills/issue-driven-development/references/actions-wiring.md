# Actions / Routines 配線

issue-driven-development を無人で回すためのトリガ配線。**配線作業をする時だけ読む。**
セキュリティ既定 (SHA ピン留め・最小権限・外部コントリビュータ除外) は省略せず全て適用する。

## 方式の選択

| 方式 | 即時性 | 予算の持ち方 | 向き |
|---|---|---|---|
| **A. claude-code-action (ラベルトリガ)** | 即時 | workflow 内で `--max-turns` / budget | 単一 repo で完結させたい時 |
| **B. Routines (GitHub イベント / 毎時)** | イベント or 毎時 | Routine プロンプトで指示 | subscription 枠で回したい時・複数 repo |

どちらも本スキル (SKILL.md) を実行させる点は同じ。トリガと実行環境だけが違う。

## A. claude-code-action ラベルトリガ

```yaml
# .github/workflows/claude-issue.yml (対象 repo)
name: claude-issue
on:
  issues:
    types: [labeled]

concurrency:
  group: claude-issue-${{ github.event.issue.number }}
  cancel-in-progress: false

jobs:
  run:
    # ラベルゲート = セキュリティゲート: ラベルは write 権限者しか付けられない。
    # 自己発火ガード: Claude App 自身のイベントでは起動しない
    if: >
      github.event.label.name == 'claude:ready' &&
      !endsWith(github.actor, '[bot]')
    runs-on: ubuntu-latest
    permissions:
      contents: write
      issues: write
      pull-requests: write
    steps:
      - uses: actions/checkout@<SHA をピン留め> # vX.Y.Z
      - uses: anthropics/claude-code-action@<SHA をピン留め> # vX.Y.Z
        with:
          claude_args: "--max-turns 80"
          prompt: |
            issue-driven-development skill に従い、この repo の issue #${{ github.event.issue.number }} を処理して PR 作成まで完遂すること。
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

注意:

- action の参照は**必ずコミット SHA でピン留め** (floating tag は供給網リスク)
- `pull_request_target` は使わない。fork からの issue/PR で secrets が要る workflow を起動しない
- issue 本文はプロンプトに直接埋め込まない ( injection 面)。番号だけ渡し、skill 側が gh で読む

## B. Routines

```
毎時 (または GitHub issues イベント):
  対象 repo で claude:ready ラベルの open issue を作成日昇順で 1 件選び、
  issue-driven-development skill に従って PR 作成まで完遂する。
  0 件なら何もせず終了する。
```

- Routine の secrets に `GH_TOKEN` (repo スコープ PAT)、任意で `LOOP_OPS_TOKEN`
- 排他はスキル本体の lock コメント protocol が守る (毎時 cron と手動の併走を想定済み)

## CI 修正・レビュー対応の反応 (イベント分割の後半)

```yaml
# CI 失敗への有界な反応の例 (概形)
on:
  workflow_run:
    workflows: [CI]
    types: [completed]
jobs:
  fix:
    if: >
      github.event.workflow_run.conclusion == 'failure' &&
      startsWith(github.event.workflow_run.head_branch, 'claude/issue-')
    # → claude-code-action で ci-self-heal 相当を 1 反応だけ実行
```

反応側の必須ルール:

- **`claude-loop:N` を進める**: 修正 push の前に PR の現在値を読み、N>=3 なら修正せず
  escalate (`ci-3-fail`)。ラベル更新と judge は反応の冒頭で行う
- **no-progress**: 直前の自分の commit と同一ファイル・同一失敗なら反復せず escalate
- **自己発火ガード**: 反応が push した commit で自分自身が再起動しない条件を必ず入れる

## 計測 (agent_run) の送信

実行の終端で ResultMessage 相当 (`claude -p --output-format json` の出力、または
Action の実行結果) から 1 イベントを送る。loop-ops を使う環境のみ:

```bash
jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg repo "$OWNER/$REPO" --argjson issue "$NUMBER" --arg phase "implement" \
  --arg subtype "$SUBTYPE" --argjson turns "$TURNS" --argjson cost "$COST" \
  --arg session "$SESSION_ID" \
  '{v:1, ts:$ts, event:"agent_run", repo:$repo, issue:$issue, phase:$phase,
    result_subtype:$subtype, num_turns:$turns, total_cost_usd:$cost, session_id:$session}' \
  | bash emit-event.sh   # loop-ops/scripts/emit-event.sh (要 LOOP_OPS_TOKEN)
```

phase は反応の種類に合わせる: `implement` (本スキル) / `ci-fix` / `review-respond`。
PR クローズ時の `pr_closed` は loop-ops の collect-metrics.yml (loop-metrics 配線) が拾う。
