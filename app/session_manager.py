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
    if path.exists():
        return read_json(path)

    matches = list(SESSIONS_DIR.glob(f"*/{session_id}/meta.json"))
    if len(matches) == 1:
        return read_json(matches[0])

    if len(matches) > 1:
        error_message = (
            f"Session meta consistency error for {session_id}: "
            f"found {len(matches)} meta.json matches"
        )
        for meta_path in matches:
            append_text_line(meta_path.parent / "events.log", f"{_now_iso()} {error_message}")
        raise RuntimeError(error_message)

    raise FileNotFoundError(f"Session meta not found for {session_id}")


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
