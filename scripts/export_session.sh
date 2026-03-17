#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Использование: $0 <session_id>"
  exit 1
fi

SESSION_ID="$1"
APP_DIR="$HOME/gps-logger"
EXPORTS_DIR="$APP_DIR/data/exports"
mkdir -p "$EXPORTS_DIR"

TARGET_DIR=""

while IFS= read -r -d '' path; do
  TARGET_DIR="$path"
  break
done < <(find "$APP_DIR/data/sessions" -type d -name "$SESSION_ID" -print0)

if [ -z "$TARGET_DIR" ]; then
  echo "[ERR] Сессия не найдена: $SESSION_ID"
  exit 1
fi

ARCHIVE="$EXPORTS_DIR/$SESSION_ID.tar.gz"
tar -czf "$ARCHIVE" -C "$(dirname "$TARGET_DIR")" "$(basename "$TARGET_DIR")"
echo "[OK] Экспортировано: $ARCHIVE"
