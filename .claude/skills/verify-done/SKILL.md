---
name: verify-done
description: >-
  「完了した」「動いた」「直した」「pass
  している」「動くはず」「いけそう」のような完了宣言・成功報告をする直前に必ず起動するゲート用スキル。最後に実際に検証コマンド (test / build /
  typecheck / lint / smoke)
  を実行してから何分経ったか、その出力を本セッション内で目視確認したか、未保存変更が無いか、を順番に潰し、満たさなければ完了報告を差し戻す。Iron Law
  は「NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE」— 過去の
  green、推測、伝聞、`should work` 系の語彙では完了と認めない。実装スキル (tdd / tidy-first /
  pr-review-respond / ci-self-heal 等) の終端、PR 作成前、merge
  直前、ユーザに「できました」「修正しました」「これで OK です」と返す直前、いずれでも必ず起動すること。本スキル自身は修正もコード生成もしない —
  検証実行と判定だけを行う門番。
allowed-tools:
  - Read
  - Bash
---
# Verify Done

完了宣言する前に「証拠が新鮮か」を必ず点検するスキル。

> **Iron Law**: NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.
> 過去の green、推測、`should work`、伝聞は完了の証拠ではない。

完了報告は **約束** であり、約束の根拠が古ければ嘘になる。本スキルは嘘の手前で止めるための門番。

---

## いつ起動するか

以下の語彙を**自分が出力しようとしている / ユーザに返そうとしている**直前に必ず起動：

- 完了系: 「完了」「できました」「終わりました」「対応済み」「修正しました」「実装しました」「直しました」
- 成功系: 「動いた」「動きます」「pass しました」「green です」「通りました」「OK です」「問題ありません」
- 推測系（特に危険）: 「動くはず」「いけるはず」「should work」「probably」「seems to」「たぶん」「おそらく」「いけそう」「見た感じ」

ツール呼び出し直後の自己評価でも、ユーザへの最終報告でも、PR description 起草中でも、適用は同じ。

---

## The Gate Function

5 ステップを順に通す。**1 つでも ✗ なら完了宣言は禁止、差し戻して修正フェーズに戻る**。

### Step 1 — 検証コマンドの存在確認

対象に応じた検証コマンドを 1 つ以上特定する。プロジェクト内の既存設定（`package.json` scripts / `Makefile` / `pyproject.toml` / `justfile` / `.github/workflows/`）から拾う。発見できなければ完了宣言を保留し、ユーザに「このリポジトリの検証コマンドは何ですか」と尋ねる。

典型的な検証コマンド階層（プロジェクト依存）：

| 種類 | 例 |
|---|---|
| typecheck | `tsc --noEmit`, `pyright`, `mypy`, `cargo check` |
| test | `pnpm test`, `uv run pytest`, `cargo test`, `go test ./...` |
| lint | `pnpm lint`, `ruff check`, `eslint .`, `cargo clippy` |
| build | `pnpm build`, `cargo build`, `go build ./...` |
| smoke | `pnpm dev` で起動 + 1 リクエスト, `curl /health`, ブラウザ操作 |

UI / フロントエンドの変更は **typecheck と test の green では完了にならない**。実際にブラウザで操作した / Playwright で smoke を流したかを別軸で確認する。

### Step 2 — Fresh evidence の取得

**今このセッション内で** 検証コマンドを実行する。以下は全て不可：

- 「さっき走らせた時は通っていた」(タイムスタンプが古い)
- 「直近の commit で CI が緑だった」(以降の編集で破壊している可能性)
- 「同じテストを以前見たから大丈夫」(現状の実装は別物)
- subagent からの伝聞（自分の眼で出力を見ていない）

実行後、**最終編集時刻 < 検証実行時刻** であることを確認する。検証後に編集が走ったら Step 2 をやり直す。

### Step 3 — 出力の目視確認

返ってきた exit code と出力本文を**実際に読む**。以下を毎回確認：

- exit code = 0 か
- テスト件数: 期待通りの件数が走ったか（0 件 pass は失敗と扱う）
- skip / xfail / warning が無いか、あるなら理由が明確か
- 変更箇所に対応するテストが実際に走ったか（テスト名で確認）

「通ったように見える」だけで進めない。**出力の最終 1 ブロックをユーザ向け報告に貼れる状態**にする。

### Step 4 — 未保存・未 commit 変更の点検

`git status` と `git diff` を読み、以下を確認：

- 未保存ファイルが無い（IDE バッファに残っていない）
- 修正と無関係な変更が紛れ込んでいない
- 検証後に編集を加えていない
- diff がテストファイル (`*_test.*` / `*.test.*` / `*.spec.*` / `tests/` 配下) を含む場合、`test-mutation-gate` を本セッション内で実行済みであること。未実行なら完了宣言を保留し、先にゲートを通す

検証後に追加編集が必要だった場合は **Step 2 から再実行**。短絡しない。

### Step 5 — 禁止語彙の自己検閲

ユーザへの最終報告ドラフトを書いたら、以下の語彙が含まれていないか検査する：

- `should`, `probably`, `seems`, `looks like`, `appears to`, `I think`, `likely`
- 「はず」「思います」「たぶん」「おそらく」「だと思う」「いけるはず」

含まれていたら **証拠不足のサイン**。Step 2-4 のいずれかが甘い。該当箇所を「実行した・見た・確認した」の事実陳述に書き直すか、書き直せないなら完了宣言を撤回する。

---

## 出力フォーマット

完了宣言時に以下を貼る（Pass / Fail いずれも同じ枠）：

```markdown
## Verification

- typecheck: <command> → <exit> (<n> errors)
- test: <command> → <exit> (<passed>/<total> passed, <skipped> skipped)
- lint: <command> → <exit> (<n> issues)
- (smoke: <手順> → <観測結果>)
- (gate: test-mutation-gate → <PASS/BLOCK>、テストファイル変更時のみ)

最終出力ブロック:
\`\`\`
<検証コマンドの末尾 5-15 行をそのまま貼る>
\`\`\`

git status: clean / <未 commit ファイル一覧>
最終編集 → 最終検証: <編集時刻> → <検証時刻>

判定: PASS / FAIL
```

`PASS` のときだけ完了宣言を出す。`FAIL` のときは「未完了」と明示し、何が落ちているかと次の手だけを返す。

---

## 適用例

### 例 1: 機能追加後

```markdown
## Verification
- typecheck: pnpm tsc --noEmit → 0 (0 errors)
- test: pnpm test packages/foo → 0 (12/12 passed, 0 skipped)
- lint: pnpm lint packages/foo → 0 (0 issues)

最終出力ブロック:
\`\`\`
Test Files  3 passed (3)
     Tests  12 passed (12)
  Duration  4.21s
\`\`\`

git status: clean
最終編集 17:42:03 → 最終検証 17:43:18

判定: PASS
```

### 例 2: ありがちな落とし穴

```markdown
## Verification
- typecheck: pnpm tsc --noEmit → 0
- test: pnpm test → 0 (0/0 passed)   ← ⚠ 0 件、テストが走っていない
- lint: pnpm lint → 0

判定: FAIL
理由: 0 件 pass はテストが選択されなかったサイン。pattern を確認 (`pnpm test packages/foo` か?)。
```

---

## 出力する成果物 / 出力しない成果物

成果物ベースで本スキルの境界を定義する (動詞ではなく出力物で語る規約に従う)。

### 出力する成果物

- **Verification ブロック 1 個** (上記「出力フォーマット」の通り、PASS / FAIL いずれも同形式)
- **検証コマンドの末尾 5-15 行** (出力ブロック内に literal で貼る)
- **判定 1 行** (PASS / FAIL のみ。中間値なし)

### 出力しない成果物

- **編集されたソースコード**: FAIL になっても本スキルからは出ない。`tdd` / `tidy-first` / 直接編集の出力。
- **CI run の URL / status**: ローカル検証のみが本スキルの成果物。CI 関連は `ci-self-heal` の Verification を別途参照。
- **発明された検証コマンド**: プロジェクトに存在しないコマンドの提案文字列は出さない。発見不能ならユーザへの質問 1 件のみを出す。
- **subagent からの伝聞要約**: 「subagent が緑だと言った」式の文字列は出さない。実行ログ literal のみ。
- **完了報告の本文ドラフト** (「これで実装完了です」「mergeしていただけます」等のユーザ向け文言): Verification ブロックのみで、その上にかぶせる報告文は呼出側スキルが作る。
- **`should` / `probably` / `seems` / 「はず」/「思います」を含む任意の文字列**: 禁止語を含む出力は本スキル経由では一切出ない (Step 5 で除去される)。

---

## 既知の限界

- **長時間 build / test (数十分超) の扱い**: バックグラウンド実行 + 通知に切り替える運用余地あり。本スキル単体ではフォアグラウンド待機を前提とする。
- **smoke テストの自動化が UI 依存**: ブラウザ操作・実機確認は人間 or `mcp__plugin_playwright_playwright__*` 系ツールに依存し、本スキルは自動化しない。「smoke を実行したか」のチェックリスト項目として残すのみ。
- **検証コマンドの優先度判定はプロジェクト依存**: typecheck / test / lint / build / smoke のどれが必須かは本スキルでは決められない。プロジェクト規約 (CLAUDE.md / contributing) を読む or ユーザに従う。
