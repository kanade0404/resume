---
name: skill-builder
description: Claude Code skill を新規作成・既存 skill のトリガ精度を測定/改善するためのメタスキル。プロジェクトの skill ディレクトリ（`.claude/skills/<name>/SKILL.md` または top-level `<name>/SKILL.md` の両形式に対応）に新しい skill を scaffold したい時、既存 skill が適切なときに発火しない / 余計な時に発火するのを直したい時、description を eval ベースで最適化したい時、trigger 性能をベースライン測定したい時、Mode C で起動後の本文品質を subagent dispatch で測りたい時、いずれでも必ず起動すること。「skill 作って」「このスキルなんで起動しない」「スキルが暴発する」「skill description 最適化」「skill の eval 作って」「メタスキル」「skill の品質測りたい」のような要請に該当する。プロジェクト規約 (CLAUDE.md / `rules/` / `AGENTS.md` 等) との整合確認も兼ね、特定プロジェクトには依存せず本スキルが置かれたリポジトリと配布先の双方で機能する。プラグインスキル（`plugins/<plugin>/skills/...`）の編集は範囲外。
claudecode:
  allowed-tools:
    - Read
    - Write
    - Edit
    - Glob
    - Grep
    - Bash
    - TaskCreate
    - TaskUpdate
    - TaskList
    - AskUserQuestion
---

# Skill Builder

公式 `skill-creator` の発想を踏襲しつつ、軽量・プロジェクト非依存のメタスキル。subagent や外部 LLM を立てずに、**1 セッション内で完結する eval ループ**を回す。

rulesync で `kanade0404/skills@<tag>` から `skills/skill-builder/` として配布される前提で project-agnostic に書く。プロジェクト規約ファイル（CLAUDE.md / `rules/`, `docs/`, `AGENTS.md` 等）への整合は consumer 側の規約として参照する。

主参照：
- [Anthropic Agent Skills best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)（公式の規範）
- [mizchi/skills empirical-prompt-tuning](https://github.com/mizchi/skills/blob/main/empirical-prompt-tuning/SKILL-ja.md)（subagent 派生）

外部 skill-creator との位置付け：

- 公式 skill-creator は汎用かつ重装備（並列 subagent、blind A/B comparator、HTML viewer）。新規プラグイン公開を想定。
- 本スキルは **ローカル skill ディレクトリを運用するための最小ループ**。プロジェクト規約 (CLAUDE.md 等) への整合、description 設計、trigger / quality の eval を担保する。プロジェクト固有のドクトリンには立ち入らず、規約ファイルがあれば参照しに行くだけにとどめる。

---

## 適用範囲

対象はプロジェクトスキル全般。配置形式は次のいずれにも対応する：

- consumer プロジェクト形式: `.claude/skills/<name>/SKILL.md`
- skill カタログ形式 (rulesync 配布元): `skills/<name>/SKILL.md`

プラグインスキル（`plugins/<plugin>/skills/...`）の編集はこのスキルでは扱わない（plugin-dev 系の専用スキルに委ねる）。本スキルは現在のリポジトリ構造を `git ls-files` 等で検出し、検出された配置形式に合わせて出力先を決める。

スキル本体は **500 行以内**を目安に保つ。越える場合は `references/<topic>.md` に切り出し、本文は「いつ参照しに行くか」のみ書く（progressive disclosure 第 3 層）。

### Frontmatter 規約（Anthropic 公式）

- `name`: 64 文字以下 / 小文字・数字・ハイフンのみ / XML タグ不可 / 予約語不可（`anthropic`, `claude`）
- `name` は **gerund 形** が推奨（`processing-pdfs` / `analyzing-spreadsheets`）。noun-phrase（`pdf-processing`）も可。`utils` や `tools` のような曖昧な名は不可
- `description`: 1024 文字以下 / 非空 / XML タグ不可
- `description` は **必ず三人称** で書く。`I can ...` / `You can ...` は禁止（system prompt に inject されるため視点ブレで discovery を壊す）
- `description` は **「何をするか」と「いつ使うか」の両方** を含める

---

## 3 つのモード

ユーザの要求から自動で判定する。曖昧なら `AskUserQuestion` で確認する。

| モード | 入力 | 出力 |
|---|---|---|
| `create` | 何をする skill か（自然文） | `<skills-dir>/<name>/SKILL.md` + `<skills-dir>/<name>/evals/<name>-trigger.json` 雛形 (配置形式は検出した構造に従う、Mode B の入力と同じパス) |
| `tune-trigger` | 既存 skill 名 | `evals/<skill>-trigger-results-<date>.json` + description 改訂案 |
| `tune-quality` | 既存 skill 名 + シナリオ | subagent 品質レポート + SKILL.md 改訂案 |

---

## Mode A: create

### Step 1 — 仕様化（インタビュー）

最低限以下を埋める。曖昧なまま書き出さない。

- **発火すべき状況** を具体名詞で 5 件以上（should-use リスト）
- **発火すべきでない類似状況** を 3 件以上（should-skip リスト、negative space）
- **入力の典型形** と **出力フォーマット**
- **既存スキルとの分担境界** — 機能が重なる skill があれば名指しで線を引く
- **依存ツール / MCP** — `allowed-tools` に何を入れるか

プロジェクト固有の確認 (規約ファイルがある場合のみ)：

- CLAUDE.md / `rules/` / `AGENTS.md` / `docs/` 等の規約があれば、新 skill が違反していないか確認する
- 取り扱う対象（テスト / API / プロンプト / インフラ / プロダクト要求 etc.）が既存 skill とどう違うかを名指しで線引きする
- 同領域の既存 skill / agent / slash command があれば、責務境界を frontmatter description に明記する

### Step 2 — frontmatter を書く

`description` は **メタデータではなく learnable parameter**。次を全部入れる：

1. **何を / なぜ** が 1〜2 文で読める導入
2. **発火条件の具体名詞列挙** — ユーザが言いそうな表現 5〜10 種を併記する。`「テスト見て」「このテストいい?」` のような口語の揺れも含める
3. **明確な negative space** — 「〜のときは別の skill を使う」「〜は範囲外」を書く
4. 命令形（imperative voice）で「必ず起動すること」「優先する」と意図を表す

避ける：
- 100 字未満の素っ気ない description（発火率が下がる）
- `ALWAYS` / `MUST` の連発（脆い）
- 既存 skill と紛らわしい同義語の濫用

### Step 3 — 本文を書く

#### Degrees of freedom を選ぶ（Anthropic 公式）

書く分量と硬さを **タスクの脆さ** に合わせる。狭い橋には手すり、広い野原には方向だけ：

| 自由度 | 使う場面 | 形式 |
|---|---|---|
| **High** | 複数アプローチが妥当 / 文脈で判断が変わる | テキストの手順書（"検討ポイント"列挙） |
| **Medium** | 推奨パターンはあるが揺らぎ許容 | パラメータ化された pseudocode / template |
| **Low** | 操作が脆く順序固定が必要 | 厳密なコマンド or スクリプトに丸投げ |

判断基準は **「Claude が書ける/判断できることを書かない」**。`PDF を読み込み → 各ページのテキストを取得` は不要、`pdfplumber を使え` だけで十分（公式の "concise is key" 原則）。

#### 参考構造（同カタログ内の `test-review` / `research-practices` / `product-discovery` を雛形にできる）：

```
# <skill name>

<なぜ必要か。1 段落>

## いつ使うか / 使わない場面
- 発火すべき状況（口語含む）
- 発火しない場面 → 該当 skill 名を明示

## ワークフロー
### Step 1 — ...
### Step 2 — ...
...

## 出力フォーマット
<固定テンプレ>

## このスキルがやらないこと
- 成果物名で除外（動詞ではなく）

## リファレンス
- references/<topic>.md
```

**書き方の原則**：

- 「なぜそうするか」を先に書く。`ALWAYS X` ではなく「X しない場合に Y が壊れるから X する」
- 曖昧・不可視な条件で黙って動作分岐させない（読み手・実行ごとに結果が割れる）。分岐するなら判定基準を**明示・観測可能**にする — Anthropic 公式の Conditional workflow pattern（`Creating?` → A / `Editing?` → B のように観測可能な決定点で分ける）に従う。検証→修正→再検証の feedback loop は推奨
- 詳細レイヤは `references/<topic>.md` に切り出し、本文からは「対象が X のときだけ参照する」と書く
- 出力フォーマットは固定する。スキャンしやすさ優先

### Step 4 — `evals/<name>-trigger.json` 雛形を置く

Mode B の入力になる。詳細は後段。

### Step 5 — レビュー観点（Anthropic 公式チェックリスト準拠）

書き終えたら以下を自己点検する。`[A]` は公式 best-practices の checklist 項目、`[L]` は本スキルが追加するローカル観点：

**Core quality**
- [A] description が具体的で key terms を含む
- [A] description が「何を」「いつ使うか」両方を含む
- [A] description が三人称（`I/You can` 不使用）、≤ 1024 char、XML タグなし
- [A] name が ≤ 64 char、小文字+数字+ハイフンのみ、reserved word（`anthropic`/`claude`）不使用、gerund 形 推奨
- [A] SKILL.md 本体 ≤ 500 行
- [A] 詳細は `references/<topic>.md` に切り出し、リンクは **1 段だけ**深い（孫リンク禁止）
- [A] 時間依存の記述は本文に置かず `<details>` の "Old patterns" セクションへ
- [A] 用語は一貫（同じ概念に複数の語を使わない）
- [A] 例は具体的（抽象例だけにしない）
- [A] 進む手順が複数ステップなら **チェックリストパターン**で書く

**Triggering / boundary**
- [A] description に should-use の典型表現が複数列挙されている
- [L] negative space（やらないこと）が **動詞ではなく成果物** で定義されている（参照: failure-patterns.md `dual-meaning-verb-by-action`）
- [L] consumer プロジェクトの CLAUDE.md / 規約ファイル（`rules/`, `AGENTS.md`, `docs/` 等）と矛盾しない

**Code / scripts（同梱する場合のみ）**
- [A] スクリプトは「Claude に投げない」(solve, don't punt)。エラー処理を内側で持つ
- [A] magic number は理由コメント付き（"voodoo constants" を作らない）
- [A] パス区切りは `/` のみ（Windows パス禁止）
- [A] 必要パッケージを明記、利用可能性を確認

**Testing**
- [A] 評価ケースを **3 つ以上** 用意する
- [A] Haiku / Sonnet / Opus すべてでテスト
- [A] 実シナリオでもテスト済

---

## Mode B: tune-trigger

既存 skill の description を **計測可能な形で**直すモード。

### Step 1 — eval セットを書く

`evals/<skill>-trigger.json` に should-trigger / should-skip ペアを **合計 16 件以上** 作る。

スキーマ：

```json
{
  "target_skill": "test-review",
  "version": "1",
  "cases": [
    {
      "id": "t01",
      "prompt": "...",
      "should_trigger": true,
      "rationale": "発火すべき / すべきでない理由（1 行）",
      "tags": ["explicit", "ambiguous", "edge"]
    }
  ]
}
```

ケース設計の指針：

- **explicit (should_trigger=true)** — 直接的に対象タスクを指定する prompt（4〜6 件）
- **ambiguous (should_trigger=true)** — 口語・省略・「ちょっと見て」系（3〜5 件）
- **adjacent (should_trigger=false)** — 同領域だが対象外の作業（4〜6 件）
- **distractor (should_trigger=false)** — 紛らわしいキーワードを含むが本質的に対象外（2〜4 件）

「false ケース」の作り込みが命。ここが薄いと false positive が見逃される。

### Step 2 — 測定する

各ケースについて、対象 skill の `description` を読んで「Claude がこの prompt でこの skill を起動するか」を判定する。

判定者は次のいずれか：

1. **本セッションの Claude 自身**（軽量・1-rater・即時）。本スキルが扱う既定の経路。
2. `claude -p "<prompt>"` を別プロセスで起動し、ツール呼び出しに `Skill(<target>)` が出るかを観測（重量・N-rater 可・要設定）。Mode B の上位互換だが本スキルでは扱わない。

判定者 1 を使う場合、各 prompt に対して以下を JSON Lines として `evals/<skill>-trigger-results-<YYYY-MM-DD>.jsonl` に追記する：

```json
{"id":"t01","predicted":true,"actual":true,"reason":"description の<具体名詞>に直接マッチ"}
```

### Step 3 — スコアリング

`scripts/score_triggers.py` を走らせて confusion matrix と F1 を出す（Bash 不可な場合は同等の手計算で良い）：

```
TP / FP / TN / FN
precision = TP / (TP + FP)
recall    = TP / (TP + FN)
F1        = 2 * P * R / (P + R)
```

**目安**: F1 < 0.8 は要改善。FP と FN のどちらが多いかで処方が変わる。

### Step 4 — 改善の処方

| 失敗モード | 処方 |
|---|---|
| **FN が多い**（発火しない） | description に should-use 名詞を追加。口語パターンを書き足す。命令形を強める |
| **FP が多い**（暴発する） | negative space を追加。「〜のときは別の skill」と分担を明示。過度な総称語（"分析"、"レビュー"）を具体名詞に置換 |
| **両方多い** | description が漠然としすぎ。担当領域を再定義する。場合により skill を 2 つに分割 |

**やってはいけない処方**：

- 単に `MUST` `ALWAYS` を盛る（脆い・他 skill を圧迫する）
- 失敗したケース 1 件を直接 description に書き写す（過剰適合）
- eval セットを失敗が消えるまで弱める（指標ハック）

### Step 5 — 反復

description を直したら **同じ eval セット**で再測定。F1 が上がっているかを見る。改善が止まったら停止。

3 回反復して頭打ちなら、description ではなく **skill 自体の役割境界**を再考する（Mode A に戻る）。

---

## 出力フォーマット

### Mode A の最終出力

```
# Skill Created: <name>

## Files
- <skills-dir>/<name>/SKILL.md
- <skills-dir>/<name>/evals/<name>-trigger.json (雛形)

## Self-review
- [✓/✗] 500 行以内
- [✓/✗] should-use / should-skip / 分担が description にある
- ...

## Next
- Mode B で初回 trigger eval を回す
```

### Mode B の最終出力

```
# Trigger Tuning: <skill>

## Score
- baseline: P=.., R=.., F1=..
- after edit: P=.., R=.., F1=..

## Failures
### FP (発火すべきでないのに起動した)
- [id] prompt → 推測理由
### FN (起動すべきなのにしなかった)
- [id] prompt → 推測理由

## Description diff
<patch>

## Recommendation
- 追加反復するか / 停止するか
- 役割再定義が必要か
```

---

## Mode C: tune-quality（subagent dispatch、mizchi 派生）

Mode B が「skill が起動するか」だけを見るのに対し、Mode C は「起動後に skill 本文が正しい出力を導けるか」を測る。出典: [mizchi/skills empirical-prompt-tuning](https://github.com/mizchi/skills/blob/main/empirical-prompt-tuning/SKILL-ja.md)。

### なぜ別モードか

trigger=true でも本文が不明瞭なら出力は壊れる。trigger を直したあと **起動後の挙動**を独立に測る。

### バイアス排除の鉄則

- 対象 skill を書いた／読んだ主体には評価させない（自己再読禁止）
- 必ず Task ツールで **新規 subagent を dispatch** し白紙で読ませる
- 「書き手には自明、読み手には不明瞭」を炙り出すのが目的

### Subagent 起動契約（テンプレ）

```
あなたは <skill 名> を白紙で読む実行者です。前提知識は持ち込まないこと。

## 対象プロンプト
<対象 skill のパス>

## シナリオ
<具体的な状況 1 段落>

## 要件チェックリスト（事前固定、事後変更禁止）
1. [critical] <最低ライン項目>
2. <通常項目>
3. <通常項目>
（3〜7 項目、[critical] は最低 1 つ）

## タスク
1. シナリオに沿って成果物を生成
2. 以下のレポート構造で返答

## レポート構造
- 成果物: <生成物 or サマリ>
- 要件達成: 各項目に ○ / × / 部分的 + 理由
- Trace: フェーズタグ（Understanding / Planning / Execution / Formatting）
- 不明瞭点: { Issue / Cause / General Fix Rule } の三点
- 裁量補完: 仕様未記載で自分が決めた箇所
- 再試行: 回数と理由
```

### 計測軸（質的優先）

| 軸 | 取得元 | 用途 |
|---|---|---|
| 成功 / 失敗 | `[critical]` 全て ○ で成功 | 最低ライン |
| 精度 | 達成 / 全体 | 部分成功度 |
| **不明瞭点 件数** | subagent 自己申告 | **主指標** |
| **裁量補完 件数** | subagent 自己申告 | description の漏れ |
| ステップ数 | tool_use 数 | 冗長度 |
| duration_ms | claude -p stream | 認知負荷代替 |
| 再試行回数 | subagent 自己申告 | 曖昧さ |

質的（不明瞭点 / 裁量補完）が主、量的は補助。

### 収束判定（数値固定）

連続 2 反復で全て満たせば停止：

- 新規不明瞭点 = 0
- 精度改善 ≤ +3 pt
- ステップ数変動 ±10% 以内
- duration 変動 ±15% 以内
- hold-out シナリオで精度低下 < 15 pt

3 反復続けて不明瞭点が減らない → **発散** = 構造ごと書き直し。

### 反復ディシプリン

- **1 反復 1 テーマ**。複数同時修正は効果特定を壊す
- シナリオを修正に合わせてチューニングしない（指標ハック）
- 同じ subagent を 2 度使わない（読了済みでバイアス混入）

### 停滞打破（バリアント探索）

- **Conservative**: 現プロンプト + 次善の小修正
- **Exploratory**: 構造変更 1 つ（節並べ替え / 段落分割 / scaffold 追加）

A vs B の直接対決はしない（位置バイアス回避）。次反復の起点を「精度高 → 不明瞭点少 → tool_use 少」の順で選ぶ。

### Failure pattern ledger

`evals/failure-patterns.md` に再発する失敗クラスを記録する。エントリ形式：

```
- **<Pattern 名>**: <短い記述>
  - Example: <代表 Issue>
  - General Fix Rule: <class レベルの修正則>
  - Seen in: <iter / case id のリスト>
```

修正前に台帳をスキャン → 既存パターンに当てはまるなら「過去の修正がなぜ再発を防げなかったか」を調査。3 回以上再発で構造シグナル。

### Mode C の最終出力

```
# Quality Tuning: <skill> iter <N>

## Variant
- Conservative / Exploratory

## 変更点（前 iter からの diff）
- <修正 1 行>
- Pattern applied: <Pattern 名 or (new)>

## 実行結果
| シナリオ | 成否 | 精度 | steps | duration | retries | Weak phase |

## 不明瞭点（今回新出）
- Issue / Cause / General Fix Rule

## 裁量補完（今回新出）

## Ledger 更新
- Added / Re-seen

## 次反復案
- 収束判定: 連続 X / 必要 Y
```

---

## このスキルがやらないこと

- **N=3 以上の variance 解析はしない。** 1-rater 即時測定が既定で、厳密測定は Mode B のハーネス（`claude -p`）か Mode C の subagent dispatch に切り替える。
- **プラグインスキルは編集しない。** `plugins/<plugin>/skills/...` は plugin-dev に任せる。
- **skill 本体のロジックは書かない。** 対象 skill の中身（例: テストレビューの判断基準）は当該 skill のオーナの仕事。本スキルは雛形と eval ループだけ提供する。
- **description を `MUST` で固める誘導はしない。** 計測駆動でしか直さない。
- **同一 agent での自己再読を計測に使わない。** Mode C はバイアス排除が前提。

## 既知の限界（公式ベストプラクティスとのギャップ）

公式 best-practices に対してまだ満たせていない項目を正直に記録する。次回以降の改善対象：

- **マルチモデル未検証**: 公式は Haiku / Sonnet / Opus すべてでテストすることを要求。本セッションの計測は Opus のみ。Haiku で同じ description が起動するかは未確認
- **Quality eval が単一シナリオ**: 公式は「最低 3 evaluation」を求める。Mode C のドッグフードは 2 シナリオに留まり、hold-out も未設定
- **Old patterns セクション**: 時間依存記述は `<details>` で隠す方針を skill-builder 内では未採用（必要が出たら導入）
