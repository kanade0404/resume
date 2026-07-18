---
name: linear-issue-driven-development
description: |
  Linear で "claude:ready" ラベルが付いた issue 1 件を、対象リポジトリの clone →
  実装 → commit → PR → CI all-green → レビュー (人間 / CodeRabbit) コメント解消まで
  ヘッドレスで完遂させるためのワークフロー。

  use when:
    - Anthropic Routines (`/schedule` で登録した recurring agent) が 1 時間毎に
      この skill をトリガーする
    - 人間が `/linear-issue <IDENTIFIER>` を打って手動で再実行する

  実行環境はクラウド (Anthropic 側 sandbox) を想定しているため、`gw` 等の
  dotfiles 同梱ヘルパには依存しない。素の `git` / `gh` / `curl` だけで動くこと。
  本ループ (loop-ops 駆動) では非対象。GitHub issue は issue-driven-development
  を使うこと — 本 skill は Linear issue 専用。
---

# linear-issue-driven-development

Linear issue を 1 件受け取り、PR がマージ可能な状態 (CI 緑 + 未解消レビュー
コメント 0) になるまで自走するスキル。

## 前提となる secret / env

| 変数 | 用途 |
|---|---|
| `LINEAR_API_KEY` | Linear GraphQL 認証 (`Settings → API → Personal API key`) |
| `GH_TOKEN` | `gh auth login --with-token` 用 PAT (repo / workflow / write) |
| `ANTHROPIC_API_KEY` | Routine 実行に必要 (登録時に自動設定) |
| `LOCK_LEASE_TTL_SECONDS` | 任意。lock lease の失効秒数 (既定 3600) |

Routine の secrets 欄に設定する。手元で `/linear-issue` を打つ場合は環境変数で
渡す。未設定なら即フェイル (`LOCK_LEASE_TTL_SECONDS` のみ未設定でも既定値で続行)。

## 入力契約

セッション冒頭のメッセージから issue を取得するパスは 2 つ:

### A. Routine モード (orchestrator が呼び出す場合)

orchestrator (routine prompt 側) が GraphQL で 1 件選んで JSON を渡す:

```json
{
  "id": "uuid",
  "identifier": "ENG-123",
  "title": "...",
  "description": "...",
  "url": "https://linear.app/...",
  "branchName": "kanade0404/eng-123-...",
  "team": { "key": "ENG", "id": "..." },
  "labels": { "nodes": [{ "id": "...", "name": "claude:ready" }] }
}
```

### B. 手動モード (`/linear-issue ENG-123`)

引数の identifier だけ来る。skill 自身が Linear GraphQL を叩いて上記 JSON を
取得する。

どちらの場合も `identifier` と `branchName` は Linear 側で生成済み。`branchName`
をそのまま git ブランチ名に使うこと (Linear の自動連携が ID を拾うため)。

## 排他制御 (二重起動防止)

着手前に Linear ラベルを `claude:ready` → `claude:in-progress` に張り替える。
ただしラベル付与は atomic な compare-and-set ではないため、2 つの実行 (cron と
手動 `/linear-issue` の併走など) が同じ `claude:ready` issue をほぼ同時取得すると
両方が処理を始める。これを防ぐため必ず以下のロック取得検証を行う。

**Iron Law**: ラベルは最古検証に勝った run しか触らない。敗者・エラー終了は
`claude:ready` を絶対に失わない (kanade0404/skills#31 — 旧手順はラベル張替を
最古検証より先に行っており、敗者やクラッシュが `claude:in-progress` だけ外して
`claude:ready` を永久に失う queue 消失バグと、lock が無期限に有効でクラッシュ
した run の lock が未来の全 run を負けさせ続けるデッドロックの 2 つを併発させて
いた)。

0. issue の labels を取得し、`claude:done` / `claude:failed` が既に付いて
   いれば処理済み。lock marker を書く前に即終了する (無駄な API 呼び出し回避)。
0b. **lease reap**: labels に `claude:in-progress` が既に付いている場合、
   `comments(orderBy: { field: createdAt, direction: DESC }, first: 20)` で
   直近の複数コメントを取得し、その中で本文が `claude-lock: ` で始まる
   **最新の 1 件**を選ぶ (`first: 1` だけを取得して判定すると、lock コメント
   より後に別のコメント — 監査コメントや進捗報告など — が投稿されていた場合に
   本物の lock コメントを見逃し、稼働中の issue を lock 無しと誤判定して
   reclaim してしまう。GitHub 版 `acquire-lock.sh` の `lock_lease_age()` も
   同様に「先にフィルタ、次に最新を選ぶ」順序を守っている)。選んだコメントの
   `ts=<epoch>` (下記 stage 1 参照) から経過秒数を計算する。
   `LOCK_LEASE_TTL_SECONDS` (既定 3600) を超えている、またはそもそも
   lock コメントが (取得した範囲に) 存在しなければ **lease 失効** とみなし、
   `issueRemoveLabel` で `claude:in-progress` を外し `issueAddLabel` で
   `claude:ready` を再付与 (`claude-lock-reclaim: ...` の監査コメントを添える)
   してから続行する。失効していなければ他の生存中の run が保持中と判断し、
   何もせず即終了する。
1. issue に一意 lock marker を書き込む — `commentCreate` で
   `claude-lock: <run-id> ts=<epoch-seconds>` (run-id は uuid) のコメントを
   1 件付ける。**タイムスタンプは lease の起点であり必須。**
2. issue を再取得し、`comments(orderBy: { field: createdAt, direction: ASC })`
   で全コメントを取得。`claude-lock: ` コメントのうち `ts` が現在時刻から
   `LOCK_LEASE_TTL_SECONDS` 以内 (＝失効していない) のものだけを対象に、
   **最古のコメントが自分の run-id か**を確認する (順序を非決定にしないため
   orderBy は必須。失効済みコメントを対象から除外することで、クラッシュした
   run の lock が未来の全 run を負けさせ続けるデッドロックを防ぐ)。
   - 自分が最古 → ロック取得成功。**ここで初めて** `issueRemoveLabel` で
     `claude:ready` を外し `issueAddLabel` で `claude:in-progress` を付与する。
   - 他者が最古 → 競合に負け。**ラベルは一切触らない**まま何もせず即終了
     (exit 0)。自分の lock コメントは監査用に残してよい (lease 失効後は
     自動的に無視されるようになる)。

完了時に `claude:done`, 失敗時に `claude:failed` に張り替える (どちらの場合も
`claude:in-progress` は外す)。**この手続きの外 (実装フェーズ中) でクラッシュ
した場合はここでは救えない** — 次にこの issue が選ばれた時の stage 0b (lease
reap) が唯一の救済経路になるため、Routine 側は毎回の issue 選定前に
`claude:in-progress` かつ lease 失効済みの issue が無いか同様のチェックを
挟むこと (省略すると kanade0404/skills#31 のデッドロックが再発する)。

ラベル ID は team 単位なので、team ごとに `claude:in-progress` / `claude:done` /
`claude:failed` が存在するか確認し、無ければ `issueLabelCreate` で作成する。

## 対象リポジトリの解決

issue の description / title から対象リポジトリを推測する。判断材料の優先順:

1. description 本文の `repo: owner/name` 行
2. description 内の GitHub URL (`github.com/owner/name`)
3. labels に `repo:<owner-name>` がある場合はそれ
4. どれも無ければ `claude:failed` でフェイルする (推測でリポジトリを変更しない)

## 主要ステップ

### 1. リポジトリ取得

```bash
gh auth login --with-token <<< "$GH_TOKEN"
gh repo clone "$OWNER/$REPO" repo
cd repo
```

base ブランチ名:

```bash
BASE=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git switch -c "$BRANCH_NAME" "origin/$BASE"
```

### 2. 実装方針の立案

- リポジトリの `CLAUDE.md` / `AGENTS.md` / `README.md` を読み、コミット規約・
  テストコマンド・lint コマンドを確認。
- issue.description の Acceptance Criteria を満たす **最小変更** を設計。
  機能を勝手に広げない。
- description が曖昧な場合は、自分の解釈を PR description に書く (issue に
  質問コメントは投げない。ヘッドレスなので返答を待てない)。

### 3. 実装 + テスト

- 変更は意図したファイルにだけ加える。
- リポジトリにテストがある場合は必ずローカルで実行。passing を確認できない
  状態で commit しない。
- テストが無い場合は最低限の検証 (ビルド・型チェック・lint) を通す。

### 4. commit

dotfiles 規約の絵文字 prefix を踏襲。issue identifier を commit 末尾に含めると
Linear と自動連携できる:

```text
:sparkles: <Subject>

<Body explaining the why>

Refs: ENG-123
```

`git add -A` は使わず変更ファイルを明示する。

### 5. push + PR 作成

```bash
git push -u origin "$BRANCH_NAME"
gh pr create \
  --title ":sparkles: <Subject> (ENG-123)" \
  --body "$(printf '## Summary\n- ...\n\n## Linear\n%s %s\n\n## Test plan\n- [x] unit tests\n' "$IDENTIFIER" "$ISSUE_URL")"
```

issue label に `claude:draft` があれば `--draft` を付ける。

### 6. CI all-green まで監視

```bash
gh pr checks --watch --interval 30
```

失敗チェックがあれば:

1. `gh pr checks --json name,conclusion,detailsUrl` で失敗ジョブを特定
2. `gh run view <run-id> --log-failed` でログ取得
3. 原因を直して追加 commit → push → 再度 watch

**連続 3 回失敗したら `claude:failed` ラベルを付けて停止** (無限ループ防止)。

### 7. レビューコメント解消

未解消の review thread が 0 になるまで対応する:

```bash
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!) {
    repository(owner:$owner,name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:50) {
          nodes { id isResolved comments(first:5) { nodes { body path line author{login} } } }
        }
      }
    }
  }' -F owner=$OWNER -F repo=$REPO -F pr=$PR_NUMBER
```

各 unresolved スレッドに対して:

1. コメント要約 → 同意できる指摘か判断
2. 同意 → 修正 commit → push
3. 不要/誤解 → スレッドに返信して根拠を簡潔に説明
4. すべて対応したら GraphQL `resolveReviewThread` で resolve

CI が再走するので 6 → 7 をループ。**全 resolved + CI green** で抜ける。
レビュー対応 5 周しても未解消が残るなら `claude:failed` で打ち切り。

### 8. 完了処理

- 成功: `claude:in-progress` 外して `claude:done` 付与
- 失敗: `claude:in-progress` 外して `claude:failed` 付与
- 最後に `gh pr view <pr> --json url,state` を log に出す

## ガードレール

- **destructive な git 操作は禁止**: `git reset --hard`, `git push --force*`,
  `git rebase` は使わない。修正は新規 commit (必要なら revert commit) で行う。
- **secrets を出さない**: `.env*`, `*.tfvars`, 鍵類は読まない/書かない/log に
  含めない。
- **無限ループしない**: CI 失敗 3 連 / レビュー対応 5 周で `claude:failed` 打切り。
- **対象が判別できないときは作業しない**: リポジトリ不明・branchName 衝突 →
  即フェイル。
- **他人のブランチに触らない**: PR 作成は常に新規ブランチ。

## Linear GraphQL ミューテーション早見表

```graphql
# label ensure (team 単位)
query { issueLabels(filter: { team: { id: { eq: $team } }, name: { eq: $name } }) { nodes { id } } }
mutation { issueLabelCreate(input: { teamId: $team, name: $name }) { issueLabel { id } } }

# label add/remove
mutation { issueAddLabel(id: $id, labelId: $labelId) { success } }
mutation { issueRemoveLabel(id: $id, labelId: $labelId) { success } }

# lock 検証用コメント取得 (作成時刻昇順、ts=<epoch> が LOCK_LEASE_TTL_SECONDS 以内の
# claude-lock: の中で最古のものを勝者と判定する。失効済みは判定対象から除外する)
query { issue(id: $id) { comments(orderBy: { field: createdAt, direction: ASC }) { nodes { id body createdAt } } } }

# lease reap 用: 直近の複数コメントを取得し、本文が claude-lock: で始まる
# 最新の1件をクライアント側で選んで失効判定する (first: 1 は lock 以外の
# コメントに隠れて本物の lock コメントを見逃すため使わない)
query { issue(id: $id) { comments(orderBy: { field: createdAt, direction: DESC }, first: 20) { nodes { id body createdAt } } } }

# state 遷移 (任意)
mutation { issueUpdate(id: $id, input: { stateId: $stateId }) { success } }
```

エンドポイント: `https://api.linear.app/graphql` 、ヘッダ `Authorization: $LINEAR_API_KEY`。
