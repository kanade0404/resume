---
name: session-retro
description: |
  作業セッション (issue 駆動の自走実行・実装・出荷・リリース) の終端で、transcript /
  会話履歴から学びを抽出し、**rule (CLAUDE.md・skill 改訂 = feedforward) / sensor
  (テスト・lint・CI チェック追加 = feedback) / issue (繰り越し作業、acceptance criteria
  必須) / eval-case (golden set 候補)** の 4 分岐に振り分けて提案として出力する振り返り
  専用スキル。シグナル源は「失敗した tool 呼び出し」「人間による訂正」「エスカレーション」
  の 3 つに限定し、全ログの漫然とした要約はしない。同じ失敗が 2 回目なら issue でなく
  rule/sensor に昇格させる。rule 提案は特定の失敗にトレースできるものだけに絞り、追加と
  同時に既存ルールの剪定候補も提示する。

  issue 対応・実装・出荷セッションの終端 (shipping / linear-issue-driven-development の
  完了直後)、release 後、「振り返りして」「retro」「レトロして」「このセッションの学びを
  まとめて」「教訓を残して」「二度と起きないようにして」「学びを CLAUDE.md に反映して」
  「詰まったことを issue 化しておいて」のような要請、Stop hook からの自動起動、いずれ
  でも必ず起動すること。

  範囲外: セッションの単純要約 (4 分岐が不要な依頼)、CLAUDE.md 全体の監査・改善
  (claude-md-improver 等)、いま起きているバグの根本原因分析 (systematic-debugging)、
  skill 本文のチューニング (skill-builder)、コードレビュー (code-review)。出力は全て
  **提案まで** — CLAUDE.md 書き換え・golden set 追加・issue 起票は人間の承認を経る。
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
---
# session-retro

> **規律 1**: 複利は issue の数ではなく rule/sensor の蓄積から生まれる。issue は「今やらない作業」の置き場であり、再発防止の置き場ではない。
> **規律 2**: 同じ問題が 2 回起きたら、それはもう issue ではない。feedforward (rule) か feedback (sensor) を改善して再発確率を下げる。
> **規律 3**: 特定の過去の失敗にトレースできない rule はノイズ。追加するたびに剪定候補を出す (具体的な 10 ルールは汎用的な 100 ルールに勝る)。

セッションの終端で「このセッションが次のセッションを楽にするもの」を抽出して 4 分岐に振り分ける。振り返りを issue 化だけで終わらせると backlog は伸びるが同じ失敗は再発し続ける。防止は harness (rule/sensor) に、作業は issue に、検証材料は eval-case に、それぞれ正しい置き場へ送るのが本スキルの仕事。

---

## いつ使うか / 使わない場面

**使う**:

- issue 対応・実装・出荷セッションの終端 (shipping / linear-issue-driven-development の完了・エスカレーション直後)
- release 後の振り返り
- 「振り返りして」「retro」「学びをまとめて」「教訓を残して」「二度と起きないようにして」
- 「この学びを CLAUDE.md に反映して」(今セッションの学び由来の最小差分提案として)
- Stop hook / Routine からの自動起動

**使わない** (成果物で判定):

- セッションの**要約文**だけが欲しい依頼 → 通常の応答で足りる
- **CLAUDE.md 全体の監査レポート** → claude-md-improver 等の専用系
- **いま起きている失敗の原因特定** → systematic-debugging (retro は事後、debug は渦中)
- **skill の description / 本文の改訂そのもの** → skill-builder (retro は「skill を直すべき」という提案までを出す)
- **コードの findings** → code-review

---

## 入力の解決

上から順に試し、最初に使えたものをシグナル源とする:

1. **transcript JSONL**: `$CLAUDE_SESSION_ID` が定義されていれば `~/.claude/projects/<cwd の / を - に置換した slug>/<session-id>.jsonl` を探す
2. **会話コンテキスト**: transcript が読めない環境 (cloud / headless / compaction 後) では、本セッションの記憶にある範囲で行う。compaction で古い履歴が失われている場合はその旨をレポートに明記する
3. **外部証跡**: PR のコメント・CI ログ・エスカレーションコメント (対象がわかっている場合のみ)

## ワークフロー

### Step 1 — シグナル抽出 (3 源限定)

全ログを均等に読まない。以下の 3 つだけを拾う:

| シグナル | transcript での見つけ方 | なぜ高シグナルか |
|---|---|---|
| **失敗した tool 呼び出し** | `"is_error": true` の tool_result | 環境・手順・前提の欠陥が集中する |
| **人間による訂正** | assistant の出力直後に方向修正・否定・やり直し指示をする user メッセージ | 「書き手には自明、agent には不明瞭」の証拠 |
| **エスカレーション** | `needs-human` ラベル付与、`loop-escalation` コメント、打ち切り宣言 | ループの限界点そのもの |

transcript がある場合の抽出例:

```bash
jq -r 'select(.type == "user") | .. | objects | select(.is_error == true) | .content' "$TRANSCRIPT" 2>/dev/null | head -30
```

シグナル 0 件なら「学びなし」で正常終了してよい (無理に絞り出さない。空振りの retro を量産すると形骸化する)。

### Step 2 — 分岐判定

各シグナルに以下を順に問う。1 シグナルが複数分岐に落ちてよい (例: 再発失敗 → rule + eval-case):

1. **過去にも起きた failure か?** (CLAUDE.md・過去 retro・issue 履歴に痕跡があるか)
   → yes なら **issue は禁止**。rule か sensor に必ず昇格させる
2. **機械で検出できるか?** (テスト・lint・CI チェック・hook で捕まえられるか)
   → yes なら **sensor**。人間や agent の注意力に頼る rule より優先する
3. **事前の一文で防げたか?** (指示・制約・手順として書けるか)
   → yes なら **rule**。ただし「特定の失敗にトレースできる具体文」で書けるときだけ
4. **今やらない作業として切り出すべきか?**
   → yes なら **issue**。acceptance criteria + 検証方法を必ず含める (下記フォーマット)
5. **再現可能な失敗ケースとして残す価値があるか?** (skill / loop の改訂を検証できるか)
   → yes なら **eval-case** (golden set 候補)

### Step 3 — 剪定チェック (rule を 1 件でも提案する場合は必須)

rule は足す一方だと context rot でループ全体を劣化させる。追加提案と同時に:

- 対象 CLAUDE.md / skill の既存ルールを読み、**今回のセッションで一度も効いていない・現状と矛盾する・新 rule と重複する**ものを最低 1 件、削除/統合候補として挙げる
- 候補が本当に無ければ「剪定候補なし」と明記する (省略しない)

### Step 4 — 出力 (提案として)

下記フォーマットで提示する。**この時点ではどこにも書き込まない。**

### Step 5 — 承認後の handoff

| 分岐 | 承認後のアクション | 実装の担当 |
|---|---|---|
| rule | 対象 CLAUDE.md / SKILL.md / 配布 rules へ最小差分を Edit | 本スキル (差分適用のみ)。skill の構造改訂が要るなら skill-builder へ |
| sensor | テスト/CI チェックの実装 | tdd (behavioral) / tidy-first (structural) へ handoff |
| issue | `gh issue create` (下記ドラフトのまま) | 本スキル |
| eval-case | loop-ops `golden/cases/` への PR 起票 | 本スキル (merge は人間) |

**rule の宛先はクラウド実行にも届く配布層を優先する** (プロジェクトの CLAUDE.md、rulesync
の rules 等)。ローカル専用ファイル (`~/.claude/CLAUDE.md`) はそのマシンでしか効かないため、
配布層が無い場合の最後の選択肢とする。

計測イベント (`agent_run` 等) の送信は本スキルの仕事ではなく実行ラッパー / Stop hook の仕事。配線方法は [references/loop-ops-integration.md](references/loop-ops-integration.md) を参照する (loop-ops 連携がある環境でのみ)。

---

## 出力フォーマット

```markdown
# Session Retro: <セッションの一言要約>

## シグナル
| # | 種別 (tool失敗/訂正/エスカレーション) | 何が起きたか (1 行) | 再発? |
|---|---|---|---|

## 分岐
### rule (feedforward)
- 提案: <対象ファイル> に「<具体文>」を追加
  - trace: シグナル #N
  - 剪定候補: <既存ルールの削除/統合案、無ければ「なし」と明記>
### sensor (feedback)
- 提案: <テスト/lint/CI チェックの具体案> — trace: #N
### issue (deferred work)
- <下記ドラフト形式> — trace: #N
### eval-case (golden set 候補)
- <下記ドラフト形式> — trace: #N

## 見送り
- <シグナルだが分岐に値しないと判断したもの + 理由>

## 承認待ちアクション
- [ ] rule 適用 / [ ] sensor handoff / [ ] issue 起票 / [ ] eval-case PR
```

### issue ドラフト形式 (acceptance criteria 必須)

自走ループの成否は issue の入口品質で決まる。以下を欠く issue は起票しない:

```markdown
title: <動詞で始まる 1 行>
body:
## 背景
<なぜやるか。retro のどのシグナル由来か>
## Acceptance Criteria
- [ ] <機械 or 人間が判定可能な条件。「いい感じ」禁止>
## 検証方法
<どのコマンド / テスト / 操作で満たしたと判定するか>
```

### eval-case ドラフト形式

loop-ops `golden/cases/<id>.md` の形式に合わせる:

```markdown
---
id: <kebab-case>
type: canary | should-escalate | regression
source: <この retro の対象セッション / PR の URL>
target_repo: <repo>
expected_outcome: <merged | escalated:<reason> | ...>
verifier: <合否の機械判定方法>
runs: 3
---
<agent に渡す issue 本文>
```

---

## このスキルがやらないこと

- **CLAUDE.md の全体監査レポート** (今セッション由来の最小差分提案のみ)
- **skill 本文の改訂そのもの** (「直すべき」という提案と根拠まで。実装は skill-builder)
- **テスト / CI チェックの実装** (sensor の仕様提示まで。実装は tdd / tidy-first)
- **golden set への直接コミット** (PR 提案まで。merge は人間 — 改善対象の agent が自分の合格基準を書ける状態にしないため)
- **計測イベントの送信** (実行ラッパー / Stop hook の責務。references 参照)
- **承認前のあらゆる書き込み**

## リファレンス

- [references/loop-ops-integration.md](references/loop-ops-integration.md) — loop-ops (計測データストア) 連携: Stop hook での agent_run 送信、eval-case PR の出し方、エスカレーション形式。loop-ops を使う環境でのみ参照する
