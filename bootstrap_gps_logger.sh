#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="$HOME/gps-logger"

echo "[1/8] Установка пакетов..."
pkg update -y
pkg install -y python python-pip curl

echo "[2/8] Установка Flask..."
pip install flask

echo "[3/8] Создание структуры проекта..."
mkdir -p "$APP_DIR"/app
mkdir -p "$APP_DIR"/web
mkdir -p "$APP_DIR"/data/sessions
mkdir -p "$APP_DIR"/data/manifests
mkdir -p "$APP_DIR"/data/exports
mkdir -p "$APP_DIR"/run
mkdir -p "$APP_DIR"/scripts

echo "[4/8] Создание app/config.py..."
cat > "$APP_DIR/app/config.py" <<'PY'
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
APP_DIR = BASE_DIR / "app"
WEB_DIR = BASE_DIR / "web"
DATA_DIR = BASE_DIR / "data"
SESSIONS_DIR = DATA_DIR / "sessions"
MANIFESTS_DIR = DATA_DIR / "manifests"
EXPORTS_DIR = DATA_DIR / "exports"
RUN_DIR = BASE_DIR / "run"

PID_FILE = RUN_DIR / "gps_logger.pid"
SERVER_LOG_FILE = RUN_DIR / "server.log"
SESSIONS_INDEX_FILE = MANIFESTS_DIR / "sessions_index.jsonl"

HOST = "127.0.0.1"
PORT = 8080
TIMEZONE_NAME = "Europe/Berlin"

CSV_HEADER = [
    "session_id",
    "point_seq",
    "client_timestamp_ms",
    "client_iso_time",
    "client_local_time",
    "server_received_at",
    "latitude",
    "longitude",
    "accuracy_m",
    "altitude_m",
    "altitude_accuracy_m",
    "heading_deg",
    "speed_mps",
    "speed_kmh",
    "battery_level",
    "is_screen_visible",
    "sample_source",
    "raw_position_timestamp_ms",
    "user_agent",
]
PY

echo "[5/8] Создание app/models.py..."
cat > "$APP_DIR/app/models.py" <<'PY'
from __future__ import annotations
from dataclasses import dataclass, asdict
from typing import Optional, Dict, Any


@dataclass
class SessionMeta:
    session_id: str
    created_at: str
    closed_at: Optional[str]
    status: str
    session_date: str
    points_file_jsonl: str
    points_file_csv: str
    events_file: str
    point_count: int
    device: Dict[str, Any]
    client: Dict[str, Any]
    sampling: Dict[str, Any]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class RawPoint:
    session_id: str
    point_seq: int
    client_timestamp_ms: Optional[int]
    client_iso_time: Optional[str]
    client_local_time: Optional[str]
    server_received_at: str
    latitude: float
    longitude: float
    accuracy_m: Optional[float]
    altitude_m: Optional[float]
    altitude_accuracy_m: Optional[float]
    heading_deg: Optional[float]
    speed_mps: Optional[float]
    speed_kmh: Optional[float]
    battery_level: Optional[int]
    is_screen_visible: Optional[bool]
    sample_source: Optional[str]
    raw_position_timestamp_ms: Optional[int]
    user_agent: Optional[str]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
PY

echo "[6/8] Создание app/storage.py..."
cat > "$APP_DIR/app/storage.py" <<'PY'
from __future__ import annotations
import csv
import json
from pathlib import Path
from typing import Dict, Any, Iterable


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def append_jsonl(path: Path, payload: Dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False) + "\n")


def append_csv_row(path: Path, header: Iterable[str], row_map: Dict[str, Any]) -> None:
    file_exists = path.exists()
    with path.open("a", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        if not file_exists:
            writer.writerow(list(header))
        writer.writerow([row_map.get(col, "") for col in header])


def append_text_line(path: Path, line: str) -> None:
    with path.open("a", encoding="utf-8") as f:
        f.write(line.rstrip("\n") + "\n")
PY

echo "[7/8] Создание app/session_manager.py..."
cat > "$APP_DIR/app/session_manager.py" <<'PY'
from __future__ import annotations
import random
import string
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

from app.config import (
    CSV_HEADER,
    SESSIONS_DIR,
    SESSIONS_INDEX_FILE,
    TIMEZONE_NAME,
)
from app.models import SessionMeta, RawPoint
from app.storage import (
    ensure_dir,
    write_json,
    read_json,
    append_jsonl,
    append_csv_row,
    append_text_line,
)

try:
    from zoneinfo import ZoneInfo
except ImportError:
    ZoneInfo = None  # type: ignore


def _now() -> datetime:
    if ZoneInfo is not None:
        return datetime.now(ZoneInfo(TIMEZONE_NAME))
    return datetime.now()


def _now_iso() -> str:
    return _now().isoformat(timespec="seconds")


def _today_dir() -> str:
    return _now().strftime("%Y-%m-%d")


def _rand4() -> str:
    chars = string.ascii_lowercase + string.digits
    return "".join(random.choice(chars) for _ in range(4))


def generate_session_id() -> str:
    return f"gps-{_now().strftime('%Y%m%d-%H%M%S')}-{_rand4()}"


def session_dir(session_id: str, session_date: Optional[str] = None) -> Path:
    date_part = session_date or _today_dir()
    return SESSIONS_DIR / date_part / session_id


def session_meta_path(session_id: str, session_date: Optional[str] = None) -> Path:
    return session_dir(session_id, session_date) / "meta.json"


def session_jsonl_path(session_id: str, session_date: Optional[str] = None) -> Path:
    return session_dir(session_id, session_date) / "points.jsonl"


def session_csv_path(session_id: str, session_date: Optional[str] = None) -> Path:
    return session_dir(session_id, session_date) / "points.csv"


def session_events_path(session_id: str, session_date: Optional[str] = None) -> Path:
    return session_dir(session_id, session_date) / "events.log"


def _manifest_append(meta: SessionMeta) -> None:
    ensure_dir(SESSIONS_INDEX_FILE.parent)
    append_jsonl(SESSIONS_INDEX_FILE, meta.to_dict())


def create_session(payload: Dict[str, Any]) -> Dict[str, Any]:
    sid = generate_session_id()
    session_date = _today_dir()
    sdir = session_dir(sid, session_date)
    ensure_dir(sdir)

    meta = SessionMeta(
        session_id=sid,
        created_at=_now_iso(),
        closed_at=None,
        status="active",
        session_date=session_date,
        points_file_jsonl=str(session_jsonl_path(sid, session_date)),
        points_file_csv=str(session_csv_path(sid, session_date)),
        events_file=str(session_events_path(sid, session_date)),
        point_count=0,
        device={
            "user_agent": payload.get("userAgent"),
            "platform_hint": payload.get("platformHint", "android"),
        },
        client={
            "timezone": payload.get("timezone", TIMEZONE_NAME),
            "language": payload.get("language", "ru-RU"),
        },
        sampling={
            "enable_high_accuracy": bool(payload.get("enableHighAccuracy", True)),
            "maximum_age_ms": int(payload.get("maximumAgeMs", 0)),
            "timeout_ms": int(payload.get("timeoutMs", 10000)),
        },
    )

    write_json(session_meta_path(sid, session_date), meta.to_dict())
    append_text_line(session_events_path(sid, session_date), f"{_now_iso()} session_started {sid}")
    _manifest_append(meta)
    return meta.to_dict()


def load_session_meta(session_id: str, session_date: Optional[str] = None) -> Dict[str, Any]:
    path = session_meta_path(session_id, session_date)
    if not path.exists():
        raise FileNotFoundError(f"Session meta not found for {session_id}")
    return read_json(path)


def save_session_meta(meta: Dict[str, Any]) -> None:
    sdir = Path(meta["points_file_jsonl"]).parent
    ensure_dir(sdir)
    write_json(sdir / "meta.json", meta)


def _coerce_float(value: Any) -> Optional[float]:
    if value in (None, "", "null"):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _coerce_int(value: Any) -> Optional[int]:
    if value in (None, "", "null"):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _coerce_bool(value: Any) -> Optional[bool]:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        low = value.strip().lower()
        if low in ("true", "1", "yes", "y", "on"):
            return True
        if low in ("false", "0", "no", "n", "off"):
            return False
    return None


def append_point(session_id: str, payload: Dict[str, Any]) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    meta = load_session_meta(session_id)
    if meta["status"] not in ("active", "interrupted"):
        raise ValueError(f"Session {session_id} is not active")

    lat = _coerce_float(payload.get("latitude"))
    lon = _coerce_float(payload.get("longitude"))

    if lat is None or lon is None:
        raise ValueError("latitude/longitude required")
    if not (-90.0 <= lat <= 90.0):
        raise ValueError("latitude out of range")
    if not (-180.0 <= lon <= 180.0):
        raise ValueError("longitude out of range")

    point_seq = int(meta.get("point_count", 0)) + 1

    point = RawPoint(
        session_id=session_id,
        point_seq=point_seq,
        client_timestamp_ms=_coerce_int(payload.get("clientTimestampMs") or payload.get("timestampMs")),
        client_iso_time=payload.get("clientIsoTime") or payload.get("isoTime"),
        client_local_time=payload.get("clientLocalTime") or payload.get("localTime"),
        server_received_at=_now_iso(),
        latitude=lat,
        longitude=lon,
        accuracy_m=_coerce_float(payload.get("accuracyM") or payload.get("accuracy")),
        altitude_m=_coerce_float(payload.get("altitudeM") or payload.get("altitude")),
        altitude_accuracy_m=_coerce_float(payload.get("altitudeAccuracyM") or payload.get("altitudeAccuracy")),
        heading_deg=_coerce_float(payload.get("headingDeg") or payload.get("heading")),
        speed_mps=_coerce_float(payload.get("speedMps")),
        speed_kmh=_coerce_float(payload.get("speedKmh")),
        battery_level=_coerce_int(payload.get("batteryLevel")),
        is_screen_visible=_coerce_bool(payload.get("isScreenVisible")),
        sample_source=payload.get("sampleSource") or "browser_geolocation",
        raw_position_timestamp_ms=_coerce_int(payload.get("rawPositionTimestampMs") or payload.get("positionTimestampMs")),
        user_agent=payload.get("userAgent"),
    )

    jsonl_path = Path(meta["points_file_jsonl"])
    csv_path = Path(meta["points_file_csv"])
    events_path = Path(meta["events_file"])

    append_jsonl(jsonl_path, point.to_dict())
    append_csv_row(csv_path, CSV_HEADER, point.to_dict())
    append_text_line(events_path, f"{_now_iso()} point_appended seq={point_seq}")

    meta["point_count"] = point_seq
    save_session_meta(meta)
    return meta, point.to_dict()


def stop_session(session_id: str) -> Dict[str, Any]:
    meta = load_session_meta(session_id)
    if meta["status"] == "closed":
        return meta

    meta["status"] = "closed"
    meta["closed_at"] = _now_iso()
    save_session_meta(meta)
    append_text_line(Path(meta["events_file"]), f"{_now_iso()} session_closed {session_id}")
    return meta


def mark_interrupted_sessions() -> int:
    changed = 0
    if not SESSIONS_DIR.exists():
        return 0

    for meta_path in SESSIONS_DIR.glob("*/*/meta.json"):
        try:
            meta = read_json(meta_path)
        except Exception:
            continue

        if meta.get("status") == "active":
            meta["status"] = "interrupted"
            write_json(meta_path, meta)
            append_text_line(meta_path.parent / "events.log", f"{_now_iso()} session_interrupted {meta.get('session_id')}")
            changed += 1

    return changed
PY

echo "[8/8] Создание app/server.py..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_TEMPLATE="$SCRIPT_DIR/app/server.py"
if [ ! -f "$SERVER_TEMPLATE" ]; then
  echo "[ERR] Не найден source-of-truth: $SERVER_TEMPLATE"
  exit 1
fi
cp "$SERVER_TEMPLATE" "$APP_DIR/app/server.py"

if ! grep -q "append_point_comment" "$APP_DIR/app/server.py"; then
  echo "[ERR] app/server.py не содержит append_point_comment"
  exit 1
fi
if ! grep -q '@app.post("/api/point-comment")' "$APP_DIR/app/server.py"; then
  echo "[ERR] app/server.py не содержит route /api/point-comment"
  exit 1
fi

echo "[9/8] Создание web/gps_logger.html..."
cat > "$APP_DIR/web/gps_logger.html" <<'HTML'
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>GPS Raw Logger</title>
  <style>
    :root {
      --bg:#0f1115;
      --panel:#171a21;
      --panel2:#1d2330;
      --text:#e8edf2;
      --muted:#96a0ad;
      --ok:#2ecc71;
      --warn:#f39c12;
      --bad:#e74c3c;
      --btn:#2b3445;
      --btn-hover:#35425a;
      --border:#2c3442;
      --primary:#1f6feb;
      --primary-hover:#2a7fff;
    }
    * { box-sizing:border-box; }
    body {
      margin:0;
      background:var(--bg);
      color:var(--text);
      font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
      line-height:1.4;
    }
    .wrap {
      max-width:1080px;
      margin:0 auto;
      padding:16px;
    }
    h1 { margin:0 0 12px; font-size:24px; }
    .sub { color:var(--muted); margin-bottom:16px; font-size:14px; }
    .panel {
      background:var(--panel);
      border:1px solid var(--border);
      border-radius:14px;
      padding:14px;
      margin-bottom:14px;
    }
    .controls {
      display:flex;
      flex-wrap:wrap;
      gap:10px;
      margin-bottom:14px;
    }
    button, a.btn {
      border:0;
      border-radius:12px;
      padding:12px 14px;
      background:var(--btn);
      color:var(--text);
      font-size:15px;
      cursor:pointer;
      min-height:46px;
      text-decoration:none;
      display:inline-flex;
      align-items:center;
      justify-content:center;
    }
    button:hover, a.btn:hover { background:var(--btn-hover); }
    .primary { background:var(--primary) !important; }
    .primary:hover { background:var(--primary-hover) !important; }
    .good { background:#1f8f50 !important; }
    .good:hover { background:#23a55b !important; }
    .warn { background:#b9770e !important; }
    .warn:hover { background:#d48d0f !important; }
    .bad { background:#b03a2e !important; }
    .bad:hover { background:#cb4335 !important; }

    .grid {
      display:grid;
      grid-template-columns:repeat(2,minmax(0,1fr));
      gap:10px;
    }
    @media (max-width:760px) {
      .grid { grid-template-columns:1fr; }
    }

    .kv {
      background:var(--panel2);
      border-radius:12px;
      padding:10px 12px;
      border:1px solid var(--border);
    }
    .kv .k {
      color:var(--muted);
      font-size:12px;
      margin-bottom:4px;
    }
    .kv .v {
      font-size:15px;
      word-break:break-word;
    }

    .status-ok { color:var(--ok); }
    .status-warn { color:var(--warn); }
    .status-bad { color:var(--bad); }

    .logbox {
      background:#0b0d11;
      border:1px solid var(--border);
      border-radius:12px;
      padding:10px;
      max-height:360px;
      overflow:auto;
      font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
      font-size:12px;
      white-space:pre-wrap;
    }

    .small { color:var(--muted); font-size:12px; }
    .mono { font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>GPS Raw Logger</h1>
    <div class="sub">
      RAW-режим: пишем максимально сырые точки по сессиям. Ничего не объединяем, ничего не фильтруем по дистанции и accuracy.
    </div>

    <div class="panel">
      <div class="controls">
        <button class="primary" id="startBtn">Старт сессии</button>
        <button class="warn" id="stopBtn">Стоп сессии</button>
        <a class="btn good" id="exportBtn" href="#" target="_blank">Экспорт сессии</a>
      </div>

      <div class="grid">
        <div class="kv"><div class="k">Статус</div><div class="v" id="status">Ожидание</div></div>
        <div class="kv"><div class="k">Session ID</div><div class="v mono" id="sessionId">—</div></div>
        <div class="kv"><div class="k">Отправлено точек</div><div class="v" id="sentCount">0</div></div>
        <div class="kv"><div class="k">Последнее client time</div><div class="v" id="lastClientTime">—</div></div>
        <div class="kv"><div class="k">Последнее server time</div><div class="v" id="lastServerTime">—</div></div>
        <div class="kv"><div class="k">Последняя координата</div><div class="v mono" id="lastCoord">—</div></div>
        <div class="kv"><div class="k">Accuracy / Speed / Heading</div><div class="v" id="lastQuality">—</div></div>
        <div class="kv"><div class="k">Raw position timestamp</div><div class="v mono" id="lastRawTimestamp">—</div></div>
      </div>
    </div>

    <div class="panel">
      <div class="small" style="margin-bottom:8px;">
        Последние события:
      </div>
      <div class="logbox" id="logView">Пока пусто.</div>
    </div>
  </div>

  <script>
    let watchId = null;
    let sessionId = null;
    let sentCount = 0;
    let wakeLock = null;

    const els = {
      status: document.getElementById("status"),
      sessionId: document.getElementById("sessionId"),
      sentCount: document.getElementById("sentCount"),
      lastClientTime: document.getElementById("lastClientTime"),
      lastServerTime: document.getElementById("lastServerTime"),
      lastCoord: document.getElementById("lastCoord"),
      lastQuality: document.getElementById("lastQuality"),
      lastRawTimestamp: document.getElementById("lastRawTimestamp"),
      logView: document.getElementById("logView"),
      startBtn: document.getElementById("startBtn"),
      stopBtn: document.getElementById("stopBtn"),
      exportBtn: document.getElementById("exportBtn"),
    };

    function setStatus(text, type="ok") {
      const cls = type === "ok" ? "status-ok" : type === "warn" ? "status-warn" : "status-bad";
      els.status.className = cls;
      els.status.textContent = text;
    }

    function logLine(text) {
      const lines = els.logView.textContent ? els.logView.textContent.split("\n") : [];
      lines.unshift(text);
      els.logView.textContent = lines.slice(0, 120).join("\n");
    }

    function formatLocal(ms) {
      return new Date(ms).toLocaleString("ru-RU", {
        year:"numeric",
        month:"2-digit",
        day:"2-digit",
        hour:"2-digit",
        minute:"2-digit",
        second:"2-digit"
      });
    }

    async function getBatteryLevel() {
      try {
        if (!navigator.getBattery) return null;
        const battery = await navigator.getBattery();
        return Math.round(battery.level * 100);
      } catch {
        return null;
      }
    }

    async function requestWakeLock() {
      try {
        if ("wakeLock" in navigator) {
          wakeLock = await navigator.wakeLock.request("screen");
        }
      } catch {}
    }

    function releaseWakeLock() {
      if (wakeLock && wakeLock.release) {
        wakeLock.release().catch(() => {});
        wakeLock = null;
      }
    }

    async function startSession() {
      if (sessionId) {
        setStatus("Сессия уже активна", "warn");
        return;
      }

      const payload = {
        userAgent: navigator.userAgent,
        platformHint: "android",
        timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || "unknown",
        language: navigator.language || "unknown",
        enableHighAccuracy: true,
        maximumAgeMs: 0,
        timeoutMs: 10000
      };

      const res = await fetch("/api/session/start", {
        method: "POST",
        headers: {"Content-Type":"application/json"},
        body: JSON.stringify(payload),
      });

      const data = await res.json();
      if (!res.ok || !data.ok) {
        throw new Error(data.error || `HTTP ${res.status}`);
      }

      sessionId = data.session.session_id;
      sentCount = 0;
      els.sessionId.textContent = sessionId;
      els.sentCount.textContent = "0";
      els.exportBtn.href = `/api/export/session/${sessionId}.tar.gz`;

      setStatus("Сессия создана, запускаю GPS...", "ok");
      logLine(`[SESSION START] ${sessionId}`);

      if (!navigator.geolocation) {
        throw new Error("Geolocation не поддерживается");
      }

      await requestWakeLock();

      watchId = navigator.geolocation.watchPosition(
        onPosition,
        onPositionError,
        {
          enableHighAccuracy: true,
          maximumAge: 0,
          timeout: 10000
        }
      );
    }

    async function stopSession() {
      if (!sessionId) {
        setStatus("Нет активной сессии", "warn");
        return;
      }

      if (watchId != null) {
        navigator.geolocation.clearWatch(watchId);
        watchId = null;
      }
      releaseWakeLock();

      const currentSessionId = sessionId;
      const res = await fetch("/api/session/stop", {
        method: "POST",
        headers: {"Content-Type":"application/json"},
        body: JSON.stringify({ sessionId: currentSessionId }),
      });

      const data = await res.json();
      if (!res.ok || !data.ok) {
        throw new Error(data.error || `HTTP ${res.status}`);
      }

      logLine(`[SESSION STOP] ${currentSessionId}`);
      setStatus("Сессия остановлена", "warn");
      sessionId = null;
      els.sessionId.textContent = "—";
    }

    async function onPosition(pos) {
      if (!sessionId) return;

      try {
        const now = Date.now();
        const coords = pos.coords;
        const batteryLevel = await getBatteryLevel();

        const payload = {
          sessionId,
          clientTimestampMs: now,
          clientIsoTime: new Date(now).toISOString(),
          clientLocalTime: formatLocal(now),
          latitude: coords.latitude,
          longitude: coords.longitude,
          accuracyM: coords.accuracy ?? null,
          altitudeM: coords.altitude ?? null,
          altitudeAccuracyM: coords.altitudeAccuracy ?? null,
          headingDeg: coords.heading ?? null,
          speedMps: coords.speed ?? null,
          speedKmh: coords.speed != null ? +(coords.speed * 3.6).toFixed(3) : null,
          batteryLevel,
          isScreenVisible: document.visibilityState === "visible",
          sampleSource: "browser_geolocation",
          rawPositionTimestampMs: typeof pos.timestamp === "number" ? Math.round(pos.timestamp) : null,
          userAgent: navigator.userAgent
        };

        const res = await fetch("/api/point", {
          method: "POST",
          headers: {"Content-Type":"application/json"},
          body: JSON.stringify(payload),
        });

        const data = await res.json();
        if (!res.ok || !data.ok) {
          throw new Error(data.error || `HTTP ${res.status}`);
        }

        sentCount = data.pointCount ?? (sentCount + 1);
        els.sentCount.textContent = String(sentCount);
        els.lastClientTime.textContent = `${payload.clientLocalTime} | ${payload.clientIsoTime}`;
        els.lastServerTime.textContent = new Date().toISOString();
        els.lastCoord.textContent = `${Number(payload.latitude).toFixed(6)}, ${Number(payload.longitude).toFixed(6)}`;
        els.lastQuality.textContent =
          `acc=${payload.accuracyM ?? "—"}м | speed=${payload.speedMps ?? "—"} м/с | heading=${payload.headingDeg ?? "—"}°`;
        els.lastRawTimestamp.textContent = String(payload.rawPositionTimestampMs ?? "—");

        setStatus("RAW точка сохранена", "ok");
        logLine(
          `[POINT ${data.pointSeq}] ${payload.clientLocalTime} | ` +
          `${Number(payload.latitude).toFixed(6)}, ${Number(payload.longitude).toFixed(6)} | ` +
          `acc=${payload.accuracyM ?? "—"} | speed=${payload.speedMps ?? "—"} | heading=${payload.headingDeg ?? "—"}`
        );
      } catch (e) {
        setStatus(`Ошибка отправки точки: ${e.message}`, "bad");
        logLine(`[ERR] ${new Date().toLocaleTimeString("ru-RU")} | ${e.message}`);
      }
    }

    function onPositionError(err) {
      setStatus(`GPS ошибка: ${err.code} ${err.message}`, "bad");
      logLine(`[GPS ERR] ${err.code} ${err.message}`);
    }

    document.addEventListener("visibilitychange", async () => {
      if (document.visibilityState === "visible" && watchId != null) {
        await requestWakeLock();
      }
    });

    window.addEventListener("beforeunload", async () => {
      if (!sessionId) return;
      try {
        navigator.sendBeacon(
          "/api/session/stop",
          new Blob([JSON.stringify({ sessionId })], { type: "application/json" })
        );
      } catch {}
    });

    els.startBtn.addEventListener("click", () => {
      startSession().catch((e) => {
        setStatus(`Ошибка старта: ${e.message}`, "bad");
        logLine(`[START ERR] ${e.message}`);
      });
    });

    els.stopBtn.addEventListener("click", () => {
      stopSession().catch((e) => {
        setStatus(`Ошибка остановки: ${e.message}`, "bad");
        logLine(`[STOP ERR] ${e.message}`);
      });
    });
  </script>
</body>
</html>
HTML

echo "[10/8] Создание scripts/start_gps_logger.sh..."
cat > "$APP_DIR/scripts/start_gps_logger.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="$HOME/gps-logger"
PID_FILE="$APP_DIR/run/gps_logger.pid"
LOG_FILE="$APP_DIR/run/server.log"

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
  if lsof -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[ERR] Порт 8080 уже занят"
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
  echo "[OK] URL: http://127.0.0.1:8080"
  echo "[OK] LOG: $LOG_FILE"
else
  echo "[ERR] Не удалось запустить сервер"
  echo "----- server.log -----"
  cat "$LOG_FILE" || true
  exit 1
fi
SH
chmod +x "$APP_DIR/scripts/start_gps_logger.sh"

echo "[11/8] Создание scripts/stop_gps_logger.sh..."
cat > "$APP_DIR/scripts/stop_gps_logger.sh" <<'SH'
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
SH
chmod +x "$APP_DIR/scripts/stop_gps_logger.sh"

echo "[12/8] Создание scripts/healthcheck.sh..."
cat > "$APP_DIR/scripts/healthcheck.sh" <<'SH'
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

echo "[4] POST /api/point-comment route"
POINT_COMMENT_STATUS="$(curl -sS -o /tmp/gps_logger_point_comment_smoke.json -w "%{http_code}" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "http://127.0.0.1:8080/api/point-comment")"

if [ "$POINT_COMMENT_STATUS" = "404" ]; then
  echo "  [ERR] route not found: /api/point-comment"
  cat /tmp/gps_logger_point_comment_smoke.json || true
  exit 1
fi
if [ "$POINT_COMMENT_STATUS" = "000" ]; then
  echo "  [ERR] request failed: /api/point-comment"
  exit 1
fi
echo "  [OK] route available, status=$POINT_COMMENT_STATUS"
SH
chmod +x "$APP_DIR/scripts/healthcheck.sh"

echo "[13/8] Создание scripts/list_sessions.sh..."
cat > "$APP_DIR/scripts/list_sessions.sh" <<'SH'
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
SH
chmod +x "$APP_DIR/scripts/list_sessions.sh"

echo "[14/8] Создание scripts/tail_session.sh..."
cat > "$APP_DIR/scripts/tail_session.sh" <<'SH'
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
SH
chmod +x "$APP_DIR/scripts/tail_session.sh"

echo "[15/8] Создание scripts/export_session.sh..."
cat > "$APP_DIR/scripts/export_session.sh" <<'SH'
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
SH
chmod +x "$APP_DIR/scripts/export_session.sh"

echo "[16/8] Создание scripts/bootstrap_gps_logger.sh..."
cat > "$APP_DIR/scripts/bootstrap_gps_logger.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
echo "Проект уже развернут в $HOME/gps-logger"
echo "Запуск: $HOME/gps-logger/scripts/start_gps_logger.sh"
SH
chmod +x "$APP_DIR/scripts/bootstrap_gps_logger.sh"

echo "[17/8] Создание README.txt..."
cat > "$APP_DIR/README.txt" <<'TXT'
GPS LOGGER RAW MODE

Запуск:
  ~/gps-logger/scripts/start_gps_logger.sh

Остановка:
  ~/gps-logger/scripts/stop_gps_logger.sh

Проверка:
  ~/gps-logger/scripts/healthcheck.sh

Список сессий:
  ~/gps-logger/scripts/list_sessions.sh

Tail по сессии:
  ~/gps-logger/scripts/tail_session.sh <session_id>

Экспорт сессии:
  ~/gps-logger/scripts/export_session.sh <session_id>

Открыть в браузере:
  http://127.0.0.1:8080
TXT

echo
echo "[DONE] Готово."
echo "Проект установлен в: $APP_DIR"
echo
echo "Дальше выполняй:"
echo "  chmod +x ~/bootstrap_gps_logger.sh"
echo "  ~/bootstrap_gps_logger.sh"
echo
echo "Потом:"
echo "  ~/gps-logger/scripts/start_gps_logger.sh"
echo "  ~/gps-logger/scripts/healthcheck.sh"
echo "  Открой в браузере: http://127.0.0.1:8080"
