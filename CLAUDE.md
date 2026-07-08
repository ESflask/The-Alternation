# The Alternation

自作 iOS アプリ（SwiftUI）から、Mac 上で動く **Claude Code CLI** を HTTP/JSON 経由で遠隔操作するためのシステム。
スマホから大雑把な指示を送ると、Mac 側の Claude Code が実行し、結果・差分・使用量をアプリに返す。

- `vibe-connect-server/` … Node.js + TypeScript + Express の中継 API サーバー。指示を `claude` CLI に `child_process` で渡す。
- `VibeConnectApp/` … SwiftUI 製 iOS アプリ（XcodeGen 管理）。チャット / ファイル閲覧編集 / 差分 / モデル選択 / 使用量表示。

---

## ⚠️ セキュリティ / デプロイ厳守事項（このリポジトリは公開）

このリポジトリを触る人間・エージェントは以下を必ず守ること。

1. **Claude Code のアカウント情報を絶対にコミット・公開しない。**
   認証は `~/.claude/`（OAuth トークン等）と macOS キーチェーンにあり、本リポジトリ外。
   これらや `.env`、APIキー、`*.pem/*.key/*.p12/*.mobileprovision` は `.gitignore` 済み。**追加しない・貼らない。**

2. **サーバーを公開インターネットに晒さない。**
   本サーバーは平文 HTTP 前提（iOS 側は `NSAllowsArbitraryLoads`）で、**Tailscale などプライベート網専用**。
   ポート 3000 を外部公開・ポート開放・リバースプロキシで一般公開しないこと。

3. **`CLAUDE_ARGS` に `--permission-mode bypassPermissions`（自律編集）を入れた常駐サーバーは特に危険。**
   到達できる相手は誰でも **あなたの Mac 上で無人のファイル編集・コマンド実行**をさせられる。
   使うなら「信頼できるプライベート網のみ」かつ `TARGET_WORKSPACE_PATH` は**捨ててよいサンドボックス**に限定する。
   既定は会話用の `-p`（`--print`）にとどめる。

4. **`TARGET_WORKSPACE_PATH` は Claude の作業対象＝影響範囲。**
   重要なリポジトリを指定しない。専用サンドボックス（例: 別ディレクトリの git リポ）を推奨。

5. **署名情報は各自のものに置換が必要。**
   `VibeConnectApp/project.yml` の `DEVELOPMENT_TEAM` / `PRODUCT_BUNDLE_IDENTIFIER` は作者固有。クローンした人は自分の Apple Developer 設定に変更すること。

---

## 構成 / データフロー

```
iPhone (SwiftUI) ──HTTP/JSON──▶ vibe-connect-server (Express) ──spawn──▶ claude CLI ──▶ 対象リポジトリ
        ▲                              │
        └──────ポーリングでログ/差分/使用量を取得──────┘
```

主な API:
- `POST /api/tasks` … 指示を受けて `claude` を起動（`{instruction, model?, effort?}`）。`GET /api/tasks/:id` でポーリング。
- `GET /api/git/diff` / `POST /api/git/commit`
- `GET /api/files/tree|read` / `PUT /api/files/write`
- `POST /api/title` … チャットの自動命名（`claude -p --model haiku`）
- `GET /api/usage?scope=all|sandbox` … `~/.claude/projects/**/*.jsonl` から使用量を集計（実測トークン＋**推定**コスト。公式請求とは別物）

---

## セットアップ & 実行

### サーバー（vibe-connect-server）
```bash
cd vibe-connect-server
npm install
npm run build           # tsc → dist/
# 環境変数を与えて起動（.env は各自作成。コミット禁止）
PORT=3000 \
TARGET_WORKSPACE_PATH=/path/to/your/sandbox-repo \
CLAUDE_BIN=/absolute/path/to/claude \
CLAUDE_ARGS="-p" \
node dist/index.js
```

必要な環境変数（`.env` はリポジトリに含めない）:

| 変数 | 意味 | 例 |
|---|---|---|
| `PORT` | 待受ポート | `3000` |
| `TARGET_WORKSPACE_PATH` | Claude の作業対象リポジトリ（**サンドボックス推奨**） | `/path/to/sandbox` |
| `CLAUDE_BIN` | `claude` 実行ファイルの絶対パス | `~/.local/bin/claude` |
| `CLAUDE_ARGS` | 前置フラグ。会話は `-p`。自律編集は自己責任 | `-p` |

### 常駐化（macOS / launchd + caffeinate）
- `vibe-connect-server/run-server.sh` を起動ラッパとして LaunchAgent から実行する構成（環境変数固定＋ポート掃除＋`caffeinate` でスリープ抑止）。
- **注意**: `run-server.sh` と LaunchAgent の plist にはマシン固有の絶対パスが入る。各自の環境に合わせて書き換えること。

### iOS アプリ（VibeConnectApp）
```bash
cd VibeConnectApp
xcodegen generate       # project.yml → *.xcodeproj（.xcodeproj は .gitignore 済み）
# Xcode で開くか、xcodebuild でビルド。実機は iOS バージョンに合う Xcode が必要。
```

---

## コミットしてはいけないもの（.gitignore 済み）
- `node_modules/`, `dist/`, `build/`, `DerivedData/`, `*.xcodeproj/`
- `.env` / `.env.*` / 各種鍵・証明書 / `.claude/`
