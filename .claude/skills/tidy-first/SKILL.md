---
name: tidy-first
description: >-
  既存コードに振る舞いの変更 (機能追加・バグ修正・リファクタを伴う仕様変更) を入れる **直前** に、まず構造の整理 (tidying)
  が必要かを判定し、必要なら tidying だけを先に独立コミットするスキル。Kent Beck の Tidy First?
  の規律に従い、structural change (rename / extract / inline / guard clause / dead code
  削除 / explaining variable / reading order 等) と behavioral change を
  **絶対に同一コミットに混ぜない**。新機能を書く前・テストを書く前・PR
  レビュー指摘の修正前・「リファクタしてから直す」「先に整理」「読みづらいから整える」「巨大関数を分割」「dead code
  消す」「ガード節に直す」「変数名を意味あるものに」「先に rename」のような発話、いずれでも必ず起動すること。本スキルは「整理が必要かを判定する →
  必要な tidying を 1 つずつ独立 commit する →
  振る舞い変更フェーズに渡す」門番で、振る舞いを変える編集は一切しない。pre-commit で混在を物理的に block する hook 設定の指示も含む。
allowed-tools:
  - Read
  - Edit
  - Bash
---
# Tidy First

> **Iron Law**: 1 commit には structural change か behavioral change のどちらか一方しか入れない。

Kent Beck の *Tidy First?* (2023) の規律を AI に強制適用するためのスキル。

整理 (tidying) と振る舞い変更を混ぜたコミットは:
- review が爆発的に難しくなる (差分のどれが意味を変えているのか分離不能)
- revert が部分的にできない (整理だけ戻すと振る舞いが壊れる、振る舞いだけ戻すと整理が消える)
- バグの bisect が壊れる (整理コミットでテストが落ちると原因特定が遅延する)

このスキルは **整理が必要かどうか** と **整理を先にどこまで commit するか** を決め、振る舞い変更の手前で止める門番。実装は呼出側 (`tdd` / 直接編集 / `pr-review-respond` Phase C) に戻す。

---

## いつ起動するか

以下のいずれかに該当したら **編集を始める前に** 起動：

- 機能追加・バグ修正で対象コードを開いた直後 (まず読みやすさを判定)
- TDD で次の失敗テストを書こうとしているが、テストを書くために構造変更が必要そうな時
- `pr-review-respond` Phase C で VALID 判定の修正を当てようとしている時
- リファクタ自体が依頼の主旨である時 (rename / extract / move 等)
- ユーザに「先に整理」「読みづらい」「巨大」「dead」「rename」「ガード節」等の語彙を含む依頼を受けた時

逆に**起動しない**:

- 純粋な振る舞い変更のみで、対象コードが既に十分整理されている時
- ドキュメント・コメント単独の更新
- format / lint ツールが自動適用するスタイル修正
- 設定ファイル (依存 version bump, env, CI 設定) の変更
- 1 行の typo 修正・defensive null check 追加のような瞬間で完結する変更

---

## ワークフロー

### Step 1 — Structural / Behavioral 区別の確定

着手前にこの分類表を当てる。**1 つの編集が両方に該当するなら、それは 2 つの編集に分けるべきもの**。

| 種別 | 定義 | 例 |
|---|---|---|
| **Structural** | 振る舞いを変えない編集 (= 既存テストが全 pass を維持する) | rename, extract function/variable/constant, inline, move (file/dir), reorder, guard clause 化, dead code 削除, explaining variable 追加, comment 削除 / 整理 |
| **Behavioral** | 観測可能な振る舞いを変える編集 (= 新規テストか、既存テストの期待値変更を伴う) | 新機能追加, バグ修正, API 仕様変更, パフォーマンス改善で結果が変わるもの |

判定の鉄則：

- **テストの結果が変わるか** で判定する。既存テスト全 pass が維持されるなら structural。
- リネーム時にテストが落ちるなら、それは「テストが実装詳細に結合している」サインで別件 (詳細は `test-review`)。
- パフォーマンス最適化で計算量だけ変わるなら structural、戻り値や副作用が変わるなら behavioral。

### Step 2 — 整理が必要かの判定

対象コードを読み、以下の 1 つでも該当すれば **整理を先に行う候補**：

- **読みにくい**: 関数 50 行以上 / nesting 3 段以上 / 1 識別子に複数概念 (`data`, `result`, `info`)
- **テストが書きにくい**: 純関数化されていない / I/O が混在 / 内部状態がテストから操作不能
- **修正対象を見つけにくい**: 関連処理が分散 / 似た処理が複数箇所
- **dead code がある**: 未使用 import / 到達不能分岐 / 過去の feature flag の残骸
- **ガード節候補**: 早期 return せず深い else が連なる
- **explaining variable / constant 候補**: magic number / 複雑な式が裸で式中にある

判定が「全て該当しない」なら整理は **行わない**。Beck の原則は「整理は将来の自分への投資、過剰投資もコスト」。当該編集に直接効かない整理は別 PR に切る。

### Step 3 — Tidying カタログから候補を選ぶ

Beck の *Tidy First?* に基づく主要な tidyings。**1 つの commit = 1 つの tidying** が原則。

| Tidying | いつ使う |
|---|---|
| **Guard Clauses** | 早期 return で nesting を浅くする |
| **Dead Code** | 到達不能 / 未使用コードを削る |
| **Normalize Symmetries** | 同じ概念を違う書き方で書いている箇所を揃える |
| **New Interface, Old Implementation** | 古い API の上に薄い新 API を被せる (移行用) |
| **Reading Order** | 読み手のために宣言・関数を並べ替える |
| **Cohesion Order** | 関連するコードを物理的に近づける |
| **Move Declaration and Initialization Together** | 宣言と初期化を隣接させる |
| **Explaining Variable** | 複雑な式を意味のある名前の中間変数に取り出す |
| **Explaining Constant** | magic number を named constant にする |
| **Explicit Parameters** | 暗黙の依存 (環境変数・グローバル) を引数にする |
| **Chunk Statements** | 関連する文を空行でグループ化する |
| **Extract Helper** | 一部の処理を関数に切り出す |
| **One Pile / Many Piles** | 過度に分割されたものを統合 / 巨大ファイルを分割 |
| **Explaining Comments** | 「なぜ」を 1-2 行で残す (実装中の決定根拠のみ) |
| **Delete Redundant Comments** | コードを音読しただけのコメントを消す |

選定の指針：

- **当該の振る舞い変更に直接効くもの** から選ぶ。広範な整理欲望は別タスクに切る。
- **小さいものから順に commit する**。1 commit = 5-30 行の差分が目安。
- **対象範囲を狭める**: 同じファイル内で 3 個 tidying したくなったら、別 commit に分ける。

### Step 4 — Tidying を 1 つずつ独立 commit する

各 tidying について：

```text
1. tidying を 1 つだけ適用
2. 既存テスト全 pass を確認 (verify-done を呼んでもよい)
3. commit する
   commit message 規約: "tidy: <one-line summary>"
   例: "tidy: extract `isEligible` from `processOrder`"
4. 次の tidying へ
```

commit message に **必ず `tidy:` プレフィックス**を付ける。後で `git log --grep '^tidy:'` で整理コミットだけ抽出できるようにする。

**禁止事項**:

- tidy commit 内で振る舞いを変える (たとえ 1 行でも)
- 複数の tidying を 1 commit にまとめる (review 困難になる)
- tidy commit 内に `// TODO`, `// FIXME` を新規追加する (それは振る舞い変更の予兆)

### Step 5 — Behavioral change への引き渡し

整理が完了したら **本スキルは終了**。振る舞い変更は呼出側へ：

- TDD で進めるなら `tdd` (新しい失敗テストを RED にしてから実装)
- 既存テスト変更を伴うバグ修正なら `verify-done` で全 pass 確認後に着手
- レビュー指摘対応なら `pr-review-respond` Phase C に戻る

引き渡し時に **整理 commit のリストをユーザに報告** する (出力フォーマット参照)。

---

## Git hook の推奨設定

混在を物理的に block するため、**`commit-msg` hook** に以下を置くことを推奨する。`pre-commit` ではなく `commit-msg` である理由は、`COMMIT_EDITMSG` (commit message ファイル) は `pre-commit` 段階では未確定であり、`commit-msg` から先でしか参照できないため。本スキルは hook を **生成しない** が、ユーザに提示する：

```bash
#!/usr/bin/env bash
# .git/hooks/commit-msg (or husky/lefthook 経由)
# 引数: $1 = commit message ファイルへのパス
# 1 commit 内で structural と behavioral を混ぜない検出

msg_file="$1"
msg=$(cat "$msg_file" 2>/dev/null || true)
if echo "$msg" | grep -qE '^tidy:'; then
  # tidy commit: 既存テストの期待値変更が含まれていないか検査
  # ヒューリスティック: staged diff で expect/assert 系の追加・削除があれば疑う
  if git diff --cached --name-only | grep -qE 'test|spec'; then
    if git diff --cached -- '*test*' '*spec*' | grep -qE '^[+-]\s*(expect|assert|toBe|toEqual)'; then
      echo "ERROR: tidy commit にテストの期待値変更が含まれます。振る舞い変更は別 commit に分けてください。" >&2
      exit 1
    fi
  fi
fi
```

ファイル種別だけ見たい場合は `pre-commit` 側に分離する選択もある (両方併用可)：

```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit
# 例: 巨大 diff の警告など、message 非依存の検査をここに置く
```

このヒューリスティックは万能ではない (test を tidying するケースは正当)。**規律は人 + AI の側で守り、hook は最終防壁**として運用する。

---

## 出力フォーマット

### Step 2 で「整理不要」と判定したとき

```markdown
## Tidy First: SKIP

対象: <ファイル / 範囲>
判定: 整理不要
理由: <該当しなかった項目を 1-2 行>

→ 振る舞い変更へ進んでよい
```

### Step 3-4 で整理を実施したとき

```markdown
## Tidy First: APPLIED

対象: <ファイル / 範囲>

### Tidyings (commit 順)
1. `<SHA>` tidy: <summary> (<+n / -m>)
2. `<SHA>` tidy: <summary> (<+n / -m>)
3. ...

### 既存テスト
- 各 commit 後に <test command> → 全 pass

### 次の手
振る舞い変更へ進む (`tdd` / 直接編集 / `pr-review-respond` Phase C)
```

### Step 2 で大規模整理が必要と判明したとき

```markdown
## Tidy First: DEFER (大規模)

対象: <ファイル / 範囲>
判定: 整理が当該編集に対して過剰な範囲
推奨: 整理だけを別 PR に切り出す

### 推奨 tidying リスト (別 PR 用)
- ...
- ...

→ 当該編集はスコープを最小に絞って先に進める or 整理 PR を先に着地
```

---

## 出力する成果物 / 出力しない成果物

### 出力する成果物

- **`tidy:` プレフィックス付きの structural change commit 列** (1 commit = 1 tidying、5-30 行差分目安)
- **Tidy First 判定レポート** (SKIP / APPLIED / DEFER のいずれか、固定フォーマット)
- **pre-commit hook の推奨設定文字列** (提示のみ、適用先はユーザ)

### 出力しない成果物

- **振る舞いを変える編集**: 本スキル経由で出る commit は全て既存テスト全 pass を維持する。
- **新規テスト / 既存テストの修正**: tidy 中にテストの assertion / 期待値を変えた diff は出さない。
- **pre-commit hook の自動配置**: `.git/hooks/` や husky / lefthook 設定への自動書き込みは行わない。
- **format / lint 修正のみの commit**: ツールが自動実施するスタイル修正は本スキルの commit 列に含めない。
- **「説明だけのコメント」**: Explaining Variable / Constant への置換が優先。コードを音読するコメント文字列は出さない。
- **当該編集に直接効かない tidying の commit**: 範囲外の整理は DEFER レポートに列挙するのみで、実際の commit は作らない。

---

## 既知の限界

- **「読みにくい」の判定が主観的**: 行数・nesting 等のヒューリスティックを使うが、最終判断は読み手依存。判定が割れたらユーザに確認する。
- **テストが既に壊れている時の挙動**: tidy 前提は「既存テスト全 pass」。pre-existing failure があるなら tidy より先に修復が必要 (本スキルではなくバグ修正フェーズ)。
- **大規模リネームのコスト**: rename はファイル横断で diff が大きくなりがち。Step 3 の「1 commit = 5-30 行」目安を守れない場合は、rename 自体を別 PR に切る判断もある。
- **言語固有の tidying は本スキルでは網羅しない**: TypeScript の `as const` 化や Python の dataclass 化等の言語固有 idiom は、別途 `references/<lang>.md` に切り出す余地あり (現状未整備)。
