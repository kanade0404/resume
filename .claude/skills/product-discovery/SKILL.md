---
name: product-discovery
description: >-
  要求定義 (PM フェーズ) を進め、ユーザの「やりたい / 困っている」を Outcome > Output で言語化して Lean PRD を
  docs/prd/<slug>.md に書き出す skill。INSPIRED の 4 リスク (value / usability /
  feasibility / viability)、Continuous Discovery Habits の Opportunity Solution
  Tree と Riskiest Assumption Test、Escape the Build Trap の outcome 重視・feature
  factory 回避を doctrine とする。顧客が自分自身であるパターンも一級扱いし、自己ヒアリングのバイアス除去プロトコルを内蔵する。発火例 —
  「〜を作りたい」「〜が欲しい」「アイデアがある」「〜って作るべき?」「PM 視点で整理して」「要求まとめて」「PRD 書いて」「PRD
  ドラフト」「discovery 回したい」「opportunity 整理」「outcome 何にする?」「riskiest assumption
  は?」「自分用ツール作りたい」。要件定義 (spec / 要件) を直接書く依頼、実装方針の検討、UI 仕様の確定、コード生成、API
  設計、データモデル詳細は本スキル範囲外で、それぞれ requirements skill / design / data-modeling skill
  等に委ねる。ドラフト後は別 agent の prd-review skill にレビューを渡し、合意済み PRD を入力に requirements
  skill を起動する想定。アドホックに要求整理するより本スキルを優先する理由は、build trap を防ぎ outcome / opportunity
  / assumption の三層を欠落なく PRD に揃え、下流レビュー・要件定義への引き継ぎ品質を担保するため。
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - WebFetch
  - WebSearch
  - AskUserQuestion
  - TaskCreate
  - TaskUpdate
  - TaskList
  - Agent
---
# product-discovery

要求定義（要件定義の前段、PM フェーズ）を進める skill。ユーザの発話を起点に Outcome → Opportunity → Assumption の三層に整理し、最終的に **Lean PRD** を `docs/prd/<slug>.md` として書き出す。下流の `prd-review` skill（別 agent）でレビューを受けて revise し、合意後に `requirements` skill（要件定義）を起動するハンドオフを前提にする。

なぜこの skill が必要か: 開発の失敗のほとんどは「要件 (spec) の精度不足」ではなく「**要求 (request) の段階で outcome と opportunity を捉え損ねたこと**」に起因する。INSPIRED / Continuous Discovery Habits / Escape the Build Trap の 3 書はいずれも、build trap（output 中心の量産）を抜けるには discovery を独立した工程として持てと説く。本 skill はその discovery を 1 セッション内で再現する PM 補助線である。

詳細レイヤ:
- `references/inspired-cdh-build-trap.md` — 3 書を本 skill 用に蒸留した doctrine
- `references/customer-is-self.md` — 顧客が自分自身のパターンの bias 除去プロトコル
- `references/triage-decision.md` — 起動 / 別 skill へ振る判定木
- `references/handoff-protocol.md` — prd-review / requirements への引き渡し仕様
- `assets/prd-lean.md.tpl` — PRD テンプレート

---

## いつ使うか

以下を強くトリガとする:

- 「〜を作りたい / 欲しい / 試したい」「アイデアがある」「ぼんやり構想中」
- 「これって作るべき?」「やる価値ある?」「PMF ありそう?」
- 「PM 視点で整理して」「要求 / requirement をまとめて」「PRD 書いて / ドラフト」
- 「discovery 回したい」「opportunity 整理」「outcome 何にする?」
- 「riskiest assumption は?」「value risk チェックして」
- 「自分用ツール作りたい」「自分が困ってるから」（顧客=自分自身）
- slash command `/product-discovery` または明示で本 skill 名を呼ばれた時

**使わない場面**:

- 既に PRD / 要求が固まっており、**仕様 (spec / 要件)** を書きたい — `requirements` skill
- PRD を書き終え、**レビュー**にかけたい — `prd-review` skill
- 単なる**実装着手の段取り** — feature-dev / design 系
- 単純な**事実調査・ライブラリ比較** — `research-practices` skill
- **テスト・コード品質**の話 — `test-review` / `simplify` 等

迷う境界は §Phase A の triage で振り分ける。

---

## 入力

- ユーザの自然文発話（「〜したい」「〜で困っている」「〜って作るべき?」など断片で可）
- 任意: 既存 PRD, ノート, Linear issue リンク, 音声書き起こし などの素材
- 任意: 顧客タイプ指定（外部 / 自分自身 / 混在）。未指定なら Phase A で確認

PRD 出力先は **常に `docs/prd/<slug>.md`**（Linear など外部ツールへの転記はユーザが手動 or 将来の Linear MCP 連携拡張で行う想定。本 skill は file-based に閉じる）。

---

## ワークフロー

```text
[Phase A: triage]          ── 顧客 / 起動可否 / 既存 PRD diff か新規か
   ↓
[Phase B: outcome framing] ── 動かしたい outcome を 1 つに絞る (Build Trap 防御)
   ↓
[Phase C: opportunity]     ── OST 軽量版で 2〜4 の opportunity を立てる
   ↓
[Phase D: assumption]      ── 4 リスク + riskiest assumption + 直近で打つテスト
   ↓
[Phase E: synthesis]       ── assets/prd-lean.md.tpl に流し込み docs/prd/<slug>.md に書く
   ↓
[Phase F: handoff]         ── prd-review skill 起動を提案、合意後 requirements 案内
```

### Phase A: triage（ユーザ対話 1 回）

`AskUserQuestion` を **冒頭で 1 回だけ** 使い、以降は本文に `[ASSUMED: ...]` `[TO_VALIDATE: ...]` を埋めて完走する（discovery の勢いを切らさない）。

冒頭 1 回で揃えるべき情報は以下。複数の問いを 1 ターンに束ねる:

1. **change_type 相当**: 新規プロダクト / 新規機能 / 既存機能の改善 / 既存 PRD の改訂 のいずれか
2. **顧客タイプ**: 外部ユーザ / 自分自身 / 混在
3. **不可逆性 / blast radius**: 本人のサンドボックス / 個人公開ツール / 業務影響あり
4. **既存素材の有無**: ノート, 音声, 過去 PRD, 競合プロダクトのリンクなど

判定の詳細は `references/triage-decision.md`。triage 結果が「本 skill 範囲外」なら（例: 仕様レベルの要件を書きたい、テストレビューをしたい）速やかに該当 skill を案内して終了する。

triage 結果は PRD §Meta に記録する。

### Phase B: outcome framing（Build Trap 防御）

「何を作るか」を聞く前に「**何を動かしたいか**」を聞く。これを飛ばすと build trap に直行する。

確認する観点:

- 動かしたい指標 / 状態変化（「自分が週 3 回やっていた手作業を 0 にする」「家族が翌日にも料理を再現できる」など、観測可能な行動 or 数値）
- 現状値 / 直近の悲しさ
- 戦略・大方針との接続（個人プロジェクトなら「自分の今の生活で何を優先しているか」でも可）
- **もし何もしなかったら 3 ヶ月後どうなるか**（do-nothing baseline）

「outcome が thin」（output を言い換えただけ）と検出したら **Phase B で停滞させて深掘りする**。代表アンチパターン:

- 「Slack bot を作りたい」→ 動かしたい outcome は? 何を Slack 経由で速くしたいのか
- 「ダッシュボードが欲しい」→ どの意思決定を速くしたいのか
- 「LLM agent を組みたい」→ 結果として何を 5 分から 30 秒にしたいのか

詳細な doctrine は `references/inspired-cdh-build-trap.md` の §Build Trap 節。

### Phase C: opportunity shaping（OST 軽量）

Continuous Discovery Habits の Opportunity Solution Tree を **軽量版** で適用する。書き出すのは PRD ではなく**頭の中の枝分かれ**。

- desired outcome（Phase B 結果）の下に **opportunity を最大 4 件** 並べる（多すぎたら統合 / 落とす）
- 各 opportunity に対し **solution candidate を 1〜3 件** ずつ持つ
- 「このソリューションがダメなら次に何を試すか」が言える状態にする（早期固定の回避）

opportunity の良し悪しの目安:

- **specific instance** から導かれている（「家族が前にこう困った」のような **具体痛点** が起点）
- 動かしたい outcome に明確に紐づく
- 顧客が**今すでにやっている代替行動**が観察できている（CDH の「customer は今何をして埋め合わせているか」）

アンチパターン:

- opportunity が「機能名」になっている（それは solution）
- opportunity が複数 outcome を兼ねている（細分化しろ）

### Phase D: assumption + riskiest test

INSPIRED の 4 リスクで未検証前提を棚卸しする:

| リスク | 問い |
|---|---|
| **value** | 顧客はそもそも欲しがるか / 使ってくれるか |
| **usability** | 使いこなせるか / 認知負荷は越えられているか |
| **feasibility** | 技術的に作れるか / 期間内に出せるか |
| **viability** | プロダクト全体・ビジネス・自分の生活で成立するか（個人なら維持コスト含む） |

各リスクで「現時点で **検証されていない** 一番痛い前提」を 1 つずつ書く。さらに:

- **riskiest assumption**: 上記から「これがウソなら全体が崩れる」を 1 つ選ぶ
- **直近で打つテスト**: その前提を 1 週間以内に falsify するなら何をするか（簡易プロトタイプ / 自己観察ログ / 紙芝居 / インタビュー 1 人）

CDH の Assumption Mapping を圧縮した形。詳細は `references/inspired-cdh-build-trap.md` §Assumption Mapping。

顧客=自分自身の場合、ここで bias check を必ず通す（次節 + `references/customer-is-self.md`）。

### Phase E: synthesis（PRD 起こし）

`assets/prd-lean.md.tpl` を読み込み、Phase A〜D の内容を埋めて `docs/prd/<slug>.md` に書き出す。

- `<slug>` は input から `kebab-case` で 2〜4 語の識別子を AI が生成（例: `weekly-recipe-bot`）
- 既存ファイルがある場合は **改訂モード**: 既存内容を読んで diff として書き、§Decision log にエントリを追加
- **抽象度を要求レベルに保つ**: 関数シグネチャ, API 仕様, データスキーマ, 画面遷移詳細などの **spec / 設計詳細** を本文に書かない（要件定義 / 設計フェーズの仕事）
- 不明点は `[TO_VALIDATE: 具体的な質問]` で本文に残す（要件定義へ持ち越す）
- §Anti-goals（「これが見えたら逆効果」）を必ず 1 件以上書く（success metric の hack 防止）

### Phase F: handoff

完了報告でユーザに以下を渡す:

1. 生成 / 更新した artifact path（`docs/prd/<slug>.md`）
2. 要約 3 点（outcome / 上位 opportunity / riskiest assumption）
3. **次の動き**:
   - `prd-review` skill にレビューを依頼する案内（別 agent で起動する想定。本 skill からは自動起動しない）
   - レビュー指摘で revise が必要なら本 skill を再起動 → §Decision log に追記
   - PRD が approved になったら `requirements` skill を起動して要件定義へ
4. 残った `[TO_VALIDATE]` の数（あれば内容）

ハンドオフ仕様の詳細は `references/handoff-protocol.md`。

---

## ユーザターン最小化の原則

- ユーザに尋ねるのは **Phase A の triage 1 回のみ** が既定
- 例外: triage 結果が本 skill 範囲外（→ 別 skill 案内のための確認）/ 既存 PRD と矛盾する入力 / 上限超過の `[TO_VALIDATE]`
- それ以外は **Phase A→B→C→D→E→F を 1 ターンで完走** して完了報告
- 不明点は `[ASSUMED: ...]` `[TO_VALIDATE: ...]` を本文に埋め、上限内（Lean PRD なら `[TO_VALIDATE]` 上限 5 件）なら自動進行

---

## 顧客=自分自身モード

個人プロダクト・社内ツール・実験コードなど、顧客が自分自身（または家族・身近な少人数）であるケースは**むしろ多数派**として扱う。「customer interview しろ」式の杓子定規を持ち込まず、自己観察のままで rigor を担保する。

最低限の bias check（詳細プロトコルは `references/customer-is-self.md`）:

- **specific instance**: 直近 2 週間で「実際に起きた瞬間」を最低 1 つ書ける
- **inversion**: 「自分でない別の人だったらこの outcome を欲しがるか」を仮定で答え、答えが no ならスコープを「自分専用」と Meta に明記
- **alternative observed**: 今すでにやっている代替行動を 1 つ以上挙げる
- **viability self-check**: 維持コスト（自分が運用できるか / 半年後も触るか）を 1 行で書く

これらが埋まらない PRD は §Self-check を `weak` とマーキングして prd-review に渡す。

---

## 出力

| パス | 条件 | 内容 |
|---|---|---|
| `docs/prd/<slug>.md` | 常時 | Lean PRD（`assets/prd-lean.md.tpl` 由来） |
| ユーザへの完了報告 | 常時 | artifact path / 3 点要約 / handoff 案内 |

PRD 自体に self-check ブロックを内蔵する（prd-review が読む契約）。

---

## このスキルがやらないこと

negative space は **動詞ではなく成果物** で書く（`skill-builder` の `dual-meaning-verb-by-action` 原則）:

- **要件 (spec) ファイル `z/{task}/requirements.md` 相当** を生成しない（→ `requirements` skill）
- **設計ドキュメント / 関数シグネチャ / API 定義 / Prisma schema** を本文に書かない（→ design / data-modeling）
- **コード / テスト / config** を生成しない
- **`prd-review` skill を自動呼び出ししない**（別 agent で明示起動する設計; 自動チェーンは討論の独立性を壊す）
- **Linear / Notion / Jira への直接書き込みを行わない**（本 skill は file-based。MCP 連携が必要なら拡張で）
- **discovery を打ち切る判断（「やめる」）を skill 単独で出さない** — riskiest assumption が崩れた時の判断はユーザに委ねる

---

## 連携 skill

| skill | 役割 | 起動タイミング |
|---|---|---|
| `prd-review`（別 agent / 別 skill） | PRD のレビュー（must / imo） | 本 skill 完了後ユーザが明示起動 |
| `requirements` | 要件定義（spec, EARS, 影響範囲） | PRD approved 後にユーザ起動 |
| `research-practices` | 競合 / 先行事例 / ライブラリ調査 | Phase B/C/D で外部根拠が必要なときのみ |
| `skill-builder` | 本 skill の trigger / quality 改善 | 本 skill の改修時 |

`prd-review` / `requirements` は本 skill から自動起動しない（auto mode 親和とレビュー独立性のため）。

---

## 言語

CLAUDE.md に従い、ユーザとのやり取りおよび PRD 本文は **日本語**。slug と frontmatter / メタキーは英小文字 + ハイフン。

---

## リファレンス

- `references/inspired-cdh-build-trap.md` — 3 書の doctrine 蒸留
- `references/customer-is-self.md` — 顧客=自分自身パターンの bias 除去
- `references/triage-decision.md` — Phase A 判定木と別 skill への振り分け
- `references/handoff-protocol.md` — prd-review / requirements への引き継ぎ仕様
- `assets/prd-lean.md.tpl` — Lean PRD テンプレート
- `evals/product-discovery-trigger.json` — trigger eval 雛形（skill-builder Mode B で利用）
