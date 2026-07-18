# Python テストレビュー (pytest 8 / Hypothesis 6 / asyncio)

このリポジトリの Python テスト固有のレビュー観点。プロジェクトは既に ruff / pyright (strict) / pytest を CI で回しており、`pyproject.toml` で `--strict-markers`、`--strict-config`、`filterwarnings=error`、`asyncio_mode=auto` が有効。ここではツールが捕まえられない部分に集中する。

---

## fixture の scope と局所性

- 既定は `function`。`session` / `module` 等の広い scope は、testcontainers やモデルロード等の「高コストで read-only」なリソースだけに使う。
- autouse は以下に限定することを推奨: (a) 時刻 pinning、(b) 環境変数リセット、(c) task leak 検出。
- **factory fixture** > データ fixture。overrides を受け取る callable を返し、意味のある値はテスト内で明示する：

  ```python
  @pytest.fixture
  def make_summary():
      def _make(**overrides):
          defaults = {"url": "https://x", "title": "t", "description": "d",
                      "word_count": 1, "language": "en"}
          return PageSummary(**{**defaults, **overrides})
      return _make
  ```

- `conftest.py` はそれを使うテストの近くに置く。スコープを必要最小限に保つ。

## `patch` のターゲット

**使用箇所** を patch する（定義元ではない）。

```python
# Good — example_agent/tests の既存規約
with patch("example_agent.agent.http_request", return_value=...): ...

# Bad — 定義モジュールを patch。agent.py に既に import されたリファレンスは置き換わらない
with patch("strands_tools.http_request", return_value=...): ...
```

素の `unittest.mock.patch` より `monkeypatch.setattr` を優先する — pytest ネイティブで teardown が自動。`pytest-mock`（`mocker` fixture）は現状 dev 依存に入っていないので、導入する場合は同じ PR で `pyproject.toml` に追加すること。

## `parametrize` と Hypothesis の使い分け

- **代表ケース、既知の回帰** → `@pytest.mark.parametrize` + `ids=[...]` or `pytest.param(..., id="...")`。
- **入力空間に対する不変条件** → Hypothesis。
- 2 つを併用するのが 2026 年の既定。`example_agent` のテストはこのパターン（`TestDetectLanguage` のテーブル + `TestDetectLanguageProperties` の Hypothesis）。

Hypothesis レビュー観点：

- I/O を含むか遅い変換を含む戦略には `settings(deadline=None)`。
- 既知エッジは `@example(...)` で pin する方が、戦略を広げるより良い。
- 再現性を優先するテストは `derandomize=True`。
- shrinking の品質: 反例がノイジーなら戦略が緩い — `@st.composite` でタイトにする。

## async テスト

モードは `asyncio_mode = "auto"` — 全 `async def test_*` が自動収集される。レビューで確認：

- 各 async テストに上限がある: `async with asyncio.timeout(5):` で Act を囲む。
- **Task leak 検出**（推奨パターン、現状は未導入）。async テストを本格的に使う PR で autouse fixture として導入する：

  ```python
  @pytest.fixture(autouse=True)
  async def _no_leaked_tasks():
      before = asyncio.all_tasks()
      yield
      leaked = asyncio.all_tasks() - before
      assert not leaked, f"leaked tasks: {leaked}"
  ```

- `event_loop` fixture のオーバーライドは非推奨。必要なら `event_loop_policy` をオーバーライドする。
- 同期/非同期が混在するコラボレータで backend 抽象が必要なら `anyio`。それ以外は asyncio で十分。

## 時刻と乱数

- `datetime.now()` / `time.time()` を本番コード（テスト経由で到達する）に直呼びしない。`Clock` Protocol を注入する。
- `time-machine`（`freezegun` はメンテナンスモード）。
- `random.Random(seed)` を注入。モジュールレベルの `random` を使わない。
- `uuid.uuid4()` も UUID 生成関数として DI する。

## HTTP / 外部 I/O（test double を避けきれない場面だけ）

このプロジェクトの既定ドクトリンは「test double を使う必要が出ないように設計する」（`patterns.md §2`）。以下の道具は、Functional Core / Imperative Shell で I/O を薄い外殻に押し出してもなお残る、**プロセス内実行不可能な外部 I/O** 境界の統合テスト用のみに使う：

- 実通信の録画（既定）→ `pytest-vcr`。サニタイズ request/response hook で API キーや PII を必ず除去。CI は `--record-mode=none`、再録画は手動。
- httpx の直接モック（録画が難しい場合のみ）→ `respx`。
- requests の直接モック（同上）→ `responses`。
- unit レイヤで `pytest-socket --disable-socket`、integration で `--allow-hosts=localhost`。

**レビュー観点**: HTTP モックが現れたら、まず「Functional Core に抽出すれば mock 不要にならないか」を問う。パース・判断・組み立てはほぼ全て純関数に寄せられる。

## 環境変数

- `monkeypatch.setenv("FOO", "bar")`。`os.environ` を直接触らない — teardown が効かない。
- デフォルトが漏れないように `monkeypatch.delenv("FOO", raising=False)`。

## カバレッジ（推奨状態、現状は未強制）

**現状**: CI (`.github/workflows/ci.yml`) は `uv run pytest -v` のみで `--cov` 引数なし。pyproject にも coverage セクションなし。以下は「導入するならこうする」という推奨案であり、現時点で PR を落とす根拠にはしない。

推奨:

- `--cov-branch` を必須化。
- `pyproject.toml` の `[tool.coverage.report]` で `if TYPE_CHECKING:`, `@overload`, `raise NotImplementedError` を除外。
- ドメインコア ≥ 95%、glue / CLI ≥ 60%。リポ全体を単一閾値で縛らない。
- 行カバレッジは正しさと同義ではない。四半期に 1 回 mutation testing (`mutmut`) を走らせて実効性を測る。

## マーカー（推奨状態、現状は未宣言）

`pyproject.toml` は `--strict-markers` を有効化しているが、`markers = [...]` リストが未宣言のため、カスタムマーカー（`@pytest.mark.llm` など）を書いた瞬間に fail する。新規マーカーは **同じ PR で pyproject に登録** することをレビューで要求する。

推奨するマーカー階層：

| Marker | 意味 |
|---|---|
| `unit` | 純粋ロジック、I/O なし、< 100 ms |
| `integration` | testcontainers (Supabase/Postgres)、ディスク、ローカルネットワーク |
| `llm` | 実 Anthropic API 呼び出し; nightly のみ |
| `e2e` | n8n + Supabase + Discord フルスタック; release 前のみ |
| `slow` | > 1 s |
| `property` | Hypothesis 駆動 |

CI 既定: `-m "not llm and not e2e"`。

（現状は CI がマーカーフィルタをしておらず、マーカーリストも未宣言。導入する PR ではこのセクションと `ci.yml` の同時更新を要求する。）

## `filterwarnings = ["error"]`

リポジトリは warning を error に昇格済み。レビューで拾うべき：

- 一括 `filterwarnings("ignore")` → 却下。
- 個別無視は特定モジュールに限定: `"ignore::DeprecationWarning:some_lib"`。
- diff から新しい warning が出てくる場合は対処計画を要求: ソースを直すか、upstream issue をコメントつきで個別無視する。

## LLM / エージェント領域での Hypothesis 戦略

- カテゴリ出力（例: `Language = Literal["en","ja","unknown"]`）→ `st.sampled_from([...])`。
- Pydantic モデル → `st.from_type(Model)` + 必要に応じて `st.register_type_strategy` で上書き。
- 自由テキスト → 制約する: `st.text(alphabet=st.characters(whitelist_categories=("L","N"," ")), max_size=200)` で、Unicode の病的ケースはスコープ外なら除外する。
- エージェントの stateful な挙動 → `RuleBasedStateMachine` で `(conversation, tool_call, tool_result)` 遷移を探索する。

## プロジェクト固有のディレクトリ構成

```text
packages/<agent-name>/
├── src/<module>/
└── tests/
    ├── conftest.py        # パッケージローカル fixture
    ├── test_*.py          # unit / property テスト
    └── eval/              # golden dataset + eval runner（llm marker）
```

`src/` 配下にテストをネストしない。`tests/` はその兄弟に置く — `ruff` の `src = ["packages/*/src"]` は既にそのスコープを想定している。
