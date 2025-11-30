# 坂田誠也

## サマリー

- 0→1フェーズのB2B SaaSを技術責任者として担当し、戦略検討からインフラ・サーバサイド・フロントエンドまで一気通貫で開発している。
- 広告配信基盤、クラウドインフラ最適化、LLM/AI Agent活用を主戦場とし、事業KPIやeCPMなどの改善につなげている。
- 個人PMとして複数プロジェクトを並走し、外部パートナーの採用や育成、コーディングAIの導入などチームづくりも担っている。
- このドキュメントは面接やディスカッションで深掘る論点と再現性のある手法をまとめた補足資料である。

## 経験タイムライン

| 期間 | 企業 / 役割 | チーム規模 | ハイライト |
| --- | --- | --- | --- |
| 2022年8月〜現在 | 株式会社Speee / Tech Lead, Architect | 3〜6名（業務委託含む） | 広告配信プロダクトと広告調査SaaSの技術リード。インフラ刷新やDSP連携でeCPM改善、AI Coding Tool導入を担当。 |
| 2022年5月〜10月 | フリーランス（業務委託） / Full Stack Eng. | 基本単独 | EC検索改善や複業SaaSの機能追加をミニマムチームで支援。 |
| 2019年8月〜2022年5月 | 株式会社ビットエー / Tech Lead | 6〜10名規模 | 広告配信DMPとAI/VR不動産プロダクトを担当し、GCP×TerraformでのDMP構築とPoC通過、障害ゼロ運用を達成。 |
| 2018年7月〜2019年7月 | 株式会社スタッフサービス（エンジニアリング事業本部） / Software Eng. | 3〜6名規模 | 衛星画像分析Webアプリや製薬向けWindowsアプリを開発し、テスト観点と品質保証を実務で習得。 |
| 2018年4月〜6月 | FIT株式会社 / Junior Eng. | 3名規模 | 太陽光発電パネルの統計Webアプリを担当し、複数技術のキャッチアップと短納期開発を経験。 |

## Table Of Contents

- [坂田誠也](#坂田誠也)
  - [サマリー](#サマリー)
  - [経験タイムライン](#経験タイムライン)
  - [Table Of Contents](#table-of-contents)
  - [自己紹介](#自己紹介)
  - [経歴一覧](#経歴一覧)
    - [株式会社Speee（2022年8月〜）※2022年8月〜2023年4月は業務委託](#株式会社speee2022年8月2022年8月2023年4月は業務委託)
      - [広告配信プラットフォームの開発](#広告配信プラットフォームの開発)
      - [広告調査SaaS立ち上げ](#広告調査saas立ち上げ)
    - [フリーランス（業務委託、2022年5月〜10月）](#フリーランス業務委託2022年5月10月)
      - [EC検索改善／複業マッチングSaaS支援（計6カ月）](#ec検索改善複業マッチングsaas支援計6カ月)
    - [株式会社ビットエー（2019年8月〜2022年5月）](#株式会社ビットエー2019年8月2022年5月)
      - [広告配信の最適化基盤・社内Webアプリ（美容系の広告代理店向け）](#広告配信の最適化基盤社内webアプリ美容系の広告代理店向け)
      - [AI/VRを活用した不動産仲介プラットフォーム](#aivrを活用した不動産仲介プラットフォーム)
    - [株式会社スタッフサービス（エンジニアリング事業本部）（2018年7月〜2019年7月）](#株式会社スタッフサービスエンジニアリング事業本部2018年7月2019年7月)
      - [衛星画像の分析支援Webアプリケーション](#衛星画像の分析支援webアプリケーション)
      - [製薬開発支援Windowsアプリケーション](#製薬開発支援windowsアプリケーション)
    - [FIT株式会社（2018年4月〜6月）](#fit株式会社2018年4月6月)
  - [できること・得意なこと](#できること得意なこと)

## 自己紹介

坂田誠也（インターネット上のハンドルは「かなで」）。東京都在住。

2018年4月よりWebのエンジニアとしてキャリアを開始しています。

主たる領域はサーバサイド開発とクラウドを使ったインフラ構築、多少はWebフロントエンド開発の心得があります。

[twitter](https://twitter.com/py_kanade0404)

[GitHub](https://github.com/kanade0404)

[はてなブログ](https://kana-kanade.hatenablog.com/)

[Obsidian Publish](https://publish.obsidian.md/kanade0404/kanade0404+memo)

[LAPRAS](https://lapras.com/public/XNYCJEI)

[Scrapbox（ほぼ停止）](https://scrapbox.io/pykanade/)

## 経歴一覧

※各プロジェクトはChallenge/Role/Actions/Result/Scale/Teamに並べた独自テンプレート（STAR系）で記述している。

### [株式会社Speee](https://speee.jp/)（2022年8月〜）※2022年8月〜2023年4月は業務委託

#### 広告配信プラットフォームの開発

- **Challenge:** 広告配信サーバやバッチ、管理画面、アドタグなど複数のコンポーネントを限られた正社員だけで保守しながら、バージョン老朽化と外部DSP連携の要求を解消する必要がありました。
- **Role:** Tech Lead兼個人PMとして、要件整理から設計・実装・運用までを一人称で担当。
- **Actions:**
  - Node.js／Terraform／Jenkins／Goなど主要ランタイムを最新LTSへアップグレード（Goではloopvar対応も実施）し、IaCとCDパイプラインを共通化。
  - EC2上のJenkinsを2.xにリプレースし、ジョブ設計と周辺AWSリソースをまとめて再構築。
  - 外部DSP連携機能、新しいアドタグ、社内バッチ群を要件定義〜実装までリード。
  - アドベリツール導入に合わせ、ブロック対象IPを配信サーバへ連携し事前除外を自動化。
- **Result:**
  - eCPM向上につながる外部在庫接続を実現。
  - 不正クリック監視の自動化で突発タスクを削減。
  - Auroraアップデート後に遅延したSQLを改善し、配信運用の安定性を向上。
- **Scale:** 広告配信サーバ、バッチ、管理画面、アドタグ。
  AWS（EC2, RDS, S3）/ Akamai / Terraform / Airflow / Go / Python / Node.js(TypeScript) / MySQL。
- **Team:** 正社員1名＋業務委託0〜2名でスプリント単位に再編し、外部協力会社とはAPI仕様書と進捗レポートで連携。

#### 広告調査SaaS立ち上げ

- **Challenge:** 0→1の新規SaaSで、事業側が作成したリーンキャンバスやユーザーストーリーマッピングを見直し、短期間でMVPを確定させる必要がありました。
- **Role:** 技術選定からアーキテクチャ設計、AWSインフラ構築、API実装、社内外調整、業務委託採用・進行管理までを担う技術責任者。
- **Actions:**
  - PdMと共にリーンキャンバス／ユーザーストーリーを再構築し、MVPスコープを再定義。
  - Node.js×React×Hono.js構成でマルチテナントSaaSアーキテクチャを設計し、TerraformでAWSインフラをコード化。
  - 管理画面の要件整理、API設計、SendGrid連携、業務委託エンジニアの採用・タスク管理を実施。
- **Result:**
  - ベータ版ローンチを完了し、社内モニタリングと顧客インタビューを回せる状態を構築。
  - クローラー領域は継続的に機能拡張を進行中。
- **Scale:** Node.js(TypeScript) / React / Next.js / Hono.js。
  AWS（ECS on Fargate, RDS, S3, CloudWatch Logs）/ Terraform / SendGrid / 各種AI Coding Tool。
- **Team:** PdM1名＋社内エンジニア1名＋業務委託2名（フロント担当1名、クローラー担当1名）。タスクはNotionで管理し、クローラー担当は現在も開発を継続中。

### フリーランス（業務委託、2022年5月〜10月）

#### EC検索改善／複業マッチングSaaS支援（計6カ月）

- **Challenge:** EC案件ではElasticSearch検索の性能低下とレガシーJavaScriptが課題だった。  
  複業SaaS案件では小規模体制のままGraphQL＋Next.jsの新機能を迅速に提供する必要があった。
- **Role:** フリーランスのフルスタックエンジニアとして単独（EC）とCTO＋自分（SaaS）で参画し、要件に沿って実装からレビューまで担当。
- **Actions:**
  - ElasticSearchのクエリ／インデックスを調査し、改善PoCと優先度付けを実施。
  - レガシーなフロントをTypeScript化し、Storybook＋Jestの検証基盤を整備。
  - Go＋gqlgen＋SQLBoilerでGraphQL APIのエンドポイント追加やスキーマ拡張を実装。
  - Next.js＋Apollo Clientでデータ取得／表示ロジックを改修し、依頼機能を短期リリース。
- **Result:**
  - EC検索のボトルネックを特定し、改善方針とモダナイゼーションの土台を提示。
  - 複業SaaSではCTO要望の機能を計画どおりリリースし、利用フロー改善に寄与。
- **Scale:**
  - Backend: Java 8 / Spring Boot / PHP(Lumen) / Go / MySQL
  - Frontend: React / Redux-Saga / TypeScript
  - UI/Testing: Storybook / Jest / Next.js / Apollo Client
  - GraphQL: gqlgen / SQLBoiler
- **Team:** ECは単独。SaaSはCTO＋自分。

### [株式会社ビットエー](https://bita.jp/)（2019年8月〜2022年5月）

SESとして顧客常駐し、サーバサイド・インフラ・フロントエンドを横断して開発と運用を担当していた。社外調整に加えて、社内の勉強会企画や採用面接、GitHubでのスカウトなど組織面の活動にも関わった。

#### 広告配信の最適化基盤・社内Webアプリ（美容系の広告代理店向け）

- **Challenge:** 既存MAツールにFacebook Conversion API連携を組み込み、Pixel欠損を補完するDMPを短期間で構築する必要があった。  
  イベントとカスタムオーディエンスを安定送信する仕組みを整えることも必須だった。  
  また社内WebアプリではCore Web Vitalsを計測し、SEO改善の起点を用意することが求められた。
- **Role:** Tech LeadとしてDMPと社内Webアプリ双方の要件定義・アーキテクチャ設計・実装を担当。社内アプリには新卒メンバーをアサインし、DMPは少数精鋭で推進した。
- **Actions:**
  - Facebook Conversion API向け計測サーバをGCP（Cloud Run, Pub/Sub, BigQuery, Cloud SQL）で構築。
  - MAツールのイベントを正規化し、Facebookへ安定送信してPixel欠損を補完。
  - カスタムオーディエンス生成と送信オペレーションを自動化し、広告運用チームの負担を軽減。
  - 社内Webアプリ（TypeScript＋Express＋Next.js）にCore Web Vitals計測機能と管理UIを実装。
  - 新卒3名に社内アプリ機能の実装を任せ、レビューとメンタリングで支援。
  - GitHub Actions／CircleCI／TerraformでIaCとCI/CDを整備し、Git-flow＋Planning Pokerでプロセスを共通化。
- **Result:**
  - MAツール経由でFacebookへ安定的にイベント／カスタムオーディエンスを送信できるようになり、既存顧客5社・新規10社へ展開。
  - Core Web Vitalsの定常計測データがSEOチームの改善サイクルに活用され、社内Webアプリの改善リードタイムが短縮。
- **Scale:**
  - Tech stack: TypeScript / Node.js / Express / Next.js / React / Jest / Playwright / Puppeteer
  - GCP: Cloud Run / Cloud Functions / Pub/Sub / Cloud SQL / BigQuery
  - GCP（続き）: Datastore / Compute Engine / Cloud Storage / Cloud Load Balancing
  - IaC: Terraform
- **Team:** DMPは正社員2名中心、社内Webアプリは新卒3名＋自分で構成。

#### AI/VRを活用した不動産仲介プラットフォーム

- **Challenge:** PoCフェーズのLaravel＋Vue.jsアプリで設計・品質課題が顕在化し、短期間でテスト基盤と設計指針を整える必要があった。
- **Role:** Backend/Frontend Engineerとして途中参画し、Laravel/Azure/Vue.jsを短期でキャッチアップして改善をリード。
- **Actions:**
  - Repository/Service/Infrastructureのレイヤーを設計し、Fat Controller化したコードを整理。
  - PHPUnit＋Jestで自動テストを導入し、Azure Pipelinesでリグレッション検知を実現。
  - Vuexベースの状態管理とAtomic Designを試行し、Figmaと連動したUIコンポーネント設計を共有。
- **Result:**
  - PoC期間中は障害ゼロを維持し、顧客の信頼を確保。
  - 設計・テストの共通言語を整備し、学びを後続案件へ展開。
- **Scale:**
  - Languages: PHP 7.4 / Laravel / Python 3.6 / Vue 2 / Vuex / A-Frame / Jest / Sass
  - Services: Maps/Geocoding/Places API / Figma / MySQL / SQL Server
  - Azure: VM / Functions / SQL Database / Storage / DevOps / Traffic Manager / CDN
  - CI: CircleCI
- **Team:** 弊社エンジニア2名＋PdM1名、先方2名の計5名。

### [株式会社スタッフサービス](https://www.staffservice-engineering.jp/)（エンジニアリング事業本部）（2018年7月〜2019年7月）

#### 衛星画像の分析支援Webアプリケーション

- **Challenge:** 衛星画像解析データを扱う社内Webアプリの表示が10秒以上かかっており、性能改善とテスト体制の強化が求められていた。
- **Role:** フルスタックエンジニアとして、Spring Boot＋Angular構成の実装と総合試験を担当。
- **Actions:** 処理分割とキャッシュ戦略を見直し、描画時間を10秒→2秒に短縮。社内総合試験ではテストケース外のシナリオも洗い出し、クリティカルなバグを報告。
- **Result:**
  - 画面表示を10秒→2秒へ短縮。
  - テスト観点の幅出しでクリティカルなバグを早期検知。
- **Scale:** 2018年10月〜2019年7月 / Java 8, Spring Boot, Angular 1.x。
#### 製薬開発支援Windowsアプリケーション

- **Challenge:** 製薬開発業務の管理ツールをC#で刷新するにあたり、要件を満たすテストケースマトリックスを用意する必要があった。
- **Role:** Windowsアプリエンジニアとして、実装とテスト計画を担当。
- **Actions:** 画面設計とドメインロジックを整理し、事前にテストケースマトリックスを提出してレビューを通過。品質確保のための手順化を学習。
- **Result:**
  - C#アプリをリリースし、業務フローをデジタル化。
  - テストケースマトリックス設計のスキルを習得。
- **Scale:** 2018年7月〜2019年9月 / C# / Windowsアプリ。
### [FIT株式会社](https://www.fit4u.co.jp/)（2018年4月〜6月）

- **Challenge:** エンジニア1年目として4月中リリースが決まった太陽光発電モニタリングWebアプリを自分主体で仕上げる必要があった。  
  先輩はレビューとフォローに専念する体制だった。
- **Role:** ジュニアエンジニアとして、C#/.NET MVC＋Angularでの機能実装とデータモデル設計を担当。
- **Actions:** PostgreSQLやAngularを業務で初キャッチアップし、自分が実装をリードしつつ先輩に随時レビューを受けた。  
  チャートやCO2削減量の表示機能を開発し、リリース後もチャート拡張などのエンハンスを継続。
- **Result:**
  - 期日どおりに初リリースを完了。
  - エンハンスを継続できる体制と知識移転を実現。
- **Scale:**
  - C# / .NET MVC / Angular 1.x
  - PostgreSQL / IIS
- **Team:** 3名規模（先輩2名＋自身）で進行。

## できること・得意なこと

- **0→1のB2B SaaS推進と広告プロダクト改善**  
  Speeeでの広告調査SaaS立ち上げや広告配信基盤リプレイス、ビットエーでのFacebook Conversion API連携など、事業KPIに直結する開発を技術責任者としてリード。要件整理→アーキ設計→実装→運用までワンストップで担っている。

- **サーバサイド／データ基盤／クラウドのフルスタック実装**  
  Go・TypeScript・Pythonを中心にAPIやバッチを開発し、GCP（Cloud Run, Pub/Sub, BigQuery, Cloud SQLなど）やAWS（ECS on Fargate, Lambda, Aurora等）でインフラを構築。TerraformとGitHub Actions / CircleCIでIaCとCI/CDを整備し、本番運用まで引き上げている。

- **広告計測・データパイプラインの構築と可観測性の強化**  
  Facebook Conversion APIを既存MAに組み込み、イベントとカスタムオーディエンスを安定送信。Core Web Vitals計測やBigQuery/Athenaでの集計を通じて、データ活用と品質計測を両立させている。

- **TypeScriptフロントエンドのモダナイゼーションと検証基盤**  
  Next.js/React＋Storybook＋Jest/Playwright構成でUIを再設計し、レガシーJSのTypeScript化やデザインシステム整備を推進。GraphQL（gqlgen, Apollo Client）でのフロント／API連携やE2Eテスト自動化も得意である。

- **少人数チームの設計・育成と開発プロセス整備**  
  新卒メンバーや業務委託を巻き込み、Planning PokerやGit-flowを取り入れたスクラム/カンバン運用を設計。RenovateやAI Coding Toolの導入も推進し、個人PM的に複数プロジェクトを並走しながらNotion/Jiraでタスクとレビュー文化を整えている。

- **行動特性**  
  自律性の高い環境で変化を歓迎し、実験的な取り組みから学びを得て事業貢献につなげるスタイル。16personalitiesではISTJ→ISTP→INTPと遷移し、DiSCはCSタイプ2。論理的に課題を分解しつつ、泥臭い実装や運用にも向き合う。
