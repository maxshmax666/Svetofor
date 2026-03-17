#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/gps-logger}"
PID_FILE="$APP_DIR/run/gps_logger.pid"

# shellcheck source=/dev/null
source "$APP_DIR/scripts/common.sh"
PORT="$(resolve_port)"
PY_BIN="$(resolve_python_bin)"

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
HEALTH_URL="http://127.0.0.1:${PORT}/health"
if HEALTH_PAYLOAD="$(curl -fsS "$HEALTH_URL")"; then
  echo "  [OK] $HEALTH_URL"
  if HEALTH_PAYLOAD="$HEALTH_PAYLOAD" EXPECTED_PORT="$PORT" "$PY_BIN" - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["HEALTH_PAYLOAD"])
expected_port = int(os.environ["EXPECTED_PORT"])
actual_port = payload.get("port")

if actual_port != expected_port:
    print(f"  [ERR] health.port mismatch: expected={expected_port} actual={actual_port}")
    sys.exit(1)

print(f"  [OK] health.port={actual_port}")
PY
  then
    :
  else
    exit 1
  fi
else
  echo "  [ERR] /health unavailable"
  exit 1
fi
