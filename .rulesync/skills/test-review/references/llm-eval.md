# LLM / エージェントテストレビュー

Claude API 呼び出し、Strands Agents ループ、tool use、RAG など、非決定的な AI パスを運ぶテストのレビュー観点。

指針: **決定論的なロジックと非決定論的な境界を分離し、それぞれをそのレイヤ固有の方法でテストする。**

---

## 決定論的な seam

これらは純関数。LLM もモックも不要で直接テストする：

1. **プロンプト合成** — テンプレ展開、context 注入、truncation、cache-breakpoint 位置決定。
2. **出力パース** — structured output のデシリアライズ、schema 検証。
3. **ツール引数バリデータ** — LLM 由来入力に対する Pydantic / JSON Schema ガード。
4. **ルーティング** — 入力に応じたモデル / ツール / 分岐の選択。
5. **メモリ / 履歴圧縮** — サマリ、退避ポリシー、must-keep 事実の保持。

2〜4 は Hypothesis が強い: 出力が型付け、不変条件も述べやすい。ここのカバレッジは 80% より 100% に近い方が正しい — エンジニアリングの本体はここにある。

## 非決定論的境界

LLM 呼び出し自体（`Agent.run`, `client.messages.create`）が境界。2 つのモードがある：

- **Unit**: `FakeModel`（Strands 提供）あるいは録画済みレスポンスを返す `respx` ハンドラに差し替える（`respx` は現状 dev 依存に無いので、導入時に `pyproject.toml` へ追加する）。trajectory、ツール呼び出し順、コストを assert する — 内容そのものは assert しない。
- **Nightly eval**: 実 API を叩く。`@pytest.mark.llm` + secret ゲート。結果はダッシュボードへ。PR は止めない。

## プロンプトテスト

- **展開後プロンプトの snapshot**。典型入力ごとに完全展開されたプロンプトを inline snapshot。テンプレ回帰（変数漏れ、セクション順の入れ替え、キャッシュ prefix の破壊）を即捕まえる。
- **cache-control の位置**。Anthropic prompt caching ではバイトオフセット単位で `cache_control` がキャッシュヒット率を決める。system プロンプトをキャッシュマーカーごと snapshot する。
- **プロンプトのバージョニング**。プロンプトが Git 管理下ならその hash がバージョン。OTel span に付与し、trace をバージョン別にグルーピングできるようにする。

## ツール呼び出しテストの 4 軸

1. **ツール選択の precision / recall**。入力 *X* に対してツール *A* が選ばれるべき、を表駆動で明示。positive だけでなく **negative**（選ばれてはいけない入力）も入れる。
2. **引数妥当性**。Hypothesis でツール引数を fuzz する。無効組み合わせはツール実行前にバリデータで弾かれるべき。
3. **存在しないツール名の検出**。モデルが架空のツール名を出すケースを negative として入れる。エージェント層は優雅に拒否する（落ちない、沈黙の成功にならない）。
4. **オーケストレーション**。マルチツールの trajectory を順序 / DAG として assert。文字列マッチではなく span assertion を使う。

## エージェントループテスト

- **停止条件**。`max_iterations`、no-op 検出（同ツールが同引数で連続呼び出し）、同じアシスタントメッセージが連続、それぞれ個別テスト。
- **コスト / トークン上限**。実行ごとに `usage.input_tokens + usage.output_tokens * price` を累積し、予算に対して assert する。プロンプト肥大の早期検知。
- **メモリ完全性**。needle-in-haystack: 基準事実を注入 → 履歴圧縮 → エージェントの public query パス経由で取り出せることを検証。
- **冪等性**。同じタスクの二回実行で Supabase に二重書き込みが発生しないこと。永続化層で dedup key を assert する。

## Eval (offline)

- **Golden dataset** はリポジトリ内: `packages/<agent>/tests/eval/fixtures/*.jsonl`、commit 対象。重要な能力ごとに dataset を持ち、回帰が見つかるたびに新ケースを追加する。
- **このレイヤで意味のある指標**（汎用 NLP スコアではなく）:
  - Task completion rate
  - Tool-call precision / recall / F1
  - Grounding / faithfulness（RAG 出力向け）
  - Refusal correctness（Safety）
  - 参照 trace との trajectory 類似度
- **LLM-as-judge** は対象と **別のモデル** を使う。Opus が Sonnet を評価、Sonnet が Haiku を評価。同一モデルは self-preference bias を生む。
- **pairwise 比較 + 順序ランダム化** で judge のキャリブレーション・ドリフトを抑える。
- **CI の階層化**
  - smoke eval (5〜10 ケース): エージェントに触れる PR ごと → 分で終わる、安い。
  - full eval: nightly。
  - release eval (full + red-team): タグ前。

## VCR / 録画

**現状**: `vcrpy` / `respx` はまだ dev 依存に入っていない。下記は LLM 境界テストを本格導入する PR で合わせて追加すべき道具立て。

- `vcrpy` / `respx` + サニタイズ hook。PII、API キー、session token はカセットが Git に入る前にスクラブする。
- CI は `--record-mode=none`。API 変更時は手動で再録画。SDK のサイレントドリフト検出のために定期再録画（月 1 など）を走らせる。
- カセットも fixture と同じようにレビューする。再録画時の diff は小さく説明可能であるべき。

## Red-team / safety テスト

Safety 原則のコードでは必須。レビューではこれらの存在を要求する：

- **Prompt injection**（Gmail / X 等のペイロードからの indirect injection 含む）。
- **system プロンプト乗っ取り**（ロール切替トリック）。
- **Data exfiltration** — ツール出力に credential や PII が漏れる。
- **Tool abuse** — ポリシー外のパラメタでツールを呼ばせる。
- **Refusal correctness** — 拒否すべき入力が拒否されている。

参照 dataset: OWASP LLM Top 10 (2025)、Garak、PyRIT、Lakera Gandalf、MLCommons AILuminate。

## OpenTelemetry assertion

Strands Agents は span を native に emit する。テスト時は in-memory OTel exporter を有効にして span 属性を直接 assert する：

```python
def test_summarize_emits_expected_spans(otel_exporter, agent):
    agent.run("summarize https://example.com")
    spans = otel_exporter.get_finished_spans()
    tool_spans = [s for s in spans if s.name == "tool.fetch_page"]
    assert len(tool_spans) == 1
    assert tool_spans[0].attributes["tool.args.url"] == "https://example.com"
```

「何をしたか」に対する assertion で、「どうしたか」（どの内部メソッドが呼ばれたか）には依存しない — リファクタ耐性が出る。

## この領域でよくあるレビュー指摘

| パターン | 問題 | 修正 |
|---|---|---|
| `temperature=0` を決定論の根拠にする | 再現性の錯覚 | モデルスナップショット pin + 構造 / 意味的性質を assert |
| `expected = agent.run(x)` | Self-consistent assertion | 仕様から expected を組む |
| エージェント全体を 1 assert で end-to-end | 落ちたときに診断不能 | seam ごとに分割 |
| 判定モデルが対象と同一 | Self-preference bias | 別モデルを使う |
| 再録画カセットの diff が巨大 | API サイレントドリフトか PII 漏れ | diff 精査、再スクラブ |
| コスト上限 assertion なし | プロンプト肥大の回帰 | 予算 assertion を追加 |
| ツール選択 positive のみ | 誤ったツールが選ばれても気付かない | negative を入れる |
| eval 更新なしのプロンプト変更 | サイレントな品質劣化 | prompt version bump + smoke eval を同じ PR に |

## モデルスナップショットの pin

テストや VCR カセット内のモデル識別子は **日付つきスナップショット** を使う（エイリアスではなく）。エイリアスのみ（例: `anthropic.claude-sonnet-4-v1`）だと Anthropic 側でベースモデルがサイレントに回転する可能性があるため、日付を含む形を使う。

形式はルートによって異なる：

- **Anthropic API 直（`@anthropic-ai/sdk` や Python `anthropic` 経由）**: 公式形式は `claude-sonnet-4-YYYYMMDD`（例: `claude-sonnet-4-20250514`）。`us.anthropic.` のようなリージョン / プロバイダ prefix は付かない。
- **Amazon Bedrock 経由（Strands Agents の既定ルートの 1 つ）**: `us.anthropic.claude-sonnet-4-20250514` のようにリージョンプレフィックス付き ID になる。既存の `packages/example-agent/tests/test_agent.py` で使われているのはこの Bedrock 形式。

レビューでは「呼び出しルートと ID 形式が一致しているか」を確認する。Anthropic 直叩きのコードに Bedrock 形式の ID を渡すとそのまま失敗するため、ID の形式がルートを暗黙に示してしまう。いずれの形式でも、必ず末尾 8 桁の日付を付けてスナップショットを pin する。
