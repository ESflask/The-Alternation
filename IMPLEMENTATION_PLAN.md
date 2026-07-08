# システム開発仕様書：VibeConnect (v1.0.0)
Inside-out Remote AI Coding Environment

本ドキュメントは、Mac上の「Claude Code」をiPhone（iOS自作アプリ）から安全かつ快適にリモート操作し、リラックスした環境での「Vibe Coding（雰囲気コーディング）」を実現するための、具体的なシステム実装仕様書である。

---

## 1. プロジェクト概要

### 1.1 目的とゴール
Macの前に縛られることなく、ベッドやソファーに寝転んだままiPhoneのチャットUIを通じてMac上の高性能AIエージェント（Claude Code CLI）を駆動する。
「大雑把な指示 ➔ AIによるコード生成 ➔ テスト・ビルド自動実行 ➔ 差分（Diff）確認 ➔ コミット・プッシュ」という一連の開発ライフサイクルを、スマホ一台で完結させることをゴールとする。

### 1.2 コア原則（AI丸投げ開発への最適化）
本システム自体のコーディングも「Claude Code（Max 20xプラン）」に大部分を委ねるため、以下のAIフレンドリーな設計を徹底する。
1. **徹底した疎結合（関心の分離）:** iOSアプリ側には複雑なターミナルパースやSSH制御を一切持たせない。フロントエンド（iOS）は「純粋なチャットUIとJSONの送受信」、バックエンド（Mac）は「コマンドの実行と結果の構造化」に完全に役割を分担する。
2. **ステートレス＆非同期キュー:** Claude Codeのタスク実行は数分に及ぶ可能性がある。iOSのバックグラウンド制限（数分で通信サスペンド）に対応するため、Mac側でタスクをキュー管理し、iPhone側はポーリング（定期確認）によって進捗を追跡する設計とする。

### 1.3 前提環境
* **ホスト（Mac）:** macOS 15+ (Sequoia以降) / Claude CLIインストールおよびログイン済 / 有効なClaude Max 20xサブスクリプション
* **クライアント（iPhone）:** iOS 17+ / 自作SwiftUIアプリ
* **ネットワーク:** ホスト・クライアント双方に「Tailscale」が導入され、同一のTailnet内でプライベート通信が可能であること

---

## 2. 全体アーキテクチャと通信フロー

### 2.1 コンポーネント構成
```
[iPhone: SwiftUI App] 
       │
       ▼ (HTTP / JSON / Tailscale 暗号化 P2P 通信)
[Mac: 中継APIサーバー (Node.js + Express)] ── (タスク状態をメモリ内オブジェクトで管理)
       │
       ▼ (child_process.spawn / 非対話モード `-y` 実行)
[Claude Code CLI] ───► [対象のソースコード (Gitリポジトリ)]
```

### 2.2 詳細通信シーケンス

```
iPhone (SwiftUI)             Mac (中継APIサーバー)             Claude Code CLI
      │                               │                                │
      │ 1. POST /api/tasks (指示送信)  │                                │
      ├──────────────────────────────►│                                │
      │                               │ 2. タスクID発行、バックグラウンド │
      │ 3. 202 Accepted (タスクID返却) │    でプロセスを非同期起動       │
      │◄──────────────────────────────┤ ──┐                            │
      │                               │   │ `claude -y "指示内容"`     │
      │                               │   ▼                            │
      │                               ├───────────────────────────────►│
      │                               │                                │
      │ 4. GET /api/tasks/:id         │ 5. 標準出力をリアルタイム取得   │
      │    (2秒ごとのポーリング開始)   │◄──────────────────────────────┤
      ├──────────────────────────────►│                                │
      │ 6. 200 OK (ステータス・ログ)   │                                │
      │◄──────────────────────────────┤                                │
      :                               :                                :
      │                               │ 7. Claude Code 処理完了(exit)   │
      │                               │◄──────────────────────────────┤
      │ 8. GET /api/tasks/:id         │                                │
      ├──────────────────────────────►│                                │
      │ 9. 200 OK (status: 'completed')│                                │
      │◄──────────────────────────────┤                                │
      │                               │                                │
      │ 10. GET /api/git/diff         │                                │
      ├──────────────────────────────►│ 11. `git diff` 実行            │
      │ 12. 200 OK (差分テキスト返却)  │◄──────────────────────────────┤
      │◄──────────────────────────────┤                                │
      │                               │                                │
      │ ── ユーザーが変更を確認・承認 ──  │                                │
      │                               │                                │
      │ 13. POST /api/git/commit      │                                │
      ├──────────────────────────────►│ 14. `git commit -am "..."`     │
      │ 15. 200 OK (完了)             │◄──────────────────────────────┤
      │◄──────────────────────────────┤                                │
```

---

## 3. ホスト側（Mac）：中継APIサーバー仕様

### 3.1 ディレクトリ構成（推奨）
```
vibe-connect-server/
├── package.json
├── tsconfig.json
├── .env
└── src/
    ├── index.ts          # エントリーポイント・Express設定
    ├── queue.ts          # タスクキュー・非同期プロセス管理
    └── routes/
        ├── tasks.ts      # タスク関連APIルーティング
        └── git.ts        # Git操作関連APIルーティング
```

### 3.2 必要パッケージ（依存関係）
* `express`, `cors`, `dotenv`, `uuid`
* `types/express`, `types/cors`, `types/uuid`, `typescript`, `ts-node` (開発依存)

### 3.3 環境変数設定 (`.env`)
```env
PORT=3000
TARGET_WORKSPACE_PATH=/Users/username/projects/your-target-app
# 注: Claude Codeのサブスク枠を使うため、ANTHROPIC_API_KEYはあえて設定しない
```

### 3.4 APIエンドポイント詳細

#### ① タスクの新規作成（AIへの指示送信）
* **メソッド / パス:** `POST /api/tasks`
* **リクエストボディ:**
  ```json
  {
    "instruction": "src/Views/MainView.swift のボタンの色をシステムブルーに変更してテストを実行して"
  }
  ```
* **レスポンス (202 Accepted):**
  ```json
  {
    "task_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
    "status": "processing",
    "message": "Task successfully dispatched to Claude Code."
  }
  ```
* **内部処理ロジック:**
  1. `uuid` で一意な `task_id` を発行。
  2. メモリ上のタスク管理オブジェクトに `status: "processing"`, `logs: ""` で登録。
  3. `child_process.spawn` を使用して、`.env` で指定されたリポジトリパスのルートで以下のコマンドを非同期実行。
     `claude -y "${instruction}"`
  4. プロセスの `stdout` および `stderr` にデータが流れてくるたびに、該当するタスクの `logs` 文字列に追記。
  5. プロセスが終了（`exit`）したら、終了コードが `0` なら `status: "completed"`、それ以外なら `status: "failed"` に更新。

#### ② タスクのステータス・進捗取得（ポーリング先）
* **メソッド / パス:** `GET /api/tasks/:id`
* **レスポンス (200 OK):**
  ```json
  {
    "task_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
    "status": "processing | completed | failed",
    "logs": "Claude Codeの現在の標準出力ログ（ANSIエスケープシーケンス除去済みが望ましい）...",
    "error": "エラーが発生した場合はここにメッセージ"
  }
  ```

#### ③ 現在のGit差分（Diff）の取得
* **メソッド / パス:** `GET /api/git/diff`
* **レスポンス (200 OK):**
  ```json
  {
    "has_changes": true,
    "diff": "--- a/src/Views/MainView.swift\n+++ b/src/Views/MainView.swift\n@@ -10,5 +10,5 @@\n- Button(\"Click Me\") {}.background(Color.red)\n+ Button(\"Click Me\") {}.background(Color.blue)"
  }
  ```

#### ④ 変更の確定（Commit）
* **メソッド / パス:** `POST /api/git/commit`
* **リクエストボディ:**
  ```json
  {
    "message": "style: update button color to blue"
  }
  ```
* **レスポンス (200 OK):**
  ```json
  {
    "success": true,
    "message": "Changes committed successfully."
  }
  ```

---

## 4. クライアント側（iPhone）：iOSアプリ仕様

### 4.1 アプリケーション基本構造
SwiftUIを採用し、ステート（タスク状態、接続状態、ログ）を一元管理する `TaskViewModel` を中心に構築する。

### 4.2 画面（ビュー）要件

#### A. メイン・チャットビュー (`ConsoleChatView`)
* **上部ヘッダー:** Macサーバー（Tailscale IP）への接続状態インジケータ（Green/Red）。
* **ログ・チャットタイムライン:**
  * 過去に送信した指示文をユーザー発言として右側に配置。
  * Claude Codeからの出力（`logs`）を左側にリアルタイムスクロール表示。フォントは等幅（`Font.system(.body, design: .monospaced)`）を採用。
* **ステータス表示:** タスクが `processing` の間は、プログレススピナーを表示し、画面最下部への自動スクロールを維持。
* **下部入力欄:** テキストエリアと送信ボタン。キーボード表示時にレイアウトが崩れないよう `SafeArea` を適切に制御。

#### B. コード差分ビュー (`DiffInspectorView`)
* **データパース:** `GET /api/git/diff` で取得した文字列を改行コードで分割し、行ごとにレンダリング。
  * 行頭が `+` の場合: 薄緑の背景（`Color.green.opacity(0.15)`）＋緑の文字色
  * 行頭が `-` の場合: 薄赤の背景（`Color.red.opacity(0.15)`）＋赤の文字色
  * それ以外: 背景なし、通常の文字色
* **フッターアクション:** 「この変更を適用（Commit）」ボタンを配置。タップすると、コミットメッセージ入力用のダイアログ（Alert / Sheet）を表示し、Mac側へ確定リクエストを送る。

### 4.3 堅牢化仕様（対障害性）
* **AppState連携:** アプリがバックグラウンドに移行しても、進行中の `task_id` は `UserDefaults` 等に永続化保持。
* **自動復旧:** アプリ再起動やフォアグラウンド復帰時に、未完了の `task_id` があれば即座にポーリング処理を再開し、画面状態を最新に同期する。

---

## 5. ネットワークとセキュリティ

* **ポート開放の禁止:** 自宅ルーターのWANポート開放やグローバルIPの直接露出は絶対を行わない。
* **Tailscaleによる解決:** MacとiPhoneの両方にTailscaleアプリをインストールし、同一アカウントでログイン。iPhoneからはMacの「Tailscale IP（例: `100.x.y.z`）」に対して `http://100.x.y.z:3000` でアクセスする。これにより、外出先のキャリア回線（4G/5G）からでも暗号化された安全なP2P通信でMacに直結できる。

---

## 6. 開発ステップとClaude Code用プロンプト

実際にMac上のClaude Codeを使ってこのシステム（VibeConnect）を自作させる際は、コンテキストの肥大化と迷走を防ぐため、以下の順序で1ステップずつファイルを作らせること。

### ステップ1: バックエンドのベース作成
**【Claude Codeへの指示プロンプト例】**
> 新規にNode.js + TypeScript + Expressのプロジェクトを作成してください。まずは基本構造（package.json, tsconfig.json, src/index.ts）をセットアップし、ポート3000で起動するシンプルなWebサーバーを作ってください。CORSを有効にし、生存確認用の `GET /health` エンドポイントを含めてください。

### ステップ2: 非同期タスクキューの実装
**【Claude Codeへの指示プロンプト例】**
> src/queue.ts を作成し、メモリ内でタスクの状態を管理する簡易キューシステムを実装してください。`POST /api/tasks` で指示を受け取ったらuuidを発行して202を返し、バックグラウンドで `child_process.spawn` を使ってダミーのシェルコマンド（例: `sleep 10 && echo 'done'`）を実行し、その出力をリアルタイムにタスクのlogオブジェクトに記録する仕組みを作ってください。また、`GET /api/tasks/:id` でその状態を取得できるようにルーティングを紐付けてください。

### ステップ3: Claude Code CLIの統合
**【Claude Codeへの指示プロンプト例】**
> バックグラウンドで実行するコマンドを、実際の `claude -y "ユーザーの指示"` に置き換えてください。実行パスは環境変数 `TARGET_WORKSPACE_PATH` から読み込むようにし、コマンド実行時の標準出力と標準エラー出力を正しくキャッチしてログに追記するようロジックを堅牢にしてください。また、`GET /api/git/diff` および `POST /api/git/commit` を実装し、対象リポジトリの `git diff` の取得や、指定メッセージでの `git commit -am` が実行できるようにしてください。

### ステップ4: iOSアプリ（SwiftUI）のUIモック作成
**【Claude Codeへの指示プロンプト例】**
> SwiftUIを使用して、iPhone用のチャット兼コンソール画面（MainView）と、Gitの差分を赤・緑で色分け表示する差分確認画面（DiffView）のモックUIを作成してください。まだ通信ロジックは不要で、プレビュー用のダミーデータ（処理中のアニメーションや、ダミーのgit diffテキスト）がきれいに表示されることを最優先に、モダンなデザインでコーディングしてください。

### ステップ5: iOSアプリの通信・ポーリング実装
**【Claude Codeへの指示プロンプト例】**
> SwiftUIのモックUIに対して、URLSessionを使ったAPI通信ロジックを統合してください。指示を送信したらタスクIDを受け取り、TimerまたはTaskのループを用いて2秒ごとに `GET /api/tasks/:id` をポーリングしてログをリアルタイム更新するロジックを実装してください。タスク完了後は自動的にDiff画面に遷移するか、Diff取得ボタンが活性化するように状態管理（ViewModel）を構築してください。