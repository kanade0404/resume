# PRIVACY-BOUNDARY: 公開/非公開境界の絶対ルール

このリポジトリ(`kanade0404/resume`)はGitHub上に公開される職務経歴書リポジトリで
あり、`.claude/skills/` はコミット対象・公開対象である。本skillの生成物のうち
何がここに書けて何が書けないかを固定する。

## skill本文(SKILL.md・references配下)への禁止事項

- 報酬額・年収・転職検討先/現職企業名・オファー内容・退職理由の内情など
  私的・機微な情報を一切書かない。フレームワーク解説・フォーマット定義・
  手順の説明はすべて一般論・ダミー値・公開情報(README/detail.mdに既にある
  情報)の範囲に留める
- vaultの実パスをSKILL本文・referencesに書かない。実行時に
  `.claude/skills/career-grilling/vault-paths.local`(gitignore対象)から解決する。
  このファイル自体は `.gitignore` に登録済み
- 決定木・台帳のscratchファイル(`decision-tree.md` 等)はgitignore対象の
  スクラッチ領域(`.claude/skills/career-grilling/scratch/` またはセッションの
  scratchpadディレクトリ)に限定し、コミット対象にしない

## write-back(書き戻し)の境界

- デフォルトの書き戻し先はprivate vaultの `profile/<topic>.md` および
  `転職/<year>/` 配下のみ。private vaultは明示的 `/add-dir` が無い限り
  デフォルトで触らず、自動addもしない
- `profile/<topic>.md` には生の数値・社名を書かず要約+`[[出典]]`リンクのみ、
  生の逐語・数値は一次ログ(日付ファイル、private側)にのみ許す
- 本skill自身はgit commitを一切実行しない。Phase6はdiff提示のみ、適用も
  承認後に `Write`/`Edit` で行うだけ

## resumeリポジトリ(公開側)への書き込み禁止事項

- `README.md`/`detail.md`/`docs/action-plan.md`/`docs/resume-update-plan.md`
  への反映は、本skillの範囲外の別フローに委譲する。反映時は必ず機微
  (報酬額・企業名・退職理由内情)を削いだ表現に変換し、`README.md`/`detail.md`
  編集時は既存の `pnpm run lint`(textlint)を必ず通す
- `README.pdf` はCIが自動生成・自動コミットする対象であり、本skill(または
  人手)が手動でコミットしてはならない(既存CLAUDE.mdの規約を継承、変更なし)

## 配布物との関係

`career-grilling` はこのリポジトリ固有のローカルskillであり、
[kanade0404/skills](https://github.com/kanade0404/skills) からのrulesync配布物
ではない(`grill-me`/`grilling` と同列)。したがって `.rulesync/` の管理対象外
であり、直接編集してよい。
