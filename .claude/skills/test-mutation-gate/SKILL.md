---
name: test-mutation-gate
description: >-
  テスト変更を含む diff に対して静的 assertion 監査 (Phase 1) と unit テスト限定の mutation smoke
  (Phase 2、実コードへの変異注入 + 再実行) を行い、PASS/BLOCK
  を判定するゲート用スキル。tautology-literal-sharing (critical) / assertion-roulette /
  overstated-coverage / boundary-gap の 4 チェックを正規表現ベースで実行し、critical が 1 件でもあれば
  BLOCK として呼び出し元に差し戻す。加えて対象が unit テスト (プロセス内で完結・外部 I/O 無し) の場合のみ
  `scripts/mutate_and_run.py` で変異注入を行い、survived mutant が 1 件でもあれば BLOCK にする。主経路は
  `tdd` Step 3.5 (GREEN 確認後・commit 前)・`pr-review-respond` Phase C (VALID 修正のテスト側
  diff)・`verify-done` Step 4 (完了宣言直前)
  の各本文に組み込まれた強制サブステップ呼び出しであり、ユーザからの直接要請にも対応する。「このテスト検出力ある?」「テスト弱くない?」「assertion
  監査して」「tautology チェックして」「このテスト実装をなぞってるだけじゃない?」「テストがバグをロックインしてないか見て」「このテスト
  mutation testing して」のような口語、いずれでも必ず起動すること。テストコードの網羅的レビューは `test-review`、push 後の
  CI 赤対応は `ci-self-heal`、skill の eval trigger JSON 採点は `skill-builder` Mode
  B、テストスイート全体の mutation score 算出 (Stryker/mutmut 相当の運用) は、いずれも本スキルの範囲外。
allowed-tools:
  - Read
  - Bash
  - Grep
  - Glob
---
# Test Mutation Gate

テスト変更 diff に対して、実行前の静的読解だけで「このテストは検出力を持っているか」を審査するゲート。PASS/BLOCK の二値判定を返し、BLOCK なら実装フェーズに差し戻す。

## なぜ必要か

本スキルは 3 つの実測エビデンスから設計されている。

1. **passive trigger は機能しない。** `test-review` は 100 セッション超の運用で明示呼び出しが 0 回だった。「テストが変更されたら自発的に review スキルが起動する」という受動的な trigger 設計は、実際のセッションでは発火しない。したがって本スキルは独立した passive skill として置かず、呼び出し元 3 スキル (`tdd` Step 3.5 / `pr-review-respond` Phase C / `verify-done` Step 4) の本文に組み込まれた**強制サブステップ**として設計する。呼び出すかどうかを Claude の裁量に委ねない。
2. **同一エージェントが実装とテストを同時に書くと tautological / self-consistent assertion が生まれる。** これが実測で最頻出かつ最高 severity の欠陥だった。実例: cursor のバグをそのまま expected 値として固定し、バグを仕様として lock-in した assertion。frozen dataclass 同士を同一の構成引数で構築して比較しただけの自明な等価性検証。実装側のハイフン/アンダースコア混同をテスト側にもそのまま複製し、バグを検出不能にしていたケース。いずれも実装者自身がテストを書いたときに起きる特有のパターンで、他人がレビューしない限り自己相似的に見逃される。
3. **テスト名が主張する検証内容と実際の assertion が乖離するケースは、これまで外部 bot 頼みだった。** 例えば「callable であることを検証する」と名乗りながら実際には `Success` フラグの有無しか assert していない、といった乖離は CodeRabbit / Devin のレビューが指摘するまで気づかれなかった。本スキルはこれを PR 起票前・commit 前の内部ゲートとして先取りする。

Phase 1 は **静的 assertion 監査**、Phase 2 は **unit テスト限定の mutation smoke** (実コードへの変異注入 + 再実行で検出力を実測する) を担う。いずれも本スキルの範囲であり、対象がテストスイート全体の mutation score 算出やツール導入である場合のみ範囲外 (詳細は「このスキルがやらないこと」「既知の限界」を参照)。

---

## いつ使うか / 使わない場面

以下いずれかに該当する時、呼び出し元スキルの本文から**必ず**サブステップとして起動する:

- `tdd` Step 3.5: GREEN 確認後・commit 前 (実装とテストが両方揃った時点で検出力を審査する)
- `pr-review-respond` Phase C: VALID 修正が既存テストの assertion / 期待値そのものを書き換える時 (「Fixed in `<SHA>`」返信前)
- `verify-done` Step 4: 完了宣言の直前、対象 diff にテスト変更が含まれる時
- ユーザから「このテスト検出力ある?」「テスト弱くない?」「assertion 監査して」「tautology チェックして」「このテスト実装をなぞってるだけじゃない?」「テストがバグをロックインしてないか見て」「このテスト mutation testing して」のような要請があった時

逆に **起動しない / 起動しても意味がない場面**:

- 対象 diff にテストファイルの変更が一切含まれない (実装コードのみの変更)
- 自明な scaffolding 変更のみ (fixture の import 追加、conftest.py のパス変更等で assert 文自体は 1 行も変わっていない)
- テストコードの網羅的なレビュー (smell カタログ全体、seam 設計、flakiness 分類等) が欲しい場合 → `test-review`
- push 後に CI が赤くなった場合の対応 → `ci-self-heal` (本スキルは静的読解 + mutation smoke のみで CI を実行しない)
- skill の eval trigger JSON (should_trigger の付与が妥当か) を採点したい場合 → `skill-builder` Mode B
- integration/E2E/DB テストに対する mutation smoke を実行したい場合 → Step 2.5 は unit テストのみが対象 (コスト・副作用のため対象外)
- テストスイート全体の mutation score 算出や Stryker/mutmut 等ツールの導入を検討したい場合 → 本スキルは変更 diff 周辺の smoke のみ (`research-practices` 等の領域)

---

## ワークフロー

### Step 0 — 起動条件判定

対象 diff にテストファイル (`*_test.*`, `*.test.*`, `*.spec.*`, `test_*.py`, `**/tests/**` 等) が含まれるかを確認する。含まれなければ本スキルを起動せず呼び出し元にそのまま戻る。含まれていても assert 文が 1 行も変わっていない自明な scaffolding 変更は skip してよい。判定に迷ったら安全側 (実行する側) に倒す。

### Step 1 — diff 生成

呼び出し元が対象範囲を決めて unified diff を生成する。典型例:

```bash
git diff HEAD -- <test-file-paths...>
```

untracked な新規テストファイルは `--diff-file` にそのまま渡さず、`+++ b/<path>` ヘッダ付きの unified diff 形式に整形してから渡す (`git diff --no-index /dev/null <file>` 等)。スクリプトは unified diff のみを前提としており、生ファイル全文を渡すと入力エラー (exit 2) になる。

### Step 2 — 静的監査実行 (3 段 fallback)

観測可能な判定手順として、以下を**上から順に**試す。どの段で実行されたかを必ず gate 結果の `mode` に記録する (silent skip 禁止):

1. `uv run --no-project python "${CLAUDE_SKILL_DIR}/scripts/assertion_audit.py" --diff-file <path> [--max-asserts N]` を実行する。コマンドが正常に起動すれば `mode: static-script (uv)`。
2. `uv` が存在しない、または実行に失敗した場合、`python3 "${CLAUDE_SKILL_DIR}/scripts/assertion_audit.py" --diff-file <path>` にフォールバックする。`mode: static-script (python3)`。
3. `python3` も存在しない場合、§手動チェックリストを Claude 自身が Read/Grep のみで適用する。`mode: manual-fallback`。

過去に「`python3` が実行環境に存在せず、スクリプトが一度も実走しないまま静かにゲートを素通りしていた」という実失敗がある。この段階を省略したり、実行失敗を「まあ大丈夫だろう」で握りつぶしたりしない — 3 段のどこで判定したかを結果に必ず明記する。

`--max-asserts N` は既定 2 (assertion-roulette チェックの閾値)。スクリプトは 4 チェックを実行する: (1) tautology-literal-sharing → critical (2) assertion-roulette → warn (3) overstated-coverage → warn (4) boundary-gap → warn。出力は次の JSON 形式:

```json
{
  "version": 1,
  "verdict": "PASS",
  "findings": [
    {"check": "tautology-literal-sharing", "severity": "critical", "file": "...", "test_name": "...", "message": "...", "evidence": "..."}
  ],
  "summary": {"critical": 0, "warn": 0, "by_check": {}, "notes": []}
}
```

exit code: `PASS` = 0 / `BLOCK` = 1 / 入力エラー = 2。正規表現ベースで Python / TypeScript / JavaScript / Go に対応し、AST は使わない (限界は §既知の限界を参照)。

### Step 2.5 — mutation smoke (unit テストのみ)

対象が **unit テスト** (プロセス内で完結・外部 I/O 無し) の場合のみ実行する。integration/E2E/DB テストはコスト・副作用の理由で対象外 — 実行するかどうか迷ったら対象外側に倒す (assertion 監査の Step 0 とは逆に、ここは安全側 = skip 側に倒す)。

1. `uv run --no-project python "${CLAUDE_SKILL_DIR}/scripts/mutate_and_run.py" --impl-file <path> --test-cmd '<unit テストを実行するシェルコマンド>' [--max-mutations 3] [--timeout-sec 120]` を実行する。Step 2 と同じ uv → python3 の順で fallback するが、**手動 fallback は無い** — `python3` も無ければ手動で変異を作ることはせず `SKIP` 扱いにする (静的監査のみで判定し、その旨を notes に残す)。
2. bool 反転 / 比較演算子反転 / off-by-one の変異を最大 `--max-mutations` 件注入し、1 件ずつ test-cmd を再実行する。全 survived を `survived: []` に列挙し、`caught`/`mutations_total` を記録する (出力形式は `scripts/mutate_and_run.py` のモジュール docstring 参照)。
3. 変異候補が 0 件 (`SKIP`) の場合、対象コードが変異不能 seam である可能性を疑う → `references/mutation-recipes.md` の fallback (純関数抽出 → `tidy-first` の structural commit) → それも不可なら `references/waiver-fallback.md` の waiver。
4. survived mutant が 1 件以上あれば、その行・変異種別を Step 3 の判定に持ち込む (`BLOCK`)。

### Step 3 — 判定

- スクリプトの `verdict` をそのまま採用する。critical ≥ 1 なら `BLOCK`。手動チェックリスト実行時も同じ基準 (critical ≥ 1 → BLOCK) を Claude 自身が適用する。
- Step 2.5 を実行した場合、mutation smoke の survived ≥ 1 も `BLOCK` に統合する (静的監査が PASS でも mutation smoke が BLOCK なら総合判定は `BLOCK`)。
- `summary.notes` が非空なら、結果ブロックに必ず転記する (テストのみ diff で tautology チェックが skip された場合や、例外/ログ文脈のリテラル共有を除外した場合等、判定の前提を握りつぶさない)。mutation smoke の `notes` (regex ベースの構文破壊リスク、build error による caught 等) も同様に転記する。
- `BLOCK` の場合、呼び出し元に差し戻す:
  - `tdd` → Step 1 (RED) に戻り、tautological / self-consistent な assertion を書き直す、または survived mutant の行を検出できるアサーションを追加する
  - `pr-review-respond` Phase C → 修正をやり直す。この段階では VALID スレッドへの返信・resolve は行わない
  - `verify-done` Step 4 → 完了宣言を保留し、Step 4 (未保存・未 commit 変更の点検) より前の状態として扱う
- **waiver 手順**: critical findings を偽陽性と判断する場合のみ、実装を進めてよい。ただし gate 結果に `waiver: <理由 1 行>` を必ず残す (例: `waiver: frozen dataclass の __eq__ 契約検証であり tautology ではない`)。理由を書かずに findings を握りつぶすことは禁止。mutation smoke の変異不能 seam に対する waiver は `references/waiver-fallback.md` のテンプレに従う。

### Step 4 — 計測 emit + 結果返却

`scripts/emit_gate_event.sh` を呼び、判定結果を loop-ops へ記録する (best-effort、詳細は §loop-ops 計測)。Step 2.5 を実行した場合は `mutations_caught` / `mutations_total` の 2 引数も追加で渡す (未実行なら省略し後方互換を保つ)。送信の成否に関わらず、§出力フォーマットの結果ブロックを呼び出し元に返す。

---

## 手動チェックリスト (fallback)

スクリプトが実行できない場合、Claude が Read/Grep のみで以下 4 チェックを人手適用する。判定基準は §Step 3 と同じ (critical ≥ 1 → BLOCK)。

1. **tautology-literal-sharing (critical)** — 実装呼び出しの戻り値をそのまま expected として使っていないか。`actual = fn(x)` と `assert actual == fn(x)` のように、expected 側にも同じ呼び出し・同じ実装ロジックが再登場していないか Grep で探す。frozen dataclass / value object 同士を同一の構成引数で構築して比較しているだけの自明な等価性検証も該当する。実装側の既知のバグ (命名規則の混同、オフセットのずれ等) が、テスト側の expected 値にもそのまま複製されていないか目視確認する。
2. **assertion-roulette (warn)** — 1 テスト関数/メソッド内で、失敗メッセージが付いていない `assert` 文 (または `expect`, `assertEqual` 等の言語別 assertion 呼び出し) の数が既定 2 件を超える場合。メッセージ付きの assertion (Python `assert expr, "msg"`、Go の `t.Errorf`/`t.Fatalf` のようにフォーマット文字列自体がメッセージを兼ねるもの、`assertEqual(a, b, "msg")` の第3引数等) はこのカウントから除外する。落ちた時にどの assertion が原因か診断できない。
3. **overstated-coverage (warn)** — テスト名が主張する検証内容 (`test_returns_zero_when_empty`, `validates_input`, `raises_on_invalid` 等) と、テスト本体の assertion 対象が一致しているか確認する。名前が動詞句で謳っている振る舞い (検証・例外送出・状態遷移等) に対応する assertion が実際に存在しない場合は該当。
4. **boundary-gap (warn)** — 境界値 (0, 空文字列, 空配列/空コレクション, `None`/`null`/`nil`, 負数, 最大値・最小値) を検証するケースが 1 件も無い場合。parametrize / table-driven test の値一覧に境界値が含まれているか確認する。

---

## 出力フォーマット

固定の gate 結果ブロックを返す:

```markdown
## Test Mutation Gate: <PASS|BLOCK>

- mode: static-script (uv) | static-script (python3) | manual-fallback
- diff scope: <対象ファイル一覧>
- findings: critical=<n> warn=<n>
- mutation smoke: <not-run | SKIP (理由) | caught=<n>/<mutations_total> survived=<n>>
- notes: <summary.notes を verbatim、無ければ "-">

| check | severity | file | test | message |
|---|---|---|---|---|
| tautology-literal-sharing | critical | path/to/test.py | test_foo | <1 行要約> |

| survived mutant (line) | kind | before → after |
|---|---|---|
| 42 | comparison-flip | `>=` → `>` |

waiver: <理由 1 行 または "-">

→ 呼び出し元への指示: <1 行。例: "tdd Step 1 に戻り assertion を書き直す">
```

`PASS` のときも同じ枠を使う (findings / survived mutant が 0 件の表は省略してよい)。呼び出し元への指示は必ず 1 行で具体的に書く (「差し戻す」だけでなく「どのステップに戻るか」まで)。

---

## loop-ops 計測

`scripts/emit_gate_event.sh` は kanade0404/loop-ops の event schema v1 に既存する `agent_run` イベント種別を再利用する (`phase="test-mutation-gate"`, `result_subtype="pass"|"block"`, `caller`, `findings_critical`, `findings_warn` 等をフィールドに載せる)。Step 2.5 (mutation smoke) を実行した呼び出しでは、任意の第 6・第 7 引数として `mutations_caught` / `mutations_total` も渡せる (未指定なら省略され、payload に含まれない — 「mutation smoke を実行しなかった」と「実行して 0 件だった」を区別するため、後方互換のため省略時に 0 を送ることはしない)。専用の `gate_result` のようなイベント種別を新設していない理由は、loop-ops 側の `schema/event.v1.schema.json` と `docs/schema.md` の更新を待たずに計測を開始できるため。専用種別が本当に必要になった場合は、loop-ops リポジトリの schema とドキュメントを**同一 PR で**更新する必要がある。

送信先は環境変数 `LOOP_OPS_TOKEN` の有無で切り替わる: あれば GitHub Contents API `PUT` で `metrics/events/YYYY-MM/` 配下に 1 event = 1 file として送信する。無ければカレントリポジトリの `.cache/test-mutation-gate/gate-events.jsonl` に 1 行 append する。エージェント設定ディレクトリ (`.claude/`) ではなく専用のキャッシュパスに書くことで、本ゲートが commit 前の必須サブステップとして毎回走っても未追跡ファイルが residual に残らないようにしている (この配布元リポジトリでは `.gitignore` の `.cache/` で既にカバー済み、consumer 側でも同様に gitignore することを推奨)。**送信失敗はゲート判定に一切影響させない** — best-effort。

計測の目的は成績集計そのものではなく、**「ゲートが呼ばれているか自体を観測すること」**にある。`test-review` が 100 セッション超で 0 回しか呼ばれなかった実測を踏まえると、本スキルについても同じ劣化 (呼び出し元の本文からサブステップ呼び出しが削られる、スキップされる) が起きうる。イベントログの発火率そのものが「強制ゲートとして機能しているか」の一次シグナルになる。

DuckDB での確認クエリ例 (呼出元別の発火率・BLOCK 率):

```sql
select
  caller,
  count(*) as invocations,
  sum(case when result_subtype = 'block' then 1 else 0 end) as blocks,
  sum(case when result_subtype = 'block' then 1 else 0 end)::double / count(*) as block_rate
from read_json_auto('metrics/events/*/*.json')
where phase = 'test-mutation-gate'
group by caller;
```

---

## このスキルがやらないこと

- **網羅的テストレビューレポート**: smell カタログ全体・seam 設計・flakiness 分類は `test-review` の成果物であり本スキルからは出さない。
- **一般コードレビュー findings**: 実装コード全般の指摘は `code-review` の領域。本スキルはテスト側 assertion のみを見る。
- **CI 修復 commit**: push 後の CI 失敗対応・root cause 特定・修正コミットは `ci-self-heal` の成果物。本スキルは commit 前の静的読解のみ。
- **eval trigger JSON の採点結果**: skill の should_trigger 判定の妥当性採点は `skill-builder` Mode B の成果物。
- **テストスイート全体の mutation score 算出**: Stryker / mutmut の代替はしない — 本スキルは変更 diff 周辺の unit テストに対する smoke (最大 `--max-mutations` 件の局所的な変異注入) のみで、コードベース全体を対象にした網羅的なミューテーションスコア計測は範囲外。
- **Stryker / mutmut 等ツール導入 PR**: 外部 mutation testing ツールの導入・設定 PR は本スキルの成果物ではない (導入自体を検討する場合は `research-practices` 等の領域)。

---

## 既知の限界

- **正規表現ベースの偽陽性/偽陰性 (Step 2 静的監査)**: AST を使わないため、複雑な式やマクロ、動的生成コードでは誤検出・見逃しが起きる。critical 判定であっても機械的な確信度は高くない — waiver 手順で人間 (Claude) の判断を挟む設計にしている。
- **対応言語は Python / TypeScript / JavaScript / Go のみ**: それ以外の言語 (Rust, Ruby, Java 等) は §手動チェックリストへの degrade が前提で、スクリプトによる自動判定は効かない。
- **waiver は自己申告**: critical findings / 変異不能 seam を偽陽性・対象外と判断する主体が実装者自身であるため、見逃しを完全には防げない。第三者レビュー (`test-review` / `code-review`) との併用が望ましい。
- **正規表現ベースの構文破壊リスク (Step 2.5 mutation smoke)**: `scripts/mutate_and_run.py` の変異注入も行単位の regex ベースであり、AST を使わない。文字列/コメントのマスキングは 1 行内で完結するため、複数行にまたがる文字列 (Python の triple-quote docstring 等) やブロックコメントの内部を誤って変異させる可能性がある。変異が構文を壊した場合の non-zero exit は「テストが検出した (caught)」と区別が付きにくいため、スクリプトは stderr のエラーメッセージから syntax/build error らしきものを検出し、`notes` に「これは実際のアサーション失敗ではなく構文破壊による可能性がある」旨を明記する — ただし判定 (caught 扱い) 自体は変えない。
- **mutation smoke は unit テスト限定**: integration/E2E/DB テストはコスト・副作用のため Step 2.5 の対象外。それらの検出力を実測したい場合は本スキルの範囲外 (手動またはツール導入の検討が必要)。
- **Phase 3 (test-canon-sync) 未実装**: レビュー指摘の蓄積 (ledger) を test-review の references / evals / rules へ蒸留するフィードバックループは今後の拡張予定。
