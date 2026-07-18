# Test Smells カタログ

Gerard Meszaros『xUnit Test Patterns』(2007) の 17 smells（#1〜#17）を、2026 年の Python コード向けに再整理したもの。#18 は本プロジェクト固有の smell（Over-mocking）。

レビューでの severity 分類: 🔴 critical（merge を止める）· 🟡 major（修正すべき）· 🟢 minor / スタイル。

各項目: 定義 · 検出 · 修正 · 既定 severity。

---

## 1. Eager test 🟡

**定義.** 1 つのテストで無関係な複数の振る舞いを検証している。

**検出.** テスト名に「and」「or」が含まれる。Act が 1 行を超える。無関係なアサーション群が空行で分かれて並んでいる。

**修正.** 振る舞いごとにテストを分割する。setup を共有するなら factory fixture に抽出。

---

## 2. Mystery guest 🟡

**定義.** テストが、テスト本体から見えない外部状態（ディスク上のファイル、DB の行、環境変数）に依存している。

**検出.** ファイル名 / row id / マジック文字列を参照しているのにファイル内に定義されておらず、インラインでも構築されていない。

**修正.** インラインで fixture を構築する（factory fixture）、あるいは `tmp_path` とヘルパでテスト内にファイルを書き出す。

---

## 3. Fragile test 🔴（リファクタを阻害する場合）

**定義.** 観測可能な振る舞いに影響しない実装変更でテストが壊れる。

**検出.** private ヘルパのリネーム、内部関数の引数順変更、クラス抽出でテストが落ちる。

**修正.** public API の観測可能な出力だけを assert する。内部コラボレータ呼び出しの検証を外す。内部ヘルパのモックを本物に戻す。

---

## 4. Obscure test 🟡

**定義.** 外部コードを読まないとテストの意図が分からない。

**検出.** Setup が遠くの fixture に隠れている。値が不可解なヘルパから来る。読み手が「このテストが何を証明しているか」を言えない。

**修正.** テストが実際に使う最小限の setup をインライン化する。fixture は退屈なデフォルトを持ち、意味のある値はテスト内で上書きする。

---

## 5. Assertion roulette 🟡

**定義.** 複数の assert があり、失敗したときにどの概念が落ちたか分からない。

**検出.** message なし、`pytest.param(id=...)` なし、明確な段階性もない複数 `assert` の羅列。

**修正.** `@pytest.mark.parametrize` + `ids=[...]` でケース分割する。`dirty-equals` や構造マッチャを使って「どのフィールドが一致しなかったか」を報告させる。やむを得ず複数 assert なら message を添える。

---

## 6. Conditional test logic 🔴

**定義.** テスト本体の制御構造が、**どのアサートが走るか / どう走るか** を分岐させている。

**検出.** テスト関数内に `if`/`try`/`while`/`for` があり、その分岐で assertion の実行可否や内容が変わる。

**正当な例外.**
- **property-based テストの precondition フィルタ**: `hypothesis.assume(cond)` が慣用形。`if cond: assert ...` も、`cond` が入力分割の述語であり、どの入力でも最終的に property を満たすなら許容（詳細は `#16 Guarded assertion` を参照して区別）。
- **パラメトリック化できないヘルパ内の純粋ループ**: assertion 自体を覆い隠さないループ。

**修正.** 分岐ごとにケースを分け、`@pytest.mark.parametrize` に展開する（各分岐が 1 テスト）。

---

## 7. Test code duplication 🟢

**定義.** 同じ Arrange ブロックが多数のテストにコピペされている。

**検出.** 5+ テストの最初の N 行が同一。

**修正.** overrides を受け取る factory fixture を作る。setup 全体を `autouse` に押し込むと Obscure test を生むので避ける。

---

## 8. Resource optimism 🟡

**定義.** 外部リソースが存在することを検証なしに仮定する。

**検出.** URL を叩く、ファイルを読む、サービスに繋ぐテストが明示的な setup なしで動く前提で書かれている。

**修正.** unit では境界をモックする。integration では testcontainers でリソースを起こすか、明確な条件で skip する。

---

## 9. Indirect testing 🟡

**定義.** 対象を別のクラス経由で叩いている。

**検出.** テスト名がクラス A のことを言っているのに、assertion は全部クラス B を見ている。

**修正.** A の public API を直接叩く。無理なら、A 側に seam を追加する設計レビューが先。

---

## 10. Sensitive equality 🟡

**定義.** 等価性が実装詳細（`__str__`, JSON フォーマットなど）に依存している。

**検出.** `assert str(obj) == "..."`、シリアライズ JSON の文字一致。

**修正.** 構造比較を使う（`model_dump()`、dict）。部分一致は `dirty-equals`。snapshot するなら先に正規化（タイムスタンプや順序を除去）。

---

## 11. For testers only 🔴

**定義.** プロダクションコードにテスト専用の分岐 / アクセサ / 属性が混入している。

**検出.** `if os.getenv("PYTEST"): ...`。`_for_test` / `reset_state` という名前のメソッド。テストフラグ時だけ internal を公開するクラス。

**修正.** Protocol / DI による seam を追加し、テストが本体に知らせずに振る舞いを差し替えられるようにする。

---

## 12. The free ride 🟢

**定義.** 既存テストに無関係な assertion を「ついでに」追加する。

**検出.** 1 つのテストが複数の概念を検証し、複数のコミット / 著者によって増築されている。

**修正.** その assertion を、検証したい振る舞い名のついた独立テストに移す。

---

## 13. Silent catcher 🔴

**定義.** テストが例外を握り潰して検証していない。

**検出.** テスト内の `except Exception: pass`。message マッチャなしの `pytest.raises(Exception)`。

**修正.** `pytest.raises(SpecificError, match="...")` を使う。例外が無関係なら try/except ごと削除。

---

## 14. Erratic (flaky) 🔴

**定義.** 通ったり落ちたりする。

**検出.** CI で fail → pass の履歴。retry アノテーション。「たまに落ちる、retry でなんとかなる」というコメント。

**修正.** SKILL.md の flakiness 分類表に従って原因を特定する。調査中の隔離は OK。`pytest-rerunfailures` で誤魔化さない。

---

## 15. Slow test 🟡

**定義.** 所属レイヤの時間予算を超える（unit > 100 ms、integration > 1 s）。

**検出.** `pytest --durations=20`。明示的な `sleep`。モックなしのネットワーク呼び出し。

**修正.** I/O を fake に寄せる。`sleep` を決定的待機（event / condition）に置き換える。本質的に遅いなら適切なマーカーを付けて integration レイヤに降ろす。

---

## 16. Guarded assertion 🟡

**定義.** アサートが `if` で守られていて、条件が偽のときはテストが暗黙に pass する。

**検出.** `if condition: assert ...` に対応する `else: pytest.fail(...)` がない。

**修正.** guard を外す（assertion は常に実行されるべき）か、parametrize で両方のケースをカバーする。

**property-based との区別.** Hypothesis の precondition フィルタ（`hypothesis.assume` や「どの入力でも property を満たす precondition の `if`」）は Guarded assertion ではない — それは入力空間の分割であって、assertion のサイレント回避ではないため。`hypothesis.assume` を優先し、`if` を使うなら「`if not P(x): return`」ではなく「`if P(x): assert Q(x)` かつ P を広く満たすもの」にする。

---

## 17. Lonely assertion 🟢

**定義.** ひとつしかない assertion が、何の契約を検証しているか不明。

**検出.** テスト名が振る舞いを説明していない 1 行テスト。

**修正.** 振る舞い名でリネーム。非自明な *why* だけコメントで補足。実質的に何も保証しないなら、より強いテストと統合するか削除を検討する。

---

## 18. Over-mocking 🔴（プロジェクト固有 smell）

**定義.** test double が「使う必要がない場面」で使われている。純関数抽出 / Humble Object 化で不要にできるはずのテストに mock / stub / spy が置かれている。

**検出.**
- テストファイルに 3+ 箇所の `patch(...)` / `mocker.patch` / `vi.fn()` が並ぶ。
- 「テストしにくいから mock した」趣旨のコメント。
- 本物で起動できる DB（testcontainers / supabase-cli で可能）に対して in-memory fake を当てている。
- 自分が所有するコードの内部関数 / 内部クラスを mock している。

**なぜ本プロジェクトで赤信号か.** このプロジェクトは「test double を使う必要が出ないように設計する」を既定ドクトリンにしている（`patterns.md §2`）。Over-mocking は設計が Functional Core / Imperative Shell に沿っていないサインであり、テスト品質の問題である前にコード設計の問題。

**修正.** まず対象コードを純関数として抽出できないかを問う（`patterns.md §6 Humble Object`）。I/O を薄い外殻に押し出して、検証したいロジックを test double なしで直接呼べる形にリファクタする。外殻の I/O は testcontainers / VCR 録画で本物を動かす。どうしても test double が必要な場面は、プロセス内実行不可能な外部 API のごく限られた境界だけ。

---

## 横断的なレビュー技法

迷ったらこう問う： *「このテストを明日削除したら、どの現実のバグをすり抜けさせるか?」* 具体的な回帰を名指しできないなら、そのテストは装飾品。近隣のテストと統合するか削除する方が健全なことが多い。

**手動 mutation の次の段階**: PR に mutation testing のスコア（Stryker / mutmut / pitest / cosmic-ray 等）が既に付いている場合、見るべきは score の絶対値ではなく **survived mutant の中身**。score が 90% でも、生き残りが認可判定や金額計算のような critical path に集中していれば要修正。逆に score が低くても、生き残りが equivalent mutant（意味的に元コードと等価な変異）ばかりなら許容してよい。

**Goodhart 対策**: mutation score を CI ゲートの KPI として固定値で強制しない。score を上げること自体が目的化すると、assertion を水増しするだけのテストが増え、`#1 Eager test` や `#17 Lonely assertion` を誘発する。

**本スキルの範囲外**: mutation testing の実行自体（テストスイートを実際に回して変異を注入する）は「テストを実行しない」宣言と整合させ、本スキルでは行わない。自動 mutation の実行・ゲート化は `test-mutation-gate` を参照。
