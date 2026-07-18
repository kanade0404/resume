# Architecture: Fundamentals (Richards & Ford) + CQRS + Event Sourcing

「アーキテクチャ特性」「アーキテクチャ量子」を意思決定の単位とし、CQRS / Event Sourcing を採否含めて評価する。

## Fundamentals of Software Architecture（Richards & Ford）

### アーキテクチャ特性

- **特性 = -ility 群**: performance, availability, scalability, evolvability, security, observability, deployability, simplicity, cost …
- **3 つまでに絞る。** 「全部大事」は決定の放棄。**最重要 1〜2、副次 1〜2（合計 3 つまで）** を ADR に書く。
- **特性同士のトレードオフを明示**: 高 availability と低 cost、強 consistency と高 throughput、simplicity と extensibility は通常両立しない。

### アーキテクチャ量子

- **量子 = 高凝集で独立にデプロイ可能な単位 + ランタイム依存の集合。**
- 1 量子か複数量子かで取れる選択肢がまるで違う：
  - 1 量子 → モノリス系（layered, modular monolith）が候補
  - 複数量子 → サービス系（microservices, event-driven, microkernel）が候補
- **同期通信は量子境界を曖昧にする**。境界をまたぐ呼び出しが多ければ実質 1 量子（=分けた意味がない）。

### スタイルの選定

- **Monolith** は「単純さ」「deployability」を最大化する。最初に否定しない。
- **Modular Monolith** は monolith + module 境界。多くのプロダクトのスイートスポット。
- **Microservices** はデプロイ独立 / チーム独立を要求する規模で初めて元が取れる。会社規模・チーム規模・取扱トラフィックを見て判断。
- **Event-Driven** は時間結合を緩めるが、デバッグ・整合・順序保証のコストを別の場所に押し出すだけ。
- **Layered Architecture** は下層変更が上層を直撃しがちで、進化容易性に弱い。
- **Hexagonal / Ports and Adapters** は I/O 境界の分離が常時欲しいときに採る。

スタイル選定の決め手は「どの -ility を優先したか」。それが書けないなら ADR を書く前。

## CQRS（Command Query Responsibility Segregation）

### CQRS とは

- **書き** と **読み** に異なるモデル / 異なるストレージを使う設計。
- "1 メソッドは command か query のどちらか" という CQS（Meyer）とは別物。CQRS は「モデル分離」のレベル。

### 採用判断

採用が正当化される条件（複数満たすと強い）：

- **read と write の負荷比が桁違い**（read が 100x など）
- **read 側に書き込みモデルでは答えられない問い合わせがある**（複雑な検索、集計、絞り込み、別コンテキストとの結合）
- **read 側 SLA と write 側 SLA が違う**（read は eventual consistency で良い、write は強い整合）
- **read model を独立にスケール / キャッシュ / 投影し直したい**

### 採用しない判断（よくある）

- 単に「将来役に立つかも」で入れる
- 単に CRUD が肥大化したから
- 単に「DDD の本に出ていたから」

### よくある実装形

- **同一 DB 内で read view（projection）を別テーブル / マテビューに作る** → 軽量 CQRS。
- **read 専用の別 DB を立てて domain event を投影する** → 本格 CQRS。
- **CQRS と Event Sourcing は独立に採る**。CQRS なし ES、ES なし CQRS、両方、どちらもなし、の 4 通り。

## Event Sourcing（ES）

### ES とは

- 集約の状態を「現在値」ではなく **「全変更の事象列」** で永続化し、再生で状態を得る。
- イベントは過去形（`OrderPlaced`、`AmountReduced`、`Cancelled`）。
- **イベントは追記専用 / 不変**。修正イベントは打ち消しイベントを足す。

### 採用判断

ES は強力だが導入コストが高い。次のいずれかに **本気で価値がある** ときだけ採用：

- **監査要件**: 誰が・いつ・何をしたかを完全に再構成する必要がある（金融、医療、法務）
- **時系列再生 / 過去状態の再現**: "去年の今この時点" のレポートが業務価値
- **複雑な状態遷移を集約として表現したい**: 状態の理由を全部辿れる必要がある
- **複数の read model を将来も増やす想定がある**: ES + CQRS が綺麗に組める

逆に **典型的 CRUD には不要**。よくある反対指標：

- 整合は "今の値が正しい" だけで良い
- レポーティングは集計クエリで足りる
- 監査は `audit_log` テーブルに更新差分を書けば足りる

### 設計上の注意

- **イベントスキーマの進化**: イベントは永続。古いイベントは消えない。バージョニングと upcaster が必要。
- **スナップショット**: 再生コストが上がったら定期スナップショットを取る。
- **冪等性**: イベント適用は決定論的かつ冪等であること（同じイベント列から同じ状態）。
- **副作用とイベント発火の分離**: イベントの "保存" と "発火（外部通知）" を atomic にするには outbox パターン等が要る。

## レビュー観点

- 採用したアーキテクチャ特性が 3 個以下に絞れているか / ADR にあるか
- 量子の数が意図した通りか（同期呼び出しで実質 1 量子になっていないか）
- スタイル選定の理由が「どの -ility を優先したか」で書けているか
- CQRS / ES が「採用したい理由」「採用しない理由」両方で評価されたか
- ES のイベントスキーマ進化方針が決まっているか
- "なんとなく microservices" になっていないか
