# Handoff protocol — prd-review / requirements への引き継ぎ

本 skill が `docs/prd/<slug>.md` を書き終えた後、下流の **`prd-review` skill（別 agent）** と **`requirements` skill（要件定義）** にどう繋ぐかを定義する。

設計原則: **本 skill は何も自動起動しない**。チェーン化はレビューの独立性を壊し、auto mode 親和も損なう。ユーザが意識的に次のフェーズに進む。

---

## ステージ全体図

```text
[product-discovery]      ── 本 skill。docs/prd/<slug>.md を生成 / 更新
        ↓ ユーザ起動
[prd-review]             ── 別 agent / 別 skill。must / imo を出す
        ↓ revise が必要なら
[product-discovery (再)] ── §Decision log にエントリを追加
        ↓ approved
[requirements]           ── 要件定義 (spec / EARS / 影響範囲)
        ↓
[design / implement / ...]
```

---

## prd-review への引き継ぎ仕様

### 入力（prd-review が読むもの）

- 必須: `docs/prd/<slug>.md`
- 任意: `docs/prd/<slug>.md` の前バージョン（git で取れるなら diff）
- 任意: `references/customer-is-self.md` の bias check 結果（PRD §Self-check に埋まっている）

### 本 skill が PRD に埋める「review が読む契約」のブロック

PRD には以下のセクションを **必ず** 埋める。prd-review はこれらを点検対象にする:

| PRD セクション | review が見るポイント |
|---|---|
| §Meta | change_type, customer_type, self_only, blast_radius |
| §1 Why now / Outcome | outcome が output の言い換えになっていないか, do-nothing baseline がある |
| §2 Customer | specific instance, alternative observed, scope 宣言 |
| §3 Opportunities | feature 名でなく顧客痛点で書かれている, 上限 4 |
| §4 Solution direction | spec / 設計詳細が混入していない, 却下した代替の理由 |
| §5 Assumptions & Riskiest test | 4 リスクすべて記載, riskiest 1 件選択, falsification test |
| §6 Success / Anti-goals | leading + lagging + anti-signal がある |
| §7 Open questions | `[TO_VALIDATE]` 上限 5 以下 |
| §8 Decision log | 改訂時にエントリ追加 |
| §Self-check (顧客=自分自身モード時) | 4 項目埋まっている |

### 完了報告でユーザに渡す文面（テンプレ）

```text
PRD ドラフトを docs/prd/<slug>.md に書きました。

要約:
- Outcome: ...
- 上位 opportunity: ...
- Riskiest assumption: ...

次のステップ:
1. 別 agent で `prd-review` skill を起動してレビューを依頼してください
   （本 skill からは自動起動しません）。
2. レビューの must 指摘があれば本 skill を再起動 → revise します
   （§Decision log に履歴が残ります）。
3. PRD が approved になったら `requirements` skill を起動して要件定義に進んでください。

残った [TO_VALIDATE]: N 件（あれば内容）
```

### prd-review が must を返したとき

ユーザは以下のいずれかを選ぶ:

1. **revise**: 本 skill を再起動。`prd_revision` モードで起動し、指摘部分の Phase（B / C / D / E）に戻ってリファインしてから PRD を上書き。§Decision log にエントリを追加
2. **drop**: PRD を破棄して再企画。本 skill を `new_product` モードで再起動
3. **defer**: 指摘を `[TO_VALIDATE]` に降格させて先に進める（要件定義フェーズで決着させる）

`defer` を選んだ際は §Decision log に **defer の理由** を残す（後で「なぜ無視したか」がわかるように）。

---

## requirements への引き継ぎ仕様

`requirements` skill は本 skill とは別 skill（speee/sengoku の `requirements` パターンを参考にする想定）。本 skill から自動起動しない。

### 引き渡すもの

- PRD パス: `docs/prd/<slug>.md`
- approved ステータス（PRD §Meta `status: approved`）
- prd-review の最終 verdict（`docs/prd/<slug>-review.md` 等が別 skill 側で生成される想定）

### requirements 側で行うこと（本 skill の責務外）

- PRD を Read して **要件 (spec)** に展開（EARS, FR / NFR, 影響範囲, AC）
- DB 修正必要性判定 → data-modeling skill delegate
- self-review で PASS / FAIL_SELF / FAIL_UPSTREAM 判定
- `z/{task}/requirements.md` を生成

### PRD と requirements の責務境界

| 軸 | PRD（本 skill） | requirements |
|---|---|---|
| 抽象度 | What / Why（要求） | What の詳細 + 観測可能な振る舞い（要件） |
| 顧客視点 | jobs / outcome / pain | use case / actor / 制約 |
| 検証対象 | 動かす指標 / anti-goal | 受入条件 (AC), Vitest テスト名対応 |
| 書かないもの | spec, シグネチャ, schema | アーキ図, クラス, 実装方針 |

PRD で書きすぎると要件が矛盾する。**本 skill は spec を書かない契約を厳守**。

---

## ユーザが本 skill / prd-review / requirements を行き来する典型パターン

### パターン 1: 順調

1. product-discovery → PRD draft
2. prd-review → must 0, imo 2 → PASS
3. ユーザ判断で imo を反映 or defer
4. requirements 起動

### パターン 2: revise loop

1. product-discovery → PRD draft (v1)
2. prd-review → must 2 → FAIL_SELF
3. product-discovery 再起動（`prd_revision`）→ PRD v2、§Decision log にエントリ
4. prd-review → PASS
5. requirements 起動

### パターン 3: 上流問題（PRD の前提が崩れる）

1. product-discovery → PRD draft
2. prd-review → FAIL_UPSTREAM（「outcome 自体が筋違い」）
3. ユーザは PRD を破棄
4. product-discovery を **`new_product` または `new_feature`** で再起動。前 PRD は §Decision log に「破棄理由」を書いて archive 扱い

### パターン 4: requirements で要求側の問題が発覚

1. product-discovery → PRD approved
2. requirements 起動 → `[NEEDS CLARIFICATION]` で「outcome に対する制約が不明」
3. ユーザ判断で本 skill を再起動して PRD を補強 → requirements 再起動

このサイクルを許容する設計にしておく。**PRD は不変文書ではなく、§Decision log を伴う 進化文書** として運用する。

---

## Linear / Notion / Jira への外部書き出し

本 skill は file-based に閉じる（`docs/prd/<slug>.md` のみ）。

外部ツールへの転記が必要な場合:

- **手動**: ユーザが `docs/prd/<slug>.md` を開いてコピー
- **将来拡張**: Linear MCP サーバが接続されている前提で、本 skill とは別の連携 skill（例: `prd-to-linear`）を作る。本 skill 自体には混ぜ込まない（責務分離）

外部ツール上に書き戻す PRD は **本 skill が書いた `docs/prd/<slug>.md` をソース・オブ・トゥルース** とする運用を推奨。
