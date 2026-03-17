from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch

from app import session_manager as sm
from app.storage import write_json


class SessionManagerFallbackTests(unittest.TestCase):
    def test_append_point_to_yesterday_session_uses_meta_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            sessions_dir = Path(tmpdir)
            session_id = "gps-legacy-session"
            yesterday = (datetime.utcnow() - timedelta(days=1)).strftime("%Y-%m-%d")
            session_root = sessions_dir / yesterday / session_id
            session_root.mkdir(parents=True, exist_ok=True)

            meta = {
                "session_id": session_id,
                "created_at": "2026-01-01T10:00:00Z",
                "closed_at": None,
                "status": "active",
                "session_date": yesterday,
                "points_file_jsonl": str(session_root / "points.jsonl"),
                "points_file_csv": str(session_root / "points.csv"),
                "sensor_events_file_jsonl": str(session_root / "sensor_events.jsonl"),
                "sensor_events_file_csv": str(session_root / "sensor_events.csv"),
                "events_file": str(session_root / "events.log"),
                "point_count": 0,
                "sensor_event_count": 0,
                "sensor_streams": {
                    "accelerometer": False,
                    "gyroscope": False,
                    "orientation": False,
                    "visibility_change": False,
                    "battery_status": False,
                },
                "device": {"user_agent": "pytest", "platform_hint": "android"},
                "client": {"timezone": "UTC", "language": "ru-RU"},
                "sampling": {
                    "enable_high_accuracy": True,
                    "maximum_age_ms": 0,
                    "timeout_ms": 10000,
                    "sensor_throttle_ms": 200,
                },
            }
            write_json(session_root / "meta.json", meta)

            with patch.object(sm, "SESSIONS_DIR", sessions_dir):
                updated_meta, point = sm.append_point(
                    session_id,
                    {
                        "latitude": 55.751244,
                        "longitude": 37.618423,
                    },
                )

            self.assertEqual(updated_meta["point_count"], 1)
            self.assertEqual(point["point_seq"], 1)
            self.assertTrue((session_root / "points.jsonl").exists())
            self.assertTrue((session_root / "meta.json").exists())


if __name__ == "__main__":
    unittest.main()
