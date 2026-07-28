---
name: pr-monitor
description: >-
  自分が作成・出荷した PR を merge / close まで長期間ポーリングで監視し、放置中に起きる CI
  失敗と新規レビューコメントへの対応までを回すスキル。毎ポーリングで同梱スクリプト `prm status <PR>` により state / head
  SHA / 失敗・pending checks / 未解決レビュースレッド全量を 1 回で観測し、`checks.failing`
  に未対応の新規失敗があれば `ci-self-heal` を、`known_comment_ids` に無い新規の未解決レビュースレッドがあれば
  `pr-review-respond` を、それぞれ subagent (Task) で dispatch する。新規分の author が全て
  CodeRabbit なら、`pr-review-respond` への契約入力で修正適用を `coderabbit:autofix` に委譲する
  (plugin がある環境のみ)。呼出側 (`shipping` Phase 6 / main セッション) は本スキル自体も subagent で
  dispatch し、main を長時間監視で塞がない。ポーリング間隔は状態変化なしで指数バックオフ (60 秒起点、上限 1800 秒)、新規
  push・新規失敗・新規コメント・決着のいずれかがあれば 60 秒にリセットする。決着 (MERGED / CLOSED) を検出したら `retro`
  を自動起動する。待機手段は `/schedule` (cron) → `ScheduleWakeup` → 手動 `--check-only`
  の優先順で環境依存を吸収する。`shipping` 完了直後・`gh pr create` 直後・「PR
  監視して」「マージされるまで見張って」「マージ/クローズしたら振り返りまで回して」「CI
  とコメントも見張って対応まで回して」のような要請で必ず起動する。CI 完了までの短時間監視や修復の実体は `ci-self-heal`、コメント対応の実体は
  `pr-review-respond` (CodeRabbit 起因は `coderabbit:autofix`) が持ち、本スキルは検知と
  dispatch のループ制御に閉じる。PR の merge 操作そのものは行わない — 決着の事実を待つだけ。
allowed-tools:
  - Read
  - Write
  - Bash(gh pr view *)
  - Bash(gh pr list *)
  - Bash(git rev-parse *)
  - Bash(git branch *)
  - Bash(bash *prm *)
  - Bash(gh pr comment *)
  - ScheduleWakeup
  - Skill
  - Task
---
# pr-monitor — PR ライフサイクル終端監視 + 放置防止ループ

> **責務境界**: 本スキルの責務は PR の **決着 (merge / close) までの長時間監視** と、毎ポーリングでの **CI failure / 未解決レビュースレッドの検知と subagent dispatch のループ制御**。修復・対応の実体は持たない — CI 修復は `ci-self-heal`、レビューコメント対応は `pr-review-respond` (CodeRabbit 起因の修正適用はさらに `coderabbit:autofix` に委譲) が担う。PR の merge / close 操作そのものも行わない。

## いつ起動するか

- `shipping` が merge-ready で停止した直後 / `gh pr create` 直後
- 「PR 監視して」「マージされるまで見張って」「決着したら retro まで」
- 「CI とコメントも見張って対応まで回して」(検知 + dispatch まで含めた監視要求)

逆に **起動しない** (実行の実体は別スキルへ):
- CI 失敗の root cause 特定・修正そのもの (`ci-self-heal`)
- レビューコメントへの応答・修正コミットそのもの (`pr-review-respond`。CodeRabbit 起因の修正適用は `coderabbit:autofix`)
- PR の merge / close 操作自体 (人間または別自動化の仕事)
- 既に merge / close 済みの PR の事後対応 (直接 `retro`)

## 起動形態

merge / close までの監視は分〜時間〜日のオーダーで、main のターンを占有すると他の作業が進まない。そのため呼出側 (`shipping` Phase 6 の監視設置フェーズ、または対話セッションの main) は本スキルを **Task で subagent dispatch** して呼び、main を即座に解放する。

dispatch された subagent 内部でも常駐しない。1 回の起動で行うのは次のどちらかだけ:

- **cron 登録** (Step 3 の手段 1 が使える場合): `/schedule` に `pr-monitor <n> --check-only` を登録して即座に終了する。以降のポーリングは cron が都度この skill を再起動する。
- **check-only 1 回判定**: cron / 前回の `ScheduleWakeup` から `--check-only` で再入した場合、Step 4 の 1 回分の判定だけ行い、次の待機を予約 (cron 経路なら何もせず) して終了する。

「pr-monitor という 1 プロセスが張り付いて監視し続ける」構造ではなく、**cron や ScheduleWakeup が短命な subagent を繰り返し起こす**構造にする。`ScheduleWakeup` 手段のときも 1 起床 = 1 subagent 終了に閉じ、session 内で foreground loop を回さない。

## 入力

| 引数 | 内容 |
|---|---|
| (省略) | 現在ブランチに紐づく PR を auto-detect |
| `<PR番号>` | 監視対象 PR を明示 |
| `--check-only` | cron / 再入時の 1 回判定モード (新規登録せず状態確認のみ。決着なら retro 起動) |

## 同梱スクリプト `scripts/prm`

`gh api` / `gh pr checks` を都度 inline で叩くと permission prompt が重なる上、未解決スレッド全量取得の cursor pagination や色付き `gh` 出力による `jq` 破壊 (`rules/bash-and-api-discipline.md` 参照) など落とし穴が多い。本スキルはこれらを `scripts/prm` に閉じ込め、**単一エントリポイントからのみ呼び出す** (`pr-review-respond` の `prr` と同じ設計)。呼び出しは常に:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/prm" <subcommand> <pr>
```

`allowed-tools` の `Bash(bash *prm *)` で auto-grant されるため、consumer 側の permission 追加は不要。

| subcommand | 役割 |
|---|---|
| `prm status <pr>` | state / head SHA / 失敗・pending checks / 未解決レビュースレッド全量を 1 つの安定 JSON で返す。毎ポーリングで呼ぶのはこれ 1 回だけ |
| `prm unresolved <pr>` | 未解決レビュースレッド全量のみ `{unresolved_count, threads}` |
| `prm state-init <pr> <json-file>` | 監視 state ファイル `.claude/.pr-monitor/PR-<pr>.json` を新規作成する (既存があれば警告を stderr に出しつつ上書き)。初回登録でのみ使う |
| `prm state-merge <pr> <json-file>` | 既存 state を読み、`<json-file>` の内容を `. + $patch` で shallow merge して書き戻す read-modify-write。**単一 writer 前提の簡易経路** — patch の全フィールドが scalar (例: `state` の単一遷移) の時だけ安全に使える。配列フィールド (`known_comment_ids` / `known_failing_checks` / `escalations` / `cycle_ledger`) を含む patch には使わない (下記 `state-apply` 参照。理由は次項) |
| `prm state-apply <pr> <jq-filter-file>` | `state-init`/`state-merge` と同じ per-PR lock を取得した**まま**既存 state を読み、`<jq-filter-file>` の jq プログラムを (`.` にその state を束縛して) 適用し、結果が JSON object であることを検証してから書き戻す read-apply-write。配列フィールドを含む更新は **これを使う** — `state-get` (lock 外) で読んだ内容から呼び出し側が完成済み配列を組み立てて `state-merge` に渡す旧プロトコルは、2 つの `--check-only` 実行が重なった時に「両者が同じ古い base から別々の配列を計算し、後勝ちの `state-merge` が shallow merge で先勝ちの配列を丸ごと上書きする」ロスト update を起こす (lock は書き込みの直列化だけを保証し、lock **外**で行われた読み取り自体の陳腐化は防げない)。`state-apply` は読み取りも lock の内側で行うため、filter 自体が `.known_comment_ids = ((.known_comment_ids + [123]) \| unique)` のように**その場の最新 state を起点に**追記・prune を表現でき、2 つの重なった呼び出しがそれぞれ別の要素を追記しても両方生き残る (下記 Step 2/4 参照) |
| `prm state-get <pr> [key]` | state 全体 (または `.<key>`) を出力。state ファイルが無ければ exit 1 |

`state-*` は `.claude/.pr-monitor/PR-<pr>.json` に対するローカルファイル操作のみで完結し、`gh` / GitHub API には一切触れない。

`prm status` の出力スキーマ:

```json
{
  "pr": {"state": "OPEN", "merged_at": null, "url": "...", "branch": "...", "head_sha": "..."},
  "checks": {"failing": [{"name": "...", "bucket": "fail", "link": "...", "workflow": "..."}], "pending": ["..."]},
  "unresolved_count": 3,
  "unresolved_threads": [
    {"thread_id": "...", "is_outdated": false, "comment_id": 123, "author": "coderabbitai", "path": "...", "url": "...", "created_at": "...", "body_head": "..."}
  ]
}
```

決定性の担保 (`prr` と同じ規律):
- GraphQL `reviewThreads` は cursor pagination で最後まで取得する。1 ページ (最大 100) で打ち切ると未解決スレッドを見落とす
- `gh` の TTY 色付けはスクリプト冒頭で無効化する (`GH_FORCE_TTY=` `NO_COLOR=1` `CLICOLOR_FORCE=0`)。色付き出力はパイプ先の `jq` を静かに壊す
- 出力は `jq -S` でキー順を安定化し、Step 4 の `known_*` 差分検知が出力順のブレで誤動作しないようにする

## ワークフロー

### Step 1 — 対象 PR を特定

```bash
gh pr view <PR or 省略> --json number,state,url,headRefName -q '.'
```

PR 番号の auto-detect (引数省略時) は `gh pr view` のまま行う — `prm` は単一 PR 番号を要求する設計で、番号解決そのものは担わない。番号が判明したら以降 (Step 2〜4) は `prm` 経由に切り替える。

state が既に `MERGED` / `CLOSED` なら **Step 5 (retro 起動) へ直行** — 状態ファイルも待機手段も作らない (Step 2〜4 は監視が要るときだけ通る)。`OPEN` なら Step 2 へ継続。

### Step 2 — 状態を永続化

consumer 側の **gitignore 前提パス** `.claude/.pr-monitor/PR-<number>.json` に記録する (リポを汚さない。配布先で `.claude/.pr-monitor/` を gitignore 推奨)。このパスは常に **repo root からの絶対パス**として解決される (`prm` が内部で `git rev-parse --show-toplevel` を起点に組み立てる — cwd 相対ではない)。subdirectory から `prm` を起動しても repo 直下の同じ state ファイルを読み書きするため、cron/wakeup の再入がどの cwd から起きても一貫する (PR #78 レビュー指摘: cwd 相対のままだと subdirectory 起動時に `subdir/.claude/.pr-monitor/` ができ、この gitignore パスの対象外になって誤コミットしうる)。

**このファイルは `prm state-init` / `prm state-merge` / `prm state-apply` 経由でのみ作成・更新する — Write ツールで直接書いてはならない。** 理由 (F1): 長時間の check-only 自己再入ループでは、モデルが「自分が直前のターンで書いた内容」を実ディスク上の内容と同一視し、次の更新前の Read を省略する傾向が実測されている (retro 分析: state 更新 23 回中 22 回が Read を経ない全文 Write だった)。read-modify-write を `prm` 側に構造的に閉じ込めることで、モデルの Read 規律に依存せずこの抜けを構造的に防ぐ。同じ read-modify-write は 2 プロセスが同時に走ると素朴には成立しない (両者が同じ base を読み、独立に merge した結果を `mv` し合うと後勝ちで前者の更新が消える) ため、`state-init`/`state-merge`/`state-apply` 自体が `mkdir` ロックで直列化する (上表参照)。ただし lock による write の直列化だけでは配列フィールドのロスト update は防げない — `state-merge` 用の patch を lock **外**の `state-get` から組み立てるプロトコルだと、2 つの重なった実行がそれぞれ古い base から別々の配列を計算し、後勝ちの shallow merge が先勝ちの追記を握りつぶす (PR #78 レビュー指摘)。配列フィールドを含む更新に `state-apply` を使うのはこのため — 読み取り自体を lock の内側に置き、追記・prune を filter として表現する。

```json
{
  "pr_number": 0,
  "url": "<url>",
  "branch": "<headRefName>",
  "state": "OPEN",
  "created_at": "<ISO8601>",
  "last_checked_at": "<ISO8601>",
  "monitor_mode": "<cron | wakeup | manual>",
  "schedule_id": "<cron/routine の id | null>",
  "origin_transcript": "<当該 feature/ship を実際に行ったセッションの transcript パス>",
  "known_comment_ids": [],
  "known_failing_checks": [],
  "last_head_sha": "<sha>",
  "poll_interval_seconds": 60,
  "escalations": [],
  "cycle_ledger": []
}
```

JSON はインラインコメントを書けないため、各フィールドの意味をここにまとめる:
- `monitor_mode` / `schedule_id`: Step 3 で採用した待機手段。再入時に何をすべきか、決着時に何を解除すべきか (cron の場合) を判別する
- `known_comment_ids` / `known_failing_checks`: dispatch 済みの対象。多重 dispatch 防止。`known_failing_checks` は複数 workflow に同名 job があるリポジトリで別インシデントを同一視しないよう、`gh pr checks --json` が返す `workflow` を含めた `"<workflow>/<name>"` の組で key する
- `last_head_sha`: 前回観測 head。新 push 検知 (バックオフ reset、`known_failing_checks` クリア、`escalations[kind=ci-halted]` クリアに使う)。この値の更新は Step 4 分岐 2 の CAS filter 経由でのみ行う — 他の分岐 (最終 apply 含む) では触れない (理由は分岐 2 参照)
- `poll_interval_seconds`: 指数バックオフの現在値
- `escalations`: `{kind: ci-halted|review-stuck, key: <"<workflow>/<name>"|comment_id>, at: <ISO8601>}` の配列。needs-human コメントを投稿済みの事象。同じ (kind, key) への再投稿を防ぐ dedup 台帳。`key` は `kind: ci-halted` では文字列、`kind: review-stuck` では `known_comment_ids` / `unresolved_threads[].comment_id` と同じ JSON 数値で保持する (型を揃えないと後述のエスカレーション分岐の prune 突合が壊れる)
- `cycle_ledger` (F7): 各ポーリングサイクルの要約を 1 行ずつ積む配列。**サイクル履歴を保持する唯一の場所** — ScheduleWakeup の prompt に累積履歴を再掲しない (詳細は Step 3 末尾「wakeup prompt 生成規約」)

- `origin_transcript` は **初回登録時の現セッション transcript** を入れる (retro が解析すべきは「PR を生んだ作業」。後の check-only 監視セッションではない)。パス特定は `retro` Step 1 と同じ slug 規則 (`pwd` の `/` `.` を `-` 置換 → `~/.claude/projects/<slug>/` 最新 `*.jsonl`)。
- 初回登録は上記スキーマを一時 JSON ファイルに書き、`prm state-init <n> <一時json>` に渡して行う。`known_comment_ids: []` / `known_failing_checks: []` / `escalations: []` / `cycle_ledger: []` / `last_head_sha: <Step1 で観測した head_sha>` / `poll_interval_seconds: 60` で開始する。
- `--check-only` で再入した時は `prm state-get <n>` で現在の state を**表示目的で**読む (今回のポーリングの判定材料 — `checks.failing` / `unresolved_threads` との突き合わせに使う)。この読み取り結果の `last_head_sha` が Step 4 冒頭で言う「前回スナップショット」であり、分岐 2 の CAS filter が比較基準にする `$snapshot_head` の値そのものになる (詳細は分岐 2 参照)。Step 4 の判定後の実際の書き戻しは、この読み取り結果をそのまま patch の base にしない — **配列フィールド (`known_comment_ids` / `known_failing_checks` / `escalations` / `cycle_ledger`) を 1 つでも含む更新は必ず `prm state-apply <n> <一時filter>` を使う**。一時ファイルには JSON patch ではなく jq プログラムを書く。例:

  ```jq
  .known_failing_checks = ((.known_failing_checks + [$key]) | unique)
  | .last_checked_at = "2026-07-09T12:00:00Z"
  | .poll_interval_seconds = 120
  | .cycle_ledger += ["new failing check dispatched"]
  ```

  呼び出しは `prm state-apply <n> <filter> --arg key "<workflow>/<name>"` — `<workflow>/<name>` は GitHub 側の自由形式文字列で quote / backslash / 改行を含みうるため、filter 本文へのリテラル埋め込みではなく `--arg` で束縛した `$key` を参照する (詳細と理由は分岐 4 を参照)。`last_head_sha` の更新はこの種の汎用 filter に混ぜず、分岐 2 専用の CAS filter でのみ行う (下記)。

  `.known_failing_checks` や `.cycle_ledger` の右辺はこの filter 自身が `.` (= lock 内で読み直された最新 state) を起点に計算するため、`state-get` で読んだ古い値を外部で組み立てて上書きする必要がない — 2 つの `--check-only` 実行が重なっても、それぞれの filter が最新 state に対して追記するので両方の更新が残る (`state-apply` の項参照)。`monitor_mode` / `schedule_id` / `origin_transcript` のようなフィールドは filter で触れなければ既存値がそのまま保持される。スカラーのみの更新 (例: `state` 単独の遷移) は引き続き `prm state-merge` で構わない。

### Step 3 — 待機手段を優先順で選ぶ

登録前に**利用可能なものを確認**し、使えるものを上から選ぶ (環境で可否が変わる):

| 優先 | 手段 | 動作 | state に書く |
|---|---|---|---|
| 1 | `/schedule` (cron / routines) | `pr-monitor <n> --check-only` を定期実行する cron を登録し、**main を解放**。間隔変更のコストが高いため固定 30 分のままでよい (指数バックオフは効かない) | `monitor_mode: cron`, `schedule_id: <登録した id>` |
| 2 | `ScheduleWakeup` | cron が無ければ session 内で `delaySeconds` に state の `poll_interval_seconds` を渡して self-pace poll。起床ごとに Step 4 を実行し、未決着なら更新後の `poll_interval_seconds` で再度 `ScheduleWakeup` | `monitor_mode: wakeup`, `schedule_id: null` |
| 3 | 手動 | どちらも不可なら「`pr-monitor <n> --check-only` を後で再実行してください」と案内して終了 | `monitor_mode: manual`, `schedule_id: null` |

手段 3 (`manual`) は監視プロセスを何も残さない — 後続の CI 失敗・新規レビューコメント・merge/close を検知する主体が居なくなる。呼出側 (`shipping` Phase 6) はこれを監視設置の成功として扱わず、SHIPPED ではなく `MONITOR_UNAVAILABLE` として人間に引き継ぐ。

`ScheduleWakeup` の `prompt` には `pr-monitor <n> --check-only` を渡し、次回起床で本スキルに戻れるようにする。採用した `monitor_mode` (と cron なら `schedule_id`) を **必ず state に書く** — 再入時の OPEN ブランチはこれを読まないと「次に wakeup を予約すべきか」「決着時に何の cron を解除するか」が判らない。

ポーリング間隔は state の `poll_interval_seconds` で管理する (基準 60 秒、上限 1800 秒)。この値の更新ルールは Step 4 の末尾で扱う。

#### wakeup prompt 生成規約 (F7)

`ScheduleWakeup` の `prompt` に書くのは次の 2 つ **だけ**:
1. `pr-monitor <n> --check-only` (次回起床で本スキルに戻るための固定コマンド)
2. state ファイルパス (`.claude/.pr-monitor/PR-<n>.json`) と、直近 1 サイクル分の差分要約 (例: 「前回 poll: checks 全 green、新規未解決スレッド 0、interval 60→120s」)

**累積の進捗ナラティブ (cycle ledger) を prompt に手打ち再掲しない。** サイクル数に比例して prompt が肥大化し、起床のたびに同じ履歴を読み直す context 浪費になる (F7: 累積 ledger の毎回再掲がこの肥大の原因だった)。サイクル履歴は state の `cycle_ledger` に `prm state-apply` (`.cycle_ledger += ["..."]`) で 1 行ずつ積むだけにとどめ、必要になれば起床後に `prm state-get <n> cycle_ledger` で読み出す — prompt 自体には転記しない。`cycle_ledger` は配列フィールドのため `state-merge` ではなく `state-apply` を使う (前掲の理由)。

### Step 4 — 状態判定 (毎ポーリング)

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/prm" status <n>
```

を 1 回叩き、返った JSON と state ファイルの前回スナップショットを突き合わせて、次の順で分岐する:

1. `pr.state` が `MERGED` / `CLOSED` → **決着候補**。ここは無条件の scalar 上書き (`state-merge`) にしない — 2 つの `--check-only` invocation が同時に決着を観測すると、両方が無条件に `state` を書き換え、両方が「以下は評価しない」を通過して Step 5 (retro 起動) と cron 解除を二重に実行してしまう (PR #78 レビュー指摘、comment 3552918951: 決着時の retro 二重起動)。そのため決着遷移も CAS (`state-apply`) で claim する:

   ```jq
   if .state == "OPEN" then
     .state = $terminal
   else
     error("already-settled")
   end
   ```

   呼び出しは `prm state-apply <n> <filter-file> --arg terminal "<MERGED|CLOSED>"` (`$terminal` には今回の `prm status` が返した `pr.state` の値をそのまま渡す)。`state-apply` は lock 内で読み直した最新 state に対して評価するため:

   - CAS が **成功** (exit 0) した invocation — on-disk `state` を初めて `OPEN` から `<MERGED|CLOSED>` へ遷移させた側 — だけが `monitor_mode: cron` の場合の `schedule_id` cron 解除と Step 5 (retro 起動) を行う。
   - CAS が **失敗** (exit 1, `already-settled`) した invocation は、既に他の invocation が決着処理 (cron 解除 + retro 起動) 済みと判断し、cron 解除も retro 起動も行わずそのまま終了する。

   勝敗いずれの場合も **ここで判定終了** (以下 2〜8 は評価しない) — 勝者は Step 5 へ、敗者は何もせず終了する。
2. **新 push 検知は on-disk `last_head_sha` への CAS で行う** (ローカルの「前回スナップショットとの比較」だけで新 push の有無を決めない — 比較結果を CAS filter の書き込み条件そのものに埋め込み、on-disk 値に対して直接判定させる)。Step 2 で読んだ「前回スナップショット」(`--check-only` 再入時の `prm state-get` 結果) の `last_head_sha` を `$snapshot_head` として保持し、今回 `prm status` が返した `head_sha` を `$observed_head` として、他の何より先に次の filter を `prm state-apply <n> <filter-file> --arg snapshot_head "<前回スナップショットの last_head_sha>" --arg observed_head "<head_sha>"` で試みる:

   ```jq
   if .last_head_sha == $snapshot_head and $snapshot_head != $observed_head then
     .known_failing_checks = []
     | .escalations = (.escalations | map(select(.kind != "ci-halted")))
     | .last_head_sha = $observed_head
   else
     error("head already advanced or no change")
   end
   ```

   `state-apply` は lock 内で読み直した最新の `.last_head_sha` に対してこの filter を評価するため、判定は常にその瞬間の on-disk 値に対して行われる。条件は 2 つを同時に見る: `$snapshot_head != $observed_head` は「このポーリングで新 push を観測したか」、`.last_head_sha == $snapshot_head` は「自分が起点にしたスナップショット以降、on-disk が他の invocation によって既に更新されていないか」。**後者が無いと**、古いスナップショットのまま観測していた invocation が、既に別の invocation によって新しい head へ更新済みの on-disk 値を「自分の観測 head と一致しない」というだけの理由で無条件に上書きし、新しい head を自分の古い観測 head で巻き戻してしまう (PR #78 レビュー指摘: 2 つの `--check-only` invocation が併走し、新しい head を検知した側が先に CAS を成功させた後、古いスナップショットのまま観測していた側が「on-disk が自分の観測 head と違う」ことを理由に CAS を成功させ、古い head で上書きしてしまうケース)。両条件を `and` で束ねることで、on-disk が自分のスナップショットから 1 度でも動いていれば `.last_head_sha == $snapshot_head` が偽になって無条件に `error()` で弾かれ、書き込みは起きない。

   `error()` (非ゼロ exit・書き込みなし) は次の 3 ケースをまとめて指す: (a) 今回はまだ新 push を観測していない (通常サイクル、`$snapshot_head == $observed_head`)、(b) 別の invocation が同じ新 head を既に検知してこの CAS を通過済み、(c) 自分のスナップショットが既に stale — 別の invocation が別の (より新しい) head で先に on-disk を更新済み。(a)・(b) では、この invocation が `prm status` で取得した `checks.failing` / `unresolved_threads` は on-disk の現在の head と依然として整合しており、状態を巻き戻すことも再取得することもなく、そのまま次段 (3 の prune 以降) に進めばよい。**(c) だけは区別が必要** — 自分の `prm status` 呼び出し自体が、on-disk に既に記録されている head よりさらに古い head を見ていたことになり、保持している `checks.failing` / `unresolved_threads` はその古い head のものである。これをそのまま 3 以降に渡すと、新 head 向けに他 invocation が claim した `known_failing_checks` を古い head の `checks.failing` との積集合で誤って prune したり、新 head では既に存在しない失敗に対して `ci-self-heal` を dispatch したりしうる (PR #78 レビュー指摘、comment 3552918955)。

   3 ケースの切り分けは CAS filter の `error()` メッセージを解析せずとも、失敗した invocation がその場で `prm state-get <n> last_head_sha` を 1 回読むだけで判定できる (ローカルファイル読み取りのみ、GitHub API は叩かない):
   - 読み直した on-disk `last_head_sha` が自分の `$observed_head` と **一致する** → ケース (a)/(b)。スナップショットは stale ではないので、そのまま次段 (3 の prune 以降) に進めばよい。
   - **一致しない** (on-disk が自分の `$observed_head` よりさらに新しい head へ進んでいる) → ケース (c)。この場合に限り `prm status <n>` を **もう一度だけ** 呼び直して新しいスナップショットを取得し、**分岐 1 から評価をやり直す** (この再評価中に分岐 2 の CAS が再び失敗しても、再帰的に `prm status` を呼び直すことはしない — 1 回のみ。2 回目の失敗はそのままこのポーリングを打ち切り、3〜6 は評価せず 7・8 の記帳 (バックオフ延長・`cycle_ledger` への 1 行) だけ行って終了する)。再評価時の `$snapshot_head` にはこの判定のために読んだ `prm state-get <n> last_head_sha` の値をそのまま使う (読み直しは 1 回で足り、二重に呼ぶ必要はない)。

   この `prm status` 再取得は、次段落 (3 以降・4/5 の判定) が行う `known_failing_checks` / `known_comment_ids` の `state-get` 再読とは別物である点に注意する: 後者はローカルの dedup 台帳の陳腐化対策であり、ここで言う `checks.failing` / `unresolved_threads` という GitHub 側の観測値そのものの陳腐化は解決しない — GitHub 側の観測値の陳腐化を解決できるのは `prm status` の再取得だけである。

   CAS が **成功** (exit 0) した invocation だけが実際に `known_failing_checks` を全クリアし、`escalations` の `kind: ci-halted` エントリを全クリアし、`last_head_sha` を更新する。クリアが必要な理由自体は変わらない: `known_failing_checks` のクリアは CI が新しい head で再走するため、前回の失敗キーを引き継ぐと新 CI 上の再失敗を見落とすため。`escalations[kind=ci-halted]` のクリアが必要なのは、3 の prune が「`key` (`"<workflow>/<name>"`) が現在の `checks.failing` に無ければ削除」という条件しか持たず、**人間の修正 push 後も同じ check が引き続き failing のケース**を救えないため — この条件だけに任せると、新 head で `ci-self-heal` が再度 `HALTED` を返しても古いエスカレーション記録の `key` が一致し続けて dedup が効いてしまい、新しいインシデントの needs-human コメントが二度と投稿されなくなる。**新 head = 新インシデント境界**という原則に従い、同一 `workflow/name` の再失敗・再 HALTED であっても新 SHA 上では独立した事象として扱い、再エスカレーションを許可する。

   `last_head_sha` の更新をこの CAS 自身に含め、かつ「クリアしてよいか」の判定自体を on-disk 値との比較にしたのは、次の事故を防ぐためである (PR #78 レビュー指摘)。以前の版は「ローカルで `pr.head_sha != last_head_sha` を比較してからクリアを実行し、`last_head_sha` の書き込み自体は Step 8 の最終 apply まで遅延する」設計だった。この場合、2 つの `--check-only` invocation が両方とも (まだ更新されていない) 古い `last_head_sha` を読んで「新 push だ」と判定でき、片方が 4 の CAS claim で `known_failing_checks` に追記した **後** に、もう片方が (自分も新 push だと思い込んだまま) 同じ全クリアを実行して先発の claim を握りつぶし、握りつぶされた分だけ後発自身の claim も成功してしまう — 同一の新規失敗に対して `ci-self-heal` が二重 dispatch される。クリアの実行可否そのものを on-disk `last_head_sha` との CAS に一本化することで、2 度目の実行は `error()` で弾かれて書き込みが起きず、この二重クリアの窓が閉じる。

   この CAS 呼び出しを failing check の評価 (4) より **前** に行う点は変わらない — push と同時に来た新規失敗が、クリア前の古い `known_failing_checks` と比較されて同一ポーリング内で「既知」と誤判定されるのを防ぐ (M1)。
3. `known_failing_checks` を **prune** する: 現在の `checks.failing` の各要素を `"<workflow>/<name>"` に組んだ集合との積集合に絞る (2 の全クリアは、新 push 時に積集合を取るまでもなく丸ごと消せるという、この prune の特殊形)。`workflow` を含めて key するのは、複数 workflow に同名 job があるリポジトリで check 名だけを key にすると別 workflow の失敗が同一視され、`ci-self-heal` が dispatch されなくなるため (`gh pr checks --json` は `workflow` フィールドを提供する)。回復して `checks.failing` から消えた `workflow/name` は積集合から自然に落ち、後日再失敗した際に (4) で「新規」として再検知される。ただし `ci-self-heal` が `HALTED` を返し続けている check は `checks.failing` に居座り続けるため prune で落ちず、再 dispatch されないまま「エスカレーション分岐」(後述) の状態を維持する。

   同じタイミングで、次の 3 つも合わせて prune する。dedup 台帳が失効しないと、同じキー・同じスレッドの **別インシデント** が二度と通知されなくなり、エスカレーション (無監視放置の防止) の存在意義が長期運用で崩れるため:
   - `escalations` の `kind: ci-halted` エントリ: `key` (`"<workflow>/<name>"`) が現在の `checks.failing` に **無ければ** 削除する (= 回復した。次に同じ `workflow/name` の check が失敗したら新インシデントとして再検知・再エスカレーション可能になる)。これは **push を伴わない回復** (手動 re-run 等で head_sha が変わらないまま check が green になるケース) を拾うための条件付きクリアであり、2 の「新 push 時の無条件全クリア」とは補完関係にある — 2 は新 head という事実だけで即座にクリアするのに対し、ここは `checks.failing` の実測結果を見て初めてクリアする。同じ `workflow/name` が failing のまま新 push が来た場合は 2 で先にクリア済みのため、この条件は素通りする (矛盾なく重複適用されるだけ)。
   - `known_comment_ids` を、現在の `unresolved_threads` の `comment_id` 集合 (`is_outdated` を問わず全件) との積集合に絞る (state ファイルの無限肥大防止 + resolve 済みスレッドが後で再オープンされた際に新規スレッドとして検知できるようにするため)。この集合を `is_outdated == false` に絞り込む**必要はない** — (5) が新規判定の対象自体を `is_outdated == false` に限定するため、outdated のまま残るスレッドの `comment_id` が `known_comment_ids` に居座っても再 dispatch には至らない (実害なし)。両者の絞り込み基準を分けることで、prune は「本当に resolve されたか」だけを見る単純な条件に保てる。
   - `escalations` の `kind: review-stuck` エントリ: `key` (comment_id) が現在の `unresolved_threads` に **無ければ** 削除する (= スレッドが resolve された)。
2 (新 push の CAS) と 3 (prune) は、4/5 の claim (次項) が判定の基準にする on-disk state そのものを作る工程なので、**どちらも 4/5 に入る前に完了させる** (early apply)。2 は前述のとおり成功でも `error()` による no-op でも構わない独立した `prm state-apply` 呼び出しであり、3 は (2 の結果を踏まえた最新 state に対して) 常に実行する別の `prm state-apply` 呼び出しである。この 2 回の呼び出しを 4/5 より前に完了させずに判定・claim を行うと、回復済みの check/thread を誤って「既知」のまま残す、または新 push で本来クリアされるべき古いキーを基準に誤判定する、といった食い違いが起きる。

`state-apply` は書き戻すだけで更新後の state を stdout に返さない (`prm` 実装参照) ため、2/3 が on-disk を書き換えても、Step 4 冒頭で読んだ「前回スナップショット」はその変更を自動では反映しない。**4/5 の候補判定 (`known_failing_checks` / `known_comment_ids` に無いものを探す) は、冒頭スナップショットをそのまま使い回さず、2/3 完了後に `prm state-get <n>` (または `state-get <n> known_failing_checks` / `known_comment_ids`) で改めて読み直した最新 state を基準にする** (PR #78 レビュー指摘)。これを怠ると、同じ `workflow/name` が failing のままの新 push で、2 が on-disk 側の `known_failing_checks` を全クリアしたにもかかわらず、4 が冒頭スナップショットの (クリア前の) 古い `known_failing_checks` と比較して「既知」と誤判定し、claim (state-apply) を試みずに新規失敗の dispatch を見送ってしまう。この再読はローカルの dedup 台帳 (`known_failing_checks` / `known_comment_ids`) の陳腐化対策であり、`checks.failing` / `unresolved_threads` という GitHub 側の観測値自体の陳腐化とは別問題である — 後者が起こりうるケースと復帰手順は分岐 2 末尾を参照。

4. `checks.failing` の中に (3 で prune 済みの) `known_failing_checks` に無い `"<workflow>/<name>"` がある → 新規失敗候補。**dispatch より前に** `prm state-apply` で claim する (PR #78 レビュー指摘: 2 つの `--check-only` 実行が重なると、両方が同じ prune 後 state を「新規」と読み、旧来の「dispatch 後に追記」の順序では両方が dispatch してしまう)。claim filter は CAS (compare-and-swap) 形にし、`"<workflow>/<name>"` は filter 本文へのリテラル埋め込みではなく `--arg key "<workflow>/<name>"` で束縛した `$key` を参照する — workflow 名・job 名は GitHub 側の自由形式文字列で quote / backslash / 改行を含みうるため、文字列リテラルとして直接埋め込むと、そうした文字を含む名前で filter の構文が壊れるか意図と異なる filter になり claim が成立しなくなる (PR #78 レビュー指摘):

   ```jq
   if (.known_failing_checks | index($key)) then
     error("already-claimed")
   else
     .known_failing_checks = ((.known_failing_checks + [$key]) | unique)
   end
   ```

   呼び出しは `bash "${CLAUDE_SKILL_DIR}/scripts/prm" state-apply <n> <filter-file> --arg key "<workflow>/<name>"`。`jq --arg` は値をそのまま文字列として束縛するため呼び出し側での手動エスケープは不要 (実測確認済み: quote / backslash / 改行を含む値でも filter は壊れず、書き戻し後の JSON も往復して正しく復元される)。

   `state-apply` は lock 内で読み直した最新 state に対してこの filter を評価し、結果を検証してから書き戻す仕組みのため、`error()` を投げた filter は非ゼロ exit・**書き込みなし**で失敗する (実測確認済み)。これにより:
   - claim が **成功** (exit 0) した invocation だけが、その check について `ci-self-heal` を使う subagent を Task で dispatch する (契約は次項)。
   - claim が **失敗** (exit 1, `already-claimed`) した invocation は、別の並走 invocation が既に claim 済みと分かるので **dispatch しない** (二重 dispatch 防止 — 本来の指摘への対処)。
   - claim 成功後、**dispatch (Task 呼び出し自体) が例外・timeout で失敗した**とこの invocation が観測した場合に **限り**、`.known_failing_checks -= [$key]` という filter (claim と同じ理由で `"<workflow>/<name>"` は filter 本文へのリテラル埋め込みではなく `--arg key "<workflow>/<name>"` 経由の `$key` 参照にする — quote / backslash / 改行を含む workflow 名・job 名で filter が壊れるのを防ぐ、PR #78 レビュー指摘) を `prm state-apply <n> <filter-file> --arg key "<workflow>/<name>"` で呼び claim を **rollback** する (次ポーリングで再び「新規」として検知・再 dispatch できるようにする — claim を dispatch より前に動かした分の取りこぼし防止)。
   - 返った `verdict` が `HALTED` (3-failure architecture gate / flaky / env / infra) → 「エスカレーション分岐」(後述) に従う。この場合は dispatch 自体は完了しているので **rollback しない** — claim は維持したまま、次回以降のポーリングでも 3 の prune で落ちない限り「新規」扱いにしない。
5. `unresolved_threads` のうち **`is_outdated == false`** のものに限り、`comment_id` が `known_comment_ids` に無いものがある → 新規の未解決レビュースレッド候補。4 と同じ CAS claim パターンを `known_comment_ids` に対して適用する。`comment_id` は GitHub の `databaseId` で常に整数のため、`"<workflow>/<name>"` と異なりここはリテラル埋め込みのままで安全 (`--arg` が必須なのは quote / backslash / 改行を含みうる自由形式文字列のみ):

   ```jq
   if (.known_comment_ids | index(<comment_id>)) then
     error("already-claimed")
   else
     .known_comment_ids = ((.known_comment_ids + [<comment_id>]) | unique)
   end
   ```

   - claim **成功**時のみ `pr-review-respond` を使う subagent を Task で dispatch する (新規分の author が全て CodeRabbit なら、契約入力に「修正適用は `coderabbit:autofix` skill に委譲する。plugin がある環境のみ、無ければ `pr-review-respond` 通常経路」と明記する)。
   - claim **失敗**時は dispatch しない (別の並走 invocation が既に処理中/済み)。
   - claim 成功後に dispatch (Task 呼び出し自体) が例外・timeout で失敗したとこの invocation が観測した場合のみ、`.known_comment_ids -= [<comment_id>]` で rollback する。
   - `is_outdated == true` のスレッドは claim も dispatch も **しない**: `pr-review-respond` Phase A は `is_outdated == true` のスレッドを処理前に除外する設計であり、dispatch しても responder が skip するだけの空振りになる (fix push で古い会話が outdated になったが、reviewer がまだ resolve していないケースがこれに当たる)。この種のスレッドは `known_comment_ids` にも追記しない — 次回以降のポーリングでも同じ判定 (dispatch 対象外) を繰り返すだけで実害はなく、むしろ id を残さない方が「未対応のまま人間判断待ち」という状態を素直に表せる。代わりに出力フォーマットの監視サマリに一覧化し、resolve するか・追加コメントで再アクション喚起するかの判断を人間に残す。
   - dispatch した subagent の handback が **終端分類 (VALID / INVALID_PUSH / VALID_DEFER / DUPLICATE) できないコメントの残存を報告した** (「未終端 n→m」で n>0) → 「エスカレーション分岐」(後述) に従う。dispatch 自体は完了しているので rollback しない — claim は維持する (再 dispatch しないため)。
   - **`verdict: WAITING` それ自体はエスカレーション条件にならない**: `pr-review-respond` はヘッドレス subagent として dispatch された場合、「全スレッドを終端分類済みで CI 完了待ちのみ」のような **呼び出し元 (= 本スキル) が再開の責任を持つ待機**でも `WAITING` を返す契約になっている (`pr-review-respond` SKILL.md「実行環境前提」表)。pr-monitor はまさにその再開責任を持つ受け手であり、次ポーリングで自然に解消する (CI 完了は `checks` 側で既に追跡している。修正済みスレッドは Phase D で resolve 済みのため次回 `unresolved_threads` から消え、3 の prune で `known_comment_ids` も自然に落ちる)。エスカレーションすべきは上のとおり **未終端コメントが残っている場合のみ** — `WAITING` かつ未終端 n=0 (全コメント分類済み、待っているのは CI 完了や次ポーリングでの自然な収束だけ) なら、この分岐には該当させず Step 4 の残り (7・8) に進み監視を継続する。
6. 4 と 5 の claim → dispatch → (必要なら) rollback は **同一ポーリング内で逐次** (`ci-self-heal` → `pr-review-respond` の順)。同一 PR ブランチを共有し双方が push しうるため並列にしない。
7. 2・4・5 のいずれかに該当した (状態に変化があった) 場合、`poll_interval_seconds` を 60 に **リセット** する。いずれにも該当しなかった場合は現在値を 2 倍 (上限 1800) にする。
8. 2 の CAS (`last_head_sha` の更新を含む)・4/5 の claim (と、あれば rollback・「エスカレーション分岐」の `escalations` 追記) は個別の `prm state-apply` 呼び出しで既にコミット済みなので、ここで改めて書く必要はない。**`last_head_sha` はここでは触れない** — 分岐 2 の CAS filter だけがこの値の唯一の書き込み経路であり、最終 apply で再度 `head_sha` を書くと「2 の CAS が本当に成功したか」に関わらず無条件に上書きしてしまい、CAS を一本化した意味が失われる。残るのは `poll_interval_seconds` の更新、`last_checked_at` を現在時刻に更新する値、このポーリングの要約 1 行 (例: 「no change, backoff 60→120s」「new failing check dispatched」) を積む `cycle_ledger` の追記であり、これらを **1 つの jq filter にまとめ**、`prm state-apply` で state ファイルへ書き戻す (最終 apply)。`cycle_ledger` が配列フィールドのため `state-merge` ではなく `state-apply` を使う — filter 自身が `.` (lock 内で読み直された最新 state) を起点に追記を計算するので、`.cycle_ledger += ["..."]` は既存全体を明示的に持ち回らなくても追記できる。`known_failing_checks` / `known_comment_ids` / `last_head_sha` はこの最終 apply では触れない (2 および 4/5 で既に確定済みの値を上書きしないため)。

state ファイルの `monitor_mode` で OPEN 時の次アクションを分岐する (再入時は `--check-only` 引数だけでは手段が判らないため。`MERGED` / `CLOSED` は分岐 1 で判定終了済み — Step 5 へ):

| state | 次の手 |
|---|---|
| `OPEN` | Step 4 の 2〜8 を実施後、`monitor_mode: cron` なら何もせず終了 (次回 cron 起床に任せる)、`monitor_mode: wakeup` なら更新後の `poll_interval_seconds` で再度 `ScheduleWakeup`、`manual` なら手動再実行を案内 |

#### エスカレーション分岐 (`ci-self-heal` HALTED / `pr-review-respond` 終端未達)

4 または 5 で dispatch した subagent が上記の条件 (HALTED / 終端未達) を返した場合、**対象の check / comment_id は `known_*` に残したまま再 dispatch しない**。ただし **監視自体は継続する** — merge / close 検知 (分岐 1) は止めず、Step 4 の残り (7・8) やバックオフ・待機手段の予約も通常どおり行う。

- 対応する `key` (`ci-halted` は `"<workflow>/<name>"`、`review-stuck` は `comment_id`) が state の `escalations` に既に同じ `kind` で記録されている場合、**同じ事象への 2 度目のコメント投稿はしない** (dedup)。
- 未記録なら:
  1. `gh pr comment <n>` で needs-human 向けの構造化コメントを 1 件投稿する。最低構成:

     ```markdown
     ## needs-human: <ci-halted | review-stuck>

     - What: <HALTED になった "<workflow>/<name>" / 終端分類できなかったコメントの URL>
     - Handback: <dispatch した subagent の handback 要点 1-2 文>
     - Next: <人間が取るべき次の一手 1 文 (例: architecture 再考 / 該当スレッドへの直接判断)>

     pr-monitor は監視を継続します。対応後の新しい push で該当 check が prune されれば自動的に再検知されます。
     ```

  2. `gh pr comment` の**投稿成功を確認してから**、`prm state-apply` で state の `escalations` に `{kind: ci-halted|review-stuck, key: <"<workflow>/<name>"|comment_id>, at: <ISO8601>}` を追記する (`escalations` は配列フィールドのため `state-merge` ではなく `state-apply` — filter は `.escalations += [{kind: "...", key: $key, at: $at}]` の形)。`$key` の束縛方法は `kind` によって**異なる**: `kind: ci-halted` の `key` (`"<workflow>/<name>"`) は分岐 4 と同じ理由で `--arg key "<workflow>/<name>"` (文字列) 経由の `$key` 参照にする。`kind: review-stuck` の `key` (comment_id) は **`--argjson key <comment_id>` (数値) を使う** — `--arg` で束縛すると `$key` が JSON 文字列 (`"123"`) になり、3 の prune が行う「`key` が `unresolved_threads[].comment_id`（常に JSON 数値）に無ければ削除」という比較が jq の型付き等価性の下で常に不一致になる。結果、記録した直後の次ポーリングで prune が「無い」と誤判定してこのエントリを毎回消してしまい、`escalations` に一度も居座れないため dedup が機能せず、同じ事象への needs-human コメントが際限なく再投稿されうる (PR #78 レビュー指摘、comment 3552918945)。`known_comment_ids` (分岐 4/5) や `unresolved_threads[].comment_id` が一貫して数値として扱われているのに合わせ、`review-stuck` の `key` も数値のまま保持する。呼び出しは kind ごとに次のようになる:

     ```bash
     # kind: ci-halted
     prm state-apply <n> <filter-file> --arg key "<workflow>/<name>" --arg at "<ISO8601>"
     # kind: review-stuck
     prm state-apply <n> <filter-file> --argjson key <comment_id> --arg at "<ISO8601>"
     ```

     いずれの呼び出しも filter が参照する `$key` と `$at` の**両方**を束縛する (`$key` の束縛だけでは `$at` が未束縛のまま残り、jq が undefined `$at` で非ゼロ exit して escalation が記録されない — PR #78 レビュー指摘)。`$at` は `gh pr comment` の投稿成功を確認した時点の現在時刻 ISO8601 文字列を `--arg at "<ISO8601>"` で束縛する。投稿が失敗した場合 (network / rate-limit / permission 等) は追記せず、次ポーリングで再試行される — ここでも「確認された成功後にのみ state を更新する」原則 (次項「dispatch 契約」参照) を守り、通知未達のまま dedup が効いて以後の再エスカレーションが永久に握りつぶされる事態を防ぐ。

人間が対応した後の新 push で `known_failing_checks` が (2 の全クリア、または 3 の prune で) 落ちれば、次のポーリングで自然に再検知・再 dispatch される。

`review-stuck` の回復パスはスレッドの **resolve / 再オープン** であり、スレッド内への追記ではない — `prm` は `comments(first: 1)` でルートコメントのみ取得するため、スレッド内で人間が返信しても `comment_id` は変わらず、追記だけでは新規検知のトリガにならない。観測可能な回復シグナルは次の 2 つ:
- 人間が当該スレッドを **resolve** すれば `unresolved_threads` から消え、3 の prune により `escalations` の `review-stuck` エントリと `known_comment_ids` の両方から失効する。
- そのスレッドが後で **unresolve (再オープン)** されれば、`known_comment_ids` は既に prune 済みのため (5) で新規スレッドとして再検知され、`pr-review-respond` へ再 dispatch される。

#### dispatch 契約 (簡略)

`shipping` の Subagent 起動契約と同型。Task で新規 subagent を 1 つ起動し、次だけ渡し、次だけ返させる:

- 入力: 対象 PR 番号 / 対象 (`ci-self-heal` なら failing checks の `"<workflow>/<name>"` 列、`pr-review-respond` なら新規 `unresolved_threads` の `thread_id`・`comment_id`・`author`・`url`・`body_head`) / (該当時) CodeRabbit 委譲の明記
- 返す構造: `verdict` (`ci-self-heal` は PASS/HALTED、`pr-review-respond` は未終端 n→m)、`pushed_commits` (この task で push した SHA 列 / none)、`handback` (呼出側が次に判断するのに要る最小ブロック)

本スキルは `verdict` / `pushed_commits` / `handback` だけを読み、次ポーリングへ戻る。`known_*` への追記 (claim) は dispatch **より前**に行っている (Step 4 の 4/5 参照) — 2 つの並走 `--check-only` invocation が同じ check/thread を両方「新規」と判定して両方 dispatch してしまうレース (PR #78 レビュー指摘) を防ぐための機構で、claim に成功した invocation だけが dispatch を実行する。

claim を dispatch より前に動かした副作用として、claim と dispatch は別の呼び出しになる。claim 成功後に **dispatch (Task 呼び出し自体) が例外・timeout で失敗する**と、何もしなければ claim だけが state に残り「既知」のまま扱われ、その check / thread は二度と再検知されない取りこぼしになる — これを防ぐため、dispatch 自体の失敗をこの invocation が観測した場合に限り claim を明示的に rollback する (Step 4 の 4/5 参照)。

まとめると、2 つの機構はそれぞれ別の失敗モードに対応しており、どちらか一方だけでは両方を防げない:

| 失敗モード | 防ぐ機構 |
|---|---|
| 2 つの並走 invocation が同じ check/thread を両方 dispatch する (二重 dispatch) | claim の CAS 化 (`state-apply` の `error()` による非ゼロ exit・書き込みなし失敗) |
| claim 成功後、dispatch (Task 呼び出し自体) が例外・timeout で失敗し、対象が二度と再検知されなくなる (取りこぼし) | dispatch 失敗を observed した invocation 自身による claim rollback |

`verdict` が HALTED / 終端未達の場合は dispatch 自体は完了しているためロールバックせず、claim を維持したまま上記「エスカレーション分岐」に従う。

### Step 5 — 決着したら retro

`Skill(retro)` を起動し、「PR #<n> が <merged/closed> した」コンテキストと **state の `origin_transcript` パス** を渡す。これにより retro は「最新の transcript」ではなく **PR を生んだ元セッション** を解析する (check-only の監視セッションを誤って解析しない)。`origin_transcript` が未記録 (Step 1 直行など) のときだけ retro 既定の最新 transcript 選択にフォールバックする。retro が改善提案 (提案のみ) を出して pr-monitor は完了。

## 出力フォーマット

```markdown
# pr-monitor: PR #<n> (<branch>)

## 監視
- state: <OPEN→…→MERGED/CLOSED>
- 手段: <cron / ScheduleWakeup / 手動>
- poll_interval_seconds: <n>
- last_checked_at: <ISO8601>

## 観測 (直近ポーリング)
- checks.failing: <件数 ("workflow/name" 列) / なし>
- checks.pending: <件数 / なし>
- unresolved_threads: <unresolved_count 件> (うち dispatch 対象外 outdated: <n 件>)
- outdated かつ未解決 (dispatch 対象外、人間判断待ち): <URL 列 / なし>

## dispatch 履歴
- <ISO8601> ci-self-heal dispatch (<"workflow/name">) → verdict: <PASS/HALTED>
- <ISO8601> pr-review-respond dispatch (<comment_id 列>, coderabbit:autofix 委譲: <あり/なし>) → verdict: <未終端 n→m>

## エスカレーション
- <escalations 件数 (kind/key 列, 新規投稿分には needs-human コメント URL) / なし>

## 決着
- <MERGED <SHA> / CLOSED / 監視中 (次回 <手段>, interval <n>s)>
- Next: <retro 起動済み / 次ポーリング予定 / 手動再実行案内>

verdict: <MONITORING (<cron|wakeup|manual>) / SETTLED (<MERGED|CLOSED>) / ESCALATED>
```

`verdict` は次の 3 トークンに固定する (`shipping` Phase 6 がこの report を dispatch 結果として読む契約。`skills/shipping/SKILL.md` の Phase 6 verdict 表記と完全一致させる):

- `SETTLED (<MERGED|CLOSED>)`: Step 4 分岐 1 (または Step 1) で決着を検知したポーリング。分岐 1 の CAS に敗れた invocation (既に他 invocation が決着処理済み) も `pr.state` 自体は同じく MERGED/CLOSED を観測しているため `SETTLED` を返してよいが、cron 解除・retro 起動は行っていない旨を「決着」セクションの `Next` に明記する (例: 「他 invocation が処理済み、retro 起動なし」)。
- `ESCALATED`: このポーリングで新規のエスカレーション (needs-human コメント投稿) が発生した、または既存の未解消エスカレーション (`escalations` に記録済みで対象がまだ prune で落ちていない) を抱えたまま終了するポーリング。**決着ではない** — 監視自体は継続し Step 5 (retro) へは進まない。
- `MONITORING (<mode>)`: 上記いずれでもない通常の監視継続。

### 出力する成果物

- **状態ファイル** `.claude/.pr-monitor/PR-<n>.json` (consumer gitignore 前提、`known_*` / `escalations` / `last_head_sha` / `poll_interval_seconds` / `cycle_ledger` 込み。`prm state-init` / `prm state-merge` / `prm state-apply` 経由でのみ作成・更新)
- **監視サマリ** (state 遷移 + 採用した待機手段 + 観測値 + dispatch 履歴 + エスカレーション + 次アクション)
- **CI 失敗検知時の `ci-self-heal` subagent dispatch** (検知と起動のみ。修復自体は `ci-self-heal` の成果物)
- **新規未解決レビュースレッド検知時の `pr-review-respond` subagent dispatch** (検知と起動のみ。返信・修正コミットは `pr-review-respond` / `coderabbit:autofix` の成果物)
- **エスカレーション時の needs-human コメント** (`gh pr comment` 経由、同一事象で 1 回のみ投稿)
- **決着時の retro 起動**

### 出力しない成果物
- **PR の merge / squash / close 操作**: 決着は人間または別自動化。本スキルは事実を待つだけ。
- **CI ログ取得 / 修復そのもの**: `ci-self-heal` の領域。本スキルは `prm status` の `checks.failing` という観測値だけ見て dispatch する。
- **コメントへの返信・修正コミットそのもの**: `pr-review-respond` (CodeRabbit 起因の修正適用は `coderabbit:autofix`) の領域。本スキルは `unresolved_threads` という観測値だけ見て dispatch する。
- **foreground の長時間 sleep / watch**: main をブロックしない。cron / ScheduleWakeup / Monitor に委ねる。
- **リポ追跡されるログ**: 状態は gitignore パスのみ。

## 既知の限界
- **cron の可否は環境依存**: `/schedule` が無い環境では ScheduleWakeup (session 生存中のみ) か手動にフォールバックする。
- **cron モードでは指数バックオフが効かない**: `/schedule` 登録は固定間隔 (30 分) のため、`poll_interval_seconds` の伸縮は state に記録されても待機間隔には反映されない。バックオフの実効果は `ScheduleWakeup` / `Monitor` 手段でのみ現れる。
- **session 終了で ScheduleWakeup は途切れる**: 長期 (日単位) 監視は cron 手段が前提。手段 2 は session が生きている間だけ。
- **claim 後・rollback 前の pr-monitor プロセス自体のクラッシュは検知されない**: 二重 dispatch 防止のため `known_failing_checks` / `known_comment_ids` への追記 (claim) を dispatch より前に行うようにした (PR #78 レビュー指摘)。dispatch 先 subagent 自体の例外・timeout はこの invocation が観測して claim を rollback するため取りこぼさないが、claim 成功から「dispatch 完了 (HALTED 含む)」または「rollback」のどちらかに到達するまでの間に **pr-monitor プロセス自身が異常終了** (Task 呼び出しの例外ではなく、monitor を実行しているプロセス自体のクラッシュ/強制終了) した場合は、claim だけが state に残り rollback が走らないため、その check / thread は以後「新規」として再検知されない。取りこぼしを完全にゼロにはできず、この狭い窓に限定して残る。
- **逐次 dispatch 前提でレイテンシが伸びる**: `ci-self-heal` と `pr-review-respond` を同一ブランチ push 競合回避のため並列にしない分、1 ポーリングあたりの所要時間は両方が完了するまで伸びる。
- **マルチモデル未検証**: trigger eval は本セッションのモデルのみ。
