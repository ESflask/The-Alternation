# VibeConnect — 共有インターフェース契約 (Interface Contract v1.0.0)

> このファイルは **5体のエージェントが並行実装するための唯一の真実 (single source of truth)** である。
> すべてのエージェントはここに定義された型・JSON形状・関数シグネチャに厳密に従うこと。
> ここに書かれた形状を勝手に変更してはならない。追加は可だが、既存フィールド名/型は固定。

---

## 1. プロジェクト・ディレクトリ構成

```
The Alternation/
├── CONTRACTS.md                 # 本ファイル
├── IMPLEMENTATION_PLAN.md
├── vibe-connect-server/         # バックエンド (Agent 1,2,3)
│   ├── package.json             # Agent 1
│   ├── tsconfig.json            # Agent 1
│   ├── .env.example             # Agent 1
│   ├── .gitignore               # Agent 1
│   ├── README.md                # Agent 1
│   └── src/
│       ├── index.ts             # Agent 1  (Express + /health + ルーターmount)
│       ├── types.ts             # Agent 1  (共有型)
│       ├── queue.ts             # Agent 2  (タスクキュー)
│       ├── routes/
│       │   ├── tasks.ts         # Agent 2  (POST/GET /api/tasks)
│       │   └── git.ts           # Agent 3  (GET diff / POST commit)
│       └── mock/
│           └── mock-claude.sh   # Agent 3  (ローカルテスト用のclaudeスタブ)
│   └── scripts/
│       └── api-test.sh          # Agent 3  (curlによるAPI疎通テスト)
└── VibeConnectApp/              # iOSアプリ (Agent 4,5)
    ├── VibeConnectApp.xcodeproj # Agent 4
    └── VibeConnectApp/
        ├── VibeConnectApp.swift # Agent 4  (@main App entry)
        ├── Models.swift         # Agent 4  (共有データモデル)
        ├── Theme.swift          # Agent 4  (配色/デザイン定数)
        ├── MockData.swift       # Agent 4  (プレビュー用ダミー)
        ├── Views/
        │   ├── ConsoleChatView.swift    # Agent 4
        │   ├── DiffInspectorView.swift  # Agent 4
        │   └── Components/...           # Agent 4
        ├── Networking/
        │   └── APIClient.swift  # Agent 5
        └── ViewModels/
            └── TaskViewModel.swift # Agent 5
```

---

## 2. REST API 契約 (バックエンド ⇄ iOS 共通)

ベースURL: `http://<TAILSCALE_IP>:3000`

### GET /health
- 200 OK
```json
{ "status": "ok", "uptime": 123.45 }
```

### POST /api/tasks
- Request body:
```json
{ "instruction": "src/Views/MainView.swift のボタンの色を青に変更してテスト実行" }
```
- 202 Accepted:
```json
{
  "task_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "status": "processing",
  "message": "Task successfully dispatched to Claude Code."
}
```
- 400 Bad Request（instruction欠落時）:
```json
{ "error": "instruction is required" }
```

### GET /api/tasks/:id
- 200 OK:
```json
{
  "task_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "status": "processing",
  "logs": "ANSI除去済みの標準出力ログ...",
  "error": null
}
```
- `status` は必ず `"processing" | "completed" | "failed"` のいずれか。
- 404 Not Found（未知のid）:
```json
{ "error": "task not found" }
```

### GET /api/git/diff
- 200 OK:
```json
{
  "has_changes": true,
  "diff": "--- a/src/Views/MainView.swift\n+++ b/src/Views/MainView.swift\n@@ ..."
}
```
- 変更なしのときは `has_changes: false`, `diff: ""`。

### POST /api/git/commit
- Request body:
```json
{ "message": "style: update button color to blue" }
```
- 200 OK:
```json
{ "success": true, "message": "Changes committed successfully." }
```
- 400（messageが空）:
```json
{ "success": false, "message": "commit message is required" }
```

---

## 3. バックエンド TypeScript 型契約 (`src/types.ts` — Agent 1 が定義)

```ts
export type TaskStatus = 'processing' | 'completed' | 'failed';

export interface Task {
  task_id: string;
  status: TaskStatus;
  instruction: string;
  logs: string;
  error: string | null;
  exit_code: number | null;
  created_at: string;   // ISO8601
  updated_at: string;   // ISO8601
}
```

### `src/queue.ts` (Agent 2) が公開すべき関数シグネチャ
```ts
import { Task } from './types';

/** タスクを生成しClaude CLIを非同期起動。生成直後のTaskを返す。 */
export function createTask(instruction: string): Task;

/** id からタスクを取得。無ければ undefined。 */
export function getTask(id: string): Task | undefined;

/** （任意）全タスク一覧 */
export function listTasks(): Task[];
```

### ルーター contract（Agent 1 の index.ts が下記の通り mount する）
```ts
// routes/tasks.ts (Agent 2) と routes/git.ts (Agent 3) は
// それぞれ Express Router を default export すること。
import tasksRouter from './routes/tasks';
import gitRouter from './routes/git';
app.use('/api/tasks', tasksRouter);   // → POST '/' , GET '/:id'
app.use('/api/git', gitRouter);       // → GET '/diff' , POST '/commit'
```
- つまり `routes/tasks.ts` 内のパスは `'/'`（POST）と `'/:id'`（GET）。
- `routes/git.ts` 内のパスは `'/diff'`（GET）と `'/commit'`（POST）。

### 環境変数
- `PORT`（デフォルト 3000）
- `TARGET_WORKSPACE_PATH`（Claude CLI と git を実行する対象リポジトリの絶対パス）
- `CLAUDE_BIN`（デフォルト `claude`。テスト時に mock-claude.sh へ差し替え可能にする）

---

## 4. iOS Swift モデル契約 (`Models.swift` — Agent 4 が定義 / Agent 5 も同一定義に依存)

```swift
import Foundation

enum TaskStatus: String, Codable, Equatable {
    case processing, completed, failed
}

/// POST /api/tasks のレスポンス
struct CreateTaskResponse: Codable, Equatable {
    let task_id: String
    let status: String
    let message: String
}

/// GET /api/tasks/:id のレスポンス
struct TaskStatusResponse: Codable, Equatable {
    let task_id: String
    let status: TaskStatus
    let logs: String
    let error: String?
}

/// GET /api/git/diff
struct DiffResponse: Codable, Equatable {
    let has_changes: Bool
    let diff: String
}

/// POST /api/git/commit
struct CommitResponse: Codable, Equatable {
    let success: Bool
    let message: String
}

/// チャットタイムラインの1メッセージ
struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id: UUID
    let role: Role
    var text: String
    let timestamp: Date
}

/// Diff表示の1行
struct DiffLine: Identifiable, Equatable {
    enum Kind { case added, removed, context, header }
    let id: UUID
    let kind: Kind
    let text: String
}
```

---

## 5. iOS ViewModel 契約 (`TaskViewModel.swift` — Agent 5 が実装 / Agent 4 の View が参照)

Agent 4 の View はこの public インターフェースにのみ依存すること。
Agent 5 はこの public インターフェースを厳守して実装すること。

```swift
@MainActor
final class TaskViewModel: ObservableObject {
    // 接続・状態
    @Published var serverHost: String            // 例: "100.101.102.103"
    @Published var isConnected: Bool             // ヘッダのGreen/Red
    @Published var isProcessing: Bool            // スピナー表示
    @Published var currentStatus: TaskStatus?    // 現在タスクの状態

    // データ
    @Published var messages: [ChatMessage]       // チャットタイムライン
    @Published var diffLines: [DiffLine]         // パース済みdiff
    @Published var hasChanges: Bool              // diff有無 → Commitボタン活性
    @Published var errorMessage: String?         // 汎用エラー表示

    // アクション
    func send(instruction: String)               // 指示送信→ポーリング開始
    func checkConnection() async                 // /health で疎通確認
    func loadDiff() async                         // GET /api/git/diff → diffLines更新
    func commit(message: String) async            // POST /api/git/commit
    func resumeIfNeeded()                         // 起動/復帰時に未完了task再開

    // プレビュー用（Agent 4 の #Preview が使用）
    static var preview: TaskViewModel { get }
}
```

- `serverHost` の初期値は `UserDefaults` から読み込む（キー: `"vibe.serverHost"`）。
- 進行中の `task_id` は `UserDefaults`（キー: `"vibe.activeTaskId"`）に永続化し `resumeIfNeeded()` で再開。
- ポーリング間隔は **2秒**。`status` が `completed`/`failed` になったら停止し、`completed` 時は `loadDiff()` を自動実行。

---

## 6. 実装上の共通ルール

1. 各エージェントは **自分が「Owns」に指定されたファイルのみ** を作成/編集する。他人のファイルを作らない。
2. 上記の型・JSON形状・シグネチャを変更しない。
3. コメントは簡潔に、日本語可。
4. 秘密情報をハードコードしない（`.env.example` はダミー値のみ）。
5. バックエンドは `npx tsc --noEmit` が通ることを目標にする（他ファイル未完による import エラーは許容だが、自分の担当ファイル内の型は正しく）。
