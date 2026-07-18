---
name: harness-distribution
description: |
  汎用性のあるハーネス片 (rule / slash command / subagent / hook / 定型スクリプト) を、
  ローカル設定ではなく **配布元 skills リポジトリの feature 枠** (rules/ commands/
  subagents/ hooks/) に canonical 形式で収録し、タグリリース → rulesync 経由で
  consumer 全 repo とクラウド実行 (Routines / cloud セッション / Actions) に届ける
  ための判定と手順のスキル。ローカル (`~/.claude/*`, `settings.local.json`) に置いた
  ハーネスはそのマシンでしか効かず、クラウド実行に届かない — 本スキルはその置き場所
  ミスを防ぐ。機密 (トークン・private repo 名・内部 URL) や特定マシン依存の内容を
  **配布しない**判定も担う。

  「このルール他の repo でも使いたい」「rulesync で配布して」「これは汎用だから
  skills repo に」「クラウド実行でも効くようにして」「この hook / command を共通化
  して」「どこに置くべき?」のような要請、session-retro の rule handoff で宛先を
  決める時、新しい rule / command / hook / subagent を書いた直後の置き場所判定、
  いずれでも必ず起動すること。

  範囲外: skill 本体の新規作成・トリガ改善 (skill-builder)、rule や教訓の中身の考案
  (session-retro 等の生成元)、単一プロジェクト固有の permissions / settings 変更
  (update-config 系)、リリース手順単体の質問 (RELEASING.md)。本スキルが持つのは
  「配布判定 → 枠選択 → canonical 収録 → リリース → consumer 反映」の経路のみ。
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
---
# harness-distribution

> **原則**: ハーネスは「効いてほしい実行環境すべてに届く場所」に置く。ローカル設定は
> そのマシン限定 — クラウド実行・複数 repo に効かせたいものは配布層 (skills リポジトリ
> + rulesync) に置き、git と タグで版管理する。
> **逆原則**: 何でも配布しない。機密と環境依存はローカルに留める。判定が本体である。

## いつ使うか / 使わない場面

**使う**:

- rule / command / subagent / hook / 定型スクリプトを書いた・書こうとしていて、置き場所を決める時
- 「他の repo でも使いたい」「rulesync で配布」「クラウド実行でも効くように」「共通化して」
- session-retro の rule handoff で宛先を決める時

**使わない** (成果物で判定):

- **skill そのもの**の新規作成・改訂 → skill-builder (skills/ 枠の中身は専任がいる)
- rule / 教訓の**中身の考案** → session-retro 等の生成元 (本スキルは置き場所と経路のみ)
- **単一プロジェクト固有**の permissions / settings 変更 → update-config 系
- リリース手順だけの確認 → RELEASING.md を直接参照

## Step 1 — 配布判定 (順に問う)

1. **機密を含むか?** — トークン・鍵・private repo 名・内部 URL・顧客情報
   → **配布しない**。ローカル settings か private な ops リポジトリへ
2. **特定環境に依存するか?** — マシン固有のパス、特定 hook 設定の前提、個人の鍵配置
   → まず**原則化を試みる**: 環境の詳細を列挙する代わりに「設定の読み方」を定める形に
   書き換えられれば汎用になる (例: 禁止コマンドの列挙 → 「ブロックされたら permissions
   設定を確認する」)。書き換えられなければローカルに留める
3. **汎用か?** → Step 2 へ

判定に迷ったら配布しない側に倒し、理由を添えてユーザに確認する。

## Step 2 — 枠の選択

| 内容 | 枠 | canonical 形式 |
|---|---|---|
| 横断的な指示・規律 (常時 or glob 適用) | `rules/` | frontmatter: `root` / `targets` / `globs` / `description` + Markdown 本文 |
| slash command | `commands/` | rulesync の command 形式 |
| subagent 定義 | `subagents/` | rulesync の subagent 形式 |
| hook | `hooks/` | rulesync の hook 形式 |
| 手順知識・ワークフロー | `skills/` | **skill-builder に引き渡す** (本スキルでは書かない) |

形式に迷ったら配布元リポジトリ内の既存ファイルか、rulesync 本体リポジトリの
`.rulesync/` 配下の実例を参照する (推測で frontmatter を書かない)。

## Step 3 — 収録

- 配布元リポジトリ (例: `kanade0404/skills`) に branch を切り、該当枠にファイルを置いて PR
- カタログの不変条件 (CLAUDE.md 記載) を守る。skills 枠なら「ディレクトリ名 = frontmatter name」等
- PR 本文に: 由来 (どのセッション / retro / 失敗からか)、なぜ配布層か、consumer への影響

## Step 4 — リリース

- merge 後、配布元の RELEASING.md に従いタグを切る (追加は MINOR)
- consumer はタグ pin なので、**タグを切るまで誰にも届かない**。溜め込まず小さく切る

## Step 5 — consumer 反映

```bash
rulesync fetch <owner>/skills@<tag> --features rules,skills,...
rulesync generate
```

- **生成物 (CLAUDE.md / AGENTS.md 等) を consumer リポジトリに commit する**。
  ここまでやって初めてクラウド実行 (repo を clone して動く環境) に届く。
  生成して commit しなければローカル生成マシン限定のままで、本スキルの目的を達成していない
- 複数 consumer がある場合は反映もれの repo を残さない (対象一覧を出して順に適用)

## 出力フォーマット

```markdown
# Harness Distribution: <対象の一言>

- 判定: 配布する / しない (理由: 機密 | 環境依存 | 汎用)
- 枠: rules | commands | subagents | hooks | skills(→skill-builder)
- 収録 PR: <URL>
- リリース: <タグ or 未 (merge 待ち)>
- consumer 反映: <repo 一覧と状態>
```

## このスキルがやらないこと

- **SKILL.md の中身** (skill-builder の成果物)
- **rule / 教訓の本文の考案** (session-retro 等の成果物)
- **単一プロジェクトの settings / permissions 変更** (update-config 系の成果物)
- **配布元リポジトリのタグ運用ポリシーの変更** (RELEASING.md の管轄)
