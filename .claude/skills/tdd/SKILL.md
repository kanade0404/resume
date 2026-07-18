---
name: tdd
description: >-
  振る舞いを変えるコード (新機能 / バグ修正 / 仕様変更) を書く際に必ず Test-Driven Development の
  RED-GREEN-REFACTOR サイクルを強制するスキル。production code は **必ず先に失敗するテストを書いてから**
  でしか書かない。「Verify RED」ゲートで失敗理由が typo / import error
  ではなく「機能が未実装」であることを確認してから実装に進む。先にコードを書いてしまった場合は **そのコードを削除してテストから書き直す**。Tidy
  First と併用するときは structural change は本スキル対象外 (テスト不要)、behavioral change のみ TDD
  を適用する。新機能を実装する時、バグ修正を当てる時、API の仕様変更を加える時、`pr-review-respond` Phase C で VALID
  修正を behavioral に当てる時、「TDD
  で」「先にテスト」「赤にしてから」「失敗するテスト書いて」「実装する前に」のような要請、いずれでも必ず起動すること。本スキル単体でカバーするのは 1
  振る舞い 1 サイクル。複数振る舞いの設計や ADR 化は対象外。
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash
---
# TDD (Test-Driven Development)

> **Iron Law**: Production code は failing test の後にしか書かない。先に書いたら **削除して書き直す**。

Kent Beck *Test-Driven Development: By Example* (2002) の RED-GREEN-REFACTOR を AI に強制適用するスキル。

TDD が解くのは「動くコードの保証」だけではなく、**仕様 (テスト) と実装の距離をゼロにすること**。後付けで書かれたテストは実装に追従して書かれるため self-consistent assertion に陥り、検出力を失う (詳細は `test-review` の AI-pattern §5)。

---

## いつ起動するか

- 新機能を実装するとき
- バグ修正を当てるとき (再現テスト → 修正の順)
- API の仕様変更で観測可能な振る舞いが変わるとき
- `pr-review-respond` Phase C で VALID 指摘が behavioral change を伴うとき
- ユーザに「TDD で」「テスト先」「赤にしてから」と言われたとき

逆に **起動しない**:

- structural change のみ (`tidy-first` の領域、既存テスト全 pass を維持できれば追加テスト不要)
- ドキュメント / コメント / 設定ファイル変更
- 自明な typo 修正 (1 文字直すだけ)
- 探索的なプロトタイピング (使い捨て前提、本番に入れない)

---

## ワークフロー (1 振る舞い 1 サイクル)

### Step 1 — RED: 失敗するテストを 1 本書く

書くテストの単位：

- **1 テスト = 1 振る舞い**。複数の振る舞いを同時に検証しない。
- **テスト名は要件文**。`test_<behavior>_when_<condition>` 形式。例: `test_returns_zero_when_input_is_empty`
- **AAA / Given-When-Then** を空行で分離。
- **assertion は state verification 優先**。呼び出し回数や順序に対する assertion は使わない (`test-review` §4 参照)。

### Step 2 — Verify RED (失敗の正当性確認)

テストを実行して失敗することを確認するだけでは不十分。**失敗理由を読む**。

| 失敗理由 | 判定 |
|---|---|
| `AssertionError: expected X got Y` (assertion 自体が落ちる) | ✅ 正当な RED |
| `NotImplementedError` / `attribute error: <new function>` 等の未実装エラー | ✅ 正当な RED (これから実装する関数が未存在) |
| `ImportError` / `ModuleNotFoundError` (typo / パス間違い) | ❌ NOT_RED — テストが構文段階で死んでいる、修正してから再実行 |
| `SyntaxError` | ❌ NOT_RED — テストが文法エラー |
| `TypeError: missing argument` (assertion 前) | ❌ NOT_RED — テストの前提が間違っている |

**NOT_RED で実装に進まない**。テストが落ちる正しい理由が出るまで Step 1 に戻る。

### Step 3 — GREEN: 最小実装で通す

- **テストを通すための最小コード**だけ書く。リファクタは Step 4。
- 一時的に hardcode / fake implementation でも構わない (Beck の "Fake It")。
- **既に書いてあったコード** に対する誘惑があれば、それは「先にコードを書いた」サイン → 削除して Step 1 からやり直す。
- 全テスト pass を確認。**新規テストだけでなく既存テストも全 pass** であること。

### Step 3.5 — Detection Gate (`test-mutation-gate`)

GREEN 確認後・commit 前に、**非自明な分岐・比較・変換を含むテスト**は `test-mutation-gate` を必ず通す。同一セッションで実装とテストを書くと self-consistent assertion (冒頭参照) に陥りやすく、GREEN はテストの検出力を保証しないため。

- 対象外: 自明な scaffolding テスト (存在確認・型チェックのみ)。
- BLOCK が返ったら **commit せず Step 1 に戻り** RED から書き直す。
- 結果 1 行 (`gate: PASS (0 critical / 1 warn)` 等) を Step 5 の TDD Cycle レポート Verify 節に含める。

### Step 4 — REFACTOR: 構造を整える

- GREEN 状態を維持したまま、重複削除 / 命名改善 / 抽出 を行う。
- リファクタは **`tidy-first` のカタログ**を参照する (Tidying の種別)。
- 各リファクタごとにテストを再実行。
- リファクタは GREEN commit と **別 commit** にする (`tidy: ...` プレフィックス)。

### Step 5 — Commit

| Phase | commit message プレフィックス | 例 |
|---|---|---|
| RED + GREEN | `feat:` / `fix:` (1 振る舞い分) | `feat: support empty input in parser` |
| REFACTOR | `tidy:` (1 リファクタ 1 commit) | `tidy: extract validateInput` |

RED テストと GREEN 実装は **同一 commit** に入れる (片方だけ revert すると意味が崩れるため)。

---

## Tidy First との併用

- **structural change** (rename / extract / inline 等) → `tidy-first` で先に独立 commit。テスト追加不要。
- **behavioral change** → 本スキルで RED-GREEN-REFACTOR を回す。

両者を **同じ commit に混ぜない**。混在の判定は `tidy-first` の Step 1 区別表に従う。

迷ったら順序：

1. `tidy-first` で「いま整理が必要か」判定 → 必要なら整理 commit を先に積む
2. 本スキルで RED → GREEN → REFACTOR
3. `verify-done` で完了判定

---

## 出力フォーマット

各サイクル完了時：

```markdown
## TDD Cycle: <behavior>

### RED
- Test: <test file>:<test name>
- Failure reason (verified): <category>

### GREEN
- Implementation: <impl file>:<symbol>
- Commit: `<SHA>` <message>

### REFACTOR
- Tidyings:
  - `<SHA>` tidy: <summary>
  - `<SHA>` tidy: <summary>

### Verify
- All tests: <command> → <passed>/<total>
- Gate: test-mutation-gate → <PASS/BLOCK> (<critical>/<warn>)
```

---

## 出力する成果物 / 出力しない成果物

### 出力する成果物

- **RED テスト 1 本** + Verify RED の失敗カテゴリ判定文字列
- **GREEN 実装** (RED テストと同一 commit、commit message は `feat:` / `fix:`)
- **REFACTOR フェーズの `tidy:` commit 列** (1 commit = 1 tidying)
- **TDD Cycle レポート** (RED / GREEN / REFACTOR / Verify 固定構造)

### 出力しない成果物

- **設計仕様 / spec ドキュメント**: 仕様起草は `design` / requirements 領域、本スキルでは出さない。
- **structural change のみの commit**: `tidy-first` の出力に委ねる。
- **CI 検証の結果**: `ci-self-heal` の領域、本スキルはローカル test 実行のみ。
- **根拠のない既存テストの assertion / 期待値変更 diff**: 既存テスト全 pass 維持が原則。**意図的な仕様変更**で既存テストの期待値変更が必要な場合のみ、RED で先に新仕様の失敗を示した直後の対応 diff として許可する (RED-GREEN サイクル内に閉じる、コミットも分離する)。
- **「先にコードを書いた」状態の commit**: テスト先行違反のコードは保持せず、削除と書き直しの commit を出す。
- **mock / stub を多用したテストコード**: test double は `test-review` §4 の規律で最小限、本スキルからは推奨も生成もしない。

---

## 既知の限界

- **UI / E2E 振る舞いの RED-GREEN は重い**: ブラウザ操作を伴う振る舞いはローカル TDD ループに組み込みにくい。本スキルは unit / integration を主対象とし、E2E は `test-review` §9 の予算原則に従って別レイヤで扱う。
- **「最小実装」の主観**: Fake It / Triangulate / Obvious Implementation の選択は判断が必要 (Beck 本 Part 1)。本スキルは「テストを通す最小」とだけ規定し、選択基準は実装者に委ねる。
- **言語固有の TDD 慣習は網羅しない**: Hypothesis / Quickcheck の property-based、pytest の parametrize 等は `skills/test-review/references/python.md` に委ねる。
