# Functional Core: FP + Railway + xUnit Test Patterns

「判断ロジックを純関数に寄せ、I/O を薄い外殻に押し出す」設計のレンズ集合。

## 関数型プログラミング（一般）

- **純関数 = 同じ入力で同じ出力 / 副作用なし。** ドメイン判断はここに寄せる。
- **代数的データ型（ADT）。**
  - **Sum type**（Discriminated Union）で状態を網羅: `Pending | Approved | Rejected(reason)`。boolean フラグの組合せで状態を表すのは禁則。
  - **Product type** で値を束ねる（Tuple / Record）。
  - 言語が ADT を持たないなら sealed hierarchy / tagged union / `match` で代替。
- **不変データ。** in-place 変更を避ける。`State -> State` を返す関数で表す。
- **高階関数で振る舞いを差し替える。** ストラテジーパターンの軽量版。
- **副作用は戻り値として表す。** `IO<T>`, `Effect<T>`, `Reader<E, T>` 風。実装上は async や Promise が境界の signal。
- **依存性は引数。** Singleton / global 経由で注入しない。

## Railway Oriented Programming（Scott Wlaschin）

例外を制御フローに使わず、`Result<T, Err>` / `Either<Err, T>` で「成功線路」と「失敗線路」を 2 本敷く。`bind` / `map` / `flatMap` で線路を合成する。

### 適用基準

- ドメイン操作が **失敗しうる種類が複数** ある（バリデーション失敗、認可失敗、整合性違反）
- 失敗ごとに **呼び出し側が違う対応** をする（再入力 / 認可失敗の HTTP コード分岐 / リトライ可否）
- 失敗を **網羅的に処理させたい**（compiler に exhaustiveness を見させる）

`Result<T, Err>` の `Err` は **sum type**。`string` ではなくドメインエラーの ADT。

### やらないこと

- `Result` を ad-hoc に作って throw と混在させる（線路が分裂する）
- `Result.unwrap()` をドメイン中で呼ぶ（境界以外で例外に戻すのは意味がない）
- 「ログ出力」「メトリクス計上」を `bind` の中で副作用としてやる（外殻 / Decorator に分離）

### 例外との分担

- **例外 = プログラマのバグ / インフラ障害**（ファイル開けない、想定外 null）
- **`Result` = ドメインの "起こりうる結末"**（在庫切れ、権限不足、入力不正）

線引きが曖昧なときはまず `Result` 側で書く。本当に "起こり得ない" なら `panic`/`throw` で良い。

## Functional Core / Imperative Shell

Gary Bernhardt のパターン。

- **Functional Core**: 純関数だけ。判断・変換・整合・組合せ。テストは値同士の比較で十分。
- **Imperative Shell**: I/O。DB 読み書き、HTTP、ファイル、time、乱数。Core を呼んで結果を捌く。
- Core は依存も状態も持たない。Shell から見ると Core は単なる "計算式"。

### Humble Object（Meszaros）

I/O やフレームワーク呼び出しと「自分の判断ロジック」を分け、判断ロジック側だけテストする。Functional Core / Imperative Shell の test pattern 版。

## xUnit Test Patterns（Meszaros）

詳細は `test-review` の references にもあるが、設計フェーズで気にする部分：

- **Test Double 分類**: Dummy · Stub · Spy · Mock · Fake。Fake と Stub の乱用は設計のシグナル。
- **Functional Core が取れていれば Test Double はほぼ要らない。** Test Double を欲しがるテストが書きたくなった時点で、設計を疑う（Step 5）。
- **Four-Phase Test**: Setup · Exercise · Verify · Teardown を視覚的に分離。
- **Humble Object で I/O を 1 行に圧縮**：`return svc.fetch(url, opts)` のような薄さなら、Core に対する property based test だけで広く守れる。

## レビュー観点

- 例外を制御フローに使っていないか
- 例外メッセージで「失敗の種類」を表現していないか（→ Err sum type に）
- 純関数化できる判断ロジックが I/O に絡まって書かれていないか
- async / Promise を Core 側に持ち込んでいないか
- Test Double が必要になった瞬間に「Core を抽出できないか」を先に問えているか
- ADT を boolean の組合せで代替していないか
