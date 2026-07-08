#!/usr/bin/env bash
# VibeConnect ローカルテスト用 Claude CLI スタブ (Agent 3)
# 実際の Claude CLI 枠を消費せずに、キュー / ログ取得 / diff / commit の動作確認を行うためのモック。
#
# 使い方:
#   サーバー起動時に CLAUDE_BIN で本スクリプトを指定すると、`claude` の代わりに呼ばれる。
#   引数（$@）にはユーザーの指示文が渡される想定。
#     TARGET_WORKSPACE_PATH="/path/to/repo" \
#     CLAUDE_BIN="./src/mock/mock-claude.sh" \
#     npm run dev
#
# 挙動:
#   1) 受け取った指示文をエコー
#   2) 数行のログを 0.5〜1秒間隔で標準出力（ANSIカラー行を1行含む → ANSI除去のテスト用）
#   3) TARGET_WORKSPACE_PATH が git リポジトリなら VIBE_MOCK.txt に追記し、diff/commit のテスト材料を作る
#   4) exit 0

set -u

# --- 1) 指示文のエコー ---
echo "[mock-claude] instruction: $*"

# --- 2) 進捗ログ（0.5〜1秒間隔、ANSIカラーを1行含める）---
sleep 0.5
echo "Analyzing repository..."
sleep 0.7
# ANSI エスケープ付きの行（黄色）。サーバー側の ANSI 除去処理のテスト用。
printf '\033[33mEditing files...\033[0m\n'
sleep 0.7
echo "Running tests..."
sleep 0.6
echo "All checks passed."
sleep 0.5
echo "Done."

# --- 3) git リポジトリなら軽微な変更を作る ---
WORKSPACE="${TARGET_WORKSPACE_PATH:-$(pwd)}"
if git -C "${WORKSPACE}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  MOCK_FILE="${WORKSPACE}/VIBE_MOCK.txt"
  {
    echo "mock change @ $(date '+%Y-%m-%d %H:%M:%S')"
    echo "instruction: $*"
  } >>"${MOCK_FILE}"
  echo "[mock-claude] appended change to ${MOCK_FILE}"
else
  echo "[mock-claude] '${WORKSPACE}' は git リポジトリではないため差分は作成しません。"
fi

exit 0
