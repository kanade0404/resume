# Philosophy of Software Design (Ousterhout)

複雑度を「漸進的に増えるもの」と捉え、毎コミットで戦術的に減らす規律。

## 中核命題

- **Complexity is incremental.** 1 件の変更がもたらす複雑度は小さく見えるが、複雑度は積み重なる。"It's just one more parameter" を許すと数年で破綻する。
- **Complexity の症状は 3 つ**: change amplification（1 機能変更が多箇所に波及）／ cognitive load（読むのに必要な事前知識が多い）／ unknown unknowns（直すべき場所が分からない）。
- **Strategic vs Tactical Programming.** 動かすことだけを優先するのが Tactical。長期コストを下げるために設計に時間を使うのが Strategic。プロは Strategic を選ぶ。

## モジュール設計の原則

- **Deep Module.** 小さい API、厚い実装。利用者から見える概念量を最小化する。
- 反対は **Shallow Module**: getter/setter ばかりのクラス、薄い wrapper、`utils` 系のかき集め。Shallow は abstraction の名を借りた cost の上乗せ。
- **インタフェースは "提供される機能" を最小限のシグネチャで表す。** 多すぎるパラメータ、パラメータの順序依存、暗黙のグローバル状態は cost。
- **General-purpose modules are deeper.** 「今まさに使う形」だけに特化したインタフェースは早晩破綻する。

## 情報隠蔽

- **Information Hiding.** 実装の決定をモジュール内に閉じる。利用側がそれを知らずに使えるなら良いインタフェース。
- **Information Leakage が最大の敵。** 同じ知識が複数モジュールに広がる（フォーマット、エンコーディング規約、状態遷移表）。
- **Different Layer, Different Abstraction.** 各層は独自の概念を持つ。下層概念をそのまま上層に持ち上げない（例: HTTP ステータスをドメインの戻り値にしない）。

## エラーハンドリング

- **Define errors out of existence.** 例外を増やす前に「そもそも例外が起きない API」を設計できないか問う（例: `delete(x)` を冪等にすれば "not found" は不要）。
- **Exceptions sit at the boundary.** 内部関数では Result/Either で型に載せ、境界で必要なら例外に変換。

## 名前と一般原則

- **Names should be precise and consistent.** "process", "manage", "handle" は意味のない名前。
- **Comments augment the code.** コードが言わない情報（不変条件、why、設計意図）をコメントで補う。コードを読めば分かることはコメントしない。
- **Modify existing code while you work.** 通り過ぎる時に少し綺麗にする（boy-scout rule に近い）。

## このプロジェクトでの適用ルール

- **新規モジュールは Deep Module 化を意図的にやる。** 「インタフェースが小さく、実装が説明 1 段落」をレビュー観点に固定。
- **Shallow Module（utility 集積、薄い委譲、getter/setter のみ）は集約を疑う。** ドメイン的に意味のある名前を持てなければ削る。
- **「process」「handle」「manage」「util」を含む名前を見たら、より具体的な名前を提案する。**
