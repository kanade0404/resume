---
name: commit
description: >-
  git commit を「観測 → ガード → 明示パス staging → ファイル経由メッセージ → 検証」の固定順で作る skill。`git add
  -A` / `git add .` / heredoc を使わないため、permission / hook
  で汎用コマンドが拒否される環境でもブロックされずに完走する。「commit して」「コミット作って」「この変更コミットしといて」「stage して
  commit」「きりのいいところで commit 切って」「一区切りだから記録して」のような要請、および tdd / tidy-first /
  shipping の各サイクル終端の commit 作成で必ず起動すること。commit までが責務 — push・PR 作成は
  `shipping`(検証ループ付き)または `commit-commands:commit-push-pr` に、リリースタグは RELEASING.md
  の手順に、structural / behavioral の分割判断は `tidy-first` に渡す。履歴書き換え (amend / rebase /
  squash / reset / revert) と commit 取り消しは範囲外 — 新規 commit を作る要請だけを扱う。
allowed-tools:
  - Read
  - Write
  - Bash(git status *)
  - Bash(git diff *)
  - Bash(git log *)
  - Bash(git ls-files *)
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(git rev-parse *)
  - Bash(git branch *)
  - Bash(git switch *)
---
# Commit

コミット作成を、guardrail の強い環境 (permission / hook が `git add -A`・`cat`・heredoc 等を
拒否する設定) でも**一発で通る手順に固定**する skill。拒否 → 言い換えリトライの往復は
それ自体が時間と context の浪費であり、拒否されない形を最初から使えば往復は発生しない。
個別の禁止コマンドは列挙しない — 設定が真実であり (`rules/bash-and-api-discipline.md`)、
本 skill は**どの設定下でも拒否されにくい最小手順**だけを規定する。

## いつ使うか / 使わない場面

**使う**: コミット作成の要請すべて。「commit して」「コミットしといて」「この変更で commit
作って」「stage して commit」「きりのいいところで commit 切って」。tdd の GREEN 直後、
tidy-first の tidying 単位、shipping Phase 3 など上流 skill からの commit 局面も同じ。

**使わない** (成果物で線を引く):

| 要求される成果物 | 渡す先 |
|---|---|
| push 済みブランチ + PR | `shipping` (検証ループ付き) / `commit-commands:commit-push-pr` |
| リリースタグ | RELEASING.md の手順 (存在するリポの場合) |
| 書き換えられた履歴 (amend / rebase / squash / reset / revert) | 範囲外。明示要求されたら本 skill の外で直接対応 |
| structural / behavioral の分割方針 | `tidy-first` (何をコミットに入れるかの判断は上流) |

## ワークフロー (順序固定)

### Step 1 — 観測

```bash
git status --short
git diff --stat          # unstaged
git diff --cached --stat # staged (残留がないか)
git rev-parse --abbrev-ref HEAD
```

働きかけの前に必ず現状を見る。既に staged の変更が残っていたら、それが今回のコミットに
属するかを判定してから進む (無言で巻き込まない)。

### Step 2 — ガード

- **default ブランチ (main / master) に居るなら**: 直コミットせず、先にブランチ作成を提案する
  (`git switch -c <topic>`)。ユーザが「master に直接で良い」と明示したときだけ続行。
- **無関係な変更が混在**: 1 コミット 1 関心事。混在していたら分割を提案し、今回分だけを
  staging 対象にする。
- **コミット対象が空**: 何も stage せず「コミット対象がない」と報告して終了。

### Step 3 — 明示パス staging

```bash
git add <path1> <path2> <dir/>   # 対象を列挙する。ディレクトリ指定は可
```

`-A` / `.` / `-u` / `--all` は**使わない**。guardrail 環境で拒否される代表格であり、
拒否されない環境でも「何が入ったか」を Step 1 の観測と突き合わせられる明示列挙の方が
巻き込み事故を構造的に防ぐ。staging 後に `git status --short` で意図どおりかを確認する。

### Step 4 — メッセージはファイル経由

メッセージは Write ツールで一時ファイル (scratchpad があればそこ、無ければ
`/tmp` 相当) に書き、`-F` で渡す:

```bash
git commit -F <scratch>/commit-msg.txt
```

`-m` + heredoc / `$(cat <<EOF ...)` は**使わない** — heredoc・`cat` は guardrail 環境で
拒否される上、複数行・引用符・記号を含むメッセージのエスケープ事故源になる。
ハーネスが trailer (Co-Authored-By 等) を要求している場合はファイル末尾に含める。

メッセージ本文は conventional な形式に固定する:

```
<要約 1 行 (50-72 字目安、何を＋なぜ)>

- <変更点 1>
- <変更点 2>
<必要なら trailer>
```

### Step 5 — 検証と報告

```bash
git log -1 --stat
```

SHA・ファイル数・行数を確認してから報告する。**pre-commit hook が失敗したら**:
root cause を読み、直せるものは直して再実行する。`--no-verify` での回避は
ユーザの明示指示なしには使わない。同型の失敗が 2 回続いたら止めて報告する
(`rules/bash-and-api-discipline.md` の「同型再試行しない」に従う)。

## このスキルがやらないこと (成果物で定義)

- **push された commit / PR**: 作らない。commit 作成で停止し、続きは呼出側が判断する。
- **書き換えられた履歴**: amend / rebase / squash / reset / force 系は既定で出力しない。
- **`--no-verify` で hook を迂回した commit**: 明示指示なしには作らない。
- **staging 全量 (`-A` / `.`) による commit**: どの環境でも作らない。
- **コミット分割方針の決定**: structural / behavioral の判断は `tidy-first` の成果物。

## リファレンス

- `rules/bash-and-api-discipline.md` — ブロック時の復帰手順・専用ツール優先の一般規律
