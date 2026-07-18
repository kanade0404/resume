# AI 生成テストのアンチパターン

LLM が書いたテストは、特定の予測可能な形で壊れる。レビュー時に探すべきパターン群。これらは実バグ検出能力がゼロに近いことが多い。

支配的な問い：**実装に現実的な mutation（`>` を `>=` に、分岐を 1 つ削除、キャッシュ値を返す、`None` を返す）を加えてもテストが通ってしまうか?** 通るなら装飾品。

---

## 1. Self-consistent assertion 🔴

`expected` を、テスト対象の実装を呼び出して得ている。

**Bad.**
```python
def test_parse():
    raw = "2026-04-22T09:00:00Z"
    expected = parse_timestamp(raw)  # ← テスト対象と同一関数
    assert parse_timestamp(raw) == expected
```

**なぜ失敗するか.** `parse_timestamp` のどんなバグも両辺に同じく現れ、assertion では検出できない。

**修正.** 仕様から手で expected を組む。あるいは人間が要件から書いた (input, expected) のテーブルで parametrize する：

```python
@pytest.mark.parametrize("raw, expected", [
    ("2026-04-22T09:00:00Z", datetime(2026, 4, 22, 9, 0, tzinfo=UTC)),
])
def test_parse(raw, expected):
    assert parse_timestamp(raw) == expected
```

---

## 2. Mock-everything 🔴

ターゲットが触れるコラボレータを全部モックし、ターゲットが実際には実行しない制御フローだけを検証している。

**Bad.**
```python
def test_run_agent(mocker):
    mocker.patch("agent.fetch_url", return_value="<html>...</html>")
    mocker.patch("agent.parse_html", return_value={"title": "x"})
    mocker.patch("agent.summarize", return_value="x summary")
    mocker.patch("agent.persist", return_value=None)
    result = run_agent("https://example.com")
    assert result is None  # ← 有意義な検証になっていない
```

**なぜ失敗するか.** モックが「真実」を定義し、テストは `run_agent` が最後のモックの戻り値を返すことしか確認していない。実ステップのバグは一つも検出できない。

**修正.** I/O 境界（`fetch_url`）だけをモックする。parser / summarizer / persistence は本物 + fake DB（in-memory repo）で走らせる。観測可能な outcome を assert する。

---

## 3. Oracle copy-paste 🔴

テストがアルゴリズムを再実装し、自分自身と比較している。

**Bad.**
```python
def test_language_detection(body):
    words = body.split()
    ja = sum(1 for w in words if w in {"の","は","が"})
    en = sum(1 for w in words if w.lower() in {"the","is"})
    expected = "ja" if ja > en else ("en" if en > 0 else "unknown")
    assert detect_language(words) == expected
```

**なぜ失敗するか.** 両実装が同じバグ（フォールバックの順序、タイブレーク）を共有している場合、両方一致してしまう。

**修正.** 独立した oracle を使う: 仕様から導出した (input, expected) を手で用意したテーブル（再計算ではなく）：

```python
@pytest.mark.parametrize("words, expected", [
    ([], "unknown"),
    (["the", "is"], "en"),
    (["の", "は"], "ja"),
    (["the", "は"], "en"),        # tie は en（仕様としての挙動）
])
def test_language_detection(words, expected):
    assert detect_language(words) == expected
```

---

## 4. Expected/actual の入れ違い、真偽反転 🔴

引数の順序が逆。あるいは仕様が「X」なのに `assert not X` になっている。

**Bad.**
```python
assert expected == actual      # pytest では動くが、片方が None だと意図が見えない
assert not is_valid(payload)   # 仕様: 「不正 payload を拒否」— だが payload はここでは有効
```

**検出.** テスト名と仕様を突き合わせる。名前が「X を拒否する」で assertion が `not rejects(X)` なら反転。実装が正しい場合にのみ反転が顕在化することもあるので、実装を読むのもセットで。

**修正.** assertion の極性をテスト名と合わせる。慣習として `assert actual == expected`（pytest は actual を左に置く）。

---

## 5. 意味不明な magic number 🟡

`42`, `"foo"`, `3` が setup や assertion に、根拠もコメントもなく現れる。

**Bad.**
```python
def test_rate_limit():
    for _ in range(42):
        client.call()
    assert client.throttled is True
```

**なぜ失敗するか.** 42 はレート制限設定か? それとも別の何か? 次のエンジニアが安全に変更できない。

**修正.** 名前付き定数にするか、仕様コメントを添える：

```python
def test_rate_limit_triggers_at_configured_threshold():
    for _ in range(RATE_LIMIT + 1):
        client.call()
    assert client.throttled is True
```

---

## 6. 呼び出し順に過剰適合した assertion 🟡

public 契約ではない内部呼び出しの順序や回数を縛っている。

**Bad.**
```python
agent.run("https://example.com")
assert fetch.call_count == 1
assert parse.call_count == 1
assert summarize.call_count == 1
assert fetch.call_args.args[0] == "https://example.com"
```

**なぜ失敗するか.** 正当なリファクタ（キャッシュ、バッチ、リトライ）が、観測可能な振る舞いを変えずにテストを壊す。

**修正.** 観測可能な結果（書き込まれた内容、戻り値、fire された span）を assert する。内部の call_count assertion を外す。

---

## 7. 何でも snapshot 🟡

LLM 出力やビルド成果物の大部分を、正規化なしで inline / ファイル snapshot に取っている。

**Bad.**
```python
def test_summary(snapshot):
    result = summarize("...long text...")
    assert result == snapshot  # timestamp, random id, model version が含まれる
```

**なぜ失敗するか.** 毎回変動するフィールドに触れる → snapshot の churn → レビュワーが diff を読まなくなる。

**修正.** snapshot 前に正規化: timestamp 除去、キーソート、id マスク。構造化部分には **structural matcher** (`toMatchObject`, `dirty-equals`) を使い、本当に静的な payload だけ snapshot する。

---

## 8. 非識別アサート 🟡

どんな「それっぽい」入力でも通ってしまうアサート。実装が壊れていても通る。

**検出例.**
- `assert result is not None` — `None` 以外なら通る。
- `assert len(items) > 0` — 何か返ってくれば通る。
- `assert isinstance(x, dict)` — 空 dict でも通る。

**修正.** 実装が生成しなければならない具体的な性質を assert する: フィールド値、件数、順序、不変条件。property-based (Hypothesis) は「このクラスの入力すべてについて、出力は性質 P を満たす」を固定する強力な手段。

---

## 9. ドリフトする fake LLM 🟡

Anthropic `Message` オブジェクトのフィクスチャを手書きで作っており、SDK の bump で実 API 形状と乖離する。

**検出.** 生 dict で組まれたフィクスチャで、テストがフィールドをハードコードしている。`anthropic` を upgrade しても fixture は通り続けるが本番では壊れる。

**修正.** `respx` / VCR で実レスポンスを 1 回録画してカセットを commit、定期再録画する。SDK ドリフト検出用に実 API に対する小さな契約テストを nightly（`llm` marker）で併走させる。

---

## 10. temperature-zero 神話 🟡

`temperature=0` で LLM が決定的になる、とテストが仮定している。

**なぜ失敗するか.** tokenizer のバッチング、サイレントなモデル更新、キャッシュ挙動はいずれも `temperature=0` でも出力を揺らす。

**修正.** モデルスナップショットを pin する（例: `us.anthropic.claude-sonnet-4-20250514`）。正確な部分文字列ではなく **構造や意味的性質** を assert する。主観的な品質は LLM-as-judge と rubric で評価する。詳細は `llm-eval.md`。

---

## 11. 型システムが保証する自明な不変条件の assertion 🟢

型注釈やデコレータが保証しているものを、テストで二度確認している。

**Bad.**
```python
def test_returns_pydantic_model():
    result = build_summary(...)
    assert isinstance(result, PageSummary)  # 戻り値型が既に保証している
```

**修正.** 削除するか、仕様が求める具体的フィールド値のチェックに置き換える。

---

## 12. private state に手を伸ばす 🟡

public API で公開されていない振る舞いのため、テストが `_private` 属性 / protected メソッドを assert している。

**検出.** `obj._cache`, `obj._foo = ...`, `patch.object(Cls, "_internal")`。

**修正.** 次のいずれか: (a) public API に観測手段を追加する（query メソッド）、(b) テストが検証すべき対象が違う。private state のテストは実装に結合し、リファクタで落ちる。

**例外.** 純粋で文書化された内部ヘルパ（`example_agent` の `_detect_language` のように、明確な契約を持ち状態を持たないもの）は直接テストして良い。

---

## レビュー時の検出ヒューリスティック

AI 生成テストの兆候を素早く拾うために：

1. **`expected = <fn_under_test>(...)` を検索する** — self-consistent assertion を一発で捕まえる。
2. **テストモジュール内の `mock` / `patch` の数を数える**。テスト 1 本あたり 4+ なら赤信号。
3. **assert のバリエーションを確認する**。全部 `is not None` / `== {}` / `isinstance` なら非識別アサート。
4. **`# TODO` / `# FIXME` を検索する** — LLM は不安なとき残す。ギャップを示す。
5. **テスト名を読み、本体を見ずに assertion を予測してみる**。予測できなければテストの契約が不明瞭。
