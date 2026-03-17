from __future__ import annotations
import json
import logging
import math
import random
import string
import threading
from datetime import datetime
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Iterator, Optional, Tuple

from app.config import (
    CSV_HEADER,
    SENSOR_CSV_HEADER,
    SESSIONS_DIR,
    SESSIONS_INDEX_FILE,
    SESSIONS_QUERY_INDEX_FILE,
    TIMEZONE_NAME,
)
from app.models import SessionMeta, RawPoint, SensorEvent
from app.storage import (
    ensure_dir,
    write_json,
    read_json,
    append_jsonl,
    append_text_line,
    rewrite_csv_from_jsonl,
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
    """Append-only audit trail of session snapshots."""
    ensure_dir(SESSIONS_INDEX_FILE.parent)
    append_jsonl(SESSIONS_INDEX_FILE, meta.to_dict())


def _query_index_upsert(meta: Dict[str, Any]) -> None:
    """Upsert query index entry by session_id (JSON map for cheap updates)."""
    ensure_dir(SESSIONS_QUERY_INDEX_FILE.parent)
    index_payload: Dict[str, Dict[str, Any]] = {}
    if SESSIONS_QUERY_INDEX_FILE.exists():
        try:
            current = read_json(SESSIONS_QUERY_INDEX_FILE)
            if isinstance(current, dict):
                index_payload = current
        except Exception:
            index_payload = {}

    session_id = str(meta.get("session_id", "")).strip()
    if not session_id:
        return

    index_payload[session_id] = {
        "session_id": session_id,
        "session_date": meta.get("session_date"),
        "created_at": meta.get("created_at"),
        "closed_at": meta.get("closed_at"),
        "status": meta.get("status"),
        "point_count": int(meta.get("point_count", 0) or 0),
        "sensor_event_count": int(meta.get("sensor_event_count", 0) or 0),
    }
    _write_json_atomic(SESSIONS_QUERY_INDEX_FILE, index_payload)


LOGGER = logging.getLogger(__name__)
_SESSION_LOCKS: Dict[str, threading.Lock] = {}
_SESSION_LOCKS_GUARD = threading.Lock()
_DEFAULT_SENSOR_STREAMS: Dict[str, bool] = {
    "accelerometer": False,
    "gyroscope": False,
    "orientation": False,
    "visibility_change": False,
    "battery_status": False,
}
_META_SCHEMA_VERSION = 2


def _write_json_atomic(path: Path, payload: Dict[str, Any]) -> None:
    """Write JSON payload atomically via temp file + rename."""
    ensure_dir(path.parent)
    tmp_path = path.with_suffix(f"{path.suffix}.tmp")
    tmp_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp_path.replace(path)


def _scan_max_seq(path: Path, seq_field: str) -> Optional[int]:
    if not path.exists():
        return None

    max_seq: Optional[int] = None
    with path.open("r", encoding="utf-8") as file:
        for line in file:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
                seq_value = int(row.get(seq_field))
            except (ValueError, TypeError, AttributeError):
                continue
            if max_seq is None or seq_value > max_seq:
                max_seq = seq_value
    return max_seq


def _warn_seq_anomaly(session_id: str, events_path: Path, seq_kind: str, seq_value: int, known_max: int) -> None:
    message = (
        f"{seq_kind} anomaly for session={session_id}: "
        f"calculated_seq={seq_value} is not unique (known_max={known_max})"
    )
    LOGGER.warning(message)
    append_text_line(events_path, f"{_now_iso()} WARN {message}")


@contextmanager
def _session_lock(session_id: str) -> Iterator[None]:
    with _SESSION_LOCKS_GUARD:
        lock = _SESSION_LOCKS.setdefault(session_id, threading.Lock())
    lock.acquire()
    try:
        yield
    finally:
        lock.release()


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
        csv_materialized=False,
        csv_last_exported_at=None,
        events_file=str(session_events_path(sid, session_date)),
        point_count=0,
        sensor_event_count=0,
        sensor_streams=dict(_DEFAULT_SENSOR_STREAMS),
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
        meta_schema_version=_META_SCHEMA_VERSION,
    )

    write_json(session_meta_path(sid, session_date), meta.to_dict())
    append_text_line(session_events_path(sid, session_date), f"{_now_iso()} session_started {sid}")
    _manifest_append(meta)
    _query_index_upsert(meta.to_dict())
    return meta.to_dict()


def _ensure_storage_model_defaults(meta: Dict[str, Any]) -> bool:
    """Backfill storage-model fields for backward-compatible meta.json payloads."""
    changed = False
    if "csv_materialized" not in meta:
        points_csv_exists = Path(meta.get("points_file_csv", "")).exists()
        sensor_csv_exists = Path(meta.get("sensor_events_file_csv", "")).exists()
        meta["csv_materialized"] = points_csv_exists or sensor_csv_exists
        changed = True
    if "csv_last_exported_at" not in meta:
        meta["csv_last_exported_at"] = None
        changed = True
    return changed


def normalize_meta(meta: Dict[str, Any]) -> bool:
    """Normalize legacy session metadata in-place and report whether any value changed."""
    changed = _ensure_storage_model_defaults(meta)

    session_id = str(meta.get("session_id", "")).strip()
    session_date = str(meta.get("session_date") or _today_dir())

    if not meta.get("sensor_events_file_jsonl") and session_id:
        meta["sensor_events_file_jsonl"] = str(session_sensor_jsonl_path(session_id, session_date))
        changed = True

    if not meta.get("sensor_events_file_csv") and session_id:
        meta["sensor_events_file_csv"] = str(session_sensor_csv_path(session_id, session_date))
        changed = True

    if "sensor_event_count" not in meta:
        meta["sensor_event_count"] = 0
        changed = True

    sensor_streams = meta.get("sensor_streams")
    if not isinstance(sensor_streams, dict):
        meta["sensor_streams"] = dict(_DEFAULT_SENSOR_STREAMS)
        changed = True
    else:
        normalized_streams = dict(_DEFAULT_SENSOR_STREAMS)
        for key in _DEFAULT_SENSOR_STREAMS:
            if key in sensor_streams:
                normalized_streams[key] = bool(sensor_streams[key])
        if normalized_streams != sensor_streams:
            meta["sensor_streams"] = normalized_streams
            changed = True

    if meta.get("meta_schema_version") != _META_SCHEMA_VERSION:
        meta["meta_schema_version"] = _META_SCHEMA_VERSION
        changed = True

    return changed


def load_session_meta(session_id: str, session_date: Optional[str] = None) -> Dict[str, Any]:
    path = session_meta_path(session_id, session_date)
    if path.exists():
        meta = read_json(path)
        if normalize_meta(meta):
            _write_json_atomic(path, meta)
        return meta

    matches = list(SESSIONS_DIR.glob(f"*/{session_id}/meta.json"))
    if len(matches) == 1:
        meta = read_json(matches[0])
        if normalize_meta(meta):
            _write_json_atomic(matches[0], meta)
        return meta

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
    _write_json_atomic(sdir / "meta.json", meta)
    _query_index_upsert(meta)


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


def _has_sensor_signal(*values: Optional[float]) -> bool:
    return any(value is not None and math.isfinite(value) for value in values)


def append_point(session_id: str, payload: Dict[str, Any]) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    lat = _coerce_float(payload.get("latitude"))
    lon = _coerce_float(payload.get("longitude"))

    if lat is None or lon is None:
        raise ValueError("latitude/longitude required")
    if not (-90.0 <= lat <= 90.0):
        raise ValueError("latitude out of range")
    if not (-180.0 <= lon <= 180.0):
        raise ValueError("longitude out of range")

    with _session_lock(session_id):
        meta = load_session_meta(session_id)
        if meta["status"] not in ("active", "interrupted"):
            raise ValueError(f"Session {session_id} is not active")

        jsonl_path = Path(meta["points_file_jsonl"])
        events_path = Path(meta["events_file"])

        point_seq = int(meta.get("point_count", 0)) + 1
        file_max_seq = _scan_max_seq(jsonl_path, "point_seq")
        if file_max_seq is not None and point_seq <= file_max_seq:
            _warn_seq_anomaly(session_id, events_path, "point_seq", point_seq, file_max_seq)
            point_seq = file_max_seq + 1

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

        append_jsonl(jsonl_path, point.to_dict())

        meta["point_count"] = point_seq
        save_session_meta(meta)
        return meta, point.to_dict()


def append_sensor_event(session_id: str, payload: Dict[str, Any]) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    event_type = (payload.get("eventType") or "").strip()
    if not event_type:
        raise ValueError("eventType required")

    with _session_lock(session_id):
        meta = load_session_meta(session_id)
        if meta["status"] not in ("active", "interrupted"):
            raise ValueError(f"Session {session_id} is not active")

        jsonl_path = Path(meta["sensor_events_file_jsonl"])
        events_path = Path(meta["events_file"])

        event_seq = int(meta.get("sensor_event_count", 0)) + 1
        file_max_seq = _scan_max_seq(jsonl_path, "event_seq")
        if file_max_seq is not None and event_seq <= file_max_seq:
            _warn_seq_anomaly(session_id, events_path, "event_seq", event_seq, file_max_seq)
            event_seq = file_max_seq + 1

        value_x = _coerce_float(payload.get("valueX"))
        value_y = _coerce_float(payload.get("valueY"))
        value_z = _coerce_float(payload.get("valueZ"))
        alpha = _coerce_float(payload.get("alpha"))
        beta = _coerce_float(payload.get("beta"))
        gamma = _coerce_float(payload.get("gamma"))
        heading_deg = _coerce_float(payload.get("headingDeg") or payload.get("heading"))
        battery_level = _coerce_int(payload.get("batteryLevel"))
        is_charging = _coerce_bool(payload.get("isCharging"))
        is_screen_visible = _coerce_bool(payload.get("isScreenVisible"))

        if not (
            _has_sensor_signal(value_x, value_y, value_z, alpha, beta, gamma, heading_deg)
            or battery_level is not None
            or is_charging is not None
            or is_screen_visible is not None
        ):
            raise ValueError("sensor payload is empty")

        event = SensorEvent(
            session_id=session_id,
            event_seq=event_seq,
            event_type=event_type,
            client_timestamp_ms=_coerce_int(payload.get("clientTimestampMs") or payload.get("timestampMs")),
            client_iso_time=payload.get("clientIsoTime") or payload.get("isoTime"),
            client_local_time=payload.get("clientLocalTime") or payload.get("localTime"),
            server_received_at=_now_iso(),
            value_x=value_x,
            value_y=value_y,
            value_z=value_z,
            alpha=alpha,
            beta=beta,
            gamma=gamma,
            heading_deg=heading_deg,
            battery_level=battery_level,
            is_charging=is_charging,
            is_screen_visible=is_screen_visible,
            sample_source=payload.get("sampleSource") or "browser_sensor",
            user_agent=payload.get("userAgent"),
        )

        append_jsonl(jsonl_path, event.to_dict())

        meta["sensor_event_count"] = event_seq
        streams = meta.get("sensor_streams") or {}
        if event_type in streams:
            streams[event_type] = True
        meta["sensor_streams"] = streams

        save_session_meta(meta)
        return meta, event.to_dict()


def materialize_session_csv(session_id: str) -> Dict[str, Any]:
    """Build CSV snapshots from JSONL source-of-truth files for a session."""
    with _session_lock(session_id):
        meta = load_session_meta(session_id)

        points_jsonl = Path(meta["points_file_jsonl"])
        points_csv = Path(meta["points_file_csv"])
        sensor_jsonl = Path(meta["sensor_events_file_jsonl"])
        sensor_csv = Path(meta["sensor_events_file_csv"])

        ensure_dir(points_csv.parent)
        points_rows = rewrite_csv_from_jsonl(points_jsonl, points_csv, CSV_HEADER)
        sensor_rows = rewrite_csv_from_jsonl(sensor_jsonl, sensor_csv, SENSOR_CSV_HEADER)

        exported_at = _now_iso()
        meta["csv_materialized"] = True
        meta["csv_last_exported_at"] = exported_at
        save_session_meta(meta)

        append_text_line(
            Path(meta["events_file"]),
            f"{exported_at} csv_materialized points_rows={points_rows} sensor_rows={sensor_rows}",
        )

        return meta


def stop_session(session_id: str) -> Dict[str, Any]:
    with _session_lock(session_id):
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
            _ensure_storage_model_defaults(meta)
            _write_json_atomic(meta_path, meta)
            _query_index_upsert(meta)
            append_text_line(meta_path.parent / "events.log", f"{_now_iso()} session_interrupted {meta.get('session_id')}")
            changed += 1

    return changed
