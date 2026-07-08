# The Alternation<img width="1024" height="1024" alt="icon" src="https://github.com/user-attachments/assets/444ce404-4bf8-4631-96cc-57c5af460b4a" />


自作の iOS アプリから、Mac 上で動く **Claude Code CLI** を遠隔操作するためのシステムです。
スマートフォンから大まかな指示を送ると、Mac 側の Claude Code が実行し、結果・差分・使用量をアプリへ返します。外出先からでも（Tailscale 経由で）自宅 Mac の Claude Code を動かせます。

> セキュリティとデプロイ時の厳守事項は [CLAUDE.md](./CLAUDE.md) にまとめています。公開・常駐運用の前に必ず読んでください。

## 構成

| ディレクトリ | 役割 |
| --- | --- |
| `vibe-connect-server/` | Node.js + TypeScript + Express の中継 API サーバー。受け取った指示を `claude` CLI に渡し、ログ・差分・使用量を返す。 |
| `VibeConnectApp/` | SwiftUI 製の iOS アプリ。XcodeGen 管理。チャット・ファイル閲覧編集・差分・モデル選択・使用量表示を持つ。 |

## 主な機能

- スマホからの指示送信と、Claude Code の応答の逐次表示（2 秒ポーリング）
- モデル / effort の選択（Opus / Sonnet / Haiku / Fable、Low〜Max）
- コードブロックだけをターミナル枠で表示する読みやすいチャット描画（Markdown 対応）
- 左ドロワーのチャット履歴・検索、`/` スラッシュコマンド
- チャットの自動命名（Claude が短い題名を付与）
- ファイルツリーの閲覧と編集の保存、`git diff` の色分け表示とコミット
- 使用量表示（`/usage`）: ローカルログからトークン量と推定コストを集計
- 既存の Claude Code 履歴（サンドボックス分）の読み込み

## アーキテクチャ

```
iPhone (SwiftUI)  --HTTP/JSON-->  中継サーバー (Express)  --spawn-->  claude CLI  -->  対象リポジトリ
      ^                                  |
      +----------- ログ / 差分 / 使用量をポーリングで取得 ----------+
```

主な API:

- `POST /api/tasks` … 指示を受けて `claude` を起動（`GET /api/tasks/:id` でポーリング）
- `GET /api/git/diff` / `POST /api/git/commit`
- `GET /api/files/tree|read` / `PUT /api/files/write`
- `POST /api/title` … チャットの自動命名
- `GET /api/usage` … ローカルログの使用量集計（実測トークン + 推定コスト）
- `GET /api/history/sessions` / `GET /api/history/:id` … 既存履歴の読み込み

## セットアップ

### サーバー

```bash
cd vibe-connect-server
npm install
npm run build
PORT=3000 \
TARGET_WORKSPACE_PATH=/path/to/your/sandbox-repo \
CLAUDE_BIN=/absolute/path/to/claude \
CLAUDE_ARGS="-p" \
node dist/index.js
```

必要な環境変数（`.env` はリポジトリに含めないこと）:

| 変数 | 意味 |
| --- | --- |
| `PORT` | 待受ポート（例 3000） |
| `TARGET_WORKSPACE_PATH` | Claude の作業対象リポジトリ。捨ててよいサンドボックス推奨 |
| `CLAUDE_BIN` | `claude` 実行ファイルの絶対パス |
| `CLAUDE_ARGS` | 前置フラグ。会話用は `-p`。自律編集は自己責任 |

### 常駐化（macOS / launchd + caffeinate）

`vibe-connect-server/run-server.sh` を起動ラッパとして LaunchAgent から実行すると、ログイン時の自動起動・クラッシュ時の自動再起動・サーバー稼働中のスリープ抑止ができます。plist とスクリプトにはマシン固有の絶対パスが入るため、各自の環境に合わせて書き換えてください。

### iOS アプリ

```bash
cd VibeConnectApp
xcodegen generate      # project.yml から *.xcodeproj を生成
```

Xcode で開いてビルドします。実機へは、その iOS バージョンに対応した Xcode が必要です。`project.yml` の `DEVELOPMENT_TEAM` と `PRODUCT_BUNDLE_IDENTIFIER` は自分の Apple Developer 設定に置き換えてください。

## セキュリティ上の注意

- Claude Code の認証情報（`~/.claude/`・キーチェーン）や `.env`・鍵類は絶対にコミットしないこと（`.gitignore` 済み）。
- サーバーは平文 HTTP 前提です。公開インターネットには晒さず、Tailscale などのプライベート網でのみ使ってください。
- `CLAUDE_ARGS` に自律編集モード（`bypassPermissions`）を入れた常駐サーバーは、到達できる相手が無人でファイル編集・コマンド実行をできる状態になります。信頼できる網かつ捨ててよいサンドボックスに限定してください。

詳細は [CLAUDE.md](./CLAUDE.md) を参照してください。
