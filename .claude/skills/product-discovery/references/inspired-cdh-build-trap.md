# INSPIRED / Continuous Discovery Habits / Escape the Build Trap — doctrine

本 skill が依拠する 3 書のエッセンスを **discovery セッションで実際に問える形** に蒸留したもの。元書の網羅的解説ではなく、PRD ドラフト中に「次に何を聞くか」を即決するための短い参照。

3 書の関係:

- **Escape the Build Trap (Melissa Perri)** — 「なぜ output 中心が失敗するのか」のフレーミング。組織論寄り。
- **INSPIRED (Marty Cagan)** — discovery と delivery を分ける思想 + 4 リスク分類。
- **Continuous Discovery Habits (Teresa Torres)** — 上記を実務に落とすための **習慣** と **OST**。

本 skill では **Build Trap → INSPIRED の 4 リスク → CDH の OST + Riskiest Assumption Test** の順で適用する。

---

## §Build Trap（Escape the Build Trap）

### 定義

「機能をたくさん出すこと」自体を成果と勘違いし、outcome（顧客の状態変化 / ビジネス指標）から切り離されて output（リリース数 / 機能数）を量産する状態。

### 検出シグナル（Phase B で疑え）

- 入力が**動詞 + 目的語の機能名**で来る（「Slack bot を作る」「ダッシュボード」「LLM agent」）
- 「いつまでに」「何を」だけが議論されており、「**それで何が良くなるのか**」が空白
- 既存機能を量産しても顧客の行動が変わらない実例がある（社内・前職経験・本人観察）
- 「他社が作っているから」「最近流行っているから」が動機

### 防御の問い

1. これを作らなかったら 3 ヶ月後どうなる? どこが具体的に困る?
2. 動かしたい outcome を 1 つに絞ると何? 観測可能か?
3. 同じ outcome を別の解で動かせないか? 安いほうから試したか?

「**outcome のない feature は spec 化しない**」を Phase B で守る。outcome が thin な状態で Phase C に進ませない。

### Product Kata（Perri）

「`現在地 → 目標 → 障害 → 次のステップ → 学び`」のループ。本 skill では:

- 現在地 = Phase A の triage 結果
- 目標 = Phase B の outcome
- 障害 = Phase C の opportunity
- 次のステップ = Phase D の riskiest test
- 学び = revise 時に PRD の §Decision log に書く

---

## §INSPIRED の 4 リスク

Cagan の主張: 製品開発の失敗のほとんどは以下 4 種に集約される。**discovery とはこれらを並行で潰す活動**である。

| リスク | 問い | discovery 手段の例 |
|---|---|---|
| **value risk** | 顧客はそもそも欲しがるか / 使うか / 金 or 時間を払うか | プロトタイプ反応, 価格提示, アナログ実験 |
| **usability risk** | 使いこなせるか / 認知負荷を越えられるか | クリック可能 prototype, タスク観察, 紙芝居 |
| **feasibility risk** | 期間 / 技術 / インフラで作れるか | spike, tracer bullet, 外部 API 検証 |
| **viability risk** | プロダクト全体・ビジネス・運用で成立するか（個人なら維持コスト） | コスト試算, 法務 / ポリシー確認, 運用負荷見積 |

### 本 skill での扱い（Phase D）

- 各リスクで「**現時点で未検証の一番痛い前提**」を 1 つずつ書かせる
- 4 つのうち **riskiest assumption** を 1 つ選ぶ（複数選ばない — 集中が崩れる）
- 1 週間以内で打てる falsification test を 1 つ書く

### 落とし穴

- value だけを論じて feasibility / viability を書き忘れる（個人プロダクトで多い: 「自分が欲しい」止まり）
- usability を「UI が綺麗か」と誤読しない。**学習コスト + 認知負荷** の話
- viability に「**自分が半年後も触るか**」を含めるのを忘れない（顧客=自分自身モード）

---

## §Continuous Discovery Habits

### Opportunity Solution Tree (OST)

```text
Outcome
 ├── Opportunity 1
 │    ├── Solution candidate 1a
 │    └── Solution candidate 1b
 ├── Opportunity 2
 │    └── Solution candidate 2a
 └── Opportunity 3
      └── ...
```

ルール:

- **outcome は 1 つ**。複数 outcome を 1 PRD に詰めない
- opportunity は **顧客の言葉 / 痛点 / jobs to be done** で書く（機能名で書かない）
- solution は **opportunity ごとに複数候補** を持つ（早期固定の回避）
- assumption test は solution ごとに付ける（CDH 原書では assumption 層が下にある）

本 skill は Phase C で軽量化し、最大 4 opportunity × 各 1〜3 solution まで。

### Continuous の意味

CDH の核心は **「週 1 回顧客に触れる」習慣**。本 skill は **1 PRD を書く瞬間** にしか動かないので continuous 性は担保できない。代わりに以下を埋め込む:

- §Open questions に「次の touchpoint で確認したいこと」を残す
- §Decision log で revise 時に「この回で何を学んだか」を書く
- 顧客=自分自身モードでは「自己観察ログを継続するか」を viability の一部として書く

つまり本 skill は **continuous の 1 点** を切り取る役割。連続性はユーザの運用側に委ねる。

### Assumption Mapping

CDH 原書では desirability / viability / feasibility / usability / **ethical** の 5 軸（INSPIRED の 4 + ethical）。本 skill では:

- 4 リスクは Phase D で必ず書く
- ethical は **§Anti-goals** として「これが見えたら逆効果」のスロットに混ぜる（差別 / 依存助長 / プライバシー悪化など、出力前に毎回点検）

### Riskiest Assumption Test (RAT)

「assumption を 1 つだけ選び、それを最も安く falsify する 1 実験」。本 skill では Phase D で 1 件強制書き出し。書けないなら opportunity / solution が抽象すぎる証拠 → Phase C に戻る。

---

## §3 書を Phase に対応づけた早見表

| Phase | 主な doctrine | 落ちやすい罠 |
|---|---|---|
| A triage | — | 仕様レベルの依頼を本 skill で受け取って、要件定義の skill に渡しそびれる |
| B outcome | Build Trap, Product Kata | outcome に output を流し込む（言い換え） |
| C opportunity | OST, jobs-to-be-done | opportunity が feature 名になる |
| D assumption | INSPIRED 4 risk + RAT, Assumption Mapping | viability / 維持コストの欠落 |
| E synthesis | — | spec / 設計詳細を PRD に書いてしまう |
| F handoff | continuous の 1 点切り取り | 自動チェーン化してレビュー独立性を壊す |

---

## 参考

3 書の原本に当たる必要があれば本 skill から **`research-practices`** を呼ぶ。本 skill 自体は 3 書の解釈に閉じる。
