---
name: resume-review
description: >
  職務経歴書(README.md / detail.md)を、立場の異なる読み手のペルソナごとに別々の
  subagentへ白紙で読ませて多角的にレビューし、統合subagentが重複排除・引用検証・優先度付けを
  した指摘を返すレビュー専用skill。ペルソナはスクリーナー(人事・エージェント)、技術面接官、
  採用責任者、事業側(PdM・CTO)、網羅チェッカーの5種で、評価基準は同梱のルーブリック(A1〜E1)。「経歴書レビューして」「職務経歴書を見て」「resumeレビュー」
  「README.md / detail.mdをレビュー」「この経歴書で通る?」「面接官目線で読んで」「多角的に
  レビューして」のような依頼、経歴書を編集した後の見直しで起動する。`persona=<name>` 引数で
  特定ペルソナだけを走らせられる(eval用)。本人しか知らない情報が必要な指摘の深掘りは
  career-grilling、企業・業界の調査は company-research / industry-research の担当。本skillは
  読んで指摘するだけで、経歴書を書き換えない。
allowed-tools: Read, Grep, Glob, Agent
disable-model-invocation: false
---

# resume-review

職務経歴書を、選考で実際に読む人の立場ごとに**別々のsubagentへ白紙で読ませる**。
1つのagentに全観点を当てると同じ前提で読むことになり、指摘が似通うためである。
主エージェント自身はレビューしない。経歴書の書き手と同じcontextにいるため、隠れた前提に気づけない。

このリポジトリは公開される。SKILL.mdとreferencesに報酬・企業名・退職理由の内情を書かない。

## 引数

| 引数 | 既定値 | 意味 |
| --- | --- | --- |
| `persona=<name>[,<name>...]` | `all` | 走らせるペルソナ。`all` = 下表の5種すべて |
| `mode=quick` | なし | `interviewer,hiring-manager` だけを走らせる簡易版 |
| `files=<path>[,<path>...]` | `README.md,detail.md` | レビュー対象 |

ペルソナが1つだけの場合は統合を省略し、そのペルソナの出力をそのまま返す(eval用)。

## ペルソナ

| name | 読み手 | 定義ファイル |
| --- | --- | --- |
| `screener` | 人事・エージェント。30秒しか読まない | [references/personas/screener.md](references/personas/screener.md) |
| `interviewer` | 現場のシニアエンジニア | [references/personas/interviewer.md](references/personas/interviewer.md) |
| `hiring-manager` | 想定レベルで採用するHiring Manager | [references/personas/hiring-manager.md](references/personas/hiring-manager.md) |
| `business` | ターゲット企業のPdM・CTO | [references/personas/business.md](references/personas/business.md) |
| `checklist` | ペルソナなし。ルーブリック全項目の網羅 | [references/personas/checklist.md](references/personas/checklist.md) |

## ワークフロー

### Step 1: 入力の確定

1. 引数からペルソナとレビュー対象を確定する。
2. README.mdの「連絡をいただきたい企業」「連絡をご遠慮いただきたい企業」節を読み、**原文のまま**ターゲット情報として抜き出す。要約・解釈を加えない(主エージェントのバイアスを混ぜないため)。
3. 経歴書そのものの中身は、主エージェントが評価しない。

### Step 2: ペルソナの並列dispatch

選んだペルソナごとに `Agent`(`subagent_type: general-purpose`)を**1メッセージ内で並列に**起動する。
バックグラウンド実行にしない。全ペルソナの結果を受け取るまで、Step 3に進まず、応答も終えない。
各subagentは互いの結果を見ない。プロンプトは次のテンプレートで組み立てる。
`references/sources.md` は根拠の記録であり、subagentには渡さない。

```markdown
あなたは職務経歴書を読む「<ペルソナ名>」です。書き手の意図は知らない前提で、
書かれているテキストだけから判断してください。ファイルは読むだけで、編集しないでください。

## あなたの立場と読み方
<references/personas/<name>.md の全文>

## ターゲット(本人が希望する応募先の条件。原文)
<Step 1で抜き出した節の原文>

## ターゲット職種の読み手が探す証跡
<references/target-profile.md の全文>

## レビュー対象
<files の各パス>。Readツールで全文を読んでから評価してください。

## 評価基準
次のルーブリックのうち、あなたの担当IDを中心に当ててください。
<references/rubric.md の全文>

## 出力形式
references/output-format.md の「ペルソナの出力」に従ってください。
<references/output-format.md の該当節の全文>
```

### Step 3: 統合

ペルソナが2つ以上なら、統合用の `Agent`(`general-purpose`)を**新規に**1つ起動する。これもバックグラウンド実行にせず、結果を受け取ってからStep 4に進む。
プロンプトには [references/integrator.md](references/integrator.md) の全文、各ペルソナの出力の原文、レビュー対象のパスを渡す。
主エージェントはペルソナの出力を書き直したり取捨選択したりしない。

### Step 4: 提示

統合agentの出力をユーザーに提示する。主エージェントが内容を書き換えない。末尾に次の2点を添える。

- `needs_user_input: yes` の指摘がある場合は、それらを `career-grilling` で深掘りする論点として一覧化して提案する
- 本人の情報なしで直せる指摘(`needs_user_input: no`)は、修正案の作成を提案する。修正は本skillの範囲外であり、ユーザーの承認後に行い、`pnpm run lint` を通す

### Step 5: やり直し

subagentがルーブリックを読まなかった、引用が不正確だった、担当外ばかり指摘した、といった場合は、
同じsubagentに追加で依頼せず、新しいsubagentを立てて再実行する(白紙性を保つため)。

## ルール

- 本skillはファイルを編集しない。commitもしない
- 指摘は、レビュー対象に実在する文の引用を根拠にする。引用できない指摘は統合段階で捨てる
- 退職理由・報酬・取引先名を、修正案として書き加える提案をしない(ルーブリックE1)
- 評価セット(欠陥を埋め込んだ経歴書)は `evals/` に置き、`claude plugin eval` で測る
