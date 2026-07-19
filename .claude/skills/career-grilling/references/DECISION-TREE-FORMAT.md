# DECISION-TREE-FORMAT: 決定木のノード形式

Phase 2 で構築する決定木のノードスキーマ。`grilling` の「decision tree の各枝を
歩く」を、キャリア壁打ち向けに具体化したもの。

## 保存場所

- セッションの scratchpad ディレクトリが本リポジトリの外(OS一時領域等)であることを
  確認できる場合のみ、そこの `decision-tree.md` に書く
- 本リポジトリ内のパスしか得られない場合、または外部であることを確認できない場合は
  `.claude/skills/career-grilling/scratch/decision-tree.md` に書く(gitignore対象)
- いずれの場合も、vault由来の機微情報を含みうるファイルをコミット対象になり得る
  パスに書かない(gitignore対象であることが確認できないパスには書かない)

## ノードスキーマ

```text
### Node <id>: <ノード名>
- kind: fact | decision
- depends_on: [<親ノードid>, ...]
- framework: <Phase2で選定した補助線名、無ければ "none">
- status: open | resolved | resolved (from ledger)
- question: <decision の場合のみ。実際にユーザへ投げる質問文の下書き>
- resolution: <resolved になったら書く。ユーザの決定そのもの>
- confidence_followup: <ユーザが確度%を自己申告した場合、次アクション子ノードのid>
```

## 構築手順(Phase 2 の詳細)

1. 既知台帳(`status: fact` / `decided`)から埋まる葉ノードには
   `status: resolved (from ledger)` を仮置きし、`resolution` にその内容を写す
2. Phase1で選んだルートから、依存関係を明示しながら子ノードを演繹する。
   「このノードの答えが決まらないと次のどのノードに進めないか」を `depends_on` で
   必ず書く。過去セッションでは依存関係のない箇条書き質問(Q5がQ2から演繹されず
   唐突)になった反省から、依存グラフの明示は省略しない
3. 各 `decision` ノードには仮置きの `framework` を1つ付ける。Phase2ステップ1で
   ルートノード用に選定した1個をまず充て、他ノードの `framework` は「そのノードに
   降りた時点で」都度1個ずつ選び直してよい(木構築の時点で全ノード分の補助線を
   まとめて確定させない)
4. 木(ノード名・順序・粒度・`depends_on`・`framework` すべて)は**完全に内部管理の
   データ構造**であり、事前承認を求めてユーザに提示することはしない。木の設計品質を
   評価させるのはユーザの仕事ではなく、承認待ちの往復自体が本skillの主目的である
   暗黙知の抽出から逸れる、という過去セッションの反省による。ユーザに見せるのは
   既知台帳の5行要約・Phase1の方針宣言1行・Node 1 の実質設問(`question` の下書きを
   [QUESTION-PROTOCOL.md](QUESTION-PROTOCOL.md) の5点固定手順と `<question-priority>`
   の優先順位に沿って書いたもの)を**同じ1メッセージ**にまとめたものだけであり、これが
   セッションの初回メッセージになる。木の形についての承認を求める文言は書かない
5. 初回メッセージの送信と並行して、`status: open` のまま残る葉ノードのうち既知台帳や
   コードベース調査で埋まらないものだけを `Skill` ツールで `research-practices` へ
   発注してよい。発注は葉ノード単位、事前の全面発注はせず、ユーザの設問1への回答を
   待たずに裏で進めてよい。発注時のサニタイズ・完全スコープ済みプロンプトの要件は
   [SKILL.md](../SKILL.md) の Phase 2 手順4 と同一(勝手に緩めない)

## Resolved 時の追加ルール

- ユーザが確度%を自己申告したら、`confidence_followup` に子ノード(kind: decision,
  question: "その確度を上げる次アクションは何か、誰に何を確認するか")を自動追加し、
  そのノードも resolved になるまで木を完了とみなさない
- 内省差分(Tier4サンプル vs profile)が見つかったら、その場で
  `kind: decision, framework: none` の新規ノードを追加する(Phase4参照)
