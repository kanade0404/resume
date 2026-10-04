---
name: industry-research
description: >-
  転職先候補の企業が属する業界を、Notion の業界DB に登録する前提で再現性のある手順で調べる。
  日本(市場規模と出典の質、商流、規制、追い風/逆風、プレイヤー比較、M&A・上場・調達)、米国
  (市場規模、構造、トレンド、主要プレイヤーとスタートアップ、エグジット)、日米スタートアップ比較と
  日本への示唆、市場規模の数字の検証(調査会社間のばらつき、会社主張の逆算)までを行い、業界DB の
  列に合わせて書き込む。「業界調査して」「業界DBに追加して」「日米の業界比較」「市場規模は本当?」
  「この業界の主要プレイヤーは?」「〇〇業界を調べて」「米国の同業スタートアップと比べて」の
  ような依頼、および company-research の Phase 0 で業界DB に該当業界が無いときに必ず起動する。
  特定企業の評価は company-research、キャリアの相談は career-grilling、技術やライブラリの比較は
  research-practices、業界DB に登録しない単発の一般レポートは deep-research の担当で、これらでは
  起動しない。
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Agent, SendMessage, Skill, WebFetch, WebSearch, ToolSearch
---

# industry-research

転職先候補の企業を評価するための前提となる、業界の構造と市場規模を調べる skill。結果は業界DB に
1業界1レコードで蓄積し、複数の企業調査から再利用する。

**このリポジトリは公開されている。** skill 本文に特定企業名・Notion の ID/URL・具体パスを書かない。

## 依存(company-research と共有)

設定ファイルと共通ルールは `company-research` 側に1か所だけ置き、ここから参照する。
下表の共通参照ファイルが無い場合は「company-research skill が見つからないため共通ルールを読めない」と
ユーザーに伝えて停止する(推測で進めない)。設定ファイル `research-config.local` が無い場合は停止せず、
`common-config.md` の手順で必要な値をユーザーに聞いて作成する。

| ファイル | 内容 |
|---|---|
| `.claude/skills/company-research/research-config.local` | 業界DB・企業DB の ID(gitignore 対象。無ければ作成する) |
| [../company-research/references/common-config.md](../company-research/references/common-config.md) | 設定ファイルの読み方・公開範囲 |
| [../company-research/references/common-sourcing.md](../company-research/references/common-sourcing.md) | 出典・確度ラベル・事実と推測の区別 |
| [../company-research/references/common-research-budget.md](../company-research/references/common-research-budget.md) | WebSearch 予算・検索ログ・Codex CLI |
| [../company-research/references/common-subagent-ops.md](../company-research/references/common-subagent-ops.md) | subagent 運用・hook/権限の代替 |
| [../company-research/references/notion-schema.md](../company-research/references/notion-schema.md) | 業界DB の列名と意味 |

## いつ使うか / 使わないか

| 依頼 | 使う skill |
|---|---|
| 業界の市場規模・構造・プレイヤー・日米比較、業界DB への追加 | **industry-research** |
| 会社が主張する市場規模が業界統計と合うかの検証 | **industry-research**(業界の値を作る)→ company-research が企業側で参照 |
| 特定企業の評価(事業・IPO・組織・発信) | `company-research` |
| 転職するか・どの業界に行くべきかの壁打ち | `career-grilling` |
| 技術・ライブラリの比較 | `research-practices` |
| 業界DB に残さない単発の一般レポート | `deep-research` |

## ワークフロー

```
- [ ] Step 0 準備: 設定読込、業界DB の既存レコード確認、業界の範囲定義、予算と検索ログ
- [ ] Step 1 日本(並列 subagent)
- [ ] Step 2 米国(並列 subagent)
- [ ] Step 3 市場規模の検証
- [ ] Step 4 日米スタートアップ比較と日本への示唆
- [ ] Step 5 整合チェック → 業界DB へ書き込み
```

### Step 0: 準備

1. `common-config.md` に従い設定ファイルを読む
2. 業界DB を業界名・類義語で検索する
   - 既存レコードがあり `Status=完了` → 再調査するかユーザーに確認(調査日が1年以上前なら再調査を提案)
   - 既存レコードがあり `調査中` → 空の列だけを埋める方針で続ける。既存の列の値を
     `<scratchpad>/i01-existing.md` に控える(Step 5 で上書きを防ぐため)
   - 無い → `Status=調査中` でレコードを作る
3. **業界の範囲を1段落で定義**して `<scratchpad>/i00-scope.md` に書く: 含むもの / 含まないもの /
   隣接業界 / 日米で同じ業界として扱う根拠。範囲が曖昧なまま市場規模を集めると、調査会社ごとに
   違う範囲の数字を比べることになる
4. 検索ログと予算(`common-research-budget.md`)。company-research から呼ばれた場合は、
   その予算表の業界調査枠(目安 40〜50 回)を使う

### Step 1: 日本 / Step 2: 米国

→ [references/japan-us.md](references/japan-us.md)

日本と米国を別 subagent(sonnet)で並列に調べる。出力は `<scratchpad>/i10-japan.md` / `i20-us.md`。

### Step 3: 市場規模の検証

→ [references/market-size-verification.md](references/market-size-verification.md)

調査会社間のばらつき、範囲定義の違い、会社主張の逆算。opus subagent か main で行う。

### Step 4: 日米スタートアップ比較

→ [references/us-japan-comparison.md](references/us-japan-comparison.md)

7観点の比較表と日本への示唆。

### Step 5: 整合チェックと書き込み

1. `common-sourcing.md` のルールで統合稿 `<scratchpad>/i60-draft.md` を確認(出典・確度ラベル・仮定の明記・
   訂正の全箇所反映・[Codex報告] が残っていないこと)
2. 業界DB のプロパティを書く(列の対応は下表)。既存レコード(`調査中` で再開)は `i01-existing.md` で
   空だった列だけを `update_properties` に入れる。値のある列を変える場合は、新旧の値を示してユーザーに
   確認してから書く。企業 relation は既存の値を残して追加する
3. 本文に統合稿を差し込む(既存本文は変更しない、`update_content` / `insert_content`、全文置換禁止、
   前後で diff 比較、表は `<table>`。詳細は `notion-schema.md`)
4. 企業調査から呼ばれた場合は、企業 relation に対象企業を追加する
5. `Status=完了`、`調査日` を設定

| 業界DB の列 | 入れる内容 |
|---|---|
| Name | 業界名(既存レコードの粒度に合わせる) |
| 企業 | 調査済み企業の relation |
| 日本市場規模 / 米国市場規模 | 採用値・年・出典、ばらつきの範囲(Step 3 の結論) |
| 成長性 | 高 / 中 / 低(判定根拠は本文) |
| 日本の主要プレイヤー / 米国の主要プレイヤー | 社名と一言(上場/未上場、規模) |
| 日米スタートアップの違い | Step 4 の要点3〜5行 |
| 調査日 / Status | 調査日 / 完了 |

Obsidian 控えが必要な場合(ユーザーが求めたとき、または company-research から呼ばれたとき)は、
company-research の Phase 5・7 と同じ方法で行う(`../company-research/references/phase5-7-writeback.md`)。

## 出力フォーマット(ユーザーへの最終報告)

```
# 業界調査: <業界名>(<調査日>)

## 範囲の定義(1段落)
## 市場規模: 日本 <採用値>(範囲 <最小>〜<最大>)/ 米国 <採用値>(範囲)
## 成長性: 高/中/低 と根拠1行
## 日米スタートアップの違い(3行)
## 日本への示唆(3行)
## 書き込み先: 業界DB(新規/更新)、追加した本文セクション
## 未確認の主要事項
## 検索予算: WebSearch 使用 N / 上限 M
```

## このスキルがやらないこと

- 個別企業の評価・IPO 見立て・組織調査(`company-research`)
- 投資判断・銘柄推奨
- 業界DB 以外のデータベースへの書き込み(企業DB は relation の追加のみ)
- このリポジトリ(経歴書)への調査結果の記載

## リファレンス

| ファイル | いつ読む |
|---|---|
| [references/japan-us.md](references/japan-us.md) | Step 1・2 の subagent 指示文を作るとき |
| [references/market-size-verification.md](references/market-size-verification.md) | Step 3 |
| [references/us-japan-comparison.md](references/us-japan-comparison.md) | Step 4 |
| 共通参照(上の「依存」表) | Step 0 と subagent 指示文の作成時 |
