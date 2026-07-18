# PRD: {{title}}

## Meta

```yaml
slug: {{slug}}
created: {{ISO8601}}
updated: {{ISO8601}}
author: {{author}}
status: draft           # draft | reviewing | revising | approved | archived
change_type: {{change_type}}      # new_product | new_feature | enhancement | prd_revision
customer_type: {{customer_type}}  # external | self | self-and-close-circle | mix
self_only: {{self_only}}          # true | false
blast_radius: {{blast_radius}}    # sandbox | personal-public | business | irreversible
handoff_to: requirements
review_skill: prd-review          # 別 agent で起動する想定
related:
  prior_prd: {{prior_prd_path|null}}
  notes: []
  competitor_links: []
  linear_urls: []
```

---

## 1. Why now / Outcome

### きっかけ

{{trigger_narrative}}

<!-- 1〜3 段落。「なぜ今これを問うているか」。直近で起きた具体的な出来事を必ず 1 つ以上含める -->

### 動かしたい outcome（1 つに絞る）

- **outcome**: {{outcome_statement}}
- **観測方法 / 指標**: {{outcome_metric}}
- **現状値**: {{baseline}}
- **目標値**（任意）: {{target}}

### Do-nothing baseline

3 ヶ月何もしなかった場合、何が起きるか:
{{do_nothing_baseline}}

### 戦略 / 大方針との接続

{{strategic_fit}}

<!-- 個人プロジェクトなら「自分の今期の優先テーマとどう紐づくか」でも可 -->

---

## 2. Customer

### 一次顧客

- 顧客タイプ: {{customer_type}}
- 具体像（誰が / どんな状況で）: {{persona}}

### Jobs to be done

- ジョブ: {{jobs_statement}}
- 状況・トリガ: {{job_context}}

### Specific instance（直近 2 週間で実際に起きた瞬間）

{{specific_instance}}

<!-- 日時 / 場所 / 何が起きたか / 何を感じたか。1 件以上、外部顧客なら 2 件以上推奨 -->

### Alternative observed（今やっている代替行動）

- {{alternative_1}}
- {{alternative_2|optional}}

### 顧客=自分自身モード Self-check（customer_type が self / self-and-close-circle / mix のとき必須）

```yaml
specific_instance_recorded: pass | fail
inversion_check: pass | fail | self_only_declared
alternative_observed: pass | fail
viability_self_check: pass | fail
overall: ok | weak
```

詳細は `references/customer-is-self.md` 参照。`overall: weak` のまま prd-review に渡してよいが、レビュー側はここを起点に bias 指摘を行う。

---

## 3. Opportunities（最大 4 件、顧客痛点で書く / feature 名で書かない）

### O1. {{opportunity_title}}

- 痛点: {{pain_description}}
- outcome への接続: {{link_to_outcome}}
- 候補ソリューション:
  - S1a: {{solution_candidate}}
  - S1b: {{solution_candidate|optional}}

### O2. ...

### 落としたもの / 統合したもの

- {{rejected_opportunity}} — 理由: {{rejection_reason}}

---

## 4. Solution direction（spec ではない）

### 大きな方針

{{solution_direction}}

<!-- 段落 1〜2 つ。具体的な機能名を出して良いが、関数 / API / schema / 画面遷移詳細は書かない -->

### 検討した代替と却下理由

| 代替 | 却下理由 |
|---|---|
| {{alt_1}} | {{reason_1}} |
| {{alt_2}} | {{reason_2}} |

### スコープ外（won't）

- {{out_of_scope_1}}
- {{out_of_scope_2}}

---

## 5. Assumptions & Riskiest test

### 4 リスク（INSPIRED）

| リスク | 未検証の一番痛い前提 |
|---|---|
| value | {{value_assumption}} |
| usability | {{usability_assumption}} |
| feasibility | {{feasibility_assumption}} |
| viability | {{viability_assumption}} |

### Riskiest assumption

> {{riskiest_assumption}}

理由（なぜ他より riskiest か）: {{why_riskiest}}

### 直近で打つ falsification test

- 実験名: {{test_name}}
- 期間: {{duration}}（1 週間以内推奨）
- 方法: {{method}}
- 「これが見えたら前提は false」: {{falsification_signal}}
- 期待コスト: {{cost}}

---

## 6. Success / Anti-goals

### Leading indicator（早く動く / 行動レベル）

- {{leading_1}}
- {{leading_2|optional}}

### Lagging indicator（遅く動く / 結果レベル）

- {{lagging_1}}

### Anti-goals（これが見えたら逆効果）

- {{anti_goal_1}}
- {{anti_goal_2|optional}}

<!-- ethical / 依存助長 / プライバシー悪化 / 自分の生活負荷増 などをここに混ぜる -->

---

## 7. Open questions（要件定義へ持ち越し / `[TO_VALIDATE]` 上限 5）

- [TO_VALIDATE: {{question_1}}]
- [TO_VALIDATE: {{question_2|optional}}]

---

## 8. Decision log

| 日付 | 変更 | 理由 / 学び |
|---|---|---|
| {{ISO_DATE}} | initial draft | — |
<!-- revise 時は新しい行を追加 -->
