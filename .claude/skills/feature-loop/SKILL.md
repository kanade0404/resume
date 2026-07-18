---
name: feature-loop
description: >-
  1 つの変更要求を、受け入れ条件の確定から実装・出荷・PR
  決着の監視・ハーネス自己改善まで一気通貫で回す最上位オーケストレータスキル。入口で要求の複雑さを**観測可能な決定表**で判定し、明確で小さければ受け入れ条件を
  1 ショット確認して即実装へ、曖昧/大きければ `grill-with-docs` で詰める。以降 `tdd`/`tidy-first` で実装 →
  `shipping` で品質ゲート〜CI〜レビュー対応を merge-ready まで収束 → `pr-monitor` で merge/close を監視
  → 決着で `retro` が自己改善提案、と各段を fresh subagent / skill に委譲する。本スキルはコードを書かず、段の順序と
  handoff と決定表の告知だけを main で持つ。「最初から最後まで回して」「受け入れ条件決めて実装して PR 決着まで面倒見て」「feature
  を頭から ship・監視・振り返りまで」、さらに口語の丸投げ「これ実装したいんだけど全部やっといて」「あとは丸ごとまかせる」のような、1
  つの変更要求を実装＋後工程まで委任する意図で必ず起動する。設計だけ・実装だけ・出荷だけ・監視だけ・振り返りだけの単機能要請、および「バグ直して」「このタイポ直して」のような単発修正は該当する個別
  skill (`grill-with-docs` / `tdd` / `shipping` / `pr-monitor` / `retro`)
  を名指しで使い、本スキルは起動しない。PR の merge 操作はせず、決着 (merge/close) を監視で待つ。
allowed-tools:
  - Read
  - Task
  - Skill
  - AskUserQuestion
  - Bash(git status *)
  - Bash(git rev-parse *)
  - Bash(git branch *)
  - Bash(gh pr view *)
---
# feature-loop — 入口から PR 決着・自己改善までの最上位ループ

> **構成原則**: 各段は個別 skill / fresh subagent に委譲する。本スキル (orchestrator) は main に残り、**段の順序・handoff・決定表の告知**だけを持つ。コードは書かない (`shipping` と同じ規律)。
> **停止しない条件**: PR は merge しない。`shipping` は merge-ready で止め、`pr-monitor` が決着を待ち、`retro` は提案のみ。各段の停止/escalation はその skill の規律に従う。

## パイプライン

```text
intake (決定表)         implement            ship                 monitor            improve
heavy: grill-with-docs  tdd / tidy-first  →  shipping          →  pr-monitor      →  retro
light: 受け入れ条件1shot                     (simplify→review      (merge/close 監視)   (決着で起動)
                                              →verify→PR→CI→…)
```

## いつ起動するか

- 「最初から最後まで回して」「受け入れ条件決めて実装して PR 決着まで」「feature を頭から ship・監視・振り返りまで」
- 口語の丸投げ「これ実装したいんだけど全部やっといて」「あとは丸ごとまかせる」(実装＋後工程まで含む委任の意図)
- 1 つの変更を end-to-end で委任したいとき

逆に **起動しない** (名指しで個別 skill へ):

| 要求 | 渡す先 |
|---|---|
| 設計・要件詰めだけ | `grill-with-docs` |
| 実装だけ | `tdd` / `tidy-first` |
| 出荷 (review〜CI〜PR) だけ | `shipping` |
| PR 決着の監視だけ | `pr-monitor` |
| 振り返りだけ | `retro` |

## Step 1 — intake: heavy / light を決定表で判定し告知

要求と現状 (受け入れ条件の有無、未確定点、影響範囲) を観測し、**決定表**で経路を選ぶ。判定は隠さず「観測したシグナル → 選んだ行」を 1 行で告知してから進む (緩和後の規約 = 明示・観測可能な分岐、Conditional workflow pattern)。

| 観測シグナル (全て満たす) | 経路 |
|---|---|
| 受け入れ条件が明示済み **かつ** 未確定点 0 **かつ** 影響 ≤ 1 モジュール **かつ** ADR 級の設計判断なし | **light** |
| 上記のいずれかを欠く | **heavy** |

- **heavy**: `Skill(grill-with-docs)` を起動し、受け入れ条件・用語・既存設計との整合を詰める。完了後 Step 2 へ。
- **light**: 受け入れ条件を 1 ショットで明文化し (`AskUserQuestion` で 1 回だけ確認)、合意できたら Step 2 へ。

ユーザは告知された経路を **override 可** (「heavy で」「light で」)。override されたらその経路に従う。

## Step 2 — implement: tdd / tidy-first

受け入れ条件を満たす実装を、変更種別でルーティングして fresh subagent に出す:

| 変更種別 | dispatch 先 |
|---|---|
| 振る舞いが変わる (新機能 / バグ修正 / 仕様変更) | `tdd` (RED→GREEN) |
| 構造のみ (rename / extract / dead code 削除) | `tidy-first` |

GREEN になったら Step 3 へ。未 GREEN / WIP のまま先へ進めない。

## Step 3 — ship: shipping

`Skill(shipping)` に handoff。shipping が Phase 1a simplify → 1b code-review → verify-done → PR materialize → CI 緑化 (`ci-self-heal`) + 自動レビュー対応 (`pr-review-respond`) の収束ループ → 最終 verify-done を回し、**merge-ready で停止**する。

| shipping verdict | 次の手 |
|---|---|
| SHIPPED (merge-ready) | PR 番号を確保して Step 4 へ |
| BLOCKED / ESCALATED | パイプライン中断。shipping の handback を添えてユーザに返す (Critical 対処・architecture 再考は上流) |

## Step 4 — monitor: pr-monitor → retro

`Skill(pr-monitor)` を起動し、Step 3 の PR 番号を渡す。pr-monitor が merge/close まで監視し、**決着を検出したら `retro` を自動起動**する。feature-loop の handoff はここで完了 — 以降は pr-monitor / retro が駆動する。

## 出力フォーマット

```markdown
# feature-loop: <要求 1 行> → PR #<n>

## Pipeline
- intake: <light / heavy (grill-with-docs)>  ← 決定表: <満たした/欠けたシグナル>
- implement: <tdd / tidy-first> → GREEN
- ship: shipping → <SHIPPED merge-ready / BLOCKED / ESCALATED>
- monitor: pr-monitor 起動 (<cron / ScheduleWakeup / 手動>) → 決着で retro

## Verdict
- <HANDED_OFF (pr-monitor 監視中) / BLOCKED / ESCALATED>
- Next: <merge 待ち (retro は決着で自動) / Critical 対処 / 設計戻し …>
```

各段 skill の本体出力 (grill QA / findings / cycle ledger) は再掲しない。handback / verdict だけ載せる。

## 出力する成果物 / 出力しない成果物

### 出力する成果物
- **Pipeline ログ** (intake 経路 + 決定表のどの行か + 各段の verdict)
- **段間の handoff 観測** (GREEN 到達 / PR 番号 / shipping verdict)
- **Verdict 1 行** (HANDED_OFF / BLOCKED / ESCALATED + Next)

### 出力しない成果物
- **実装コード・修正差分**: 本スキルは書かない。`tdd` / `tidy-first` / `shipping` 配下の subagent が出す。
- **各段 skill の本体出力の再掲**: grill の QA、code-review findings、cycle ledger は各 skill が持つ。本スキルは handback 参照のみ。
- **PR の merge / close 操作**: 決着は人間/別自動化。`pr-monitor` が事実を待つ。
- **隠れた intake 分岐**: 経路判定は必ず告知する。黙って heavy/light を切り替えない。
- **個別段の単独実行**: 単機能要請は個別 skill へ。本スキルは end-to-end 委任のときだけ。

## 既知の限界
- **single PR / single feature 前提**: 1 ループ 1 PR。複数並走は想定しない。
- **長期監視は環境依存**: Step 4 の長期 (日単位) 監視は `/schedule` (cron) を要する。無ければ pr-monitor が ScheduleWakeup / 手動にフォールバックする。
- **マルチモデル未検証**: trigger eval は本セッションのモデルのみ。
