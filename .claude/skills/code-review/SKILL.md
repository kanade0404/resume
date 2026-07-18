---
name: code-review
description: >-
  実装が完了した後・PR 作成前に、変更差分を白紙の subagent にレビューさせて Critical / Important / Minor の三分類で
  findings を返すゲート用スキル。観点は spec 準拠、責務逸脱、依存方向違反、null/error handling、命名、test
  coverage、副作用混入、unused code、performative comment / dead code 残し、AI 生成パターン
  (self-consistent assertion 等は `test-review` 参照)。実装直後・「コードレビューして」「PR
  出す前にチェック」「実装見て」「これで OK?」「マージ前確認」のような要請、`pr-review-respond`
  での修正完了直後、いずれでも必ず起動すること。本スキルは subagent によるセルフ・コードレビューで、CodeRabbit / Devin /
  人間レビュアーの代替ではなく **PR 起票前のセーフティネット**。findings は実装者 (= 本スキル呼出側) に返り、修正後に
  `verify-done` を経て PR 起票へ。subagent には書き手の前提知識を持ち込ませない。
allowed-tools:
  - Read
  - Bash
  - Task
---
# Code Review

> **規律**: 書き手に評価させない。**書き手の頭の中を持ち込まない subagent** にコードだけを読ませて、PR 起票前に最後の盲点を炙り出す。

`pr-review-respond` が外部レビュアー (CodeRabbit / Devin / 人間) のフィードバックに対応するスキルなのに対し、本スキルは **PR を出す前** に同種のレビューを内製する。外部レビュアーの仕事を奪うのではなく、自明な指摘で PR を汚さないため。

---

## いつ起動するか

- 実装が GREEN になった直後 (TDD の REFACTOR 後 or 直接編集後)
- `pr-review-respond` Phase C で VALID 修正を当てた直後
- PR 起票前 (gh pr create の直前)
- ユーザに「コードレビュー」「PR 前確認」「実装見て」と言われた時

逆に **起動しない**:

- WIP の途中段階 (REFACTOR 前 / 全テスト未 pass)
- 単純な typo / format 修正のみ
- 既に PR が出ている (それは `pr-review-respond` の領域)

---

## ワークフロー

### Step 1 — 差分の特定

```bash
git diff --name-only <base>...HEAD       # 変更ファイル
git diff <base>...HEAD                   # 全 diff
git log --oneline <base>..HEAD           # commit ヒストリ
```

`<base>` は PR の予定 base ブランチ (default `main` / `master`)。

### Step 2 — Subagent への入力

Task tool で `feature-dev:code-reviewer` または `pr-review-toolkit:code-reviewer` を起動 (利用可能な方)。なければ `general-purpose`。

プロンプトに必ず含める:

- 「あなたはコードレビュアーです。実装者の前提知識は持ち込まない」
- 変更ファイル一覧と diff
- 関連 ADR / spec があればパス参照
- 観点リスト (下記)
- severity 三分類フォーマット
- "performative agreement 禁止" / 「妥当性を verify してから指摘する」

### Step 3 — レビュー観点

```markdown
## 観点

1. Spec / Requirements 準拠 — 実装が要件を満たしているか / 過剰実装はないか (YAGNI)
2. 責務 — 変更で増えた module/class/function は単一責務か / 既存責務と重複していないか
3. 依存方向 — 不安定 → 安定 の方向か / domain → infra になっていないか / 循環参照は無いか
4. Error / Null Handling — 失敗パスが明示的か / silent failure / catch-and-ignore はないか / 復旧可能なエラーと不能なエラーの区別がついているか
5. 副作用 — 純関数化できる部分が外部 I/O と混在していないか
6. 命名 — 1 識別子 1 概念 / data/result/info のような曖昧名はないか / 動詞句で関数名 / 名詞句で型名
7. Test Coverage — 変更箇所のテストが新規 or 更新されているか / 既存テストが破壊されていないか / AI 生成パターン (self-consistent assertion / oracle copy-paste 等) はないか
8. Dead Code / Unused — 未使用 import / 到達不能分岐 / コメントアウトされたコード / 過去の feature flag 残骸
9. Performative Comments — コードを音読しただけのコメント / TODO/FIXME 新規追加
10. Convention — CLAUDE.md / 既存 ADR / 既存コードの慣例と矛盾していないか

## Severity

- Critical: マージするとバグ / セキュリティ / 重大な技術的負債を生む → ブロック
- Important: PR 前に対処すべき / マージ可能だが reviewer に説明が必要 → 対処を要求
- Minor: 改善余地はあるが PR 後でも良い / 取捨選択は実装者
```

### Step 4 — Findings の収集

subagent からの戻り値を以下の構造で受け取る：

```markdown
## Critical
- [<file>:<line>] [<観点>] <issue 1 行>
  - Suggested action: <具体的な修正提案 1 行>

## Important
- ...

## Minor
- ...

## What's good
- ...
```

### Step 5 — 判定と次の手

| 状態 | 次の手 |
|---|---|
| Critical = 0 / Important = 0 | PASS — `verify-done` を経て PR 起票へ |
| Critical = 0 / Important > 0 | PASS_WITH_FIXES — Important を対処してから再 review |
| Critical > 0 | FAIL — 実装に戻る |

呼出側に判定と findings をそのまま返す。本スキル内で修正はしない。

### Step 6 — Pushback の余地

subagent の指摘が技術的に不適切と判断した場合、`receiving-code-review` の規律に従い:

- 「You're absolutely right!」式の自動同意は禁止
- INVALID と判定する正当化を 1 文で書ける場合のみ pushback (YAGNI / 既存方針 / 前提誤り / トレードオフ)
- pushback したものはユーザ報告に **明示** する (黙って無視しない)

---

## 出力フォーマット

```markdown
## Code Review

### Scope
- Base: <branch>
- Files changed: <n>
- Commits: <n>

### Findings
- Critical: <n>
- Important: <n>
- Minor: <n>

### Critical (blocks)
- [<file>:<line>] [<観点>] <issue> → <action>

### Important (fix or 説明)
- ...

### Minor
- ...

### Pushback (subagent 指摘を却下)
- [<観点>] <subagent 指摘> → 却下理由: <YAGNI / 既存方針 / 前提誤り / トレードオフ>

### What's good
- ...

### Verdict
- PASS / PASS_WITH_FIXES / FAIL
- Next: PR 起票へ / Important 対処 / 実装に戻る
```

---

## 出力する成果物 / 出力しない成果物

### 出力する成果物

- **10 観点 × severity 三分類の findings リスト** (Critical / Important / Minor / What's good の固定構造)
- **Verdict** (PASS / PASS_WITH_FIXES / FAIL + 次の手 1 行)
- **Pushback リスト** (subagent 指摘を却下した分は根拠 1 行と共に明示)

### 出力しない成果物

- **修正コード差分**: findings のみ返し、修正は呼出側 (実装フェーズ)。
- **テスト実行結果 / Verification ブロック**: テスト実行と完了判定は `verify-done` 領域、本スキルは静的レビューのみ。
- **PR 起票 (gh pr create) コマンド or 結果**: PR 起票は `commit-commands:commit-push-pr` 等の別経路。
- **CodeRabbit / Devin 互換のスキャン結果**: 依存スキャン / セキュリティスキャンは外部レビュアーの領域、本スキルからは出さない。
- **同一 subagent での再 review 結果**: 修正後は新規 subagent dispatch、過去 agent の再利用出力はない。
- **subagent 指摘の盲信受容**: pushback 候補は出力に明示、根拠なしの自動同意は出さない。

---

## 既知の限界

- **subagent の context window 制限**: 大規模 diff (数千行) は 1 subagent で全件読めない。ファイル単位で分割 dispatch する運用余地。本スキルは 1 dispatch で完結する規模を前提。
- **静的レビューの限界**: 実行時の振る舞い (race / leak / 性能) は静的レビューで検出不能。`verify-done` のテスト実行 + 必要なら専用ツール (profiler / sanitizer) で補う。
- **Solo dev 向け**: チーム運用では subagent レビューに加えて人間レビューが必須。本スキルは「人間レビューの前段」として位置付ける場合も使える。
- **subagent agent type の可用性**: `feature-dev:code-reviewer` 等が利用できない環境では `general-purpose` にフォールバック。観点リストの効果は同等。
