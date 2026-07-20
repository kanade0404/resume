# WRITEBACK-SCHEMA: Phase 6 書き戻しの一般化パターン

## 二層構造

| 層 | 保存先 | 内容 |
|---|---|---|
| 生ログ | `<private>/転職/<year>/グリルセッション成果_<YYYY-MM>.md` 相当(日付入り専用ファイル) | 逐語+導出過程。数値・社名・内情もここには許される(private側のみ) |
| 蒸留 | `<private>/profile/<topic>.md` | frontmatter付き要約+`[[出典]]`リンクのみ。生の数値・社名は書かない |

蒸留層から生ログ層へのリンクは `[[転職/<year>/グリルセッション成果_<YYYY-MM>]]`
のようなObsidian wiki-linkで持つ。

## profile frontmatter 仕様

```yaml
---
sensitivity: low | medium | high
status: filled | stub | needs-interview
updated: YYYY-MM-DD
sources:
  - "[[転職/<year>/グリルセッション成果_<YYYY-MM>]]"
---
```

- `sensitivity` は記述内容の機微度(vault内での取り扱い基準。private vault の
  既存運用に従う)
- `status` は Phase 0 の stub 抽出で使うキー。書き戻し後は `filled` に更新する
- `sources` は複数可。壁打ちで参照した過去ログ・台帳をすべて列挙する

## 台帳ファイルの更新

`<private>/転職/<year>/grill-ledger.md` を [LEDGER-FORMAT.md](LEDGER-FORMAT.md)
のスキーマで更新する。次回セッションのPhase 0がこれを読むことで、同じ問いを
繰り返さないループを閉じる。

## diff提示と適用の順序

1. 生ログファイルへの追記diff、profile各ファイルへの要約diff、grill-ledger.md
   への追記diffを**すべてscratch diffとして1メッセージにまとめて提示**する
2. ユーザ承認後にのみ `Write`/`Edit` で適用する
3. 本skillはgit commitを一切行わない(private vaultはユーザ自身が別途コミットする)

## 公開リポジトリへの反映が必要な場合

`docs/resume-update-plan.md` / `docs/action-plan.md` への反映が壁打ちの結果として
必要になった場合:

1. 機微(報酬額・企業名・退職理由の内情)を削いだ表現に変換したdiff案のみを提示する
   (社内システム名・特定クライアント名・広告出稿先ブランド名等の社内実装詳細は、
   `resume-update-plan.md` の既存の抽象化レベルに合わせて一般化した表現に言い換える)
2. コミットはユーザ承認後、かつ `pnpm run lint`(textlint)通過確認後に行う
3. この適用作業自体は本skillの範囲外の別フロー(通常のREADME/detail.md編集フロー)
   に委譲する。本skillはdiff案の提示までで止まる
4. `README.pdf` はCIが自動生成・自動コミットする対象であり、本skill(または人手)が
   手動でコミットしてはならない
