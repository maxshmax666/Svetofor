#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Использование: $0 <session_id>"
  exit 1
fi

SESSION_ID="$1"
APP_DIR="$HOME/gps-logger"

cd "$APP_DIR"
ARCHIVE_PATH="$(python -m app.export_session "$SESSION_ID")"
echo "[OK] Экспортировано: $ARCHIVE_PATH"
