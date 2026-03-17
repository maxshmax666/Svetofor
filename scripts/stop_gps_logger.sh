#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="$HOME/gps-logger"
PID_FILE="$APP_DIR/run/gps_logger.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "[WARN] PID-файл не найден"
  exit 0
fi

PID="$(cat "$PID_FILE" || true)"

if [ -z "${PID:-}" ]; then
  echo "[WARN] PID пустой"
  rm -f "$PID_FILE"
  exit 0
fi

if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  sleep 1
  if kill -0 "$PID" 2>/dev/null; then
    kill -9 "$PID"
  fi
  echo "[OK] Сервер остановлен, PID=$PID"
else
  echo "[WARN] Процесс $PID уже не существует"
fi

rm -f "$PID_FILE"
