# Domain-Driven Design (Vlad Khononov "Learning DDD")

ドメインを分類して投資配分を決め、境界をひいて統合方法を選ぶレンズ。

## サブドメインの分類（投資配分の決定）

| 種類 | 性格 | 設計コスト | 例 |
|---|---|---|---|
| **Core** | 競争優位の源泉 | 高（自前で書く・ベスト道具） | 価格決定、リコメンド、独自ロジック |
| **Supporting** | 業務に必要だが差別化要素ではない | 中（簡素に・チームが書ける範囲で） | 顧客プロフィール管理、社内タスク |
| **Generic** | どこでも同じ | 低（買う・既製品） | 認証、決済（基本部分）、メール送信 |

**ルール**:
- Core にだけ Tactical DDD（集約 / 値オブジェクト / イベント）の重装備を当てる。
- Supporting に Active Record / Transaction Script で十分。Generic は SaaS / OSS。
- 「うちのは特別」は大抵 Supporting を Core 扱いしているサイン。

## ユビキタス言語

- **同じ概念を 2 つ以上の名前で呼ばない**（user / customer / account を曖昧に混ぜない）。
- **同じ語を文脈で違う意味に使うのは OK**。ただし Bounded Context を分けてその語の意味を context 内で固定する。
- **language は drift する。** ドメインエキスパートが今使っている語を上書きする。古い名前を残さない。

## Bounded Context

- 1 つのモデル / 1 つの言語が一貫して通用する範囲。物理境界（リポジトリ、サービス）と必ずしも一致させない。
- **境界 = モデル整合性が崩れる前線。** ここを越えるときは必ず変換層を経由。

### Context Map（統合パターン）

| パターン | 関係 | 使い所 |
|---|---|---|
| **Partnership** | 双方向に協力 | 同じプロダクトの中で密結合チーム |
| **Customer / Supplier** | 上流 / 下流。下流の要求を上流が受ける | 内部に上下があるとき |
| **Conformist** | 下流が上流に合わせる | 上流の言うとおりに従うしかない |
| **Anti-Corruption Layer (ACL)** | 下流が変換層を持って上流から守る | 古い / 汚いシステムと連携 |
| **Open Host Service (OHS)** | 上流が公開された API + Published Language を持つ | 多くの下流に提供する |
| **Shared Kernel** | 共有モデル | コストが高い。最後の手段 |
| **Separate Ways** | 統合しない | 重複してでも独立を保つ価値があるとき |

選んだら ADR に残す。

## 集約

- **集約 = 不変条件を守るための整合境界 = トランザクション境界。**
- **1 トランザクション 1 集約**を既定。例外は明示的根拠（性能 / モデル不整合の合法）と一緒に。
- **集約 ID で集約間を参照**（オブジェクト参照ではなく）。集約 root のみ外から参照可能。
- **集約は小さく**。整合を守るために必要な属性 / 子のみを抱える。
- **集約間の整合は eventually consistent**（domain event / outbox）。

## ドメインイベント

- **過去形で命名**（`OrderPlaced`、`PaymentFailed`）。命令形（`PlaceOrder`）はコマンド。
- **集約を変えた事実の記録。** 集約を変えずに発火する domain event は怪しい。
- **integration event** （他 Bounded Context へ送る用）は別物。domain event をそのまま外に出さない。

## 戦略的設計と CQRS / Event Sourcing の関係

- **CQRS は集約とは別軸。** 集約は書き込み整合のため、read model は別構造。
- **Event Sourcing は集約の永続化形式の選択。** 集約が複雑な履歴を持つ Core でだけ検討。詳しくは `references/architecture.md`。

## レビュー観点

- 全機能を Core 扱いして集約を切り刻んでいないか（Supporting の判別）
- 集約境界 = トランザクション境界になっているか
- 1 トランザクションで複数集約を更新していないか
- 集約間の参照が ID ではなくオブジェクトになっていないか
- ユビキタス言語に同義語が混在していないか
- Context Map が ADR に残っているか
- 統合パターン（ACL / OHS など）が明示されているか
