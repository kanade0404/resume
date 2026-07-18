---
name: retro
description: >-
  完了したセッション (PR が merge / close された後、長時間セッションの後、新 skill を運用した直後) のトランスクリプトを
  **バイアスを排した fresh subagent** に網羅解析させ、ハーネス自身の改善提案を返すスキル。tool 統計・権限拒否・subagent
  結果・ループ/stall/escalation・skill の不発や暴発・token 浪費・blocking 待ちを洗い、各 finding を「どのレバー
  (hook / settings allow-deny / skill 編集 / 新規 skill / CLAUDE.md・rule /
  empirical-prompt-tuning への handoff / none) で直すか」「なぜ局所パッチでは再発するか (class
  レベルの根本原因)」付きで構造化する。`pr-monitor` が merge / close
  を検出した直後の主経路、「振り返り」「retro」「セッション分析」「ハーネス改善したい」「allow リスト見直したい」「hooks
  候補ある?」「なんでこの skill 起動しなかった?」のような要請で必ず起動する。本スキルは**提案のみ**で、settings / skill /
  rule / hook の編集・コミットは一切せず、すべて人間承認を待つ。改善の実体 (skill 編集や trigger 調整) は承認後に
  `skill-builder` / `empirical-prompt-tuning`
  等が担う。コードレビューやバグ修正のセッション分析ではなく、**エージェント運用 (harness) の改善**に閉じる。
allowed-tools:
  - Read
  - Bash
  - Task
---
# retro — セッション振り返り & ハーネス自己改善 (提案のみ)

> **Iron Law (バイアス排除)**: 解析は **執筆バイアスを持つ main セッションが自分でしない**。fresh subagent に transcript と repo skill 一覧だけを渡して dispatch する。自己レビューは構造的に客観視できない (`skill-builder` Mode C / `design-review` と同じ規律)。
> **Iron Law (提案のみ)**: 本スキルは settings / skill / rule / hook を **編集・コミットしない**。出すのは承認待ちの提案だけ。「とりあえず rule に追記」を既定の手にしない。

## いつ起動するか

- `pr-monitor` が PR の merge / close を検出した直後 (主経路)
- 長時間セッションの後 / 新しい skill を初めて運用した直後
- 「振り返り」「retro」「セッション分析」「ハーネス改善」「allow リスト見直し」「hooks 候補」「なんでこの skill 起動しなかった / 暴発した」

逆に **起動しない**:

- コードのバグ修正・実装そのもののセッション分析 (それは `systematic-debugging` / 各実装 skill)
- skill 本体の新規作成・trigger 調整の実行 (承認後に `skill-builder` / `empirical-prompt-tuning`)
- PR コメントへの対応 (`pr-review-respond`)

## ワークフロー

### Step 1 — transcript を特定 (main が実行)

**呼び出し元が transcript パスを明示してきたらそれを最優先で使う** (`pr-monitor` は決着時に state の `origin_transcript` = PR を生んだ元セッションを渡す。後の監視セッションを誤解析しないため)。渡されなかったときだけ、以下で現プロジェクトの最新 `.jsonl` を当該セッションとして特定する。場所は環境依存なので存在するパスを使う:

```bash
# プロジェクトディレクトリ slug は cwd の "/" と "." を両方 "-" に置換したもの
# 例: /a/b/.claude/c → -a-b--claude-c  (/. が -- になる)
proj=$(pwd | sed 's#[/.]#-#g')
# 最新 mtime の jsonl = 当該セッション。
# glob + ls -t は macOS/BSD でも GNU でも動く (GNU 専用の `xargs -r` を使わない)。
# マッチ無しなら glob はリテラルのまま残り ls がエラー → /dev/null → 空出力。
ls -t "$HOME/.claude/projects/$proj"/*.jsonl 2>/dev/null | head -1
```

slug 規則が環境で違う / 見つからない場合は推測で代用せず、`~/.claude/projects/` 配下で最新 mtime の `*.jsonl` を全 dir 横断で 1 つ出してユーザに確認する。確定したパスを `TRANSCRIPT` として Step 2 に渡す。

### Step 2 — fresh subagent に網羅解析を dispatch (Iron Law)

`Task` で**新規 subagent** を 1 つ起動し、以下の起動契約で渡す。main は解析しない:

```text
あなたはハーネス運用を監査する解析者です。main セッションの執筆者ではない前提で、
transcript の事実だけから判断する。実装の良し悪しは見ない — エージェント運用を見る。

## 入力
- TRANSCRIPT: <path>
- repo skill 一覧: skill ディレクトリの name と description。**置き場は環境依存** — 配布元では top-level `skills/<name>/`、consumer 生成先では `.claude/skills/<name>/` や `.agents/skills/<name>/` になる。`skill-builder` が記す multi-location discovery と同じ要領で存在するパスを使い、`skills/` 決め打ちで空一覧にしない (規範は skills/skill-builder/SKILL.md)

## 網羅スキャン (jq / Read で transcript を読む。観点を 1 つも飛ばさない)
1. tool 利用統計 (種別ごとの回数)
2. 権限拒否 (denied / Permission を含む tool_result)
3. subagent dispatch の結果 (Task の subagent_type / 成否 / 空振り)
4. ループ・stall・escalation・同一操作のリトライ
5. skill の不発 (起動すべきだったのに起動しなかった) / 暴発 (不要なのに起動)
6. token 浪費 (生ログの main 引き込み等) と blocking 待ち (foreground sleep / watch)

## 各 finding の構造 (これだけ返す)
- priority: P1 / P2 / P3
- observation: transcript 上の事実 (該当箇所の引用 1 行)
- root-cause: class レベルの根本原因 (その場限りでない一般化)
- lever: hook / settings(allow) / settings(deny) / skill 編集 / 新規 skill / CLAUDE.md・rule / ept-handoff / none
- why-not-local: なぜ局所パッチ (1 箇所の rule 追記等) では再発するか
- proposal: 承認後に取る具体アクション (誰が = skill-builder / ept / 人間)
```

`lever` 選択の規律: 「`echo`/`ls` 等が毎回拒否される」→ settings(allow)、「危険操作を物理的に止めたい」→ hook、「skill が不発」→ skill 編集 or ept-handoff、「複数 skill に跨る運用ルール」→ CLAUDE.md・rule、「構造的に再発しない」→ none。**rule 追記を反射的に選ばない** — まず lever 表で最小・最適なレバーを当てる。

### Step 3 — 提案を集約して提示 (main が実行、編集はしない)

subagent の findings を priority 順に 1 メッセージで提示する。各 finding はそのまま上記構造で出す。**ここで編集・コミットはしない**。最後に「どれを適用するか」を人間に問い、承認されたものだけを承認後に該当 skill (`skill-builder` / `empirical-prompt-tuning`) または人間に渡す。

## 出力フォーマット

```markdown
# Retro: <session 短縮 ID> (<PR #n / merged|closed>)

## 網羅スキャン サマリ
- tool 利用: <上位 3>
- 権限拒否: <n 件>
- subagent: <n dispatch / 空振り m>
- ループ/stall/escalation: <n>
- skill 不発/暴発: <例>
- token 浪費 / blocking: <例>

## 改善提案 (提案のみ・未適用)
### P1 — <一言>
- observation: <事実引用>
- root-cause: <class レベル>
- lever: <…>
- why-not-local: <…>
- proposal: <承認後アクション / 担当>
### P2 — …
### P3 — …

## 適用判断のお願い
- 上記のうち適用するものを選んでください。承認後に skill-builder / ept / 手動へ渡します。
```

## 出力する成果物 / 出力しない成果物

### 出力する成果物
- **網羅スキャン サマリ** (6 観点の数値/例)
- **改善提案リスト** (priority / observation / root-cause / lever / why-not-local / proposal の構造)
- **適用判断の依頼** (人間承認のための選択肢提示)

### 出力しない成果物
- **settings.json / SKILL.md / rule / hook への編集・コミット**: 本スキルは提案のみ。適用は承認後に別主体。
- **main セッション自身による解析結果**: 解析は fresh subagent。自己レビュー出力は出さない。
- **局所パッチ前提の「rule にこう追記」だけの提案**: lever 表で最小・最適レバーを当て、why-not-local を必ず添える。
- **コードのバグ/実装に関する指摘**: 範囲外 (harness 運用に閉じる)。

## リファレンス
- `skills/skill-builder/SKILL.md` Mode B/C — 承認後の trigger / 品質改善の実体
- `skills/empirical-prompt-tuning/SKILL.md` — skill 不発の反復チューニング handoff 先
