# ライブラリ・ツール評価

技術選定における実務チェックリスト。ライブラリ・フレームワーク・ツール・サービスを評価する際に使う。

## 27項目チェックリスト

5カテゴリに分類（A:7, B:5, C:6, D:4, E:5）。半分以上（14項目以上）埋まらなければ情報不足と判定し、追加調査するか「情報不足のため判断保留」と明記する。

### A. プロジェクトの健康度

- [ ] 最終コミット日時
- [ ] 過去12か月のリリース頻度
- [ ] アクティブなメンテナ数（bus factor = 何人辞めたら止まるか）
- [ ] Open Issue / Closed Issue の比率、平均クローズ時間
- [ ] メンテナの所属（個人 / 財団 / 企業）と継続の蓋然性
- [ ] スポンサー・資金源
- [ ] GitHub Stars / Download の推移グラフ

### B. API / 実装

- [ ] 公式ドキュメントの完成度と鮮度
- [ ] CHANGELOG が継続的にメンテされているか
- [ ] Semantic Versioning の遵守度、破壊的変更ポリシー
- [ ] 型定義（TypeScript, stubs）の質
- [ ] テストカバレッジ、CI 状況

### C. 運用

- [ ] License（プロジェクト互換性、再配布、特許条項）
- [ ] Dependency tree の深さ・サイズ
- [ ] Bundle size / コールドスタート時間
- [ ] Runtime performance（自分のユースケースで実測）
- [ ] Memory footprint
- [ ] 既知の CVE（GHSA, Snyk, OSV）、Supply chain（publisher 2FA, 署名, SBOM）

### D. エコシステム

- [ ] 類似・競合ライブラリの存在
- [ ] 統合可能な周辺ツール
- [ ] コミュニティ規模（Discord, Slack, Reddit, Stack Overflow 質問数）
- [ ] 日本語情報の有無（チーム言語環境次第）

### E. 戦略適合

- [ ] 解こうとしている問題が本質的に解けるか
- [ ] 5年後にも維持されている蓋然性
- [ ] Lock-in の強度、乗り換えコスト
- [ ] 自前実装した場合のコスト（Build vs Buy）
- [ ] プロジェクト規約（ライセンス、言語、フレームワーク）との整合

---

## Thoughtworks Tech Radar 方式

Thoughtworks が半年ごとに出している業界レーダー。自分たちのチーム版を作るのも有効。

**4象限**:

- Languages & Frameworks
- Tools
- Platforms
- Techniques

**4リング**:

- **Adopt** — デフォルトで採用
- **Trial** — 積極的に試す段階
- **Assess** — 注視する段階
- **Hold** — 新規採用を避ける

新規ライブラリを見たらまず「自分たちのレーダーのどこに置くか」を判断すると、軽率な Adopt を避けられる。

---

## Build vs Buy

### Buy を先に検討する

- 既存があれば「維持コスト」が外部化される
- 自作はしばしば見積もりを大幅に超過する
- 維持が必要になる期間が読めない

### Build が正当化される条件

- **中核差別化要因** — 自社の競争優位に直結
- **既存が致命的に不足** — どのプロダクトも解いていない
- **Lock-in リスクが受容不能** — 業界の寡占ベンダーに握られる

### Fork

最後の手段。Fork するなら:

- 上流に還元する覚悟
- あるいは完全に別プロダクトにする覚悟

曖昧な Fork は長期維持コストの地雷。

---

## RFC / ADR の違い

| | RFC | ADR |
|--|-----|-----|
| 状態 | 提案中 | 決定済み |
| 発祥 | IETF / Rust / PEP / Go proposal | Michael Nygard 2011 |
| 目的 | 公開議論 | 意思決定の記録 |
| タイミング | 提案時 | 実装時 |

Aegis プロジェクトは ADR を使う。**計画段階では書かず、実装時の意思決定が発生したタイミングで書く**（CLAUDE.md 準拠）。

### ADR フォーマット

```
# ADR-NNNN: タイトル
Status: Proposed | Accepted | Deprecated | Superseded by ADR-XXXX
Context: 意思決定が必要になった背景
Decision: 何を決めたか
Consequences:
  - Positive: 良い面
  - Negative: 悪い面
  - Neutral: 中立的な影響
```

---

## 探索的実装の型

### Spike（XP）

タイムボックス化した技術調査。成果は捨てる前提。未知技術の感触を掴む。

- 時間制限: 最大1-2日
- 成果: 知見。コードは捨てる
- ドキュメント: どこがハマりそうか、どこが容易か

### PoC（Proof of Concept）

「これで本当に解けるか」を最小コストで証明する。

- 本番品質を要求しない
- 最小のスコープ、最大の不確実性を潰す
- 成功基準を事前に書く

### Tracer Bullet（Hunt & Thomas）

エンドツーエンドの最薄い実装を通す。骨格で全系を確認してから肉付け。

- UI → API → DB → UI の往復を最小実装で通す
- 統合の問題を早期発現させる

### Walking Skeleton（Alistair Cockburn）

Tracer Bullet に近い。最小構成で全層を通す。デプロイパイプラインまで含む。

---

## ベンチマーク

### マイクロベンチ

- ツール: Benchmark.js, criterion.rs, JMH, pytest-benchmark
- 注意: ウォームアップ、統計的繰り返し、外れ値除去、Steady-state 到達
- 罠: JIT、GC、キャッシュ効果、分岐予測

### マクロベンチ / E2E

- ツール: k6, Locust, JMeter, wrk
- 本番相当シナリオで測る
- レイテンシのパーセンタイル（p50, p95, p99）を見る。平均だけ見ない

### プロファイリング

- CPU / Memory / Flame graph
- Brendan Gregg の Flame Graph 図法が標準
- pyflame, py-spy, perf, dtrace, eBPF

---

## セキュリティ評価

### 脆弱性データベース

- **CVE / NVD** — 標準
- **GHSA** — GitHub Security Advisory
- **OSV** — Open Source Vulnerabilities (Google)
- **Snyk / Socket.dev** — 商用スキャン

### 脅威モデリング

- **STRIDE**: Spoofing / Tampering / Repudiation / Info disclosure / DoS / Elevation of privilege
- **MITRE ATT&CK**: 実在攻撃の戦術・技法カタログ
- **OWASP Top 10**: Web アプリの典型的脅威
- Adam Shostack『Threat Modeling: Designing for Security』

### Supply Chain

- 公開者（publisher）の 2FA 有効化
- 署名された成果物（Sigstore / PGP）
- SBOM（Software Bill of Materials）の提供
- 依存の依存（transitive deps）までスキャン
- Typosquatting / Dependency confusion のリスク
