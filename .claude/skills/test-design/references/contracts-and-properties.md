# 契約からの導出 と Property-based Testing の taxonomy

Design by Contract（Bertrand Meyer）/ Hoare 論理からの導出手順と、property-based testing で property をどう選ぶかの taxonomy。Python/Hypothesis 固有の書き方は `skills/test-review/references/python.md` に既にあるため重複させない。fast-check (JS/TS) 等、本カタログに専用リファレンスが無いツールの API 詳細は各ツールの公式ドキュメントを参照する。ここでは「何を assert すべきか」の方法論に集中する。

---

## 1. 契約からの導出 (Hoare 論理 / Design by Contract)

**表記.** `{P} C {Q}` — 事前条件 `P` を満たす状態でコマンド `C` を実行すると、事後条件 `Q` を満たす状態で終了する。加えて `C` の実行を通じて常に成り立つべき **不変条件 (invariant)** を持つ場合がある。

**手順.**
1. 対象のシグネチャから `P`（呼び出し側が保証すべき前提）を全て書き出す。型だけで表現できない制約（「配列は空でない」「日付は未来でない」等）を優先的に拾う。
2. `Q`（呼び出し後に保証される性質）を書き出す。戻り値の性質だけでなく、副作用（状態変化、外部への書き込み）も含める。
3. `invariant`（呼び出し前後で常に成り立つ性質、例: 「リストの長さは減らない」「合計金額は負にならない」）を書き出す。無ければ「なし」と明記する。
4. 契約設計の判断: **defensive contract**（`P` 違反時に例外/エラーで防御する）か **wide contract**（`P` の範囲を広げて呼び出し側の制約を減らす）かを確認する。この判断自体が API の設計判断であり、**本スキルが独自に決めるものではない**。既存の仕様・型・コードコメントから defensive/wide のどちらかが既にトレース可能ならそれに従う。トレースできない場合は SKILL.md Step 1 の規律（黙って推測しない）に従い、`AskUserQuestion` で確認するか「要確認」タグを付けて `design`/`software-design` に判断を委ねる — テスト設計側が固定するのは対応関係だけ（defensive なら (b) のエラー系テストを書く、wide なら該当入力を正常系として (a) に含める）。

**ここから 3 種類のテストが導出される。**

**(a) 事後条件 → 正常系 assertion.** `Q` に書いた各性質をそのまま assertion にする。`Q` が複数の独立した性質を持つなら、性質ごとに 1 ケース（または 1 テスト内の複数 assertion、`test-review` の「1 テスト 1 概念」に従う）。

**(b) 事前条件違反 → エラー系テスト.** defensive contract を選んだ場合のみ、`P` の各条件について「その条件を破った入力」を 1 つずつ独立にケース化する（同時に複数条件を破らない — どの条件が原因でエラーになったか切り分けられなくする）。wide contract を選んだ場合は、その入力はそもそも `P` の範囲内なので (a) の正常系に含める。

**(c) 不変条件 → 全テスト共通の検証 or 独立の property.** `invariant` は個別ケースの assertion に混ぜてもよいし、Step 2 で property-based を選んだ場合は §2 の invariant property として独立に書いてもよい。両方に書いて二重に検証する必要はない。

**例.** `withdraw(account, amount)`:
- `P`: `amount > 0`、`account.balance >= amount`
- `Q`: 戻り値の新しい残高 `== account.balance - amount`、取引履歴に 1 件追加される
- invariant: `account.balance` は常に `0` 以上
- defensive contract を選択 → `amount <= 0` と `account.balance < amount` はそれぞれ独立にエラー系ケース化

**設計表への落とし方.** 技法列 = `契約`、導出根拠列 = `postcondition: <Q の項目>` / `precondition 違反: <P のどの条件か>` / `invariant: <不変条件>`。

契約技法を複合ラベル（`状態遷移/契約` 等）として追加するのは、precondition 違反または独立した invariant 検証を明示的に狙う場合に限る。正常系の出力検証は事後条件の確認そのものであり、契約ラベルを重ねない（ラベルのインフレ防止）。

---

## 2. Property-based Testing の Property 導出 Taxonomy

**example-based との使い分け.** 個別の入出力ペアで十分検証できる振る舞い（デシジョンテーブルの各列、契約の (a)(b)）は example-based のままでよい。**入力空間が広く、かつ入力と出力の間に代数的な関係が成り立つ**場合にのみ property-based を追加する — 全てのテストを property 化する必要はない。

Property は次の 5 分類から選ぶ。複数該当してよい。

### Invariant（不変条件）
入力に関わらず常に成り立つ性質。§1 の invariant をそのまま property 化したもの。
例: 「ソート後の配列は要素数が変わらない」「正規化後の文字列は必ず NFC 形式」

### Roundtrip（往復変換）
`decode(encode(x)) == x` の形。エンコード/デコード、シリアライズ/デシリアライズ、圧縮/展開のような対になる変換に使う。
例: `parse(serialize(obj)) == obj`

### Oracle（参照実装との一致）
素朴な別実装（遅くても正しいとわかっている実装、あるいは既存のライブラリ）と出力を突き合わせる。最適化された実装の正しさを、愚直な実装と比較して検証する時に使う。
例: 自前のソートアルゴリズムの出力を標準ライブラリの `sort` と比較する

**注意.** oracle として「対象と同じロジックをテスト内に再実装したもの」を使うと `test-review` の AI 生成アンチパターン「oracle copy-paste」に陥る。oracle は対象と **独立した実装**（別アルゴリズム、既存の信頼できるライブラリ）でなければならない。

### Metamorphic（変換関係）
入力に何らかの変換を加えたときに、出力がどう変化する「はず」かという関係を検証する。個別の期待値がわからなくても、相対的な関係は検証できる場合に使う。
例: 「ソート済み配列に要素を 1 つ追加して再ソートしても、元の要素間の相対順序は保たれる」「画像を上下反転してから顔検出しても、検出数は変わらない」

### Idempotence（冪等性）
`f(f(x)) == f(x)`。同じ操作を 2 回適用しても結果が変わらない性質。
例: 「正規化関数を 2 回適用しても 1 回適用と同じ」「PUT リクエストを 2 回送っても状態は 1 回目と同じ」

**shrinking しやすい property の書き方.**
- property の前提条件（`assume`/`pre` のようなフィルタ）を最小限にする。フィルタが厳しいほど shrinking が失敗しやすい。
- 生成する入力の構造をシンプルに保つ（ネストの深いオブジェクトより、フラットな構造の組合せで表現できないか検討する）。
- 失敗時に人間が読める最小反例が得られるよう、生成戦略はまず単純な型（整数・短い文字列）から試す。

具体的なツールの書き方は、Hypothesis (Python) の `@given`/`strategies` なら `skills/test-review/references/python.md` を参照する（重複させない）。fast-check (JS/TS) の `fc.assert`/`fc.property` 等、本カタログに専用リファレンスが無いツールは各ツールの公式ドキュメントを参照する。

**設計表への落とし方.** 技法列 = `property/<種類>`（例: `property/roundtrip`）、導出根拠列 = `<種類>: <どの代数的性質か>`。
