#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_DIR="$HOME/gps-logger"

if [ ! -d "$APP_DIR/app" ] || [ ! -d "$APP_DIR/web" ]; then
  echo "[ERR] Не найден проект $APP_DIR"
  exit 1
fi

echo "[1/5] Обновляю app/config.py ..."
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
TIMEZONE_NAME = "UTC"

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

SENSOR_CSV_HEADER = [
    "session_id",
    "event_seq",
    "event_type",
    "client_timestamp_ms",
    "client_iso_time",
    "client_local_time",
    "server_received_at",
    "value_x",
    "value_y",
    "value_z",
    "alpha",
    "beta",
    "gamma",
    "heading_deg",
    "battery_level",
    "is_charging",
    "is_screen_visible",
    "sample_source",
    "user_agent",
]
PY

echo "[2/5] Обновляю app/models.py ..."
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
    sensor_events_file_jsonl: str
    sensor_events_file_csv: str
    events_file: str
    point_count: int
    sensor_event_count: int
    sensor_streams: Dict[str, Any]
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


@dataclass
class SensorEvent:
    session_id: str
    event_seq: int
    event_type: str
    client_timestamp_ms: Optional[int]
    client_iso_time: Optional[str]
    client_local_time: Optional[str]
    server_received_at: str
    value_x: Optional[float]
    value_y: Optional[float]
    value_z: Optional[float]
    alpha: Optional[float]
    beta: Optional[float]
    gamma: Optional[float]
    heading_deg: Optional[float]
    battery_level: Optional[int]
    is_charging: Optional[bool]
    is_screen_visible: Optional[bool]
    sample_source: Optional[str]
    user_agent: Optional[str]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
PY

echo "[3/5] Обновляю app/session_manager.py ..."
cat > "$APP_DIR/app/session_manager.py" <<'PY'
from __future__ import annotations
import random
import string
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

from app.config import (
    CSV_HEADER,
    SENSOR_CSV_HEADER,
    SESSIONS_DIR,
    SESSIONS_INDEX_FILE,
    TIMEZONE_NAME,
)
from app.models import SessionMeta, RawPoint, SensorEvent
from app.storage import (
    ensure_dir,
    write_json,
    read_json,
    append_jsonl,
    append_csv_row,
    append_text_line,
)


def _now() -> datetime:
    return datetime.utcnow()


def _now_iso() -> str:
    return _now().isoformat(timespec="seconds") + "Z"


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


def session_sensor_jsonl_path(session_id: str, session_date: Optional[str] = None) -> Path:
    return session_dir(session_id, session_date) / "sensor_events.jsonl"


def session_sensor_csv_path(session_id: str, session_date: Optional[str] = None) -> Path:
    return session_dir(session_id, session_date) / "sensor_events.csv"


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
        sensor_events_file_jsonl=str(session_sensor_jsonl_path(sid, session_date)),
        sensor_events_file_csv=str(session_sensor_csv_path(sid, session_date)),
        events_file=str(session_events_path(sid, session_date)),
        point_count=0,
        sensor_event_count=0,
        sensor_streams={
            "accelerometer": False,
            "gyroscope": False,
            "orientation": False,
            "visibility_change": False,
            "battery_status": False,
        },
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
            "sensor_throttle_ms": int(payload.get("sensorThrottleMs", 200)),
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


def append_sensor_event(session_id: str, payload: Dict[str, Any]) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    meta = load_session_meta(session_id)
    if meta["status"] not in ("active", "interrupted"):
        raise ValueError(f"Session {session_id} is not active")

    event_type = (payload.get("eventType") or "").strip()
    if not event_type:
        raise ValueError("eventType required")

    event_seq = int(meta.get("sensor_event_count", 0)) + 1

    event = SensorEvent(
        session_id=session_id,
        event_seq=event_seq,
        event_type=event_type,
        client_timestamp_ms=_coerce_int(payload.get("clientTimestampMs") or payload.get("timestampMs")),
        client_iso_time=payload.get("clientIsoTime") or payload.get("isoTime"),
        client_local_time=payload.get("clientLocalTime") or payload.get("localTime"),
        server_received_at=_now_iso(),
        value_x=_coerce_float(payload.get("valueX")),
        value_y=_coerce_float(payload.get("valueY")),
        value_z=_coerce_float(payload.get("valueZ")),
        alpha=_coerce_float(payload.get("alpha")),
        beta=_coerce_float(payload.get("beta")),
        gamma=_coerce_float(payload.get("gamma")),
        heading_deg=_coerce_float(payload.get("headingDeg") or payload.get("heading")),
        battery_level=_coerce_int(payload.get("batteryLevel")),
        is_charging=_coerce_bool(payload.get("isCharging")),
        is_screen_visible=_coerce_bool(payload.get("isScreenVisible")),
        sample_source=payload.get("sampleSource") or "browser_sensor",
        user_agent=payload.get("userAgent"),
    )

    jsonl_path = Path(meta["sensor_events_file_jsonl"])
    csv_path = Path(meta["sensor_events_file_csv"])
    events_path = Path(meta["events_file"])

    append_jsonl(jsonl_path, event.to_dict())
    append_csv_row(csv_path, SENSOR_CSV_HEADER, event.to_dict())
    append_text_line(events_path, f"{_now_iso()} sensor_event_appended seq={event_seq} type={event_type}")

    meta["sensor_event_count"] = event_seq
    streams = meta.get("sensor_streams") or {}
    if event_type in streams:
        streams[event_type] = True
    meta["sensor_streams"] = streams

    save_session_meta(meta)
    return meta, event.to_dict()


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

echo "[4/5] Обновляю app/server.py ..."
cat > "$APP_DIR/app/server.py" <<'PY'
from __future__ import annotations
import io
import json
import tarfile
from pathlib import Path

from flask import Flask, jsonify, request, send_file, Response

from app.config import (
    EXPORTS_DIR,
    HOST,
    PORT,
    RUN_DIR,
    SESSIONS_DIR,
    TIMEZONE_NAME,
)
from app.session_manager import (
    append_point,
    append_sensor_event,
    create_session,
    load_session_meta,
    mark_interrupted_sessions,
    stop_session,
)

app = Flask(__name__, static_folder=None, template_folder=None)


@app.get("/")
def index() -> Response:
    html_path = Path(__file__).resolve().parent.parent / "web" / "gps_logger.html"
    return Response(html_path.read_text(encoding="utf-8"), mimetype="text/html")


@app.get("/health")
def health():
    return jsonify({
        "ok": True,
        "host": HOST,
        "port": PORT,
        "timezone": TIMEZONE_NAME,
        "run_dir": str(RUN_DIR),
        "sessions_dir": str(SESSIONS_DIR),
    })


@app.post("/api/session/start")
def api_session_start():
    payload = request.get_json(silent=True) or {}
    meta = create_session(payload)
    return jsonify({"ok": True, "session": meta})


@app.post("/api/session/stop")
def api_session_stop():
    payload = request.get_json(silent=True) or {}
    session_id = payload.get("sessionId")
    if not session_id:
        return jsonify({"ok": False, "error": "sessionId required"}), 400

    meta = stop_session(session_id)
    return jsonify({"ok": True, "session": meta})


@app.post("/api/point")
def api_point():
    payload = request.get_json(silent=True) or {}
    session_id = payload.get("sessionId")
    if not session_id:
        return jsonify({"ok": False, "error": "sessionId required"}), 400

    try:
        meta, point = append_point(session_id, payload)
        return jsonify({
            "ok": True,
            "sessionId": session_id,
            "pointSeq": point["point_seq"],
            "pointCount": meta["point_count"],
        })
    except FileNotFoundError as e:
        return jsonify({"ok": False, "error": str(e)}), 404
    except ValueError as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.post("/api/sensor-event")
def api_sensor_event():
    payload = request.get_json(silent=True) or {}
    session_id = payload.get("sessionId")
    if not session_id:
        return jsonify({"ok": False, "error": "sessionId required"}), 400

    try:
        meta, event = append_sensor_event(session_id, payload)
        return jsonify({
            "ok": True,
            "sessionId": session_id,
            "eventSeq": event["event_seq"],
            "sensorEventCount": meta["sensor_event_count"],
            "eventType": event["event_type"],
        })
    except FileNotFoundError as e:
        return jsonify({"ok": False, "error": str(e)}), 404
    except ValueError as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.get("/api/session/<session_id>")
def api_session_meta(session_id: str):
    try:
        meta = load_session_meta(session_id)
        return jsonify({"ok": True, "session": meta})
    except FileNotFoundError as e:
        return jsonify({"ok": False, "error": str(e)}), 404


@app.get("/api/sessions")
def api_sessions():
    items = []
    if SESSIONS_DIR.exists():
        for meta_path in sorted(SESSIONS_DIR.glob("*/*/meta.json")):
            try:
                payload = json.loads(meta_path.read_text(encoding="utf-8"))
                items.append(payload)
            except Exception:
                continue
    items.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    return jsonify({"ok": True, "sessions": items})


@app.get("/api/export/session/<session_id>.tar.gz")
def api_export_session(session_id: str):
    target_dir = None
    for candidate in SESSIONS_DIR.glob(f"*/*"):
        if candidate.is_dir() and candidate.name == session_id:
            target_dir = candidate
            break

    if target_dir is None:
        return jsonify({"ok": False, "error": "session not found"}), 404

    EXPORTS_DIR.mkdir(parents=True, exist_ok=True)
    memory_file = io.BytesIO()

    with tarfile.open(fileobj=memory_file, mode="w:gz") as tar:
        for child in target_dir.iterdir():
            tar.add(child, arcname=f"{session_id}/{child.name}")

    memory_file.seek(0)
    return send_file(
        memory_file,
        mimetype="application/gzip",
        as_attachment=True,
        download_name=f"{session_id}.tar.gz",
    )


if __name__ == "__main__":
    recovered = mark_interrupted_sessions()
    print(f"[gps-logger] recovered_interrupted_sessions={recovered}")
    app.run(host=HOST, port=PORT, debug=False)
PY

echo "[5/5] Обновляю web/gps_logger.html ..."
cat > "$APP_DIR/web/gps_logger.html" <<'HTML'
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>GPS Raw Logger + Sensors</title>
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
    <h1>GPS Raw Logger + Sensors</h1>
    <div class="sub">
      RAW-режим: GPS + sensor events. Пишем сырые точки и сырые датчики без объединения и без фильтрации.
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
        <div class="kv"><div class="k">GPS точек</div><div class="v" id="sentCount">0</div></div>
        <div class="kv"><div class="k">Sensor events</div><div class="v" id="sensorCount">0</div></div>
        <div class="kv"><div class="k">Последнее client time</div><div class="v" id="lastClientTime">—</div></div>
        <div class="kv"><div class="k">Последнее server time</div><div class="v" id="lastServerTime">—</div></div>
        <div class="kv"><div class="k">Последняя координата</div><div class="v mono" id="lastCoord">—</div></div>
        <div class="kv"><div class="k">Accuracy / Speed / Heading</div><div class="v" id="lastQuality">—</div></div>
        <div class="kv"><div class="k">Последний sensor event</div><div class="v" id="lastSensorInfo">—</div></div>
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
    let sensorCount = 0;
    let wakeLock = null;
    let batteryRef = null;

    const SENSOR_THROTTLE_MS = 200;
    let lastAccelAt = 0;
    let lastGyroAt = 0;
    let lastOrientAt = 0;
    let lastBatteryAt = 0;

    const els = {
      status: document.getElementById("status"),
      sessionId: document.getElementById("sessionId"),
      sentCount: document.getElementById("sentCount"),
      sensorCount: document.getElementById("sensorCount"),
      lastClientTime: document.getElementById("lastClientTime"),
      lastServerTime: document.getElementById("lastServerTime"),
      lastCoord: document.getElementById("lastCoord"),
      lastQuality: document.getElementById("lastQuality"),
      lastSensorInfo: document.getElementById("lastSensorInfo"),
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
      els.logView.textContent = lines.slice(0, 150).join("\n");
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
        if (!navigator.getBattery) return { batteryLevel: null, isCharging: null };
        if (!batteryRef) batteryRef = await navigator.getBattery();
        return {
          batteryLevel: Math.round(batteryRef.level * 100),
          isCharging: !!batteryRef.charging
        };
      } catch {
        return { batteryLevel: null, isCharging: null };
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

    async function ensureIOSPermissions() {
      try {
        if (typeof DeviceMotionEvent !== "undefined" && typeof DeviceMotionEvent.requestPermission === "function") {
          const motion = await DeviceMotionEvent.requestPermission();
          logLine(`[PERMISSION] DeviceMotion: ${motion}`);
        }
      } catch (e) {
        logLine(`[PERMISSION WARN] DeviceMotion: ${e.message}`);
      }

      try {
        if (typeof DeviceOrientationEvent !== "undefined" && typeof DeviceOrientationEvent.requestPermission === "function") {
          const orient = await DeviceOrientationEvent.requestPermission();
          logLine(`[PERMISSION] DeviceOrientation: ${orient}`);
        }
      } catch (e) {
        logLine(`[PERMISSION WARN] DeviceOrientation: ${e.message}`);
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
        timeoutMs: 10000,
        sensorThrottleMs: SENSOR_THROTTLE_MS
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
      sensorCount = 0;
      els.sessionId.textContent = sessionId;
      els.sentCount.textContent = "0";
      els.sensorCount.textContent = "0";
      els.exportBtn.href = `/api/export/session/${sessionId}.tar.gz`;

      setStatus("Сессия создана, запускаю GPS и датчики...", "ok");
      logLine(`[SESSION START] ${sessionId}`);

      if (!navigator.geolocation) {
        throw new Error("Geolocation не поддерживается");
      }

      await ensureIOSPermissions();
      await requestWakeLock();

      bindSensorListeners();

      watchId = navigator.geolocation.watchPosition(
        onPosition,
        onPositionError,
        {
          enableHighAccuracy: true,
          maximumAge: 0,
          timeout: 10000
        }
      );

      await emitBatteryStatus("battery_status");
      await emitVisibilityChange();
    }

    async function stopSession() {
      if (!sessionId) {
        setStatus("Нет активной сессии", "warn");
        return;
      }

      unbindSensorListeners();

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

    async function postSensorEvent(payload) {
      if (!sessionId) return;
      const res = await fetch("/api/sensor-event", {
        method: "POST",
        headers: {"Content-Type":"application/json"},
        body: JSON.stringify({
          sessionId,
          clientTimestampMs: payload.clientTimestampMs,
          clientIsoTime: payload.clientIsoTime,
          clientLocalTime: payload.clientLocalTime,
          eventType: payload.eventType,
          valueX: payload.valueX,
          valueY: payload.valueY,
          valueZ: payload.valueZ,
          alpha: payload.alpha,
          beta: payload.beta,
          gamma: payload.gamma,
          headingDeg: payload.headingDeg,
          batteryLevel: payload.batteryLevel,
          isCharging: payload.isCharging,
          isScreenVisible: payload.isScreenVisible,
          sampleSource: payload.sampleSource,
          userAgent: navigator.userAgent
        }),
      });

      const data = await res.json();
      if (!res.ok || !data.ok) {
        throw new Error(data.error || `HTTP ${res.status}`);
      }

      sensorCount = data.sensorEventCount ?? (sensorCount + 1);
      els.sensorCount.textContent = String(sensorCount);
      els.lastSensorInfo.textContent =
        `${payload.eventType} | ` +
        `x=${payload.valueX ?? "—"} y=${payload.valueY ?? "—"} z=${payload.valueZ ?? "—"} ` +
        `a=${payload.alpha ?? "—"} b=${payload.beta ?? "—"} g=${payload.gamma ?? "—"} h=${payload.headingDeg ?? "—"}`;

      logLine(`[SENSOR ${data.eventSeq}] ${payload.eventType} | t=${payload.clientLocalTime}`);
    }

    async function emitSensorEvent(eventType, fields) {
      const now = Date.now();
      const battery = await getBatteryLevel();

      await postSensorEvent({
        eventType,
        clientTimestampMs: now,
        clientIsoTime: new Date(now).toISOString(),
        clientLocalTime: formatLocal(now),
        valueX: fields.valueX ?? null,
        valueY: fields.valueY ?? null,
        valueZ: fields.valueZ ?? null,
        alpha: fields.alpha ?? null,
        beta: fields.beta ?? null,
        gamma: fields.gamma ?? null,
        headingDeg: fields.headingDeg ?? null,
        batteryLevel: battery.batteryLevel,
        isCharging: battery.isCharging,
        isScreenVisible: document.visibilityState === "visible",
        sampleSource: fields.sampleSource ?? "browser_sensor"
      });
    }

    async function emitVisibilityChange() {
      try {
        await emitSensorEvent("visibility_change", {
          sampleSource: "visibilitychange"
        });
      } catch (e) {
        logLine(`[SENSOR ERR] visibility_change | ${e.message}`);
      }
    }

    async function emitBatteryStatus(eventType="battery_status") {
      try {
        const now = Date.now();
        if (now - lastBatteryAt < 1000) return;
        lastBatteryAt = now;

        const battery = await getBatteryLevel();
        await postSensorEvent({
          eventType,
          clientTimestampMs: now,
          clientIsoTime: new Date(now).toISOString(),
          clientLocalTime: formatLocal(now),
          valueX: null,
          valueY: null,
          valueZ: null,
          alpha: null,
          beta: null,
          gamma: null,
          headingDeg: null,
          batteryLevel: battery.batteryLevel,
          isCharging: battery.isCharging,
          isScreenVisible: document.visibilityState === "visible",
          sampleSource: "battery"
        });
      } catch (e) {
        logLine(`[SENSOR ERR] battery_status | ${e.message}`);
      }
    }

    async function onDeviceMotion(ev) {
      if (!sessionId) return;
      const now = Date.now();
      if (now - lastAccelAt >= SENSOR_THROTTLE_MS) {
        lastAccelAt = now;
        try {
          const acc = ev.accelerationIncludingGravity || ev.acceleration || {};
          await emitSensorEvent("accelerometer", {
            valueX: acc.x ?? null,
            valueY: acc.y ?? null,
            valueZ: acc.z ?? null,
            sampleSource: "devicemotion_acceleration"
          });
        } catch (e) {
          logLine(`[SENSOR ERR] accelerometer | ${e.message}`);
        }
      }

      if (now - lastGyroAt >= SENSOR_THROTTLE_MS) {
        lastGyroAt = now;
        try {
          const rr = ev.rotationRate || {};
          await emitSensorEvent("gyroscope", {
            valueX: rr.alpha ?? null,
            valueY: rr.beta ?? null,
            valueZ: rr.gamma ?? null,
            sampleSource: "devicemotion_rotation"
          });
        } catch (e) {
          logLine(`[SENSOR ERR] gyroscope | ${e.message}`);
        }
      }
    }

    async function onDeviceOrientation(ev) {
      if (!sessionId) return;
      const now = Date.now();
      if (now - lastOrientAt < SENSOR_THROTTLE_MS) return;
      lastOrientAt = now;

      try {
        const headingDeg =
          typeof ev.webkitCompassHeading === "number"
            ? ev.webkitCompassHeading
            : null;

        await emitSensorEvent("orientation", {
          alpha: ev.alpha ?? null,
          beta: ev.beta ?? null,
          gamma: ev.gamma ?? null,
          headingDeg,
          sampleSource: "deviceorientation"
        });
      } catch (e) {
        logLine(`[SENSOR ERR] orientation | ${e.message}`);
      }
    }

    function bindSensorListeners() {
      window.addEventListener("devicemotion", onDeviceMotion);
      window.addEventListener("deviceorientation", onDeviceOrientation);
      document.addEventListener("visibilitychange", handleVisibilityChange);

      if (batteryRef) {
        batteryRef.addEventListener?.("chargingchange", handleBatteryChange);
        batteryRef.addEventListener?.("levelchange", handleBatteryChange);
      } else if (navigator.getBattery) {
        navigator.getBattery().then((b) => {
          batteryRef = b;
          batteryRef.addEventListener?.("chargingchange", handleBatteryChange);
          batteryRef.addEventListener?.("levelchange", handleBatteryChange);
        }).catch(() => {});
      }
    }

    function unbindSensorListeners() {
      window.removeEventListener("devicemotion", onDeviceMotion);
      window.removeEventListener("deviceorientation", onDeviceOrientation);
      document.removeEventListener("visibilitychange", handleVisibilityChange);

      if (batteryRef) {
        batteryRef.removeEventListener?.("chargingchange", handleBatteryChange);
        batteryRef.removeEventListener?.("levelchange", handleBatteryChange);
      }
    }

    function handleVisibilityChange() {
      emitVisibilityChange().catch((e) => {
        logLine(`[SENSOR ERR] visibility_change | ${e.message}`);
      });
    }

    function handleBatteryChange() {
      emitBatteryStatus("battery_status").catch((e) => {
        logLine(`[SENSOR ERR] battery_status | ${e.message}`);
      });
    }

    async function onPosition(pos) {
      if (!sessionId) return;

      try {
        const now = Date.now();
        const coords = pos.coords;
        const battery = await getBatteryLevel();

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
          batteryLevel: battery.batteryLevel,
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

        setStatus("RAW GPS точка сохранена", "ok");
        logLine(
          `[POINT ${data.pointSeq}] ${payload.clientLocalTime} | ` +
          `${Number(payload.latitude).toFixed(6)}, ${Number(payload.longitude).toFixed(6)} | ` +
          `acc=${payload.accuracyM ?? "—"} | speed=${payload.speedMps ?? "—"} | heading=${payload.headingDeg ?? "—"}`
        );
      } catch (e) {
        setStatus(`Ошибка отправки GPS точки: ${e.message}`, "bad");
        logLine(`[GPS ERR] ${new Date().toLocaleTimeString("ru-RU")} | ${e.message}`);
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

echo
echo "[DONE] Патч установлен."
echo "Теперь перезапусти сервер:"
echo "  ~/gps-logger/scripts/stop_gps_logger.sh"
echo "  ~/gps-logger/scripts/start_gps_logger.sh"
echo
echo "После этого открой:"
echo "  http://127.0.0.1:8080"
