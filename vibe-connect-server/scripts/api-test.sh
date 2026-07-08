#!/usr/bin/env bash
# VibeConnect API 疎通テスト (Agent 3)
# サーバー起動中に叩く curl ベースの簡易 E2E テスト。
#
# 使い方:
#   1) 別ターミナルでサーバーを起動する（モック CLI を使う例）:
#        cd vibe-connect-server
#        TARGET_WORKSPACE_PATH="/path/to/your/git/repo" \
#        CLAUDE_BIN="./src/mock/mock-claude.sh" \
#        npm run dev
#      ※ /api/git/diff まで検証したい場合、TARGET_WORKSPACE_PATH は git リポジトリを指すこと。
#   2) 本スクリプトを実行:
#        ./scripts/api-test.sh
#        BASE=http://100.x.y.z:3000 ./scripts/api-test.sh    # Tailscale 経由で叩く場合
#        INSTRUCTION="ボタンの色を青に" ./scripts/api-test.sh  # 送る指示文を変える場合
#
# 依存: curl（jq があれば整形/抽出に使用。無ければ grep/sed でフォールバック）

set -euo pipefail

BASE="${BASE:-http://localhost:3000}"
INSTRUCTION="${INSTRUCTION:-mock: VIBE_MOCK.txt に一行追記してテストを実行して}"

HAS_JQ=0
if command -v jq >/dev/null 2>&1; then
  HAS_JQ=1
fi

echo "==> BASE=${BASE}  (jq=$([ "${HAS_JQ}" -eq 1 ] && echo yes || echo no))"

# --- 1) GET /health ---
echo ""
echo "==> GET /health"
curl -sS "${BASE}/health"
echo ""

# --- 2) POST /api/tasks ---
echo ""
echo "==> POST /api/tasks"
CREATE_RESP="$(curl -sS -X POST "${BASE}/api/tasks" \
  -H 'Content-Type: application/json' \
  -d "{\"instruction\": \"${INSTRUCTION}\"}")"
echo "${CREATE_RESP}"

# task_id を抽出（jq 優先、無ければ grep/sed フォールバック）。
TASK_ID=""
if [ "${HAS_JQ}" -eq 1 ]; then
  TASK_ID="$(printf '%s' "${CREATE_RESP}" | jq -r '.task_id // empty')" || true
else
  TASK_ID="$(printf '%s' "${CREATE_RESP}" \
    | grep -o '"task_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed -E 's/.*"task_id"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')" || true
fi
echo "==> task_id=${TASK_ID}"

if [ -z "${TASK_ID}" ] || [ "${TASK_ID}" = "null" ]; then
  echo "!! task_id を取得できませんでした。サーバー応答を確認してください。中断します。" >&2
  exit 1
fi

# --- 3) GET /api/tasks/:id を数回ポーリング ---
echo ""
echo "==> GET /api/tasks/${TASK_ID}（2秒間隔でポーリング）"
STATUS_RESP=""
STATUS=""
for i in $(seq 1 10); do
  STATUS_RESP="$(curl -sS "${BASE}/api/tasks/${TASK_ID}")"
  if [ "${HAS_JQ}" -eq 1 ]; then
    STATUS="$(printf '%s' "${STATUS_RESP}" | jq -r '.status // empty')" || true
  else
    STATUS="$(printf '%s' "${STATUS_RESP}" \
      | grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -1 \
      | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/')" || true
  fi
  echo "  [poll ${i}] status=${STATUS}"
  if [ "${STATUS}" = "completed" ] || [ "${STATUS}" = "failed" ]; then
    break
  fi
  sleep 2
done

echo ""
echo "==> 最終タスク状態"
if [ "${HAS_JQ}" -eq 1 ]; then
  printf '%s' "${STATUS_RESP}" | jq .
else
  echo "${STATUS_RESP}"
fi

# --- 4) GET /api/git/diff ---
echo ""
echo "==> GET /api/git/diff"
DIFF_RESP="$(curl -sS "${BASE}/api/git/diff")"
if [ "${HAS_JQ}" -eq 1 ]; then
  printf '%s' "${DIFF_RESP}" | jq .
else
  echo "${DIFF_RESP}"
fi

# --- 参考: 変更の確定（Commit）は任意で以下を実行 ---
echo ""
echo "==> 完了。変更を確定するには（任意）:"
echo "    curl -sS -X POST ${BASE}/api/git/commit \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"message\":\"test: mock commit\"}'"
