---
name: design
description: >-
  要件が確定した後、実装に入る前に、構造選択・I/O 境界・依存方向・外部制約を**会話 /
  一時ファイル**で検討するスキル。設計ドキュメントを永続化することは目的としない —
  コードを読めばわかる範囲は書かず、**コードを読んでもわからない外部要因・制約・選択肢と却下理由のみ ADR に蒸留**する (ADR 化は
  `adr-writer` の責務)。設計の検討内容は temp scratchpad (`<work-dir>/design-scratch.md`
  等、配布先で gitignore 推奨) に書き、PR マージ後は破棄。要件 → 実装の間、`pr-review-respond` で
  VALID_DEFER を新規 issue 化する時、「設計どうする」「アーキ考えて」「どこに置く」「依存方向は」「I/O
  境界どこ」「先にデザインして」のような要請、いずれでも必ず起動すること。本スキルは設計の **検討と決定の蒸留** までで、実装・テスト・ADR
  文面化は別スキルに渡す。詳細仕様の永続化や spec ファイル化は意図的にしない。
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Task
---
# Design

> **規律**: コードを読めばわかる設計を文書に残さない。残すのは **コードを読んでもわからないもの** (外部制約・却下した選択肢・トレードオフの根拠) のみ、それも `adr-writer` 経由で ADR に蒸留する。

設計ドキュメントを長期保管しない理由：

- 実装と乖離する (rot)
- 読み手は結局コードを読む (二度手間)
- 「決定の理由」だけがコードから読めず、それは ADR のスコープ

本スキルは **検討の場** を temp に確保し、**決定** を ADR に渡し、**過程** は破棄するワークフローを駆動する。

---

## いつ起動するか

- 要件が確定した直後 (requirements / requirements-review が PASS)
- `pr-review-respond` で VALID_DEFER を新規 issue / 別 PR に切る時の方針メモ
- 既存コードに大きく手を入れる前 (アーキへの影響範囲が読めない時)
- ユーザに「設計」「アーキ」「どこに置く」「I/O 境界」「依存方向」「責務」と聞かれた時

逆に **起動しない**:

- 設計上の選択がほぼ自明な小修正 (typo / 1 関数の振る舞い修正)
- リファクタのみで構造を増やさない (`tidy-first` の領域)
- 既に ADR が存在する領域への追従実装

---

## ワークフロー

### Step 1 — Scratchpad の準備

`<work-dir>/design-scratch.md` を作る。配置先の指針：

- 配布先プロジェクトに `.gitignore` で `design-scratch.md` / `*.scratch.md` / `z/**/scratch.md` を追加 (本スキルは推奨提示まで、自動編集はしない)
- 既存の sengoku 流 `z/{task}/{session}/` パターンがあればそこを使う

### Step 2 — 検討項目チェックリスト

scratchpad に以下を 1 項目ずつ書く。**書けない項目があるならそれが論点**:

- **境界 (Boundaries)**: 入出力は何か / 外部 (DB / API / 他サービス) との接点はどこか / 同期 or 非同期 / batch or stream
- **依存方向 (Direction of Dependencies)**: 安定したものに依存する / domain → infra ではなく infra → domain にしない / 循環参照を作らない
- **責務 (Responsibilities)**: この変更で増える module / class / function は何の責務か / 既存責務との重複は無いか
- **可逆性 (Reversibility)**: この設計選択は後で変えられるか / one-way door か two-way door か (Bezos の表現)
- **外部制約 (External Constraints)**: コードからは読めない事実 — 法令・SLA・他チームとの API 契約・本番運用上の理由・パフォーマンス予算
- **テスタビリティ (Testability)**: 純関数として抽出できるか / I/O は薄い shell に押し出せるか / test double 不要で書けるか
- **代替案 (Alternatives)**: 採用案以外に検討した選択肢を最低 2 つ / 各却下理由を 1 行

### Step 3 — 検討の進め方

Single-pass で書ききらない。**書きながら却下案を増やす**。3 案以上比較できないなら検討が浅い。

迷ったら投げる質問：

- 「これを 1 年後に削除するとしたら何箇所変更が必要か」 (一way door 度の指標)
- 「これがコードから読めるか」 (Yes なら ADR にしない)
- 「既存コードのどの慣例と一致するか / 矛盾するか」 (慣例と矛盾するなら ADR 必須)
- 「この決定の前提となる外部要因は何か」 (前提が変われば再考する trigger)

### Step 4 — ADR 化判定

検討が固まったら **`adr-writer` を呼ぶ** (Task tool 経由)。`adr-writer` 側が「ADR に値するか」を 1 次判定する。判定基準は当該スキル参照。

ADR に値しないと判定された場合は、**何も永続化しない**。scratchpad は PR マージ後に破棄。

### Step 5 — design-review への引き渡し

scratchpad と (生成された場合は) ADR ドラフトをセットで `design-review` に渡す。レビュアー subagent が severity 三分類で findings を返す。

Critical が残っているなら Step 2 に戻る。Important 以下は次の実装フェーズに引き継ぎ可能。

### Step 6 — Scratchpad の破棄計画

PR マージ後に scratchpad を削除する旨を **PR description に明記する** (約束を残す)。例：

```markdown
## Scratchpad
- z/<task>/<session>/design-scratch.md (post-merge: delete)
- ADR added: docs/adr/0042-... .md (persistent)
```

---

## 出力フォーマット

ユーザへの最終報告：

```markdown
## Design

### Scratchpad
- Path: <work-dir>/design-scratch.md (temp, gitignored)

### 採用案
<1-3 行で要約>

### 却下案 (理由)
- <案 A>: <却下理由 1 行>
- <案 B>: <却下理由 1 行>

### ADR 化判定
- 値する / 値しない (理由 1 行)
- (値する場合) ADR draft → adr-writer に dispatch 済 → docs/adr/<NNNN>-<slug>.md

### Review
- design-review findings: Critical=<n> / Important=<n> / Minor=<n>
- Critical 残: <あれば一覧 / なければ "なし">

### 次の手
- 実装へ (`tdd` / 直接編集) / Critical 解消のため再設計
```

---

## 出力する成果物 / 出力しない成果物

本セクションは成果物ベースで境界を定義する (動詞ではなく出力物で語る)。

### 出力する成果物

- **`design-scratch.md` (temp ファイル 1 つ)** — 採用案 + 却下案最低 2 個 + 却下理由を含む
- **`adr-writer` への dispatch 入力** (該当時のみ、ADR 候補のネタ)
- **`design-review` への dispatch 入力**
- **ユーザ向け Design レポート** (Scratchpad path / 採用 / 却下 / ADR 化判定 / Review findings / 次の手 の固定構造)

### 出力しない成果物

- **永続化された spec.md / design.md**: 設計仕様の長期保管ファイルは作らない。
- **実装コード / テストコード**: 検討までで止める。実装は `tdd` / 直接編集の出力。
- **ADR の本文文字列**: `adr-writer` が出す。本スキルは ADR 候補のネタを渡すまで。
- **要件文書の修正**: 要件側の曖昧さは requirements / requirements-review に戻す。
- **大規模な ER 図 / シーケンス図**: 図はコードと乖離する。必要なら ADR の Context に短い記述として埋め込む程度。
- **scratchpad の削除コミット**: PR マージ後の scratchpad 削除は人間 / 後続スキル (clean_gone 系) の責任、本スキルからは出さない。

---

## 既知の限界

- **「コードを読めばわかる」の境界が主観**: 慣例的な構造選択は ADR 不要だが、慣例から外れる選択は ADR 必須。境界判定は人間判断に委ねる。
- **Solo dev 前提**: 複数人レビューを前提にしない。チーム導入時は Mob Elaboration 的な検討儀式が別途必要 (AI-DLC 参照)。
- **scratchpad の gitignore 設定は提案のみ**: `.gitignore` を自動編集しない。プロジェクト規約の更新は別経路。
- **検討の深さは時間予算依存**: Step 2 のチェックリスト全項目を書ききるのは大規模設計のときのみ。小設計では「境界 / 依存方向 / 代替案」3 項目だけ書いて先に進めて良い。
