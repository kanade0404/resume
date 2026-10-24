# 共通: 設定ファイルと公開範囲

`company-research` と `industry-research` の両方が使う。

## 設定ファイル

- 実値: `~/.config/kanade0404-resume/research-config`(リポジトリの外。Read には `$HOME` を展開した絶対パスで渡す)
- テンプレート: `.claude/skills/company-research/research-config.example`(ダミー値のみ。コミット可)
- `industry-research` と `company-screening` も**同じ1ファイル**を読む。2つ目の設定ファイルは作らない

実値をリポジトリの外に置くのは、gitignore 対象のファイルが新しい worktree にコピーされず、
worktree を作るたびに ID を聞き直すことになるため。旧置き場所
`.claude/skills/company-research/research-config.local`(gitignore 対象)は移行用に読むだけで、新しくは書かない。

形式は `key=value`、1行1項目、`#` 以降はコメント。

| key | 意味 | 無い場合 |
|---|---|---|
| `company_db_data_source` | 企業DBのdata source(`collection://...`) | ユーザーに聞く |
| `company_db_parent_page` | 企業DBを置いている親ページURL | 任意。DB を探すときの起点 |
| `industry_db_page` / `industry_db_data_source` | 業界DBのページURLとdata source | ユーザーに聞く |
| `publications_db_page` / `publications_db_data_source` | 外部発信DBのページURLとdata source | ユーザーに聞く |
| `obsidian_dir` | Obsidian控えの置き場所(企業ごとの `.md`) | 控えを省略してよいか聞く |
| `obsidian_repo` / `obsidian_remote` | 控え先のgitリポジトリのローカルパスとremote | 同上 |
| `obsidian_merge` | `pr`(ブランチ+PR)/ `direct`(書くだけ、git操作なし) | `pr` |
| `web_search_budget` | セッション全体のWebSearch上限 | 環境変数 `CLAUDE_CODE_MAX_WEB_SEARCHES_PER_SESSION` の値、無ければ 200 |
| `scout_db_data_source` / `screening_*` | `company-screening` が使うスカウトDB と正本ページ(一覧は同 skill の「設定」表) | タイトル検索 → ユーザーに確認 |

### 読み方

1. Read ツールで `~/.config/kanade0404-resume/research-config` を読む。無ければ旧置き場所
   `.claude/skills/company-research/research-config.local` を読み、あれば中身を新しい置き場所へ写す
2. どちらにも無い、または必要な key が欠けている場合は、まず `notion-search` でページ・DB をタイトルで探す
   (企業DB は「企業」、業界DB は「業界」、外部発信DB は「外部発信」。`company-screening` の key は
   同 skill の表のタイトル)。同じタイトルの候補が複数ある、または親ページ(パス)が想定と違うときは
   推測で選ばず、候補を並べてユーザーに確認する。それでも埋まらない key **だけ**をまとめて1回でユーザーに聞く。
   クラウド実行など設定ファイルを置けない環境でも、この探索で動けるようにする
3. 確定した値を `research-config.example` の形式で `~/.config/kanade0404-resume/research-config` に書く
   (ディレクトリが無ければ作る)。以後同じセッションでは再質問しない
4. **リポジトリ内には書かない**。旧置き場所の `.local` も新しく作らない

## 公開範囲(このリポジトリは GitHub で公開されている)

skill 本文(`SKILL.md` / `references/` / `evals/` / `research-config.example`)に次を**書かない**:

- 特定の企業名・転職先候補名・調査対象の社名(例は「A社」「X社」で書く)
- Notion の DB / ページ ID、`collection://` URL、Notion のページURL
- Obsidian vault の具体パス、private リポジトリ名
- 報酬・給与・オファー内容などの機微情報

調査結果そのものは Notion と Obsidian(private)にだけ書く。このリポジトリには書かない。
scratchpad はセッションの scratchpad ディレクトリを使い、無ければ gitignore 対象の
`.claude/skills/<skill>/scratch/` を使う。

## 人に関する情報の境界

- 扱うのは**職業上の経歴**(所属・役職・在籍期間・公開登壇・公開記事)だけ
- 私生活・家族・健康・個人攻撃につながる情報は、公開されていても収集・記録しない
- 企業DBの「社員」relation 先の DB には書き込まない(個人の記録を増やさない)
- 給与・年収の数値は Notion/Obsidian の private 側にのみ置き、要約やこのrepoに出さない
