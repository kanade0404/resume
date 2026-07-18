# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## リポジトリ概要

日本語の職務経歴書をMarkdownで管理し、PDFに変換するリポジトリ。アプリケーションコードは無く、成果物はMarkdown文書とそこから生成されるPDF。

- `README.md` — サマリ版の経歴書(プロフィール・ハイライト・強み)
- `detail.md` — 詳細版の職務経歴書
- `docs/action-plan.md` — 期限付きアクションプラン。毎週月曜09:00 JSTにGitHub Actionsが未完了タスク(`- [ ]`)をDiscordにリマインドする。期限は `(期限: YYYY-MM-DD)` 形式を厳守すること(リマインダーがこの形式をパースする)
- `docs/resume-update-plan.md` — 経歴書アップデート計画

## 開発環境とコマンド

ツールチェイン(Node.js + pnpm)はnixで管理する。`nix develop` で開発シェルに入ってからpnpmを使う。

```bash
nix develop                       # 開発シェル(node + pnpm)に入る
pnpm install                      # 依存インストール
pnpm run lint                     # textlint でルート直下の *.md を検査
pnpm run lint:fix                 # textlint 自動修正
pnpm run generate                 # convert.sh でルート直下の全 *.md を PDF 化
pnpm run fix                      # fixpack で package.json を整形
```

- PDF生成はmd-to-pdf(内部でPuppeteer/Chromium)を使用する。CIでは日本語フォント(Noto CJK, IPA)のインストールが前提
- 単一ファイルだけ変換する場合:

```bash
md-to-pdf detail.md --stylesheet ./style.css --pdf-options '{ "format": "A4", "printBackground": true }'
```

## ハーネス配布(rulesync)

skillとruleは配布元リポジトリ [kanade0404/skills](https://github.com/kanade0404/skills) からrulesyncで取得する。`.rulesync/` と生成物(`.claude/skills/`, `.claude/rules/`)はコミット対象。**配布物を直接編集しない**(編集はskills repo側で行いタグを上げて再取得する)。

```bash
pnpm run rulesync:fetch           # kanade0404/skills@<pin タグ> から取得(要 GITHUB_TOKEN)
pnpm run rulesync:generate        # .claude/ に生成
pnpm run rulesync:check           # ドリフト検出(CI 用)
```

`grill-me` と `grilling` はこのリポジトリ固有のローカルskillで、配布物ではない。

## CI / 自動化

- `textlint.yaml` — masterへのpushと全PRでlintを実行。textlintを通らない文章はマージできない
- `convert.yaml` — masterへ `*.md` がpushされるとPDFを生成し、`README.pdf` をbotが自動コミットする。**PDF は手動でコミットしない**(README.pdfはCIが更新する)
- `action-plan-reminder.yaml` — `docs/action-plan.md` の未完了タスクをDiscordへ通知(要 `DISCORD_WEBHOOK_URL` シークレット)
- `skills-update.yml` — skills repoの新タグを検知してrulesync pinの更新PRを自動作成する

## 文章規約(textlint)

`.textlintrc` で `preset-ja-technical-writing`(である/ですます混在チェックは無効)と `preset-ja-spacing` を適用する。`spellcheck-tech-word` も有効。経歴書本文を編集したら必ず `pnpm run lint` を通すこと。許容語の追加は `.textlintrc` の `allowlist` フィルタに追記する(例:「デグレード」)。
