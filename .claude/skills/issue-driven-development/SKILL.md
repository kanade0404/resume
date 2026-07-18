---
name: issue-driven-development
description: |
  GitHub issue に `claude:ready` ラベルが付いた 1 件を、排他ロック → 入口ゲート
  (acceptance criteria 検証) → branch → 実装 → ローカルテスト green → commit → push →
  **PR 作成まで**ヘッドレスで完遂するワークフロー。`linear-issue-driven-development`
  の GitHub 移植で、最大の差分は**イベント分割**: CI を watch せず PR 作成で終了し、
  CI 修正 (`ci-self-heal`) とレビュー対応 (`pr-review-respond`) は Actions のイベント
  トリガによる有界な反応として別途走る。acceptance criteria の無い issue は実装せず
  `ambiguous-issue` でエスカレートする (推測で実装しない)。エスカレーションは
  `needs-human` + 構造化コメント (loop-escalation:v1)、反復上限は `claude-loop:N`
  ラベルで PR に永続化する。Routine / Actions (ラベルイベント) からの起動が主経路。
  `owner/repo#123` 形式の手動再実行、「この issue やっておいて」「claude:ready の
  issue を処理して」「issue から PR まで自走して」でも必ず起動すること。範囲外:
  Linear issue (`linear-issue-driven-development`)、対話的な実装後の出荷 (`shipping`)、
  CI 修正単体 (`ci-self-heal`)、レビュー対応単体 (`pr-review-respond`)、conflict 解消
  単体 (`pr-conflict-resolver`)、PR の merge (人間ゲート)。実行環境はクラウドを想定し、
  素の `git` / `gh` / `jq` だけで動くこと。
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - Task
---
# issue-driven-development

GitHub issue 1 件を「merge 可能な PR の材料」に変えるスキル。**PR 作成が終端** — CI 緑化
とレビュー対応はイベント駆動の別反応に委ね、本スキルは長い実装セッション 1 回分だけを持つ。

> **Iron Law 1**: acceptance criteria が無い issue は実装しない。`ambiguous-issue` で止まるのが正解。
> **Iron Law 2**: CI を watch しない。PR を作ったら終わる (待ちはイベントに置き換える)。
> **Iron Law 3**: テストと CI 設定を弱める変更 (削除・skip・閾値緩和) は書かない。

## 前提となる secret / env

| 変数 | 用途 | 必須 |
|---|---|---|
| `GH_TOKEN` (or `gh auth` 済み) | clone / label / PR 操作 | yes |
| `LOOP_OPS_TOKEN` | 計測イベント送信 (emit-event.sh) | no (無ければ送信を skip) |
| `LOCK_LEASE_TTL_SECONDS` | `scripts/acquire-lock.sh` の lock lease 失効秒数 | no (既定 3600) |

## 入力契約

いずれかで issue を特定する:

- **A. トリガペイロード** (Actions の labeled イベント / Routine): `owner/repo` と issue 番号が渡される
- **B. 手動**: `owner/repo#123` 形式の識別子
- **C. 探索モード**: まず `"${CLAUDE_SKILL_DIR}/scripts/acquire-lock.sh" --reap $REPO` で失効した
  `claude:in-progress` (crash した run) を `claude:ready` へ差し戻してから、
  対象 repo で `claude:ready` ラベルの issue を作成日昇順で 1 件取る:
  `gh issue list -R $REPO --label claude:ready --state open --json number --jq 'sort_by(.number) | .[0].number'`
  reap を省略すると、クラッシュした run が握ったままの issue が永久に
  queue へ戻らない (kanade0404/skills#31 のデッドロック)。

Linear 版と違い**対象リポジトリの解決は不要** (issue が属する repo がそのまま対象)。

## 排他制御 (二重起動防止)

ラベル張り替えは atomic でないため、決定論的なロック検証を行う。手順は
[`scripts/acquire-lock.sh`](scripts/acquire-lock.sh) に切り出し済み — **ラベルは
最古検証に勝った run しか触らない**ことと、**lock に有効期限 (lease) を持たせる**
ことで、旧手順にあった 2 つの非可逆バグ (kanade0404/skills#31) を構造的に潰している:

- **queue 消失**: 旧手順は「lock コメント投稿 → ラベル張替 → 最古検証」の順で、
  敗者やクラッシュした run が `claude:in-progress` だけ外して `claude:ready` を
  永久に失っていた。新手順は「lock コメント投稿 → 最古検証 → (勝者だけ) ラベル張替」
  の順に入れ替え、**敗者・エラー終了はラベルを一切書き換えない**。
- **デッドロック**: 旧手順は「最古の `claude-lock:` コメントが勝ち」を無期限に
  適用しており、クラッシュした run のコメントが永久に勝ち続けた。新手順は
  lock コメントに `ts=<epoch>` のリース時刻を刻み、`LOCK_LEASE_TTL_SECONDS`
  (既定 3600 秒) を超えたコメントは勝者判定から除外する。加えて `claude:in-progress`
  のまま放置された issue は、次にこの issue へ触れたタイミング (単発呼び出し、
  または探索モードの `--reap` 事前スイープ) で自動的に `claude:ready` へ差し戻す。

呼び出しは agent の作業ディレクトリ (対象リポジトリの checkout) ではなく本 skill の
インストール先を指す `${CLAUDE_SKILL_DIR}` を起点にする — 対象リポジトリ側に
`scripts/acquire-lock.sh` が無い consumer 環境では cwd 相対だと解決に失敗するため:

```bash
"${CLAUDE_SKILL_DIR}/scripts/acquire-lock.sh" "$OWNER/$REPO" "$NUMBER"
```

| 終了コード | 意味 | 次のアクション |
|---|---|---|
| `0` | ロック取得成功。ラベルは `claude:in-progress` に変わっている | 実装に進む |
| `3` | 既に終端 (`claude:done` / `claude:failed`) | 何もせず次の issue へ (探索モードなら次候補) |
| `4` | 他の生存中の run が保持中 (lease 未失効) | 何もせず次の issue へ |
| `5` | 最古検証に敗北 | 何もせず次の issue へ (自分の lock コメントは監査用に残る) |
| `1` / `2` | 予期しない失敗 / 使用法エラー | ラベルは script 内の `trap` が復元済み。ログを見てリトライ判断 |

ラベルが repo に無ければ script が `gh label create` で作る (`claude:ready` /
`claude:in-progress` / `claude:done` / `claude:failed` / `needs-human` /
`claude-loop:1..3`)。`claude-loop:N` はこの後の CI 修正反応 (`ci-self-heal`)
が付け替える前提のラベルで、事前作成しておかないと fresh な consumer repo で
最初の CI 失敗反応が失敗する。

**この trap が保護しないもの**: script 自身は `exit 0` で戻った後、実装フェーズ
(この SKILL の 3〜5 節) の異常終了までは面倒を見ない。そこで死んだ run の復旧は
lease 失効 + 次回 `--reap` (または該当 issue への再アクセス時の自動 reclaim) に
委ねている。想定される正常系はあくまで `## エスカレーション` — 継続不能を検知
できた場合は必ずそちらで `needs-human` + `claude:failed` に明示遷移すること。

Actions 起動の場合はさらに workflow 側の `concurrency` グループが二重起動を防ぐ
([references/actions-wiring.md](references/actions-wiring.md))。

## 入口ゲート — acceptance criteria 検証

issue 本文に以下が読み取れるか確認する:

- **Acceptance Criteria**: 機械または人間が判定可能な完了条件 (「いい感じ」「今風」は不可)
- **検証方法**: どのコマンド / テスト / 操作で満たしたと判定するか (明示が無くても AC から
  自明に導けるなら可)

読み取れない場合は**実装に入らず**エスカレーション (reason: `ambiguous-issue`) する。
これは失敗ではなく、issue の入口品質の問題を上流に返す正常動作。**推測でスコープを
埋めて実装を始めることを禁じる** — 未指定の細部は実行毎に揺れ、レビュー不能な PR を生む。

## 主要ステップ

### 1. リポジトリ取得と branch

```bash
gh repo clone "$OWNER/$REPO" repo && cd repo   # Actions 上で checkout 済みならスキップ
BASE=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git switch -c "claude/issue-${NUMBER}-<slug>" "origin/$BASE"
```

slug は issue タイトルから生成 (小文字・ハイフン・40 字以内)。

### 2. 実装方針

- リポジトリの `CLAUDE.md` / `AGENTS.md` / `README.md` を読み、規約・テスト/lint コマンドを確認
- AC を満たす**最小変更**を設計する。機能を勝手に広げない
- 解釈の余地があった点は PR description に書く (issue に質問コメントは投げない —
  ヘッドレスなので返答を待てない。判断できないほど曖昧なら入口ゲートに戻って escalate)

### 3. 実装 + テスト

- behavioral change は `tdd` の規律 (先に失敗するテスト)、structural は `tidy-first` に従う
- リポジトリにテストがあれば必ずローカル実行し、green を確認してから commit
- テストが無ければビルド・型チェック・lint を通す
- **既存テストの削除・skip 化・アサーション緩和・CI 設定の弱体化はしない** (Iron Law 3)。
  テストが間違っていると判断した場合はその根拠を PR に書き、テスト修正だけの commit に分離する

### 4. commit / push / PR

```bash
git add <変更ファイルを明示>   # git add -A は使わない
git commit -m "<repo 規約に従う subject>

<why を説明する body>

Refs: #${NUMBER}"
git push -u origin "claude/issue-${NUMBER}-<slug>"
gh pr create --title "<subject> (#${NUMBER})" --body "$(printf '## Summary\n- ...\n\nCloses #%s\n\n## 解釈と判断\n- <AC の解釈で自分が決めた点>\n\n## Test plan\n- [x] <実行したテスト/検証>\n' "$NUMBER")"
```

- PR body の `Closes #N` は必須 (issue 自動クローズ + 計測の issue 紐付けの両方に使われる)
- issue ラベルに `claude:draft` があれば `--draft`

### 5. 終端処理 — ここで終了する

- PR URL を issue にコメントし、`claude:in-progress` → `claude:done` に張り替える
  (done = 「PR 作成まで完了」の意。merge ではない)
- **CI を watch しない。レビューを待たない。** 以降は次の反応が引き継ぐ:

| イベント | 反応 (別トリガで起動) | 上限 |
|---|---|---|
| CI 失敗 (`workflow_run`) | `ci-self-heal` — 修正 push ごとに `claude-loop:N` を進める | N=3 で escalate |
| レビューコメント | `pr-review-respond` | 5 周で escalate |
| conflict | `pr-conflict-resolver` | — |

- 反応側の no-progress 検出: 直前の自分の修正と同一ファイル・同一失敗なら反復せず escalate

## エスカレーション

どの段階でも継続不能になったら:

1. `needs-human` ラベルを付け、`claude:in-progress` を外し `claude:failed` を付ける
2. issue (PR があれば PR) に構造化コメントを投稿する:

````markdown
<状況の自由文: 何を試し、なぜ止まるのか>

<!-- loop-escalation:v1 -->
```json
{"reason": "<enum>", "detail": "<1-2 文>", "attempts": <n>, "session_id": "<取れれば>", "next_action_hint": "<人間の最短の一手>"}
```
````

reason は次の enum から: `budget-exceeded / max-turns / ci-3-fail / review-5-rounds /
no-progress / ambiguous-issue / repo-unresolvable / conflict / security-block / other`。
`LOOP_OPS_TOKEN` があれば `escalated` イベントも送信する (無ければコメントのみで良い —
PR クローズ時の収集がフォールバックで拾う)。

## ガードレール

- **destructive git 禁止**: `reset --hard` / `push --force*` / `rebase` を使わない。修正は常に追加 commit
- **secrets を読まない・書かない・ログに出さない**: `.env*`, `*.tfvars`, 鍵類
- **PR を merge しない**: merge は常に人間ゲート
- **`.github/workflows/` を変更しない**: CI の変更が必要なら escalate (security-block)
- **予算上限は起動側が持つ**: runner は `--max-turns` / `--max-budget-usd` を必ず設定する
  (超過時の subtype がそのまま escalation reason になる)。設定方法は references 参照
- **他人の branch に触らない**: 常に新規 `claude/issue-*` branch

## リファレンス

- [references/actions-wiring.md](references/actions-wiring.md) — トリガ配線 (claude-code-action ラベル起動 / Routines)、concurrency・自己発火ガード・SHA ピン留め・最小権限、`claude-loop:N` の進め方、`agent_run` 計測イベントの送信。**配線作業をする時だけ読む**
