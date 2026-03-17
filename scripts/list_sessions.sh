#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="$HOME/gps-logger"
SESSIONS_DIR="$APP_DIR/data/sessions"

if [ ! -d "$SESSIONS_DIR" ]; then
  echo "[WARN] sessions dir not found"
  exit 0
fi

python - <<'PY'
import json
from pathlib import Path

sessions_dir = Path.home() / "gps-logger" / "data" / "sessions"
items = []

for meta_path in sessions_dir.glob("*/*/meta.json"):
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except Exception:
        continue
    items.append(meta)

items.sort(key=lambda x: x.get("created_at", ""), reverse=True)

if not items:
    print("[INFO] Нет сессий")
else:
    for m in items:
        print(
            f"{m.get('created_at','?')} | "
            f"{m.get('session_id','?')} | "
            f"status={m.get('status','?')} | "
            f"points={m.get('point_count','?')} | "
            f"date={m.get('session_date','?')}"
        )
PY
