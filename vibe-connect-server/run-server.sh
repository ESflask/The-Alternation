#!/bin/zsh
# The Alternation 中継サーバー 常駐起動ラッパー（launchd から呼ばれる）
# - 本物 Claude(-p) モードの環境変数を固定
# - 起動前にポート3000の残留プロセスを掃除（モック二重起動の再発防止）
# - caffeinate でサーバー稼働中はスリープ抑止（node が終わると抑止も解除）
# - dist/index.js（コンパイル版）を実行。サーバーコード変更時は `npm run build` → 再起動。

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PORT=3000
export TARGET_WORKSPACE_PATH="/Users/endoushougo/Python_pjs/vibe-sandbox"
export CLAUDE_BIN="/Users/endoushougo/.local/bin/claude"
export CLAUDE_ARGS="-p"

SERVER_DIR="/Users/endoushougo/Python_pjs/The Alternation/vibe-connect-server"
cd "$SERVER_DIR" || exit 1

# 3000番の残留プロセス（古い dev/mock サーバー等）を掃除してからバインド
lsof -ti tcp:3000 2>/dev/null | xargs kill -9 2>/dev/null

# node が生きている間だけ idle/system スリープを抑止して常駐させる
exec caffeinate -is /opt/homebrew/bin/node dist/index.js
