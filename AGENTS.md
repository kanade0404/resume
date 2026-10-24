# AGENTS.md

ファイル構成・コマンド・CIの中身はリポジトリを読めば分かるので書かない。
ここにはリポジトリの外の事情と、ファイルを読んでも気づきにくい約束だけを書く。

## 公開範囲

このリポジトリはGitHubで公開している。次はskill・docs・commit message・PR本文のどこにも書かない。

- 転職先候補や選考を受けた企業の名前
- NotionのページID・URL・`collection://`
- 報酬・転職理由・人物評価

これらはNotion(非公開)にだけ置く。skillに実例が要るときは「A社」と書くか、日付だけを書いてNotion側を参照させる。

## リポジトリの外にあるもの

- 転職活動の記録と企業の判定基準はNotionで管理する。Obsidianは廃止する予定で、新しい記録は書かない
- NotionのIDは `~/.config/kanade0404-resume/research-config` から読む。gitignore対象のファイルは新しいworktreeにコピーされないので、設定をリポジトリ内に置かない
