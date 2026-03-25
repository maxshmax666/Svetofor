#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/gps-logger}"
PID_FILE="$APP_DIR/run/gps_logger.pid"
LOG_FILE="$APP_DIR/run/server.log"

# shellcheck source=/dev/null
source "$APP_DIR/scripts/common.sh"
PORT="$(resolve_port)"

mkdir -p "$APP_DIR/run"

if [ -f "$PID_FILE" ]; then
  OLD_PID="$(cat "$PID_FILE" || true)"
  if [ -n "${OLD_PID:-}" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[ERR] Сервер уже запущен, PID=$OLD_PID"
    exit 1
  fi
  rm -f "$PID_FILE"
fi

if command -v lsof >/dev/null 2>&1; then
  if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[ERR] Порт $PORT уже занят"
    exit 1
  fi
fi

cd "$APP_DIR"
nohup python -m app.server > "$LOG_FILE" 2>&1 &
PID=$!
echo "$PID" > "$PID_FILE"

sleep 2

if kill -0 "$PID" 2>/dev/null; then
  echo "[OK] GPS logger запущен"
  echo "[OK] PID: $PID"
  echo "[OK] URL: http://127.0.0.1:$PORT"
  echo "[OK] LOG: $LOG_FILE"
else
  echo "[ERR] Не удалось запустить сервер"
  echo "----- server.log -----"
  cat "$LOG_FILE" || true
  exit 1
fi
