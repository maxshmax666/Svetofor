#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Использование: $0 <session_id>"
  exit 1
fi

SESSION_ID="$1"
APP_DIR="$HOME/gps-logger"
TARGET=""

while IFS= read -r -d '' path; do
  TARGET="$path"
  break
done < <(find "$APP_DIR/data/sessions" -type f -path "*/$SESSION_ID/points.jsonl" -print0)

if [ -z "$TARGET" ]; then
  echo "[ERR] Сессия не найдена: $SESSION_ID"
  exit 1
fi

echo "[OK] tail -f $TARGET"
tail -f "$TARGET"
