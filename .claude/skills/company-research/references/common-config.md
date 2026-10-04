# 共通: 設定ファイルと公開範囲

`company-research` と `industry-research` の両方が使う。

## 設定ファイル

- 実値: `.claude/skills/company-research/research-config.local`(gitignore対象。コミット禁止)
- テンプレート: `.claude/skills/company-research/research-config.example`(ダミー値のみ。コミット可)
- `industry-research` も**同じ1ファイル**を読む。2つ目の設定ファイルは作らない

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

### 読み方

1. Read ツールで `research-config.local` を読む
2. 無い、または必要な key が欠けている場合は、欠けている key **だけ**をまとめて1回でユーザーに聞く。
   Notion の場合は `notion-search` で DB 名(「企業」「業界」「外部発信」)を検索し、候補を提示してから確認してよい
3. 回答を `research-config.example` の形式で `research-config.local` に書く。以後同じセッションでは再質問しない
4. 書いた直後に `git -C <このrepo> check-ignore -v .claude/skills/company-research/research-config.local` で
   ignore されていることを確認する(ignore されていなければ書き込みを取り消してユーザーに報告)

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
