#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="$HOME/gps-logger"
PID_FILE="$APP_DIR/run/gps_logger.pid"

echo "[1] Структура"
for p in \
  "$APP_DIR/app" \
  "$APP_DIR/web" \
  "$APP_DIR/data" \
  "$APP_DIR/data/sessions" \
  "$APP_DIR/data/manifests" \
  "$APP_DIR/data/exports" \
  "$APP_DIR/run" \
  "$APP_DIR/scripts"
do
  if [ -e "$p" ]; then
    echo "  [OK] $p"
  else
    echo "  [ERR] $p"
  fi
done

echo "[2] PID"
if [ -f "$PID_FILE" ]; then
  PID="$(cat "$PID_FILE" || true)"
  if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
    echo "  [OK] server pid alive: $PID"
  else
    echo "  [WARN] pid file exists but process dead"
  fi
else
  echo "  [WARN] pid file missing"
fi

echo "[3] HTTP /health"
curl -fsS http://127.0.0.1:8080/health && echo || echo "  [ERR] /health unavailable"
