# 顧客=自分自身パターンの bias 除去プロトコル

個人プロダクト・社内ツール・実験的ボット・自分用 CLI など、**顧客が自分自身（or 家族・身近な少人数）** であるケースのために置く参照。

本 skill のスタンス: 顧客=自分自身パターンは「劣化版 discovery」ではなく、**discovery の正規パターン**として扱う。N=1 でも rigor は確保できる。ただし以下のバイアスが構造的に強く出るので明示的に防御する。

---

## このパターンで出るバイアス

| バイアス | 症状 |
|---|---|
| **confirmation bias** | 自分が欲しい結論に合う観察だけ集めて、合わない観察を忘れる |
| **planning fallacy** | 自作だから維持できると過信し、半年後に放置 |
| **endowment effect** | 既に書いたコード / アイデアに引きずられて outcome を曲げる |
| **availability bias** | 直近の苛立ちだけが outcome を支配する（実は週 1 回しか起きない問題かも） |
| **social desirability の不在** | 顧客インタビューでは抑圧される「面倒だから使わない」が、自分相手だと逆に過小評価される |

これらに対する反証手順を Phase C/D の前に通す。

---

## 4 つの bias check（必須）

PRD 本文の `§Self-check` セクションに各項目を埋める。書けない項目があれば**その時点では PRD を完成させず Phase B/C に戻る**。

### 1. Specific Instance — 「直近の実例を 1 つ」

直近 2 週間で「実際にその痛みが起きた瞬間」を時系列で 1 つ書ける必要がある。

良い例:
> 4/29 19:30、夕食の献立を考えるのに 23 分かかり、結局昨日と同じになった。冷蔵庫の中身を見るたびに思い出さなくてはいけないのが嫌だった。

悪い例（generic complaint）:
> いつも献立決めに困っている。

書けないなら **availability bias** の疑いあり。outcome を retain するなら頻度を計測する 1 週間の log を取ることを Phase D の test にする。

### 2. Inversion — 「自分でなかったら欲しいか」

「**もし自分以外の同じ状況の人**（家族 / 同僚 / 似た嗜好の友人）がこれを使うとしたら、欲しがるか」を仮定で答える。

- 答えが **明確に yes**（具体的に思い浮かぶ人がいる）→ scope は「自分 + 周囲数名」
- 答えが **微妙 / no** → scope を「自分専用」と Meta に明記する。これは悪いことではない。**自分専用**だと明示することで、PRD の品質基準が変わる（汎用性 / 一般化を諦めて、自己観察を信頼する）

inversion で「全人類が欲しいはず」と答えたくなったら **confirmation bias の警報**。Phase C に戻る。

### 3. Alternative Observed — 「今やってる代替行動」

CDH の核心: 「customer が今すでにやっている代替行動 / workaround」を 1 つ以上挙げる。

書けないなら、その痛みは**そもそも痛みでない**可能性が高い（人は痛ければ何かしら代替してる）。

例:
- 献立決め → 「クックパッドの履歴を見る / 妻に丸投げする」
- メール整理 → 「未読を放置して土曜日にまとめて見る」
- ノート整理 → 「Slack の自分宛 DM に投げて検索で探す」

代替行動が「**実用的に成立している**」なら、新しい解の value risk は高い（既に解けてる）。代替行動が**苦痛で持続できない**なら value がある。

### 4. Viability Self-check — 「半年後も触るか」

INSPIRED の viability を **個人プロダクトに翻訳**したもの。

- 自分が運用 / メンテできる技術スタックか
- 半年後に「使い続けるモチベーション」があるか（hobby vs tool の見極め）
- 月額コスト / API rate limit / インフラ管理の負荷が自分の許容範囲か
- **やめる時の出口**は確保できているか（データのエクスポート / 依存解除）

書けないなら viability risk が riskiest assumption になりがち。Phase D で必ず取り上げる。

---

## scope の宣言

bias check の結果、PRD の §Meta に以下を明記する:

```yaml
customer_type: self          # self | self-and-close-circle | external | mix
self_only: true              # inversion の結果（自分専用なら true）
sample_size: 1               # N=1 を隠さない
generalization_claimed: false # 一般化主張があるか
```

`self_only: true` の PRD は、prd-review で「外部顧客向けの validation 不足」を must 指摘から除外する契約にする（過剰な客観性要求は意味がない）。

---

## 「家族 + 自分」「友人 5 人」などの近接コミュニティ

最も誤読されやすいゾーン。N が小さい外部ユーザに見えるが、実態は**自分自身 + わずかな観測対象**。

ルール:

- 観測対象（家族 / 友人）には **specific instance を本人由来で 1 件**確保する（推測ではなく実観察）
- 観測対象が 5 人以上なら external 寄り、4 人以下なら self-and-close-circle 扱いで bias check は self と同様に厳しく
- 観測対象が嫌がる UX を **過小評価しない**（家族が「面倒」と一言言ったら value risk として扱う）

---

## このプロトコルで判定が変わる典型例

| 入力 | bias check 後の判定 |
|---|---|
| 「献立 bot 作りたい。みんな困ってるはず」 | inversion で具体名が出ない → self_only: true、scope を縮める |
| 「ToDo app を作りたい」 | alternative observed が「Reminders.app で十分機能してる」→ value risk 高、Phase B 再検討 |
| 「読書管理 SaaS」 | viability で「半年後も触るか」が no → hobby project として明示し scale 想定を捨てる |
| 「家族で使うレシピ共有」 | 家族 1 人が「面倒」と言った → usability risk を riskiest に格上げ |

---

## prd-review への引き渡し

`§Self-check` ブロックに上記 4 項目の結果と scope 宣言を埋めた PRD を `prd-review` に渡す。レビュー側はこのブロックを読んで、レビュー観点を **self_only スコープ用** に絞る運用とする（詳細は `handoff-protocol.md`）。
