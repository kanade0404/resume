---
root: false
targets: ["*"]
description: "Bash の汎用コマンドより専用ツールを優先する規律、permission/hook にブロックされたときの復帰手順、gh api / curl 出力の取り扱い規律。すべての作業で常時適用する。"
globs: ["**/*"]
---

# Bash / API discipline

- ファイルの閲覧・検索・加工は専用ツール (Read / Glob / Grep / Edit) を優先し、Bash の
  汎用テキストコマンドで代用しない。専用ツールの方が行番号表示・出力制御の点で優れており、
  環境によっては permission / hook が汎用コマンドを拒否する。
- コマンドが permission / hook にブロックされたら、**同型のコマンドを再試行しない**:
  1. エラーメッセージに代替手段が提示されていればそれに従う
  2. 提示が無い・不明瞭なら、その環境の permissions 設定 (`/permissions`、
     `.claude/settings.json` 等) を確認してから続行する
  3. カレント repo 外への git 操作が拒否される環境では GitHub API
     (contents / git database) で代替する
  (どのコマンドが禁止かは環境設定に依存して変わるため、このルールは個別コマンドを
  列挙しない。設定が真実であり、ルールはその読み方だけを定める)
- `gh api` / `curl` の出力をデータとして扱う前に、必ず成功を確認する。`gh api` は
  HTTP エラーで非ゼロ exit するが、**素の `curl` は HTTP エラーでも exit 0** なので
  `--fail` 系オプションを併用して exit code を見るか、HTTP ステータスを自分で検査
  する。失敗時はエラー本文が stdout に混ざるため、そのままパースすると誤検知する
  (例: 404 のエラー JSON を「データが存在する」と誤認する)。
- **機械処理スクリプトは入口で `NO_COLOR=1` / `CLICOLOR_FORCE=0` を export し
  `GH_FORCE_TTY` を unset して、環境の端末装飾に依存しない状態を自分で作る**。
  `CLICOLOR_FORCE=1` の環境では
  `gh api` の生 JSON 出力が pipe 先でも色付けされ、下流の jq を静かに壊す
  (実例: 監視 2 回 + skill 同梱スクリプト 1 回が同根で故障)。`--jq` / `--json` を
  使っていても、生出力をパイプする経路が 1 箇所でもあれば防御にならない —
  読み手の注意ではなく entry point での構造的無効化で防ぐ。
- CI / GitHub Actions 内で GitHub API を叩くツール (rulesync, gh 等) には
  `GITHUB_TOKEN` / `GH_TOKEN` を明示的に渡す。runner の匿名クォータは 60 req/h で
  即枯渇する (実例: workflow 内の `rulesync fetch` が匿名レート制限の 403 で失敗)。
