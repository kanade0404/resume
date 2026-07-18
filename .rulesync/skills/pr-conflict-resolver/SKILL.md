---
name: pr-conflict-resolver
description: |
  GitHub PR で発生した merge conflict を自動修正するための手順とベストプラクティス。
  PR コメントで `@claude` 経由で呼ばれた conflict 解決タスクや、ローカルでの rebase / merge
  conflict を解決するときに必ず参照する。チェックアウト → merge → conflict 解決 →
  lock ファイル再生成 → 検証 → commit で merge を確定 → push までの一連の安全な流れを、
  同梱スクリプト (`scripts/*.sh`) の決定的な実行として定義する。
claudecode:
  allowed-tools:
    - Bash
    - Read
    - Edit
    - Write
    - Glob
    - Grep
---

# PR conflict resolver

PR のターゲットブランチ (base) と head ブランチの間で発生した merge conflict を、機能を欠落させず
安全に解決するための手順。

## 実行環境前提

本スキルは **対話ローカル実行 / ヘッドレス実行 (Claude Code Action 等) の両方**で使う。
呼び出し元が人間かどうかに関わらず、以降の手順は同一とする:

- 判断が必要な分岐 (ソース conflict の統合方針、撤退判断) で**人間に質問して止まる設計にしない**。
  ヘッドレスでは応答が来ないため、質問した時点でセッションが unattended のまま放置される。
- 継続不能なときは 4 章「エスカレーション」の **`needs-human` ラベル + 構造化コメント**で停止する。
  これは対話環境でも同じ挙動にする (人間に質問するのではなく、判断材料を残して停止し、人間の
  タイミングでコメントを読んでもらう)。
- 決定的な多段操作 (PR 情報抽出・merge 実行・lockfile 再生成・検証・push 前確定) は
  すべて `scripts/*.sh` に閉じ込めてある。**フラグを追加したり、同等のコマンドを手で
  組み立てて代替したりしない** — 実行者ごとの手順のブレをなくすための決定的スクリプトなので、
  そのまま実行する。

## 同梱スクリプトと権限

```text
scripts/
├── pr-context.sh       # 0. PR 情報の取得
├── resolve-merge.sh    # 2. base の merge 実行 + conflict 検出
├── regen-lockfiles.sh  # 3. lockfile の再生成
├── verify.sh           # 4. 検証チェーン
└── finalize.sh         # 5. commit で merge 確定 → push 前チェック → push
```

| script | 役割 | exit code |
|---|---|---|
| `pr-context.sh <PR番号>` | `gh pr view --json` で `PR_NUMBER`/`PR_HEAD`/`PR_BASE`/`PR_TITLE`/`PR_URL`/`PR_HEAD_SHA` を `eval` 可能な `NAME=value` 形式で stdout に出力 | 0=成功、127=`gh`/`jq` 不在、1=PR 取得失敗、2=usage |
| `resolve-merge.sh <base-branch>` | `origin/<base>` を `--no-ff --no-edit` で merge。stdout は conflict ファイル一覧のみ (git 自身の進捗メッセージは stderr に retarget 済み) | 0=conflict なし (merge 完了済み)、10=conflict あり (stdout に一覧)、その他=想定外の merge 失敗 |
| `regen-lockfiles.sh <path...>` | 渡された各パスの basename でエコシステムを判定し `case` 文で再生成 (`package-lock.json` / `pnpm-lock.yaml` / `yarn.lock` / `bun.lock(b)` / `Cargo.lock` / `poetry.lock` / `uv.lock` / `go.sum` / `Gemfile.lock`)。未知の lockfile は再生成せずエラー | 0=全件成功、1=1件以上失敗、2=usage |
| `verify.sh` | repo 検出 (`package.json`/`pyproject.toml`/`go.mod`/`Cargo.toml`/`Makefile`) に応じて tsc/lint/test 等を実行。**`\|\| true` は使わない** — 各チェックの exit code をそのまま保持する | 0=全チェック PASS (未検出時も PASS 扱い)、1=1件以上 FAIL |
| `finalize.sh <push-branch> <resolved-file...>` | conflict marker の残存チェック → `git add` → `git commit` で merge を確定 → push 前チェックリスト → `git push` | 0=push 完了、1=チェックリスト不通過または push 失敗、2=usage |

`scripts/*.sh` は `bash "${CLAUDE_SKILL_DIR}/scripts/<name>.sh" <args>` で呼び出す。
最小依存 (`bash`, `git`, `gh`, `jq`) のみを前提とし、Python/Node 等の追加ランタイムは使わない。

## 0. 前提情報の確認

呼び出し元のコメントに PR 番号があればそれを使う。明示的な解決方針の指示 (例:「lock ファイルは
theirs を採用」) があれば以降の手順より優先する。

`scripts/pr-context.sh <PR番号> を正確に実行。フラグ追加禁止。`

```bash
eval "$(bash "${CLAUDE_SKILL_DIR}/scripts/pr-context.sh" <PR番号>)"
```

以降 `$PR_NUMBER` / `$PR_HEAD` / `$PR_BASE` / `$PR_TITLE` / `$PR_URL` / `$PR_HEAD_SHA` を使う。

## 1. ブランチをチェックアウト

```bash
git fetch origin "$PR_BASE" "$PR_HEAD"
git checkout "$PR_HEAD"
git pull --ff-only origin "$PR_HEAD"
```

`--ff-only` は他者の push を上書きしないための安全策。fast-forward できないときは
push が走った可能性があるので `git status` で状態を確認し、想定外であれば
4 章の手順でエスカレーションする (無理に `--force` で追従しない)。

## 2. base を merge して conflict を検出

rebase ではなく **merge** を既定とする。PR の commit 履歴・署名 (Co-Authored-By 等) を
壊さず、レビュー中の force-push による差分見失いも避けられるため。**rebase への切り替えは
サポートしない** — 同梱スクリプトは merge 専用に決定的な処理を組んでおり
(`finalize.sh` は `MERGE_HEAD` の存在と非 force push を前提とする)、rebase は履歴を
書き換えて force push が必要になる (「destructive git 禁止」のガードレールと矛盾する)
うえ `finalize.sh` では完了処理できない。rebase を明示的に希望された場合は 4 章の手順で
エスカレーションする。

`scripts/resolve-merge.sh を正確に実行。フラグ追加禁止。`

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/resolve-merge.sh" "$PR_BASE"
```

exit code で分岐する:

- **0** — conflict なし。merge commit は作成済み。3〜4 章を飛ばして 5 章 (`finalize.sh`) へ進む。
- **10** — conflict あり。stdout に conflict ファイル一覧 (1 行 1 ファイル) が出力される。
  3 章に進んで各ファイルを解決する。
- **それ以外** — 認証エラーや壊れた ref 等、merge conflict 以外の理由での失敗。
  **conflict 解決フローに進まない**。4 章の手順でエスカレーションする。

## 3. conflict 箇所を種別ごとに解決する

`resolve-merge.sh` が出力した一覧をファイル種別で振り分ける:

| ファイル種別 | 戦略 |
|------------|------|
| ソースコード | 下記「ソース conflict 解決ガイドライン」に従い Edit ツールで手で解決 |
| lock ファイル (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock(b)`, `Cargo.lock`, `Gemfile.lock`, `poetry.lock`, `uv.lock`, `go.sum`) | `scripts/regen-lockfiles.sh` に渡して再生成する (手で marker を編集しない) |
| 生成物 (`dist/`, `build/`, `*.min.js`, snapshot) | `.gitignore` 漏れがないか確認した上で、可能ならビルドし直して上書き |
| バイナリ | `git checkout --theirs <path>` または `--ours <path>` で base/head どちらかを採用。採用理由を最終コメントに残す |

lock ファイルは `scripts/regen-lockfiles.sh を正確に実行。フラグ追加禁止。`

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/regen-lockfiles.sh" <conflict した lockfile のパス...>
```

未知の lockfile 名 (`case` の `*)` 分岐) は再生成コマンドを推測せず失敗する。その場合は
手動解決に切り替えるか、4 章の手順でエスカレーションする。

### ソース conflict 解決ガイドライン

1. **両側の意図を読む**: `git log --merge -p <file>` で双方の commit 履歴と差分を確認
2. **関数/ブロック単位で統合**: 片側削除を安易に選ばない。同じ箇所への重複編集は **両方の機能を残す**
3. **import / 型定義 / API シグネチャ** は両側の変更を合算
4. **テストファイル** は両側のケースを残し、重複は名前を変えて両立させる
5. 解決後、conflict マーカー (`<<<<<<<`, `=======`, `>>>>>>>`) が残っていないことを
   `grep -rnE '^<<<<<<< |^=======$|^>>>>>>> ' .` で確認する (`finalize.sh` も同じチェックを
   `git add` 前に強制するが、無駄な手戻りを避けるため先に自分で確認しておく)

判断が難しい場合 (相反する仕様変更、両方残すと壊れるロジック等) は **無理に解決せず**、
4 章「エスカレーション」に従って停止する。ユーザに質問して応答を待つ設計にはしない。

## 4. 検証

`scripts/verify.sh を正確に実行。フラグ追加禁止。`

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/verify.sh"
```

exit 0 (`RESULT: PASS`) でなければ **conflict 解決の副作用がある**とみなし、5 章に進まない。
出力の各行 (`<name>: PASS|FAIL`) は完了コメントにそのまま転記する — 実行していないチェックを
PASS と書かない。タイムアウトや外部依存で特定チェックが実行不能な場合は `verify.sh` の出力
どおりに (`FAIL` として) 報告し、CI 側の再走に委ねる旨を追記する。**`\|\| true` 等で失敗を
握り潰して push に進まない。**

## 5. commit で merge を確定し push する

`scripts/finalize.sh を正確に実行。フラグ追加禁止。`

呼び出し方は 2 章の `resolve-merge.sh` の exit code で変わる:

- **conflict あり (exit 10) で 3 章を経由した場合** — 解決した全ファイルを渡す:

  ```bash
  bash "${CLAUDE_SKILL_DIR}/scripts/finalize.sh" "$PR_HEAD" <3章で解決した全ファイルのパス...>
  ```

- **conflict なし (exit 0) で 3〜4 章を飛ばした場合** — `resolve-merge.sh` の
  `git merge` が merge commit を作成済み (`MERGE_HEAD` は既に消えている) なので、
  ファイル一覧を渡さず push 前チェックリストだけを実行させる:

  ```bash
  bash "${CLAUDE_SKILL_DIR}/scripts/finalize.sh" "$PR_HEAD"
  ```

このスクリプトが強制する順序 (手動での代替手順を組み立てない):

1. `MERGE_HEAD` の有無で分岐する。存在すれば 2〜5 (conflict 解決パス)、なければ
   ファイル一覧が空であることだけ確認して 6 のチェックリストに直行する
   (`MERGE_HEAD` なしでファイル一覧が渡されていたらエラーで停止する — exit code の
   取り違えを検知するため)
2. 渡されたファイル一覧が、git が把握している unmerged パス全体をカバーしていることの確認
3. 渡された各ファイルに conflict marker が残っていないことの確認 (`git add` 前に実施 —
   `git add` 自体は marker が残っていても unmerged 状態を消してしまうため、ここでしか
   検知できない)
4. `git add -- <ファイル一覧>` (`git add -A` は使わない — 無関係な変更を巻き込まないため)
5. `git commit --no-edit` で merge commit を確定
6. push 前チェックリスト (working tree clean / `MERGE_HEAD` 消滅 / unmerged パスなし /
   想定ブランチに HEAD がある)
7. `git push origin "$PR_HEAD"` (force push は使わない — merge commit である限り不要)

exit 0 で完了。exit 1 の場合、**merge commit は既にローカルに作成されている**ことがあるため
(2〜3 のチェック不通過ならまだ未作成、6 のチェック不通過なら作成済みでの停止)、
stderr のメッセージを読んでから対応する。盲目的にスクリプトを再実行しない。

push 後、PR に以下フォーマットで結果コメントを残す:

```markdown
### conflict 解決完了

- 解決方針: merge
- 解決したファイル:
  - `path/to/file.ts` — <統合内容を 1 行で>
  - `package-lock.json` — 再生成 (`regen-lockfiles.sh`)
- 検証結果 (`verify.sh` の出力をそのまま転記):
  - tsc: PASS
  - lint: PASS
  - test: FAIL <理由>
- 残課題: <あれば箇条書き / なければ「なし」>

push: `<commit-sha>`
```

## エスカレーション (無理しない撤退)

次のいずれかに該当するときは **その場で解決を試み続けず**、`needs-human` ラベル + 構造化
コメントで停止する:

1. 機能仕様レベルで相反する変更 (双方の機能を両立させると要件矛盾になる)
2. 同一テストケースに対する期待値が両側で食い違う
3. 巨大な自動生成物 (protobuf, GraphQL schema, OpenAPI 等) の手解決が現実的でない
4. `secrets` / 認証情報 / migration 順序など、誤った解決が破壊的になるもの
5. `regen-lockfiles.sh` が未知の lockfile でエラー終了し、手動解決も安全に行えない
6. `verify.sh` が 5 回以上修正を試みても `RESULT: PASS` にならない
7. `resolve-merge.sh` が exit 10 (conflict) 以外の非ゼロで失敗した (2 章)

手順:

1. `gh label create needs-human --color FBCA04 2>/dev/null || true` (既存なら no-op 扱い)
2. `gh pr edit "$PR_NUMBER" --add-label needs-human`
3. コメント本文を一時ファイル (例: `/tmp/escalation-comment.md`) に Write ツールで書き出し、
   `gh pr comment "$PR_NUMBER" --body-file <path>` で投稿する。本文の形式:

````markdown
<状況の自由文: 何を試し、なぜ止まるのか。conflict が起きているファイルと衝突箇所の概要、
両側の変更意図の推定、推奨される解決方針を含める>

<!-- loop-escalation:v1 -->
```json
{"reason": "conflict", "detail": "<1-2 文>", "attempts": <試行回数>, "next_action_hint": "<人間の最短の一手>"}
```
````

ユーザに質問して応答を待つ設計にはしない — コメント投稿とラベル付与をもって処理を終了する。
`needs-human` 対応後の再開は人間または別トリガに委ねる。

## ガードレール

- **destructive git 禁止**: `push --force*` / `reset --hard` を使わない。merge commit は
  常に追加コミットとして扱う
- **secrets を読まない・書かない・ログに出さない**: `.env*`, `*.tfvars`, 鍵類が conflict
  していたら 3 の条件でエスカレーションする
- **`.github/workflows/` の conflict は自動解決しない**: エスカレーションする (security-block 相当)
- **PR を merge しない**: merge は常に人間ゲート
