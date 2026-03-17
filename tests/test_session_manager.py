from __future__ import annotations

import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch

from app import session_manager as sm
from app.storage import read_json, write_json


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
                "csv_materialized": False,
                "csv_last_exported_at": None,
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


    def test_append_point_warns_and_recovers_on_duplicate_seq(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            sessions_dir = Path(tmpdir)
            session_id = "gps-duplicate-seq"
            today = datetime.utcnow().strftime("%Y-%m-%d")
            session_root = sessions_dir / today / session_id
            session_root.mkdir(parents=True, exist_ok=True)

            meta = {
                "session_id": session_id,
                "created_at": "2026-01-01T10:00:00Z",
                "closed_at": None,
                "status": "active",
                "session_date": today,
                "points_file_jsonl": str(session_root / "points.jsonl"),
                "points_file_csv": str(session_root / "points.csv"),
                "sensor_events_file_jsonl": str(session_root / "sensor_events.jsonl"),
                "sensor_events_file_csv": str(session_root / "sensor_events.csv"),
                "csv_materialized": False,
                "csv_last_exported_at": None,
                "events_file": str(session_root / "events.log"),
                "point_count": 1,
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
            (session_root / "points.jsonl").write_text(
                '{"session_id":"gps-duplicate-seq","point_seq":2}\n',
                encoding="utf-8",
            )

            with patch.object(sm, "SESSIONS_DIR", sessions_dir), self.assertLogs(sm.LOGGER, level="WARNING") as logs:
                updated_meta, point = sm.append_point(
                    session_id,
                    {
                        "latitude": 55.751244,
                        "longitude": 37.618423,
                    },
                )

            self.assertEqual(updated_meta["point_count"], 3)
            self.assertEqual(point["point_seq"], 3)
            self.assertTrue(any("point_seq anomaly" in msg for msg in logs.output))
            events_text = (session_root / "events.log").read_text(encoding="utf-8")
            self.assertIn("WARN point_seq anomaly", events_text)


class SessionManagerSensorValidationTests(unittest.TestCase):
    def _session_meta(self, session_id: str, session_root: Path, session_date: str) -> dict:
        return {
            "session_id": session_id,
            "created_at": "2026-01-01T10:00:00Z",
            "closed_at": None,
            "status": "active",
            "session_date": session_date,
            "points_file_jsonl": str(session_root / "points.jsonl"),
            "points_file_csv": str(session_root / "points.csv"),
            "sensor_events_file_jsonl": str(session_root / "sensor_events.jsonl"),
            "sensor_events_file_csv": str(session_root / "sensor_events.csv"),
            "csv_materialized": False,
            "csv_last_exported_at": None,
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

    def test_append_sensor_event_rejects_completely_empty_payload(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            sessions_dir = Path(tmpdir)
            session_id = "gps-empty-sensor"
            today = datetime.utcnow().strftime("%Y-%m-%d")
            session_root = sessions_dir / today / session_id
            session_root.mkdir(parents=True, exist_ok=True)
            write_json(session_root / "meta.json", self._session_meta(session_id, session_root, today))

            with patch.object(sm, "SESSIONS_DIR", sessions_dir):
                with self.assertRaisesRegex(ValueError, "sensor payload is empty"):
                    sm.append_sensor_event(
                        session_id,
                        {
                            "eventType": "orientation",
                        },
                    )


    def test_append_sensor_event_normalizes_legacy_meta_without_keyerror(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            sessions_dir = Path(tmpdir)
            session_id = "gps-legacy-sensor-meta"
            today = datetime.utcnow().strftime("%Y-%m-%d")
            session_root = sessions_dir / today / session_id
            session_root.mkdir(parents=True, exist_ok=True)

            legacy_meta = {
                "session_id": session_id,
                "created_at": "2026-01-01T10:00:00Z",
                "closed_at": None,
                "status": "active",
                "session_date": today,
                "points_file_jsonl": str(session_root / "points.jsonl"),
                "points_file_csv": str(session_root / "points.csv"),
                "events_file": str(session_root / "events.log"),
                "point_count": 0,
                "device": {"user_agent": "pytest", "platform_hint": "android"},
                "client": {"timezone": "UTC", "language": "ru-RU"},
                "sampling": {
                    "enable_high_accuracy": True,
                    "maximum_age_ms": 0,
                    "timeout_ms": 10000,
                    "sensor_throttle_ms": 200,
                },
            }
            write_json(session_root / "meta.json", legacy_meta)

            with patch.object(sm, "SESSIONS_DIR", sessions_dir):
                updated_meta, event = sm.append_sensor_event(
                    session_id,
                    {
                        "eventType": "orientation",
                        "alpha": 1.0,
                    },
                )

            self.assertEqual(updated_meta["sensor_event_count"], 1)
            self.assertEqual(event["event_seq"], 1)
            self.assertTrue(updated_meta["sensor_streams"]["orientation"])
            self.assertEqual(updated_meta["meta_schema_version"], 2)

            persisted = read_json(session_root / "meta.json")
            self.assertIn("sensor_events_file_jsonl", persisted)
            self.assertIn("sensor_events_file_csv", persisted)
            self.assertIn("sensor_streams", persisted)
            self.assertEqual(persisted["meta_schema_version"], 2)

    def test_append_sensor_event_accepts_battery_only_payload(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            sessions_dir = Path(tmpdir)
            session_id = "gps-battery-sensor"
            today = datetime.utcnow().strftime("%Y-%m-%d")
            session_root = sessions_dir / today / session_id
            session_root.mkdir(parents=True, exist_ok=True)
            write_json(session_root / "meta.json", self._session_meta(session_id, session_root, today))

            with patch.object(sm, "SESSIONS_DIR", sessions_dir):
                updated_meta, event = sm.append_sensor_event(
                    session_id,
                    {
                        "eventType": "battery_status",
                        "batteryLevel": 85,
                    },
                )

            self.assertEqual(updated_meta["sensor_event_count"], 1)
            self.assertEqual(event["event_type"], "battery_status")
            self.assertEqual(event["battery_level"], 85)


class SessionManagerCsvMaterializationTests(unittest.TestCase):
    def test_append_point_does_not_write_csv_in_hot_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            sessions_dir = Path(tmpdir)
            session_id = "gps-no-hotpath-csv"
            today = datetime.utcnow().strftime("%Y-%m-%d")
            session_root = sessions_dir / today / session_id
            session_root.mkdir(parents=True, exist_ok=True)

            meta = {
                "session_id": session_id,
                "created_at": "2026-01-01T10:00:00Z",
                "closed_at": None,
                "status": "active",
                "session_date": today,
                "points_file_jsonl": str(session_root / "points.jsonl"),
                "points_file_csv": str(session_root / "points.csv"),
                "sensor_events_file_jsonl": str(session_root / "sensor_events.jsonl"),
                "sensor_events_file_csv": str(session_root / "sensor_events.csv"),
                "csv_materialized": False,
                "csv_last_exported_at": None,
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
                sm.append_point(session_id, {"latitude": 55.751244, "longitude": 37.618423})

            self.assertTrue((session_root / "points.jsonl").exists())
            self.assertFalse((session_root / "points.csv").exists())
            events_text = (session_root / "events.log").read_text(encoding="utf-8") if (session_root / "events.log").exists() else ""
            self.assertNotIn("point_appended", events_text)

    def test_materialize_session_csv_rebuilds_csv_and_updates_meta(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            sessions_dir = Path(tmpdir)
            session_id = "gps-materialize-csv"
            today = datetime.utcnow().strftime("%Y-%m-%d")
            session_root = sessions_dir / today / session_id
            session_root.mkdir(parents=True, exist_ok=True)

            meta = {
                "session_id": session_id,
                "created_at": "2026-01-01T10:00:00Z",
                "closed_at": None,
                "status": "active",
                "session_date": today,
                "points_file_jsonl": str(session_root / "points.jsonl"),
                "points_file_csv": str(session_root / "points.csv"),
                "sensor_events_file_jsonl": str(session_root / "sensor_events.jsonl"),
                "sensor_events_file_csv": str(session_root / "sensor_events.csv"),
                "csv_materialized": False,
                "csv_last_exported_at": None,
                "events_file": str(session_root / "events.log"),
                "point_count": 1,
                "sensor_event_count": 1,
                "sensor_streams": {
                    "accelerometer": True,
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
            (session_root / "points.jsonl").write_text(
                '{"session_id":"gps-materialize-csv","point_seq":1,"latitude":55.1,"longitude":37.1}\n',
                encoding="utf-8",
            )
            (session_root / "sensor_events.jsonl").write_text(
                '{"session_id":"gps-materialize-csv","event_seq":1,"event_type":"accelerometer","value_x":0.1}\n',
                encoding="utf-8",
            )

            with patch.object(sm, "SESSIONS_DIR", sessions_dir):
                updated_meta = sm.materialize_session_csv(session_id)

            self.assertTrue((session_root / "points.csv").exists())
            self.assertTrue((session_root / "sensor_events.csv").exists())
            self.assertTrue(updated_meta["csv_materialized"])
            self.assertIsNotNone(updated_meta["csv_last_exported_at"])
            events_text = (session_root / "events.log").read_text(encoding="utf-8")
            self.assertIn("csv_materialized", events_text)


if __name__ == "__main__":
    unittest.main()
