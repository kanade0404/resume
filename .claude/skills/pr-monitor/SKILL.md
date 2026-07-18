---
name: pr-monitor
description: >-
  自分が作成・出荷した PR の状態 (open / merged / closed) を、merge または close
  に至るまで長期間ポーリングで監視するスキル。`shipping` が merge-ready で停止した後の終端監視として、PR の最終決着 (merge
  / close) を完了シグナルとして待ち、検出したら `retro` を自動起動する。待機手段は環境に依存しないよう優先順で選ぶ —
  `/schedule` (cron) があれば登録して main を解放、無ければ `ScheduleWakeup` で self-pace
  poll、どちらも不可なら `--check-only` の手動再実行を案内する。状態は consumer 側の gitignore
  パスに永続する。`shipping` 完了直後・`gh pr create` 直後・「PR
  監視して」「マージされるまで見張って」「マージ/クローズしたら振り返りまで回して」のような要請で必ず起動する。CI 完了までの短時間監視は
  `ci-self-heal` (秒〜分)、本スキルは merge / close までの長時間監視 (分〜時間〜日) で責務分離する。PR の merge
  操作そのものは行わない — 人間 (または別の自動化) が merge / close した事実を待つだけ。
allowed-tools:
  - Read
  - Write
  - Bash(gh pr view *)
  - Bash(gh pr list *)
  - Bash(git rev-parse *)
  - Bash(git branch *)
  - ScheduleWakeup
  - Skill
  - Task
---
# pr-monitor — PR ライフサイクル終端監視

> **責務境界**: `ci-self-heal` は CI 完了までの短時間監視。本スキルは **merge / close までの長時間監視**。PR を merge しない — 決着の事実を待ち、決着したら `retro` に渡す。

## いつ起動するか

- `shipping` が merge-ready で停止した直後 / `gh pr create` 直後
- 「PR 監視して」「マージされるまで見張って」「決着したら retro まで」

逆に **起動しない**:
- CI 緑化までの監視 (`ci-self-heal`)
- PR の merge / close 操作自体 (人間または別自動化の仕事)
- 既に merge / close 済みの PR の事後対応 (直接 `retro`)

## 入力

| 引数 | 内容 |
|---|---|
| (省略) | 現在ブランチに紐づく PR を auto-detect |
| `<PR番号>` | 監視対象 PR を明示 |
| `--check-only` | cron / 再入時の 1 回判定モード (新規登録せず状態確認のみ。決着なら retro 起動) |

## ワークフロー

### Step 1 — 対象 PR を特定

```bash
gh pr view <PR or 省略> --json number,state,url,headRefName -q '.'
```

state が既に `MERGED` / `CLOSED` なら **Step 5 (retro 起動) へ直行** — 状態ファイルも待機手段も作らない (Step 2〜4 は監視が要るときだけ通る。決着済みに state ファイル更新は不要)。`OPEN` なら Step 2 へ継続。

### Step 2 — 状態を永続化

consumer 側の **gitignore 前提パス** `.claude/.pr-monitor/PR-<number>.yml` に記録する (リポを汚さない。配布先で `.claude/.pr-monitor/` を gitignore 推奨):

```yaml
pr_number: <n>
url: <url>
branch: <headRefName>
state: OPEN
created_at: <ISO8601>
last_checked_at: <ISO8601>
monitor_mode: <cron | wakeup | manual>   # Step 3 で採用した待機手段。再入時に何をすべきか判る
schedule_id: <cron/routine の id | null>  # cron 手段のとき。決着時の解除対象 (無いと何を消すか判らない)
origin_transcript: <当該 feature/ship を実際に行ったセッションの transcript パス>
```

- `origin_transcript` は **初回登録時の現セッション transcript** を入れる (retro が解析すべきは「PR を生んだ作業」。後の check-only 監視セッションではない)。パス特定は `retro` Step 1 と同じ slug 規則 (`pwd` の `/` `.` を `-` 置換 → `~/.claude/projects/<slug>/` 最新 `*.jsonl`)。
- `--check-only` で再入した時はこのファイルを Read し、`last_checked_at` だけ更新する (新規登録せず、`monitor_mode` / `schedule_id` / `origin_transcript` は保持)。

### Step 3 — 待機手段を優先順で選ぶ

登録前に**利用可能なものを確認**し、使えるものを上から選ぶ (環境で可否が変わる):

| 優先 | 手段 | 動作 | state に書く |
|---|---|---|---|
| 1 | `/schedule` (cron / routines) | `pr-monitor <n> --check-only` を定期実行する cron を登録し、**main を解放**。ポーリング間隔は 30 分目安 | `monitor_mode: cron`, `schedule_id: <登録した id>` |
| 2 | `ScheduleWakeup` | cron が無ければ session 内で `delaySeconds≈1800` を渡して self-pace poll。起床ごとに Step 4 を実行し、未決着なら再度 `ScheduleWakeup` | `monitor_mode: wakeup`, `schedule_id: null` |
| 3 | 手動 | どちらも不可なら「`pr-monitor <n> --check-only` を後で再実行してください」と案内して終了 | `monitor_mode: manual`, `schedule_id: null` |

`ScheduleWakeup` の `prompt` には `pr-monitor <n> --check-only` を渡し、次回起床で本スキルに戻れるようにする。採用した `monitor_mode` (と cron なら `schedule_id`) を **必ず state に書く** — 再入時の OPEN ブランチはこれを読まないと「次に wakeup を予約すべきか」「決着時に何の cron を解除するか」が判らない。

### Step 4 — 状態判定 (毎ポーリング)

```bash
gh pr view <n> --json state -q '.state'
```

state ファイルの `monitor_mode` を読んで分岐する (再入時は `--check-only` 引数だけでは手段が判らないため):

| state | 次の手 |
|---|---|
| `OPEN` | `last_checked_at` 更新。`monitor_mode: cron` なら何もせず終了 (次回 cron 起床に任せる)、`monitor_mode: wakeup` なら再度 `ScheduleWakeup` を予約、`manual` なら手動再実行を案内 |
| `MERGED` / `CLOSED` | **決着**。状態ファイルの `state` を更新。`monitor_mode: cron` なら `schedule_id` の cron を解除 (one-shot で消さないと check-only が鳴り続け `retro` が再起動し続ける)。Step 5 へ |

### Step 5 — 決着したら retro

`Skill(retro)` を起動し、「PR #<n> が <merged/closed> した」コンテキストと **state の `origin_transcript` パス** を渡す。これにより retro は「最新の transcript」ではなく **PR を生んだ元セッション** を解析する (check-only の監視セッションを誤って解析しない)。`origin_transcript` が未記録 (Step 1 直行など) のときだけ retro 既定の最新 transcript 選択にフォールバックする。retro が改善提案 (提案のみ) を出して pr-monitor は完了。

## 出力フォーマット

```markdown
# pr-monitor: PR #<n> (<branch>)

## 監視
- state: <OPEN→…→MERGED/CLOSED>
- 手段: <cron / ScheduleWakeup / 手動>
- last_checked_at: <ISO8601>

## 決着
- <MERGED <SHA> / CLOSED / 監視中 (次回 <手段>)>
- Next: <retro 起動済み / 次ポーリング予定 / 手動再実行案内>
```

## 出力する成果物 / 出力しない成果物

### 出力する成果物
- **状態ファイル** `.claude/.pr-monitor/PR-<n>.yml` (consumer gitignore 前提)
- **監視サマリ** (state 遷移 + 採用した待機手段 + 次アクション)
- **決着時の retro 起動**

### 出力しない成果物
- **PR の merge / squash / close 操作**: 決着は人間または別自動化。本スキルは事実を待つだけ。
- **CI ログ取得 / 修復**: `ci-self-heal` の領域。本スキルは state だけ見る。
- **foreground の長時間 sleep / watch**: main をブロックしない。cron / ScheduleWakeup に委ねる。
- **リポ追跡されるログ**: 状態は gitignore パスのみ。

## 既知の限界
- **cron の可否は環境依存**: `/schedule` が無い環境では ScheduleWakeup (session 生存中のみ) か手動にフォールバックする。
- **session 終了で ScheduleWakeup は途切れる**: 長期 (日単位) 監視は cron 手段が前提。手段 2 は session が生きている間だけ。
- **マルチモデル未検証**: trigger eval は本セッションのモデルのみ。
