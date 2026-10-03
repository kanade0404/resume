# Phase 0: 準備(企業の特定・起点URL・予算)

**この Phase が終わるまで並列 subagent を出さない。** 企業を取り違えたまま並列調査を出すと、
全観点の結果が無駄になり、検索予算も失う(同名・類似名の別会社は珍しくない)。

## チェックリスト

```
- [ ] 0-1 設定ファイルを読んだ(common-config.md)
- [ ] 0-2 企業DBの対象レコードを fetch し、企業を一意に特定した
- [ ] 0-3 業界DBを確認し、industry-research の要否を判断した
- [ ] 0-4 起点URLリストを作った
- [ ] 0-5 scratchpad に search-log.md と budget.md を作った
- [ ] 0-6 企業DBの Status を In-Progress にした
```

## 0-2 企業の特定

1. 企業DB の data source を `notion-query-data-sources` / `notion-search` で検索し、対象レコードを `notion-fetch` する
   - レコードが無ければユーザーに「新規作成してよいか」を確認してから作る(Name・URL・事業内容だけ埋める)
2. レコードの **事業内容・URL・要約** を手がかりに公式サイトを開き、次を照合する
   - 正式社名(商号)、本店所在地、代表者名、設立年、主力プロダクト名
   - 法人番号(国税庁法人番号公表サイト)で商号・所在地を確認できれば `[照合済]`
3. 次の場合は**止めてユーザーに確認**する
   - 同名・類似名の会社が複数見つかり、レコードの情報だけでは決めきれない
   - レコードの URL と事業内容が別会社を指している
   - 商号変更・合併・持株会社化があり、どの法人を調べるか曖昧
4. 特定結果を `<scratchpad>/00-identity.md` に書く: 正式社名 / 旧社名 / 法人番号 / URL / 事業内容1行 /
   **取り違えやすい別会社と見分け方**。以後の全 subagent 指示文にこのファイルを読ませる

## 0-3 業界DBの確認

- 企業レコードの「業界」relation、または業界DB を業界名で検索する
- 該当業界レコードが**無い**、または `Status=調査中` で主要列が空 → 先に `industry-research` を実行する
  (Skill ツールで起動。企業調査の投資家目線 Phase が業界の市場規模・比較企業に依存するため)
- 該当レコードが**ある** → 参照のみ。業界DB の本文・列は変更しない(更新が必要そうなら最後にユーザーへ提案)

## 0-4 起点URLリスト

`<scratchpad>/01-seed-urls.md` に、見つかった URL と取得手段を表で書く。WebSearch より先に
公式サイトのフッター・会社概要・採用ページのリンクから辿る(予算を使わない)。

| 種別 | 探す場所 | 取得手段 |
|---|---|---|
| 公式サイト | 会社概要・IR・ニュース | WebFetch |
| プレスリリース | PR TIMES 企業ページ(`prtimes.jp/main/html/searchrlp/company_id/<id>`) | WebFetch / RSS |
| 公式 note / 個人 note | `note.com/<urlname>` | note API(`external-publications.md`) |
| RSS | ブログ・ニュースの feed | WebFetch(最大50件程度しか返らない点に注意) |
| テックブログ | 独自ドメイン、Zenn Publication、Qiita Organization、はてなブログ | WebFetch / RSS |
| 採用ページ | HERP、Green、Wantedly、Forkwell、自社採用サイト | WebFetch |
| 登壇資料 | SpeakerDeck のユーザー/組織ページ | WebFetch |
| イベント | connpass のグループページ | connpass API / WebFetch |
| GitHub | GitHub org | GitHub API |
| 決算 | 官報、電子公告ページ、決算公告 PDF | WebFetch |

見つからない種別は「未確認」と書く(無いとは書かない)。

## 0-5 予算と検索ログ

- `common-research-budget.md` に従い `<scratchpad>/search-log.md` を作る
- `<scratchpad>/budget.md` に「総予算 / 使用済み / 観点ごとの割り当て」を書く。
  目安(総予算 200、業界調査を同セッションで行う場合はその分を先に引く):

| 観点 | 目安 |
|---|---|
| Phase 1 各観点(4つ) | 各 10〜15 |
| Phase 2 投資家目線 | 25〜30 |
| Phase 3 組織・人 | 20 |
| Phase 4 外部発信 | 5(一覧は API で取る) |
| main 予備 | 20 |
