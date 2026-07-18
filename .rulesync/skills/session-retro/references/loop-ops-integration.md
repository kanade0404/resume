# loop-ops 連携

session-retro を [loop-ops](https://github.com/kanade0404/loop-ops) (private な計測データストア) と
組み合わせる環境での配線。loop-ops を使わない環境ではこのファイルは無視してよい。

## 責務の分離

| 何を | 誰が | いつ |
|---|---|---|
| `agent_run` イベント送信 (cost / turns / subtype) | **実行ラッパー / Stop hook** | agent 実行の終端で必ず |
| `escalated` イベント送信 | エスカレーション処理 (実行側 skill) | needs-human 付与と同時 |
| retro の 4 分岐出力 | session-retro (本体) | セッション終端 |
| eval-case の PR 起票 | session-retro (承認後) | retro 承認後 |

session-retro 自身はイベントを送らない。セッション内から自分の総コスト・ターン数は取れないため、
`agent_run` は **セッションの外側** (ResultMessage / `claude -p --output-format json` の出力を持つ側)
が送る。

## Stop hook での agent_run 送信 (実行ラッパー側の設定例)

`claude -p` をラップする実行スクリプトの終端で:

```bash
# result.json = claude -p --output-format json の出力
jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg repo "$OWNER/$REPO" --argjson issue "${ISSUE_NUMBER:-null}" \
  --arg phase "implement" \
  --arg subtype "$(jq -r '.subtype // "unknown"' result.json)" \
  --argjson turns "$(jq '.num_turns // 0' result.json)" \
  --argjson cost "$(jq '.total_cost_usd // 0' result.json)" \
  --arg session "$(jq -r '.session_id // ""' result.json)" \
  '{v: 1, ts: $ts, event: "agent_run", repo: $repo, issue: $issue, phase: $phase,
    result_subtype: $subtype, num_turns: $turns, total_cost_usd: $cost, session_id: $session}' \
  | bash emit-event.sh   # loop-ops/scripts/emit-event.sh (要 LOOP_OPS_TOKEN)
```

`phase` は `implement | ci-fix | review-respond | conflict-resolve | retro | meta` から。
対話セッションで hook として仕込む場合は Stop hook から同スクリプトを叩く
(transcript パスが hook 入力で渡るので、そこから session_id を拾える)。

## eval-case の PR 起票

retro が承認された eval-case は loop-ops に PR で送る:

```bash
# 1 ファイルなので contents API で branch + PR を作るのが最短
gh api repos/<owner>/loop-ops/git/refs -f ref="refs/heads/eval/<id>" \
  -f sha="$(gh api repos/<owner>/loop-ops/git/ref/heads/master --jq '.object.sha')"
gh api -X PUT "repos/<owner>/loop-ops/contents/golden/cases/<id>.md" \
  -f branch="eval/<id>" -f message="eval: add <id> (from session retro)" \
  -f content="$(base64 < case.md | tr -d '\n')"
gh pr create -R <owner>/loop-ops --head "eval/<id>" --title "eval: <id>" \
  --body "source: <セッション/PR URL>. 承認後 merge (agent は self-merge しない)"
```

**merge は必ず人間**。改善対象の agent が自分の合格基準を書ける状態にしない、という
golden set の不変条件 (loop-ops/golden/README.md) を守る。

## エスカレーション形式との整合

retro がエスカレーション由来のシグナルを扱うとき、reason は loop-ops の taxonomy
(`docs/taxonomy.md`) の enum を使う: `budget-exceeded / max-turns / ci-3-fail /
review-5-rounds / no-progress / ambiguous-issue / repo-unresolvable / conflict /
security-block / other`。

`ambiguous-issue` は失敗ではなく「issue の入口品質の問題を上流に返した正常動作」。
retro ではこれを issue の書き方の rule (例: acceptance criteria テンプレの改善) に
昇格させる候補として扱う。
