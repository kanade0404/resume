# [株式会社ビットエー](https://bita.jp/)（2019年8月〜）

## データ基盤統合システム開発

### 案件クライアント

大手通信会社

### 期間

2021年1月〜

### 技術スタック

- Backend
  - [Python3.9](https://www.python.org/)
  - [独自フレームワーク（tornadoベース）](https://axis-edge.github.io/qmonus-sdk-programming-guide/)
- Others
  - [Git](https://git-scm.com/)
  - [GitHub](https://github.co.jp/)
  - [Windows](https://www.microsoft.com/ja-jp/windows) + [WSL2(Ubuntu20.04)](https://docs.microsoft.com/ja-jp/windows/wsl/)

## 新卒就活サービス新規開発

### 案件クライアント

大手新卒就活サービス運営会社

### 期間

2021年1月〜

### 技術スタック

- Backend
  - [Java11 or higher](https://www.java.com/)
  - [Spring Boot](https://spring.io/projects/spring-boot)

## オンボーディングシステム開発（社内開発）

### 期間

2021年1月〜

## タレントマネジメントシステム開発（社内開発）

### 期間

2021年10月〜

### 技術スタック

- Backend
  - [Hasura](https://hasura.io/)
- Frontend
  - [TypeScript](https://www.typescriptlang.org/)
  - [Next.js](https://nextjs.org/)
  - [React](https://reactjs.org/)
- Infrastructure
  - [AWS](https://aws.amazon.com/)（インフラ検討中）
- DevOps
  - [Terraform](https://www.terraform.io/)

## 擬似Confluence開発（社内開発）

### 期間

2021年5月〜

### 技術スタック

- Backend
  - [Go](https://go.dev/)
  - [gin](https://github.com/gin-gonic/gin)
  - [gqlgen](https://github.com/99designs/gqlgen)

- Frontend
  - [Next.js](https://nextjs.org/)
  - [NestJS](https://nestjs.com/)
  - [TypeScript](https://www.typescriptlang.org/)

- Infrastructure
  - [PostgreSQL](https://www.postgresql.org/)
- DevOps
  - [Docker](https://www.docker.com/)
  - [Docker Compose](https://docs.docker.com/compose/)
  - [Terraform](https://www.terraform.io/)
  - [Terraform Cloud](https://cloud.hashicorp.com/products/terraform)

## 広告配信の最適化の基盤システムの開発・運用

### 案件クライアント

美容系専門の広告代理店

### 期間

2021年1月~2021年12月

### 開発人数

2〜5人（途中で増加）

### 技術スタック

- Backend
  - [TypeScript](https://www.typescriptlang.org/)
  - [Node.js](https://nodejs.org)
  - [Express](https://expressjs.com/)
  - [Jest](https://jestjs.io/ja/)
  - [Puppeteer](https://github.com/puppeteer/puppeteer)
- Frontend
  - [TypeScript](https://www.typescriptlang.org/)
  - [Next.js](https://nextjs.org/)
  - [React](https://reactjs.org/)
  - [Jest](https://jestjs.io/ja/)
  - [Ant Design](https://ant.design/)
  - [styled-components](https://styled-components.com/)
  - [Adobe XD](https://www.adobe.com/jp/products/xd.html)
- Infrastructure
  - [Google Cloud Platform](https://console.cloud.google.com/)
    - [IAM](https://cloud.google.com/iam)
    - [Cloud Run](https://cloud.google.com/run)
    - [App Engine](https://cloud.google.com/appengine)
    - [BigQuery](https://cloud.google.com/bigquery)
    - [Cloud SQL](https://cloud.google.com/sql)
    - [Cloud Pub/Sub](https://cloud.google.com/pubsub)
    - [Cloud Tasks](https://cloud.google.com/tasks)
    - [Dataflow](https://cloud.google.com/dataflow)
    - [DataStore](https://cloud.google.com/datastore)
    - [Cloud Storage](https://cloud.google.com/storage)
    - [Container Registry](https://cloud.google.com/container-registry)
    - [Cloud DNS](https://cloud.google.com/dns)
    - [Cloud Build](https://cloud.google.com/build)
  - [MySQL](https://www.mysql.com/)
- DevOps
  - [Docker](https://www.docker.com/)
  - [Terraform](https://www.terraform.io/)
  - [GitHub Actions](https://github.co.jp/features/actions)
- Others
  - [Git](https://git-scm.com/)
  - [GitHub](https://github.co.jp/)
  - [Slack](https://slack.com/)
  - [Jira](https://www.atlassian.com/ja/software/jira)
  - [Confluence](https://www.atlassian.com/ja/software/confluence)
  - [MacOS](https://www.apple.com/jp/macos)

### 開発内容

開発全体としてはスクラム開発の手法を一部採用してGit-flowで開発をしました。
1週間を1スプリントとして、スプリントの最初にSprint Planningをしてスプリント最後にRetrospectiveをしてKPTについて話し合いました。
新たに発生したタスクに対してはstory pointをplanning pokerで見積もりをしました。

当初は自分と弊社の別メンバーのみで開発をしましたが、メンターをしていた常駐先クライアントの新卒3名を開発に加えて最終的には5名で開発をしました。

主に2つの開発をしました。

1つは常駐先クライアント社内で広告運用に使用している社内Webアプリケーションの機械学習を使った予算配分の最適化機能の開発です。

もう1つは自社クライアント向けの効果測定と広告配信の最適化の基盤システム開発です。

社内Webアプリケーションは自分がアサインされる以前に弊社の別メンバーが開発していたアプリケーションにエンハンスで新規のページから作成をしました。

構成はBackendがTypeScript+Expressで、FrontendがTypeScript+Next.jsでCloud Runにデプロイしています。

初めて実務でTypeScriptやExpress、Next.jsやGCPを使いましたが、アプリケーションの仕様を含めてキャッチアップを行い、スケジュール通りに新機能をリリースできました。

基盤システム開発は自社顧客向けにFacebook Conversion APIを利用した広告配信の最適化と効果測定を目的としています。要件定義から開発運用を行いました。

立ち上げ時は自分含め2名で開発をしました。プロパーではなかったですが、システム要件の策定からクラウドアーキテクチャの設計、開発と運用まで含めて全て任せていただきました。

現在ではリリース済みで、多くの顧客企業様に導入していただいております。

この開発では、多くのGCPサービスを使い倒す機会を得ることができたこと、実務未経験でしたがIaCにTerraformを自分から導入し、インフラを安全に管理できるようにしました。

この2つの開発以外の業務では、広告運用チームとそのチームの担当顧客とのFacebook Conversion APIの導入相談を受けたり、常駐先クライアントの新卒のメンターを行いました。

開発面ではIaCの旗振り役をやったりテストコードの推奨、アプリケーションやTerraformのCI/CD自動化を導入しておりました。

## AI/VRを活用した不動産仲介プラットフォーム開発

### 案件クライアント

某外資系コンサルティングファーム

### 期間

2019年10月〜11月
2020年4月〜12月

### 技術スタック

- Backend
  - [PHP7.4](https://www.php.net/)
  - [Python3.6](https://www.python.org/)
  - [Laravel](https://laravel.com/)
  - [PHPUnit](https://phpunit.de/)
  - [SendGrid](https://sendgrid.kke.co.jp/)
  - [Splunk](https://www.splunk.com/ja_jp)
- Frontend
  - [JavaScript](https://developer.mozilla.org/en-US/docs/Web/JavaScript)
  - [A-Frame](https://aframe.io/)
  - [Vue2](https://jp.vuejs.org/index.html)
  - [Vuex](https://vuex.vuejs.org/ja/)
  - [Jest](https://jestjs.io/ja/)
  - [Sass](https://sass-lang.com/)
  - [Maps JavaScript API](https://developers.google.com/maps/documentation/javascript?hl=ja)
  - [Geocoding API](https://developers.google.com/maps/documentation/geocoding?hl=ja)
  - [Places API for Web](https://developers.google.com/maps/documentation?hl=ja)
  - [Figma](https://www.figma.com/)
- Infrastructure
  - [MySQL](https://www.mysql.com/)
  - [SQL Server](https://www.microsoft.com/ja-jp/sql-server/)
  - [Azure](https://azure.microsoft.com/ja-jp/)
    - [Virtual Machine](https://azure.microsoft.com/ja-jp/services/virtual-machines/)
    - [Azure Functions](https://azure.microsoft.com/ja-jp/services/functions/)
    - [Azure SQL Database](https://azure.microsoft.com/ja-jp/products/azure-sql/database/)
    - [Azure Storage](https://azure.microsoft.com/ja-jp/product-categories/storage/)
    - [Azure DevOps](https://azure.microsoft.com/ja-jp/services/devops/)
    - [Traffic Manager](https://docs.microsoft.com/ja-jp/azure/traffic-manager/traffic-manager-overview)
    - [Azure CDN](https://azure.microsoft.com/ja-jp/services/cdn/)
- DevOps
  - [Docker](https://www.docker.com/)
  - [Docker Compose](https://docs.docker.com/compose/)
  - [Circle CI](https://circleci.com/ja/)
- Others
  - [Git](https://git-scm.com/)
  - [GitHub](https://github.co.jp/)
  - [AirTable](https://www.airtable.com/)
  - [Trello](https://trello.com/ja)
  - [Kibela](https://kibe.la/)
  - [Slack](https://slack.com/)
  - [MacOS](https://www.apple.com/jp/macos)

### 開発内容

途中参画にはなりますが、入社して初めての案件でした。

Laravelを使ったバックエンド開発とVue.jsを使ったフロントエンド開発、詳細設計とテストを行いました。

LaravelとAzureは初めてだったためキャッチアップを行い、既存メンバーよりも詳しくなりました。

- テストコードの導入
- Clean Architecture likeな設計導入
- Bus EventをVuexに置き換え
- Atomic Designの導入

# [株式会社スタッフサービス](https://www.staffservice-engineering.jp/)（エンジニアリング事業本部）（2018年7月〜2019年7月）

## 衛生画像の分析支援Webアプリケーション開発

### 案件クライアント

大手日系メーカー子会社

### 期間

2018年10月〜2019年7月

### 技術スタック

- Backend
  - Java 8
  - Spring Boot
- Frontend
  - JavaScript
  - Angular 1.x
- Others
  - Git
  - BitBucket

### 開発内容

Spring Bootでのバックエンド開発とAngularでのフロントエンド開発、開発後のテストで社内のみの総合試験を行いました。

開発では元々画面の描画完了まで10秒かかっていた処理を2秒まで短縮したこと、総合試験で不要ログ削除ツールのバグを発見するなどをしました。

## 製薬開発支援Windowsアプリケーション開発

### 案件クライアント

中小SIer

### 期間

2018年7月〜2019年9月

### 技術スタック

- Application
  - C#
- Others
  - SVN
  - Visual Studio
  - Windows

### 開発内容

C#でのWindowsアプリケーションの開発をしました。

# [FIT株式会社](https://www.fit4u.co.jp/)

## 太陽光発電パネルの統計情報管理Webアプリケーション

### 期間

2018年4月〜6月

### 技術スタック

- Backend
  - C#
  - .NET MVC
- Frontend
  - Angular 1.x
- Infrastructure
  - PostgreSQL
  - IIS
- Others
  - SVN

### 開発内容

太陽光パネルを設置している顧客向けに発電量やCO2削減量などを確認できるWebアプリケーションを開発しました。

エンジニアとして初めての業務で、最初のリリースは4月中と決められていたため頑張って開発をして期日に間に合わせました。

PostgreSQL以外は初めてでしたが、業務中にキャッチアップを行って先輩に質問しながら開発を進めました。

リリース後はエンハンスでチャート画面の拡張などを行いました。
