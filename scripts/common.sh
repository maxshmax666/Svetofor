#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/gps-logger}"

resolve_python_bin() {
  if command -v python >/dev/null 2>&1; then
    echo "python"
  elif command -v python3 >/dev/null 2>&1; then
    echo "python3"
  else
    echo "[ERR] python/python3 not found" >&2
    return 1
  fi
}

resolve_port() {
  local py_bin
  py_bin="$(resolve_python_bin)"
  (
    cd "$APP_DIR"
    "$py_bin" -c 'from app.config import PORT; print(PORT)'
  )
}

