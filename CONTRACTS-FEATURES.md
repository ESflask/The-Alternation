# VibeConnect 機能拡張 契約 (Features v1.1)

③④機能の並列実装のための追加契約。既存 `CONTRACTS.md` は変更しない。
**統合（`ConsoleChatView.swift` / `TaskViewModel.swift` / `Networking/APIClient.swift` / `src/index.ts`）はオーケストレータ（親）が行う。各エージェントは自分の「Owns」ファイルのみ作成/書き換えし、これら統合対象ファイルには触れないこと。**

環境: iOSデプロイターゲット 17.0（ただし実機は iOS 27）。`.glassEffect()` 等 Liquid Glass は iOS 26+。`if #available(iOS 26.0, *)` でガードし、未満は `.ultraThinMaterial` 等でフォールバックすること。

---

## A. ファイルAPI（バックエンド：`src/routes/files.ts`、`/api/files` にmount）
`process.env.TARGET_WORKSPACE_PATH`（未設定は `process.cwd()`）をルートとする。**パストラバーサル対策必須**：`path` を正規化し、解決後の絶対パスがルート配下でなければ `400 {"error":"invalid path"}`。`.git` 配下は除外。

- `GET /api/files/tree?path=<rel>`（`path`省略でルート）
  - 200: `{ "path": "<rel>", "entries": [ { "name": string, "path": string, "type": "file"|"dir", "size": number|null } ] }`
  - `path` はルート相対（ルートは `""`）。ディレクトリ優先→名前昇順。
- `GET /api/files/read?path=<rel>`
  - 200: `{ "path": string, "content": string, "truncated": boolean }`
  - テキストのみ。2MB超やバイナリ判定時は `content` を空 or 先頭のみにして `truncated: true`。
- `PUT /api/files/write` body `{ "path": string, "content": string }`
  - 200: `{ "success": true, "message": "saved" }` / 失敗 `400|500 { "success": false, "message": string }`
- 実装は `fs/promises` を使用。ルーターは `express.Router()` を **default export**（親が `app.use('/api/files', filesRouter)` する）。

---

## B. Swift ファイルモデル（新規 `Models/FileModels.swift`）
```swift
import Foundation
enum FileNodeType: String, Codable { case file, dir }
struct FileEntry: Codable, Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let type: FileNodeType
    let size: Int?
}
struct FileTreeResponse: Codable { let path: String; let entries: [FileEntry] }
struct FileReadResponse: Codable { let path: String; let content: String; let truncated: Bool }
struct FileWriteResponse: Codable { let success: Bool; let message: String }
```

## C. APIClient ファイル拡張（新規 `Networking/FileAPI.swift`）
`APIClient` は `struct APIClient { var baseURL: URL }`（既存）。**その private ヘルパは使えない**ので、`baseURL` から自前で `URLRequest` を組み `URLSession` で通信する extension を新規ファイルに書く：
```swift
extension APIClient {
    func fileTree(path: String?) async throws -> FileTreeResponse   // GET /api/files/tree
    func readFile(path: String) async throws -> FileReadResponse    // GET /api/files/read
    func writeFile(path: String, content: String) async throws -> FileWriteResponse // PUT /api/files/write
}
```
エラーは投げる（既存 `APIError` があれば流用、無ければ自前 enum 可）。クエリは `URLComponents` で安全にエンコード。

## D. ファイル画面（新規 `Views/FileBrowserView.swift`, `Views/FileEditorView.swift`）
- `FileBrowserView`: `APIClient.fileTree` でツリー表示。ディレクトリはタップで展開/潜行、ファイルタップで `FileEditorView` へ遷移。`serverHost` から `APIClient` を組む初期化を受ける（`init(host: String)` か、`APIClient` を引数で受ける）。**`TaskViewModel` には依存しない**（`serverHost: String` を引数で受け取る形）。
- `FileEditorView(path:host:)`: `readFile` で内容取得 →（等幅の編集可能 `TextEditor`）→ 「保存」で `writeFile`。読み取り専用トグル、変更検知、保存結果トースト。Theme（既存 `Theme.swift`）の配色・等幅フォントを使用。
- 親が `ConsoleChatView` から `FileBrowserView(host: viewModel.serverHost)` を push する。だからこの2画面は `serverHost: String` だけ受け取れば動く自己完結にすること。

## E. Liquid Glass 入力欄＋スワイプ（`Views/Components/MessageInputBar.swift` を**専有・書き換え**）
既存シグネチャは維持（親 `ConsoleChatView` が下記で呼ぶ）：
```swift
MessageInputBar(text: $inputText, isProcessing: viewModel.isProcessing, onSend: send)
```
= `struct MessageInputBar { @Binding var text: String; let isProcessing: Bool; let onSend: () -> Void }` を保ちつつ内部を刷新：
- 入力欄背景を **Liquid Glass**（`if #available(iOS 26.0,*) { .glassEffect(in: Capsule()) } else { .ultraThinMaterial }`）。送信ボタンもglass調に。
- **上下スワイプでキーボード表示/非表示**：内部 `@FocusState` を持ち、入力欄への下スワイプ(`DragGesture`)で `isFocused=false`（閉じる）、上スワイプで `isFocused=true`（開く）。処理中は送信不可（既存挙動維持）。
- 既存の外部シグネチャ（引数名・型）を変えないこと。変えると親のビルドが壊れる。

## F. 複数セッション/新規チャット（新規 `Models/ChatSession.swift`, `Stores/SessionStore.swift`, `Views/SessionListView.swift`）
- `ChatSession`: `struct ChatSession: Identifiable, Equatable { let id: UUID; var title: String; var createdAt: Date; var messages: [ChatMessage] }`（`ChatMessage` は既存 `Models.swift`。Codable でないため**永続化は必須にしない**。アプリ実行中のメモリ保持でよい。任意で UserDefaults に「タイトル+id+createdAt」だけ保存可）。
- `SessionStore: ObservableObject`: `@Published var sessions: [ChatSession]`, `@Published var activeID: UUID?`。メソッド `newSession()`（新規作成しactive化）, `select(_ id:)`, `rename(_ id:, title:)`, `delete(_ id:)`。空なら初期セッションを1つ用意。
- `SessionListView`: セッション一覧（タイトル・作成時刻）＋「＋ 新規チャット」ボタン。タップで `select`。Liquid Glass 調のシート/ドロワー（iOS26+）。`@ObservedObject var store: SessionStore` を受ける。
- **`TaskViewModel` は触らない**。親が `SessionStore` と `TaskViewModel` を結線する（アクティブセッションのmessagesとViewModelの同期は親が担当）。

---

## 共通ルール
1. 上記の型/JSON形状/シグネチャを変えない。Owns 以外のファイルを作らない・触らない。
2. 統合対象（`ConsoleChatView.swift` / `TaskViewModel.swift` / `Networking/APIClient.swift` / `src/index.ts` / `Models.swift`）は**親が編集**。エージェントは読み取り参照のみ可。
3. 絶対パスで操作。単体でコンパイルが通らなくても、結合時に通る前提で契約に厳密に従う。
4. Theme（既存 `Theme.swift`）の配色・フォントを流用し、既存デザインと調和させる。
