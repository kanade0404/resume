# データスタックテストレビュー (Supabase / PostgreSQL / pgvector / RLS / n8n)

データ層（スキーマ、RLS、pgvector、n8n ワークフロー）を運ぶテストのレビュー観点。

> **このリポジトリの現状**: 本ドキュメント執筆時点で、リポジトリには Supabase 設定（`supabase/` ディレクトリ、マイグレーション、`.sql` テスト）も、n8n ワークフロー（`workflows/*.json`）も、pre-commit 設定も存在しない。したがって以下の記述は、**データスタックを導入する PR を書く / レビューするときの推奨指針** として読むこと。現状の PR を却下する根拠にはならない。実際の配線（CI ジョブ、pre-commit フック、supabase CLI ワークフロー）は、初回導入の PR で本ドキュメントと同期して作成すること。

---

## Supabase ローカルスタック（導入時）

- ローカル開発: `supabase start`（フルスタック）。CI: `supabase db start`（Postgres + migrations のみ）で高速化。
- フルスタックが不要な Python テスト一式は `testcontainers-python` を session scope + `reuse=True` で起動する方が軽い。

## マイグレーション（導入時）

- `supabase migration new <name>` で timestamped SQL。
- `supabase db diff` でスキーマ差分を検証。
- **Linting**: `squawk` を pre-commit に入れると `ADD COLUMN NOT NULL`、FK への index 抜け、lock-heavy なパターン、prod-unsafe な変更を検出できる。
- **CI dry-run**: 各マイグレーションを (a) 空 DB、(b) production スキーマダンプの両方に流す。両方通ること。
- **ゼロダウンタイムパターン** (expand/contract あるいは `pgroll`): ホットテーブルに触る場合は expand/contract ペアをレビューで要求する。

## Row-Level Security (RLS)

Safety 原則の中心。新規ユーザーデータテーブルの PR が RLS assertion なしで上がってきたら不完全。

- **pgTAP + `supabase/test_helpers`** がデファクト。`tests.authenticate_as('authenticated', '<user_uuid>')` でロール切替。
- **3 ロールすべてをカバーする**: `anon`, `authenticated`, `service_role`。各ポリシーごとに挙動が違う。
- **ロール × positive/negative の掛け合わせ**:
  - ユーザー A として、自分の行を読めるか? (positive)
  - ユーザー A として、ユーザー B の行を読めるか? (negative)
  - ユーザー A として、join や CTE の裏技でユーザー B の行を更新できるか? (negative)
  - anon で、テーブルが完全に不可視か? (negative)
- **ポリシー diff にはテスト diff が伴う**。PR がポリシーを変更したら、少なくとも 1 つの pgTAP テストを同時に動かす。

サンプル:

```sql
BEGIN;
SELECT plan(4);

SELECT tests.authenticate_as('authenticated', 'aaaa...');
SELECT results_eq(
  $$SELECT count(*) FROM messages WHERE user_id = 'aaaa...'$$,
  $$SELECT 3::bigint$$,
  'user A sees own 3 messages'
);
SELECT results_eq(
  $$SELECT count(*) FROM messages WHERE user_id = 'bbbb...'$$,
  $$SELECT 0::bigint$$,
  'user A cannot see user B messages'
);
SELECT tests.clear_authentication();
-- ... anon と service_role のケースを続ける ...

SELECT finish();
ROLLBACK;
```

## pgvector

- **埋め込みの決定性**。`embedding_model` と `embedding_version` カラムを持つ。テストは固定埋め込み（事前計算 JSON）を fixture として使い、モデルの升バンプがサイレントに recall を変えないようにする。
- **距離メトリック**がインデックスと一致していること（`vector_cosine_ops` / `vector_l2_ops` / `vector_ip_ops`）。不一致は negative ケースとしてテストする。
- **インデックス使用の確認**。PR がインデックス追加を含むなら、query planner が実際にそれを使うか `EXPLAIN (FORMAT JSON)` で確認し、`Index Scan using ...` が現れることを assert する。
- **recall 閾値**。関連性既知の golden dataset に対して `recall@10`, `nDCG@10` が設定済み floor を下回ったら CI fail。HNSW と IVFFlat で別閾値を設定する。

## トランザクション分離（テストごと）

- 各テストを独自トランザクション内で実行し、teardown で rollback（SAVEPOINT ネスト）する。`TRUNCATE` より 10 倍高速。
- `pytest-postgresql` か、`asyncpg` の上に手書き async fixture を使う。
- テスト間でロールバックなしに共有データを変更するパターンは却下 — 順序依存が入る。

## 冪等性 (Order 原則)

webhook / cron 駆動の書き込みは重複排除する：

- テーブル `processed_events(id uuid pk, source text, key text, unique(source, key))`。
- 書き込みは `INSERT ... ON CONFLICT DO NOTHING`。
- テスト: 同じイベントを 3 回送り、ターゲットテーブルがちょうど 1 行増えることを assert する。
- レビュー: 書き込みパスに dedup key が無い場合、ハンドラが本質的に冪等でない限り指摘する。

## テストデータ生成

- **polyfactory** > factory-boy（Pydantic v2 ネイティブ）。
- 匿名化 production ダンプは `pg_anonymizer` または `neosync` 経由で。生 prod をテスト環境に置かない。
- snapshot 近接の assertion には静的 JSON fixture。

## Supabase クライアント契約

- `supabase gen types python` / `typescript` を pre-commit で自動化。スキーマ PR には生成ファイルの diff を必ず同梱する。
- 生 `createClient()` がアプリコードに出ていたら指摘対象。型パラメタ化されていないのは契約を捨てている。

## Edge Functions (Deno)

- `deno test --allow-net --allow-env` で unit。
- 外部呼び出しは `@supabase/functions-js` の Request/Response スタブでモック。
- `supabase functions serve` でローカル integration、`supabase functions deploy --dry-run` で deploy manifest を検証。

## Storage と Realtime

- **Signed URL**: 生成 → HEAD リクエスト → 有効期限と content-type を検証。バケットレベル RLS は pgTAP でカバーする。
- **Realtime**: `ws` モックサーバーに接続し、3 種の channel（`broadcast`, `presence`, `postgres_changes`）を個別に assert。

---

## n8n ワークフローテスト

### workflow.json のバージョニング

- `n8n export:workflow --all` でワークフローを `workflows/*.json` として Git 管理。
- CI で snapshot-diff — 未説明の変更は fail させる。
- `n8n import:workflow` をクリーン n8n インスタンスに対して実行し、ファイルが valid かつ self-consistent かを検証する。

### カスタムノード

- `@n8n/node-dev` でスキャフォールド。テストはノードの隣に置く。
- `INodeType.execute` を、`INodeExecutionData` を受けて結果を返す純関数に切り出す。ノード本体は入出力の配線だけを受け持つ。
- Jest も Vitest も可。

### Webhook

- `n8n webhook:test <name>` でローカル実行。
- 署名ヘッダ（`X-N8N-Signature` など）をハンドラ内で検証する。検証ロジック自体を、正当 payload と改ざん payload の両方でテストする。

### 外部 API 契約

- Claude API 呼び出しはワークフロー実行時にローカルモック（LiteLLM proxy の record/replay モード、`anthropic-mock`）を使う。ワークフロー CI で実 API を叩かない。
- 外部 REST は `prism mock` / `wiremock` を立ててスペック駆動でモック。

### Credentials

- 暗号化キー（`N8N_ENCRYPTION_KEY`）は環境ごと（dev / staging / prod）に分離。テストは dev キー + dev credentials で走る。暗号化キーを export / commit しない。

### Observability

- n8n の `executions` テーブルを Supabase にミラーして集中ダッシュボードに。
- エラー時の Discord webhook 通知テストは `httpbin` に送る。実 Discord チャンネルには絶対に送らない。

## データスタック固有のレビュー指摘

- RLS ポリシーなしの新規テーブル、かつ RLS テストもなし → Critical。
- カラムデフォルト追加 + 非同期バックフィル、feature flag なし → Critical。
- pgvector インデックス追加、recall floor テストなし → Major。
- webhook 駆動の書き込みパスに dedup key なし → Major。
- アプリコードに `service_role` 使用（server-side admin 操作以外） → Critical。
- 本物のユーザー ID に見えるハードコード UUID → prod データでないか確認 → Major。
- コード / 設定の変更なしに n8n workflow.json の diff だけ → Major（事故キャプチャの可能性）。
