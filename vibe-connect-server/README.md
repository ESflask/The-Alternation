# VibeConnect 中継APIサーバー

Mac 上の **Claude Code CLI** を iPhone（自作 SwiftUI アプリ）からリモート操作するための中継 API サーバーです。
Node.js + TypeScript + Express で実装され、Tailscale 経由のプライベート通信で iPhone と接続します。

- フロントエンド（iOS）: 純粋なチャット UI と JSON 送受信
- バックエンド（本サーバー）: コマンドの実行と結果の構造化

---

## 必要環境

- Node.js **22 以上**
- macOS 15+（Claude CLI インストール・ログイン済み / 有効な Claude Max サブスクリプション）
- Tailscale（Mac / iPhone 双方に導入、同一 Tailnet）

---

## セットアップ

```bash
# 1. 依存インストール
npm install

# 2. 環境変数ファイルを作成して編集
cp .env.example .env
#   TARGET_WORKSPACE_PATH を対象リポジトリの絶対パスに書き換える

# 3. 開発起動（ホットリロード）
npm run dev
```

その他のスクリプト:

| コマンド | 説明 |
| --- | --- |
| `npm run dev` | `tsx watch` によるホットリロード起動 |
| `npm run build` | `tsc` で `dist/` にビルド |
| `npm start` | ビルド済み `dist/index.js` を起動 |
| `npm run typecheck` | `tsc --noEmit` で型チェックのみ実行 |

---

## 環境変数（`.env`）

| 変数 | デフォルト | 説明 |
| --- | --- | --- |
| `PORT` | `3000` | サーバーの待ち受けポート |
| `TARGET_WORKSPACE_PATH` | （必須） | Claude CLI と git を実行する対象リポジトリの絶対パス |
| `CLAUDE_BIN` | `claude` | Claude CLI の実行バイナリ。テスト時は `mock/mock-claude.sh` へ差し替え可 |

> **注:** Claude Code のサブスク枠（Max 20x プラン）を利用するため、`ANTHROPIC_API_KEY` はあえて設定しません。

---

## API エンドポイント一覧

ベース URL: `http://<TAILSCALE_IP>:3000`

| メソッド / パス | 説明 |
| --- | --- |
| `GET /health` | 生存確認。`{ "status": "ok", "uptime": 123.45 }` |
| `POST /api/tasks` | 指示送信。`{ "instruction": "..." }` を受け取り 202 でタスク発行 |
| `GET /api/tasks/:id` | タスクのステータス・ログ取得（2秒ポーリング先） |
| `GET /api/git/diff` | 対象リポジトリの `git diff` を取得 |
| `POST /api/git/commit` | `{ "message": "..." }` で `git commit -am` を実行 |

### レスポンス例

`POST /api/tasks` → **202 Accepted**

```json
{
  "task_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "status": "processing",
  "message": "Task successfully dispatched to Claude Code."
}
```

`GET /api/tasks/:id` → **200 OK**

```json
{
  "task_id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "status": "processing",
  "logs": "ANSI除去済みの標準出力ログ...",
  "error": null
}
```

`GET /api/git/diff` → **200 OK**

```json
{ "has_changes": true, "diff": "--- a/... \n+++ b/... \n@@ ..." }
```

`POST /api/git/commit` → **200 OK**

```json
{ "success": true, "message": "Changes committed successfully." }
```

---

## Tailscale 経由アクセス

- 自宅ルーターの WAN ポート開放やグローバル IP の直接露出は **行いません**。
- Mac と iPhone の両方に Tailscale をインストールし、同一アカウントでログインします。
- 本サーバーは `0.0.0.0` で待ち受けるため、iPhone からは Mac の **Tailscale IP**（例: `100.x.y.z`）に対して
  `http://100.x.y.z:3000` でアクセスできます。
- これにより、外出先のキャリア回線（4G/5G）からでも暗号化された安全な P2P 通信で Mac に直結できます。

Mac の Tailscale IP は次のコマンドで確認できます:

```bash
tailscale ip -4
```
