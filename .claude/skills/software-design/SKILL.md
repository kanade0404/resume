---
name: software-design
description: >-
  ソフトウェア設計の判断・指示・成果物（モデル / モジュール境界 / エラー戦略 / アーキテクチャ決定 /
  セキュリティ）を扱う際に起動するスキル。philosophy of software design (Ousterhout)、immutable data
  model (kawasima)、TM法 (佐藤正美)、関数型プログラミング、Domain-Driven Design (Vlad
  Khononov)、TDD (Kent Beck)、Railway Oriented Programming (Scott
  Wlaschin)、Fundamentals of Software Architecture、xUnit Test Patterns、CQRS、Event
  Sourcing、ADR (Nygard)、Secure by Design の 13
  本を一貫したレンズ群として適用する。「設計どうする」「ドメインモデル作って」「集約をどこで切る」「Result 型に直したい」「例外やめて Railway
  で」「CQRS 入れる?」「Event Sourcing 採用する?」「ADR 書く」「アーキテクチャ決定を残す」「immutable
  データモデルに直して」「TM法でモデル化して」「TDD で進めたい」「Deep Module になってる?」「サブドメイン分けたい」「Secure by
  Design
  観点で見て」のような要請のほか、コードを書く前のモデル設計フェーズ、既存設計の妥当性レビュー、トランザクション境界・副作用境界・データ整合性の議論、技術的負債の優先度判断、セキュリティ設計レビューでも必ず起動する。テスト本体のレビューは
  `test-review`、調査作業は `research-practices`、Skill 自体の新規作成は `skill-builder`
  の担当のため、それらの目的が明確な依頼ではこのスキルを起動しない。実装そのものを書き下すだけの作業（タイポ修正、lint
  違反対応、単純なバグ修正、純粋なパフォーマンスチューニング）は本スキルの範囲外で、本スキルは「どう設計すべきか」を構造化して提示・指摘するためのレンズ集である。設計後の最終レビューは
  `design-review` を併用する。
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - WebFetch
  - WebSearch
  - TaskCreate
  - TaskUpdate
  - TaskList
  - AskUserQuestion
  - mcp__plugin_context7_context7__resolve-library-id
  - mcp__plugin_context7_context7__query-docs
  - mcp__plugin_serena_serena__find_symbol
  - mcp__plugin_serena_serena__find_referencing_symbols
  - mcp__plugin_serena_serena__get_symbols_overview
  - mcp__plugin_serena_serena__search_for_pattern
  - mcp__plugin_serena_serena__list_dir
  - mcp__plugin_serena_serena__find_file
  - mcp__plugin_serena_serena__read_file
---
# Software Design

設計判断を「センス」ではなく **再現可能なレンズの組み合わせ** で行うためのスキル。13 冊分の主張を毎回頭の中で素手で並べる代わりに、状況からレンズを選ぶ → そのレンズの主張を読みに行く、という同じ手順を踏む。

設計は「正しい一つの答え」を見つける作業ではなく、**トレードオフを言語化して残す** 作業。だから本スキルの最終成果物は常にコードではなく、**意思決定の根拠が読める文章**（ADR / モデル図 / レビューコメント）である。

---

## 13 レンズの一覧

| レンズ | 出典 | 何を見るか |
|---|---|---|
| Philosophy of Software Design | Ousterhout | モジュールの深さ・複雑度の漸進的増大・情報隠蔽 |
| Immutable Data Model | kawasima | 不変属性 / 可変属性の分離・履歴・参照性 |
| TM法 | 佐藤正美 | 主キーの整合・事実と認識の分離・event / resource |
| Functional Programming | 一般 | 純関数 / 副作用境界・参照透過・代数的データ型 |
| Domain-Driven Design | Vlad Khononov "Learning DDD" | サブドメイン分類・境界づけ・集約・統合パターン |
| Test-Driven Development | Kent Beck | red-green-refactor・テストが設計に与える圧力 |
| Railway Oriented Programming | Scott Wlaschin | Result/Either の合成・例外の排除 |
| Fundamentals of Software Architecture | Richards & Ford | 量子・特性・アーキテクチャスタイル選定 |
| xUnit Test Patterns | Meszaros | Test Double の分類・Four-Phase Test |
| CQRS | Greg Young 系 | 読み / 書きの非対称性・モデル分割 |
| Event Sourcing | 同上 | 状態ではなく事象の永続化・投影 |
| ADR | Nygard | 設計決定を文脈・選択肢・帰結で残す |
| Secure by Design | Bergh Johnsson, Deogun, Sawano | ドメインプリミティブ・契約による検証 |

各レンズの要点は `references/` に分割：

- `references/philosophy.md` — Ousterhout
- `references/data-model.md` — Immutable Data Model + TM法
- `references/functional-core.md` — FP + Railway + xUnit Test Patterns
- `references/domain.md` — DDD (Khononov)
- `references/tdd.md` — TDD (Beck)
- `references/architecture.md` — Fundamentals + CQRS + Event Sourcing
- `references/adr.md` — ADR (Nygard)
- `references/security.md` — Secure by Design

レンズは事前に全部読まない。Step 1 で要るものだけ拾いに行く。

---

## ワークフロー

### Step 1 — タスク分類（どのレンズが要るか）

入力を読み、以下の表で必要なレンズ集合を決める。複数該当することが普通。

| 入力の信号 | 主レンズ | 補助レンズ |
|---|---|---|
| 新規プロダクト / 新規境界の切り出し | DDD, Architecture | Philosophy, ADR |
| 既存モジュールの設計レビュー | Philosophy | DDD, FP |
| データモデルを起こす / 直す | Immutable Data Model, TM法 | DDD, Security |
| 例外まみれ / null まみれ / try ネスト | FP, Railway | Philosophy |
| 「テストが書きにくい」 | TDD, xUnit, FP | Philosophy |
| 読み / 書きが非対称（read 重い、書き保証重い） | CQRS | Architecture, Event Sourcing |
| 監査・履歴・時系列再生が要件 | Event Sourcing | Immutable, CQRS |
| 技術選定・スタイル選定 | Architecture, ADR | DDD |
| API 入力 / 認可 / 機微データ | Security | DDD, FP |
| 設計決定を残す | ADR | （全レンズの帰結を集約） |

選んだ各レンズについて、対応する `references/*.md` を読む。読まずに記憶で答えない。

### Step 2 — ドメイン理解（コードを書く前）

DDD と TM法 を併用してドメインを言語化する。詳細は `references/domain.md` と `references/data-model.md`。

最低限の確認：

- **Core / Supporting / Generic の判別。** Core にだけ最良の道具を投入する（Khononov）。Supporting にカスタム集約を作らない。
- **ユビキタス言語の固定。** 同じ概念を 2 つ以上の名前で呼んでいたら必ず統一する。`User` と `Account` が同義かどうか曖昧なまま設計に入らない。
- **event vs resource の分類**（TM法）。「発生したこと」（event）と「在るもの」（resource）を混ぜると主キー設計が崩れる。
- **集約境界 = トランザクション境界。** 1 トランザクション 1 集約を既定。例外は明示的根拠（ADR）と一緒に。
- **Bounded Context 間の統合パターン**（Customer/Supplier · ACL · OHS · Conformist · Partnership · Shared Kernel）を選び、ADR に書く。

### Step 3 — モデル設計（不変性 / プリミティブ / 契約）

`references/data-model.md` と `references/security.md` を当てる。

- **不変属性 / 可変属性 / 履歴属性を分離。** 属性ごとに性格が違う。ID（不変）／状態（可変）／ログ（履歴）を 1 個のクラスに混ぜない（kawasima）。
- **値オブジェクトを過剰に作らない、過少にも作らない。** 「`int` の意味が増えた瞬間」が値オブジェクト化の閾値（Email, Money, OrderId など）。
- **ドメインプリミティブ**（Bergh Johnsson）= 値オブジェクト + コンストラクタで全契約を強制。`new Email(s)` を通った瞬間に「妥当な email」が型レベルで保証される。バリデーションが層を貫いて散らない（Secure by Design）。
- **代数的データ型で状態を表す。** `Pending | Approved(by) | Rejected(reason)` のように状態を sum type で。boolean フラグの組合せは禁則。
- **TM法の主キー規律。** 「在るもの」の identifier は外部から与えられる（自然キー）か、システムが永続的に発行する（サロゲート）。後から変わる属性を主キーに使わない。

### Step 4 — モジュール / コードレベル設計

`references/philosophy.md` と `references/functional-core.md` を当てる。

- **Deep Module を作る（Ousterhout）。** インタフェースは小さく、実装は厚く。逆（薄い実装に長い API）は cost。
- **Strategic vs Tactical。** 戦術的な複雑度は許容しても、戦略的（後から効く）複雑度は早期に潰す（情報隠蔽 / 名前 / コメント）。
- **Functional Core / Imperative Shell。** 判断ロジックは純関数に寄せる。I/O は薄い外殻に押し出す。
- **Result / Either で Railway 化。** 例外を制御フローに使わない（Wlaschin）。`bind` / `map` で合成。
- **エラーは "ドメインの一部"。** 例外メッセージで「失敗の種類」を表現せず、`Error` を sum type にして compiler に網羅性を見させる。
- **副作用は "戻り値" として表す**（Reader / IO / Effect 風）。`async` 関数は I/O 境界の印として扱い、純関数からは排除する。

### Step 5 — テスト戦略 / TDD で設計圧をかける

`references/tdd.md` と `references/functional-core.md`（xUnit Test Patterns 部分）を当てる。詳細レビューは `test-review` skill が担当するが、設計フェーズで確認する範囲：

- **テストが書きにくいなら設計が間違っている。** Test Double が欲しい時点で Functional Core にできていない兆候。
- **red → green → refactor のリズム。** green を直接書かない。
- **集約 / ドメインプリミティブは Test Double 不要で直接テストできる構造にする。** これが取れない時、Step 3 の境界が間違っている。
- **テスト命名は仕様文。** `test_<method>` ではなく `<事実>_when_<条件>`。

### Step 6 — アーキテクチャレベルの選定

`references/architecture.md` を当てる。

- **アーキテクチャ特性（性能 / 可用性 / 進化容易性 / セキュリティ / コスト …）を 3 個まで明示的に選ぶ。** 全部は最適化できない（Richards & Ford 推奨）。
- **Architecture quantum** の単位で考える。境界をまたぐ依存があるかどうかで quantum が決まる。
- **CQRS を採用するときの判断基準**（read/write の非対称性 / 異なる UI 要件 / 異なる整合性要求）。「なんとなく」では入れない。
- **Event Sourcing を採用するときの判断基準**（監査 / 時系列再生 / "どうやってここに来たか" が業務価値）。CRUD が回るドメインに無理に入れない。
- **CQRS と Event Sourcing は独立**。混同しない。CQRS だけ・ES だけ・両方・どちらも無し、の 4 通り全部ありえる。

### Step 7 — セキュリティを後付けにしない

`references/security.md` を当てる。Secure by Design の中核は「**セキュリティはドメインモデルの中で表現する**」：

- **入力の妥当性をドメインプリミティブに閉じ込める。** API レイヤや middleware にバリデーションを書かない。
- **認可はドメイン操作の前提条件として表現。** 「権限がないと操作が呼べない」を型で表す（capability / 引数として権限を要求）。
- **機微データの暴露経路を型で塞ぐ。** `SensitiveString` のような型で `toString` / ログ出力を制御。
- **Fail securely。** 失敗時に open ではなく closed（権限デフォルト deny、ロックデフォルト lock）。

### Step 8 — 決定を ADR に残す

`references/adr.md`。Nygard 形式（Context · Decision · Consequences）を最低限とし、「考えたが採らなかった選択肢」を必ず一節置く。

ADR を書くタイミング：

- 「この設計はなぜ?」を 6 ヶ月後の自分が聞き返しそうな決定すべて
- 採用も却下も書く。**特に却下したものを書く**（誰もが踏みに来る道）。
- 1 ADR 1 決定。複数決定は分割。
- 既存決定を覆すときは新 ADR を書き、旧 ADR を `Superseded by ADR-NNN` に更新。書き換えない。

ADR の標準ファイル名: `docs/adr/NNNN-<kebab-title>.md`。

### Step 9 — レビュー

設計成果物（モデル / モジュール構造 / ADR）が固まったら、`design-review` skill を起動して別エージェントに白紙でレビューさせる。書き手バイアスを排除する目的で、`software-design` 自身でセルフレビューしない。

---

## 出力フォーマット

要請の種類に応じて、以下のいずれかで返す。

### A. 設計提案（モデル / モジュール / アーキテクチャ）

```markdown
# Design Proposal: <名称>

## 文脈 / 制約
<3〜5 行。何を解こうとしているか・既存制約>

## 適用したレンズ
- <レンズ名>: <そこから来た主張 1 行>
- ...

## モデル / モジュール
<図 or 構造化リスト。コード片は最小限。>

## トレードオフ
- 採用: <案> — 理由
- 不採用: <案> — 却下理由

## 次の検証
- <ADR を起こす項目>
- <PoC で確認する項目>
```

### B. 既存設計のレビュー指摘

```markdown
# Design Review (self)

## Summary
<判定: OK / changes requested / 要議論。主要懸念 ≤ 3>

## Critical (blocks merge)
- [path:line] [<lens-tag>]: <issue>
  - Fix: <提案>

## Major (should fix)
- ...

## Minor / Style
- ...

## Open Questions
- ...

## Strengths
- ...
```

`<lens-tag>` の例: `philosophy/deep-module`, `data/mutable-mix`, `tm/key`, `fp/exception-as-control`, `ddd/aggregate-boundary`, `tdd/untestable`, `rop/result-leak`, `arch/quantum`, `xunit/double-overuse`, `cqrs/asymmetry`, `es/state-loss`, `adr/missing`, `secure/primitive`。

### C. ADR 提案

`references/adr.md` のテンプレートに沿って 1 ファイル分のドラフトを返す。

---

## このスキルがやらないこと

- **テスト本体のレビュー。** `test-review` の担当。
- **新規ライブラリ / 先行事例の調査。** `research-practices` の担当。
- **Skill 自体の作成 / チューニング。** `skill-builder` の担当。
- **lint / formatter / 型エラー / タイポ修正。** ツールの仕事を奪わない。
- **設計と無関係な実装作業の代行。** 設計判断を含まない作業はこのスキルを起動しない。
- **レンズの記憶からの即答。** 必ず該当 `references/*.md` を読みに行く。
- **「正解」の押し付け。** トレードオフを 2 案以上提示し、決定は ADR で残す方向に倒す。

---

## 既知の限界

- 13 レンズ間の対立（例: DDD の集約境界と CQRS の read model 分割、TDD の green-first と Philosophy の strategic design）は本スキルでは "両論を並べる" までで止め、最終裁定はユーザに委ねる。自動裁定は過信を生む。
- Event Sourcing / CQRS は「使うべき場面」より「使うべきでない場面」のほうが多い。本スキルはデフォルトで採用に倒さない。
- ADR の質は本スキルが直接保証しない。`design-review` で別エージェントに当てさせる。
