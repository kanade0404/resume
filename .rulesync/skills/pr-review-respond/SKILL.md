---
name: pr-review-respond
description: "PR の自動レビュー (CodeRabbit / Devin) と人間レビュアーの指摘を、行スレッド・レビュー本文 (折りたたみ内の Outside diff range / Nitpick 等を含む)・会話コメントの 3 種から網羅取得し、妥当性を verify して対応するスキル。VALID は修正コミット + 「Fixed in <SHA>」返信、INVALID_PUSH は根拠付き pushback (resolve しない)、VALID_DEFER は issue 化、DUPLICATE は既存対応を参照し、最後に集約サマリコメントを 1 件投稿する。「指摘確認して」「レビュー指摘を確認」「指摘ある?」「レビューコメント見て」のような確認だけの依頼でも起動し、その場合は読み取り専用モード (取得 + triage 報告のみ。修正・返信・resolve はしない) で動く。`gh pr create` 直後・既存 PR ブランチへの push 直後 (レビュー対応後の再 push を含む)・「レビュー対応して」「コメント見て対応して」「コードラビット対応」「Devin の指摘片付けて」「PR のコメント全部捌いて」のような要請、新規レビューコメントの検知時、merge 前の未解決確認時、いずれでも必ず起動すること。未解決スレッドが残る PR を離れる前にも一度起動する。subagent に PR 指摘の取得を委譲する場合も ad-hoc な gh コマンドではなく本スキルの `prr fetch` を使わせる。レビュー自体の実行 (CodeRabbit / Devin の呼び出し) はしない。GitHub API は同梱 `scripts/prr` (fetch/reply/resolve/summary/wait-ci 等) に集約。CodeRabbit 指摘の修正適用は coderabbit plugin があれば `coderabbit:autofix` に委譲する。"
claudecode:
  allowed-tools:
    - Read
    - Write
    - Edit
    - Bash(bash *prr *)
    - Bash(git add *)
    - Bash(git commit *)
    - Bash(git diff *)
    - Bash(git log *)
    - Bash(git push *)
    - Bash(git rev-parse *)
    - Bash(git status *)
    - Bash(jq *)
    - Task
---

# PR Review Respond

CodeRabbit / Devin / 人間レビュアーが残したコメントを **盲信せず verify したうえで** 捌くスキル。完了時には PR を読み返した第三者が「何を直し、何を直さず、なぜか」を 1 コメントで追える状態にする。

設計の柱は 3 つ：

- **verify-before-implement** — 妥当性を AI が一次判定してから手を動かす。`receiving-code-review` 系の規律を取り込む。
- **pushback はコメントのみ** — INVALID と判定したものは根拠を書くだけで resolve しない。reviewer の最終判断余地を残す。
- **トレーサビリティは PR 集約コメント 1 本に集約** — ローカルログは作らない。後から PR を見れば全てわかる状態にする。

### 取得対象は 3 種 (1 つでも欠けると取りこぼす)

| 種別 | API | 典型的な中身 |
|---|---|---|
| 行スレッド | GraphQL `reviewThreads` | diff 行への inline 指摘 |
| **レビュー本文** | REST `pulls/{n}/reviews` の `body` | CodeRabbit の「⚠️ Outside diff range comments」「🧹 Nitpick comments」「Additional / Duplicate comments」(折りたたみ `<details>` 内)、Devin・人間が本文だけに書いた指摘 |
| 会話コメント | REST `issues/{n}/comments` | CodeRabbit walkthrough / サマリ、Devin 総評、人間の自由記述 |

行スレッドだけを見て「指摘は N 件」と結論しない (実例: Devin の行コメント 2 件だけを拾い、CodeRabbit がレビュー本文に書いた diff 外指摘を見落とした)。`prr fetch` は 3 種すべてを返す。

### モード

| モード | 起動条件 | やること | やらないこと |
|---|---|---|---|
| 対応モード (既定) | 「対応して」「捌いて」「片付けて」、push 直後、監視からの dispatch | Phase A〜E 全部 | — |
| **読み取り専用モード** | 「指摘確認して」「レビューコメント見て」「指摘ある?」「レビュー指摘を確認」のように**確認だけ**を求める依頼 | Phase A (取得) + Phase B (triage) → 「確認モードの報告」(後述) を返して終了 | 修正・commit・push・返信・resolve・issue 作成・サマリ投稿 |

依頼が確認か対応か曖昧なら読み取り専用モードで報告し、対応に進むかをユーザに委ねる (書き込みは後から足せるが、投稿した返信や resolve は取り消しにくい)。

### オーケストレータ / subagent 委譲時の規律

PR 指摘の取得を subagent に委譲する場合も、ad-hoc な `gh api` / `gh pr view --comments` を並べさせず、**本スキル (`prr fetch`) を使わせる**。委譲プロンプトには次を含める:

- 「pr-review-respond skill を (読み取り専用モード / 対応モードで) 使い、`prr -R <owner>/<repo> fetch <PR>` で取得すること」 (subagent の cwd が PR のクローンとは限らないので `-R` を省かせない)
- 「取得件数を **行スレッド (未解決数) / レビュー本文 (うち分解済み指摘数) / 会話コメント** の別で必ず報告すること」 (`prr fetch` 出力の `counts` をそのまま転記させる)

件数がソース別に報告されていない結果は「取得が網羅的だった」証拠にならないので、受け取った側は再取得させる。

---

## 実行環境前提

本スキルは 3 つの実行環境で起動しうる。**待機や中断の扱いが環境ごとに違う**ため、起動時にどの環境かを意識する:

| 環境 | 特徴 | 待機や行き詰まりの扱い |
|---|---|---|
| 対話ローカルセッション | 画面前に人間がいる | Phase E の `WAITING` verdict をそのまま人間に返してよい |
| ヘッドレス subagent (`shipping` 等からの dispatch) | 呼び出し元 skill/agent がいる | `WAITING` verdict を呼び出し元に返す。呼び出し元が再開の責任を持つ |
| CI / スケジュール起動 (無人実行) | `WAITING` を受け取る相手がいない | **`WAITING` で止めない**。`needs-human` ラベル付与 + 構造化コメント (`prr escalate`、後述) を必須のフォールバックとする |

いずれの環境でも共通の規律は Phase E で扱う「待機委譲時の end_turn 禁止」。

---

## 前提: 同梱スクリプトと権限

`gh api` / `gh pr ...` を毎回 inline で叩くと、実行のたびに permission prompt が発生して煩雑になる。本スキルは GitHub API 呼び出しを `scripts/` 配下に閉じ込め、**単一エントリーポイント `prr` 経由でのみ呼び出す** 設計にしている。これにより:

- `allowed-tools` の rule は `Bash(bash *prr *)` 1 行で全アクションをカバー (末尾 `*` のみで Claude Code permission engine の保証範囲内)
- consumer の `~/.claude/settings.json` への permission 追加は不要 (`allowed-tools` が auto-grant、workspace trust 受諾後に有効化)

### scripts/

```text
scripts/
├── prr                  # entry point (subcommand dispatcher、-R owner/repo を解釈)
├── lib_repo.sh          # 対象リポジトリの解決 (-R / GH_REPO / cwd)。各スクリプトが source
├── fetch_threads.sh     # prr fetch (API 取得)
├── normalize_fetch.jq   # prr fetch の正規化 (純関数、fixture テスト対象)
├── reply_thread.sh      # prr reply
├── resolve_thread.sh    # prr resolve
├── post_summary.sh      # prr summary
├── wait_ci.sh           # prr wait-ci
├── defer_issue.sh       # prr defer
└── escalate.sh          # prr escalate
```

### Subcommand 一覧

すべて `bash "${CLAUDE_SKILL_DIR}/scripts/prr" [-R owner/repo] <subcommand> <args>` で呼び出す。

**対象リポジトリ**: `-R owner/repo` (subcommand の直前・直後どちらでも可。環境変数 `GH_REPO` でも同じ) で明示する。省略時は cwd のリポジトリ (`gh repo view`) を使う。解決したリポジトリは毎回 stderr に `prr: repository <owner/repo> (source: -R|GH_REPO|cwd)` と出る。**cwd が PR のクローンでない場合 (別リポジトリにいる、subagent の cwd が不明) は必ず `-R` を付ける** — cwd の別リポジトリに同番号の PR があると、その PR を正常に読んでしまう。

| Subcommand | 役割 |
|---|---|
| `prr fetch <PR>` | 行スレッド (GraphQL) + レビュー本文 (`pulls/{n}/reviews`) + 会話コメント (`issues/{n}/comments`) を全件取得し、vendor 判定 (`coderabbit` / `devin` / `human`)・`self_replied` フラグ・レビュー本文の `embedded_findings`・ソース別 `counts` を付けた正規化 JSON を stdout に出力。解決したリポジトリに PR が無い・PR がそのリポジトリに属さない場合は空の結果を返さず非ゼロ exit (stderr に理由) |
| `prr reply <PR> <comment-id> <body-file>` | 正しい `/repos/{O}/{R}/pulls/{PR}/comments/{id}/replies` エンドポイントで返信投稿。本文は file 経由で multi-line / 引用符事故を防ぐ |
| `prr resolve <PR> <comment-id> <classification> <vendor> [body-file]` | vendor (`coderabbit`/`devin`/`human`、**必須・省略不可**) 別に返信本文を組み立てたうえで (coderabbit のみ `@coderabbitai resolve` を併記)、GraphQL `resolveReviewThread` mutation で全 vendor のスレッドを直接 resolve。`classification` は `VALID` / `VALID_DEFER` / `DUPLICATE` のみ許可。**`INVALID_PUSH` を渡すと非ゼロ exit で拒否する** (誤 resolve ガード、後述)。vendor を省略・誤指定すると usage を表示して非ゼロ exit で拒否する (暗黙デフォルト廃止 — 誤 vendor 判定で人間スレッドに `@coderabbitai resolve` を投稿する事故を防ぐ) |
| `prr summary <PR> <body-file>` | 集約 Review Response Summary を **新規** issue comment として投稿 (毎回新規投稿、過去サマリは履歴として残す) |
| `prr wait-ci <PR> [interval]` | `gh pr checks --watch` をラップし全 check 完了まで block。失敗時は exit 非ゼロで呼出側に通知 (本スキルは retry しない) |
| `prr defer <PR> <thread-url> <title> <body-file>` | `VALID_DEFER` 判定のフォロー issue を作成し、`<issue-number> <issue-url>` を stdout に出力。本文に元スレッド URL と PR URL を自動付記する。`<thread-url>` は指摘固有 (レビュー本文・会話コメント由来は `#finding-...` キー付き、後述) |
| `prr escalate <PR> <reason> <body-file>` | 無人実行で `WAITING` を返す相手がいない時のフォールバック。PR に `needs-human` ラベルを付け、`body-file` を構造化コメントとして投稿する |

スクリプト本体は最小依存 (`gh`, `jq`, `bash`) のみ前提。Python / Node 等は使わない。

---

## ワークフロー

### Phase A — 取得 (fetch)

行スレッド・レビュー本文・会話コメントの 3 種を 1 コマンドで取得・正規化する。`gh api` は `prr` wrapper 経由で呼び出して毎回の許可確認を不要にする。**ad-hoc な `gh` コマンドで代用しない** (どれか 1 種が抜けるのが典型的な取りこぼし経路)。

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/prr" -R <owner>/<repo> fetch <PR>   # → 正規化 JSON を stdout
# PR のクローン内で実行する場合に限り -R は省略可
```

取得後、**`pr.url` (と `pr.repo`) が意図した PR か確認してから** 件数を読む。非ゼロ exit は「指摘ゼロ」ではなく取得失敗として扱い、stderr の理由 (PR が見つからない / 別リポジトリ) を報告する。

出力の主要フィールド:

- `threads[]` — GraphQL `reviewThreads` を cursor pagination で全取得。root comment + `is_resolved` / `is_outdated` / `self_replied`
- `review_bodies[]` — `pulls/<PR>/reviews` のうち body が空でない提出済みレビュー (`id, author, vendor, state, body, submitted_at, url, commit_id`)。**`body` は常に全文**。CodeRabbit の Outside diff range / Nitpick / Additional / Duplicate セクションは `embedded_findings[]` (`category, path, start_line, end_line, title, body`) にベストエフォートで分解される
- `issue_comments[]` — `issues/<PR>/comments` の会話コメント。body 全文 (CodeRabbit walkthrough 内の actionable 指摘も含む)
- `counts` — `threads` / `unresolved_threads` / `eligible_threads` (未解決 ∧ 非 outdated ∧ 非 self_replied = 下記の除外後に triage する行スレッド数) / `skipped_threads` (未解決だが outdated または self_replied) / `review_bodies` / `embedded_findings` / `issue_comments` のソース別件数。**報告時はこれをそのまま使う**
- 各要素に `vendor` (`coderabbit` / `devin` / `human`、author login から判定、bot suffix のような表面ルールは持たない)

呼出側 (本スキル本体) は得られた JSON から:

- `is_resolved == true` / `is_outdated == true` のスレッドを除外
- 自分が投稿した集約サマリ (`Review Response Summary` ヘッダ) を `issue_comments` から除外
- `self_replied == true` のスレッドはスキップ (多重返信防止)
- **レビュー本文は `embedded_findings` だけで済ませない**。`embedded_findings` が空でも body に指摘らしき記述 (Devin / 人間の本文、未知レイアウトの CodeRabbit セクション) があれば body 全文を読んで指摘を列挙する。分解はあくまで補助
- 再確認 (2 回目以降の起動) では、前回の自分の `Review Response Summary` の投稿時刻以降に `submitted_at` / `created_at` を持つレビュー本文・会話コメント・スレッドを「新着」として明示する。ただし新着だけに絞り込まず、未対応のまま残っている過去分も対象に含める

### Phase B — 妥当性 verify (triage)

各 thread / コメントを **4 値分類** する。判定は description ではなく **指摘本文 + 該当コード** を読んで行う。レビュアー名で重み付けしない。

triage の単位は「指摘 1 件」で、ソースを問わない:

- 行スレッド — 1 スレッド = 1 件
- レビュー本文 — `embedded_findings` の 1 要素 = 1 件 (分解されなかった本文中の指摘も、自分で 1 件ずつ切り出す)。レビュー本文を「総評」として丸ごと読み流さない
- 会話コメント — actionable な指摘を含むものを 1 件ずつ (walkthrough の要約部分は対象外)

同じ指摘が行スレッドとレビュー本文の両方に現れる場合 (CodeRabbit の Duplicate comments 等) は、行スレッド側を主として本文側を `DUPLICATE` にする。

| 分類 | 定義 |
|---|---|
| `VALID` | 指摘通り、本 PR スコープ内で修正する |
| `INVALID_PUSH` | 技術的に不適切 / 既存方針と矛盾 / YAGNI / 文脈不足。根拠を返してそのまま残す |
| `VALID_DEFER` | 妥当だが本 PR スコープ外。issue を切って参照する |
| `DUPLICATE` | 同 PR 内の他スレッドで既に対応済み |

判定の際の禁則：

- **performative agreement 禁止**。`"You're absolutely right!"` / 「おっしゃる通り」式の同意のみで実装に進まない。**指摘内容を自分の言葉で要約できないなら VALID と判定しない**。
- **レビュアー権威での自動 VALID 化禁止**。CodeRabbit / Devin / Senior 人間のいずれであっても、根拠が薄ければ INVALID_PUSH を恐れない。
- **逆も禁止**。AI レビューだから INVALID と決め打ちしない。

`INVALID_PUSH` の正当化は次のいずれかに該当することを 1 文で書けること：

- YAGNI（指摘の抽象化に必要な呼出元が現状 1 箇所しかない、等）
- 既存方針との矛盾（プロジェクト規約 / 他コンポーネントの先例と整合しない）
- 指摘の前提が誤り（コード読み違え、context window の境界で見えていない情報がある）
- トレードオフの選択（パフォーマンス vs 可読性、等の意識的な選択）

### 読み取り専用モードの終端

読み取り専用モードは Phase B の triage 結果を「確認モードの報告」(出力フォーマット節) として返して終了する。Phase C 以降 (修正・push・返信・resolve・issue 作成・サマリ投稿) には進まない。分類は「対応するならこう扱う」という提案であり、ユーザが対応を指示したら対応モードで Phase A から再実行する (確認から時間が経っていれば新着が増えているため、取得結果を使い回さない)。

### Phase C — 修正 (apply)

`VALID` のみ対象。

**CodeRabbit 起因の指摘は `coderabbit:autofix` への委譲を許容する**: CodeRabbit が投稿した `VALID` 判定の指摘について、coderabbit plugin が導入されている環境では、修正適用そのものを per-change approval 付きで安全に適用する専用スキル `coderabbit:autofix` に委譲してよい。委譲した場合でも、triage (Phase B)・返信 / resolve (Phase D)・集約サマリ (Phase E) を本スキルが持つ分担は変わらない。plugin が無い環境では従来どおり本 Phase の経路 (structural → `tidy-first` / behavioral → `tdd`) で修正する。commit への `Refs:` 付与と Phase C 終端の push 規律 (後述) は、委譲した場合も適用される。

- **structural change** (純リファクタ・rename・抽出) は **behavioral change と commit を分ける**。`tidy-first` の規律を踏む。
- **behavioral change** は失敗テストを先に書く（`test-driven-development` の規律）。
- 各 commit message に該当スレッドの URL を `Refs:` で付ける：

```text
fix: handle empty result in foo()

Refs: https://github.com/<owner>/<repo>/pull/<n>#discussion_r<id>
```

これにより返信時に `<SHA>` を貼ればトレースが完結する。

- 修正が **既存テストの assertion / 期待値そのものを書き換える**場合 (新規テスト追加ではなく、緩い・誤った assertion の訂正)、Phase D で「Fixed in `<SHA>`」を返信する **前に** `test-mutation-gate` を必ず通す。レビュー起点のテスト修正が本当に検出力を持つかを機械的に裏取りするため。BLOCK なら修正をやり直し、返信しない。

**Devin の re-review は commit push に任せる**。`@devin` メンションでの再依頼はしない（push を検知して自動再評価するため）。

### Phase C 終端 — push (省略禁止)

commit を当てただけでは GitHub 上の PR は古い HEAD のままで、CI もレビュー bot もそれを見ている。**Phase D / E に進む前に必ず push する**:

```bash
git push origin <branch>
git rev-parse HEAD   # push した SHA を記録し、以降の "Fixed in <SHA>" 返信に使う
```

- push を省略すると `prr wait-ci` が古い HEAD の CI 結果を見て「完了」と誤判定する。Devin の自動 re-review も push が trigger のため起動しない。
- push が rejected / diverged で失敗したら、原因 (force-push 済みの remote など) を解消してから再 push する。**push が成功したことを確認した SHA でのみ** Phase D 以降に進む。
- 複数 commit をまとめて 1 回だけ push してよい。commit ごとの push は必須ではない。

### VALID_DEFER — フォロー issue 作成

`VALID_DEFER` は「妥当だがスコープ外」の判定であり、返信 (Phase D) で `Tracked in #<issue>` と書く以上、その issue は **返信より前に実在していなければならない**。

```bash
# body-file には指摘の要約 (自分の言葉で) + スコープ外と判断した理由を書く
bash "${CLAUDE_SKILL_DIR}/scripts/prr" defer <PR> <thread-url> "<title>" <body-file>
# stdout: "<issue-number> <issue-url>"
```

- **`<thread-url>` は指摘 1 件に固有であること** (重複 issue 防止の検索キーを兼ねる): 行スレッドはスレッド URL (`#discussion_r<id>`) をそのまま渡す。**レビュー本文・会話コメント由来の指摘**は、同じレビュー / コメントの全指摘が URL を共有するため、指摘固有キーを付けて渡す — `<review_bodies[].url または comment url>#finding-<category>-<path>-<start>-<end>-<ordinal>` (例: `https://github.com/o/r/pull/7#pullrequestreview-9001#finding-outside_diff_range-src/a.ts-88-96-1`)。`category` は `embedded_findings[].category` (自分で切り出した指摘は `body`)、path / 行が無ければ `-` 、`ordinal` はそのレビュー内での 1 始まりの通し番号、path 中の空白は `_` に置換する。キー無しの `#pullrequestreview-` / `#issuecomment-` URL は `prr defer` が非ゼロ exit で拒否する。同じキーで再実行すれば既存 issue が返る
- **タイトル規約**: 指摘内容を要約した命令形 1 行 (例: `Extract retry policy into shared helper`)。skill 名等のプレフィックスは付けない。
- **本文必須項目**: 指摘の要約、スコープ外と判断した理由 (1 文)。元スレッド URL と PR URL は `prr defer` が自動で付記する。
- 生成された issue 番号を Phase D の返信 (`Tracked in #<issue>`) と Phase E のサマリ (`[<thread-url>] → #<issue>`) の両方に使う。

### Phase D — 返信 (reply)

inline thread への返信は GitHub REST の `/replies` エンドポイントを使う必要がある (top-level review comment への返信のみ可、reply-to-reply は不可)。これも `prr` wrapper に閉じ込める。

```bash
# 返信本文は file 経由 (multi-line / 引用符のエスケープ事故防止)
bash "${CLAUDE_SKILL_DIR}/scripts/prr" reply <PR> <root-comment-id> <body-file>

# 対応済みスレッドを resolve する場合 (VALID / VALID_DEFER / DUPLICATE のみ)。
# vendor は coderabbit/devin/human から必須指定 (4 番目の引数。省略・誤指定は
# usage 表示 + 非ゼロ exit で拒否 — 暗黙デフォルトは廃止)
bash "${CLAUDE_SKILL_DIR}/scripts/prr" resolve <PR> <root-comment-id> <classification> <vendor> [body-file]
# classification は VALID / VALID_DEFER / DUPLICATE のいずれか。
# INVALID_PUSH を渡すとスクリプトが非ゼロ exit で拒否する (誤 resolve ガード)。
# vendor=coderabbit: body-file 内容 + 改行 + "@coderabbitai resolve" を返信投稿してから resolve。
# vendor=devin/human: body-file 内容のみを返信投稿してから resolve (ディレクティブは付けない)。
#   body-file を省略すると返信は送らず resolve のみ行う。
# resolve 自体はいずれの vendor でも GraphQL resolveReviewThread mutation でスレッドを直接
# resolve する (CodeRabbit のメンション頼みではない — メンションは coderabbit 向けの併記のみ)
```

vendor 別の使い分け:

| 分類 | CodeRabbit | Devin | 人間 |
|---|---|---|---|
| `VALID` | `prr resolve` vendor=coderabbit (body: 「Fixed in `<SHA>`」、`@coderabbitai resolve` 併記) | `prr resolve` vendor=devin (body: 「Fixed in `<SHA>`」、ディレクティブ無し) | `prr resolve` vendor=human (body: 「Fixed in `<SHA>`. Ready for re-review.」、ディレクティブ無し) |
| `INVALID_PUSH` | `prr reply` (根拠のみ、resolve しない) | `prr reply` (根拠のみ) | `prr reply` (根拠 + 質問形式) |
| `VALID_DEFER` | `prr resolve` vendor=coderabbit (body: 「Tracked in #`<issue>`」) | `prr resolve` vendor=devin (body: 「Tracked in #`<issue>`」) | `prr resolve` vendor=human (body: 「Tracked in #`<issue>`」) |
| `DUPLICATE` | `prr resolve` vendor=coderabbit (body: 「Already addressed by `<other-thread-url>`」) | `prr resolve` vendor=devin (body: Already addressed by ...) | `prr resolve` vendor=human (同左) |

対応済み (修正 commit 済み / issue 化済み / 重複参照済み) のスレッドは vendor を問わず resolve し、PR の未解決スレッド数を実態に一致させる。これは `pr-monitor` の `prm` が持つ `unresolved_count` (`isResolved == false` の全スレッド数) が収束判定の前提にしている値そのものであり、CodeRabbit 以外のスレッドを resolve せず放置すると、対応済みでも `unresolved_count` が減らず収束ループが成立しない。

**行スレッドが無い指摘 (レビュー本文・会話コメント由来) の返信先**: `prr reply` / `prr resolve` は行スレッド専用で使えない。これらは Phase E の集約サマリ内「Review body / conversation findings」節で、元レビュー (`review_bodies[].url`) または元コメントの URL と `path:line` を引用して 1 件ずつ分類・対応内容 (Fixed in `<SHA>` / pushback 根拠 / Tracked in #`<issue>` / Duplicate of `<thread-url>`) を書く。個別の会話コメントを指摘ごとに乱発しない — サマリ 1 本に集約する方針はここでも同じ。`VALID_DEFER` の issue は指摘ごとに `#finding-...` キー付き URL で `prr defer` する (VALID_DEFER 節参照。review URL のままだと同じレビューの 2 件目以降が 1 件目の issue に吸収される)。

**重要**: `INVALID_PUSH` は **どのレビュアーに対しても resolve コマンドを発行しない** (`prr reply` のみ使用)。reviewer 側に「無視された」と取られる余地を消すため。この規律は運用 (書き手の注意) だけに頼らず、`resolve_thread.sh` 自身が `classification` 引数に `INVALID_PUSH` を渡された時点で非ゼロ exit するガードとして実装されている。

返信本文の最低構成 (INVALID_PUSH の例):

```text
本指摘は採用しません。理由: <YAGNI / 既存方針 / 前提誤り / トレードオフ のいずれか> — <1-2 文で具体>。
再考の余地があればコメントで詳細を教えてください。
```

### Phase E — 集約サマリ投稿 + 最終 gate

PR の **issue comment** として、以下のサマリを **新規 1 件** で投稿する (既存サマリの更新ではなく毎回新規投稿、古いサマリは残して履歴にする)。投稿は `prr` wrapper 経由:

```bash
# サマリ本文を temp file に書き出してから投稿
bash "${CLAUDE_SKILL_DIR}/scripts/prr" summary <PR> <body-file>
```

サマリ本文テンプレ (`<body-file>` の中身):

```markdown
## Review Response Summary (<YYYY-MM-DD HH:MM JST>)

| Reviewer | Total | Fixed | Pushback | Deferred | Duplicate |
|---|---|---|---|---|---|
| CodeRabbit | 8 | 5 | 2 | 1 | 0 |
| Devin | 3 | 2 | 1 | 0 | 0 |
| @<login> | 1 | 0 | 0 | 0 | 1 |

### Pushback (要 reviewer 判断)
- [<thread-url>] <1 行サマリ>: <根拠 1 行>
- [<thread-url>] <1 行サマリ>: <根拠 1 行>

### Deferred
- [<thread-url>] → #<issue>

### Fixed (commit)
- [<thread-url>] → `<SHA>`

### Review body / conversation findings (行スレッド外の指摘)
- [<review-url>] `<path>:<start>-<end>` (Outside diff range) <1 行サマリ> → Fixed in `<SHA>`
- [<review-url>] `<path>:<line>` (Nitpick) <1 行サマリ> → Pushback: <根拠 1 行>
- [<comment-url>] <1 行サマリ> → Tracked in #<issue>

取得件数: 行スレッド <n> (未解決 <n>、うち対応対象 <eligible_threads>) / レビュー本文 <n> (分解済み指摘 <n>) / 会話コメント <n>
skip した未解決スレッド: <skipped_threads> 件 (outdated / 返信済み)
各スレッドへの返信は thread 内に投稿済み。行スレッド外の指摘への応答は本コメントが正。
```

最終 gate：

- `counts.eligible_threads` (未解決 ∧ 非 outdated ∧ 非 self_replied — Phase A の除外と同じ基準) + 行スレッド外の指摘数 = サマリの (Fixed + Pushback + Deferred + Duplicate) を確認 (レビュー本文由来の指摘も Total に数える)。`unresolved_threads` は outdated / 返信済みを含むので照合に使わない。skip したスレッド数 (`counts.skipped_threads`) はこの式に入れず、サマリと最終報告に別行で書く
- ローカル検証は **`verify-done` を呼んで** PASS を取る (`should/probably/seems` 系の語彙はそこで弾かれる)
- CI 完了待ちも `prr` 経由:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/prr" wait-ci <PR>   # 全 check 完了まで block、fail なら ci-self-heal に渡す
```

### 待機委譲時の規律 (end_turn 禁止)

`wait-ci` はブロッキング呼び出しだが、長時間 CI を `Monitor` 等のバックグラウンド監視に委譲したくなる場面がある。**委譲した直後に end_turn してはならない** — 誰も再開しないまま放置される実例が起きている (待機委譲後 50 分放置)。

- 同一ターン内で `wait-ci` (または委譲した監視) の完了 (pass/fail) まで確認できるなら、そのまま最終報告に進む。
- 同一ターン内で完結できない場合、最終報告の代わりに **`WAITING` verdict を明示的に返す**:
  - 現在までの進捗 (Fixed / Pushback / Deferred / Duplicate の内訳)
  - 何を待っているか (CI の残り check / 追加レビュー等)
  - 再開条件 (checks 完了、新規コメント等) と再開方法 (呼び出し元がポーリングするか、`pr-monitor` 等に引き継ぐか)
  - `WAITING` を返したターンで end_turn してよいのは、「実行環境前提」表の対話ローカル / ヘッドレス subagent のように **`WAITING` を受け取る相手が存在する場合のみ**
- 受け取る相手がいない (CI / スケジュール起動の無人実行) 場合は `WAITING` で止めない。代わりに次を実行してから終える:

```bash
# body-file は loop-escalation:v1 形式 (issue-driven-development skill と共通の規約):
# 自由文の状況説明 + <!-- loop-escalation:v1 --> に続く JSON
#   {"reason": "...", "detail": "...", "attempts": <n>, "session_id": "...", "next_action_hint": "..."}
# reason は budget-exceeded / max-turns / ci-3-fail / review-5-rounds / no-progress /
# ambiguous-issue / repo-unresolvable / conflict / security-block / other から選ぶ
bash "${CLAUDE_SKILL_DIR}/scripts/prr" escalate <PR> <reason> <body-file>
```

---

## 出力フォーマット

ユーザへの最終報告は以下の構造で 1 メッセージ：

```markdown
# PR Review Response: #<n>

## Stats
- Fetched: 行スレッド <n> (未解決 <n>、うち対応対象 <eligible_threads>) / レビュー本文 <n> (分解済み指摘 <n>) / 会話コメント <n>   ← `prr fetch` の `counts`
- Skipped unresolved threads: <skipped_threads> (outdated / 返信済み)
- Findings processed: <total>
- Fixed: <n>  / Pushback: <n>  / Deferred: <n>  / Duplicate: <n>

## Commits
- `<SHA>` <message>
- ...

## Pushback (理由)
- [<thread-url>] <分類根拠 1 行>

## CI
- <pass/fail/pending> (<URL>)

## Summary comment posted
<URL>
```

### 確認モードの報告 (読み取り専用モード)

```markdown
# PR Review Check: #<n> (読み取り専用 — 修正・返信・resolve はしていない)

## Fetched
- 行スレッド <n> (未解決 <n>、うち対応対象 <eligible_threads>) / レビュー本文 <n> (分解済み指摘 <n>) / 会話コメント <n>
- 前回サマリ以降の新着: <n> 件

## Findings (要対応候補)
| # | Source | Reviewer | Location | 要約 (自分の言葉で) | 分類案 | 根拠 |
|---|---|---|---|---|---|---|
| 1 | thread | Devin | `src/a.ts:10` | ... | VALID | ... |
| 2 | review body (Outside diff range) | CodeRabbit | `src/b.ts:88-96` | ... | INVALID_PUSH | ... |

## 対象外 (resolved / outdated / 自分の返信済み / walkthrough 要約)
- <n> 件

対応する場合は「対応して」で対応モードを起動 (取得からやり直す)。
```

---

## レビュアー判別

`fetch_threads.sh` が `vendor` フィールドを 1 次判定として返す (author login が `coderabbit*` で始まるなら `coderabbit`、`devin*` または `devin-ai-*` を含むなら `devin`、それ以外は `human`)。

本スキルは script 結果を起点に、本文構造でさらに補正する:

- 本文構造が CodeRabbit walkthrough / nitpick markup を含む → `coderabbit` で固定
- 本文に Devin 特有のシグネチャ / Confidence 表記 → `devin` で固定
- それ以外で script の判定が曖昧な場合 → **人間として扱う** (`@coderabbitai resolve` メンションを誤って付与しないための安全側デフォルト。resolve 自体は vendor によらず GraphQL mutation で行うため、この判定が影響するのは「resolve するか否か」ではなく「CodeRabbit 宛のメンションを併記するか否か」だけ)

PR 作者本人 (= 自分) のコメントは fetcher 側ではフィルタしない。本スキルが「自分のコメント」「自分の集約サマリ」を識別して捌く。

---

## 出力する成果物 / 出力しない成果物

### 出力する成果物

- **集約サマリコメント 1 件** (`prr summary` 経由で PR の issue comment として投稿、毎回新規、過去サマリは履歴として残す)
- **inline thread への返信文字列** (`prr reply` / `prr resolve` 経由、vendor 別フォーマット)
- **修正コミット列 + push** (commit message に `Refs: <thread-url>` を含み、Phase C 終端で push 済み)
- **フォロー issue** (`VALID_DEFER` 判定時のみ、`prr defer` 経由で作成)
- **ユーザ向け最終報告** (Stats / Commits / Pushback / CI / Summary URL の固定構造、または `WAITING` verdict)。読み取り専用モードでは「確認モードの報告」のみ
- **`needs-human` ラベル + エスカレーションコメント** (無人実行で `WAITING` の受け手がいない場合のみ、`prr escalate` 経由)

### 出力しない成果物

- **新規レビュー実行結果**: CodeRabbit / Devin 自身を起動した出力は出さない (既存コメントへの後追い専用)。
- **ローカルログファイル**: `pr-review-response.md` 等のリポ内ファイルは作らない (トレースは PR 集約コメント 1 本のみ)。
- **構造変更を含む commit / テストコード**: それらは `tidy-first` / `tdd` 経由の出力で、本スキル内では呼び出しのみ。
- **`@devin` 再レビュー mention 文字列**: commit push を契機にした自動再評価に任せる。
- **`@coderabbitai resolve` コマンド (INVALID_PUSH 時)**: pushback 時は本文のみ、resolve 文字列は出さない。
- **既処理 thread への 2 度目の返信**: 自分が返信済みの thread には何も投稿しない。
- **既存集約サマリの編集差分**: サマリ更新は edit ではなく新規 issue comment として出す。

---

## 既知の限界

- **`embedded_findings` はベストエフォート**: CodeRabbit のレビュー本文レイアウト (旧: カテゴリ `<details>` > ファイル `<details>` > `` `range`: `` 形式 / 現行: `> [!CAUTION]` callout 内の太字見出し > 指摘ごとの `<details>` + `` `path:range` `` 形式) の 2 種に対応。未知レイアウトでは分解が空になるが `body` 全文は常に残るので、Phase A の規律どおり本文を読んで補う。
- **レビュー本文・会話コメントだけの新規指摘は `pr-monitor` 経由では起動されない**: `pr-monitor` は新規の未解決行スレッドだけを契機に本スキルを dispatch するため、行コメントを伴わない指摘は手動起動 (または push 後の起動) まで拾われない (kanade0404/skills#158 で対応予定)。
- **Devin protocol の表面追跡が必要**: Devin の出力フォーマットは更新される。本文判定の文字列マッチが滑ったら「人間扱い」に倒れるが、resolve 誤発行の害より対応漏れの害が小さいので意図通り。
- **GraphQL `reviewThreads.isResolved` への依存**: REST だけでは resolve 判定が取れないため GraphQL 併用。`gh` 認証スコープに graphql 必須。
- **`resolveReviewThread` mutation は書き込み権限が必要**: 読み取り専用の `gh` 認証や外部フォークからの実行では失敗する。自分の PR / write 権限のあるリポジトリで動かす前提。
- **`gh pr checks --watch` の長時間ブロック**: 大規模 CI で 30 分超を想定。バックグラウンド実行 + 通知に切り替える運用余地あり。
- **別リポジトリの同番号 PR は `-R` 無しでは検出できない**: cwd 由来で解決したリポジトリに同じ番号の PR が実在すると、`prr fetch` はそれを正しい PR として読む (PR 不在・リポジトリ不一致は非ゼロ exit で検出する)。stderr の `prr: repository ...` と出力の `pr.url` で対象を確認し、クローン外からは `-R` を必須とする。
- **github.com 専用**: `-R` / `GH_REPO` は `owner/repo` (または `github.com/owner/repo`) のみ受け付ける。GitHub Enterprise の `HOST/owner/repo` は、API 呼び出しが github.com の同名リポジトリを読んでしまうため非ゼロ exit で拒否する。
- **`prr defer` の重複検出は 1 レビューあたり 1000 件まで**: 既存 issue の候補検索は search API の上限 (1000 件) までしか見ない。同じレビューから 1000 件超を defer する運用は想定しない。
- **multi-PR 並走の分離**: 1 セッション内で複数 PR を同時に捌く運用は想定していない。PR ごとに 1 セッション。
