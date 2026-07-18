---
name: design-review
description: >-
  ソフトウェア設計の成果物（ADR、ドメインモデル、モジュール構造、アーキテクチャ提案、設計差分、`software-design` skill
  の提案）を、書き手バイアスのない別エージェントに白紙で読ませて構造化された指摘を返すレビュー専用スキル。philosophy of software
  design (Ousterhout)、immutable data model (kawasima)、TM法 (佐藤正美)、関数型プログラミング、DDD
  (Vlad Khononov)、TDD (Kent Beck)、Railway Oriented Programming (Scott
  Wlaschin)、Fundamentals of Software Architecture、xUnit Test Patterns、CQRS、Event
  Sourcing、ADR (Nygard)、Secure by Design の 13 レンズを checklist で当てる。「設計レビューして」「ADR
  レビューして」「設計で抜け落ちている観点ない?」「別エージェントで読み直して」「設計の最終チェック」「この提案で行く?」「集約境界これで
  OK?」「Result への置き換え、抜けない?」「Secure by Design 観点で監査して」「ADR の Negative
  consequences 薄い」のような要請、`software-design` の Proposal/ADR 最終確認、PR の設計関連ドキュメント /
  コード境界の妥当性確認、設計セッション後の「セルフレビューでない外部視点」が必要な場面で必ず起動する。Agent ツールで subagent を
  dispatch して評価し、書き手（同セッションの主エージェント）にレビューさせない。テスト本体のレビューは `test-review`、調査は
  `research-practices`、Skill 本体の作成・トリガ調整は `skill-builder`
  担当のため、それらの目的が明確な依頼ではこのスキルを起動しない。実装を書き換える作業（コード修正、リファクタリング実施、lint
  違反対応）は範囲外で、本スキルは「読んで指摘する」レビュー専用である。
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Agent
  - TaskCreate
  - TaskUpdate
  - TaskList
  - AskUserQuestion
  - mcp__plugin_serena_serena__find_symbol
  - mcp__plugin_serena_serena__get_symbols_overview
  - mcp__plugin_serena_serena__search_for_pattern
  - mcp__plugin_serena_serena__list_dir
  - mcp__plugin_serena_serena__find_file
  - mcp__plugin_serena_serena__read_file
---
# Design Review

設計成果物を **書き手バイアスのない別エージェント** に白紙で読ませ、`software-design` の 13 レンズに沿った checklist を機械的に当てて構造化された findings を返すスキル。

書き手バイアス排除の鉄則：

- **同じセッション / 同じ context の主エージェントにレビューさせない。** 「書きながら自分でセルフレビュー」は読み返しているだけで、隠れた前提に気づけない。
- **必ず Agent ツールで subagent を dispatch** し、白紙でレビュー資料を読ませる。
- **subagent にも "13 レンズの checklist を順に当てよ" と指示する。** 主観で読み流させない。

`software-design` を実行した直後、ADR をドラフトした直後、PR に含まれる設計関連の差分が固まった時に併用する。

---

## ワークフロー

### Step 1 — レビュー対象の同定

入力から以下を確定する。曖昧なら `AskUserQuestion` で確認する。

| 種別 | 例 |
|---|---|
| ADR | `docs/adr/0007-*.md` |
| Design Proposal | `software-design` skill が直前に出した文書 |
| 設計コード差分 | 集約 / モデル / ports & adapters の追加・改変 |
| アーキテクチャ図 / モデル図 | C4, ER, シーケンス |
| 既存設計の妥当性 | 指定モジュールに対する general review |

**スコープを 1 リクエスト 1 種別に絞る。** 「全部見て」は subagent 側で焦点が散る。

### Step 2 — 適用レンズの選択

対象種別に応じて、`skills/software-design/references/` の中から当てる checklist を選ぶ。本スキルの `references/checklist.md` がレンズごとの設問集を持つ。

| 対象 | 適用レンズ（既定） |
|---|---|
| ADR | adr, architecture, ddd（決定が触れる範囲） |
| Domain model | ddd, data-model, security |
| Module / class 構造 | philosophy, functional-core, tdd |
| Aggregate / repository | ddd, data-model |
| Error handling 戦略 | functional-core (FP/Railway), philosophy |
| アーキテクチャ提案 | architecture, ddd, adr |
| Auth / 入力検証 | security, data-model |
| 全般（種別不明） | philosophy, ddd, security, adr の 4 本を必ず + 内容に応じて追加 |

### Step 3 — Subagent dispatch

`Agent` ツールを使い、`general-purpose` subagent に以下のテンプレートで投げる。**本スキルが書き手代わりに評価しない**：

```markdown
あなたは <対象名> を白紙で読むレビュー実行者です。書き手の意図は知らない前提で、
書かれているテキスト / コードだけから判断してください。

## レビュー対象
<ファイルパス・該当範囲・コードブロック>

## 適用 checklist
以下のレンズについて、`skills/software-design/references/<lens>.md` の "レビュー観点" 節を
順に当ててください。レンズ:
- <lens-1>
- <lens-2>
- ...

## チェックの仕方
各観点について次のいずれかを返す:
- ○ 充足している（短い根拠 1 行）
- × 充足していない（issue 1 行 + Fix 提案 1 行 + 該当 path:line）
- ? 判断不能（追加情報が必要 — 何が要るか 1 行）

## 出力形式
レンズごとに H2 を立て、観点ごとに箇条書きで上記 ○/×/? を並べる。
最後に "Summary" 節を立て、Critical / Major / Minor の数を集計し、
merge OK / changes requested / 要議論 を判定する。findings は捏造しない。
読みづらいなら "?" で素直にエスカレーションする。
```

`Agent` の `subagent_type` は `general-purpose`（特化エージェントが既にあるなら指定）。出力をそのまま受け取り、**本スキル側で書き直さない**（バイアスを混ぜないため）。

### Step 4 — 主エージェントが集約

subagent から返ってきた findings を、ユーザ向け最終出力に整形する。整形時にやること：

- **重複統合**: 同じ issue が複数レンズで出ているなら 1 件にまとめる（Lens 名タグを `[philosophy/deep-module] [ddd/aggregate]` のように複数つける）
- **Critical / Major / Minor 振り分け**: subagent の判定を尊重するが、明らかにレベル違いが見えたら主エージェントが調整。理由を 1 行残す。
- **Open Questions の昇格**: subagent が "?" にした項目は最終出力の "Open Questions" に集める。ユーザに判断を返す。
- **Strengths**: ○ で良かったところを最低 1 件残す。「悪いとこだけ列挙」はレビュー疲れを招く。

### Step 5 — 必要に応じて再 dispatch

以下の場合は同じ subagent に **続報を依頼せず、新しい subagent を立てて** やり直す：

- subagent が checklist を一部スキップした
- "?" が多すぎて判断材料が足りなかった
- レンズ選択が誤っていた

「同じ subagent に追加質問」をしないのは、初回読みの白紙性を維持するため。

---

## 出力フォーマット

```markdown
# Design Review

## Summary
判定: <merge OK / changes requested / 要議論>
主要懸念（最大 3）: ...

## Critical (blocks merge)
- [path:line] [<lens-tag>] [<lens-tag>]: <issue>
  - Fix: <提案>
  - Reviewer note: <subagent の根拠 1 行>

## Major (should fix)
- ...

## Minor / Style
- ...

## Open Questions
- [<lens-tag>]: <subagent が "?" にした項目>

## Strengths
- ...

## Reviewed lenses
- <lens-1>: ○ N / × N / ? N
- <lens-2>: ...

## Reviewer
- subagent: general-purpose（white-paper read）
- 主エージェント: 集約のみ（レビュー判断はしていない）
```

`<lens-tag>` 例（`software-design` と整合）: `philosophy/deep-module`, `data/mutable-mix`, `tm/key`, `fp/exception-as-control`, `ddd/aggregate-boundary`, `tdd/untestable`, `rop/result-leak`, `arch/quantum`, `xunit/double-overuse`, `cqrs/asymmetry`, `es/state-loss`, `adr/missing-options`, `secure/primitive`。

---

## このスキルがやらないこと

- **設計の "提案"。** 提案は `software-design` の担当。本スキルは "読んで指摘" のみ。
- **コード書き換え。** Fix は提案テキスト。実装は別ステップ / 別スキル。
- **書き手（同セッションの主エージェント）による直接評価。** 必ず subagent dispatch。
- **テスト本体のレビュー。** `test-review` の担当。
- **調査作業（先行事例 / 学術調査）。** `research-practices` の担当。
- **subagent の出力を主エージェントが書き直して "正しく" すること。** 出力は集約のみ。指摘内容を主エージェントの判断で握りつぶさない。
- **複数の対象を 1 回でレビューすること。** スコープを 1 種別に絞り、必要なら複数回呼ぶ。

---

## 良いレビューの例

```markdown
# Design Review

## Summary
判定: changes requested
主要懸念: (1) ADR-0007 が Considered Options に却下案を 1 案しか書いていない、
(2) `Order` 集約が `Customer` と同一トランザクションで更新されている、
(3) Email がプリミティブ string のまま service 層を流れている。

## Critical (blocks merge)
- [packages/orders/src/use_cases/place_order.ts:42] [ddd/aggregate-boundary]: 1 トランザクションで `Order` と `Customer` の双方を更新している。
  - Fix: `Customer.creditUsed` を更新するのは domain event `OrderPlaced` を outbox に書き、別トランザクションで反映する。集約境界に書き戻す動機を ADR に切り出す。
  - Reviewer note: `Repository.beginTx()` 配下に複数集約の `save()` が並ぶのを検出。

- [packages/orders/src/api/place_order.ts:18] [secure/primitive]: 受け取った `email: string` がそのまま `OrderService.placeOrder(email, ...)` に渡っている。
  - Fix: API 入口で `Email.parse(raw)` を通し、`Email` 型として service に渡す。`OrderService` の引数を `Email` に変更。

## Major (should fix)
- [docs/adr/0007-event-sourcing-for-orders.md:24] [adr/missing-options]: Considered Options に "ES なし、状態 + audit_log" 案がない。
  - Fix: 当該案を Pros/Cons つきで追記し、却下根拠を Decision に書く。

## Minor / Style
- [packages/orders/src/domain/order.ts:7] [philosophy/deep-module]: `OrderManager` という名前は "manage" を含む。
  - Fix: 役割が "発注の整合確認" なら `OrderPlacement` のような具体名に。

## Open Questions
- [arch/quantum]: ADR-0007 が "Order と Inventory は同期 RPC で繋ぐ" としているが、これだと量子は実質 1 つになる。意図して同期にしている?

## Strengths
- ドメインプリミティブ `Money(amount, currency)` の不変性とコンストラクタ検証は徹底できている。
- `Result<T, OrderError>` の Err sum type に網羅性チェックがコンパイル時に効いている。

## Reviewed lenses
- adr: ○ 4 / × 1 / ? 0
- ddd: ○ 5 / × 1 / ? 0
- security: ○ 3 / × 1 / ? 0
- architecture: ○ 3 / × 0 / ? 1
- philosophy: ○ 6 / × 1 / ? 0

## Reviewer
- subagent: general-purpose (white-paper read)
- 主エージェント: 集約のみ
```
