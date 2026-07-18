# Design Review Checklist

`skills/software-design/references/*.md` の "レビュー観点" を、レビュー subagent が機械的に当てやすいよう設問形式にまとめたもの。本書を読み手 (subagent) が直接見る想定。

各設問について `○` / `×` / `?` のいずれかで答え、`×` は issue + Fix + path:line を必ず添える。

---

## philosophy（Ousterhout）

1. 公開 API の幅は実装の厚みに見合うか? Shallow Module になっていないか?
2. インタフェースに不必要なパラメータ / 順序依存 / 暗黙のグローバル状態が露出していないか?
3. 名前に "process" / "handle" / "manage" / "util" のような曖昧語が含まれていないか?
4. 同じ知識（フォーマット規約、エンコーディング、状態遷移表）が複数モジュールに重複していないか?
5. 下層概念（HTTP ステータス、SQL エラーコード）が上層に漏れ出していないか?
6. 例外を増やす前に「例外が起きない API」を検討した跡があるか?
7. コメントは "コードが言わない情報"（不変条件 / why / 設計意図）を補っているか? 「コードが言うこと」を繰り返していないか?

---

## data-model（Immutable Data Model + TM法）

1. 不変属性 / 可変属性 / 履歴属性 が同一クラス・同一テーブルに混在していないか?
2. 主キーが「後から変わる属性」を含んでいないか? (email, name, login_id を natural key に使っていないか)
3. nullable 列が "状態" を表していないか? （→ 状態は ADT / 状態遷移で表す）
4. Event と Resource を 1 テーブル / 1 集約に混ぜていないか?
5. 削除が `deleted_at` のような sentinel ではなく状態遷移として表現されているか?
6. `created_at` / `updated_at` がドメインロジックを駆動していないか?（監査用 metadata に留まっているか）
7. 値オブジェクト化基準（型混同 / 妥当性 / ドメイン演算）を満たす場所でプリミティブのままになっていないか?

---

## functional-core（FP + Railway + xUnit）

1. 例外が制御フロー（バリデーション失敗、認可失敗、整合性違反）に使われていないか?
2. ドメインエラーが文字列 / 単一例外型ではなく sum type で表現されているか?
3. 純関数化できる判断ロジック（parse, validate, route, decide）が I/O コードと混在していないか?
4. async / Promise / IO が Functional Core 側に侵入していないか?
5. boolean フラグの組み合わせで状態を表していないか?（→ ADT に）
6. Test Double を 5 個以上組まないとテストが書けない構造になっていないか?
7. `Result.unwrap()` がドメインの中で呼ばれていないか? (境界以外で例外に戻していないか)

---

## domain（DDD / Khononov）

1. Core / Supporting / Generic の判別が ADR / proposal に書かれているか?
2. Supporting や Generic に Tactical DDD（集約 / 値オブジェクト / イベント）の重装備が当たっていないか?
3. ユビキタス言語に同義語の混在がないか?（user / customer / account 等）
4. 集約境界 = トランザクション境界になっているか? 1 トランザクションで複数集約を更新していないか?
5. 集約間の参照が ID ではなくオブジェクト参照になっていないか?
6. 集約 root 以外を外から直接参照していないか?
7. ドメインイベントが過去形で命名されているか? (命令形は command と混ざる)
8. Bounded Context 間の統合パターン（Partnership / Customer-Supplier / ACL / OHS / Conformist / Shared Kernel / Separate Ways）が ADR に書かれているか?

---

## tdd（Beck）

1. 新規 Core 機能に対して red → green → refactor のリズムが辿れる粒度のコミットになっているか?
2. テスト命名が "behavior_when_condition" 風になっているか? (`test_works`, `test_fn_1` 等の意味なし命名がないか)
3. リファクタリング（tidy）と振る舞い変更が同一コミットに混ざっていないか?
4. private 露出 / time / random / uuid 直接呼びのテストが残っていないか? (DI されているか)
5. 1 テストの行数が常識的か? (30 行超は集約 / 責務肥大の兆候)

---

## architecture（Fundamentals + CQRS + Event Sourcing）

1. 採用したアーキテクチャ特性（-ility）が 3 個以下に絞られ、ADR に書かれているか?
2. 量子の数が意図通りか? 同期 RPC で実質 1 量子になっていないか?
3. スタイル選定の理由が「どの -ility を優先したか」で書けているか?
4. CQRS を採用するなら、read/write 非対称性 / 別 SLA / 投影の独立性 のいずれかが具体的に説明されているか?
5. CQRS / Event Sourcing が「採用理由」だけでなく「採用しない場合の代替案」と並べて評価されているか?
6. Event Sourcing を採用するなら、イベントスキーマ進化 / スナップショット / 冪等性 / outbox のいずれかが言及されているか?
7. ES のイベントが過去形で命名されているか?

---

## adr（Nygard）

1. 1 ADR 1 決定になっているか? 複数論点が混在していないか?
2. Considered Options に却下案が複数（最低 1 つ以上、できれば 2 つ以上）あるか?
3. Consequences に Negative が書かれているか? (Positive だけは怪しい)
4. Drivers / 制約に "どの -ility を優先したか" が書かれているか?
5. Status が Accepted の ADR が後から書き換えられていないか?（変更は新 ADR + Superseded で）
6. ファイル名が `NNNN-<kebab-title>.md` 形式で連番に穴 / 重複がないか?
7. タイトルが命令形 / 断定形か? (`Use X for Y`, `Adopt CQRS for orders`, `Reject microservices for v1`)

---

## security（Secure by Design）

1. 入力 raw 値（外部 HTTP / queue / file 由来の生 string・number）が API 入口より深く流れていないか?
2. ドメインプリミティブ（Email, Money, OrderId, Quantity 等）に妥当性検証がコンストラクタで強制されているか?
3. バリデーションが境界 / middleware / service / DB に重複していないか?
4. 認可判定がドメイン操作内の `if role == ...` で散っていないか? (型 / capability で表現できているか)
5. 失敗時のデフォルト動作が "通る" になっていないか? (fail closed が守られているか)
6. Quantity / collection size / 試行回数 / レートに上限が定義されているか?
7. ログに平文の機微データ（パスワード、トークン、PII）が乗っていないか? `Sensitive` 型で守られているか?

---

## レビュー判定の集計

各レンズで `×` を数え、Critical / Major / Minor を判定する：

| 内容 | レベル |
|---|---|
| データ漏洩 / 認可スキップ / トランザクション境界違反 / 不変条件破綻 | Critical |
| ADR の Considered Options 不足 / 集約肥大 / Test Double 濫用 / 名前曖昧 | Major |
| コメント過不足 / コミット粒度 / 単発の命名 | Minor |

迷ったら 1 段重く判定する（誤って甘くするより、ユーザに判断を返す方が安全）。
