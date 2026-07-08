# VibeConnect 機能拡張 契約 (Features v1.2)

UI刷新バッチの並列実装契約。既存 `CONTRACTS.md` / `CONTRACTS-FEATURES.md` は変更しない。
**統合（`ConsoleChatView.swift` / `TaskViewModel.swift` / `Networking/APIClient.swift` / 入力欄 `MessageInputBar.swift`）はオーケストレータ（親）が担当。各エージェントは自分の Owns ファイルのみ触る。**

環境: iOS 26+ で Liquid Glass（`.glassEffect`）。ターゲット17なので `if #available(iOS 26.0, *)` でガードしフォールバック必須。既存 `Theme.swift` の配色/等幅を流用。

---

## モデル/effort の正準定義（バックエンド・UI共通の語彙）
- モデルID（`claude --model <id>` のエイリアス）: `opus`(表示 "Opus 4.8") / `sonnet`("Sonnet 5") / `haiku`("Haiku 4.5") / `fable`("Fable 5")
- effort（`claude --effort <level>`）: `low` / `medium` / `high` / `xhigh` / `max`

---

## A. バックエンド：model/effort 対応（`src/queue.ts` と `src/routes/tasks.ts` を編集）
**後方互換必須**（model/effort 未指定なら現状動作のまま）。
- `POST /api/tasks` のリクエストボディを拡張:
  ```json
  { "instruction": "…", "model": "opus"|"sonnet"|"haiku"|"fable"|null, "effort": "low"|"medium"|"high"|"xhigh"|"max"|null }
  ```
  `instruction` 必須（現状通り）。`model`/`effort` は任意。未知値は無視（バリデーションして不正なら単に付けない）。
- `createTask` を `createTask(instruction: string, opts?: { model?: string; effort?: string }): Task` に拡張（第2引数は任意、既存呼び出しと互換）。
- claude 起動引数の組み立て順: `[...CLAUDE_ARGS(既定 -p 等), (model ? ['--model', model] : []), (effort ? ['--effort', effort] : []), instruction]`。`shell:false` 配列渡しを維持（インジェクション回避）。
- レスポンス形状（202）は不変。`Task` 型に `model?/effort?` を足すのは可（任意）。
- 完了後 `npx tsc --noEmit` で自ファイルの型健全性を確認。

## B. Markdown描画：返答は素テキスト、コードのみ枠（`Views/Components/ChatBubble.swift` を書き換え + `Views/Components/MessageContentView.swift` 新規）
- **user 吹き出しは現状維持**（右・アクセント）。
- **assistant** は現在「全文をターミナル枠」に入れているのをやめ、`message.text` を**セグメント分割**して描画:
  - フェンス code block ` ``` … ``` `（言語指定 optional）→ **ターミナル枠**（等幅・`Theme.sunkenSurface`・横スクロール・ヘッダ"⌘言語"＋コピー）。既存の枠デザインを流用。
  - それ以外の地の文（prose）→ **枠なしの通常テキスト**（`Theme.primaryText`、通常フォント、選択可）。可能なら見出し/箇条書き/インライン`code`を軽く整形（`AttributedString(markdown:)` 使用可。失敗時はプレーン表示にフォールバック）。
- パーサは `MessageContentView.swift` に `enum MessageSegment { case text(String); case code(String, lang: String?) }` と分割関数＋描画Viewを実装。ChatBubble はこれを呼ぶ。アバター(sparkle)は残す。
- `#Preview` を用意（MockData利用可）。**TaskViewModel非依存。**

## C. 左ドロワー＋検索（`Views/ChatDrawerView.swift` 新規）
- 画像#12 風の左サイドバー。`@ObservedObject var store: SessionStore` を受け、`var onClose: () -> Void` と `var onSelect: (UUID) -> Void` を受ける（親がスワイプ開閉・オーバーレイ配置を担当するので、**このViewは中身だけ**）。
- 上部にタイトル（例 "VibeConnect"）、**検索欄**（`@State searchText`）でセッションを `displayTitle` 部分一致フィルタ。
- 一覧: `store.sessions`（フィルタ後）を新しい順で。行タップ→ `onSelect(id)`。アクティブ行を強調。スワイプ削除で `store.delete`。
- 下部/上部に「＋ New chat」（`store.newSession()` → `onSelect(newID)`）。
- 背景は `Theme` の暗色。iOS26+で軽くglass可（フォールバック必須）。幅は画面の約80%想定（親が制御するので `.frame(maxWidth:.infinity)` で内容だけ組み、幅は親指定に従う）。
- `#Preview` は `SessionStore.preview` 使用。**TaskViewModel非依存。**

---

## 共通ルール
1. 型/JSON形状/シグネチャを変えない。Owns 以外を触らない。統合対象（`ConsoleChatView`/`TaskViewModel`/`APIClient`/`MessageInputBar`）は**親が編集**。
2. 絶対パスで操作。単体コンパイル不可でも結合時に通る前提で契約厳守。
3. 既存 `Theme` を流用し既存デザインと調和。ダーク/ライト両対応。
