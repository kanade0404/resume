---
name: adr-writer
description: >-
  設計検討から出てきた決定について「これは ADR (Architecture Decision Record) に値するか」を判定し、値する場合のみ
  [adr-tools](https://github.com/npryce/adr-tools) の `adr new` コマンドで Michael
  Nygard 形式の ADR を生成するスキル。**コードを読めばわかる決定は ADR にしない**。値する基準は (1)
  将来「なぜこうした?」と疑問になりうる (2) 容易に変更できない one-way door (3) 別の選択肢があり却下した
  のいずれか。番号採番・slug 生成・テンプレ展開・supersede リンクの相互更新は全て `adr new` / `adr new -s` /
  `adr new -l` に委譲する。`design` Step 4 から呼ばれる主経路、設計判断を残したい時、「これ ADR
  にして」「決定記録残して」「architecture decision」「設計判断のドキュメント」のような要請、いずれでも必ず起動すること。本スキルは
  ADR 単体の生成と判定までで、設計検討自体や実装には関与しない。詳細仕様や API ドキュメントの代わりに ADR を使うことは推奨しない (ADR
  は「決定」の記録、「使い方」のドキュメントではない)。adr-tools が未インストールの場合は導入手順を提示し、勝手に install しない。
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
---
# ADR Writer

> **規律**: コードを読めばわかる決定を ADR にしない。**過去の自分が悩んだ理由** だけを残す。
> **道具**: 採番・テンプレ・supersede 相互更新は [adr-tools](https://github.com/npryce/adr-tools) に丸投げする。手で書かない。

ADR (Architecture Decision Record) を Michael Nygard *Documenting Architecture Decisions* (2011) の形式で生成するスキル。生成・採番・リンク管理は adr-tools (`adr` コマンド) に委譲し、本スキルは **値判定** と **Context / Decision / Consequences / Alternatives の中身埋め** に集中する。

ADR を残す目的は **将来の自分 (or 後任) が「なぜこれを選んだか」を再構築できなくなるのを防ぐ** こと。実装やテストから読める情報は ADR に書かない。

---

## いつ起動するか

- `design` Step 4 から呼ばれる (主経路)
- 既存コードベースに大きな技術選択を入れる時 (ライブラリ採択、protocol 決定、データ境界変更)
- 既存方針を覆す決定を下した時 (ADR を `Superseded by NNNN` で繋ぐ)
- ユーザに「ADR にして」「決定記録」「Architecture Decision」と言われた時

逆に **起動しない**:

- API ドキュメント / 使用方法ガイドの代わり
- 1 関数の実装方針 (コード comment で十分)
- 一過性の判断 (型を 1 つ変えた等)

---

## 前提: adr-tools の導入確認

```bash
command -v adr >/dev/null && adr help | head -1
```

未インストールなら **本スキルは ADR 生成を保留** し、ユーザに以下を提示する:

| 環境 | install |
|---|---|
| macOS (Homebrew) | `brew install adr-tools` |
| Linux (manual) | `git clone https://github.com/npryce/adr-tools && export PATH=$PWD/adr-tools/src:$PATH` |
| Nix / 其他 | upstream README 参照 |

導入完了後に再起動。**本スキルは勝手に install しない**。

---

## ワークフロー

### Step 1 — ADR 値判定

以下の **3 基準のいずれか** を満たすか判定。1 つも該当しなければ「ADR 不要」と返す。

| 基準 | 判定の問い |
|---|---|
| **Question** | 1 年後の自分が「なぜこうした?」と疑問になりうるか |
| **One-way door** | 後で変えるのに大きなコストがかかるか (DB schema / 公開 API / 永続化形式 / 採用言語等) |
| **Alternatives existed** | 別の選択肢が複数あり、意識的に却下したか |

判定の禁則：

- **「念のため残しておく」で ADR を作らない**。3 基準のいずれも満たさない場合は Step 1 で停止。
- **使用方法の記述は ADR にしない**。それは README / docstring の領域。
- **コードを音読しただけの決定** ("we use TypeScript") を ADR にしない。慣例化していて疑問にならない。

### Step 2 — ADR ディレクトリの確認 / 初期化

adr-tools は ADR の置き場所を `.adr-dir` ファイル (リポジトリルート) で指定する。確認:

```bash
test -f .adr-dir && cat .adr-dir
```

存在しなければ初期化する。プロジェクト内の既存慣例を尊重 (`docs/adr/` / `doc/adr/` / `architecture/adr/` 等):

```bash
adr init docs/adr   # 慣例があればそのパスで。指定なければ adr-tools default は doc/adr/
```

`adr init <path>` は `<path>/0001-record-architecture-decisions.md` (本制度自体の ADR) を生成する。これは慣例として残す。

### Step 3 — 新規 ADR を `adr new` で生成

タイトルは **動詞句 + 対象**。文末ピリオド無し。30 字以内目安。

```bash
adr new "Use Postgres for primary store"
# → docs/adr/0042-use-postgres-for-primary-store.md (skeleton)
```

`adr new` は以下を自動で行う:

- 既存最大番号 + 1 を 4 桁ゼロ埋めで採番
- タイトルを kebab-case slug に変換
- テンプレート (default Nygard) を skeleton として展開
- ファイル open は環境依存 (本スキルは open しない、生成されたパスを後続 step で読む)

既存方針を **覆す** 場合は `-s`:

```bash
adr new -s 17 "Use Postgres for primary store"
# → 0042 を新規作成、0017 の Status を「Superseded by 0042」に自動更新
```

**関連 ADR を双方向リンク** したい場合は `-l`:

```bash
adr new -l "12:Amends:Amended by" "Tighten retry policy"
# → 新 ADR に「Amends 0012」、ADR 0012 に「Amended by 0044」を追加
```

### Step 4 — Skeleton への中身埋め

`adr new` が生成した skeleton をエディタで開く代わりに本スキルが Edit で埋める。

#### 標準 skeleton (adr-tools default)

```markdown
# NN. Title

Date: YYYY-MM-DD

## Status

Accepted

## Context

## Decision

## Consequences
```

#### 本スキルが追記する内容

各セクションを以下の規律で埋める:

**Context** (事実のみ、1-3 段落):

- 外部要因: SLA / 法令 / 他チーム契約 / パフォーマンス予算等、コードから読めない事実
- 既存の関連決定: ADR への相互参照 (`See ADR 0017`)
- 制約条件: リソース / 時間 / スキル

「~したい」「~であるべき」は書かない。それは Decision。

**Decision** (命令形 1 段落):

- "We will use X" / "X を採用する"
- 条件付き決定 ("If we hit Y, then Z") は別 ADR に分割

**Consequences** (Positive / Negative 両方必須):

```markdown
## Consequences

### Positive
- この決定が解く問題 / 得られる性質

### Negative
- この決定で生じる制約 / 受け入れるトレードオフ

### Neutral
- 注記事項。後続決定の trigger になる前提
```

トレードオフのない決定は ADR に値しないと判定し直し、Step 1 に戻る。

**Alternatives Considered** (最低 2 案、各 1-2 行):

```markdown
## Alternatives Considered

### Option A: <名前>
- 概要: ...
- 却下理由: ...

### Option B: <名前>
- 概要: ...
- 却下理由: ...
```

「他案を検討していない」と書くくらいなら ADR を作らない (Step 1 に戻る)。

なお adr-tools default template には Alternatives Considered セクションが無い。プロジェクトで永続的にこの形式を使うなら **`<adr-dir>/templates/template.md` をカスタマイズ** することで `adr new` が常にこの structure で skeleton を出す (本スキルは template の install は提案するだけ、自動配置はしない。提案は出力フォーマット参照)。

### Step 5 — Status 管理

新規作成時は基本 `Accepted` (proposed → review → accepted を経ているなら直接 Accepted)。

`adr new -s NN` を使えば旧 ADR の Status は自動で `Superseded by NNNN` に書き換わる。`-s` を使わずに手で supersede した場合は Edit で旧 ADR の Status 行のみ更新 (本文の Decision / Context は触らない)。

既存 ADR を **削除しない**。supersede でも歴史として残す。

### Step 6 — Index / TOC の生成 (任意)

```bash
adr generate toc > "$(cat .adr-dir)/README.md"
```

リポジトリ慣例で TOC を `README.md` として残す場合のみ実行する。本スキルは TOC を強制せず、推奨提示にとどめる。

`adr generate graph` で Graphviz の依存関係図も出せる (supersede / amend リンクの可視化)。これも提案までで自動実行しない。

---

## 出力フォーマット

```markdown
## ADR Decision

### 値判定
- 該当基準: Question / One-way door / Alternatives existed (該当のみ列挙)
- 値する: Yes / No

### Yes の場合
- File: <adr-dir>/<NNNN>-<slug>.md (例: docs/adr/0042-use-postgres-for-primary-store.md)
- Status: Accepted | Superseded by NNNN | ...
- Title: <タイトル>
- Supersedes: <NNNN if any>
- Used commands:
  - `adr new "..."` (新規)
  - `adr new -s NN "..."` (supersede)
  - `adr new -l "NN:Amends:Amended by" "..."` (amend / 双方向)

### No の場合
- 理由: <1 行>
- 推奨: コメント / README / 何も書かない のいずれか

### template カスタマイズ (推奨提示のみ)
- `<adr-dir>/templates/template.md` を置けば `adr new` が常に Alternatives Considered + Positive/Negative/Neutral 細分化された skeleton を出す
- 提案ファイル内容: <添付>
```

---

## 出力する成果物 / 出力しない成果物

### 出力する成果物

- **`<adr-dir>/<NNNN>-<slug>.md` 1 ファイル** (Nygard 形式、`adr new` 経由で生成、本スキルが Context / Decision / Consequences / Alternatives を埋める)
- **値判定結果** (Yes / No + 該当した基準 + 理由 1 行)
- **既存 ADR の Status 行更新** (`adr new -s` が自動で実行、本スキルは指示と検証のみ)
- **テンプレートカスタマイズ提案文字列** (`<adr-dir>/templates/template.md` の推奨内容、提示のみ)

### 出力しない成果物

- **使用方法 / API ドキュメント文字列**: README / docstring / コード comment 領域、ADR には書かない。
- **複数決定を含む 1 ADR**: 1 ADR = 1 決定。関連決定の統合 ADR は出さない。
- **「仕様書」としての ADR**: 仕様は実装が真実の源、本スキルは決定の記録のみ出す。
- **古い ADR の本文編集差分** (Status 行と `adr new -s/-l` 自動更新を除く): 歴史を残すため、Decision / Context / Consequences の事後編集は出さない。
- **自動 supersede 判定結果**: 新決定が旧 ADR を覆すかの判断は人間 / `design` の責任、本スキルは `-s` 引数として渡された関係のみ反映する。
- **`<adr-dir>/README.md` (TOC) の自動編集差分**: `adr generate toc` の実行は推奨提示までで、自動 commit は出さない。
- **adr-tools 自体の install コマンド実行**: 環境依存のため、install 手順を提示するのみ。

---

## 既知の限界

- **adr-tools 依存**: bash 製 CLI (npryce/adr-tools) に依存する。インストールが面倒な環境 (Windows ネイティブ等) では代替実装 (`adr-manager`, Python 製 fork 等) の選択も可能だが、本スキルは upstream の adr-tools のみ前提とする。
- **default template に Alternatives セクションが無い**: adr-tools の skeleton は最小限。本スキルは `<adr-dir>/templates/template.md` のカスタマイズを推奨するが、適用するかはプロジェクト判断。template 未適用時は本スキルが Edit で section を追加する。
- **値判定の主観**: 3 基準は曖昧さを残す。判定が割れたらユーザに尋ねる。**過剰に ADR を残すよりは少ない方を選ぶ** (rot 防止)。
- **採番の並行競合**: `adr new` は実行時の最大番号 + 1 を採番するため、別 PR で同番号を取る競合は CLI 側でも防げない。マージ時に rebase して `adr` ファイル名を rename する手作業が必要 (本スキルでは自動解決しない)。
- **MADR 形式は採用しない**: より構造化された MADR (Markdown Architectural Decision Records) を選択することも可能だが、本スキルは adr-tools の default Nygard を採用。MADR を使うなら別 skill / 別 template が必要。
