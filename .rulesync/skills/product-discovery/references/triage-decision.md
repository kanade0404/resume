# Phase A: triage 決定木

本 skill を起動するか / 別 skill に振るかの判定、および本 skill 内で扱う **change_type** と **顧客タイプ** を決める。

冒頭の `AskUserQuestion` 1 回でユーザに揃えてもらい、以降は本文で完走する。

---

## Step 0: 本 skill 範囲外の検出

ユーザ入力が以下のいずれかに該当するなら、本 skill を起動せず該当 skill を案内して終了する:

| 検出キー | 振り先 |
|---|---|
| 「要件 / spec / 仕様 を書きたい / 確定したい」「EARS で書く」 | `requirements` skill |
| 「PRD のレビュー」「PRD を見て指摘」「PRD のチェック」 | `prd-review` skill |
| 「設計して」「アーキテクチャ」「クラス図」「シーケンス図」 | feature-dev / design 系 |
| 「実装して」「コード書いて」「リファクタリング」 | 該当の実装系 skill / agent |
| 「ライブラリ調べて」「比較して」「先行事例」 | `research-practices` skill |
| 「テスト見て」「テストレビュー」 | `test-review` skill |
| 「データモデル / Prisma schema / index 設計」 | data-modeling 系 skill |

迷うなら「本 skill は **要求 (request)**、`requirements` は **要件 (spec)** を扱う」を物差しにする。

---

## Step 1: change_type の判定

| change_type | 入力サイン | Phase 重点 |
|---|---|---|
| `new_product` | 「〜を作りたい（既存なし）」「ゼロから」「新しいプロダクト / サービス / bot」 | Phase B (outcome) を厚く。Phase D viability 必須 |
| `new_feature` | 既存プロダクトに対する「機能を足したい」 | Phase B（既存 outcome との接続）+ Phase C |
| `enhancement` | 「〜を変えたい」「挙動修正」「改善したい」 | Phase B（**直す価値があるか**）+ Phase D usability 重点 |
| `prd_revision` | 「PRD を直したい」「前の PRD に追記」 | 既存 PRD を Read → diff モード（Phase E で revise） |

`enhancement` か `new_feature` か微妙な場合は、対象機能が**既に動いていて顧客が使っているか**で分岐する（使っていれば enhancement）。

---

## Step 2: 顧客タイプの判定

| customer_type | 入力サイン | doctrine |
|---|---|---|
| `external` | 「ユーザに使ってもらう」「販売 / 配布する」「会社のプロダクト」 | INSPIRED 通常運用。CDH の continuous touchpoint を §Open questions に残す |
| `self` | 「自分用」「自分が困ってる」「個人プロジェクト」 | `customer-is-self.md` プロトコル必須 |
| `self-and-close-circle` | 「家族 / パートナー / 友人 5 人以下で」 | self プロトコル + 近接コミュニティ補足 |
| `mix` | 「最初は自分、いずれ外部」 | self プロトコル + scope 拡張時の前提を §Open questions に |

**判定が曖昧なときは self に寄せて始める**（後で external に持ち上げるほうが安全）。

---

## Step 3: 不可逆性 / blast radius の判定

下流の review / 要件定義の厳しさを変えるためのヒント。PRD §Meta に `blast_radius` として記録。

| blast_radius | 例 | review 厳しさ |
|---|---|---|
| `sandbox` | 自分のローカルだけ。お金もデータも他人に触れない | 軽い。riskiest test も小さくて良い |
| `personal-public` | 個人で web 公開。少数の他人が触る可能性 | 中。ethical anti-goals に依存助長 / 誤情報を混ぜる |
| `business` | 会社・チームの業務に影響 | 厚い。viability + 法務 / セキュリティを書かせる |
| `irreversible` | 課金 / 顧客データ / 法的責任 | 最厚。本 skill 単独で完結させない（要件定義 + 設計レビューを必ず回す） |

`irreversible` の場合、本 skill 完了報告で「**要件定義 + 設計レビューを通すまで実装着手しないこと**」を明示する。

---

## Step 4: 既存素材の有無

ユーザが「ノート / 音声 / 過去 PRD / 競合プロダクトリンク / Linear issue」などを持っているか。

- 既存 **PRD** あり → revise モード（Phase E で diff 起こし）
- ノート / 音声 → Phase B/C の入力として活用。長い場合は冒頭で要約させる
- 競合プロダクトリンク → Phase C で alternative observed の参考に
- Linear issue → 本 skill は file-based なので、内容を抜き出して `docs/prd/<slug>.md` に取り込む（Linear 自動同期はしない）

---

## triage の出力スキーマ

Phase A の結果を内部で次の YAML として持つ（PRD §Meta に書き出す）:

```yaml
change_type: new_product | new_feature | enhancement | prd_revision
customer_type: external | self | self-and-close-circle | mix
self_only: bool
blast_radius: sandbox | personal-public | business | irreversible
existing_materials:
  prd_path: docs/prd/<slug>.md | null
  notes: bool
  competitor_links: []
  linear_urls: []

# PRD §Meta への変換規則（Phase E で適用）:
#   existing_materials.prd_path        → related.prior_prd (path or null)
#   existing_materials.notes (bool)    → related.notes (array; bool は「素材が存在するか」フラグ。中身は Phase B/C 入力に展開)
#   existing_materials.competitor_links → related.competitor_links (array)
#   existing_materials.linear_urls     → related.linear_urls (array)
```

これを以後の Phase で参照する。

---

## triage で判定しない（後段に委ねる）

- depth（Lean / Full） — 本 skill は **常に Lean PRD** で固定。Full PRD は将来追加検討
- DB 修正必要性 — `requirements` skill 側の責務（PRD では §Open questions に「DB 影響ありそう」とだけ残す）
- 実装工数見積 — PRD ではなく要件定義 / 設計フェーズ
