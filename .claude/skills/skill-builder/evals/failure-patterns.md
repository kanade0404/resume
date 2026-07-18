# Failure Pattern Ledger

skill-builder Mode B / Mode C の反復で観測された失敗クラスを横串で蓄積する。
新規修正前に必ず本台帳をスキャンし、既存パターンに当てはまるかを確認する。
3 回以上再発するパターンは構造的シグナルとして発散判定の入力になる。

参照: [mizchi/skills empirical-prompt-tuning](https://github.com/mizchi/skills/blob/main/empirical-prompt-tuning/SKILL-ja.md)

エントリ形式：

```
- **<Pattern 名>**: 短い記述
  - Example: 代表 Issue
  - General Fix Rule: class レベルの修正則
  - Seen in: <skill>:<iter / case id> ...
```

---

## Patterns

- **weak-verb-passes-through**: description 内の起動条件に強い動詞（レビュー / 監査）しか書かれておらず、口語の弱い動詞（チェック / 見て / 確認 / どう?）で起動が漏れる
  - Example: t06 `supabase/tests/messages.sql をチェック` — ファイルパスは description に明記されているのに「チェック」では起動しない
  - General Fix Rule: should-use リストに口語動詞のバリエーション（チェック / 確認 / 見て / どう? / 不安 / 気になる）を併記する。あるいは「ファイルパスが <pattern> なら動詞によらず起動」と先行ルールを置く
  - Seen in: test-review:harness-2026-04-29:t06

- **sentiment-not-action**: ユーザーが感想・懸念を表明するだけで明示的な行動指示がないと、Claude が「同意して終わる」挙動になり skill を起動しない
  - Example: t07 `このエージェント eval が雑な気がするんだけど` — 「雑な気がする」は感想止まり、レビュー依頼として認識されにくい
  - General Fix Rule: description に「テスト/eval への懸念表明（雑 / 不安 / 怪しい / 大丈夫? / 気になる）も該当」と明示的に書く
  - Seen in: test-review:harness-2026-04-29:t07

- **keyword-overreach** *(解消済み、再発ウォッチ用)*: テスト関連キーワード（pytest / テスト / RLS）に description が反応しすぎ、実装作業（並列化 / 移行 / 基盤改善）まで巻き込む
  - Example: t17 `pytest の実行が遅いから並列化したい` — 改訂前に FP
  - General Fix Rule: description に negative space を 1 文以上置く（「実装作業は範囲外、本スキルは『読んで指摘する』レビュー専用」）
  - Seen in: test-review:1-rater-2026-04-26:t17, t20 → 2026-04-27 で解消

- **dual-meaning-verb-by-action**: 除外を動詞単位で線引きすると両義語（「チェック」「確認」「見て」「OK?」）が境界に落ちて trigger が揺れる。動詞ではなく **成果物** で除外を定義すべき
  - Example: t06 introspection で subagent が「チェック」を review か lint/run か判断保留
  - General Fix Rule: negative space は「書く / 直す / 移行 / 並列化 / 基盤改善」のような **成果物**で除外する。動詞自体は除外条件に使わない
  - Seen in: test-review:dogfood-2026-04-30:subagent-A

- **severity-threshold-undefined**: skill 出力フォーマットに severity 階層（Critical / Major / Minor）があるのに、各階層に振り分ける判定軸が SKILL.md 本体に書かれていない
  - Example: 「Critical / Major の閾値が定義されていない」(subagent B 不明瞭点 #1)
  - General Fix Rule: 階層を持つ出力フォーマットには「<階層名> = <判定軸>」を 1 行ずつ本体に書く（例: 「Critical = merge をブロックするか」）。references に委譲しない
  - Seen in: test-review:dogfood-2026-04-30:subagent-B

- **zero-finding-handling**: 固定フォーマットの章で finding が 0 件のときの書き方が指定されていないと、書き手都合で空欄か「該当なし」かがブレる
  - Example: 「What's good」がゼロ件時の扱い不明（subagent B 不明瞭点 #2）
  - General Fix Rule: 固定フォーマットの各章末に「0 件時は『該当なし』と明記」のような **空集合の表記法**を仕様化する
  - Seen in: test-review:dogfood-2026-04-30:subagent-B
