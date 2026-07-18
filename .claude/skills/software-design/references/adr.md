# Architecture Decision Records (Nygard)

設計決定を「なぜそう決めたか」が後から読める形で残すための軽量フォーマット。

## なぜ ADR が必要か

- 設計の決定は **一度書かれてしまうとコードからは "なぜ" が読めない**。
- 6 ヶ月後の自分は別人。チームに新メンバが入る。同じ議論を繰り返す。
- ADR は **議論のスナップショット**。結論だけでなく **却下した選択肢** を残すのが本質。

## Nygard 形式（最小）

```markdown
# ADR-NNNN: <title>

- Date: YYYY-MM-DD
- Status: Proposed | Accepted | Deprecated | Superseded by ADR-MMMM

## Context
<問題と制約。3〜10 行。「いつ・どこで・誰が」を含める。前提（読者が知らない事情）を簡潔に。>

## Decision
<採用した方針。命令形 / 断定形。1〜3 行が理想、長くて 10 行。>

## Consequences
<結果として何が良くなり、何が悪くなるか。Positive / Negative / Neutral 別に箇条書き。>
```

## 推奨拡張

### Considered Options

決定の質を上げるために必須に近い拡張。

```markdown
## Considered Options
1. **<案 A>** — <内容 1 行>
   - Pros: ...
   - Cons: ...
2. **<案 B>** — <内容 1 行>
   - Pros: ...
   - Cons: ...
3. **<案 C>** — ...

## Decision
<どの案を選んだか + 1〜3 行の根拠>
```

却下案を書くのが ADR の真価。書かないと半年後に同じ案を別人が再提案する。

### Drivers / 制約

決定を駆動した特性を明示：

```markdown
## Drivers
- 最重要: <-ility 1 つ>
- 副次: <-ility 1 つ>
- 制約: <技術的・組織的・予算的制約>
```

### Stakeholders

```markdown
## Stakeholders
- 提案: <name>
- 承認: <name(s)>
- 関係チーム: ...
```

## 運用ルール

### ファイル配置と命名

- 場所: `docs/adr/` を既定（プロジェクトに既存場所があればそれに従う）。
- 名前: `NNNN-<kebab-title>.md`。`NNNN` は **0001 から連番**。連番は予約。穴を埋めない。
- タイトル: 60 字以内、命令形か断定形（"Use X for Y"、"Adopt CQRS for orders"、"Reject microservices for v1"）。

### ステータス遷移

- **Proposed**: 議論中。draft。
- **Accepted**: 合意済 / 適用中。書き換え禁止。
- **Deprecated**: 使われなくなった。代替がない場合に使う。
- **Superseded by ADR-MMMM**: 別 ADR で覆された。`Decision` 末尾に `**Superseded by ADR-MMMM (YYYY-MM-DD).**` を追記する。本文は書き換えない（履歴として残す）。

### 1 ADR 1 決定

- 1 つの ADR には 1 つの決定だけ書く。複合決定は分割。
- 「採用も却下も同じ ADR」は OK（"Use X over Y" は X 採用 + Y 却下の 1 決定）。
- 「全く別の論点を併記」は分割。

### 何に対して書くか

- 「6 ヶ月後の自分が "なぜ?" と聞き返す決定」すべて。
- 採用も却下も書く。**特に却下を書く。** 誰もが踏みに来る道。
- 自明な決定（"`tsconfig.strict: true` にする"）は書かなくていいが、議論があったら書く。
- ADR は **増やしてよい**。多すぎることより少なすぎることを心配する。

## レビュー観点

- 1 ADR 1 決定になっているか
- "Considered Options" に却下案が複数あるか
- "Consequences" に Negative が書かれているか（Positive だけは怪しい）
- "Drivers" に -ility が書かれているか
- ステータスが Accepted の ADR を後から書き換えていないか（Superseded で新規 ADR を起こす）
- 連番に穴がないか / 重複がないか
- ファイル名・配置が規約通りか
