---
name: test-review
description: >-
  テストコード（pytest / vitest / jest / rspec / go test / pgTAP / ワークフロー定義
  等の任意フレームワーク）をレビューする際に使うスキル。test smells（Meszaros 17 種）、Khorikov の 4 属性
  (Protection / Resistance to refactoring / Fast feedback / Maintainability)、AI
  生成テストのアンチパターン、seam / mock 境界の違反、LLM・エージェント eval の抜け、DB / RLS /
  認可テストのカバー、flakiness の原因分類をまとめて点検する。テストファイル（`**/tests/**`, `*_test.*`,
  `*.test.*`, `*.spec.*`, `supabase/tests/**` など）を含む PR / diff
  のレビュー時、新規テストファイルの監査時、テストスイートの品質チェック時、flaky テストの原因追跡時、LLM / エージェント eval
  の厳密性評価時、RLS / 認可テストの存在確認時、いずれでも必ず起動すること。ユーザーの言い方が曖昧でも —
  「テスト見て」「このテストいい?」「テストスイート大丈夫?」「このテストなんで壊れる?」「認可のテスト足りてる?」「eval
  レビューして」「このプロンプトテストでカバーできてる?」—
  どれも該当する。ただし以下の成果物を生む依頼はこのスキルの範囲外：テスト追加・テスト修正・テスト基盤の移行・テスト並列化・パフォーマンス改善・lint
  違反修正。本スキルは「読んで指摘する」レビュー専用で、コードを書き換える依頼には起動しない。アドホックなレビューより本スキルを優先する理由は、構造化されたチェックリスト（Meszaros
  / Khorikov / AI antipatterns）を一貫適用して findings を出すためである。
---
# Test Review

テストを書くのが速く、レビューするのが安いままであるようにテストコードをレビューするためのスキル。テスト品質は予測可能な形で劣化するので、その劣化を一度・一貫して捕まえることで、以降の PR で時間を節約できる。

rulesync で `kanade0404/skills@<tag>` から `skills/test-review/` として配布される前提で project-agnostic に書く。consumer プロジェクトに固有の doctrine (例: Safety / Order / Reinforcement のような独自原則) があれば §Step 7 で取り込む拡張点を持たせている。

レビューの主レンズ:

- **Khorikov の 4 属性** — Protection against regressions · Resistance to refactoring · Fast feedback · Maintainability。掛け算的に効く。どれか 1 軸でもゼロに近づくとテストの価値のほとんどが失われる。
- **Meszaros の 17 smells** — `references/smells.md` の完全カタログを §Step 3 で当てる。
- **AI 生成テストのアンチパターン** — `references/ai-generated.md` に詳細。LLM が書いたテストに偏った 6 種を §Step 5 で常時チェック。
- **consumer プロジェクトの doctrine マッピング**（任意）— §Step 7。プロジェクトに独自の原則（Safety / Order / Reinforcement, Reliability / Observability / Idempotence 等）があれば、非自明なテストをそれに対応付ける。

---

## ワークフロー

以下の順で進め、信号が明確ならその時点で短絡する。全ファイルに全ステップを当てる必要はない。

### Step 1 — スコープ分類

変更されたテストを読み、ファイルごとに分類する。下表は consumer プロジェクトで頻出するレイヤの**例**。consumer の技術スタックに応じて読み替える。

| 信号（例） | レイヤ | 主要な関心事 |
|---|---|---|
| `pytest`, `vitest`, `jest`, `rspec`, `go test` などの単体テスト | unit | §3, §4, §5 |
| `respx`, `msw`, `testcontainers`, `supertest`, `httptest` 等 + DB / 外部 API | integration | §3, §4, §5, §8 |
| `anthropic` / `openai` SDK, agent loop, tool use, prompt eval | LLM / agent | §3, §4, §5, §7, §8 |
| `pgTAP`, RLS テスト, supabase test helpers | DB / 認可 | §8 |
| ワークフロー定義 (`workflow.json`, n8n, Temporal 等) | workflow | §8 |
| ブラウザ E2E (Playwright, Cypress) | E2E | §9 |

レイヤ固有の詳細は **必要になったときのみ** 参照する。本カタログは以下の汎用 reference を同梱する。consumer プロジェクトは独自の `references/<stack>.md` を追加して拡張できる:

- `references/patterns.md` — xUnit Test Patterns の正のパターン（Four-Phase Test, Test Double タクソノミ, Fixture 戦略, テストデータ構築, 結果検証, Humble Object 等。言語非依存）
- `references/smells.md` — Meszaros 17 smells の完全版、修正例つき（言語非依存）
- `references/ai-generated.md` — AI 生成テスト特有のアンチパターンと検出ヒューリスティック（言語非依存）
- `references/python.md` — pytest / Hypothesis / async / fixture の具体（**Python 例**。他言語の consumer は無視）
- `references/llm-eval.md` — LLM / エージェント eval の具体（汎用）
- `references/data-stack.md` — Supabase / RLS / pgvector / n8n の具体（**特定スタック例**。consumer のスタックに応じて参照）

これらは参考資料であり、事前に読む必要はない。対象ファイルが要求するときだけ読む。

### Step 2 — 構造チェック（全テストに適用）

ここで落ちるテストは、どれだけ内容が正しくても読みにくい。

- **テスト名は要件文。** 振る舞いが名前から読めること。class で整理している場合は class 名を文脈として扱って良い（例: `TestPageSummary.test_construction` は class 名と合わせて「PageSummary の construction を検証」と読めるので OK）。class のない関数スタイルでは `test_<behavior>_when_<condition>`（例: `test_returns_unknown_when_no_indicators`）を推奨。却下: `test_fn_1`, `test_works`, `test_internal_helper` のように振る舞いが読めないもの。
- **AAA / Given-When-Then** が空行で視覚的に分離されている。
- **Act は 1 行。** 複数行にわたるなら複数の振る舞いを検証している兆候 — 分割する。
- **1 テスト 1 概念。** 同じ概念を確認する複数の物理 `assert` は OK（返り値の各フィールドなど）。
- **Assertion は原則 State Verification。** 戻り値・保持された状態・外界の観測可能な出力（DB の行、OTel span の属性、webhook 受信記録）を直接比較する。呼び出し回数や呼び出し順の assertion は使わない — §4 で test double を使わない設計により、そもそも道具が存在しない。詳細は `references/patterns.md §5`。
- **テスト本体に「どのアサートが走るか」を分岐させる制御構造を置かない。** `if`/`try`/`while`/`for` でアサートの実行可否が変わるものは却下し、parametrize 機能（`@pytest.mark.parametrize`, `it.each`, `describe.each`, `RSpec.shared_examples` 等）に展開する。ただし **property-based テストの precondition フィルタ** は正当な例外 — Hypothesis の `assume(cond)`、fast-check の `fc.pre(cond)` などが慣用形。
- **マーカー / タグの整合。** `@pytest.mark.<foo>` / `describe.skip` / `RSpec.tag` 等を使う場合、フレームワークの設定（`pyproject.toml` `markers` リスト、jest config 等）に宣言されていること。`--strict-markers` 相当の検査が CI で動いているなら、未宣言マーカーは即エラーになる。新規マーカー追加時は同じ PR で設定に登録する。
- **Reader test。** 実装を知らない読み手がテストだけを読んで契約を言えるか。言えないなら、書き手都合のテストになっている。

### Step 3 — Test smells スキャン

17 項目カタログ（Meszaros。定義・例・severity・修正は `references/smells.md`）を当てる：

Eager test · Mystery guest · Fragile test · Obscure test · Assertion roulette · Conditional test logic · Test code duplication · Resource optimism · Indirect testing · Sensitive equality · For testers only · The free ride · Silent catcher · Erratic (flaky) · Slow test · Guarded assertion · Lonely assertion.

境界値・同値クラス・状態遷移のケース欠落（`coverage-gap`）に気づいた場合は、本ステップでは smell として指摘するに留め、テストケースの設計そのものは `test-design` スキルに委ねる。

### Step 4 — seam / 外部 I/O 境界

**立場**: **test double を使う必要が出ないように設計する**ことを優先するレビューを行う。test double が欲しくなる時点で、設計が正しくない可能性を先に疑う。Classicist に Functional Core / Imperative Shell と Humble Object を強く適用した立場。詳細は `references/patterns.md §2` と `§6 Humble Object`。

レビューで当てる順序：

- **「test double が必要」と主張するテストは設計を疑う。** 先に純関数として抽出できないかを問う。パース、バリデーション、プロンプト合成、ルーティング、判断ロジックはほぼ全て純関数に寄せられる — そうすれば test double なしで直接テストできる。
- **本物優先。** 自分が所有するコードは test double にしない。内部クラスや内部関数を mock しているテストは、ほぼ必ず設計の問題のサインなので指摘する。
- **DB は本物を使う。** PostgreSQL / MySQL / SQLite などは Testcontainers (testcontainers-python / testcontainers-node / testcontainers-java など) や docker-compose, ローカル CLI (例: `supabase start`) でローカル実行できるので、本物で検証する。`InMemoryRepo` 等の DB fake は作らない。RLS や stored procedure のように SQL に書かれた制約は、SQL を実行しないテストでは何も検証されない。
- **外部 API（LLM 提供者 / 通知先 / メーラー / OAuth プロバイダ等）の扱いも "まず Humble Object 化"**。I/O を薄い外殻に押し出し、周辺の Functional Core は本物のデータ（録画された JSON 等）で直接テストする。**残る薄い I/O 部分だけ** VCR 録画系ツール（vcrpy / nock / WireMock / Polly.JS / respx / msw など、言語に応じて）で統合テストする。録画時は **サニタイズ hook で PII / API キー除去** を必須にする。録画が難しい場合のみ境界アダプタに薄い Fake を 1 枚、50 行以下で置く。
- **Clock / UUID / 乱数** はインタフェース（Python Protocol / TypeScript interface / Go interface 等）で DI する（fake を書くのではなく、決定的な実装を本番 / テストで差し替える設計）。
- **monkey-patch のターゲットは使用箇所、定義元ではない。** Python `unittest.mock.patch` / Jest `jest.mock` / Sinon stub 等、どの言語でも同じ原則。良: `patch("<own_module>.<imported_name>")`、悪: `patch("<vendor_lib>.<name>")`。Functional Core と I/O 境界が分離しきれていないコードでは使用箇所 patch を暫定的に許容するが、境界が明確化されれば patch 自体が不要になる方向で設計を進める（外部 I/O は `LLMClient` / `HttpFetcher` 相当のアダプタを 1 枚挟むのが理想）。
- **純関数は直接テストする。** parser / validator / prompt composer / routing は test double 不要。
- **flaky retry プラグインで flaky を隠さない。** `pytest-rerunfailures`, `jest --retry`, `mocha --retries` 等。flaky が現れたら §6 で分類する。

### Step 5 — AI 生成テストのアンチパターン

LLM が書いたテストは特定の失敗パターンに偏る。完全な一覧は `references/ai-generated.md`。常にチェックするコア 6 件：

1. **Self-consistent assertion** — `expected` を実装自身から得て、実装が壊れていてもテストが通る。
2. **Mock-everything** — コラボレータを全部モックし、実質制御フローしか検証していない。
3. **Oracle copy-paste** — テストがアルゴリズムを再実装しており、独立した oracle になっていない。
4. **Expected/actual 入れ違い** または **真偽反転**（仕様が「X である」なのに `assert not X`）。
5. **意味不明な magic number** — `42`, `"foo"`, `3` が定数化も根拠コメントもなく使われている。
6. **実装の呼び出し順に過剰適合した assertion** — public 契約に属さない内部呼び出し順序を縛っている。

**一次ヒューリスティック**: 実装に現実的な mutation（`>` を `>=` に反転、分岐を 1 つ削除、古いキャッシュを返す等）を加えてもテストが通ってしまうなら、そのテストは装飾品。

### Step 6 — flakiness の原因分類

「たまに落ちる」や retry プラグイン（`pytest-rerunfailures` / `jest --retry` / `mocha --retries` 等）が diff に出たら、原因分類を要求する。retry-to-green は認めない。

| 原因 | 対策（言語に応じた具体ツール） |
|---|---|
| 非同期レース | timeout 明示 + 決定的スケジューリング (Python `asyncio.timeout`, JS `Promise.race + AbortController`, Go `context.WithTimeout`) |
| ネットワーク | MSW / nock / VCR / vcrpy / WireMock / Testcontainers で固定化 |
| 順序依存 | 共有可変状態を排除。テスト順序ランダム化（`pytest-randomly`, `jest --randomize`）で検出 |
| Clock | 注入可能な Clock インタフェース。`time-machine` / `@sinonjs/fake-timers` / `clock-mock` などで決定化（`freezegun` の monkey-patch 系より DI 推奨） |
| 乱数 | seed 注入（`random.Random(seed)` / `seedrandom` / Go `rand.New(rand.NewSource(seed))`） |
| 環境変数 | テスト用の差し替え API のみ使用（Python `monkeypatch.setenv`, Node `process.env` を fixture で復元、Go `t.Setenv`） |
| リソースリーク | リーク検出 fixture / hook（Python `asyncio.all_tasks()`, Jest `--detectOpenHandles`, Node `--detect-leaks`） |

調査中の隔離（`@pytest.mark.skip` / `it.skip` 等で issue 番号付き）は OK。リトライで誤魔化すのは NG。

### Step 7 — consumer プロジェクトの doctrine マッピング（任意）

consumer プロジェクトに **テストが守るべき独自原則** が明文化されているなら、非自明なテストはそのいずれかに明確に対応付けることを要求する。

このセクションは **consumer 側に doctrine がある場合のみ有効**。無い場合はスキップしてよい。doctrine の典型例:

- **Safety / Order / Reinforcement** — エージェント・データ系のプロダクトでよく置かれる 3 原則
  - Safety: RLS 否定系、prompt injection red team、ツール出力の data exfil フィルタ、PII 編集、policy violation の refusal
  - Order: 書き込みの冪等性、エージェントループの停止条件（iter / token / cost 上限）、OTel span 属性の assertion、単調な状態遷移
  - Reinforcement: golden dataset への新規ケース追加、trace replay 回帰、prompt version bump と同時の eval 更新、dataset バージョニング
- **Reliability / Observability / Recoverability** — 分散システム・SaaS 寄りで置かれることが多い
- **Correctness / Performance / Compatibility** — ライブラリ・SDK で置かれることが多い

Google の Test Sizes（Small / Medium / Large）分類を doctrine として採用している consumer もある。Size は Step 1 のレイヤ（scope）とは別の軸 — プロセス/スレッド数、sleep・ネットワーク・ディスク I/O の有無などの **リソース制約** で決まるため、レイヤから自動導出しない（例: レイヤが unit でも sleep やディスク I/O があれば small ではない）。既定では Step 1 の分類は変えず、この制約を実際に満たすかを別途確認したうえで `doctrine/small` のような doctrine タグとして追加マッピングする。満たさない場合はレイヤはそのままに、size 違反として指摘する。

consumer プロジェクトは `references/project-doctrine.md` を追加してここに自分の doctrine を書ける（本スキルは無くても動く）。

doctrine マッピングを **要求するレベル**:

- 些末なヘルパのテスト → マッピング不要
- ビジネスロジック / セキュリティ境界 / データ整合性 / エージェント挙動 → どれかに必ず対応するはず。対応しない場合は、テストが違う場所にあるか、そもそも検証対象がここで検証する価値を持たない疑い

### Step 8 — レイヤ固有の深掘り

対象ファイルがそのレイヤにあるときだけ参照する：

- LLM / エージェントコード → `references/llm-eval.md`（汎用）
- Supabase / RLS / pgvector / n8n のような特定スタック → `references/data-stack.md`（**特定スタック例**。consumer のスタックが異なる場合、独自の `references/<stack>.md` を追加して使う）
- Python 具体（fixture scope, asyncio 癖, Hypothesis チューニング）→ `references/python.md`（**Python 例**）

consumer プロジェクトが他言語・他スタック（TypeScript / Go / Ruby / Rust 等）であれば、本カタログの上記 references を参考に独自の `references/<lang>.md` / `references/<stack>.md` を追加できる。本スキルは追加 references を `references/` 配下に置けば自動的に Step 8 から参照される設計。

### Step 9 — E2E 予算の確認

E2E テスト（Playwright / Cypress / Selenium / 手動シナリオ自動化）を diff が追加している場合：

- より安いレイヤ（unit / integration / contract test）で既にカバーされていないかを確認する。
- 予算の目安（consumer プロジェクトの基準があればそれに従う）: CI 全体 10 分以下、flaky 率 < 1%。
- できる限りテストピラミッドの下側に寄せる（unit → integration → E2E の順）。
- E2E は golden path と critical safety path に限定する。E2E でしか検証できない振る舞いだけを残す。

---

## 出力フォーマット

レビューは以下の固定構造で 1 本の文書として出力する。30 秒でスキャンできることが目的：

```markdown
# Test Review

## Summary
<1〜2 文。判定: merge OK / changes requested / 要議論。主要な懸念を最大 3 つ挙げる。>

## Critical (blocks merge)
- [path/to/file:line] [category]: <issue>
  - Fix: <具体的な提案>

## Major (should fix)
- [path/to/file:line] [category]: <issue>
  - Fix: <具体的な提案>

## Minor / Style
- ...

## Questions for author
- ...

## What's good (keep doing)
- ...
```

カテゴリタグ（必ず角括弧つきで明示）: `smell/<name>`, `seam`, `ai-pattern`, `flaky`, `naming`, `coverage-gap`, `lang-specific`, `eval`, `e2e-budget`, `auth`, `rls`, `doctrine/<name>`。`doctrine/safety`, `doctrine/order`, `doctrine/reinforcement` のように consumer プロジェクトの doctrine 名を `/` で繋いで使う（doctrine マッピングを採用している場合）。

各項目は「issue 1 行 + Fix 1 行」。長めの理由は末尾の **Notes** 付録に脚注番号で参照させ、本文はスキャンしやすく保つ。

見つからない場合は素直にそう書く：*「今回のレビュー範囲では問題なし。テストは謳っている振る舞いをカバーし、seam の規律も守られている」*。findings を捏造しない。

---

## このスキルがやらないこと

- **テストを実行しない。** 著者がローカルでテスト・lint・型チェック（pytest / vitest / jest / rspec / go test, ruff / eslint / rubocop / golangci-lint, pyright / tsc 等）を回している前提。レビューは読むだけ。
- **コードを書き換えない。** 提案はテキスト。編集は著者 or 別ステップ。
- **ツールが強制しているスタイルは二度検証しない。** lint / formatter / 型チェッカがスタイルの権威 — 重複しない。テスト固有のスタイル（命名、smell）のみ指摘する。
- **CI と重複しない。** CI が enforce している項目は手動で再検証しない。

---

## 良いレビューの例

以下は Python + Supabase + LLM スタックでの具体例。本スキルは任意の言語・スタックで同じ構造のレビューを出力する。

```markdown
# Test Review

## Summary
Changes requested。3 点: (1) `test_agent_run` が Anthropic SDK を直接モックしており、プロジェクトのアダプタ経由でない、(2) 新 `/messages` エンドポイントの RLS 否定系ケースなし、(3) `test_parser_handles_input` が self-consistent assertion（expected = `parse(input)`）。

## Critical (blocks merge)
- [packages/chat-agent/tests/test_run.py:42] [seam]: `anthropic.Anthropic` を直接モック。ベンダ SDK の形状に結合する。
  - Fix: `chat_agent/ports.py` に `LLMClient` Protocol を追加し、それを patch する。既存アダプタは残す。`example_agent` と同じパターンで。
- [supabase/tests/messages.sql:12] [rls]: 正例のみ。他ユーザの行が見える可能性があるが否定 `SELECT` が無い。
  - Fix: `tests.authenticate_as('authenticated', me)` 配下で `results_eq(...)` が `WHERE messages.user_id = other_user` に対して 0 行を返すことを assert。

## Major (should fix)
- [packages/chat-agent/tests/test_parser.py:8] [ai-pattern]: `expected = parse(raw_input)` — self-consistent。
  - Fix: 仕様から expected を手で組むか、`tests/fixtures/parser/*.json` に golden pair を置いて parametrize。

## Minor / Style
- [packages/chat-agent/tests/test_run.py:3] [naming]: `test_it_works` → `test_returns_summary_when_url_is_reachable`。

## Questions for author
- `ChatAgent.run` に per-invocation のコスト上限はある? assertion されている?

## What's good (keep doing)
- `detect_language` の Hypothesis property はよく効いている。`example_agent` 先例を踏襲。
- fixture は boring で形状どおりに命名されており、mystery guest がない。
```
