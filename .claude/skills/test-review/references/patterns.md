# xUnit Test Patterns（正のパターン集）

Gerard Meszaros『xUnit Test Patterns』(2007) の中核パターンを、2026 年の Python / Strands Agents 文脈で再整理したもの。`smells.md` が「やってはいけない」を扱うのに対し、こちらは「こう書く」を扱う。

レビューでは、指摘するときに「どのパターンに合わせると良いか」を具体的に指し示すために使う。

---

## 1. Four-Phase Test（AAA / Given-When-Then）

テストの骨格。4 つのフェーズを視覚的に分離する：

| Phase | 目的 | 推奨 |
|---|---|---|
| **Setup (Arrange / Given)** | SUT と依存を用意する | factory fixture で boring な既定、意味ある値はインライン |
| **Exercise (Act / When)** | SUT の 1 つの振る舞いを呼ぶ | **1 行**に収める |
| **Verify (Assert / Then)** | 期待する観測可能な結果を確認 | 1 つの論理概念のみ |
| **Teardown** | 副作用を元に戻す | pytest の fixture `yield` で自動化 |

```python
def test_returns_unknown_when_no_indicators():
    # Setup
    words = ["hello", "world", "foo"]

    # Exercise
    result = _detect_language(words)

    # Verify
    assert result == "unknown"

    # Teardown: not needed (pure function)
```

空行で区切る。`# Setup` のようなフェーズコメントは必須ではない — 構造だけで意図が伝わるのが理想。ただし慣れていないチームメイトがいる段階や、Arrange が複数の論理段階に分かれる長いテストでは、コメントを付けても良い。

**Given-When-Then** は BDD 文脈で同じ構造の言い換え。どちらを使っても OK、チーム内で統一する。

---

## 2. Test Double — 使わなくて済む設計を先に作る

**大前提**: このプロジェクトでは **test double を使う必要が出ないように設計する**。test double が欲しくなる時点で、設計が正しくない可能性を先に疑う。立場は Classicist / Chicago school に、**Functional Core / Imperative Shell**（Gary Bernhardt）と **Humble Object**（Meszaros）を強く適用したもの。

順序はこう考える：

1. ロジックは **純関数** に閉じ込める。入力と出力が明らかで、副作用がない。→ test double 不要。
2. I/O は **ごく薄い外殻（Imperative Shell）**に押し出す。ここには意思決定ロジックを入れない。計算は Functional Core に委ねる配線だけ書く。→ 外殻は薄いので、test double を置くのではなく、統合テストで本物を動かす（testcontainers, 録画再生）で十分検証できる。
3. 外殻と Core の境界は **関数の引数 / コンストラクタ**で繋ぐ（依存注入）。→ テストは本物の Core を直接呼ぶだけ。

この順序で設計できていれば、test double は不要になる。test double を書きたくなったら、まず設計を戻して Functional Core に抽出できないかを考える。詳細は §6 Humble Object を参照。

### 本物を使う原則

- **DB は本物を使う。** Supabase / PostgreSQL は `testcontainers-python` や `supabase start` でローカル実行できるので、**プロセス外だがアクセス可能**なリソースとして本物を使う。`InMemoryRepo` を DB 代替に作るのは禁止 — それは RLS も SQL も検証しない別物の fake に過ぎない。
- **自分が所有するコードは test double にしない。** 内部クラスや内部関数を mock しているテストは、ほぼ必ず設計の問題のサイン。
- **Clock / UUID / 乱数** は Protocol 経由で決定的な実装を注入する（fake を書くのではなく、決定的な実装を本番 / テストで差し替える設計）。

### 外部 API はどう扱うか

Claude API や外部 Web サービス（Gmail, X, Discord の実 API）は、テスト実行時にプロセス内で動かせないため、唯一の「テストが本物を動かせない」境界。ここでも test double を書くのは最後の手段：

1. **第一に、境界を Humble Object 化して Functional Core を可能な限り大きくする。** パース、プロンプト合成、ルーティング、バリデーション — I/O 呼び出しの前後ほぼ全てを純関数に寄せる。それらは本物の入出力データ（録画された JSON）を使って直接テストする。
2. **I/O を実際に跨ぐ部分は VCR 録画で統合テストする。** `vcrpy` / `respx` で本物のレスポンスを一度録画し再生する。これは「hand-written test double」ではなく「本物の振る舞いのスナップショット」。サニタイズ hook で PII / API キーを必ず除去する。
3. **どうしても録画が無理な場面**（ストリーミング、認証フロー等）だけ、境界アダプタに薄い Fake を 1 枚置く。**実装は 50 行以下**を目標。これが必要になった時点で、そもそも Functional Core への抽出が足りていないかを再検討する。

### 意思決定フロー

```text
  │
  ├─ test double が欲しくなった?
  │     └─→ STOP。まず純関数抽出 / Humble Object 化で不要にならないか検討 (→ §6)
  │
  ├─ 自分が所有するコード? ──────── YES ─→ 本物を使う。double しない
  │
  ├─ DB / Supabase / pgvector ? ── YES ─→ testcontainers / supabase-cli で本物
  │
  ├─ Clock / UUID / random ? ───── YES ─→ Protocol 注入 + 決定的実装
  │
  ├─ LLM / 外部 Web API ? ──────── YES ─→ (a) まず境界を薄くして Functional Core を本物でテスト
  │                                         (b) 残る I/O 部分は VCR 録画
  │                                         (c) それも無理なら、境界に薄い Fake 1 枚
  │
  └─ その他 ──────────────────→ そもそも seam が間違っている。設計を戻す
```

### なぜこの順序か

- **Maintainability**: test double は実装結合。リファクタで壊れる。本物で組めば「何が動いているか」が常に明示される。
- **Resistance to refactoring**: 内部メソッドのリネーム / 分割で test double が壊れるのは避けられる損失。
- **Protection against regressions**: 本物の DB・本物のクエリ・本物の RLS が走っていないテストは、契約を検証しているとは言いがたい。Supabase の RLS は SQL で書かれているので、SQL を実行しないテストでは何も保証できない。
- **AI 生成テストの暴走抑制**: LLM が書くテストは自然に mock を多用する傾向がある。「使わなくて済む設計を先に」を既定ドクトリンにすると、`ai-generated.md #2 Mock-everything` 型のドリフトが構造的に起きにくくなる。

### 従来のタクソノミ（参考情報、原則使わない）

Meszaros の 5 分類は概念整理としてのみ残す。本プロジェクトで **Stub / Spy / Mock は使わない**。

| 種類 | このプロジェクトでの扱い |
|---|---|
| **Dummy** | 型を満たすだけの `object()` 等。技術的に必要ならあり |
| **Stub** | 使わない。値を制御したくなったら設計を見直す |
| **Fake** | プロセス内実行不可能な I/O 境界（LLM, 外部 Web API）で録画が困難なときに限って、薄い 1 枚だけ。`InMemoryRepo` は作らない |
| **Spy** | 使わない。呼び出しを観測したいなら OTel span を本番ごと出して、それを assert する |
| **Mock** | 使わない。Mock が欲しいテストは分解して書き直す |

### アンチパターンとの接続

- Test double を既定で使う → `smells.md #18 Over-mocking`
- 内部コラボレータを mock → `smells.md #3 Fragile test`、`ai-generated.md #2 Mock-everything`
- Mock の呼び出し順を縛る → `ai-generated.md #6 呼び出し順に過剰適合した assertion`
- DB を in-memory fake に差し替える → 本ドクトリン違反。本物の Postgres + RLS で回す
- 「このコードはテストが難しい」と思ったら mock を書く → 違う。**純関数として抽出できないか**を先に考える（§6 Humble Object）

### London school vs Classical school（立場の補足）

上記は Classical school（Detroit school）の立場を Functional Core / Imperative Shell まで押し進めたもの。**London school（mockist）** は逆の主張をする — SUT の直近のコラボレータを全て test double に置き換え、コラボレータとの対話（どのメソッドをどう呼ぶか）そのものを仕様として固定する。outside-in（受け入れテストから内側へ設計を導出する）や、協調そのものを先に決めてから実装するスタイルと相性が良い。

トレードオフ：

| 観点 | Classical | London |
|---|---|---|
| Resistance to refactoring | 高い（内部構造を変えても壊れない） | 低い（コラボレータの呼び出し方を変えると壊れる） |
| 設計への影響力 | 事後的（実装してからテストで検証） | 事前的（interaction を先に決めて実装を導出） |
| 向く場面 | 計算ロジック・ドメインロジック | 未確定の協調設計、outside-in TDD の駆動 |

本 reference は Classical を既定として書いているが、これは「常に正しい」という意味ではない。outside-in で協調そのものを設計したい局面では London の主張にも一理ある。レビューでは、その PR がどちらの立場を取っているかを先に見極め、立場そのものではなく「その立場の中で一貫しているか」を問う。ただしこの補足は、プロジェクト自身が反 mock ドクトリンを明示している場合（`smells.md #18 Over-mocking` の既定ドクトリン）を上書きしない — その場合はドクトリンが優先で、London 採用はドクトリン側の変更として扱う。

---

## 3. Fixture 戦略

フィクスチャ（SUT と依存のセットアップ）の配布方法：

| パターン | 説明 | 適用 |
|---|---|---|
| **Inline Setup** | テスト本体の中で全部組む | 小規模・読みやすさ重視 |
| **Delegated Setup** | factory fixture に組み立てを委譲 | 中規模。overrides でテスト内の意味ある値を明示 |
| **Implicit Setup** | `autouse=True` や base class で暗黙に組む | 副作用リセット・時刻固定など、**全テスト共通の前提**にのみ |
| **Fresh Fixture** | テストごとに新規生成（既定） | 順序独立性が必要 |
| **Shared Fixture** | session / module scope で 1 回だけ | testcontainers, 大きなモデルロードなど I/O 重コスト |
| **Persistent Shared Fixture** | テスト実行を跨いで状態を使い回す（マイグレーション済み DB スキーマ、外部環境の常設シードデータ等） | 再構築コストが極めて高いときの最終手段。Shared Fixture よりさらに寿命が長い分、汚染リスクも大きい。Meszaros の **Persistent Fresh Fixture**（物理的に残るが再利用はしない、明示 teardown 必須）とは別物 |
| **Lazy Setup** | 使われるときに初めて組む | 条件分岐で必要な依存だけ準備 |

**推奨デフォルト**：Delegated Setup（factory fixture）+ Fresh Fixture。Implicit / Shared / Persistent は例外扱いで、理由をコメントに残す。

### 関連 smell

- Implicit Setup を多用 → `smells.md #4 Obscure test`
- Shared Fixture の汚染 → `smells.md #14 Erratic (flaky)`
- Persistent Shared Fixture の後始末漏れ → **Interacting Tests**（あるテストが残した状態に別のテストが暗黙に依存する）。DB スキーマのような高コスト fixture ほど「毎回作り直さない」誘惑が強いが、各テストは自分が使うデータをテスト内で明示し、他テストの実行順や残留状態に依存していないことを確認する。`smells.md #14 Erratic (flaky)` に分類。

---

## 4. テストデータ構築

テストデータをどう組み立てるか。ハードコード / グローバル fixture を避けるためのパターン群：

### Creation Method（生成メソッド）

ドメイン型の構築ロジックをテストヘルパにまとめる：

```python
def _make_summary(**overrides) -> PageSummary:
    defaults = {"url": "https://x", "title": "t", "description": "d",
                "word_count": 1, "language": "en"}
    return PageSummary(**{**defaults, **overrides})
```

### Factory Fixture（pytest 流）

Creation Method を fixture 化：

```python
@pytest.fixture
def make_summary():
    def _make(**overrides):
        defaults = {...}
        return PageSummary(**{**defaults, **overrides})
    return _make
```

### Object Mother

意味のあるプリセットに名前を付けてまとめる：

```python
class Summaries:
    @staticmethod
    def english_short() -> PageSummary: ...
    @staticmethod
    def japanese_long() -> PageSummary: ...
    @staticmethod
    def unknown_language_empty() -> PageSummary: ...
```

**適用**：同じ「種類」のオブジェクトが複数テストで使われ、**名前を付ける価値がある**とき。過剰に作ると Mystery Guest 化するので注意。

### Test Data Builder（流暢ビルダー）

構築を宣言的に：

```python
(SummaryBuilder()
    .url("https://x").title("t").words(["hello", "world"])
    .language("en")
    .build())
```

Python では `@dataclass` + `dataclasses.replace` や `polyfactory` が同じ役割をカバーする。

### 選び方

| シナリオ | パターン |
|---|---|
| 使用箇所 1〜2 | Inline / Creation Method |
| 中規模・overrides 必要 | Factory Fixture |
| 典型プリセットに意味がある | Object Mother |
| 組立の組み合わせが爆発 | Test Data Builder / polyfactory |

---

## 5. 結果検証 — 原則 State Verification

このプロジェクトでは assertion は **原則すべて State Verification**。それ以外の検証技法は基本的に不要。素朴な `assert actual == expected` が第一選択で、迷ったらこれに戻す。

### 既定: State Verification

SUT の戻り値、保持された状態、外界の観測可能な出力を直接比較する：

```python
result = summarize(url, llm)
assert result == PageSummary(url=..., title=..., language="en", word_count=42)
```

「何になったか」をストレートに表現する。レビュー時もこの形が既定で、他の形が出てきたら「なぜこの形でないのか」を問う。

### Behavior Verification は使わない

「どのメソッドが何回・どの引数で呼ばれたか」を assert するのは、このプロジェクトでは原則行わない。理由：

- 内部メソッドの呼び出しは public 契約ではない。リファクタで壊れる（`smells.md #3 Fragile test`、`ai-generated.md #6 呼び出し順に過剰適合した assertion`）。
- §2 で述べた通り **Mock / Spy を使わない方針**なので、Behavior Verification の道具そのものが存在しない設計になっている。つまり「この方針だと無理なく書ける」ではなく「この方針なら書けようがない」。

### 外部への副作用も State Verification として書く

「Supabase に行が INSERT された」「OTel span が emit された」のような外界への副作用は、Behavior Verification ではなく、**その外界の状態を読みに行く State Verification** として表現する：

- DB 書き込み → 書き込み後に `SELECT` してその行を assert。
- OTel span → in-memory exporter からスパン一覧を読み、属性を assert。
- Discord メッセージ → テスト用 webhook receiver（httpbin 等）の受信記録を assert。

こう書くと、実装が中でどの関数を何回呼んだかは問わず、**最終的にどの状態になったか**だけを検証する。内部構造を変えるリファクタで壊れない。

### 既存の assertion バリアント（参考、覚えなくて良い）

Meszaros が別名を与えているものはあるが、実態はほぼ全て State Verification の具体形。ほぼ常に `assert actual == expected` で事足りるので、名前を使い分ける必要はない：

| 名前 | 実態 |
|---|---|
| Expected Object | オブジェクト全体で比較する State Verification |
| Expected State | 一部のフィールドだけ比較する State Verification |
| Custom Assertion | ドメイン用語で薄く包んだ State Verification（同じ assert が 5+ 箇所で再利用されるときだけ抽出を検討） |
| Guard Assertion | 前提条件の State を先に確認するだけ |
| Delta Assertion | before/after の差分を State で比較する |

分類を覚える労力は不要。迷ったら `assert actual == expected` に戻す。

---

## 6. テスト容易性のリファクタ

テストしにくいコードをテスト可能にするパターン。レビュー時に「このコードがテストしにくいのは設計の問題」と指摘する際に使う：

### Humble Object

非決定的・外部依存のある部分を**薄く**して、ロジックを純関数に分離する：

```python
# Before: LLM 呼び出しとパースが絡まっている
async def summarize(url: str) -> PageSummary:
    html = await fetch(url)
    response = await claude.messages.create(...)  # 非決定
    parsed = json.loads(response.content[0].text)
    return PageSummary(**parsed)

# After: Humble Object 化
async def summarize(url: str, llm: LLMClient) -> PageSummary:
    html = await fetch(url)
    raw = await llm.complete(build_prompt(html))  # 薄い境界
    return parse_summary_response(raw)  # 純関数、テスト容易

# parse_summary_response, build_prompt を個別に unit test
```

`SKILL.md §4` の seam 設計の具体化。

### Dependency Injection

コラボレータを **引数 / コンストラクタ**で受け取る：

```python
# Bad: モジュール直呼び
def run():
    client = anthropic.Anthropic()  # テストから置換不能
    ...

# Good: 注入
def run(client: LLMClient):
    ...
```

Protocol 型で受ければダックタイプで Fake を差し込める。

### Test Hook

本番でも無害な形で、テスト時に観測点を用意する。**`smells.md #11 For testers only` と紙一重**：

- OK: 構造化ログや OTel span として外に出す（本番でも使う）
- NG: `if os.getenv("PYTEST"): ...` のような条件分岐

### Test Double Installation

テストから DI 点に Fake を渡せるよう、production コードの入口（factory / entrypoint）を明示的に設計する：

```python
def create_agent(*, llm: LLMClient | None = None) -> Agent:
    llm = llm or default_llm_client()
    ...
```

`example_agent.create_agent(model=...)` が既にこの形。

---

## 7. Test Organization — テストをどう束ねるか

テストが増えるにつれ、「どの粒度でファイル/クラスを分けるか」が可読性を左右する。Meszaros は束ね方を 3 通り区別する：

| パターン | 束ね方 | 適用 |
|---|---|---|
| **Testcase Class per Fixture** | 同じ setup を共有するテストを 1 クラス/ファイルにまとめる | fixture 再利用が主目的。setup 変更の影響範囲が明確になる |
| **Testcase Class per Feature** | 1 つの振る舞い・ユースケース単位でまとめる（`describe("checkout flow")` 等） | BDD 寄り。仕様書として読めることを優先 |
| **Testcase Class per Class** | 1 プロダクションクラス/モジュールに 1 テストクラス（`TestFoo` ↔ `Foo`） | デフォルトで迷ったらこれ。SUT との対応が探しやすい |

3 つは排他ではなく、小さいモジュールは per Class、複雑なユースケースは per Feature に寄せるといった混在も可。ただし 1 ファイル内で方針を混在させると Obscure test（`smells.md #4`）を招くので、ファイル単位では 1 つの方針に揃える。

**Test Utility Method**（複数テストで使う assertion / 構築ヘルパ、§4 Creation Method 等）の配置の目安：

- 1 クラス内でしか使わない → そのクラス内のプライベートヘルパ
- 同じ fixture を共有する複数クラスで使う → per-Fixture の基底クラス / shared module
- プロジェクト全体で使う（カスタム assertion 等） → `conftest.py` 相当の共通ユーティリティモジュール

置き場所が実際に使うテストから遠すぎると Mystery guest（`smells.md #2`）になるため、距離を意識する。

---

## レビューで引用するときの書式

レビューコメントに本ファイルを参照するとき、どのパターンを推奨しているか明示する：

```text
[seam]: ここは Humble Object 化できる。parse_response を純関数に切り出して
unit-test し、LLM 呼び出しは Protocol 経由にする。
→ 詳細は references/patterns.md §6 Humble Object。
```

パターン名で指すことで、著者が同じ語彙で応答できる。
