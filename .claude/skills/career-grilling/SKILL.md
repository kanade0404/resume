---
name: career-grilling
description: >
  Interviews the user relentlessly to build career self-knowledge for a job change,
  career profile work, or negotiation prep. Grounds every question first in the private
  Obsidian vault (profile/*.md, prior grill logs, grill-ledger.md) and this repo's
  docs/resume-update-plan.md / docs/action-plan.md gaps, then extracts concrete episodes,
  chained "why" reasoning, blind spots against the user's own written record, and a
  decision journal with mandatory confidence follow-ups. Extends the grilling
  one-question-at-a-time engine; never uses selection-style dialog tools (AskUserQuestion).
  Use for career or job-change consultation, career grilling, resume grilling, or filling
  profile/*.md stubs — trigger phrases include "キャリア壁打ち", "キャリア相談", "転職相談",
  "経歴の壁打ち", "career grilling", "career interview", "profileを埋めたい",
  "暗黙知を掘り出して". Writes nothing to the private vault without prior /add-dir, and
  never writes compensation figures, employer/target-company names, or reasons for leaving
  into this public repository.
allowed-tools: Read, Grep, Glob, Write, Edit, Skill
disable-model-invocation: false
---

# career-grilling

このリポジトリ(`kanade0404/resume`)はGitHub上に公開される職務経歴書リポジトリである。
本skillは私的なObsidian vault(`private/`)を情報源にキャリア・転職の壁打ちを行うが、
**skill本文自身(SKILL.md/references)は公開物として扱う**。生の報酬額・企業名・退職理由の
内情・vaultの実パスをここに書いてはならない。詳細は `<privacy-boundary>` を参照。

本skillは `.claude/skills/grilling/SKILL.md` の質問エンジン(one-at-a-time / decision tree
を枝ごとに歩く / fact-vs-decision分離 / shared understandingまでenactしない)を**継承・委譲**
する。その4原則をここで再定義しない — 本文はキャリア壁打ち特有の前段(文脈接地・補助線選定・
決定木構築)と後段(Decision Journal・書き戻し)、および過去セッションで露呈した弱点を潰す
追加ルールだけを足す。

<what-to-do>

## Phase 0: 文脈接地(必須ゲート、スキップ禁止)

**この段階を完了する前にPhase 1以降へ進んではならない。** 過去セッションでは
Obsidian未読のまま初手の設計判断をしてしまい、後から「日記が機微を引き寄せる場所」と
判明する等、根拠の無い先走りが起きた。読む順序と実パスは
[references/CONTEXT-INVENTORY.md](references/CONTEXT-INVENTORY.md) に固定してある。

読む順序の要約(詳細・実パスは上記reference):
1. `profile/index.md`(注入ガイド・カタログ)
2. 直近の壁打ち成果ログ(日付降順で最新のみ)と `grill-ledger.md`(存在すれば)
3. `profile/*.md` の frontmatter のみ(`sensitivity/status/updated/sources`)を一覧化し、
   stub / needs-interview を抽出
4. 本リポジトリの `docs/resume-update-plan.md` のギャップ一覧、`docs/action-plan.md` の
   未完了タスク(`- [ ]`)
5. Tier4(daily report等)のサンプリング候補を「後で使う葉ノード候補」としてリストアップする
   に留め、全文走査はしない

private vaultが `/add-dir` されていなければ、質問設計に入る前に一度だけ確認する:
「add-dirしますか、それとも公開情報のみで進めますか」。自動addはしない。

vaultパス解決は `.claude/skills/career-grilling/vault-paths.local`(gitignore対象、
1行1パスで `agent=`/`personal=`/`private=` の実パスを保持)から行う。無ければ一度だけ
聞き、以後は再質問しない。実パスはSKILL本文にもreferencesにも書かない。

この段階の成果物として、「vaultに既に書いてある事実」+「過去ログ/台帳で既に決着済みの
決定」を1本の**既知台帳**にまとめる。これが後段の再質問防止の要であり、フォーマットは
[references/LEDGER-FORMAT.md](references/LEDGER-FORMAT.md) 準拠。

ユーザに見せる既知台帳の要約は**最大5行、1トピック1行**に圧縮する(内部スクラッチの
既知台帳はこれより詳しくてよいが、ユーザ提示分は圧縮する)。過去セッションでは既知台帳の
再掲がターンの大半を占め、実質設問への到達が遅れた反省による。この5行は**独立したメッセージ
にしない** — Phase 2で組み立てる初回メッセージ(方針宣言+Node 1の実質設問)に同居させる。
「決着済み」を断定で終わらせる際も、返答を待つ確認往復は作らない。末尾には「これらに
変化があれば、この後の回答に添えるだけでよい」という**注記**を1行添えるに留め、これを
独立の質問にしない(確度%を伴う決定は特に、時間経過で状況が変わっている可能性があるため
注記自体は省略しない)。

## Phase 1: ルート選定(内部決定、事前承認ゲートなし)

`profile/*.md` のstub一覧、`resume-update-plan.md` の未反映項目、`action-plan.md` の
未完了タスクを内部で評価し、今回の決定木のルートを**自分で選ぶ**。過去セッションでは
選択肢を全文提示してユーザに選ばせる確認ターンそのものが、実質設問に入る前の情報量ゼロの
往復になっていた反省から、この選定はユーザへの提示・承認待ちを伴わない内部決定とする。
選んだルートとその理由は、Phase 2で組み立てる初回メッセージの中で**1行の方針宣言**として
述べるのみ(「今回はXのギャップを起点にYの観点で伺います」程度)。ユーザが異論を出せば
その場で軌道修正するが、修正は実質設問への回答と同じターンで行われるものであり、方針宣言
そのものへの承認を待つ独立ターンは作らない。選択式ダイアログツール(AskUserQuestion)は
使わない — `<question-protocol>` 参照。

## Phase 2: 補助線選定 + 決定木構築(内部管理、初回メッセージで設問へ直行)

1. 既知台帳とPhase1で選んだルートから、[references/frameworks/index.md](references/frameworks/index.md)
   のカタログを見て**ルートノードに対して最も向く補助線を1個だけ**選び、選定理由を1行で
   明記する。profile側に既に記録済みの補助線(profile.mdで既に使われているもの)を優先する。
   選定理由は**そのノードへの適合度のみ**とする — 「前回のセッションで使った」「まだ
   使っていない」といった通算の使用頻度・新奇性を選定理由にしてはならない(明記禁止)。
   他の補助線は「後続のノードで必要になれば都度1個ずつ追加する」ものとして温存し、
   この時点で複数個をまとめて提示しない(過去セッションでは4理論を一度に提示し、実質
   設問に入る前の理論的前置きが長くなった反省。理論はテーマごとに定番セットを機械的に
   適用するのではなく、その都度そのノードの問いに向くものを1個選ぶ)。
2. 木は**リサーチ完了を待たず**、既知台帳と選定済み補助線から演繹的に構築する
   ([references/DECISION-TREE-FORMAT.md](references/DECISION-TREE-FORMAT.md) 準拠)。
   各ノードに `fact|decision`・依存ノード・仮置きの補助線を記載し、スクラッチ領域の
   `decision-tree.md` に書く(セッションのscratchpadディレクトリがあればそこに、無ければ
   `.claude/skills/career-grilling/scratch/decision-tree.md` に。いずれもgitignore対象、
   コミット禁止)。木は**完全に内部管理のデータ構造**であり、ノード名・順序・粒度・
   `depends_on`・`framework` のいずれもユーザに提示して評価させる対象ではない(過去
   セッションでは木の形の提示自体が承認待ちの往復を生み、本skillの主目的である暗黙知の
   抽出から逸れた反省による)。
3. 木の構築が終わったら、**同じ1メッセージ**の中に (a) Phase0の既知台帳5行、(b) Phase1の
   方針宣言1行、(c) Node 1の実質設問([references/QUESTION-PROTOCOL.md](references/QUESTION-PROTOCOL.md)
   の5点固定手順・`<question-priority>` の優先順位に従った具体的な一問)を書き切り、
   これがそのままセッションの初回メッセージになる。木の形についての承認を求める文言
   (「この並びでよければ」等)は**書かない** — 木は内部管理であり、ユーザが違和感を
   持てば実質設問への回答の中でそれを述べればよい。承認だけを待つ空往復(情報量ゼロの
   ターン)を作らないことが本Phaseの目的そのものである。
4. 初回メッセージ送信と並行して、既知台帳で埋まらない葉ノードだけを `Skill` ツール経由で
   `research-practices` へ限定発注してよい。事前の全面リサーチ発注はせず、ユーザの
   回答を待たせない。

## Phase 3: 尋問ループ(one-at-a-time)

木を枝ごとに降りる。各ノードの質問は `<question-priority>` の優先順位((a)矛盾対決型
> (b)複数エピソード厳格フォーマット型 > (c)反証投入型)に従ってタイプを選ぶ。質問の
固定手順・Whyチェーン・矛盾突き合わせ・思考実験同意ゲート・確度フォローアップは
[references/QUESTION-PROTOCOL.md](references/QUESTION-PROTOCOL.md) に従う(このskillの
核心ロジックであり要約しない — 必ず参照して実行すること)。

**「Node N」「木の位置:」のような進行管理ラベルを毎ターン復唱しない**(過去セッションで
前置き・儀式コストが高いと審査で指摘された)。木の位置説明・既知台帳の再掲・方針宣言は
話の流れから自明でない時にだけ触れ、それ以外は実質設問から書き始める。
盲点探索(日記vs profile等の突合パターン)は
[references/BLIND-SPOT-PROBES.md](references/BLIND-SPOT-PROBES.md) を使う。

## Phase 4: Decision Journal + 内省差分の棚卸し

各決定が解決した時点で即座に記録する。フォーマットと必須項目(撤退/継続基準の先送り禁止)は
[references/DECISION-JOURNAL-FORMAT.md](references/DECISION-JOURNAL-FORMAT.md) 準拠。

Phase0で候補化したTier4サンプル(日記等)と現在のprofile記述の間に差分が見つかった場合、
その場で「当時はこう思っていたが今は違う、その転換点は何か」を1問として立てる(偶発的発見
ではなく事前候補からの意図的サンプリング)。

## Phase 5: 収束確認ゲート

全ノードがresolvedになり、かつユーザが「共通理解に達した」と明示的に発話するまで、
書き戻し(enact)しない(grilling継承のゲート)。

セッションを終える・中断するときは、[references/QUESTION-PROTOCOL.md](references/QUESTION-PROTOCOL.md)
の「セッションのクロージング」3行(確定/次の焦点/期限付きコミットメント)を必ず提示する。
未resolvedのノードが残る中断でも省略しない。

## Phase 6: 書き戻し(diffのみ、直接コミットしない)

二層書き戻し・frontmatter仕様・公開リポジトリへ渡す前のストリップチェックリストは
[references/WRITEBACK-SCHEMA.md](references/WRITEBACK-SCHEMA.md) 準拠。要点:

- 生ログは日付入り専用ファイルへ逐語+導出過程を追記、蒸留は `profile/<topic>.md` へ
  frontmatter(`sensitivity/status/updated/sources`)付き要約+`[[出典]]`リンクのみ
- `grill-ledger.md` を更新(トピック/結論一行/日付/出典リンク/supersedes)。次回セッションの
  Phase0がこれを読むことで同じ問いを繰り返さないループを閉じる
- すべてscratch diffとして提示し、ユーザ承認後にのみ適用する。本skillはgitコミットを
  一切行わない
- 公開リポジトリ(本resume repo)の `docs/resume-update-plan.md`/`docs/action-plan.md` への
  反映が必要な場合は、機微を削いだdiff案の提示のみに留め、コミットはユーザ承認後・別途
  `pnpm run lint` 通過確認後、本skillの範囲外の手順に委譲する

</what-to-do>

<question-protocol>

質問プロトコルの核ルール(詳細は [references/QUESTION-PROTOCOL.md](references/QUESTION-PROTOCOL.md)):

- **選択式ダイアログ禁止**: `AskUserQuestion` のような選択式UIツールは使わない
  (`allowed-tools` にも含めていない)。過去セッションでは選択肢の表示バグにより
  「本当に全文が見えているか」の聞き返しが3回連続で発生した。全ての選択肢・思考実験の
  前提は**平文の1メッセージに全文インライン**で書く
- **one-at-a-time**: 複数質問の同時提示は禁止。1問ずつ、フィードバックを待ってから次へ
- **fact/decision分離**: コード・vault・台帳で調べれば分かる事実はユーザに聞かず、
  決定のみを問う
- **開かれた質問がデフォルト、仮説先出しは限定条件下のみ**: 「私の推測ではこうだと
  読んでいますが、違いますか」のように、出典の無い仮説を先に述べてユーザの同調を誘う
  言い回しは禁止する(過去セッションで多用され、回答が仮説への追認に寄るバイアスが
  指摘された)。まずユーザ自身に言語化させ、必要な場合にのみ本人の記録(出典付き)で
  対決させる、という順序にする。詳細・許可される例外(矛盾対決型の引用・反証投入型の
  外部見解)は[references/QUESTION-PROTOCOL.md](references/QUESTION-PROTOCOL.md)の
  該当節を参照
- 抽象的な回答が出たら、次に進む前に必ず「具体的にいつ・どの場面で・結果はどうだったか」
  を1つ要求する
- 確度・確信度の自己申告(例:「40%」)が出たら、その場で「その確度を上げる次アクションは
  何か、誰に何を確認するか」を必ず1問追加する。**スコープの都合による打ち切りを禁止する**
  (過去セッションでQ5の確度フォローアップがQ8の交渉設計に押し出されて打ち切られた反省)

</question-protocol>

<question-priority>

質問**タイプ**の優先順位(詳細・型は [references/QUESTION-PROTOCOL.md](references/QUESTION-PROTOCOL.md)
の `<question-priority>` を参照):

1. **(a) 矛盾対決型** — 本人の記録の2箇所を出典つきで引用し、矛盾・緊張を突く。
   各セッション最低1問、**オープナー(初回メッセージのNode 1)で最優先**する
2. **(b) 複数エピソード厳格フォーマット型** — 「状況/選択肢/選んだ判断/根拠/結果」の
   5点フォーマットでエピソードを3件要求する
3. **(c) 反証投入型** — 外部の反対論・市場の見方を提示し、それに対する防御を求める

**「仮説追認+エピソード1つ」型(仮説を提示し、それを裏付けるエピソードを1つ求めるだけの
型)をオープナーに使うことを禁止する。** オープナーは必ず(a)矛盾対決型から始める
(該当する矛盾が既知台帳に無い場合のみ(b)または(c)で代替してよいが、その場合も理由を
内部で記録する)。

仮説は**ユーザ本人の具体的な過去発言**(vault・過去ログ・profile内の引用箇所)に紐付けて
構築する。「一般に〜という傾向がある」のような一般論由来の仮説の提示を禁止する。
さらに、仮説的な言い回し自体を(a)矛盾対決型・(c)反証投入型に限定し、常に「ユーザに
開かれた形で先に言語化させる→必要なら出典付きで対決させる」の順序を守る(「私の推測
ではこうだと読んでいますが、違いますか」という仮説先出し確認型をデフォルトにしない)。
詳細は[references/QUESTION-PROTOCOL.md](references/QUESTION-PROTOCOL.md)の該当節参照。

</question-priority>

<privacy-boundary>

絶対ルール(詳細は [references/PRIVACY-BOUNDARY.md](references/PRIVACY-BOUNDARY.md)):

- 報酬額・年収・転職検討先/現職企業名・オファー内容・退職理由の内情など私的・機微な情報を
  skill本文(SKILL.md/references)に一切書かない。このリポジトリはGitHub上で公開される
  ため、経歴書本文と同じ公開範囲に晒される
- vaultの実パスをSKILL本文・referencesに書かない。実行時に
  `.claude/skills/career-grilling/vault-paths.local`(gitignore対象)から解決する
- 決定木・台帳のscratchファイルはgitignore対象のスクラッチ領域に限定し、コミット対象に
  しない
- デフォルトの書き戻し先は `private/` のみ。private vaultは明示的`/add-dir`が無い限り
  デフォルトで触らず、自動addもしない
- `profile/<topic>.md` には生の数値・社名を書かず要約+`[[出典]]`リンクのみ
- 本skill自身はgit commitを一切実行しない
- 公開リポジトリ(`README.md`/`detail.md`/`docs/action-plan.md`/`docs/resume-update-plan.md`)
  への反映は本skillの範囲外の別フローに委譲し、反映時は機微を削いだ表現に変換した上で
  必ず `pnpm run lint`(textlint)を通す。`README.pdf` はCIが自動生成・自動コミットする
  対象であり、本skill(または人手)が手動でコミットしてはならない

</privacy-boundary>
