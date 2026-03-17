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
SESSIONS_INDEX_FILE = MANIFESTS_DIR / "sessions_index.jsonl"  # append-only audit trail
SESSIONS_QUERY_INDEX_FILE = MANIFESTS_DIR / "sessions_index.json"  # upsert query index

HOST = "127.0.0.1"
PORT = 18080
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
